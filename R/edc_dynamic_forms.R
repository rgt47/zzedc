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
      "       is_required, placeholder, help_text, default_value, widget_file,",
      "       help_detail",
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
      choices     = choices,
      widget      = if (!is.na(fr$widget_file)) fr$widget_file else NULL,
      help_detail = if (!is.na(fr$help_detail)) fr$help_detail else NULL
    )
  })
  stats::setNames(metadata, fields$field_code)
}


#' Tracking-ID prefix convention for a CRF form, if one is defined
#'
#' Only the manuscripts form currently has an enforced tracking ID
#' convention (`PUB-<year>-<n>`, assigned in sequence per year by
#' [next_manuscript_tracking_id()]). Returns `NULL` for any other
#' form (or an unrecognized `crf_code`), so
#' [validate_tracking_id_format()] is a no-op there.
#'
#' @param crf_code A form's `crf_definitions.crf_code`, in any case.
#' @return A single prefix string, or `NULL`.
#' @keywords internal
tracking_id_prefix_for_form <- function(crf_code) {
  prefixes <- c(manuscripts = "PUB")
  key <- tolower(crf_code %||% "")
  if (!key %in% names(prefixes)) return(NULL)
  prefixes[[key]]
}

#' Human-readable description of a form's tracking-ID pattern
#'
#' Used by both [validate_tracking_id_format()]'s error message and
#' [tracking_id_format_hint()], so the two always describe the same
#' convention in the same words.
#'
#' @param prefix A tracking-ID prefix, e.g. `"PUB"`.
#' @return A single string, e.g. `'PUB-YYYY-N (e.g. "PUB-2026-001")'`.
#' @keywords internal
.tracking_id_pattern_text <- function(prefix) {
  sprintf('%s-YYYY-N (e.g. "%s-%s-001")', prefix, prefix, format(Sys.Date(), "%Y"))
}

#' Format hint for a form's tracking-ID field, if it has a convention
#'
#' Meant to sit permanently beneath the field as `renderPanel()`'s
#' own `help` text -- always visible, not hover-dependent -- as well
#' as in the field's `title` attribute (the EDC tab overrides that
#' with the specific error message instead, once there is one; see
#' `inst/app/edc.R`'s `edc_crf_field_flags` output).
#'
#' @param crf_code The form's `crf_code`, or `NULL`.
#' @return A single string, or `NULL` if the form has no
#'   tracking-ID convention.
#' @keywords internal
tracking_id_format_hint <- function(crf_code) {
  prefix <- tracking_id_prefix_for_form(crf_code)
  if (is.null(prefix)) return(NULL)
  sprintf("Format: %s, unique within its year.", .tracking_id_pattern_text(prefix))
}

#' Check a tracking ID against its form's prefix-year-number convention
#'
#' @param value The submitted `tracking_id` value.
#' @param crf_code The form's `crf_code` (e.g. `"manuscripts"`).
#' @return `NULL` if the form has no tracking-ID convention, or
#'   `value` is blank, or `value` matches it; otherwise an error
#'   message string.
#' @keywords internal
validate_tracking_id_format <- function(value, crf_code) {
  prefix <- tracking_id_prefix_for_form(crf_code)
  if (is.null(prefix) || is.null(value) || !nzchar(trimws(value))) {
    return(NULL)
  }
  pattern <- sprintf("^%s-[0-9]{4}-[0-9]+$", prefix)
  if (grepl(pattern, value)) {
    return(NULL)
  }
  sprintf("Tracking ID must match %s", .tracking_id_pattern_text(prefix))
}

#' Validate a CRF submission's field values against their metadata
#'
#' Checks required-field presence, for choice-type fields
#' (`select`/`radio`/`checkbox_group`) with a defined choice set,
#' that every non-blank submitted value is actually a member of it,
#' and, when `crf_code` names a form with a tracking-ID convention
#' (see [tracking_id_prefix_for_form()]), that `tracking_id` matches
#' it. A blank, non-required field is never flagged. Pulled out as a
#' plain function (rather than inlined in the EDC tab's Shiny
#' observer) so it is unit-testable outside Shiny and so the EDC
#' tab can run the exact same check twice for two different
#' purposes: live, non-blocking inline flags as the user fills in
#' the form (via [crf_live_invalid_fields()], which only surfaces
#' non-`"required"`-kind problems -- an empty required field is
#' expected while a form is still being filled in, not an error to
#' flag mid-entry), and the full gate run once at submit time
#' (every error kind, including `"required"`), which still blocks
#' saving an incomplete or invalid record.
#'
#' Uniqueness of `tracking_id` within its year, and every
#' cross-field/range rule authored in the study's data dictionary
#' (e.g. "acceptance date must be on or after submission date"), are
#' separate, database-backed checks (see
#' [tracking_id_already_used()] and [validate_dsl_rules()]
#' respectively); neither is performed here since this function is
#' deliberately pure and database-free.
#'
#' @param field_data Named list of submitted field values, keyed by
#'   `field_code` (same shape passed to [save_crf_entry()]).
#' @param metadata Field metadata as returned by
#'   [get_crf_field_metadata()].
#' @param crf_code The form's `crf_code`, or `NULL` to skip the
#'   tracking-ID format check entirely.
#' @return `list(valid=, errors=)`. `errors` is a named list (by
#'   `field_code`) of `list(kind=, message=)`, `kind` one of
#'   `"required"`, `"invalid_choice"`, or `"invalid_format"`.
#' @keywords internal
validate_crf_submission <- function(field_data, metadata, crf_code = NULL) {
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

    if (f == "tracking_id" && !is.null(crf_code)) {
      fmt_error <- validate_tracking_id_format(as.character(v), crf_code)
      if (!is.null(fmt_error)) {
        errors[[f]] <- list(kind = "invalid_format", message = fmt_error)
      }
    }
  }

  list(valid = length(errors) == 0, errors = errors)
}


