#' Data and Safety Monitoring Plans
#'
#' Storage, validation, and lifecycle of a study's data and safety
#' monitoring plan, for the draft NIH policy update NOT-OD-27-006
#' (design: `docs/nih-dsm-monitoring-plan-design-2026-11-23.md`,
#' Section 6). A plan version is an immutable row in
#' `dsm_plan_versions`, so an electronic signature on it stays valid;
#' its lifecycle is the append-only `dsm_plan_events`, from which the
#' current status is derived. zzedc records what users report about
#' the funding institute's (ICO's) actions and never asserts them.
#'
#' @name dsm_plan
#' @keywords internal
NULL


# =============================================================================
# Constants
# =============================================================================

.dsm_spec_version <- 1L

.dsm_default_risk_categories <- c(
  "participant_safety", "data_quality", "complexity_processes",
  "financial_stewardship", "other"
)

.dsm_stored_statuses <- c(
  "draft", "internal_review", "signed", "submitted", "approved",
  "revise", "in_effect", "superseded"
)

# Allowed stored transitions. submitted -> in_effect is the deemed-
# approval path and carries its own checks in dsm_transition().
.dsm_transitions <- list(
  draft = c("internal_review"),
  internal_review = c("draft", "signed"),
  # signed -> in_effect only for an amendment of class
  # report_at_interval (checked in dsm_transition()).
  signed = c("submitted", "in_effect"),
  submitted = c("in_effect"),
  approved = c("in_effect"),
  revise = character(0),
  in_effect = character(0),
  superseded = character(0)
)


#' Risk Categories in Force (internal)
#'
#' The five categories of the draft notice, overridable with the
#' option `zzedc.dsm_risk_categories` should the final policy change
#' them.
#'
#' @return Character vector.
#' @keywords internal
.dsm_risk_categories <- function() {
  getOption("zzedc.dsm_risk_categories", .dsm_default_risk_categories)
}


# =============================================================================
# Tables
# =============================================================================

#' Do This Database's Monitoring-Plan Tables Exist? (internal)
#'
#' @param conn A DBI connection or pool.
#' @return `TRUE`/`FALSE`. Never throws.
#' @keywords internal
.dsm_tables_exist <- function(conn) {
  isTRUE(tryCatch(DBI::dbExistsTable(conn, "dsm_plan_versions"),
                  error = function(e) FALSE))
}


#' Add the Monitoring-Plan Tables to a Study Database
#'
#' Idempotent. Creates `dsm_plan_versions` (one immutable row per plan
#' version) and `dsm_plan_events` (the append-only lifecycle), and
#' brings the audit trail's event-type constraint up to date with
#' [migrate_audit_event_types()], as
#' [migrate_add_randomization_tables()] does.
#'
#' Neither table has an index on a column that is later updated, and
#' neither is ever updated, so DuckDB's foreign-key limitation on
#' updates of indexed columns does not arise.
#'
#' @param conn A DBI connection or pool.
#' @param adapter Optional `DatabaseAdapter`; resolved from
#'   `get_db_adapter()` when `NULL`.
#' @return `invisible(TRUE)`.
#' @export
migrate_add_dsm_tables <- function(conn, adapter = NULL) {
  adapter <- adapter %||% get_db_adapter()
  backend <- adapter$backend_name()
  if (backend == "clickhouse") {
    stop("Monitoring plans are not supported on ClickHouse, which is ",
         "not supported as a system of record.", call. = FALSE)
  }
  dialect <- adapter$dialect()
  text_type <- dialect$text_type
  int_type <- dialect$integer_type
  ts_type <- dialect$timestamp_type

  adapter$prepare_auto_increment(conn, "dsm_plan_versions", "plan_id")
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS dsm_plan_versions (
      plan_id %s,
      study_id %s NOT NULL,
      version %s NOT NULL,
      spec_version %s NOT NULL,
      spec_json %s NOT NULL,
      spec_hash %s NOT NULL,
      risk_tier %s NOT NULL,
      funding_ico %s,
      independent_monitor %s NOT NULL,
      interim_efficacy %s NOT NULL,
      interim_futility %s NOT NULL,
      source_hash %s,
      created_by %s NOT NULL,
      created_at %s NOT NULL,
      UNIQUE (study_id, version)
    )
  ", adapter$auto_increment_column("dsm_plan_versions", "plan_id"),
     text_type, int_type, int_type, text_type, text_type, text_type,
     text_type, text_type, int_type, int_type, text_type, text_type,
     ts_type))

  adapter$prepare_auto_increment(conn, "dsm_plan_events", "event_id")
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS dsm_plan_events (
      event_id %s,
      plan_id %s NOT NULL REFERENCES dsm_plan_versions(plan_id),
      from_status %s,
      to_status %s NOT NULL,
      event_at %s NOT NULL,
      effective_date %s,
      user_id %s NOT NULL,
      note %s,
      ico_decision %s,
      signature_code %s,
      document_ref %s
    )
  ", adapter$auto_increment_column("dsm_plan_events", "event_id"),
     int_type, text_type, text_type, ts_type, text_type, text_type,
     text_type, text_type, text_type, text_type))

  DBI::dbExecute(conn, "
    CREATE INDEX IF NOT EXISTS idx_dsm_events_plan
    ON dsm_plan_events(plan_id)
  ")

  # Append-only, like the events: one row per amended version.
  adapter$prepare_auto_increment(conn, "dsm_amendments", "amendment_id")
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS dsm_amendments (
      amendment_id %s,
      plan_id %s NOT NULL UNIQUE REFERENCES dsm_plan_versions(plan_id),
      from_plan_id %s NOT NULL REFERENCES dsm_plan_versions(plan_id),
      amendment_class %s NOT NULL,
      summary %s NOT NULL,
      rationale %s NOT NULL,
      created_by %s NOT NULL,
      created_at %s NOT NULL
    )
  ", adapter$auto_increment_column("dsm_amendments", "amendment_id"),
     int_type, int_type, text_type, text_type, text_type, text_type,
     ts_type))

  migrate_audit_event_types(conn, adapter = adapter)
  invisible(TRUE)
}


