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
    # CALCULATED was already a valid designer field type
    # (get_designer_field_types(), R/crf_designer.R) and importable
    # via map_gsheets_field_type()'s "calculated" vocabulary, but
    # had no rendering here at all -- renderPanel()'s
    # "readonly_display" case (R/renderpanels.R) is the actual
    # implementation; used first for randomize_next_subject()'s
    # system-set treatment arm (R/randomization_module.R), which
    # must never be a user-editable field.
    CALCULATED  = "readonly_display",
    # FILE and TEXTAREA had no case here, so both fell through to
    # the "text" default below -- a FILE- or TEXTAREA-type field
    # imported from a Data_Dictionary rendered as a plain one-line
    # text box, never reaching renderPanel()'s "file" =
    # fileInput(...) or "textarea" = tags$textarea(...) cases at all.
    FILE        = "file",
    TEXTAREA    = "textarea",
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
  # require_double_entry (2026-11-19) is added to designer_fields by
  # init_crf_designer()'s idempotent ALTER (R/crf_designer.R), but
  # that function is only ever called from the REDCap/Google-Sheets
  # import orchestrators, not unconditionally at app startup -- so an
  # existing database that has never run either import since this
  # column was introduced may not have it yet. Selecting a column
  # that doesn't exist would break every form's metadata lookup, not
  # just double-data-entry's, so this checks first and selects a
  # literal FALSE in its place when absent, rather than requiring
  # every caller to have migrated first.
  has_dde_col <- "require_double_entry" %in%
    DBI::dbListFields(conn, "designer_fields")
  fields <- DBI::dbGetQuery(
    conn,
    paste(
      "SELECT field_id, field_code, field_label, field_type,",
      "       is_required, placeholder, help_text, default_value, widget_file,",
      "       help_detail, field_row, field_column, field_width,",
      if (has_dde_col) "require_double_entry" else "0 AS require_double_entry",
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
      help_detail = if (!is.na(fr$help_detail)) fr$help_detail else NULL,
      # Carried through for renderPanel()'s `columns` argument
      # (R/renderpanels.R): previously fetched (the ORDER BY above)
      # and never placed anywhere a caller could read them, so the
      # multi-column layout these columns exist to drive had no data
      # to act on. Defaults match designer_fields' own column
      # defaults (R/crf_designer.R) for a metadata list built by a
      # caller that never set them (e.g. the correction module's
      # single-field renderPanel() call).
      field_row    = if (!is.na(fr$field_row)) as.integer(fr$field_row) else 1L,
      field_column = if (!is.na(fr$field_column)) as.integer(fr$field_column) else 1L,
      field_width  = if (!is.na(fr$field_width)) as.integer(fr$field_width) else 100L,
      # Double-data-entry opt-in (R/double_data_entry.R); see the
      # has_dde_col fallback above for why this can never be NA here.
      require_double_entry = isTRUE(fr$require_double_entry == 1)
    )
  })
  stats::setNames(metadata, fields$field_code)
}


#' Tracking-ID prefix convention for a CRF form, if one is defined
#'
#' Only the manuscripts form has a convention built into the package
#' (`PUB-<year>-<n>`, assigned in sequence per year by
#' [next_manuscript_tracking_id()]). Every other form's convention is
#' authored per-study, not in code: the Setup form designer's
#' `tracking_id` field `help_text` (e.g. `"Format: JRV-YYYY-NNN (e.g.
#' JRV-2026-001)"`) is both what the EDC tab already shows the user
#' (see `inst/app/edc.R`'s `edc_crf_field_flags`, which falls back to
#' a field's own `help` text for every form but manuscripts) and, via
#' `help_text`, the only record of that form's intended prefix -- so
#' it is parsed from there rather than requiring a second, hardcoded
#' table entry per form (which nothing kept in sync with the
#' designer, and had already let a `journal_reviews` entry's
#' `tracking_id` be saved as `PUB-2026-001`, unflagged, before this
#' fallback existed).
#'
#' @param crf_code A form's `crf_definitions.crf_code`, in any case.
#' @param help_text The form's `tracking_id` field's own `help_text`
#'   (`designer_fields.help_text`), if known; used only when
#'   `crf_code` has no built-in convention.
#' @return A single prefix string, or `NULL`.
#' @keywords internal
tracking_id_prefix_for_form <- function(crf_code, help_text = NULL) {
  prefixes <- c(manuscripts = "PUB")
  key <- tolower(crf_code %||% "")
  if (key %in% names(prefixes)) return(prefixes[[key]])
  .tracking_id_prefix_from_help_text(help_text)
}

