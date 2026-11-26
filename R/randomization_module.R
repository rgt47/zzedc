# Randomization (zzalloc integration)
#
# Phase 1 of the randomization/blinding plan: a study-level
# randomization_config, an append-only randomization_history that
# lets zzalloc's batch allocate() be replayed one subject at a time,
# and treatment_arm_labels mapping zzalloc's raw integer arm codes to
# a human label -- see ~/.claude/plans/soft-orbiting-acorn.md for the
# full phased plan.
#
# Phase 2 adds blinding enforcement: grant_unblinded_access() /
# revoke_unblinded_access() below manage the study_unblinding_grants
# table that is_unblinded()/require_unblinded() (R/authorization.R)
# read; callers (the Randomize button, any future report) are
# responsible for calling is_unblinded() before showing a subject's
# arm to a given viewer -- randomize_next_subject() and
# get_subject_arm() still always return the real arm_code, since the
# gate belongs at display time, not at the data layer (the same
# reasoning as keeping arm off of `subjects`: one place to get right
# instead of auditing every call site).
#
# Phase 3 wires up the covariate-adaptive schemes:
# "stratified_block", "pocock_simon", "hu_hu", "msb". Their RNG
# consumption is, like "simple"'s, exactly one draw per subject in
# arrival order regardless of branch taken (confirmed by reading
# zzalloc's own source, R/biased_coin.R's biased_draw() and the
# per-scheme loops), so the same replay-from-the-original-seed
# strategy randomize_next_subject() already used for "simple"
# reproduces every prior subject's arm for these schemes too, even
# though their *content* (not just count) of draws depends on the
# accumulated covariate history. Verified directly, not just by this
# reading: see the scratch reproducibility test run for this change.
#
# "cara" is deliberately NOT wired up: zzalloc::alloc_cara() is
# response-*adaptive*, not just covariate-adaptive. It requires a
# `response_fn` evaluated against each subject's outcome at the
# moment of randomization -- a function argument that cannot be
# serialized into scheme_params the way every other scheme's
# arguments can, and which assumes the outcome is already known at
# enrollment, false for this EDC's visit-based flow where outcomes
# are collected on later visits. validate_randomization_config()
# rejects it outright with that explanation; randomize_next_subject()
# also refuses it directly as defense in depth, since alloc_cara()
# additionally returns a list ($trt/$response), not the plain integer
# vector every other scheme returns, which this file's arm-extraction
# code does not handle.
#
# Phase 4 adds emergency_unblind_subject(): a one-time, reason-
# mandatory reveal of a single subject's arm, distinct from
# grant_unblinded_access()'s *standing* access -- it never writes to
# study_unblinding_grants. Its EMERGENCY_UNBLIND audit event is the
# one event type in this file whose `details` legitimately contains
# the revealed arm (every RANDOMIZATION event deliberately omits it),
# so the audit viewer must mask that event's details for a blinded
# viewer -- see R/audit_log_viewer_module.R.
#
# Treatment arm lives ONLY in randomization_history.arm, never on
# subjects: every existing subjects-based query (CRF rendering,
# exports, reports, the audit viewer) stays blind by construction,
# with nothing to audit at each of those call sites individually.

#' Study id for the (single) study in this database
#'
#' Every zzedc database holds exactly one study (confirmed
#' throughout this package: `launch_zzedc()` operates on one
#' already-open database for its whole process lifetime). The
#' randomization tables still carry an explicit `study_id` column
#' for forward compatibility, so this is the one place that id is
#' read from `study_info` -- falling back to a fixed sentinel
#' (`"_default_study_"`) when that table has no row at all, which it
#' does not for some already-provisioned demo studies whose metadata
#' lives only in `config.yml`. The fallback matters correctness-wise,
#' not just cosmetically: binding `NA`/`NULL` as a SQL parameter and
#' then comparing `study_id = ?` against it never matches (SQL NULL
#' is never equal to NULL), so every lookup in this file would
#' silently find nothing without it.
#'
#' @param conn A DBI connection or pool.
#' @return A single string, or `NA_character_` if `study_info` is
#'   empty.
#' @keywords internal
.current_study_id <- function(conn) {
  row <- DBI::dbGetQuery(conn, "SELECT study_id FROM study_info LIMIT 1")
  if (nrow(row) == 0 || is.na(row$study_id[1])) {
    "_default_study_"
  } else {
    as.character(row$study_id[1])
  }
}


