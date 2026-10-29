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
#' for `SELECT`/`RADIO` choice lists) for the given form and returns
#' a named list in the shape [renderPanel()] expects.
#'
#' The Google Sheets/CSV `Data_Dictionary` import does not currently
#' capture a choices/options column, so `designer_field_options` is
#' typically empty for an imported form even though the field is
#' marked `SELECT` or `RADIO`. Rendering a choice widget with no
#' choices to offer is worse than a plain text box, so a `SELECT`/
#' `RADIO` field with no rows in `designer_field_options` is rendered
#' as `"text"` instead; this is a known limitation of the import
#' path, not a limitation of this renderer.
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
    if (type %in% c("select", "radio") && is.null(choices)) {
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