#' Parse a tracking-ID prefix out of a field's own "Format: ..." help text
#'
#' Matches the convention the Setup form designer's help text already
#' uses (`"Format: <PREFIX>-YYYY-NNN"`, optionally followed by more
#' text such as an `(e.g. ...)` example) -- the same string
#' [tracking_id_format_hint()] and the designer UI both display, so
#' there is exactly one place this convention is authored.
#'
#' @param help_text A field's `help_text`, or `NULL`/`NA`.
#' @return A single prefix string, or `NULL` if `help_text` doesn't
#'   match the convention.
#' @keywords internal
.tracking_id_prefix_from_help_text <- function(help_text) {
  if (is.null(help_text) || is.na(help_text) || !nzchar(help_text)) return(NULL)
  m <- regmatches(help_text, regexpr("Format:\\s*([A-Za-z0-9]+)-YYYY-N+", help_text))
  if (length(m) == 0 || !nzchar(m)) return(NULL)
  sub("Format:\\s*([A-Za-z0-9]+)-YYYY-N+", "\\1", m)
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
#' @param help_text The `tracking_id` field's own `help_text`, used
#'   as a fallback to find the convention when `crf_code` has none
#'   built in (see [tracking_id_prefix_for_form()]).
#' @return `NULL` if the form has no tracking-ID convention, or
#'   `value` is blank, or `value` matches it; otherwise an error
#'   message string.
#' @keywords internal
validate_tracking_id_format <- function(value, crf_code, help_text = NULL) {
  prefix <- tracking_id_prefix_for_form(crf_code, help_text = help_text)
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
#' and, when the form has a tracking-ID convention -- `crf_code`
#' names one built into the package, or `metadata$tracking_id$help`
#' declares one itself (see [tracking_id_prefix_for_form()]) -- that
#' `tracking_id` matches it. A blank, non-required field is never
#' flagged. Pulled out as a
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

    if (f == "tracking_id") {
      fmt_error <- validate_tracking_id_format(as.character(v), crf_code, help_text = m$help)
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
#' blank form. This restores each field named in `metadata` to a
#' blank starting point via the matching `shiny::update*Input()`
#' call, so a successful submit leaves the form ready for the next
#' entry.
#'
#' A date field is cleared to blank here rather than reset to
#' today's date (unlike [renderPanel()]'s own first-render default):
#' a just-submitted entry's dates (e.g. a manuscript's submission or
#' acceptance date) have no reason to carry over, or to default to
#' today, for an unrelated next entry. `shiny::updateDateInput(value
#' = NA)` is not used for this even though it is the documented
#' idiom and does send the client a correctly-formed "clear" message
#' -- verified directly against both `dateInputBinding`'s own
#' `receiveMessage()`/`setValue()` and `shiny:::toJSON()`'s
#' NA-to-`null` serialization -- because the bundled
#' bootstrap-datepicker widget's own `update()` call (what
#' `setValue(el, null)` invokes) can re-populate the field from
#' today's date instead of leaving it blank, confirmed live against
#' this application. A file field has no `shiny::update*Input()` of
#' its own at all -- there is no `updateFileInput()` -- and clearing
#' Shiny's server-side value alone would leave a file still visibly
#' "selected" in the widget, confusingly implying it would be
#' resubmitted.
#'
#' Both of those -- a datepicker's own `clearDates()` method, and
#' directly emptying a file input's DOM value -- need client-side
#' JavaScript, which is why both cases send a custom message
#' (`session$sendCustomMessage()`) instead of calling an
#' `update*Input()` function. `shinyjs::runjs()`/`shinyjs::reset()`
#' were tried first for this, since both are already a hard
#' dependency and this is exactly what they are for, but both
#' resolve their own session via `shinyjs:::getSession()` /
#' `shiny::getDefaultReactiveDomain()` rather than using the
#' `session` argument actually passed in here, and that lookup was
#' confirmed, live, not to resolve to this application's session;
#' `shinyjs::reset()` additionally has no working path for a "file"
#' field at all regardless of that, since internally it waits for
#' the client to report the reset element's detected widget type and
#' calls the matching `shiny::update<Type>Input()`, and there is no
#' `updateFileInput()` for it to find. Sending the message directly
#' through the `session` object already in hand avoids depending on
#' either of those paths. The two
#' `Shiny.addCustomMessageHandler()` calls these messages rely on are
#' registered by [.zzedc_crf_reset_message_handlers()], included once
#' in the page `<head>` by both `inst/app/ui.R` and
#' `inst/app/gsheets_ui_integration.R`.
#'
#' Only the field types [map_designer_field_type()] actually
#' produces (`text`, `textarea`, `numeric`, `date`, `select`,
#' `radio`, `checkbox_group`, `file`) are handled explicitly; any
#' other type falls back to the text-input reset, matching
#' [renderPanel()]'s own fallback for an unrecognized type. The
#' text-input reset uses `field_config$value` when the caller has
#' set one (e.g. the EDC tab's submit handler recomputes the next
#' free tracking ID before calling this, for forms with a
#' tracking-ID convention), and falls back to blank otherwise.
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
      # updateDateInput(value = NA) looked like the standard idiom
      # to clear a dateInput, and does send the client a message the
      # dateInputBinding's own receiveMessage()/setValue() correctly
      # interpret as "clear" (value: null, after NA's expected
      # shiny:::toJSON(na = "null") serialization) -- verified by
      # reading both ends of that path directly. It still did not
      # visually clear the field, confirmed live: the bundled
      # bootstrap-datepicker widget's own update() call (what
      # setValue(el, null) invokes after emptying the input) can
      # re-populate itself from today's date rather than staying
      # blank. clearDates() is that same plugin's own, dedicated
      # method for actually emptying a datepicker and does not have
      # this problem, so the client is told to call it directly
      # instead (see .zzedc_crf_reset_message_handlers()).
      #
      # shinyjs::runjs()/shinyjs::reset() were tried first for this
      # and the "file" case below, since both are already a hard
      # dependency and this is exactly what they are for -- but both
      # resolve their own session via shinyjs:::getSession() /
      # shiny::getDefaultReactiveDomain() rather than using the
      # `session` argument actually passed in here, and that lookup
      # was confirmed live, directly, not to resolve to this
      # application's session (shinyjs::reset() additionally has no
      # working path for a "file" field at all regardless: internally
      # it waits for the client to report the reset element's
      # detected widget type and calls the matching
      # shiny::update<Type>Input(), and there is no
      # updateFileInput()). Sending the message directly through the
      # `session` object already in hand avoids depending on that
      # lookup at all.
      "date" = session$sendCustomMessage(
        "zzedc-clear-date-input", field_name
      ),
      "select" = shiny::updateSelectInput(
        session, field_name, selected = field_config$choices[1]
      ),
      "radio" = shiny::updateRadioButtons(
        session, field_name, selected = field_config$choices[1]
      ),
      "checkbox_group" = shiny::updateCheckboxGroupInput(
        session, field_name, selected = character(0)
      ),
      "textarea" = shiny::updateTextAreaInput(session, field_name, value = ""),
      # There is no updateFileInput(); clearing the client's actual
      # browser-held file selection (not just Shiny's server-side
      # value, which would leave a file still visibly "selected" in
      # the widget) needs direct DOM access on the client, same
      # reasoning and the same explicit-`session` approach as "date"
      # above.
      "file" = session$sendCustomMessage(
        "zzedc-clear-file-input", field_name
      ),
      shiny::updateTextInput(session, field_name, value = field_config$value %||% "")
    )
  }
  invisible(NULL)
}