#' Does This Database Have the Randomization Tables? (internal)
#'
#' `randomization_config`/`randomization_history`/`treatment_arm_labels`/
#' `study_unblinding_grants` only exist on a database provisioned by
#' this package's randomization feature (new studies get them
#' automatically via `create_core_tables()`; an existing study needs
#' [migrate_add_randomization_tables()]). The vast majority of
#' already-running zzedc studies -- including every one that is not
#' a randomized trial at all -- have never run that migration, and
#' every read function in this file is called unconditionally while
#' rendering the admin dashboard's Randomization tab (and, for
#' `is_unblinded()`, while rendering any CRF form with a
#' `randomization_group` field). Before this check existed, opening
#' that tab against such a database crashed the whole Shiny session
#' ("no such table: study_unblinding_grants" from
#' `list_unblinding_grants()`, reproduced directly against a
#' pre-existing non-trial deployment) rather than showing the
#' obviously-correct "nothing configured yet" state.
#'
#' @param conn A DBI connection or pool.
#' @return `TRUE`/`FALSE`. Never throws.
#' @keywords internal
.randomization_tables_exist <- function(conn) {
  isTRUE(tryCatch(DBI::dbExistsTable(conn, "randomization_config"),
                   error = function(e) FALSE))
}


#' Add the Randomization Tables to an Already-Provisioned Database
#'
#' For a study database created before this feature existed.
#' `create_wizard_database()`/`create_core_tables()` already create
#' these tables for any newly-provisioned study, so this is only
#' needed as a one-time migration for an existing one.
#'
#' @param conn A DBI connection or pool.
#' @param adapter Optional `DatabaseAdapter`; resolved from
#'   `get_db_adapter()` when `NULL` (see `.ensure_audit_tables()`'s
#'   own docs for why a caller that already holds the adapter that
#'   produced `conn` should pass it explicitly).
#' @return `invisible(TRUE)`.
#' @export
migrate_add_randomization_tables <- function(conn, adapter = NULL) {
  adapter <- adapter %||% get_db_adapter()
  dialect <- adapter$dialect()
  backend <- adapter$backend_name()
  .create_randomization_tables(conn, dialect, backend, adapter)
  # Defect 11 (zzedc-modernization-whitepaper-2026-11-13.md, Section
  # 2.2): a database old enough to need this migration predates
  # RANDOMIZATION/EMERGENCY_UNBLIND in .audit_event_types too, so
  # audit_log's CHECK constraint would reject both event types this
  # feature writes. This is the one place an existing study's
  # database is migrated for randomization at all, so it is also the
  # right (and only, until a caller invokes it elsewhere) place to
  # close that gap for one.
  migrate_audit_event_types(conn, adapter = adapter)
  invisible(TRUE)
}


#' Validate a Randomization Scheme Configuration
#'
#' @param scheme One of `zzalloc::allocation_schemes()`.
#' @param scheme_params A named list of arguments for that scheme's
#'   `alloc_*` function (e.g. `list(prob = 0.5)` for `"simple"`).
#' @param covariate_fields Character vector of CRF field names used
#'   as covariates, or `NULL`. Required (non-empty) for schemes that
#'   need covariates; must be `NULL`/empty otherwise.
#' @param available_fields Character vector of this study's actual
#'   CRF field names, to check `covariate_fields` against. May be
#'   `NULL` to skip that check (e.g. when fields aren't known yet).
#' @return `list(success = TRUE)` or `list(success = FALSE, error = ...)`.
#' @keywords internal
validate_randomization_config <- function(scheme, scheme_params = list(),
                                           covariate_fields = NULL,
                                           available_fields = NULL) {
  schemes <- zzalloc::allocation_schemes()
  if (!isTRUE(scheme %in% schemes)) {
    return(list(success = FALSE, error = paste0(
      "Unknown scheme '", scheme, "'. Must be one of: ",
      paste(schemes, collapse = ", ")
    )))
  }
  if (identical(scheme, "cara")) {
    return(list(success = FALSE, error = paste(
      "Scheme 'cara' is not supported by this EDC. It is",
      "response-adaptive, not just covariate-adaptive: zzalloc::alloc_cara()",
      "requires a `response_fn` evaluated against each subject's",
      "outcome at the moment of randomization, which (a) cannot be",
      "serialized into scheme_params the way the other schemes'",
      "arguments can, and (b) assumes an outcome is already known",
      "when a subject enrolls -- false for this EDC's visit-based",
      "flow, where outcomes are collected on later visits. Use",
      "'stratified_block', 'pocock_simon', 'hu_hu', or 'msb' for",
      "covariate-adaptive (not outcome-adaptive) allocation instead."
    )))
  }

  needs_cov <- scheme %in% c("stratified_block", "pocock_simon", "hu_hu",
                              "msb")
  if (needs_cov && length(covariate_fields) == 0) {
    return(list(success = FALSE, error = paste0(
      "Scheme '", scheme, "' requires `covariate_fields`."
    )))
  }
  if (!needs_cov && length(covariate_fields) > 0) {
    return(list(success = FALSE, error = paste0(
      "Scheme '", scheme, "' does not use covariates; ",
      "`covariate_fields` must be empty."
    )))
  }
  if (needs_cov && !is.null(available_fields)) {
    missing <- setdiff(covariate_fields, available_fields)
    if (length(missing) > 0) {
      return(list(success = FALSE, error = paste0(
        "covariate_fields not found on this study's CRF: ",
        paste(missing, collapse = ", ")
      )))
    }
  }

  alloc_fn <- tryCatch(
    utils::getFromNamespace(paste0("alloc_", scheme), "zzalloc"),
    error = function(e) NULL
  )
  if (!is.null(alloc_fn) && length(scheme_params) > 0) {
    bad <- setdiff(names(scheme_params), names(formals(alloc_fn)))
    if (length(bad) > 0) {
      return(list(success = FALSE, error = paste0(
        "scheme_params has arguments alloc_", scheme, "() does not take: ",
        paste(bad, collapse = ", ")
      )))
    }
  }

  list(success = TRUE)
}