#' Lock a Study's Monitoring Plans for a Transaction (internal)
#'
#' Serializes lifecycle writes for one study, so two versions cannot
#' be put into effect at once. Same shape as
#' `.lock_randomization_history()`: an advisory lock on PostgreSQL, a
#' locking read on MySQL, the engine's single writer otherwise.
#'
#' @param conn A DBI connection, inside a transaction.
#' @param study_id The study.
#' @return `invisible(TRUE)`.
#' @keywords internal
.lock_dsm_study <- function(conn, study_id) {
  backend <- .conn_backend(conn)
  if (backend == "postgresql") {
    key <- 726454902L + (sum(utf8ToInt(study_id)) %% 100000L)
    DBI::dbGetQuery(conn, sprintf("SELECT pg_advisory_xact_lock(%d)", key))
  } else if (backend == "mysql") {
    DBI::dbGetQuery(conn, "
      SELECT plan_id FROM dsm_plan_versions
      WHERE study_id = ? ORDER BY plan_id FOR UPDATE
    ", params = list(study_id))
  }
  invisible(TRUE)
}


# =============================================================================
# Spec: canonical form, validation, import, export
# =============================================================================

#' Sort a Spec's Named Lists Recursively (internal)
#'
#' @param x A list or atomic value.
#' @return `x` with every named list's elements ordered by name.
#' @keywords internal
.dsm_sort_names <- function(x) {
  if (!is.list(x)) return(x)
  x <- lapply(x, .dsm_sort_names)
  nms <- names(x)
  if (!is.null(nms) && all(nzchar(nms))) x[order(nms)] else x
}


#' Canonical JSON for a Spec (internal)
#'
#' Names sorted recursively and numbers written in full (`digits =
#' NA`), so the same content always gives the same text and hash,
#' including after export and re-import.
#'
#' @param spec A spec list.
#' @return A single JSON string.
#' @keywords internal
.dsm_canonical_json <- function(spec) {
  as.character(jsonlite::toJSON(.dsm_sort_names(spec), auto_unbox = TRUE,
                                digits = NA, null = "null",
                                na = "null"))
}


#' Read a Spec From a File or a List (internal)
#'
#' @param spec A list, or a path to a `.json`, `.yaml`, or `.yml` file.
#' @return A list.
#' @keywords internal
.dsm_read_spec <- function(spec) {
  if (is.list(spec)) return(spec)
  if (!is.character(spec) || length(spec) != 1 || !file.exists(spec)) {
    stop("spec must be a list or the path of an existing file", call. = FALSE)
  }
  ext <- tolower(tools::file_ext(spec))
  if (ext %in% c("yaml", "yml")) {
    if (!requireNamespace("yaml", quietly = TRUE)) {
      stop("Reading a YAML spec needs the 'yaml' package", call. = FALSE)
    }
    return(yaml::read_yaml(spec))
  }
  jsonlite::fromJSON(spec, simplifyVector = FALSE)
}


#' Validate a Monitoring-Plan Spec
#'
#' Checks a spec against the rules of the design document, Section
#' 6.3, and reports every problem, not only the first. Each problem
#' carries a path (for example `risks[2].likelihood`), which the
#' workbook importer translates to a sheet, row, and column.
#'
#' Not yet checked (Phase 2): that indicator names exist in the
#' indicator registry, the ordering of thresholds by an indicator's
#' direction, and that referenced forms and fields exist in the
#' study's data dictionary.
#'
#' @param spec A spec list, or a path to a JSON or YAML file.
#' @return `list(success = TRUE, problems = <empty data frame>)`, or
#'   `list(success = FALSE, error = <summary>, problems = data.frame(
#'   path, message))`.
#' @export
dsm_validate_spec <- function(spec) {
  spec <- tryCatch(.dsm_read_spec(spec), error = function(e) e)
  if (inherits(spec, "error")) {
    p <- data.frame(path = "", message = conditionMessage(spec))
    return(list(success = FALSE, error = p$message, problems = p))
  }

  probs <- list()
  add <- function(path, message) {
    probs[[length(probs) + 1]] <<- data.frame(path = path, message = message)
  }
  is_str <- function(x) is.character(x) && length(x) == 1 && !is.na(x) &&
    nzchar(trimws(x))
  is_flag <- function(x) is.logical(x) && length(x) == 1 && !is.na(x)
  is_count <- function(x) is.numeric(x) && length(x) == 1 && !is.na(x) &&
    x == round(x)
  levels3 <- c("low", "medium", "high")

  if (!identical(as.integer(spec$dsm_spec_version %||% NA), .dsm_spec_version)) {
    add("dsm_spec_version", paste("must be", .dsm_spec_version))
  }
  if (!is_str(spec$study_id)) add("study_id", "is required")
  if (!isTRUE(spec$risk_tier %in% c("minimal", "moderate", "trial"))) {
    add("risk_tier", "must be one of minimal, moderate, trial")
  }
  if (!is.null(spec$funding_ico) && !is_str(spec$funding_ico)) {
    add("funding_ico", "must be a single name, such as NIA")
  }

  interim <- spec$interim_analyses %||% list()
  for (k in c("efficacy", "futility")) {
    if (!is.null(interim[[k]]) && !is_flag(interim[[k]])) {
      add(paste0("interim_analyses.", k), "must be true or false")
    }
  }
  monitor <- spec$independent_monitor$type %||% "none"
  if (!isTRUE(monitor %in% c("none", "individual", "committee"))) {
    add("independent_monitor.type",
        "must be one of none, individual, committee")
  } else if (monitor == "none" &&
             (isTRUE(interim$efficacy) || isTRUE(interim$futility))) {
    add("independent_monitor.type", paste(
      "planned interim efficacy or futility analyses need an independent",
      "monitor or committee (design Section 7.8)"))
  }

  freq <- spec$review$report_frequency_months
  if (is.null(freq) || !is_count(freq) || freq < 1 || freq > 12) {
    add("review.report_frequency_months", paste(
      "must be a whole number of months from 1 to 12 (routine reports",
      "are reviewed at least annually)"))
  }

  risks <- spec$risks
  if (!is.list(risks) || length(risks) == 0) {
    add("risks", "at least one risk is required")
    risks <- list()
  }
  categories <- .dsm_risk_categories()
  ids <- character(0)
  indicator_names <- character(0)
  for (i in seq_along(risks)) {
    r <- risks[[i]]
    at <- function(f) sprintf("risks[%d].%s", i, f)
    if (!is_str(r$id)) {
      add(at("id"), "is required")
    } else if (r$id %in% ids) {
      add(at("id"), paste0("duplicates another risk id ('", r$id, "')"))
    } else {
      ids <- c(ids, r$id)
    }
    if (!isTRUE(r$category %in% categories)) {
      add(at("category"),
          paste("must be one of", paste(categories, collapse = ", ")))
    }
    if (!is_str(r$description)) add(at("description"), "is required")
    if (!isTRUE(r$likelihood %in% levels3)) {
      add(at("likelihood"), "must be low, medium, or high")
    }
    if (!isTRUE(r$impact %in% levels3)) {
      add(at("impact"), "must be low, medium, or high")
    }
    if (!is_flag(r$critical)) add(at("critical"), "must be true or false")

    inds <- r$indicators %||% list()
    monitored_by <- r$monitored_by %||%
      (if (length(inds) > 0) "indicator" else "narrative")
    if (!isTRUE(monitored_by %in% c("indicator", "narrative", "both"))) {
      add(at("monitored_by"), "must be indicator, narrative, or both")
    }
    if (isTRUE(r$critical)) {
      if (monitored_by %in% c("indicator", "both") && length(inds) == 0) {
        add(at("indicators"), paste(
          "a critical risk monitored by indicator needs at least one",
          "indicator"))
      }
      if (monitored_by %in% c("narrative", "both") && !is_str(r$mitigation)) {
        add(at("mitigation"), paste(
          "a critical risk monitored by narrative needs a mitigation"))
      }
    }

    for (j in seq_along(inds)) {
      d <- inds[[j]]
      ai <- function(f) sprintf("risks[%d].indicators[%d].%s", i, j, f)
      if (!is_str(d$indicator)) {
        add(ai("indicator"), "is required")
      } else {
        indicator_names <- c(indicator_names, d$indicator)
      }
      for (lvl in c("warning", "alert")) {
        v <- d[[lvl]]
        if (!is.null(v) && !(is.numeric(v) && length(v) == 1 &&
                             !is.na(v) && v >= 0)) {
          add(ai(lvl), "must be a non-negative number")
        }
      }
      if (is.null(d$warning) && is.null(d$alert)) {
        add(ai("alert"), "an indicator needs a warning or an alert threshold")
      }
      if (!is.null(d$grain) && !isTRUE(d$grain %in% c("study", "site", "arm"))) {
        add(ai("grain"), "must be study, site, or arm")
      }
      for (f in c("window_days", "min_denominator")) {
        v <- d[[f]]
        if (!is.null(v) && !(is_count(v) && v >= 0)) {
          add(ai(f), "must be a non-negative whole number")
        }
      }
    }
  }

  rules <- spec$stopping_rules %||% list()
  for (k in seq_along(rules)) {
    s <- rules[[k]]
    if (!is_str(s$description)) {
      add(sprintf("stopping_rules[%d].description", k), "is required")
    }
    if (!is.null(s$indicator) && !isTRUE(s$indicator %in% indicator_names)) {
      add(sprintf("stopping_rules[%d].indicator", k),
          "must name an indicator used by one of the risks")
    }
  }

  problems <- if (length(probs) == 0) {
    data.frame(path = character(0), message = character(0))
  } else {
    do.call(rbind, probs)
  }
  if (nrow(problems) == 0) {
    list(success = TRUE, problems = problems)
  } else {
    list(success = FALSE,
         error = paste0(nrow(problems), " problem(s): ",
                        paste(problems$path, problems$message, sep = " ",
                              collapse = "; ")),
         problems = problems)
  }
}


#' Import a Monitoring-Plan Spec as a New Draft Version
#'
#' Validates the spec and, if valid, stores it as the next version of
#' the study's plan, in status `draft`. Never changes an existing
#' version. The version row, its first lifecycle event, and their
#' audit records are written in one transaction.
#'
#' @param conn A DBI connection or pool.
#' @param spec A spec list, or a path to a JSON or YAML file.
#' @param user_id The user importing the plan.
#' @param source_hash Optional SHA-256 of the source document (for
#'   example the workbook the spec was read from).
#' @return `list(success = TRUE, plan_id, version, spec_hash)`, or
#'   `list(success = FALSE, error, problems)`.
#' @export
dsm_import_spec <- function(conn, spec, user_id, source_hash = NULL) {
  spec <- tryCatch(.dsm_read_spec(spec), error = function(e) e)
  if (inherits(spec, "error")) {
    return(list(success = FALSE, error = conditionMessage(spec)))
  }
  v <- dsm_validate_spec(spec)
  if (!isTRUE(v$success)) return(v)

  tryCatch({
    migrate_add_dsm_tables(conn)
    json <- .dsm_canonical_json(spec)
    spec_hash <- digest::digest(json, algo = "sha256", serialize = FALSE)
    now <- format(Sys.time(), tz = "UTC", "%Y-%m-%d %H:%M:%S")
    interim <- spec$interim_analyses %||% list()

    out <- .with_db_transaction(conn, function(c) {
      .lock_dsm_study(c, spec$study_id)
      last <- DBI::dbGetQuery(c, "
        SELECT MAX(version) AS v FROM dsm_plan_versions WHERE study_id = ?
      ", params = list(spec$study_id))$v[1]
      version <- if (is.na(last)) 1L else as.integer(last) + 1L

      plan_id <- DBI::dbGetQuery(c, "
        INSERT INTO dsm_plan_versions (
          study_id, version, spec_version, spec_json, spec_hash, risk_tier,
          funding_ico, independent_monitor, interim_efficacy,
          interim_futility, source_hash, created_by, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        RETURNING plan_id AS id
      ", params = list(
        spec$study_id, version, .dsm_spec_version, json, spec_hash,
        spec$risk_tier, spec$funding_ico %||% NA_character_,
        spec$independent_monitor$type %||% "none",
        as.integer(isTRUE(interim$efficacy)),
        as.integer(isTRUE(interim$futility)),
        source_hash %||% NA_character_, user_id, now
      ))$id[1]

      .append_audit_record(
        c, event_type = "INSERT", table_name = "dsm_plan_versions",
        record_id = plan_id,
        operation = sprintf("Monitoring plan version %d imported", version),
        details = .dsm_json(list(study_id = spec$study_id, version = version,
                                 spec_hash = spec_hash,
                                 source_hash = source_hash)),
        user_id = user_id
      )
      .dsm_insert_event(c, plan_id, from = NA_character_, to = "draft",
                        user_id = user_id, at = now)
      list(plan_id = plan_id, version = version)
    })

    list(success = TRUE, plan_id = out$plan_id, version = out$version,
         spec_hash = spec_hash)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}


#' Export a Monitoring-Plan Version's Spec
#'
#' @param conn A DBI connection or pool.
#' @param plan_id The plan version.
#' @param path Optional file to write; `.json` (canonical form) or
#'   `.yaml`/`.yml` (needs the `yaml` package).
#' @return `list(success = TRUE, spec, spec_hash)` or
#'   `list(success = FALSE, error)`.
#' @export
dsm_export_spec <- function(conn, plan_id, path = NULL) {
  tryCatch({
    if (!.dsm_tables_exist(conn)) stop("This database has no monitoring plans")
    row <- DBI::dbGetQuery(conn, "
      SELECT spec_json, spec_hash FROM dsm_plan_versions WHERE plan_id = ?
    ", params = list(plan_id))
    if (nrow(row) == 0) stop("Plan version ", plan_id, " not found")
    spec <- jsonlite::fromJSON(row$spec_json[1], simplifyVector = FALSE)
    if (!is.null(path)) {
      ext <- tolower(tools::file_ext(path))
      if (ext %in% c("yaml", "yml")) {
        if (!requireNamespace("yaml", quietly = TRUE)) {
          stop("Writing YAML needs the 'yaml' package")
        }
        yaml::write_yaml(spec, path)
      } else {
        writeLines(row$spec_json[1], path)
      }
    }
    list(success = TRUE, spec = spec, spec_hash = row$spec_hash[1])
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}


# =============================================================================
# Lifecycle
# =============================================================================

#' JSON for Audit Details (internal)
#' @param x Named list.
#' @return JSON string.
#' @keywords internal
.dsm_json <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null",
                                na = "null"))
}


#' Append One Lifecycle Event and Its Audit Record (internal)
#'
#' @param conn A DBI connection, inside a transaction.
#' @param plan_id,from,to,user_id,at,effective_date,note,ico_decision,signature_code,document_ref
#'   Event content.
#' @return The new `event_id`.
#' @keywords internal
.dsm_insert_event <- function(conn, plan_id, from, to, user_id, at,
                              effective_date = NULL, note = NULL,
                              ico_decision = NULL, signature_code = NULL,
                              document_ref = NULL) {
  na_chr <- function(x) if (is.null(x)) NA_character_ else as.character(x)
  event_id <- DBI::dbGetQuery(conn, "
    INSERT INTO dsm_plan_events (
      plan_id, from_status, to_status, event_at, effective_date, user_id,
      note, ico_decision, signature_code, document_ref
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    RETURNING event_id AS id
  ", params = list(plan_id, na_chr(from), to, at, na_chr(effective_date),
                   user_id, na_chr(note), na_chr(ico_decision),
                   na_chr(signature_code), na_chr(document_ref)))$id[1]

  .append_audit_record(
    conn, event_type = "DSM_PLAN_STATUS", table_name = "dsm_plan_events",
    record_id = event_id,
    operation = sprintf("Monitoring plan %s: %s -> %s", plan_id,
                        if (is.na(na_chr(from))) "(new)" else from, to),
    details = .dsm_json(list(plan_id = plan_id, from_status = from,
                             to_status = to,
                             effective_date = effective_date,
                             ico_decision = ico_decision,
                             signature_code = signature_code,
                             document_ref = document_ref)),
    user_id = user_id
  )
  event_id
}


#' Day Count for Deemed Approval (internal)
#'
#' @param from Date the plan was received (as entered by the user).
#' @param as_of Date of evaluation.
#' @return Days counted under the configured rule.
#' @keywords internal
.dsm_days_elapsed <- function(from, as_of) {
  type <- getOption("zzedc.dsm_deemed_approval_day_type", "calendar")
  from <- as.Date(from)
  as_of <- as.Date(as_of)
  if (as_of <= from) return(0L)
  if (identical(type, "business")) {
    days <- seq(from + 1, as_of, by = "day")
    as.integer(sum(!format(days, "%u") %in% c("6", "7")))
  } else {
    as.integer(as_of - from)
  }
}


#' Status of a Monitoring-Plan Version
#'
#' Derived from the version's lifecycle events. A `submitted` version
#' with no recorded ICO decision becomes eligible for deemed approval
#' once the configured number of days (option
#' `zzedc.dsm_deemed_approval_days`, default 30; day type option
#' `zzedc.dsm_deemed_approval_day_type`, `"calendar"` by default or
#' `"business"`, which excludes weekends but not holidays) has passed
#' since the user-entered submission date. Eligibility is never
#' approval: putting such a plan into effect needs a signed
#' attestation ([dsm_transition()]).
#'
#' @param conn A DBI connection or pool.
#' @param plan_id The plan version.
#' @param as_of Date of evaluation (default today).
#' @return A list: `status`, `submitted_on`, `ico_decision`,
#'   `ico_decision_on`, `in_effect_from`, `deemed_eligible`,
#'   `deemed_eligible_on`; or `NULL` if the version does not exist.
#' @export
dsm_plan_status <- function(conn, plan_id, as_of = Sys.Date()) {
  if (!.dsm_tables_exist(conn)) return(NULL)
  ev <- DBI::dbGetQuery(conn, "
    SELECT event_id, to_status, effective_date, ico_decision
    FROM dsm_plan_events WHERE plan_id = ? ORDER BY event_id
  ", params = list(plan_id))
  if (nrow(ev) == 0) return(NULL)

  status <- ev$to_status[nrow(ev)]
  sub <- ev[ev$to_status == "submitted", , drop = FALSE]
  submitted_on <- if (nrow(sub) > 0) sub$effective_date[nrow(sub)] else NA
  dec <- ev[!is.na(ev$ico_decision), , drop = FALSE]
  ico_decision <- if (nrow(dec) > 0) dec$ico_decision[nrow(dec)] else NA
  ico_decision_on <- if (nrow(dec) > 0) dec$effective_date[nrow(dec)] else NA
  eff <- ev[ev$to_status == "in_effect", , drop = FALSE]
  in_effect_from <- if (nrow(eff) > 0) eff$effective_date[nrow(eff)] else NA

  days <- as.integer(getOption("zzedc.dsm_deemed_approval_days", 30L))
  eligible_on <- NA
  eligible <- FALSE
  if (identical(status, "submitted") && !is.na(submitted_on) &&
      is.na(ico_decision)) {
    eligible <- .dsm_days_elapsed(submitted_on, as_of) >= days
    if (identical(getOption("zzedc.dsm_deemed_approval_day_type",
                            "calendar"), "calendar")) {
      eligible_on <- as.character(as.Date(submitted_on) + days)
    }
  }

  list(status = status, submitted_on = submitted_on,
       ico_decision = ico_decision, ico_decision_on = ico_decision_on,
       in_effect_from = in_effect_from, deemed_eligible = eligible,
       deemed_eligible_on = eligible_on)
}


#' Check a Signature Presented for a Transition (internal)
#'
#' The signature must exist, be valid, be on this plan version's row
#' with the required meaning, be by the user making the transition,
#' still match the row's content, and not have been used for an
#' earlier transition.
#'
#' @param conn A DBI connection, inside a transaction.
#' @param signature_code The code returned by
#'   [apply_electronic_signature()].
#' @param plan_id The plan version.
#' @param meaning Required signature meaning.
#' @param user_id The user making the transition.
#' @param role Required signer role, or `NULL` for any role.
#' @return `invisible(TRUE)`; stops with a message otherwise.
#' @keywords internal
.dsm_check_signature <- function(conn, signature_code, plan_id, meaning,
                                 user_id, role = NULL) {
  if (is.null(signature_code) || !nzchar(signature_code)) {
    stop("This transition needs an electronic signature (", meaning,
         ") on the plan version")
  }
  if (!DBI::dbExistsTable(conn, "electronic_signatures")) {
    stop("Signature ", signature_code, " not found")
  }
  sig <- DBI::dbGetQuery(conn, "
    SELECT * FROM electronic_signatures WHERE signature_code = ?
  ", params = list(signature_code))
  if (nrow(sig) == 0) stop("Signature ", signature_code, " not found")
  if (!isTRUE(as.logical(as.integer(sig$is_valid[1])))) {
    stop("Signature ", signature_code, " has been invalidated")
  }
  if (!identical(sig$table_name[1], "dsm_plan_versions") ||
      !identical(as.character(sig$record_id[1]), as.character(plan_id))) {
    stop("Signature ", signature_code, " is not on plan version ", plan_id)
  }
  if (!identical(sig$signature_meaning[1], meaning)) {
    stop("Signature ", signature_code, " has meaning ",
         sig$signature_meaning[1], ", not ", meaning)
  }
  if (!identical(sig$signer_user_id[1], user_id)) {
    stop("Signature ", signature_code, " was applied by ",
         sig$signer_user_id[1], ", not by ", user_id)
  }
  current <- compute_record_hash(conn, "dsm_plan_versions", plan_id)
  if (!identical(current, sig$record_hash[1])) {
    stop("Plan version ", plan_id, " has changed since it was signed")
  }
  used <- DBI::dbGetQuery(conn, "
    SELECT COUNT(*) AS n FROM dsm_plan_events WHERE signature_code = ?
  ", params = list(signature_code))$n[1]
  if (used > 0) stop("Signature ", signature_code, " has already been used")
  if (!is.null(role)) {
    r <- DBI::dbGetQuery(conn, "
      SELECT role FROM edc_users WHERE user_id = ?
    ", params = list(user_id))
    if (nrow(r) == 0 || !identical(.normalize_role_name(r$role[1]),
                                   .normalize_role_name(role))) {
      stop("This signature must be applied by a user with role ", role)
    }
  }
  invisible(TRUE)
}


#' Move a Monitoring-Plan Version Through Its Lifecycle
#'
#' Allowed moves (design Section 6.4):
#'
#' * `draft` -> `internal_review` -> `signed`, which needs an
#'   `APPROVED_BY` signature on the version by the user making the
#'   move, who must have role `pi`; `internal_review` -> `draft`
#'   returns a plan for changes.
#' * `signed` -> `submitted`, with `effective_date` the date the plan
#'   was sent to the funding institute, as the user states it.
#' * `approved` -> `in_effect`. `approved` and `revise` are reached by
#'   [dsm_record_ico_decision()].
#' * `submitted` -> `in_effect` without an ICO decision (deemed
#'   approval), only once the version is eligible as of `as_of`, and
#'   with a `CERTIFIED_BY` signature by the user making the move,
#'   attesting that no response was received.
#'
#' * `signed` -> `in_effect` directly, only for a version registered as
#'   an amendment of class `"report_at_interval"`
#'   ([dsm_register_amendment()]). A `"prior_approval"` amendment takes
#'   effect only from `approved`; the deemed-approval path is refused
#'   for it.
#'
#' Putting a version into effect supersedes the study's version then
#' in effect, in the same transaction. Every move writes an event and
#' a `DSM_PLAN_STATUS` audit record together; a refused move writes
#' nothing.
#'
#' @param conn A DBI connection or pool.
#' @param plan_id The plan version.
#' @param to_status Target status.
#' @param user_id The user making the move.
#' @param effective_date The date the move refers to (submission date,
#'   or the date the plan takes effect); defaults to `as_of`.
#' @param note Optional free text.
#' @param signature_code Signature code, where the move needs one.
#' @param as_of Date of evaluation (default today).
#' @return `list(success = TRUE, plan_id, status)` or
#'   `list(success = FALSE, error)`.
#' @export
dsm_transition <- function(conn, plan_id, to_status, user_id,
                           effective_date = NULL, note = NULL,
                           signature_code = NULL, as_of = Sys.Date()) {
  # Evaluate every argument before the transaction opens. An argument
  # such as signature_code = apply_electronic_signature(...)$... is
  # otherwise evaluated lazily inside the transaction, where its own
  # connection is refused ("database is locked") on SQLite.
  force(signature_code)
  force(effective_date)
  force(note)
  force(as_of)
  tryCatch({
    if (!.dsm_tables_exist(conn)) stop("This database has no monitoring plans")
    if (!to_status %in% .dsm_stored_statuses) {
      stop("Unknown status: ", to_status)
    }
    if (to_status %in% c("approved", "revise")) {
      stop("Use dsm_record_ico_decision() to record the institute's decision")
    }
    effective_date <- as.character(as.Date(effective_date %||% as_of))
    now <- format(Sys.time(), tz = "UTC", "%Y-%m-%d %H:%M:%S")

    .with_db_transaction(conn, function(c) {
      plan <- DBI::dbGetQuery(c, "
        SELECT plan_id, study_id FROM dsm_plan_versions WHERE plan_id = ?
      ", params = list(plan_id))
      if (nrow(plan) == 0) stop("Plan version ", plan_id, " not found")
      .lock_dsm_study(c, plan$study_id[1])

      st <- dsm_plan_status(c, plan_id, as_of = as_of)
      from <- st$status
      if (!to_status %in% .dsm_transitions[[from]]) {
        stop("A plan cannot move from ", from, " to ", to_status)
      }

      if (to_status == "signed") {
        .dsm_check_signature(c, signature_code, plan_id, "APPROVED_BY",
                             user_id, role = "pi")
      }
      if (to_status == "submitted" && as.Date(effective_date) > as.Date(as_of)) {
        stop("The submission date cannot be in the future")
      }
      amendment <- .dsm_amendment_class(c, plan_id)
      if (to_status == "in_effect" && from == "signed" &&
          !identical(amendment, "report_at_interval")) {
        stop("Only an amendment reported at the next interval can take ",
             "effect without the institute's review; submit this plan")
      }
      if (to_status == "in_effect" && from == "submitted" &&
          identical(amendment, "prior_approval")) {
        stop("An amendment that needs prior approval takes effect only ",
             "after the institute's approval is recorded")
      }
      if (to_status == "in_effect" && from == "submitted") {
        if (!isTRUE(st$deemed_eligible)) {
          stop("Plan version ", plan_id, " is not yet eligible for deemed ",
               "approval and has no recorded ICO approval")
        }
        .dsm_check_signature(c, signature_code, plan_id, "CERTIFIED_BY",
                             user_id)
      }

      if (to_status == "in_effect") {
        current <- .dsm_in_effect_id(c, plan$study_id[1])
        if (!is.null(current) && current != plan_id) {
          .dsm_insert_event(c, current, from = "in_effect",
                            to = "superseded", user_id = user_id, at = now,
                            effective_date = effective_date,
                            note = paste("Superseded by plan version",
                                         plan_id))
        }
      }

      .dsm_insert_event(c, plan_id, from = from, to = to_status,
                        user_id = user_id, at = now,
                        effective_date = effective_date, note = note,
                        signature_code = signature_code)
    })
    list(success = TRUE, plan_id = plan_id, status = to_status)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}


#' Record the Funding Institute's Decision on a Submitted Plan
#'
#' Records what the user reports: zzedc cannot know the decision
#' itself. `approved` moves the version to `approved`; `revise` to
#' `revise`, after which a new version is imported.
#'
#' @param conn A DBI connection or pool.
#' @param plan_id The plan version, which must be `submitted`.
#' @param decision `"approved"` or `"revise"`.
#' @param decision_date The date of the decision, as the user states it.
#' @param user_id The user recording it.
#' @param document_ref Optional reference to the institute's letter.
#' @param as_of Date of evaluation (default today).
#' @return `list(success = TRUE, plan_id, status)` or
#'   `list(success = FALSE, error)`.
#' @export
dsm_record_ico_decision <- function(conn, plan_id, decision, decision_date,
                                    user_id, document_ref = NULL,
                                    as_of = Sys.Date()) {
  force(decision_date)
  force(document_ref)
  force(as_of)
  tryCatch({
    if (!.dsm_tables_exist(conn)) stop("This database has no monitoring plans")
    if (!decision %in% c("approved", "revise")) {
      stop("decision must be 'approved' or 'revise'")
    }
    decision_date <- as.character(as.Date(decision_date))
    if (as.Date(decision_date) > as.Date(as_of)) {
      stop("The decision date cannot be in the future")
    }
    now <- format(Sys.time(), tz = "UTC", "%Y-%m-%d %H:%M:%S")
    .with_db_transaction(conn, function(c) {
      plan <- DBI::dbGetQuery(c, "
        SELECT study_id FROM dsm_plan_versions WHERE plan_id = ?
      ", params = list(plan_id))
      if (nrow(plan) == 0) stop("Plan version ", plan_id, " not found")
      .lock_dsm_study(c, plan$study_id[1])
      st <- dsm_plan_status(c, plan_id, as_of = as_of)
      if (!identical(st$status, "submitted")) {
        stop("Only a submitted plan can receive a decision; this one is ",
             st$status)
      }
      if (as.Date(decision_date) < as.Date(st$submitted_on)) {
        stop("The decision date is before the submission date")
      }
      .dsm_insert_event(c, plan_id, from = "submitted", to = decision,
                        user_id = user_id, at = now,
                        effective_date = decision_date,
                        ico_decision = decision, document_ref = document_ref)
    })
    list(success = TRUE, plan_id = plan_id, status = decision)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}


#' Plan Version in Effect (internal, on a connection)
#' @param conn A DBI connection.
#' @param study_id The study.
#' @return A `plan_id`, or `NULL`.
#' @keywords internal
.dsm_in_effect_id <- function(conn, study_id) {
  ids <- DBI::dbGetQuery(conn, "
    SELECT plan_id FROM dsm_plan_versions WHERE study_id = ?
    ORDER BY version DESC
  ", params = list(study_id))$plan_id
  for (id in ids) {
    if (identical(dsm_plan_status(conn, id)$status, "in_effect")) return(id)
  }
  NULL
}


#' Monitoring-Plan Version in Effect for a Study
#'
#' @param conn A DBI connection or pool.
#' @param study_id The study.
#' @return A list (`plan_id`, `version`, `spec_hash`, `in_effect_from`),
#'   or `NULL` when no version is in effect or the database has no
#'   monitoring plans.
#' @export
dsm_plan_in_effect <- function(conn, study_id) {
  if (!.dsm_tables_exist(conn)) return(NULL)
  id <- .dsm_in_effect_id(conn, study_id)
  if (is.null(id)) return(NULL)
  row <- DBI::dbGetQuery(conn, "
    SELECT plan_id, version, spec_hash FROM dsm_plan_versions
    WHERE plan_id = ?
  ", params = list(id))
  list(plan_id = row$plan_id[1], version = row$version[1],
       spec_hash = row$spec_hash[1],
       in_effect_from = dsm_plan_status(conn, id)$in_effect_from)
}


#' History of a Study's Monitoring Plan
#'
#' @param conn A DBI connection or pool.
#' @param study_id The study.
#' @return A data frame of lifecycle events across all versions, in
#'   order (empty when there are none).
#' @export
dsm_plan_history <- function(conn, study_id) {
  if (!.dsm_tables_exist(conn)) {
    return(data.frame(plan_id = integer(0), version = integer(0),
                      from_status = character(0), to_status = character(0)))
  }
  DBI::dbGetQuery(conn, "
    SELECT v.plan_id, v.version, e.event_id, e.from_status, e.to_status,
           e.event_at, e.effective_date, e.user_id, e.ico_decision,
           e.signature_code, e.document_ref, e.note
    FROM dsm_plan_events e
    JOIN dsm_plan_versions v ON v.plan_id = e.plan_id
    WHERE v.study_id = ?
    ORDER BY e.event_id
  ", params = list(study_id))
}


# =============================================================================
# Amendments
# =============================================================================

#' Amendment Class of a Plan Version (internal)
#' @param conn A DBI connection.
#' @param plan_id The plan version.
#' @return `"prior_approval"`, `"report_at_interval"`, or `NULL` when the
#'   version is not registered as an amendment.
#' @keywords internal
.dsm_amendment_class <- function(conn, plan_id) {
  if (!DBI::dbExistsTable(conn, "dsm_amendments")) return(NULL)
  r <- DBI::dbGetQuery(conn, "
    SELECT amendment_class FROM dsm_amendments WHERE plan_id = ?
  ", params = list(plan_id))
  if (nrow(r) == 0) NULL else r$amendment_class[1]
}


#' Register a Draft Plan Version as an Amendment
#'
#' An amendment is a new plan version, usually imported from a
#' workbook generated from the version in effect
#' ([dsm_generate_workbook()] with `plan_id`), registered here with
#' its class while it is still a draft. The class decides how it
#' takes effect (draft notice, Section IV):
#'
#' * `"prior_approval"`: a change that needs NIH prior approval and
#'   amends the plan. The version must be submitted and the institute's
#'   approval recorded ([dsm_record_ico_decision()]) before it can take
#'   effect; the deemed-approval path is not available to it.
#' * `"report_at_interval"`: any other change. The version can take
#'   effect after the PI's signature, and the amendment is summarized
#'   at the next reporting interval ([dsm_amendments()]).
#'
#' zzedc cannot decide which class applies; that depends on the award's
#' prior-approval terms, and the rationale is required.
#'
#' @param conn A DBI connection or pool.
#' @param plan_id The new version, in status `draft`.
#' @param amendment_class `"prior_approval"` or `"report_at_interval"`.
#' @param summary What changes.
#' @param rationale Why, including why this class applies.
#' @param user_id The user registering it.
#' @return `list(success = TRUE, amendment_id, from_plan_id)` or
#'   `list(success = FALSE, error)`.
#' @export
dsm_register_amendment <- function(conn, plan_id, amendment_class, summary,
                                   rationale, user_id) {
  tryCatch({
    if (!.dsm_tables_exist(conn)) stop("This database has no monitoring plans")
    if (!amendment_class %in% c("prior_approval", "report_at_interval")) {
      stop("amendment_class must be 'prior_approval' or 'report_at_interval'")
    }
    for (x in list(summary, rationale)) {
      if (!is.character(x) || length(x) != 1 || !nzchar(trimws(x))) {
        stop("summary and rationale are required")
      }
    }
    migrate_add_dsm_tables(conn)
    now <- format(Sys.time(), tz = "UTC", "%Y-%m-%d %H:%M:%S")
    out <- .with_db_transaction(conn, function(c) {
      plan <- DBI::dbGetQuery(c, "
        SELECT study_id FROM dsm_plan_versions WHERE plan_id = ?
      ", params = list(plan_id))
      if (nrow(plan) == 0) stop("Plan version ", plan_id, " not found")
      .lock_dsm_study(c, plan$study_id[1])
      if (!identical(dsm_plan_status(c, plan_id)$status, "draft")) {
        stop("Only a draft version can be registered as an amendment")
      }
      if (!is.null(.dsm_amendment_class(c, plan_id))) {
        stop("Plan version ", plan_id, " is already registered as an amendment")
      }
      from <- .dsm_in_effect_id(c, plan$study_id[1])
      if (is.null(from)) {
        stop("No plan version is in effect, so there is nothing to amend")
      }
      id <- DBI::dbGetQuery(c, "
        INSERT INTO dsm_amendments (
          plan_id, from_plan_id, amendment_class, summary, rationale,
          created_by, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        RETURNING amendment_id AS id
      ", params = list(plan_id, from, amendment_class, summary, rationale,
                       user_id, now))$id[1]
      .append_audit_record(
        c, event_type = "INSERT", table_name = "dsm_amendments",
        record_id = id,
        operation = sprintf("Monitoring plan amendment registered (%s)",
                            amendment_class),
        details = .dsm_json(list(plan_id = plan_id, from_plan_id = from,
                                 amendment_class = amendment_class,
                                 summary = summary)),
        user_id = user_id
      )
      list(amendment_id = id, from_plan_id = from)
    })
    list(success = TRUE, amendment_id = out$amendment_id,
         from_plan_id = out$from_plan_id)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}


#' A Study's Plan Amendments
#'
#' Amendments with the date each took effect, for the amendment table of
#' a periodic monitoring report: an amendment of class
#' `"report_at_interval"` that took effect within the reporting period
#' is summarized in that period's report.
#'
#' @param conn A DBI connection or pool.
#' @param study_id The study.
#' @param from,to Optional dates bounding the date the amendments took
#'   effect (inclusive); amendments not yet in effect are included only
#'   when both are `NULL`.
#' @return A data frame (empty when there are none).
#' @export
dsm_amendments <- function(conn, study_id, from = NULL, to = NULL) {
  empty <- data.frame(amendment_id = integer(0), plan_id = integer(0),
                      from_plan_id = integer(0),
                      amendment_class = character(0), summary = character(0),
                      rationale = character(0), in_effect_from = character(0))
  if (!.dsm_tables_exist(conn) || !DBI::dbExistsTable(conn, "dsm_amendments")) {
    return(empty)
  }
  a <- DBI::dbGetQuery(conn, "
    SELECT a.amendment_id, a.plan_id, a.from_plan_id, a.amendment_class,
           a.summary, a.rationale
    FROM dsm_amendments a
    JOIN dsm_plan_versions v ON v.plan_id = a.plan_id
    WHERE v.study_id = ?
    ORDER BY a.amendment_id
  ", params = list(study_id))
  if (nrow(a) == 0) return(empty)
  a$in_effect_from <- vapply(a$plan_id, function(id) {
    v <- dsm_plan_status(conn, id)$in_effect_from
    if (is.null(v) || is.na(v)) NA_character_ else as.character(v)
  }, character(1))
  if (!is.null(from) || !is.null(to)) {
    d <- as.Date(a$in_effect_from)
    keep <- !is.na(d)
    if (!is.null(from)) keep <- keep & d >= as.Date(from)
    if (!is.null(to)) keep <- keep & d <= as.Date(to)
    a <- a[keep, , drop = FALSE]
  }
  a
}


# =============================================================================
# Activity gate
# =============================================================================

#' Is the Activity Gate On? (internal)
#'
#' Option `zzedc.dsm_require_plan_in_effect`, `FALSE` by default under
#' every security profile (owner decision, 2026-11-23).
#'
#' @return `TRUE`/`FALSE`.
#' @keywords internal
.dsm_gate_on <- function() {
  isTRUE(getOption("zzedc.dsm_require_plan_in_effect", FALSE))
}


#' Check the Activity Gate (internal)
#'
#' When the gate is on, randomization and the first data entry for a
#' subject need a monitoring-plan version in effect (the draft notice
#' requires an approved plan before human subject activities begin).
#' When the gate is off, returns at once, without touching the
#' database.
#'
#' @param conn A DBI connection or pool.
#' @param action Short description for the message.
#' @return `NULL` when the action may proceed, otherwise
#'   `list(success = FALSE, error = ...)`.
#' @keywords internal
.dsm_activity_gate <- function(conn, action) {
  if (!.dsm_gate_on()) return(NULL)
  in_effect <- tryCatch({
    if (!.dsm_tables_exist(conn)) {
      FALSE
    } else {
      studies <- DBI::dbGetQuery(conn, "
        SELECT DISTINCT study_id FROM dsm_plan_versions
      ")$study_id
      any(vapply(studies, function(s) !is.null(.dsm_in_effect_id(conn, s)),
                 logical(1)))
    }
  }, error = function(e) FALSE)
  if (isTRUE(in_effect)) return(NULL)
  list(success = FALSE, error = paste0(
    "No data and safety monitoring plan is in effect, so ", action,
    " is refused (option zzedc.dsm_require_plan_in_effect is on)."))
}