#' Pre-fill a dynamic CRF form's inputs from a resumed draft's values
#'
#' The "Continue" action on an open ("Save and Finish Later",
#' `is_complete = 0`) `data_entries` row only ever appears next to a
#' row already filtered to the form currently rendered on screen
#' (`inst/app/edc.R`'s `crf_entries_table` lists only the selected
#' form's entries), so unlike a brand-new form render, the inputs
#' this needs to fill already exist in the DOM -- this uses
#' `shiny::update*Input()` directly, the mirror image of
#' [reset_crf_field_inputs()], rather than re-rendering through
#' `renderUI()`'s `field_config$value`.
#'
#' `values` is a parsed `data_json` (`jsonlite::fromJSON(...,
#' simplifyVector = FALSE)`), so a given field's value can be `NULL`
#' (stored JSON `null`), a zero-length `list()` (a cleared
#' `dateInput()`), a length-1 value, or a longer vector (a
#' `checkbox_group`'s multiple selections) -- the same three shapes
#' [flatten_crf_entries_for_export()]'s blank-field coercion already
#' handles, applied here in the opposite direction (into a form
#' input, not out to a flattened string).
#'
#' A "date" field's blank case reuses
#' [reset_crf_field_inputs()]'s `"zzedc-clear-date-input"` message
#' rather than `shiny::updateDateInput(value = NA)`, for the same
#' reason documented there: the bundled datepicker widget's own
#' `update()` can silently re-populate from today's date instead of
#' staying blank.
#'
#' A "file" field is never touched here at all -- there is no
#' `updateFileInput()`, and a previously uploaded file cannot be
#' placed back into the browser's own file-picker control. The
#' caller is responsible for carrying the stored upload path forward
#' into the next save's `field_data` itself when the user does not
#' choose a new file (see `inst/app/edc.R`'s submit/draft-save
#' handlers).
#'
#' @param session The current Shiny session.
#' @param metadata Field metadata as returned by
#'   [get_crf_field_metadata()].
#' @param values The draft's parsed field values (named list, keyed
#'   by `field_code`, in the same shape `metadata` is).
#' @return `NULL`, invisibly. Called for its side effect.
#' @keywords internal
fill_crf_field_inputs <- function(session, metadata, values) {
  for (field_name in names(metadata)) {
    field_config <- metadata[[field_name]] %||% list(type = "text")
    v <- values[[field_name]]
    is_blank <- is.null(v) || length(v) == 0
    scalar <- function() as.character(unlist(v))[1]
    vec <- function() as.character(unlist(v))
    switch(
      field_config$type,
      "numeric" = shiny::updateNumericInput(
        session, field_name,
        value = if (is_blank) NA else suppressWarnings(as.numeric(scalar()))
      ),
      "date" = if (is_blank) {
        session$sendCustomMessage("zzedc-clear-date-input", field_name)
      } else {
        parsed <- tryCatch(as.Date(scalar()), error = function(e) NA)
        if (!is.na(parsed)) {
          shiny::updateDateInput(session, field_name, value = parsed)
        }
      },
      "select" = shiny::updateSelectInput(
        session, field_name,
        selected = if (is_blank) field_config$choices[1] else scalar()
      ),
      "radio" = shiny::updateRadioButtons(
        session, field_name,
        selected = if (is_blank) character(0) else scalar()
      ),
      "checkbox_group" = shiny::updateCheckboxGroupInput(
        session, field_name,
        selected = if (is_blank) character(0) else vec()
      ),
      "textarea" = shiny::updateTextAreaInput(
        session, field_name,
        value = if (is_blank) "" else paste(vec(), collapse = ", ")
      ),
      # No updateFileInput(); see this function's @details.
      "file" = NULL,
      # readonly_display has no Shiny input binding to update.
      "readonly_display" = NULL,
      shiny::updateTextInput(
        session, field_name,
        value = if (is_blank) "" else paste(vec(), collapse = ", ")
      )
    )
  }
  invisible(NULL)
}