#' Read a Study's Randomization Config
#'
#' @param conn A DBI connection or pool.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @return A list with `scheme`, `scheme_params` (unserialized from
#'   JSON), `covariate_fields` (character vector), `rng_seed`,
#'   `status`; or `NULL` if the study has no randomization config yet
#'   (including when this database predates the randomization
#'   feature entirely and has never run
#'   [migrate_add_randomization_tables()] -- indistinguishable, from
#'   a caller's perspective, from "not configured").
#' @export
get_randomization_config <- function(conn, study_id = NULL) {
  if (!.randomization_tables_exist(conn)) return(NULL)
  study_id <- study_id %||% .current_study_id(conn)
  row <- DBI::dbGetQuery(conn,
    "SELECT * FROM randomization_config WHERE study_id = ?",
    params = list(study_id)
  )
  if (nrow(row) == 0) return(NULL)
  list(
    study_id = row$study_id[1],
    scheme = row$scheme[1],
    scheme_params = if (!is.na(row$scheme_params[1])) {
      jsonlite::fromJSON(row$scheme_params[1])
    } else {
      list()
    },
    covariate_fields = if (!is.na(row$covariate_fields[1])) {
      jsonlite::fromJSON(row$covariate_fields[1])
    } else {
      character(0)
    },
    rng_seed = as.integer(row$rng_seed[1]),
    status = row$status[1]
  )
}


#' Set Up a Study's Randomization Scheme
#'
#' Writes (or replaces, while `status == "active"`, i.e. before any
#' subject has been randomized) a study's `randomization_config` row.
#' Refuses once the config is `"locked"` (set automatically by
#' [randomize_next_subject()] on its first call for the study) so a
#' scheme or seed cannot change mid-study and silently reinterpret
#' the history already recorded.
#'
#' @param conn A DBI connection or pool.
#' @param scheme,scheme_params,covariate_fields See
#'   [validate_randomization_config()].
#' @param rng_seed A single integer, fixed for the life of the study.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @param created_by User id performing this setup.
#' @param available_fields Passed to [validate_randomization_config()].
#' @param actor_role Optional: the configuring user's role, checked
#'   via [require_role()] against `c("Admin")` -- choosing the
#'   scheme/seed a study's allocation depends on is as sensitive as
#'   granting unblinded access. `NULL` skips the check.
#' @return `list(success = TRUE)` or `list(success = FALSE, error = ...)`.
#' @export
set_randomization_config <- function(conn, scheme, rng_seed,
                                      scheme_params = list(),
                                      covariate_fields = NULL,
                                      study_id = NULL,
                                      created_by = NULL,
                                      available_fields = NULL,
                                      actor_role = NULL) {
  if (!.randomization_tables_exist(conn)) {
    return(list(success = FALSE, error = paste(
      "This database has no randomization tables yet. Call",
      "migrate_add_randomization_tables() first."
    )))
  }
  study_id <- study_id %||% .current_study_id(conn)
  if (!is.null(actor_role)) {
    denied <- require_role(actor_role, c("Admin"), "configure the randomization scheme")
    if (!is.null(denied)) return(denied)
  }
  check <- validate_randomization_config(scheme, scheme_params,
                                          covariate_fields, available_fields)
  if (!isTRUE(check$success)) return(check)

  existing <- get_randomization_config(conn, study_id)
  if (!is.null(existing) && identical(existing$status, "locked")) {
    return(list(success = FALSE, error = paste(
      "Randomization is locked for this study (a subject has already",
      "been randomized) and cannot be reconfigured."
    )))
  }

  .with_db_transaction(conn, function(c) {
    DBI::dbExecute(c, "DELETE FROM randomization_config WHERE study_id = ?",
                    params = list(study_id))
    DBI::dbExecute(c, "
      INSERT INTO randomization_config
        (study_id, scheme, scheme_params, covariate_fields, rng_seed,
         status, created_by)
      VALUES (?, ?, ?, ?, ?, 'active', ?)
    ", params = list(
      study_id, scheme,
      jsonlite::toJSON(scheme_params, auto_unbox = TRUE),
      jsonlite::toJSON(covariate_fields %||% character(0), auto_unbox = TRUE),
      as.integer(rng_seed), created_by
    ))
  })
  list(success = TRUE)
}


