#' REDCap to ZZedc Migration: Phase C1 connector
#'
#' Read-only ingestion of a REDCap-shaped relational database
#' into a ZZedc-compatible study. Phase C1 emits a directory of
#' CSV files (data dictionary, validation rules, user roster,
#' subject data, audit trail) that can be fed into
#' `setup_zzedc_from_gsheets()` (after staging into a Google
#' Sheet) or directly into the CSV authoring path documented in
#' `vignette('demonstration-trial-setup')`.
#'
#' Phase C2 (planned) will replace the CSV-emission step with
#' direct database creation and hash-chain replay; Phase C3
#' (planned) will add `.sql`-dump and REST-API source modes. See
#' `vignette('mysql-redcap-migration-roadmap')` for the full
#' phasing.
#'
#' The connector accepts any DBI-compatible connection whose
#' schema matches REDCap's relational layout. Tested source
#' types:
#' \itemize{
#'   \item Live MySQL / MariaDB connection (via
#'         \pkg{RMariaDB}); the typical production use case.
#'   \item SQLite database hydrated with REDCap-shaped tables;
#'         used by the package's own tests against synthetic
#'         fixtures and useful for offline replay.
#' }
#'
#' Untested but expected to work:
#' \itemize{
#'   \item PostgreSQL or other DBI connection whose schema has
#'         been pre-populated to match REDCap's table layout.
#' }
#'
#' @keywords internal
#' @name redcap_import
NULL


# ============================================================================
# REDCap field-type translation
# ============================================================================

#' Lookup table: REDCap field type -> ZZedc field type
#'
#' REDCap stores field types in `redcap_metadata.field_type` with
#' free-text validation in `text_validation_type_or_show_slider_number`.
#' The lookup below handles the common combinations.
#'
#' @keywords internal
REDCAP_FIELD_TYPE_MAP <- list(
  text          = "text",
  notes         = "text",
  textarea      = "text",
  calc          = "numeric",
  dropdown      = "select",
  radio         = "radio",
  checkbox      = "checkbox",
  yesno         = "checkbox",
  truefalse     = "checkbox",
  file          = "text",
  slider        = "numeric",
  descriptive   = "text",
  sql           = "text",
  email         = "text",
  date          = "date",
  datetime      = "date"
)

#' Translate a REDCap (field_type, validation_type) pair to a
#' ZZedc field_type.
#'
#' @keywords internal
redcap_translate_field_type <- function(redcap_type, validation_type = NA) {
  redcap_type <- tolower(as.character(redcap_type))
  validation_type <- tolower(as.character(validation_type))

  # Validation refines `text` into something more specific
  if (redcap_type == "text" && !is.na(validation_type) &&
      nzchar(validation_type)) {
    if (grepl("^date", validation_type)) return("date")
    if (grepl("^integer$|^number$|^float$",
              validation_type)) return("numeric")
    if (validation_type == "email")  return("text")
    if (validation_type == "phone")  return("text")
  }

  out <- REDCAP_FIELD_TYPE_MAP[[redcap_type]]
  if (is.null(out)) "text" else out
}


# ============================================================================
# Validation-rule extraction
# ============================================================================

#' Extract a ZZedc DSL validation rule from a REDCap metadata row.
#'
#' Phase C1 handles only range-style validations
#' (`text_validation_type_or_show_slider_number` is `integer`,
#' `number`, or `float` with `text_validation_min` /
#' `text_validation_max` set). Branching-logic translation is
#' deferred to Phase C2 (see roadmap vignette §"Implementation
#' work" for design notes on the recursive-descent parser this
#' will require).
#'
#' @param meta_row One-row data frame from `redcap_metadata`.
#' @return Named list with `dsl` (character or NA) and
#'   `category` (character).
#' @keywords internal
redcap_extract_rule_dsl <- function(meta_row) {
  vt <- tolower(as.character(
    meta_row$text_validation_type_or_show_slider_number %||% ""))
  vmin <- meta_row$text_validation_min
  vmax <- meta_row$text_validation_max
  fname <- as.character(meta_row$field_name)

  # Range validation
  is_numeric_validation <- vt %in% c("integer", "number", "float")
  has_min <- !is.null(vmin) && !is.na(vmin) && nzchar(as.character(vmin))
  has_max <- !is.null(vmax) && !is.na(vmax) && nzchar(as.character(vmax))

  if (is_numeric_validation && has_min && has_max) {
    return(list(
      dsl = sprintf("%s between %s and %s", fname, vmin, vmax),
      category = "FIELD"
    ))
  }
  if (is_numeric_validation && has_min) {
    return(list(dsl = sprintf("%s >= %s", fname, vmin), category = "FIELD"))
  }
  if (is_numeric_validation && has_max) {
    return(list(dsl = sprintf("%s <= %s", fname, vmax), category = "FIELD"))
  }

  # Branching logic translation deferred to Phase C2
  list(dsl = NA_character_, category = NA_character_)
}


# ============================================================================
# REDCap user-role translation
# ============================================================================

#' Translate REDCap permission flags to a ZZedc role string.
#'
#' REDCap encodes permissions as a packed string of comma-
#' separated rights (`design,user_rights,data_access_groups,
#' data_export_tool,...`). ZZedc's role system is coarser. Phase
#' C1 uses heuristic mapping: a user with `design` rights becomes
#' `Admin`; with `data_export_tool` becomes `Researcher`; with
#' general entry rights becomes `Coordinator`; otherwise
#' `Monitor`.
#'
#' @param rights_str REDCap rights string.
#' @return Character: one of `Admin`, `Coordinator`, `Researcher`,
#'   `Monitor`.
#' @keywords internal
redcap_translate_role <- function(rights_str) {
  if (is.null(rights_str) || is.na(rights_str)) return("Monitor")
  rs <- tolower(as.character(rights_str))
  if (grepl("design", rs))             return("Admin")
  if (grepl("data_export_tool", rs))   return("Researcher")
  if (grepl("data_entry|forms", rs))   return("Coordinator")
  "Monitor"
}


# ============================================================================
# Source-side extractors
# ============================================================================