#' Client-side handlers for `reset_crf_field_inputs()`'s "date" and
#' "file" custom messages
#'
#' Neither a `dateInput()` nor a `fileInput()` can be reliably cleared
#' from the server alone (see `reset_crf_field_inputs()`'s "date" and
#' "file" cases for why); this registers the two
#' `Shiny.addCustomMessageHandler()` handlers their
#' `session$sendCustomMessage()` calls rely on. Included once in the
#' page `<head>` (alongside `shinyjs::useShinyjs()`, which this does
#' not use but is naturally grouped with) by both `inst/app/ui.R` and
#' `inst/app/gsheets_ui_integration.R`.
#'
#' @return A `tags$script()` tag.
#' @keywords internal
.zzedc_crf_reset_message_handlers <- function() {
  shiny::tags$script(shiny::HTML(
    "Shiny.addCustomMessageHandler('zzedc-clear-date-input', function(id) {",
    "  $('#' + id).find('input').bsDatepicker('clearDates');",
    "});",
    "Shiny.addCustomMessageHandler('zzedc-clear-file-input', function(id) {",
    "  var el = document.getElementById(id);",
    "  if (el) { el.value = ''; }",
    "});"
  ))
}


#' The Subject a CRF Submission Belongs To
#'
#' The one rule for which form field identifies the subject: the
#' value of `tracking_id` if the form has that field and it is filled
#' in, otherwise the value of `subject_id`. Registry forms use
#' `tracking_id`; clinical forms, including the shipped demonstration
#' study and the forms described in `vignette("content-author-guide")`,
#' use `subject_id`.
#'
#' @param field_data Named list of submitted field values.
#' @return The trimmed subject identifier, or `NULL` if neither field
#'   holds a value.
#' @keywords internal
crf_subject_key <- function(field_data) {
  for (f in .crf_subject_key_fields) {
    v <- field_data[[f]]
    if (!is.null(v) && length(v) == 1 && !is.na(v) &&
        nzchar(trimws(as.character(v)))) {
      return(trimws(as.character(v)))
    }
  }
  NULL
}

