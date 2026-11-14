# Randomization (zzalloc integration)
#
# Phase 1 of the randomization/blinding plan: a study-level
# randomization_config, an append-only randomization_history that
# lets zzalloc's batch allocate() be replayed one subject at a time,
# and treatment_arm_labels mapping zzalloc's raw integer arm codes to
# a human label. Deliberately no blinding enforcement yet (every
# caller sees the arm directly) and only the "simple" scheme is
# wired up -- see ~/.claude/plans/soft-orbiting-acorn.md for the full
# phased plan (blinding in phase 2, adaptive/covariate schemes in
# phase 3, emergency unblinding in phase 4).
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

  needs_cov <- scheme %in% c("stratified_block", "pocock_simon", "hu_hu",
                              "msb", "cara")
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
#'   `status`; or `NULL` if the study has no randomization config yet.
#' @export
get_randomization_config <- function(conn, study_id = NULL) {
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
#' @return `list(success = TRUE)` or `list(success = FALSE, error = ...)`.
#' @export
set_randomization_config <- function(conn, scheme, rng_seed,
                                      scheme_params = list(),
                                      covariate_fields = NULL,
                                      study_id = NULL,
                                      created_by = NULL,
                                      available_fields = NULL) {
  study_id <- study_id %||% .current_study_id(conn)
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
#'   "pocock_simon", "hu_hu", "msb", "cara")`.
#' @param study_id Defaults to `.current_study_id(conn)`.
#' @param randomized_by User id performing the randomization, for the
#'   audit trail.
#' @return `list(success = TRUE, arm_code = <int>)` or
#'   `list(success = FALSE, error = ...)`. Phase 1 has no blinding
#'   enforcement, so the arm code is always returned; translating it
#'   to a label (`treatment_arm_labels`) and deciding whether to show
#'   it to a given viewer is the caller's responsibility (and, from
#'   phase 2 on, `is_unblinded()`'s).
#' @export
randomize_next_subject <- function(conn, subject_id, covariates_row = NULL,
                                    study_id = NULL, randomized_by = NULL) {
  study_id <- study_id %||% .current_study_id(conn)

  config <- get_randomization_config(conn, study_id)
  if (is.null(config)) {
    return(list(success = FALSE, error = paste(
      "This study has no randomization_config; call",
      "set_randomization_config() first."
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
                                     "hu_hu", "msb", "cara")
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
#'   the subject has not been randomized.
#' @export
get_subject_arm <- function(conn, subject_id, study_id = NULL) {
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