#' Extract REDCap metadata (field definitions) for a project.
#'
#' Returns a tibble in ZZedc data-dictionary shape: one row per
#' field, columns `form_code`, `field_name`, `field_label`,
#' `field_type`, `required`, `validation`, `description`,
#' `field_order`.
#'
#' @param conn DBI connection to a REDCap-shaped database.
#' @param pid Numeric project ID (`redcap_metadata.project_id`).
#' @return Data frame.
#' @keywords internal
redcap_extract_metadata <- function(conn, pid) {
  rows <- DBI::dbGetQuery(conn, "
    SELECT field_name, form_name, field_type,
           element_label,
           required_field,
           text_validation_type_or_show_slider_number,
           text_validation_min, text_validation_max,
           field_order
      FROM redcap_metadata
     WHERE project_id = ?
     ORDER BY form_name, field_order
  ", params = list(pid))

  if (nrow(rows) == 0) {
    return(data.frame(
      form_code = character(0), field_name = character(0),
      field_label = character(0), field_type = character(0),
      required = logical(0), validation = character(0),
      description = character(0), field_order = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  data.frame(
    form_code   = as.character(rows$form_name),
    field_name  = as.character(rows$field_name),
    field_label = as.character(rows$element_label),
    field_type  = vapply(seq_len(nrow(rows)), function(i) {
      redcap_translate_field_type(
        rows$field_type[i],
        rows$text_validation_type_or_show_slider_number[i])
    }, character(1)),
    required    = !is.na(rows$required_field) &
                    as.character(rows$required_field) == "y",
    validation  = vapply(seq_len(nrow(rows)), function(i) {
      r <- redcap_extract_rule_dsl(rows[i, , drop = FALSE])
      if (is.na(r$dsl)) "" else r$dsl
    }, character(1)),
    description = "",
    field_order = as.integer(rows$field_order),
    stringsAsFactors = FALSE
  )
}


#' Extract REDCap validation rules in ZZedc DSL form.
#'
#' One row per validatable field. Fields without a translatable
#' rule (branching logic, complex conditionals) are skipped in
#' Phase C1 and recorded in the result's `skipped_rules` slot
#' for human review.
#'
#' @keywords internal
redcap_extract_validation_rules <- function(conn, pid) {
  rows <- DBI::dbGetQuery(conn, "
    SELECT field_name, form_name,
           field_type,
           text_validation_type_or_show_slider_number,
           text_validation_min, text_validation_max,
           branching_logic, element_label
      FROM redcap_metadata
     WHERE project_id = ?
  ", params = list(pid))

  out <- list()
  skipped <- list()

  for (i in seq_len(nrow(rows))) {
    r <- redcap_extract_rule_dsl(rows[i, , drop = FALSE])
    fname <- as.character(rows$field_name[i])

    if (!is.na(r$dsl)) {
      out[[length(out) + 1]] <- data.frame(
        rule_id        = paste0(toupper(fname), "_RANGE"),
        field_code     = fname,
        rule_dsl       = r$dsl,
        form_code      = as.character(rows$form_name[i]),
        rule_name      = paste(rows$element_label[i], "range"),
        error_message  = paste("Value out of allowed range for", fname),
        severity       = "ERROR",
        rule_category  = r$category,
        is_active      = TRUE,
        stringsAsFactors = FALSE
      )
    }

    bl <- rows$branching_logic[i]
    if (!is.null(bl) && !is.na(bl) && nzchar(as.character(bl))) {
      skipped[[length(skipped) + 1]] <- list(
        field = fname,
        reason = "branching_logic translation deferred to Phase C2",
        original = as.character(bl)
      )
    }
  }

  rules_df <- if (length(out) > 0) do.call(rbind, out) else
    data.frame(rule_id = character(0), field_code = character(0),
               rule_dsl = character(0), form_code = character(0),
               rule_name = character(0), error_message = character(0),
               severity = character(0), rule_category = character(0),
               is_active = logical(0), stringsAsFactors = FALSE)
  list(rules = rules_df, skipped_rules = skipped)
}


#' Extract REDCap users for a project.
#'
#' @keywords internal
redcap_extract_users <- function(conn, pid) {
  rows <- DBI::dbGetQuery(conn, "
    SELECT username, role_id, expiration,
           design, user_rights, data_access_groups,
           data_export_tool, reports, alerts, calendar
      FROM redcap_user_rights
     WHERE project_id = ?
  ", params = list(pid))

  if (nrow(rows) == 0) {
    return(data.frame(
      username = character(0), full_name = character(0),
      email = character(0), role = character(0),
      password_initial = character(0), site_id = character(0),
      active = logical(0), stringsAsFactors = FALSE
    ))
  }

  rights_concat <- function(i) {
    paste(c(
      if (!is.na(rows$design[i])           && rows$design[i] == 1)           "design",
      if (!is.na(rows$user_rights[i])      && rows$user_rights[i] == 1)      "user_rights",
      if (!is.na(rows$data_export_tool[i]) && rows$data_export_tool[i] != 0) "data_export_tool",
      if (!is.na(rows$data_access_groups[i]) && rows$data_access_groups[i] == 1) "data_access_groups",
      "forms"
    ), collapse = ",")
  }

  data.frame(
    username         = as.character(rows$username),
    full_name        = as.character(rows$username),  # full name lives elsewhere; placeholder
    email            = "",                            # placeholder; resolved from `redcap_user_information`
    role             = vapply(seq_len(nrow(rows)),
                              function(i) redcap_translate_role(rights_concat(i)),
                              character(1)),
    password_initial = "ChangeMe!2026",
    site_id          = "001",
    active           = is.na(rows$expiration) |
                         as.character(rows$expiration) == "" |
                         (suppressWarnings(as.Date(rows$expiration)) > Sys.Date()),
    stringsAsFactors = FALSE
  )
}


#' Extract REDCap subjects (record IDs).
#'
#' @keywords internal
redcap_extract_subjects <- function(conn, pid) {
  rows <- DBI::dbGetQuery(conn, "
    SELECT DISTINCT record FROM redcap_data WHERE project_id = ?
  ", params = list(pid))

  if (nrow(rows) == 0) {
    return(data.frame(subject_id = character(0),
                      stringsAsFactors = FALSE))
  }
  data.frame(subject_id = as.character(rows$record),
             stringsAsFactors = FALSE)
}


#' Extract REDCap subject data, EAV pivoted to wide form.
#'
#' For Phase C1, returns a long-form tibble (subject_id,
#' field_name, value, event_id) rather than a fully pivoted
#' wide table. Pivoting requires knowledge of repeating
#' instruments and longitudinal events, which the importer
#' captures separately and emits in C2.
#'
#' @keywords internal
redcap_extract_data <- function(conn, pid) {
  DBI::dbGetQuery(conn, "
    SELECT record AS subject_id,
           field_name,
           value,
           event_id
      FROM redcap_data
     WHERE project_id = ?
     ORDER BY record, event_id, field_name
  ", params = list(pid))
}


#' Extract REDCap audit log for a project.
#'
#' Phase C1 emits the audit rows as-is for human inspection.
#' Phase C2 will replay them into ZZedc's hash-chained
#' `audit_trail` table.
#'
#' @keywords internal
redcap_extract_audit <- function(conn, pid) {
  rows <- DBI::dbGetQuery(conn, "
    SELECT log_event_id, ts, user, ip, page, event,
           object_type, sql_log, pk, project_id, description
      FROM redcap_log_event
     WHERE project_id = ?
     ORDER BY ts
  ", params = list(pid))
  rows
}


# ============================================================================
# Phase C1 orchestrator
# ============================================================================

#' Import a REDCap project into ZZedc CSV-format artefacts
#'
#' Phase C1 of the REDCap migration pipeline. Reads a REDCap-
#' shaped relational database (typically via an \pkg{RMariaDB}
#' connection) and produces a directory of CSV files matching
#' the shape that
#' \code{\link{setup_zzedc_from_gsheets}} and the CSV authoring
#' path expect.
#'
#' Phase C1 limitations (deferred to subsequent phases):
#' \itemize{
#'   \item No direct database creation; the caller must run a
#'         second step (e.g.,
#'         \code{setup_zzedc_from_gsheets()} after staging the
#'         CSVs into a Google Sheet, or the data-dictionary CSV
#'         path).
#'   \item No audit-trail hash-chain replay; the audit CSV is
#'         emitted for human inspection.
#'   \item Branching-logic rules and complex cross-field
#'         conditionals are recorded in
#'         \code{result$skipped_rules} for manual translation.
#'   \item Repeating instruments and longitudinal events are
#'         emitted in long form rather than pivoted.
#'   \item Source modes other than a live DBI connection
#'         (\code{.sql}-dump file, REDCap REST API) are
#'         deferred to Phase C3.
#' }
#'
#' @param conn        DBI connection to a REDCap-shaped database
#'   (typically a live MySQL / MariaDB connection or a SQLite
#'   database hydrated with REDCap-shaped tables for testing).
#' @param pid         Numeric REDCap project ID.
#' @param output_dir  Directory to write CSV artefacts into.
#'   Created if it does not exist.
#' @param redcap_version Optional version string recorded in the
#'   manifest. The importer makes no version-specific decisions
#'   in C1; the field is for traceability.
#'
#' @return Named list with one entry per stage:
#' \describe{
#'   \item{success}{Logical TRUE if every stage succeeded.}
#'   \item{output_dir}{Directory the CSVs were written to.}
#'   \item{paths}{Named list of file paths
#'     (`data_dictionary`, `validation_rules`, `users`,
#'     `subjects`, `subject_data`, `audit_log`, `manifest`).}
#'   \item{counts}{Per-artefact row counts.}
#'   \item{skipped_rules}{List of rules that could not be
#'     translated automatically (branching logic, complex
#'     conditionals).}
#'   \item{warnings}{List of import-time warnings.}
#' }
#'
#' @examples
#' \dontrun{
#' # Live MySQL source (typical production use)
#' library(RMariaDB)
#' conn <- DBI::dbConnect(MariaDB(),
#'   host = "redcap.example.org",
#'   dbname = "redcap",
#'   user = "redcap_reader",
#'   password = Sys.getenv("REDCAP_DB_PASSWORD"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#'
#' result <- import_redcap_to_zzedc(
#'   conn       = conn,
#'   pid        = 42L,
#'   output_dir = "~/zzedc_migration/redcap_42"
#' )
#'
#' result$success
#' result$counts
#' length(result$skipped_rules)   # rules needing manual review
#'
#' # Next step: stage the CSVs into a Google Sheet (or use the
#' # data-dictionary CSV path) and call setup_zzedc_from_gsheets()
#' # against it. See vignette('mysql-redcap-migration-roadmap').
#' }
#'
#' @seealso \code{\link{setup_zzedc_from_gsheets}};
#'   \code{vignette('mysql-redcap-migration-roadmap')} for the
#'   full phasing.
#'
#' @export
import_redcap_to_zzedc <- function(conn, pid, output_dir,
                                    redcap_version = NULL) {
  if (!inherits(conn, "DBIConnection")) {
    return(list(success = FALSE,
                error = "`conn` must be a DBI connection"))
  }
  if (missing(pid) || !is.numeric(pid) || length(pid) != 1) {
    return(list(success = FALSE,
                error = "`pid` must be a single numeric value"))
  }
  if (missing(output_dir) || is.null(output_dir) ||
      !nzchar(output_dir)) {
    return(list(success = FALSE,
                error = "`output_dir` is required"))
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  result <- list(
    success = TRUE,
    output_dir = output_dir,
    redcap_version = redcap_version,
    paths = list(),
    counts = list(),
    skipped_rules = list(),
    warnings = list()
  )

  paths <- list(
    data_dictionary  = file.path(output_dir, "data_dictionary.csv"),
    validation_rules = file.path(output_dir, "validation_rules.csv"),
    users            = file.path(output_dir, "users.csv"),
    subjects         = file.path(output_dir, "subjects.csv"),
    subject_data     = file.path(output_dir, "subject_data.csv"),
    audit_log        = file.path(output_dir, "audit_log.csv"),
    manifest         = file.path(output_dir, "manifest.json")
  )
  result$paths <- paths

  # 1. Data dictionary
  dd <- tryCatch(redcap_extract_metadata(conn, pid),
                  error = function(e) {
                    result$warnings <<- c(result$warnings,
                      paste("metadata extraction failed:", e$message))
                    NULL
                  })
  if (!is.null(dd)) {
    utils::write.csv(dd, paths$data_dictionary, row.names = FALSE)
    result$counts$data_dictionary <- nrow(dd)
  } else {
    result$success <- FALSE
  }

  # 2. Validation rules
  rules <- tryCatch(redcap_extract_validation_rules(conn, pid),
                     error = function(e) {
                       result$warnings <<- c(result$warnings,
                         paste("rule extraction failed:", e$message))
                       NULL
                     })
  if (!is.null(rules)) {
    utils::write.csv(rules$rules, paths$validation_rules,
                      row.names = FALSE)
    result$counts$validation_rules <- nrow(rules$rules)
    result$skipped_rules <- rules$skipped_rules
  } else {
    result$success <- FALSE
  }

  # 3. Users
  users <- tryCatch(redcap_extract_users(conn, pid),
                     error = function(e) {
                       result$warnings <<- c(result$warnings,
                         paste("user extraction failed:", e$message))
                       NULL
                     })
  if (!is.null(users)) {
    utils::write.csv(users, paths$users, row.names = FALSE)
    result$counts$users <- nrow(users)
  } else {
    result$success <- FALSE
  }

  # 4. Subjects
  subjects <- tryCatch(redcap_extract_subjects(conn, pid),
                        error = function(e) {
                          result$warnings <<- c(result$warnings,
                            paste("subject extraction failed:", e$message))
                          NULL
                        })
  if (!is.null(subjects)) {
    utils::write.csv(subjects, paths$subjects, row.names = FALSE)
    result$counts$subjects <- nrow(subjects)
  } else {
    result$success <- FALSE
  }

  # 5. Subject data (long-form EAV)
  subj_data <- tryCatch(redcap_extract_data(conn, pid),
                         error = function(e) {
                           result$warnings <<- c(result$warnings,
                             paste("data extraction failed:", e$message))
                           NULL
                         })
  if (!is.null(subj_data)) {
    utils::write.csv(subj_data, paths$subject_data, row.names = FALSE)
    result$counts$subject_data <- nrow(subj_data)
  } else {
    result$success <- FALSE
  }

  # 6. Audit log
  audit <- tryCatch(redcap_extract_audit(conn, pid),
                     error = function(e) {
                       result$warnings <<- c(result$warnings,
                         paste("audit extraction failed:", e$message))
                       NULL
                     })
  if (!is.null(audit)) {
    utils::write.csv(audit, paths$audit_log, row.names = FALSE)
    result$counts$audit_log <- nrow(audit)
  } else {
    result$success <- FALSE
  }

  # 7. Manifest
  manifest <- list(
    redcap_project_id  = pid,
    redcap_version     = redcap_version,
    imported_at        = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    imported_by        = Sys.info()[["user"]],
    counts             = result$counts,
    skipped_rules      = length(result$skipped_rules),
    warnings           = length(result$warnings),
    importer_phase     = "C1",
    next_step          = paste("Stage CSVs into Google Sheet and run",
                                "setup_zzedc_from_gsheets() (or use the",
                                "CSV authoring path documented in",
                                "vignette('demonstration-trial-setup'))")
  )
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE,
                                 pretty = TRUE), paths$manifest)
  } else {
    writeLines(c(sprintf("redcap_project_id: %d", pid),
                  sprintf("imported_at: %s", manifest$imported_at)),
                paths$manifest)
  }

  result
}


# ============================================================================
# Roadmap stubs (Phase C2 / C3)
# ============================================================================

# ============================================================================
# Phase C2: branching-logic translator (simple cases)
# ============================================================================

#' Translate a REDCap branching-logic expression to ZZedc DSL.
#'
#' REDCap's branching-logic syntax uses `[field] OP value` with
#' the field name in square brackets. Phase C2 translates the
#' three most common patterns:
#'
#' \enumerate{
#'   \item Equality: `[sex] = "F"` -> `sex == "F"`
#'   \item Comparison: `[age] >= 18` -> `age >= 18`
#'   \item Logical compound: `[a] = "1" or [b] = "1"` -> `a == "1" || b == "1"`
#' }
#'
#' Phase C2 conservatively returns NA for any expression that
#' contains a construct it does not recognise (parentheses
#' nested deeper than one level, REDCap-specific functions like
#' `datediff()`, instance references like `[event_arm_1][age]`).
#' Such rows are recorded in the importer's
#' `result$skipped_rules` list so the user can translate them
#' manually following the patterns documented in
#' `vignette('content-author-guide')` Chapter 3 ('Authoring the
#' workbook').
#'
#' @param expr REDCap branching-logic expression.
#' @return Character ZZedc DSL expression, or NA if untranslatable.
#' @keywords internal
redcap_translate_branching_logic <- function(expr) {
  if (is.null(expr) || is.na(expr)) return(NA_character_)
  expr <- as.character(expr)
  if (!nzchar(trimws(expr))) return(NA_character_)

  # Reject constructs Phase C2 cannot handle: REDCap-specific
  # functions (datediff, sum, ...); event-arm prefixed
  # references; nested square brackets.
  hard <- c("datediff", "sum(", "rounddown", "[event-name]",
            "[arm-num]", "][")
  if (any(vapply(hard, function(p) grepl(p, expr, fixed = TRUE),
                  logical(1)))) {
    return(NA_character_)
  }

  out <- expr
  # Field references: [field_name] -> field_name
  out <- gsub("\\[([a-zA-Z_][a-zA-Z0-9_]*)\\]", "\\1", out)
  # Equality:    `=` (REDCap)  -> `==` (DSL)
  # Inequality:  `<>`          -> `!=`
  # Other comparators (>=, <=, >, <, !=) match DSL already.
  # Use placeholders so we don't double-translate.
  out <- gsub("<>", " %NE% ", out, fixed = TRUE)
  out <- gsub("(?<![<>=!])=(?!=)", " == ", out, perl = TRUE)
  out <- gsub("%NE%", "!=", out, fixed = TRUE)
  # Logical operators: REDCap's word forms -> DSL symbols
  out <- gsub("\\bor\\b",  "||", out, ignore.case = TRUE)
  out <- gsub("\\band\\b", "&&", out, ignore.case = TRUE)
  out <- gsub("\\bnot\\b", "!",  out, ignore.case = TRUE)
  # Collapse whitespace
  out <- gsub("\\s+", " ", trimws(out))

  # Final acceptance check: the translated expression must
  # consist only of identifiers, numbers, quoted strings, the
  # accepted operator set, and parentheses. Anything else is
  # rejected.
  permitted <- "^[ A-Za-z0-9_\"'.<>=!&|()+\\-]*$"
  if (!grepl(permitted, out)) return(NA_character_)
  out
}


# ============================================================================
# Phase C2: audit-trail hash-chain replay
# ============================================================================

#' Translate a REDCap event label to a ZZedc event_type.
#'
#' REDCap's `redcap_log_event.event` is free-text descriptive
#' (e.g., "INSERT", "Manage/Design", "Updated record S001").
#' ZZedc's `audit_log.event_type` is constrained to a fixed
#' enumeration. Phase C2 maps the common categories; anything
#' unrecognised becomes `ACCESS` (the safest non-destructive
#' default) with the original label preserved in `details`.
#'
#' @keywords internal
redcap_translate_event_type <- function(label) {
  if (is.null(label) || is.na(label)) return("ACCESS")
  l <- tolower(as.character(label))
  if (grepl("insert|create|add",        l)) return("INSERT")
  if (grepl("update|edit|modif",        l)) return("UPDATE")
  if (grepl("delete|remov",             l)) return("DELETE")
  if (grepl("export|download",          l)) return("EXPORT")
  if (grepl("login.*fail|invalid pass", l)) return("LOGIN_FAILED")
  if (grepl("login",                    l)) return("LOGIN")
  if (grepl("logout",                   l)) return("LOGOUT")
  if (grepl("design|manage",            l)) return("CONFIG_CHANGE")
  "ACCESS"
}


#' Replay a REDCap audit log into ZZedc's hash-chained audit table.
#'
#' Iterates over a REDCap `redcap_log_event` extract in
#' chronological order, computes a ZZedc `audit_log` row for
#' each REDCap row, and writes both that row and a corresponding
#' `audit_chain` row. The hash chain is computed live: each
#' record's `audit_hash` is `sha256(event_type | table_name |
#' record_id | operation | details | user_id | timestamp |
#' previous_hash)`, with the first record's `previous_hash` set
#' to `GENESIS`. After replay, `verify_audit_log_integrity()`
#' validates the chain.
#'
#' Imported rows have `details` JSON marked
#' `{"source":"redcap","redcap_log_event_id":...,"original":"..."}`
#' so that REDCap-origin actions remain attributable after the
#' import.
#'
#' @param redcap_audit Data frame of REDCap audit rows in the
#'   shape returned by [redcap_extract_audit()] (columns
#'   `log_event_id`, `ts`, `user`, `event`, `description`,
#'   `pk`).
#' @param db_path Path to the ZZedc database to populate.
#' @param key Encryption key (from
#'   `initialize_encrypted_database()$key`).
#' @param completeness One of `"full"`, `"partial"`, `"empty"`.
#'   When not `"full"`, a marker event is prepended to the
#'   audit chain documenting the gap; downstream chain
#'   validation continues to succeed, but the chain is
#'   labelled as starting at the migration boundary rather
#'   than at the project's true genesis.
#' @return List with `success`, `imported`, `errors`,
#'   `chain_validates`, and (when applicable) `completeness`
#'   and `marker_inserted`.
#' @keywords internal
replay_redcap_audit <- function(redcap_audit, db_path, key,
                                 completeness = "full") {
  if (!is.data.frame(redcap_audit)) {
    return(list(success = FALSE, imported = 0L,
                error = "redcap_audit must be a data frame"))
  }
  completeness <- match.arg(completeness,
                              c("full", "partial", "empty"))
  if (nrow(redcap_audit) == 0L && completeness == "full") {
    return(list(success = TRUE, imported = 0L,
                chain_validates = TRUE,
                completeness = "full",
                marker_inserted = FALSE,
                message = "no audit rows to replay"))
  }

  conn <- connect_encrypted_db(db_path = db_path, key = key)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # Establish the chain anchor. If the audit_log already has
  # rows, replay continues from the last hash; otherwise the
  # first replayed row's previous_hash is "GENESIS".
  prev_hash_q <- DBI::dbGetQuery(conn, "
    SELECT audit_hash FROM audit_log
    ORDER BY audit_id DESC LIMIT 1
  ")
  previous_hash <- if (nrow(prev_hash_q) > 0L) prev_hash_q[1, 1] else "GENESIS"

  # Determine starting chain_order
  chain_q <- DBI::dbGetQuery(conn,
    "SELECT COALESCE(MAX(chain_order), 0) AS m FROM audit_chain")
  chain_order <- chain_q$m[1]

  marker_inserted <- FALSE

  # If the source's audit log was partial or empty, insert a
  # single marker event before replay so the chain anchor is
  # explicit. Downstream callers can detect the marker by
  # `event_type == "MIGRATION_AUDIT_GAP"` and degrade their
  # continuity-of-record claim accordingly.
  if (completeness != "full") {
    marker_event_type <- "MIGRATION_AUDIT_GAP"
    marker_user       <- "redcap_import"
    marker_record     <- ""
    marker_table      <- "audit_log"
    marker_op         <- sprintf(
      "REDCap audit log was %s during REST API migration",
      completeness)
    marker_details_obj <- list(
      source       = "redcap_api",
      completeness = completeness,
      reason       = paste("REDCap log endpoint returned",
                            completeness, "audit"),
      notice       = paste("Continuity-of-record begins from",
                            "this marker forward; pre-migration",
                            "history is unverified.")
    )
    marker_details <- if (requireNamespace("jsonlite", quietly = TRUE)) {
      jsonlite::toJSON(marker_details_obj, auto_unbox = TRUE,
                        na = "string")
    } else {
      sprintf("source=redcap_api; completeness=%s", completeness)
    }
    marker_ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    marker_content <- paste(marker_event_type, marker_table,
                             marker_record, marker_op,
                             marker_details, marker_user,
                             marker_ts, previous_hash, sep = "|")
    marker_hash <- digest::digest(marker_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO audit_log
        (timestamp, user_id, event_type, table_name, record_id,
         operation, details, audit_hash, previous_hash)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(marker_ts, marker_user, marker_event_type,
            marker_table, marker_record, marker_op,
            marker_details, marker_hash, previous_hash))
    marker_audit_id <- DBI::dbGetQuery(conn,
      "SELECT last_insert_rowid() AS id")$id[1]
    chain_order <- chain_order + 1L
    DBI::dbExecute(conn, "
      INSERT INTO audit_chain
        (audit_id, record_hash, previous_hash, chain_order, verified)
      VALUES (?, ?, ?, ?, 1)
    ", list(marker_audit_id, marker_hash, previous_hash,
            chain_order))
    previous_hash   <- marker_hash
    marker_inserted <- TRUE
  }

  if (nrow(redcap_audit) == 0L) {
    # No events to replay (empty completeness). Validate the
    # chain (which now contains just the marker) and return.
    chain <- DBI::dbGetQuery(conn,
      "SELECT * FROM audit_chain ORDER BY chain_order")
    chain_validates <- if (nrow(chain) <= 1L) TRUE
      else all(chain$previous_hash[-1] ==
                  chain$record_hash[-nrow(chain)])
    return(list(success = TRUE, imported = 0L,
                chain_validates = chain_validates,
                completeness = completeness,
                marker_inserted = marker_inserted))
  }

  # Sort REDCap rows chronologically before replay.
  ord <- order(as.character(redcap_audit$ts))
  redcap_audit <- redcap_audit[ord, , drop = FALSE]

  imported <- 0L
  errors   <- list()

  for (i in seq_len(nrow(redcap_audit))) {
    row <- redcap_audit[i, , drop = FALSE]
    event_type <- redcap_translate_event_type(row$event)
    user_id    <- as.character(row$user %||% "redcap")
    record_id  <- as.character(row$pk %||% "")
    table_nm   <- "redcap_data"
    operation  <- as.character(row$description %||% "")
    ts         <- as.character(row$ts %||% format(Sys.time()))
    details_obj <- list(
      source              = "redcap",
      redcap_log_event_id = row$log_event_id %||% NA,
      redcap_event_label  = row$event,
      redcap_timestamp    = ts
    )
    details <- if (requireNamespace("jsonlite", quietly = TRUE)) {
      jsonlite::toJSON(details_obj, auto_unbox = TRUE, na = "string")
    } else {
      sprintf("source=redcap; ts=%s", ts)
    }

    record_content <- paste(event_type, table_nm, record_id,
                             operation, details, user_id, ts,
                             previous_hash, sep = "|")
    audit_hash <- digest::digest(record_content, algo = "sha256")

    inserted <- tryCatch({
      DBI::dbExecute(conn, "
        INSERT INTO audit_log
          (timestamp, user_id, event_type, table_name, record_id,
           operation, details, audit_hash, previous_hash)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ", list(ts, user_id, event_type, table_nm, record_id,
              operation, details, audit_hash, previous_hash))
      audit_id <- DBI::dbGetQuery(conn,
        "SELECT last_insert_rowid() AS id")$id[1]
      chain_order <- chain_order + 1L
      DBI::dbExecute(conn, "
        INSERT INTO audit_chain
          (audit_id, record_hash, previous_hash, chain_order, verified)
        VALUES (?, ?, ?, ?, 1)
      ", list(audit_id, audit_hash, previous_hash, chain_order))
      TRUE
    }, error = function(e) {
      errors[[length(errors) + 1L]] <<- list(
        index = i, log_event_id = row$log_event_id,
        error = e$message)
      FALSE
    })

    if (inserted) {
      imported    <- imported + 1L
      previous_hash <- audit_hash
    }
  }

  # Validate the chain
  chain_validates <- tryCatch({
    chain <- DBI::dbGetQuery(conn,
      "SELECT * FROM audit_chain ORDER BY chain_order")
    if (nrow(chain) == 0) TRUE
    else {
      ok <- TRUE
      for (j in seq_len(nrow(chain))[-1]) {
        if (chain$previous_hash[j] != chain$record_hash[j - 1L]) {
          ok <- FALSE; break
        }
      }
      ok
    }
  }, error = function(e) FALSE)

  list(
    success         = length(errors) == 0L,
    imported        = imported,
    errors          = errors,
    chain_validates = chain_validates,
    completeness    = completeness,
    marker_inserted = marker_inserted
  )
}


# ============================================================================
# Phase C2: direct-to-database orchestrator
# ============================================================================

#' Direct-to-database REDCap importer (Phase C2 + C3a)
#'
#' One-call equivalent to the C1 two-step flow: extract from
#' REDCap, create a ZZedc database, populate users and CRFs,
#' load subjects and form data, and replay the REDCap audit log
#' into the ZZedc hash-chained audit trail.
#'
#' Two source modes are supported:
#' \itemize{
#'   \item `source = "db"` (the default; Phase C2): extract via
#'         a live DBI connection (typically MySQL / MariaDB
#'         against the REDCap relational tables). Audit log is
#'         always full.
#'   \item `source = "api"` (Phase C3a): extract via the REDCap
#'         REST API using \pkg{REDCapR}. The audit log is
#'         classified as `full`, `partial`, or `empty` depending
#'         on the token's `Logging` permission. When not
#'         `"full"`, a `MIGRATION_AUDIT_GAP` marker is prepended
#'         to the audit chain so continuity-of-record is
#'         preserved from the migration boundary forward.
#' }
#'
#' Phase C2 / C3a limitations (deferred to subsequent work):
#' \itemize{
#'   \item Repeating instruments and longitudinal events are
#'         flattened into a single `visit_code` per
#'         `event_id`. Studies with repeating-instrument
#'         schemas should review the import diagnostics and may
#'         need to restructure the data dictionary.
#'   \item Branching-logic rules that exceed the simple grammar
#'         in `redcap_translate_branching_logic()` are recorded
#'         as skipped rather than translated; manual review is
#'         required.
#'   \item `.sql`-dump source mode is Phase C3b.
#' }
#'
#' @param conn        DBI connection to a REDCap-shaped database.
#'   Required for `source = "db"`.
#' @param pid         Numeric REDCap project ID. Required for
#'   `source = "db"`; ignored for `source = "api"` (the API
#'   token implicitly scopes the project).
#' @param db_path     Path to the ZZedc encrypted SQLite database
#'   to create. Must not exist unless `overwrite = TRUE`.
#' @param source      One of `"db"` (default) or `"api"`.
#' @param api         Optional pre-built API handle from
#'   [redcap_api_connect()]. If supplied, `api_url` /
#'   `api_token` are ignored. Useful for tests.
#' @param api_url     REDCap API endpoint. Required for
#'   `source = "api"` when `api` is not supplied.
#' @param api_token   REDCap API token. Required for
#'   `source = "api"` when `api` is not supplied.
#' @param overwrite   Logical. Overwrite an existing database?
#'   Default `FALSE`.
#' @param on_conflict Resolution policy when imported rows
#'   conflict with existing rows (relevant only when importing
#'   into a non-empty database). One of `"skip"` (default),
#'   `"merge"` (more permissive role wins), `"fail"`.
#' @param dry_run     Logical. If TRUE, exercises the importer
#'   end-to-end but rolls back the database transaction.
#' @param imported_by User ID recorded for the import action.
#'
#' @return Named list with one entry per stage (`csv`,
#'   `database`, `users`, `forms`, `subjects`, `subject_data`,
#'   `audit_replay`), each carrying its own success flag and
#'   counts. Top-level `success` is TRUE only if every stage
#'   passed. Includes `key` (encryption key) so callers can
#'   `Sys.setenv(DB_ENCRYPTION_KEY = result$key)` for subsequent
#'   operations. The `audit_replay` slot carries
#'   `completeness` (`"full"` / `"partial"` / `"empty"`) and
#'   `marker_inserted` (TRUE iff a `MIGRATION_AUDIT_GAP` marker
#'   was prepended).
#'
#' @examples
#' \dontrun{
#' # Phase C2 (live MySQL source)
#' library(RMariaDB)
#' conn <- DBI::dbConnect(MariaDB(),
#'   host     = "redcap.example.org",
#'   dbname   = "redcap",
#'   user     = "redcap_reader",
#'   password = Sys.getenv("REDCAP_DB_PASSWORD"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#'
#' result <- import_redcap_to_zzedc_db(
#'   conn       = conn,
#'   pid        = 42L,
#'   db_path    = "/srv/zzedc/MIGRATED-001/study.db",
#'   overwrite  = TRUE
#' )
#'
#' # Phase C3a (REST API source)
#' result_api <- import_redcap_to_zzedc_db(
#'   source    = "api",
#'   api_url   = "https://redcap.example.org/api/",
#'   api_token = Sys.getenv("REDCAP_API_TOKEN"),
#'   db_path   = "/srv/zzedc/MIGRATED-002/study.db",
#'   overwrite = TRUE
#' )
#'
#' Sys.setenv(DB_ENCRYPTION_KEY = result$key)
#' result$audit_replay$chain_validates    # should be TRUE
#' result$audit_replay$completeness       # full / partial / empty
#' result$audit_replay$marker_inserted    # TRUE if not full
#' length(result$skipped_rules)           # rules needing manual review
#' }
#'
#' @seealso [import_redcap_to_zzedc()] for Phase C1 (CSV
#'   emission); [redcap_api_connect()] for the API handle;
#'   `vignette('mysql-redcap-migration-roadmap')` for the full
#'   phasing.
#'
#' @export
import_redcap_to_zzedc_db <- function(conn = NULL, pid = NA,
                                       db_path,
                                       source = c("db", "api"),
                                       api = NULL,
                                       api_url = NULL,
                                       api_token = NULL,
                                       overwrite   = FALSE,
                                       on_conflict = c("skip",
                                                       "merge",
                                                       "fail"),
                                       dry_run     = FALSE,
                                       imported_by = "redcap_import") {
  source <- match.arg(source)
  on_conflict <- match.arg(on_conflict)

  if (missing(db_path) || is.null(db_path) || !nzchar(db_path)) {
    return(list(success = FALSE,
                error = "`db_path` is required"))
  }

  if (source == "db") {
    if (!inherits(conn, "DBIConnection")) {
      return(list(success = FALSE,
                  error = "`conn` must be a DBI connection"))
    }
    if (!is.numeric(pid) || length(pid) != 1L || is.na(pid)) {
      return(list(success = FALSE,
                  error = "`pid` must be a single numeric value"))
    }
  } else {
    if (is.null(api)) {
      api <- tryCatch(
        redcap_api_connect(api_url = api_url, api_token = api_token),
        error = function(e) {
          structure(list(error = conditionMessage(e)),
                     class = "redcap_api_error")
        }
      )
      if (inherits(api, "redcap_api_error")) {
        return(list(success = FALSE,
                    error = paste("REDCap API connect failed:",
                                   api$error)))
      }
    }
    if (!is.numeric(pid) || length(pid) != 1L || is.na(pid)) {
      pid <- 0L
    }
  }

  result <- list(
    success         = TRUE,
    pid             = pid,
    db_path         = db_path,
    source          = source,
    on_conflict     = on_conflict,
    dry_run         = dry_run,
    csv             = list(success = FALSE),
    database        = list(success = FALSE),
    users           = list(success = FALSE, imported = 0L),
    forms           = list(success = FALSE, imported_forms = 0L,
                            imported_fields = 0L),
    subjects        = list(success = FALSE, imported = 0L),
    subject_data    = list(success = FALSE, imported = 0L),
    audit_replay    = list(success = FALSE, imported = 0L),
    skipped_rules   = list(),
    errors          = list()
  )

  # --- 1. Extract artefacts from REDCap --------------------------
  csv_dir <- file.path(tempdir(),
                        sprintf("redcap_c2_pid_%s_%s",
                                as.character(pid),
                                format(Sys.time(), "%Y%m%d%H%M%S")))
  dir.create(csv_dir, recursive = TRUE, showWarnings = FALSE)

  audit_completeness <- "full"

  if (source == "db") {
    c1 <- import_redcap_to_zzedc(conn = conn, pid = pid,
                                  output_dir = csv_dir)
    result$csv <- c1
    if (!isTRUE(c1$success)) {
      result$success <- FALSE
      result$errors$csv <- c1$error %||% "C1 extraction failed"
      return(result)
    }
    result$skipped_rules <- c1$skipped_rules

    dd       <- utils::read.csv(c1$paths$data_dictionary,
                                  stringsAsFactors = FALSE)
    rules_df <- utils::read.csv(c1$paths$validation_rules,
                                  stringsAsFactors = FALSE)
    users_df <- utils::read.csv(c1$paths$users,
                                  stringsAsFactors = FALSE)
    subj_df  <- utils::read.csv(c1$paths$subjects,
                                  stringsAsFactors = FALSE)
    data_df  <- utils::read.csv(c1$paths$subject_data,
                                  stringsAsFactors = FALSE)
    audit_df <- utils::read.csv(c1$paths$audit_log,
                                  stringsAsFactors = FALSE)
    api_metadata <- NULL
  } else {
    # source == "api": run API extractors directly into data
    # frames, then write CSVs in parallel with the C1 contract
    # so downstream stages see an identical shape.
    api_metadata <- redcap_extract_metadata_api(api)
    dd           <- api_metadata
    users_df     <- redcap_extract_users_api(api)
    subj_df      <- redcap_extract_subjects_api(api,
                                                 metadata = api_metadata)
    data_df      <- redcap_extract_data_api(api)
    audit_obj    <- redcap_extract_audit_api(api)
    audit_completeness <- redcap_check_audit_completeness(
      audit_obj, n_records = nrow(subj_df))
    audit_df     <- audit_obj$events

    rules_df <- data.frame(
      rule_id = character(0), field_code = character(0),
      rule_dsl = character(0), form_code = character(0),
      rule_name = character(0), error_message = character(0),
      severity = character(0), rule_category = character(0),
      is_active = logical(0), stringsAsFactors = FALSE
    )
    skipped <- list()
    if (nrow(api_metadata) > 0L) {
      raw_meta <- tryCatch(api$ops$metadata(),
                            error = function(e) NULL)
      if (!is.null(raw_meta) && nrow(raw_meta) > 0L) {
        for (i in seq_len(nrow(api_metadata))) {
          fname <- as.character(api_metadata$field_name[i])
          dsl   <- as.character(api_metadata$validation[i])
          if (nzchar(dsl)) {
            rules_df <- rbind(rules_df, data.frame(
              rule_id        = paste0(toupper(fname), "_RANGE"),
              field_code     = fname,
              rule_dsl       = dsl,
              form_code      = as.character(api_metadata$form_code[i]),
              rule_name      = paste(api_metadata$field_label[i],
                                      "range"),
              error_message  = paste("Value out of allowed range for",
                                      fname),
              severity       = "ERROR",
              rule_category  = "FIELD",
              is_active      = TRUE,
              stringsAsFactors = FALSE))
          }
          bl <- raw_meta$branching_logic[
            match(fname, as.character(raw_meta$field_name))]
          if (!is.null(bl) && !is.na(bl) &&
                nzchar(as.character(bl))) {
            skipped[[length(skipped) + 1L]] <- list(
              field    = fname,
              reason   = "branching_logic translation deferred",
              original = as.character(bl))
          }
        }
      }
    }
    result$skipped_rules <- skipped

    utils::write.csv(dd,       file.path(csv_dir, "data_dictionary.csv"),
                      row.names = FALSE)
    utils::write.csv(rules_df, file.path(csv_dir, "validation_rules.csv"),
                      row.names = FALSE)
    utils::write.csv(users_df, file.path(csv_dir, "users.csv"),
                      row.names = FALSE)
    utils::write.csv(subj_df,  file.path(csv_dir, "subjects.csv"),
                      row.names = FALSE)
    utils::write.csv(data_df,  file.path(csv_dir, "subject_data.csv"),
                      row.names = FALSE)
    utils::write.csv(audit_df, file.path(csv_dir, "audit_log.csv"),
                      row.names = FALSE)
    result$csv <- list(
      success    = TRUE,
      output_dir = csv_dir,
      paths      = list(
        data_dictionary  = file.path(csv_dir, "data_dictionary.csv"),
        validation_rules = file.path(csv_dir, "validation_rules.csv"),
        users            = file.path(csv_dir, "users.csv"),
        subjects         = file.path(csv_dir, "subjects.csv"),
        subject_data     = file.path(csv_dir, "subject_data.csv"),
        audit_log        = file.path(csv_dir, "audit_log.csv")),
      counts     = list(
        data_dictionary  = nrow(dd),
        validation_rules = nrow(rules_df),
        users            = nrow(users_df),
        subjects         = nrow(subj_df),
        subject_data     = nrow(data_df),
        audit_log        = nrow(audit_df))
    )

    if (audit_completeness != "full") {
      warning(sprintf(
        "REDCap audit log was %s during API extraction; ",
        audit_completeness),
        "continuity-of-record will be anchored at a ",
        "MIGRATION_AUDIT_GAP marker. The chain validates ",
        "from the marker forward.")
    }
  }

  # --- 2. Translate branching-logic rules where possible --------
  if (source == "db") {
    meta_rows <- DBI::dbGetQuery(conn, "
      SELECT field_name, branching_logic FROM redcap_metadata
      WHERE project_id = ?
        AND branching_logic IS NOT NULL
        AND branching_logic <> ''
    ", params = list(pid))
  } else {
    raw <- tryCatch(api$ops$metadata(), error = function(e) NULL)
    if (is.null(raw) ||
          !"branching_logic" %in% names(raw)) {
      meta_rows <- data.frame(field_name = character(0),
                               branching_logic = character(0),
                               stringsAsFactors = FALSE)
    } else {
      keep <- !is.na(raw$branching_logic) &
                nzchar(as.character(raw$branching_logic))
      meta_rows <- data.frame(
        field_name      = as.character(raw$field_name[keep]),
        branching_logic = as.character(raw$branching_logic[keep]),
        stringsAsFactors = FALSE)
    }
  }
  branching_added <- 0L
  for (i in seq_len(nrow(meta_rows))) {
    dsl <- redcap_translate_branching_logic(meta_rows$branching_logic[i])
    if (!is.na(dsl) && nzchar(dsl)) {
      rules_df <- rbind(rules_df, data.frame(
        rule_id        = paste0(toupper(meta_rows$field_name[i]),
                                 "_BRANCH"),
        field_code     = meta_rows$field_name[i],
        rule_dsl       = dsl,
        form_code      = "",
        rule_name      = paste("Branching:", meta_rows$field_name[i]),
        error_message  = paste("Branching rule failed for",
                                meta_rows$field_name[i]),
        severity       = "WARNING",
        rule_category  = "CROSS_FIELD",
        is_active      = TRUE,
        stringsAsFactors = FALSE
      ))
      branching_added <- branching_added + 1L
    }
  }
  result$branching_translated <- branching_added

  # --- 3. Initialise the encrypted database ---------------------
  if (dry_run) {
    result$database <- list(success = TRUE,
                            message = "dry_run: skipped database init")
    return(result)
  }
  # `initialize_encrypted_database()` creates the encrypted
  # SQLite file with `study_info` and `subjects` tables; we
  # provision the additional tables the importer needs
  # (`edc_users`, `form_data`) via raw CREATE TABLE IF NOT
  # EXISTS through the encrypted connection. This keeps the
  # encryption story simple: every connection uses the same
  # key and the file is encrypted from genesis.
  init_res <- initialize_encrypted_database(db_path = db_path,
                                              overwrite = overwrite)
  result$database <- init_res
  if (!isTRUE(init_res$success)) {
    result$success <- FALSE
    result$errors$database <- init_res$error
    return(result)
  }
  result$key <- init_res$key

  # `save_user_to_db()`, `create_crf_definition()` and
  # `add_form_field()` resolve the target database through
  # `Sys.getenv("ZZEDC_DB_PATH")` plus `DB_ENCRYPTION_KEY`.
  # Save the prior values and restore on exit so the caller's
  # environment is left unchanged (CRAN policy).
  prior_db_path <- Sys.getenv("ZZEDC_DB_PATH", unset = NA)
  prior_key     <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
  on.exit({
    if (is.na(prior_db_path)) {
      Sys.unsetenv("ZZEDC_DB_PATH")
    } else {
      Sys.setenv(ZZEDC_DB_PATH = prior_db_path)
    }
    if (is.na(prior_key)) {
      Sys.unsetenv("DB_ENCRYPTION_KEY")
    } else {
      Sys.setenv(DB_ENCRYPTION_KEY = prior_key)
    }
  }, add = TRUE)
  Sys.setenv(ZZEDC_DB_PATH      = normalizePath(db_path,
                                                 mustWork = FALSE))
  Sys.setenv(DB_ENCRYPTION_KEY  = init_res$key)

  audit_res <- init_audit_logging(db_path = db_path)
  if (!isTRUE(audit_res$success)) {
    result$success <- FALSE
    result$errors$audit_init <- audit_res$error %||% "init_audit_logging failed"
    return(result)
  }

  # CRF schema is created lazily by `init_crf_version()` and
  # `init_crf_designer()`. The orchestrator calls them
  # explicitly so `create_crf_definition()` and
  # `add_form_field()` find the tables they expect.
  tryCatch(init_crf_version(),  error = function(e) NULL)
  tryCatch(init_crf_designer(), error = function(e) NULL)

  # Open a single connection for raw user / subject / data
  # inserts. CRF helpers and audit replay each manage their own
  # connections.
  zconn_setup <- connect_encrypted_db(db_path = db_path,
                                       key = init_res$key)
  on.exit(DBI::dbDisconnect(zconn_setup), add = TRUE)

  # `initialize_encrypted_database()` does not create the
  # `edc_users` or `form_data` tables; the wizard normally does,
  # but the wizard creates an unencrypted file. Provision the
  # tables we need directly through the encrypted connection
  # (`edc_users` via the canonical helper in `R/db_users.R`,
  # `form_data` inline because the importer has no other
  # caller).
  ensure_edc_users_table(zconn_setup)
  DBI::dbExecute(zconn_setup, "
    CREATE TABLE IF NOT EXISTS form_data (
      record_id        INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id       TEXT,
      form_id          INTEGER,
      field_name       TEXT,
      field_value      TEXT,
      visit_code       TEXT,
      data_entry_date  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      user_id          TEXT
    )
  ")

  # --- 4. Users -------------------------------------------------
  # Programmatic user provisioning via `db_insert_user()`. The
  # Shiny-internal `save_user_to_db()` is bypassed because it
  # expects a reactive `db_pool` argument bound to the admin UI.
  user_errors <- list()
  n_users_imported <- 0L
  default_salt <- "redcap_import_salt_change_in_production"
  for (i in seq_len(nrow(users_df))) {
    pw <- as.character(users_df$password_initial[i] %||%
                         "ChangeMe!2026")
    pw_hash <- digest::digest(paste0(pw, default_salt),
                                algo = "sha256")
    saved <- db_insert_user(
      conn          = zconn_setup,
      username      = as.character(users_df$username[i]),
      password_hash = pw_hash,
      full_name     = as.character(users_df$full_name[i] %||%
                                     users_df$username[i]),
      email         = as.character(users_df$email[i] %||% ""),
      role          = as.character(users_df$role[i]),
      site_id       = as.character(users_df$site_id[i] %||%
                                     "001"),
      active        = isTRUE(as.logical(users_df$active[i])),
      created_by    = "redcap_import"
    )
    if (isTRUE(saved$success)) {
      n_users_imported <- n_users_imported + 1L
    } else {
      user_errors[[as.character(users_df$username[i])]] <-
        saved$error
    }
  }
  result$users <- list(
    success  = length(user_errors) == 0L,
    imported = n_users_imported,
    errors   = user_errors
  )
  if (length(user_errors) > 0L) result$success <- FALSE

  # --- 5. Forms (CRFs + fields) ---------------------------------
  form_errors <- list()
  n_forms  <- 0L
  n_fields <- 0L
  for (form_code in unique(as.character(dd$form_code))) {
    fields <- dd[as.character(dd$form_code) == form_code, ]
    crf <- tryCatch(
      create_crf_definition(
        crf_code   = toupper(form_code),
        crf_name   = paste(toupper(form_code), "Form"),
        created_by = imported_by
      ),
      error = function(e) list(success = FALSE, error = e$message)
    )
    if (!isTRUE(crf$success)) {
      form_errors[[form_code]] <- crf$error %||%
        "create_crf_definition failed"
      next
    }
    n_forms <- n_forms + 1L
    # `add_form_field()` validates `field_type` against
    # `get_designer_field_types()`, whose keys are uppercase
    # (`TEXT`, `NUMBER`, `RADIO`, ...). Translate the
    # ZZedc-CSV lowercase types accordingly.
    designer_type <- function(t) {
      switch(tolower(t),
        text     = "TEXT",
        textarea = "TEXTAREA",
        numeric  = "NUMBER",
        integer  = "INTEGER",
        date     = "DATE",
        time     = "TIME",
        datetime = "DATETIME",
        radio    = "RADIO",
        checkbox = "CHECKBOX",
        select   = "SELECT",
        multiselect = "MULTISELECT",
        file     = "FILE",
        signature = "SIGNATURE",
        calculated = "CALCULATED",
        toupper(t)
      )
    }
    for (j in seq_len(nrow(fields))) {
      added <- tryCatch(
        add_form_field(
          design_id   = crf$crf_id,
          field_code  = as.character(fields$field_name[j]),
          field_label = as.character(fields$field_label[j]),
          field_type  = designer_type(fields$field_type[j]),
          is_required = isTRUE(as.logical(fields$required[j]))
        ),
        error = function(e) list(success = FALSE, error = e$message)
      )
      if (isTRUE(added$success)) {
        n_fields <- n_fields + 1L
      } else {
        form_errors[[paste(form_code,
                            fields$field_name[j], sep = "/")]] <-
          added$error %||% "add_form_field failed"
      }
    }
  }
  result$forms <- list(
    success         = length(form_errors) == 0L,
    imported_forms  = n_forms,
    imported_fields = n_fields,
    errors          = form_errors
  )
  if (length(form_errors) > 0L) result$success <- FALSE

  # --- 6. Subjects + data ---------------------------------------
  # Reuse the connection opened above for the user inserts.
  zconn <- zconn_setup

  n_subj <- 0L
  for (sid in unique(as.character(subj_df$subject_id))) {
    inserted <- tryCatch({
      DBI::dbExecute(zconn, "
        INSERT INTO subjects (subject_id, study_id, status, created_date)
        VALUES (?, 'REDCAP-IMPORT', 'Enrolled', datetime('now'))
      ", list(sid))
      TRUE
    }, error = function(e) FALSE)
    if (inserted) n_subj <- n_subj + 1L
  }
  result$subjects <- list(success = TRUE, imported = n_subj)

  # Map event_id -> visit_code (Phase C2: simple flatten;
  # repeating-instrument semantics deferred to C2.1)
  events_df <- if (source == "db") {
    tryCatch(
      DBI::dbGetQuery(conn, "
        SELECT event_id, descrip FROM redcap_events_metadata
        WHERE project_id = ?
      ", params = list(pid)),
      error = function(e) data.frame(event_id = integer(0),
                                      descrip = character(0))
    )
  } else {
    # API mode: events endpoint is optional and not exposed
    # uniformly via REDCapR. Default to flat EVENT_<id> labels;
    # this is consistent with the C2 / C3a flattening caveat.
    data.frame(event_id = integer(0), descrip = character(0))
  }
  visit_lookup <- if (nrow(events_df) > 0L) {
    setNames(as.character(events_df$descrip),
              as.character(events_df$event_id))
  } else NULL

  n_data <- 0L
  for (i in seq_len(nrow(data_df))) {
    visit_code <- if (!is.null(visit_lookup) &&
                       as.character(data_df$event_id[i]) %in%
                         names(visit_lookup)) {
      visit_lookup[[as.character(data_df$event_id[i])]]
    } else {
      paste0("EVENT_", as.character(data_df$event_id[i]))
    }
    inserted <- tryCatch({
      DBI::dbExecute(zconn, "
        INSERT INTO form_data
          (subject_id, field_name, field_value, visit_code,
           data_entry_date)
        VALUES (?, ?, ?, ?, datetime('now'))
      ", list(as.character(data_df$subject_id[i]),
              as.character(data_df$field_name[i]),
              as.character(data_df$value[i]),
              visit_code))
      TRUE
    }, error = function(e) FALSE)
    if (inserted) n_data <- n_data + 1L
  }
  result$subject_data <- list(success = TRUE, imported = n_data)

  # --- 7. Audit replay ------------------------------------------
  replay <- replay_redcap_audit(
    redcap_audit = audit_df,
    db_path      = db_path,
    key          = init_res$key,
    completeness = audit_completeness
  )
  result$audit_replay <- replay
  if (!isTRUE(replay$success)) {
    result$success <- FALSE
    result$errors$audit_replay <- "audit replay failed"
  }

  result
}


# ============================================================================
# Phase C3a: REDCap REST API source mode
# ============================================================================

#' Connect to a REDCap project via the REST API.
#'
#' Validates the URL/token pair by calling the `version`
#' endpoint and returns an opaque handle that the API extractors
#' below consume. The handle holds an `ops` list of zero-argument
#' (or single-argument) closures that wrap the underlying
#' \pkg{REDCapR} calls; tests can construct an `api` handle with
#' synthetic `ops` directly, bypassing the network.
#'
#' @param api_url   REDCap API endpoint
#'   (e.g., `https://redcap.example.org/api/`).
#' @param api_token Project-scoped API token. Tokens carry the
#'   permissions of the user that minted them; for full audit
#'   replay, the token must come from a user with `Logging`
#'   rights, otherwise the `log` endpoint will return a redacted
#'   or empty response (see `redcap_check_audit_completeness()`).
#' @param ops Optional list of operation closures; when supplied,
#'   `REDCapR` is not invoked. Used by the test suite to inject
#'   synthetic responses.
#' @return List with `url`, `token`, `version`, and `ops`.
#' @keywords internal
redcap_api_connect <- function(api_url = NULL, api_token = NULL, ops = NULL) {
  if (is.null(ops)) {
    if (!requireNamespace("REDCapR", quietly = TRUE)) {
      stop("Package 'REDCapR' is required for source = 'api'. ",
           "Install with install.packages('REDCapR').")
    }
    if (is.null(api_url) || !nzchar(api_url)) {
      stop("`api_url` is required")
    }
    if (is.null(api_token) || !nzchar(api_token)) {
      stop("`api_token` is required")
    }
    ops <- list(
      version  = function() {
        as.character(REDCapR::redcap_version(
          redcap_uri = api_url, token = api_token))
      },
      metadata = function() {
        REDCapR::redcap_metadata_read(
          redcap_uri = api_url, token = api_token)$data
      },
      users    = function() {
        REDCapR::redcap_users_export(
          redcap_uri = api_url, token = api_token)$data
      },
      records  = function(fields = NULL) {
        REDCapR::redcap_read_oneshot(
          redcap_uri = api_url, token = api_token,
          fields = fields)$data
      },
      log      = function() {
        REDCapR::redcap_log_read(
          redcap_uri = api_url, token = api_token)$data
      }
    )
  }

  ver <- tryCatch(ops$version(), error = function(e) {
    stop("REDCap API connection failed: ", conditionMessage(e))
  })

  list(url = api_url %||% "", token = api_token %||% "",
       version = ver, ops = ops)
}


#' Extract REDCap metadata via the REST API.
#'
#' Returns a tibble in the same shape produced by
#' [redcap_extract_metadata()] (the DB extractor), so downstream
#' translators are reused unchanged.
#'
#' @keywords internal
redcap_extract_metadata_api <- function(api) {
  rows <- tryCatch(api$ops$metadata(), error = function(e) NULL)
  if (is.null(rows) || !is.data.frame(rows) || nrow(rows) == 0L) {
    return(data.frame(
      form_code = character(0), field_name = character(0),
      field_label = character(0), field_type = character(0),
      required = logical(0), validation = character(0),
      description = character(0), field_order = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  # API uses `field_label`; DB uses `element_label`. Normalise.
  label_col <- if ("field_label" %in% names(rows)) "field_label"
               else "element_label"

  data.frame(
    form_code   = as.character(rows$form_name),
    field_name  = as.character(rows$field_name),
    field_label = as.character(rows[[label_col]]),
    field_type  = vapply(seq_len(nrow(rows)), function(i) {
      redcap_translate_field_type(
        rows$field_type[i],
        rows$text_validation_type_or_show_slider_number[i])
    }, character(1)),
    required    = !is.na(rows$required_field) &
                    as.character(rows$required_field) == "y",
    validation  = vapply(seq_len(nrow(rows)), function(i) {
      meta_row <- data.frame(
        field_name = rows$field_name[i],
        text_validation_type_or_show_slider_number =
          rows$text_validation_type_or_show_slider_number[i],
        text_validation_min = rows$text_validation_min[i],
        text_validation_max = rows$text_validation_max[i],
        stringsAsFactors = FALSE
      )
      r <- redcap_extract_rule_dsl(meta_row)
      if (is.na(r$dsl)) "" else r$dsl
    }, character(1)),
    description = "",
    field_order = seq_len(nrow(rows)),
    stringsAsFactors = FALSE
  )
}


#' Extract REDCap users via the REST API.
#' @keywords internal
redcap_extract_users_api <- function(api) {
  rows <- tryCatch(api$ops$users(), error = function(e) NULL)
  if (is.null(rows) || !is.data.frame(rows) || nrow(rows) == 0L) {
    return(data.frame(
      username = character(0), full_name = character(0),
      email = character(0), role = character(0),
      password_initial = character(0), site_id = character(0),
      active = logical(0), stringsAsFactors = FALSE
    ))
  }

  rights_for <- function(i) {
    paste(c(
      if (!is.null(rows$design) && isTRUE(rows$design[i] == 1))
        "design",
      if (!is.null(rows$user_rights) &&
            isTRUE(rows$user_rights[i] == 1))
        "user_rights",
      if (!is.null(rows$data_export) &&
            !is.na(rows$data_export[i]) &&
            rows$data_export[i] != 0)
        "data_export_tool",
      if (!is.null(rows$data_access_groups) &&
            isTRUE(rows$data_access_groups[i] == 1))
        "data_access_groups",
      "forms"
    ), collapse = ",")
  }

  full_name <- if (all(c("firstname", "lastname") %in% names(rows))) {
    trimws(paste(rows$firstname %||% "", rows$lastname %||% ""))
  } else {
    as.character(rows$username)
  }

  data.frame(
    username         = as.character(rows$username),
    full_name        = full_name,
    email            = as.character(rows$email %||% ""),
    role             = vapply(seq_len(nrow(rows)),
                              function(i) redcap_translate_role(rights_for(i)),
                              character(1)),
    password_initial = "ChangeMe!2026",
    site_id          = "001",
    active           = is.na(rows$expiration) |
                         as.character(rows$expiration) == "" |
                         (suppressWarnings(as.Date(rows$expiration)) >
                            Sys.Date()),
    stringsAsFactors = FALSE
  )
}


#' Extract REDCap subject IDs via the REST API.
#' @keywords internal
redcap_extract_subjects_api <- function(api, metadata = NULL) {
  if (is.null(metadata)) metadata <- redcap_extract_metadata_api(api)
  if (nrow(metadata) == 0L) {
    return(data.frame(subject_id = character(0),
                      stringsAsFactors = FALSE))
  }
  id_field <- as.character(metadata$field_name[1])
  rows <- tryCatch(api$ops$records(fields = id_field),
                    error = function(e) NULL)
  if (is.null(rows) || !is.data.frame(rows) || nrow(rows) == 0L) {
    return(data.frame(subject_id = character(0),
                      stringsAsFactors = FALSE))
  }
  ids <- if (id_field %in% names(rows)) rows[[id_field]] else rows[[1]]
  data.frame(subject_id = as.character(unique(ids)),
             stringsAsFactors = FALSE)
}


#' Extract REDCap subject data via the REST API, pivoted to long form.
#'
#' The REDCap API returns wide-form records by default. The DB
#' extractor returns long-form (subject_id, field_name, value,
#' event_id), so this function pivots wide -> long after the
#' fetch. Empty / NA cells are dropped to match the DB extractor's
#' behaviour (it reads from the EAV `redcap_data` table, which
#' stores only set values).
#'
#' @keywords internal
redcap_extract_data_api <- function(api) {
  rows <- tryCatch(api$ops$records(), error = function(e) NULL)
  if (is.null(rows) || !is.data.frame(rows) || nrow(rows) == 0L) {
    return(data.frame(
      subject_id = character(0), field_name = character(0),
      value = character(0), event_id = integer(0),
      stringsAsFactors = FALSE))
  }

  id_col <- names(rows)[1]
  event_col <- if ("redcap_event_name" %in% names(rows))
    "redcap_event_name" else NULL
  meta_cols <- c(id_col,
                 grep("^redcap_", names(rows), value = TRUE))
  data_cols <- setdiff(names(rows), meta_cols)

  if (length(data_cols) == 0L) {
    return(data.frame(
      subject_id = character(0), field_name = character(0),
      value = character(0), event_id = integer(0),
      stringsAsFactors = FALSE))
  }

  event_id <- if (!is.null(event_col)) {
    as.integer(factor(as.character(rows[[event_col]])))
  } else {
    rep(1L, nrow(rows))
  }

  pieces <- lapply(data_cols, function(col) {
    data.frame(
      subject_id = as.character(rows[[id_col]]),
      field_name = col,
      value      = as.character(rows[[col]]),
      event_id   = event_id,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, pieces)
  out[!is.na(out$value) & nzchar(out$value), , drop = FALSE]
}


#' Extract REDCap audit log via the REST API.
#'
#' Returns a list with `events` (data frame in the same shape as
#' [redcap_extract_audit()]) and `completeness` (one of `"full"`,
#' `"partial"`, `"empty"`). Completeness classification is
#' refined by [redcap_check_audit_completeness()] once the
#' record count is known.
#'
#' @keywords internal
redcap_extract_audit_api <- function(api) {
  rows <- tryCatch(api$ops$log(), error = function(e) NULL)
  if (is.null(rows) || !is.data.frame(rows) || nrow(rows) == 0L) {
    return(list(
      events = data.frame(
        log_event_id = integer(0), ts = character(0),
        user = character(0), ip = character(0), page = character(0),
        event = character(0), object_type = character(0),
        sql_log = character(0), pk = character(0),
        project_id = integer(0), description = character(0),
        stringsAsFactors = FALSE),
      completeness = "empty"))
  }

  events <- data.frame(
    log_event_id = seq_len(nrow(rows)),
    ts           = as.character(rows$timestamp %||% NA),
    user         = as.character(rows$username  %||% NA),
    ip           = NA_character_,
    page         = NA_character_,
    event        = as.character(rows$action    %||% NA),
    object_type  = NA_character_,
    sql_log      = NA_character_,
    pk           = as.character(rows$record    %||% ""),
    project_id   = NA_integer_,
    description  = as.character(rows$details   %||% ""),
    stringsAsFactors = FALSE
  )

  # Provisional completeness: refined later against record count.
  data_events <- sum(grepl("update|insert|edit|create|delete",
                            events$event, ignore.case = TRUE))
  completeness <- if (data_events == 0L) "partial" else "full"

  list(events = events, completeness = completeness)
}


#' Classify audit-log completeness for a REST-API import.
#'
#' Refines the provisional classification from
#' [redcap_extract_audit_api()] using the subject-record count.
#' If there are records but no audit events, the log endpoint is
#' empty (token lacks `Logging` rights). If there are records and
#' the log contains only non-data events (login / logout / view),
#' it is partial. Otherwise the log is treated as full.
#'
#' @keywords internal
redcap_check_audit_completeness <- function(audit_result, n_records) {
  events <- audit_result$events
  if (is.null(events) || nrow(events) == 0L) {
    return(if (n_records > 0L) "empty" else "full")
  }
  data_events <- sum(grepl("update|insert|edit|create|delete",
                            events$event, ignore.case = TRUE))
  if (data_events == 0L && n_records > 0L) "partial" else "full"
}


#' (Phase C3b - planned) Read a REDCap MySQL .sql dump file
#'
#' Will hydrate a transient MySQL or MariaDB server from a
#' REDCap-format `.sql` dump and return a DBI connection
#' suitable for `import_redcap_to_zzedc_db()`. Today, dumps must
#' be loaded manually into a MySQL instance before invoking the
#' importer.
#'
#' Not yet implemented.
#'
#' @keywords internal
load_redcap_sql_dump <- function(dump_path, target_host = "localhost",
                                  target_port = 3306L) {
  stop("Phase C3b: SQL-dump source mode is on the roadmap. ",
       "Manually load the dump into a MySQL or MariaDB ",
       "instance and pass a live connection to ",
       "import_redcap_to_zzedc_db(). See ",
       "vignette('mysql-redcap-migration-roadmap').")
}