#' Short, kind-specific advice for resolving a live validation error
#'
#' Keyed on the same `kind` values [validate_crf_submission()],
#' [tracking_id_already_used()], and [validate_dsl_rules()] already
#' assign to an error -- this is purely presentation (what to tell
#' the user to do about it), not a new error classification.
#' Appended to the error's own message in the EDC tab's hint-icon
#' tooltip (see `inst/app/edc.R`'s `edc_crf_field_flags` output), so
#' hovering the icon gives both what is wrong and how to fix it, not
#' the message alone.
#'
#' @param kind One of `"required"`, `"invalid_choice"`,
#'   `"invalid_format"`, `"duplicate"`, `"dsl_rule"`, or any other
#'   string (falls back to `""`, i.e. no advice added).
#' @return A single string, possibly `""`.
#' @keywords internal
field_error_resolution_hint <- function(kind) {
  switch(
    kind,
    required = "Fill in this field before submitting.",
    invalid_choice = "Pick one of the listed options; free text is not accepted here.",
    invalid_format = "Match the field's required format exactly, including punctuation.",
    duplicate = paste(
      "This ID is already used by another entry.",
      "Use the next free ID, or confirm you are not re-entering an existing record."
    ),
    dsl_rule = paste(
      "This value breaks a cross-field rule defined for this form;",
      "check it against the related field(s)."
    ),
    ""
  )
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
#' @param crf_code The form's `crf_code`, or `NULL` to skip the
#'   tracking-ID format check (see [validate_crf_submission()]).
#' @return Character vector of flag messages, in field order; empty
#'   (`character(0)`) when nothing is currently flagged.
#' @keywords internal
crf_live_invalid_fields <- function(field_data, metadata, crf_code = NULL) {
  result <- validate_crf_submission(field_data, metadata, crf_code = crf_code)
  live <- Filter(function(e) e$kind != "required", result$errors)
  vapply(live, function(e) e$message, character(1))
}


#' Reset a dynamic CRF form's inputs after a successful submission
#'
#' [renderPanel()] gives every field in a freshly rendered form a
#' deterministic starting value (an empty string for text fields,
#' today's date for date fields, the first choice for select/radio
#' fields, nothing selected for a checkbox group). The EDC tab's
#' submit handler previously left every input holding whatever the
#' user had just typed, so a second entry on the same form always
#' started pre-filled with the first entry's values instead of a
#' blank form. This restores each field named in `metadata` to that
#' same fresh-render default via the matching `shiny::update*Input()`
#' call, so a successful submit leaves the form ready for the next
#' entry.
#'
#' Only the field types [map_designer_field_type()] actually
#' produces (`text`, `numeric`, `date`, `select`, `radio`,
#' `checkbox_group`) are handled explicitly; any other type falls
#' back to the text-input reset, matching [renderPanel()]'s own
#' fallback for an unrecognized type. The text-input reset uses
#' `field_config$value` when the caller has set one (e.g. the EDC
#' tab's submit handler recomputes the next free tracking ID before
#' calling this, for forms with a tracking-ID convention), and
#' falls back to blank otherwise.
#'
#' @param session The current Shiny session.
#' @param metadata Field metadata as returned by
#'   [get_crf_field_metadata()].
#' @return `NULL`, invisibly. Called for its side effect.
#' @keywords internal
reset_crf_field_inputs <- function(session, metadata) {
  for (field_name in names(metadata)) {
    field_config <- metadata[[field_name]] %||% list(type = "text")
    switch(
      field_config$type,
      "numeric" = shiny::updateNumericInput(session, field_name, value = NA),
      "date" = shiny::updateDateInput(session, field_name, value = Sys.Date()),
      "select" = shiny::updateSelectInput(
        session, field_name, selected = field_config$choices[1]
      ),
      "radio" = shiny::updateRadioButtons(
        session, field_name, selected = field_config$choices[1]
      ),
      "checkbox_group" = shiny::updateCheckboxGroupInput(
        session, field_name, selected = character(0)
      ),
      shiny::updateTextInput(session, field_name, value = field_config$value %||% "")
    )
  }
  invisible(NULL)
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