.crf_subject_key_fields <- c("tracking_id", "subject_id")

#' The Subject-Key Field a Form Has (internal)
#'
#' @param field_names The form's field codes.
#' @return `"tracking_id"`, `"subject_id"`, or `NULL`.
#' @keywords internal
crf_subject_key_field <- function(field_names) {
  hit <- intersect(.crf_subject_key_fields, field_names)
  if (length(hit) == 0) NULL else hit[1]
}


#' Save a submitted CRF entry to `data_entries`
#'
#' Thin wrapper over [ensure_data_entries_table()]/
#' [db_insert_data_entry()] for CRF-form submissions from the EDC
#' tab's dynamic (imported-form) rendering path, distinct from the
#' study-specific `forms/save.R` used by the demo scaffold path.
#'
#' The `data_entries` table requires a non-empty `subject_id`. The
#' entry's subject is the form's subject-key field (see
#' [crf_subject_key()]): `tracking_id` on registry forms (a
#' manuscript, a course, a committee term, ...), or `subject_id` on
#' clinical forms such as the shipped demonstration study's. Before
#' 2026-11-27 only `tracking_id` was read, so a form keyed by
#' `subject_id` stored every entry under a generated placeholder. If
#' the form has neither field, or it was left blank, a timestamp-based
#' placeholder is still used so the insert can proceed; such an entry
#' is linked to no subject.
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_code The form's `crf_definitions.crf_code` (used,
#'   lower-cased, as `data_entries.form_name`, matching the
#'   lower-case `form_code` convention already used by
#'   `dsl_validation_rules`).
#' @param field_data Named list of submitted field values, keyed by
#'   `field_code`.
#' @param created_by String identifying who submitted the entry.
#' @param is_complete `TRUE` (the default, preserving every existing
#'   caller's behavior unchanged) for an ordinary full "Submit";
#'   `FALSE` for a first "Save and Finish Later" draft save of a
#'   *new* entry (one with no `entry_id` yet to resume) --
#'   subsequent saves of that same draft go through
#'   [db_update_incomplete_data_entry()] instead, not back through
#'   this insert-only path.
#' @param dde_group_id,audit_extra Passed through unchanged to
#'   [db_insert_data_entry()]; see its own documentation. Used by the
#'   double-data-entry save path (`R/double_data_entry.R`), `NULL` for
#'   every ordinary submission.
#' @param ip_address,session_id Recorded in the entry's audit record
#'   (see `session_audit_context()`).
#' @return The `list(success=, entry_id=)` / `list(success=FALSE,
#'   error=)` result from [db_insert_data_entry()].
#' @keywords internal
save_crf_entry <- function(conn, crf_code, field_data, created_by,
                           is_complete = TRUE,
                           dde_group_id = NULL, audit_extra = NULL,
                           ip_address = NULL, session_id = NULL) {
  ensure_data_entries_table(conn)

  subject_id <- crf_subject_key(field_data)
  if (is.null(subject_id)) {
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
    is_complete = is_complete,
    created_by  = created_by,
    dde_group_id = dde_group_id,
    audit_extra  = audit_extra,
    ip_address  = ip_address,
    session_id  = session_id
  )
}


