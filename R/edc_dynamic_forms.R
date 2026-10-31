#' Internal helpers for rendering the EDC tab from imported CRF
#' definitions
#'
#' `setup_zzedc_from_gsheets()` (and the CSV import path) populate
#' `crf_definitions` (one row per imported form) and
#' `designer_fields` (one row per field, keyed to `crf_definitions`
#' via `designer_fields$design_id == crf_definitions$crf_id`).
#' Previously `inst/app/edc.R` never read either table; it only
#' ever rendered a demo form from study-specific `forms/*.R` files.
#' These helpers translate the imported CRF tables into the field
#' metadata format [renderPanel()] already understands, so the EDC
#' tab can render and save against a study's actual imported forms
#' with no intermediate generated files.
#'
#' @name edc_dynamic_forms
#' @keywords internal
NULL


#' List the CRF forms available for data entry
#'
#' @param conn A DBI connection (or pool object).
#' @return A data frame with columns `crf_id`, `crf_code`,
#'   `crf_name`, one row per form in `crf_definitions`. Zero rows
#'   when no CRF has been imported/defined yet.
#' @keywords internal
get_active_crf_forms <- function(conn) {
  DBI::dbGetQuery(
    conn,
    "SELECT crf_id, crf_code, crf_name FROM crf_definitions ORDER BY crf_id"
  )
}


#' Map a `designer_fields.field_type` value to a [renderPanel()] type
#'
#' `designer_fields.field_type` is written in upper case by the
#' Google Sheets/CSV importers (`TEXT`, `NUMBER`, `DATE`, `SELECT`,
#' `RADIO`, ...); [renderPanel()]'s `field_metadata` contract uses
#' lower-case type strings (`"text"`, `"numeric"`, ...). Unknown or
#' missing values fall back to `"text"` rather than erroring, since
#' a plain text box is always a safe default for an unanticipated
#' type.
#'
#' @param x A single `field_type` string.
#' @return A lower-case type string understood by [renderPanel()].
#' @keywords internal
map_designer_field_type <- function(x) {
  switch(
    toupper(x %||% ""),
    TEXT        = "text",
    NUMBER      = "numeric",
    DATE        = "date",
    SELECT      = "select",
    RADIO       = "radio",
    MULTISELECT = "checkbox_group",
    "text"
  )
}


#' Build [renderPanel()] field metadata for one imported CRF form
#'
#' Reads `designer_fields` (and, where present, `designer_field_options`
#' for `SELECT`/`RADIO`/`MULTISELECT` choice lists) for the given
#' form and returns a named list in the shape [renderPanel()]
#' expects.
#'
#' The Google Sheets/CSV `Data_Dictionary` import populates
#' `designer_field_options` only when a choice-type field's
#' `validation` cell holds an `in(...)` list (see
#' `parse_gsheets_choice_list()`); a field authored without one, or
#' imported before this import-time support existed, still has no
#' rows there even though it is marked `SELECT`/`RADIO`/
#' `MULTISELECT`. Rendering a choice widget with no choices to offer
#' is worse than a plain text box, so such a field is rendered as
#' `"text"` instead; this is a property of the data, not a
#' limitation of this renderer.
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_id The `crf_definitions.crf_id` / `designer_fields.design_id`
#'   identifying the form.
#' @return A named list (names are `field_code`s, in `designer_fields`'
#'   row order) suitable as the `field_metadata` argument to
#'   [renderPanel()]. An empty list when the form has no fields.
#' @keywords internal
get_crf_field_metadata <- function(conn, crf_id) {
  fields <- DBI::dbGetQuery(
    conn,
    paste(
      "SELECT field_id, field_code, field_label, field_type,",
      "       is_required, placeholder, help_text, default_value",
      "FROM designer_fields",
      "WHERE design_id = ?",
      "ORDER BY field_row, field_column, field_id"
    ),
    params = list(crf_id)
  )
  if (nrow(fields) == 0) return(list())

  placeholders <- paste(rep("?", nrow(fields)), collapse = ", ")
  options <- DBI::dbGetQuery(
    conn,
    sprintf(
      paste(
        "SELECT field_id, option_value, option_label",
        "FROM designer_field_options",
        "WHERE field_id IN (%s)",
        "ORDER BY field_id, option_order"
      ),
      placeholders
    ),
    params = as.list(fields$field_id)
  )

  metadata <- lapply(seq_len(nrow(fields)), function(i) {
    fr <- fields[i, ]
    type <- map_designer_field_type(fr$field_type)

    opts <- options[options$field_id == fr$field_id, , drop = FALSE]
    choices <- if (nrow(opts) > 0) {
      stats::setNames(opts$option_value, opts$option_label)
    } else {
      NULL
    }
    if (type %in% c("select", "radio", "checkbox_group") && is.null(choices)) {
      type <- "text"
    }

    list(
      type        = type,
      label       = fr$field_label,
      required    = isTRUE(fr$is_required == 1),
      placeholder = if (!is.na(fr$placeholder)) fr$placeholder else NULL,
      help        = if (!is.na(fr$help_text)) fr$help_text else NULL,
      value       = if (!is.na(fr$default_value)) fr$default_value else NULL,
      choices     = choices
    )
  })
  stats::setNames(metadata, fields$field_code)
}