#' Set a Study's Treatment Arm Labels
#'
#' @param conn A DBI connection or pool.
#' @param labels A named integer-keyed character vector, e.g.
#'   `c("1" = "Active", "2" = "Placebo")`.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @return `invisible(TRUE)`.
#' @export
set_treatment_arm_labels <- function(conn, labels, study_id = NULL) {
  if (!.randomization_tables_exist(conn)) {
    stop(paste(
      "This database has no randomization tables yet. Call",
      "migrate_add_randomization_tables() first."
    ), call. = FALSE)
  }
  study_id <- study_id %||% .current_study_id(conn)
  .with_db_transaction(conn, function(c) {
    DBI::dbExecute(c, "DELETE FROM treatment_arm_labels WHERE study_id = ?",
                    params = list(study_id))
    for (code in names(labels)) {
      DBI::dbExecute(c, "
        INSERT INTO treatment_arm_labels (study_id, arm_code, arm_label)
        VALUES (?, ?, ?)
      ", params = list(study_id, as.integer(code), labels[[code]]))
    }
  })
  invisible(TRUE)
}


#' Lock the Randomization History for a Transaction (internal)
#'
#' Mirrors `.lock_audit_chain()`'s per-backend shape (R/audit_append.R):
#' a transaction-scoped advisory lock on Postgres, a locking read on
#' MySQL, and SQLite/DuckDB's own serialization otherwise. Scoped to
#' one study so two subjects enrolling in different studies never
#' block each other.
#'
#' @param conn A DBI connection, already inside a transaction.
#' @param study_id The study being locked.
#' @return `invisible(TRUE)`.
#' @keywords internal
.lock_randomization_history <- function(conn, study_id) {
  backend <- .conn_backend(conn)
  if (backend == "postgresql") {
    # A single bigint advisory-lock key derived from study_id, distinct
    # from .lock_audit_chain()'s fixed key (726354901).
    key <- 726354902L + (sum(utf8ToInt(study_id)) %% 100000L)
    DBI::dbGetQuery(conn, sprintf("SELECT pg_advisory_xact_lock(%d)", key))
  } else if (backend == "mysql") {
    DBI::dbGetQuery(conn, "
      SELECT arrival_order FROM randomization_history
      WHERE study_id = ? ORDER BY arrival_order DESC LIMIT 1 FOR UPDATE
    ", params = list(study_id))
  }
  invisible(TRUE)
}


#' Randomize the Next Subject for a Study
#'
#' Replays `zzalloc::allocate()` over this study's history-so-far
#' plus the new subject, since zzalloc's allocation functions are
#' batch/vectorized (one call returns a full arrival-order sequence)
#' with no incremental "just the next one" entry point. Every call
#' re-seeds from this study's fixed `randomization_config$rng_seed`
#' and requests the full sequence up to and including the new
#' subject, taking only the last element -- R's PRNG is prefix-
#' stable (re-seeding and drawing `n` values always reproduces the
#' first `k` values of a previous `k`-length draw from the same
#' seed, for any `k <= n`), so this reproduces every prior subject's
#' already-recorded arm exactly, with no RNG state of its own to
#' persist or restore. (An earlier version of this function tried to
#' save/restore `.Random.seed` between calls instead -- that
#' resumes the stream mid-sequence and so draws *fresh* random
#' numbers for the already-decided positions on every call, silently
#' consuming extra draws and never reproducing the same sequence
#' twice. Always replaying from the original seed avoids that
#' entirely.)
#'
#' Locks the study's randomization config on its first call (see
#' [set_randomization_config()]): scheme/seed can no longer change
#' once a subject has been randomized.
#'
#' @param conn A DBI connection or pool.
#' @param subject_id The subject being randomized. Must not already
#'   have a `randomization_history` row for this study.
#' @param covariates_row A named list of covariate values, required
#'   (and used) only for schemes in `c("stratified_block",
#'   "pocock_simon", "hu_hu", "msb")`. `"cara"` is rejected by
#'   [validate_randomization_config()] and can never reach this
#'   function via [set_randomization_config()] -- see that
#'   function's docs for why.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @param randomized_by User id performing the randomization, for the
#'   audit trail.
#' @return `list(success = TRUE, arm_code = <int>)` or
#'   `list(success = FALSE, error = ...)`. The arm code is always
#'   returned; translating it to a label (`treatment_arm_labels`) and
#'   deciding whether to show it to a given viewer is the caller's
#'   responsibility (and `is_unblinded()`'s, from phase 2 on).
#' @export
randomize_next_subject <- function(conn, subject_id, covariates_row = NULL,
                                    study_id = NULL, randomized_by = NULL) {
  # Optional monitoring-plan gate (R/dsm_plan.R); returns at once,
  # without database access, unless zzedc.dsm_require_plan_in_effect
  # is on.
  gate <- .dsm_activity_gate(conn, "randomization")
  if (!is.null(gate)) return(gate)
  study_id <- study_id %||% .current_study_id(conn)

  config <- get_randomization_config(conn, study_id)
  if (is.null(config)) {
    return(list(success = FALSE, error = paste(
      "This study has no randomization_config; call",
      "set_randomization_config() first."
    )))
  }
  if (identical(config$scheme, "cara")) {
    # Defense in depth: set_randomization_config() already refuses to
    # write a 'cara' config (validate_randomization_config()), so this
    # should be unreachable -- but if it is ever reached (e.g. a config
    # row written directly, bypassing that gate), fail loudly instead
    # of mishandling alloc_cara()'s different return shape (a list with
    # $trt/$response, not a plain integer vector) as if it were a
    # normal scheme's result.
    return(list(success = FALSE, error = paste(
      "Scheme 'cara' is not supported for live randomization",
      "(see validate_randomization_config())."
    )))
  }

  existing <- DBI::dbGetQuery(conn, "
    SELECT 1 FROM randomization_history WHERE study_id = ? AND subject_id = ?
  ", params = list(study_id, subject_id))
  if (nrow(existing) > 0) {
    return(list(success = FALSE, error = paste0(
      "Subject '", subject_id, "' has already been randomized."
    )))
  }

  needs_cov <- config$scheme %in% c("stratified_block", "pocock_simon",
                                     "hu_hu", "msb")
  if (needs_cov) {
    missing <- setdiff(config$covariate_fields, names(covariates_row %||% list()))
    if (length(missing) > 0) {
      return(list(success = FALSE, error = paste0(
        "Missing covariate value(s) for this scheme: ",
        paste(missing, collapse = ", ")
      )))
    }
  }

  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv)) {
    get(".Random.seed", envir = .GlobalEnv)
  } else {
    NULL
  }
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)

  history <- DBI::dbGetQuery(conn, "
    SELECT arrival_order, subject_id, covariates_json
    FROM randomization_history WHERE study_id = ? ORDER BY arrival_order
  ", params = list(study_id))

  set.seed(config$rng_seed)
  n_new <- nrow(history) + 1L
  alloc_error <- NULL
  result <- tryCatch({
    if (needs_cov) {
      prior_cov <- if (nrow(history) > 0) {
        do.call(rbind, lapply(history$covariates_json, function(j) {
          as.data.frame(jsonlite::fromJSON(j), stringsAsFactors = FALSE)
        }))
      } else {
        NULL
      }
      new_cov <- as.data.frame(covariates_row, stringsAsFactors = FALSE)
      all_cov <- if (is.null(prior_cov)) new_cov else rbind(prior_cov, new_cov)
      do.call(zzalloc::allocate, c(
        list(scheme = config$scheme, covariates = all_cov), config$scheme_params
      ))
    } else {
      do.call(zzalloc::allocate, c(
        list(scheme = config$scheme, n = n_new), config$scheme_params
      ))
    }
  }, error = function(e) {
    alloc_error <<- conditionMessage(e)
    NULL
  })
  if (!is.null(alloc_error)) {
    return(list(success = FALSE, error = paste(
      "zzalloc::allocate() failed:", alloc_error
    )))
  }

  arm_code <- as.integer(utils::tail(result, 1))
  covariates_json <- jsonlite::toJSON(covariates_row %||% list(), auto_unbox = TRUE)
  # DBI parameter binding requires every element to have length 1;
  # a NULL randomized_by (no caller-supplied actor identity) has
  # length 0 and would otherwise abort the whole transaction with
  # "Parameter 6 does not have length 1" instead of recording the
  # randomization with an unknown actor.
  randomized_by <- randomized_by %||% NA_character_

  .with_db_transaction(conn, function(c) {
    .lock_randomization_history(c, study_id)
    DBI::dbExecute(c, "
      INSERT INTO randomization_history
        (study_id, arrival_order, subject_id, covariates_json, arm, randomized_by)
      VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(study_id, n_new, subject_id, covariates_json,
                      arm_code, randomized_by))
    if (identical(config$status, "active")) {
      DBI::dbExecute(c,
        "UPDATE randomization_config SET status = 'locked' WHERE study_id = ?",
        params = list(study_id))
    }
    # details deliberately omits the arm -- see R/randomization_module.R's
    # top-of-file note and the plan's Audit trail section: nothing
    # arm-revealing is ever written here, so there is nothing to mask
    # for a blinded viewer of the audit trail.
    .append_audit_record(
      c, event_type = "RANDOMIZATION", table_name = "randomization_history",
      record_id = subject_id,
      operation = paste0("Subject randomized (scheme: ", config$scheme,
                          ", arrival #", n_new, ")"),
      details = jsonlite::toJSON(
        list(scheme = config$scheme, arrival_order = n_new), auto_unbox = TRUE
      ),
      user_id = randomized_by
    )
  })

  list(success = TRUE, arm_code = arm_code)
}


#' Look Up a Subject's Randomized Arm
#'
#' @param conn A DBI connection or pool.
#' @param subject_id The subject.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @return A list with `arm_code` and `arm_label` (label `NA` if
#'   `treatment_arm_labels` has no row for that code), or `NULL` if
#'   the subject has not been randomized -- including when this
#'   database has no randomization tables at all. Called
#'   unconditionally from `inst/app/edc.R` for any CRF form with a
#'   `randomization_group` field, so it must never throw just
#'   because a given study was never migrated for randomization.
#' @export
get_subject_arm <- function(conn, subject_id, study_id = NULL) {
  if (!.randomization_tables_exist(conn)) return(NULL)
  study_id <- study_id %||% .current_study_id(conn)
  row <- DBI::dbGetQuery(conn, "
    SELECT h.arm, l.arm_label
    FROM randomization_history h
    LEFT JOIN treatment_arm_labels l
      ON l.study_id = h.study_id AND l.arm_code = h.arm
    WHERE h.study_id = ? AND h.subject_id = ?
  ", params = list(study_id, subject_id))
  if (nrow(row) == 0) return(NULL)
  list(arm_code = as.integer(row$arm[1]), arm_label = row$arm_label[1])
}


#' Grant a User Routine Unblinded Access to a Study
#'
#' Admin-only (mirroring `invalidate_signature()`'s Admin-only
#' precedent, R/electronic_signatures.R -- see the plan's "open
#' decisions" section for why this is the default rather than, say,
#' PI-grantable). Inserting a fresh grant row when a prior one
#' exists and was revoked is deliberate: it is a new, auditable grant
#' event, not a resurrection of the old one.
#'
#' @param conn A DBI connection or pool.
#' @param study_id The study to grant unblinded access to.
#' @param user_id The user being granted access.
#' @param granted_by User id performing this grant, for the audit
#'   trail.
#' @param actor_role Optional: the granting user's role, checked via
#'   [require_role()] against `c("Admin")`. `NULL` skips the check.
#' @return `list(success = TRUE)` or `list(success = FALSE, error = ...)`.
#' @export
grant_unblinded_access <- function(conn, study_id, user_id, granted_by,
                                    actor_role = NULL) {
  if (!.randomization_tables_exist(conn)) {
    return(list(success = FALSE, error = paste(
      "This database has no randomization tables yet. Call",
      "migrate_add_randomization_tables() first."
    )))
  }
  if (!is.null(actor_role)) {
    denied <- require_role(actor_role, c("Admin"), "grant unblinded access")
    if (!is.null(denied)) return(denied)
  }
  if (is.null(granted_by) || is.na(granted_by) || !nzchar(granted_by)) {
    return(list(success = FALSE, error = "granted_by is required."))
  }
  if (is_unblinded(conn, study_id, user_id)) {
    return(list(success = FALSE, error = paste0(
      "User '", user_id, "' already has unblinded access to this study."
    )))
  }

  .with_db_transaction(conn, function(c) {
    DBI::dbExecute(c, "
      INSERT INTO study_unblinding_grants (study_id, user_id, granted_by)
      VALUES (?, ?, ?)
    ", params = list(study_id, user_id, granted_by))
    .append_audit_record(
      c, event_type = "PERMISSION_CHANGE", table_name = "study_unblinding_grants",
      record_id = user_id,
      operation = paste0("Granted unblinded access for study '", study_id, "'"),
      details = jsonlite::toJSON(list(study_id = study_id, user_id = user_id),
                                  auto_unbox = TRUE),
      user_id = granted_by
    )
  })
  list(success = TRUE)
}


#' Revoke a User's Unblinded Access to a Study
#'
#' @param conn A DBI connection or pool.
#' @param study_id The study.
#' @param user_id The user whose access is being revoked.
#' @param revoked_by User id performing this revocation, for the
#'   audit trail.
#' @param actor_role Optional: the revoking user's role, checked via
#'   [require_role()] against `c("Admin")`. `NULL` skips the check.
#' @return `list(success = TRUE)` or `list(success = FALSE, error = ...)`.
#' @export
revoke_unblinded_access <- function(conn, study_id, user_id, revoked_by,
                                     actor_role = NULL) {
  if (!.randomization_tables_exist(conn)) {
    return(list(success = FALSE, error = paste(
      "This database has no randomization tables yet. Call",
      "migrate_add_randomization_tables() first."
    )))
  }
  if (!is.null(actor_role)) {
    denied <- require_role(actor_role, c("Admin"), "revoke unblinded access")
    if (!is.null(denied)) return(denied)
  }
  if (is.null(revoked_by) || is.na(revoked_by) || !nzchar(revoked_by)) {
    return(list(success = FALSE, error = "revoked_by is required."))
  }
  if (!is_unblinded(conn, study_id, user_id)) {
    return(list(success = FALSE, error = paste0(
      "User '", user_id, "' does not currently have unblinded access to this study."
    )))
  }

  .with_db_transaction(conn, function(c) {
    DBI::dbExecute(c, "
      UPDATE study_unblinding_grants
      SET revoked_date = CURRENT_TIMESTAMP, revoked_by = ?
      WHERE study_id = ? AND user_id = ? AND revoked_date IS NULL
    ", params = list(revoked_by, study_id, user_id))
    .append_audit_record(
      c, event_type = "PERMISSION_CHANGE", table_name = "study_unblinding_grants",
      record_id = user_id,
      operation = paste0("Revoked unblinded access for study '", study_id, "'"),
      details = jsonlite::toJSON(list(study_id = study_id, user_id = user_id),
                                  auto_unbox = TRUE),
      user_id = revoked_by
    )
  })
  list(success = TRUE)
}


#' List Current Unblinding Grants for a Study
#'
#' @param conn A DBI connection or pool.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @return A data frame with `user_id`, `granted_date`, `granted_by`
#'   for every currently-live (not revoked) grant. Zero rows, with
#'   the right columns, when this database has no randomization
#'   tables yet (see [get_randomization_config()]'s docs).
#' @export
list_unblinding_grants <- function(conn, study_id = NULL) {
  if (!.randomization_tables_exist(conn)) {
    return(data.frame(user_id = character(0), granted_date = character(0),
                       granted_by = character(0), stringsAsFactors = FALSE))
  }
  study_id <- study_id %||% .current_study_id(conn)
  DBI::dbGetQuery(conn, "
    SELECT user_id, granted_date, granted_by
    FROM study_unblinding_grants
    WHERE study_id = ? AND revoked_date IS NULL
    ORDER BY granted_date
  ", params = list(study_id))
}


#' Balance Diagnostics for a Study's Randomization History
#'
#' Wraps `zzalloc::allocation_imbalance()` over this study's realized
#' allocation, reconstructing the same covariates data frame
#' [randomize_next_subject()] builds for a covariate-adaptive scheme.
#' Reveals the arm, so a caller showing this in a UI is responsible
#' for gating it behind [is_unblinded()] the same way as
#' [get_subject_arm()] -- it is not gated here, for the same
#' data-layer-vs-display-time reasoning documented at the top of
#' this file.
#'
#' `zzalloc::weighted_imbalance()` is not wrapped here: it additionally
#' requires a `beta` (per-covariate outcome-association weight), which
#' is study-specific statistical knowledge this package has no source
#' for, not something derivable from `randomization_history` alone.
#'
#' @param conn A DBI connection or pool.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @return `zzalloc::allocation_imbalance()`'s return value (a list
#'   with `overall`, `marginal`, `max_marginal`, `stratum`), or
#'   `NULL` if the study has no randomization history yet.
#' @export
get_study_imbalance <- function(conn, study_id = NULL) {
  if (!.randomization_tables_exist(conn)) return(NULL)
  study_id <- study_id %||% .current_study_id(conn)
  config <- get_randomization_config(conn, study_id)
  history <- DBI::dbGetQuery(conn, "
    SELECT arrival_order, arm, covariates_json
    FROM randomization_history WHERE study_id = ? ORDER BY arrival_order
  ", params = list(study_id))
  if (nrow(history) == 0) return(NULL)

  trt <- as.integer(history$arm)
  has_cov <- !is.null(config) && length(config$covariate_fields) > 0
  cov_df <- if (has_cov) {
    do.call(rbind, lapply(history$covariates_json, function(j) {
      as.data.frame(jsonlite::fromJSON(j), stringsAsFactors = FALSE)
    }))
  } else {
    NULL
  }
  zzalloc::allocation_imbalance(trt, cov_df)
}


#' Emergency-Unblind a Single Subject
#'
#' A one-time, reason-mandatory reveal of one subject's treatment
#' arm -- distinct from [grant_unblinded_access()], which gives
#' *standing* access to every subject in a study. This never writes
#' to `study_unblinding_grants`: a clinician who needs to know one
#' subject's arm right now (e.g. a serious adverse event) does not
#' thereby become unblinded for the rest of the study, and the next
#' call to [is_unblinded()] for that user is unaffected.
#'
#' The reveal is recorded as its own `EMERGENCY_UNBLIND` audit event
#' whose `details` *legitimately* contains the revealed arm (unlike
#' `RANDOMIZATION` events, which never do) -- a UI showing the audit
#' trail to a viewer who is not unblinded must mask this event's
#' `details`, the same way `get_subject_arm()`'s result must be
#' gated at display time rather than withheld here.
#'
#' @param conn A DBI connection or pool.
#' @param subject_id The subject to unblind. Must already be
#'   randomized.
#' @param requested_by User id performing this unblind, for the
#'   audit trail. Required.
#' @param reason Free-text justification, at least 10 characters
#'   (the same minimum [zzedc::invalidate_signature()] requires for
#'   its own most-sensitive action). Required.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @param actor_role Optional: the requesting user's role, checked
#'   via [require_role()] against `c("Admin", "PI")`. `NULL` skips
#'   the check.
#' @return `list(success = TRUE, arm_code = <int>, arm_label = <chr>)`
#'   for one-time display, or `list(success = FALSE, error = ...)`.
#' @export
emergency_unblind_subject <- function(conn, subject_id, requested_by, reason,
                                       study_id = NULL, actor_role = NULL) {
  study_id <- study_id %||% .current_study_id(conn)
  if (!is.null(actor_role)) {
    denied <- require_role(actor_role, c("Admin", "PI"), "perform an emergency unblind")
    if (!is.null(denied)) return(denied)
  }
  if (is.null(requested_by) || is.na(requested_by) || !nzchar(requested_by)) {
    return(list(success = FALSE, error = "requested_by is required."))
  }
  if (is.null(reason) || nchar(trimws(reason %||% "")) < 10) {
    return(list(success = FALSE, error = paste(
      "A reason of at least 10 characters is required for an",
      "emergency unblind."
    )))
  }

  arm <- get_subject_arm(conn, subject_id, study_id)
  if (is.null(arm)) {
    return(list(success = FALSE, error = paste0(
      "Subject '", subject_id, "' has not been randomized."
    )))
  }

  .with_db_transaction(conn, function(c) {
    .append_audit_record(
      c, event_type = "EMERGENCY_UNBLIND", table_name = "randomization_history",
      record_id = subject_id,
      operation = paste0("Emergency unblind for subject '", subject_id, "'"),
      details = jsonlite::toJSON(list(
        study_id = study_id, subject_id = subject_id,
        arm_code = arm$arm_code, arm_label = arm$arm_label %||% NA_character_,
        reason = reason
      ), auto_unbox = TRUE),
      user_id = requested_by
    )
  })

  list(success = TRUE, arm_code = arm$arm_code, arm_label = arm$arm_label)
}