#' Persist a submitted CRF file upload to permanent storage
#'
#' Shiny's `fileInput()` leaves an uploaded file at a temp path
#' (`input[[field_code]]$datapath`) that is deleted when the session
#' ends, so a "file"-type field's value cannot be stored as-is by
#' [save_crf_entry()] the way every other field type's value is --
#' the submit handler must copy it somewhere permanent first and
#' store that path instead. Destination:
#' `<dirname(db_path)>/uploads/<crf_code>/<tracking_id>/<field_code>_<original name>`,
#' with every path component sanitized to `[A-Za-z0-9._-]` so
#' neither the tracking ID nor the uploaded filename can escape the
#' uploads directory or collide with punctuation-sensitive tooling.
#'
#' @param tmp_path The temp file path, from `input[[field_code]]$datapath`.
#' @param original_name The uploaded file's original name, from
#'   `input[[field_code]]$name`.
#' @param db_path The study database's file path; uploads are stored
#'   under a `uploads/` directory next to it.
#' @param crf_code,tracking_id,field_code Identify the submission and
#'   field this upload belongs to, for the destination path.
#' @return The stored file's path, relative to `dirname(db_path)`
#'   (suitable for storing in `field_data` and later resolving with
#'   `file.path(dirname(db_path), stored_path)`).
#' @keywords internal
persist_crf_upload <- function(tmp_path, original_name, db_path, crf_code,
                                tracking_id, field_code) {
  sanitize <- function(x) gsub("[^A-Za-z0-9._-]+", "_", as.character(x))

  rel_dir <- file.path("uploads", sanitize(crf_code), sanitize(tracking_id))
  dest_dir <- file.path(dirname(db_path), rel_dir)
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

  dest_name <- paste0(sanitize(field_code), "_", sanitize(basename(original_name)))
  dest_path <- file.path(dest_dir, dest_name)
  file.copy(tmp_path, dest_path, overwrite = TRUE)

  file.path(rel_dir, dest_name)
}