#' Validate a CRF submission's field values against their metadata
#'
#' Checks required-field presence and, for choice-type fields
#' (`select`/`radio`/`checkbox_group`) with a defined choice set,
#' that every non-blank submitted value is actually a member of it.
#' A blank, non-required field is never flagged. Pulled out as a
#' plain function (rather than inlined in the EDC tab's Shiny
#' observer) so it is unit-testable outside Shiny and so the EDC
#' tab can run the exact same check twice for two different
#' purposes: live, non-blocking inline flags as the user fills in
#' the form (via [crf_live_invalid_fields()], which only surfaces
#' `"invalid_choice"`-kind problems -- an empty required field is
#' expected while a form is still being filled in, not an error to
#' flag mid-entry), and the full gate run once at submit time
#' (every error kind, including `"required"`), which still blocks
#' saving an incomplete or invalid record.
#'
#' @param field_data Named list of submitted field values, keyed by
#'   `field_code` (same shape passed to [save_crf_entry()]).
#' @param metadata Field metadata as returned by
#'   [get_crf_field_metadata()].
#' @return `list(valid=, errors=)`. `errors` is a named list (by
#'   `field_code`) of `list(kind=, message=)`, `kind` one of
#'   `"required"` or `"invalid_choice"`.
#' @keywords internal
validate_crf_submission <- function(field_data, metadata) {
  errors <- list()

  for (f in names(metadata)) {
    m <- metadata[[f]]
    v <- field_data[[f]]
    is_blank <- is.null(v) || all(is.na(v)) ||
      all(!nzchar(trimws(as.character(v))))

    if (isTRUE(m$required) && is_blank) {
      errors[[f]] <- list(kind = "required",
                           message = sprintf("%s is required", m$label %||% f))
      next
    }
    if (is_blank) next

    if (m$type %in% c("select", "radio", "checkbox_group") &&
          !is.null(m$choices)) {
      submitted <- as.character(v)
      submitted <- submitted[nzchar(trimws(submitted))]
      bad <- setdiff(submitted, unname(m$choices))
      if (length(bad) > 0) {
        errors[[f]] <- list(
          kind = "invalid_choice",
          message = sprintf("%s: \"%s\" is not one of the listed options",
                             m$label %||% f, paste(bad, collapse = '", "'))
        )
      }
    }
  }

  list(valid = length(errors) == 0, errors = errors)
}


#' Live, non-blocking field flags for a CRF form in progress
#'
#' Filters [validate_crf_submission()]'s result down to the subset
#' meant to be shown while the user is still filling in the form --
#' i.e. everything except `"required"`-kind errors, since a field
#' simply not filled in yet is not an invalid entry. Intended to be
#' called from a reactive that re-runs on every keystroke/selection
#' change, so the EDC tab can flag a bad entry (e.g. a value no
#' longer in a field's choice set after a CRF definition change)
#' immediately, without disabling input or the submit button.
#'
#' @param field_data Named list of currently entered field values.
#' @param metadata Field metadata as returned by
#'   [get_crf_field_metadata()].
#' @return Character vector of flag messages, in field order; empty
#'   (`character(0)`) when nothing is currently flagged.
#' @keywords internal
crf_live_invalid_fields <- function(field_data, metadata) {
  result <- validate_crf_submission(field_data, metadata)
  live <- Filter(function(e) e$kind != "required", result$errors)
  vapply(live, function(e) e$message, character(1))
}


#' Save a submitted CRF entry to `data_entries`
#'
#' Thin wrapper over [ensure_data_entries_table()]/
#' [db_insert_data_entry()] for CRF-form submissions from the EDC
#' tab's dynamic (imported-form) rendering path, distinct from the
#' study-specific `forms/save.R` used by the demo scaffold path.
#'
#' The `data_entries` table requires a non-empty `subject_id`. The
#' CRF forms imported by this package track one record per
#' submission (a manuscript, a course, a committee term, ...), not
#' a subject's repeated visits, so there is no natural "subject" to
#' key on. `tracking_id` (present and required on every imported
#' form seen so far) is used as the `subject_id` surrogate when
#' present; if a form has no `tracking_id` field, or it was left
#' blank, a timestamp-based placeholder is used instead so the
#' insert can still proceed rather than failing the whole
#' submission over a cosmetic identifier.
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_code The form's `crf_definitions.crf_code` (used,
#'   lower-cased, as `data_entries.form_name`, matching the
#'   lower-case `form_code` convention already used by
#'   `dsl_validation_rules`).
#' @param field_data Named list of submitted field values, keyed by
#'   `field_code`.
#' @param created_by String identifying who submitted the entry.
#' @return The `list(success=, entry_id=)` / `list(success=FALSE,
#'   error=)` result from [db_insert_data_entry()].
#' @keywords internal
save_crf_entry <- function(conn, crf_code, field_data, created_by) {
  ensure_data_entries_table(conn)

  subject_id <- field_data$tracking_id
  if (is.null(subject_id) || !nzchar(trimws(as.character(subject_id)))) {
    subject_id <- paste0(
      toupper(crf_code), "-",
      format(Sys.time(), "%Y%m%d%H%M%OS3", tz = "UTC")
    )
  }

  db_insert_data_entry(
    conn,
    subject_id  = as.character(subject_id),
    form_name   = tolower(crf_code),
    data        = field_data,
    is_complete = TRUE,
    created_by  = created_by
  )
}
