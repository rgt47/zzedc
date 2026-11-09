#' WYSIWYG CRF Designer (Feature #32)
#'
#' Drag-and-drop CRF design interface with form sections,
#' field placement, and layout management.
#'
#' @keywords internal
#' @name crf_designer
NULL

#' @keywords internal
safe_scalar_cd <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Record a CRF Designer Mutation to the Audit Trail
#'
#' `log_audit_event()`'s `operation` argument has no default and is
#' evaluated before that function's own `tryCatch` begins, so a call
#' that omits it throws before the error ever reaches that internal
#' handler; every caller elsewhere in the package wraps its own call
#' in `tryCatch(..., error = function(e) NULL)`, which only swallows
#' the symptom. This helper always supplies `operation` so that
#' failure mode cannot recur here, and still wraps the call so a
#' genuine audit-logging failure (e.g. a locked-down `audit_log`
#' table) never blocks the CRF designer operation it is recording.
#'
#' @keywords internal
audit_cd_event <- function(event_type, table_name, record_id, operation,
                            user_id = NULL, details = NULL) {
  tryCatch({
    log_audit_event(
      event_type = event_type, table_name = table_name,
      record_id = as.character(record_id), operation = operation,
      user_id = user_id, details = details
    )
  }, error = function(e) NULL)
}

#' Initialize CRF Designer System
#' @return List with success status
#' @keywords internal
#' @export
init_crf_designer <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    prepare_auto_increment(con, "designer_forms", "design_id")
    DBI::dbExecute(con, sprintf("
      CREATE TABLE IF NOT EXISTS designer_forms (
        design_id %s,
        form_code TEXT UNIQUE NOT NULL,
        form_name TEXT NOT NULL,
        form_category TEXT,
        form_description TEXT,
        layout_type TEXT DEFAULT 'SINGLE_COLUMN',
        status TEXT DEFAULT 'DRAFT',
        is_locked INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (CURRENT_TIMESTAMP),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT
      )
    ", auto_increment_ddl("designer_forms", "design_id")))

    prepare_auto_increment(con, "designer_sections", "section_id")
    DBI::dbExecute(con, sprintf("
      CREATE TABLE IF NOT EXISTS designer_sections (
        section_id %s,
        design_id INTEGER NOT NULL,
        section_code TEXT NOT NULL,
        section_name TEXT NOT NULL,
        section_order INTEGER DEFAULT 1,
        is_repeating INTEGER DEFAULT 0,
        is_collapsible INTEGER DEFAULT 1,
        default_collapsed INTEGER DEFAULT 0,
        columns INTEGER DEFAULT 1,
        FOREIGN KEY (design_id) REFERENCES designer_forms(design_id)
      )
    ", auto_increment_ddl("designer_sections", "section_id")))

    prepare_auto_increment(con, "designer_fields", "field_id")
    DBI::dbExecute(con, sprintf("
      CREATE TABLE IF NOT EXISTS designer_fields (
        field_id %s,
        design_id INTEGER NOT NULL,
        section_id INTEGER,
        field_code TEXT NOT NULL,
        field_label TEXT NOT NULL,
        field_type TEXT NOT NULL,
        field_row INTEGER DEFAULT 1,
        field_column INTEGER DEFAULT 1,
        field_width INTEGER DEFAULT 100,
        is_required INTEGER DEFAULT 0,
        is_visible INTEGER DEFAULT 1,
        placeholder TEXT,
        help_text TEXT,
        default_value TEXT,
        css_class TEXT,
        widget_file TEXT,
        help_detail TEXT,
        FOREIGN KEY (design_id) REFERENCES designer_forms(design_id),
        FOREIGN KEY (section_id) REFERENCES designer_sections(section_id)
      )
    ", auto_increment_ddl("designer_fields", "field_id")))

    # CREATE TABLE IF NOT EXISTS only takes effect for a brand-new
    # database; a database initialized before widget_file (or, later,
    # help_detail) existed (e.g. this package's own live promotion-
    # tracker deployment) needs each added on to the table it already
    # has.
    existing_cols <- get_db_adapter()$describe_table(con, "designer_fields")$name
    if (!"widget_file" %in% existing_cols) {
      DBI::dbExecute(con, "ALTER TABLE designer_fields ADD COLUMN widget_file TEXT")
    }
    if (!"help_detail" %in% existing_cols) {
      DBI::dbExecute(con, "ALTER TABLE designer_fields ADD COLUMN help_detail TEXT")
    }

    prepare_auto_increment(con, "designer_field_options", "option_id")
    DBI::dbExecute(con, sprintf("
      CREATE TABLE IF NOT EXISTS designer_field_options (
        option_id %s,
        field_id INTEGER NOT NULL,
        option_value TEXT NOT NULL,
        option_label TEXT NOT NULL,
        option_order INTEGER DEFAULT 1,
        is_default INTEGER DEFAULT 0,
        FOREIGN KEY (field_id) REFERENCES designer_fields(field_id)
      )
    ", auto_increment_ddl("designer_field_options", "option_id")))

    list(success = TRUE, message = "CRF designer system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Layout Types
#' @return Named character vector
#' @keywords internal
#' @export
get_layout_types <- function() {
  c(
    SINGLE_COLUMN = "Single column layout",
    TWO_COLUMN = "Two column layout",
    THREE_COLUMN = "Three column layout",
    GRID = "Grid-based layout"
  )
}

#' Get Field Types
#' @return Named character vector
#' @keywords internal
#' @export
get_designer_field_types <- function() {
  c(
    TEXT = "Single-line text input",
    TEXTAREA = "Multi-line text area",
    NUMBER = "Numeric input",
    INTEGER = "Integer input",
    DATE = "Date picker",
    TIME = "Time picker",
    DATETIME = "Date and time picker",
    RADIO = "Radio button group",
    CHECKBOX = "Checkbox group",
    SELECT = "Dropdown select",
    MULTISELECT = "Multi-select dropdown",
    FILE = "File upload",
    SIGNATURE = "Electronic signature",
    CALCULATED = "Calculated field",
    LABEL = "Static label/text",
    DIVIDER = "Section divider"
  )
}

#' Get Form Statuses
#' @return Named character vector
#' @keywords internal
#' @export
get_form_statuses <- function() {
  c(
    DRAFT = "Form is being designed",
    REVIEW = "Form under review",
    APPROVED = "Form approved for use",
    ACTIVE = "Form in active use",
    RETIRED = "Form retired from use"
  )
}

#' Create Designer Form
#' @param form_code Unique code
#' @param form_name Form name
#' @param created_by User creating
#' @param form_category Optional category
#' @param form_description Optional description
#' @param layout_type Layout type
#' @return List with success status
#' @keywords internal
#' @export
create_designer_form <- function(form_code, form_name, created_by,
                                  form_category = NULL,
                                  form_description = NULL,
                                  layout_type = "SINGLE_COLUMN") {
  tryCatch({
    if (missing(form_code) || form_code == "") {
      return(list(success = FALSE, error = "form_code is required"))
    }

    valid_layouts <- names(get_layout_types())
    if (!layout_type %in% valid_layouts) {
      return(list(success = FALSE,
                  error = paste("Invalid layout_type:", layout_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    design_id <- DBI::dbGetQuery(con, "
      INSERT INTO designer_forms (
        form_code, form_name, form_category, form_description,
        layout_type, created_by
      ) VALUES (?, ?, ?, ?, ?, ?)
      RETURNING design_id AS id
    ", params = list(
      form_code, form_name, safe_scalar_cd(form_category),
      safe_scalar_cd(form_description), layout_type, created_by
    ))$id[1]

    audit_cd_event(
      event_type = "INSERT", table_name = "designer_forms",
      record_id = design_id, user_id = created_by,
      operation = paste("Created form", form_code),
      details = paste0("form_name=", form_name, "; layout_type=", layout_type)
    )

    list(success = TRUE, design_id = design_id)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Form Section
#' @param design_id Design ID
#' @param section_code Section code
#' @param section_name Section name
#' @param section_order Order
#' @param is_repeating Whether repeating
#' @param columns Number of columns
#' @param user_id Optional: the user performing this change, recorded
#'   in the audit trail (see `audit_cd_event()`). `NULL` records an
#'   unattributed entry rather than failing the operation.
#' @return List with success status
#'
#' @examples
#' \dontrun{
#' # Add a "Vital Signs" section to an existing CRF design.
#' # `design_id` is returned by `create_designer_form()`. Use
#' # `is_repeating = TRUE` for sections that can record multiple
#' # measurements (e.g., adverse-event log entries).
#' add_form_section(
#'   design_id    = 1,
#'   section_code = "vitals",
#'   section_name = "Vital Signs",
#'   section_order = 2,
#'   columns       = 2
#' )
#' }
#' @export
add_form_section <- function(design_id, section_code, section_name,
                              section_order = 1, is_repeating = FALSE,
                              columns = 1, user_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    section_id <- DBI::dbGetQuery(con, "
      INSERT INTO designer_sections (
        design_id, section_code, section_name, section_order,
        is_repeating, columns
      ) VALUES (?, ?, ?, ?, ?, ?)
      RETURNING section_id AS id
    ", params = list(
      design_id, section_code, section_name, as.integer(section_order),
      as.integer(is_repeating), as.integer(columns)
    ))$id[1]

    audit_cd_event(
      event_type = "INSERT", table_name = "designer_sections",
      record_id = section_id, user_id = user_id,
      operation = paste("Added section", section_code, "to design", design_id)
    )

    list(success = TRUE, section_id = section_id)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Form Field
#' @param design_id Design ID
#' @param field_code Field code
#' @param field_label Field label
#' @param field_type Field type
#' @param section_id Optional section ID
#' @param field_row Row position
#' @param field_column Column position
#' @param field_width Width percentage
#' @param is_required Whether required
#' @param placeholder Placeholder text
#' @param help_text Help text
#' @param default_value Default value
#' @param widget_file Name of a custom widget to attach to this
#'   field (e.g. `"coauthor_builder"`), or `NULL` for none. Resolved
#'   at render time by [resolve_widget_module()] to a file under
#'   `inst/app/widgets/`; only `[a-zA-Z0-9_]+` is accepted as a
#'   widget name.
#' @param help_detail Optional long-form help content for this
#'   field -- a full explanation, worked example, or convention
#'   description that would be too much for `help_text`'s one-line
#'   hover hint. Shown instead in a modal, opened by clicking the
#'   field's hint icon (see `inst/app/edc.R`); a field with no
#'   `help_detail` keeps the plain hover tooltip for that click.
#' @param user_id Optional: the user performing this change, recorded
#'   in the audit trail (see `audit_cd_event()`). `NULL` records an
#'   unattributed entry rather than failing the operation.
#' @return List with success status
#'
#' @examples
#' \dontrun{
#' # Add a required systolic-blood-pressure field to the vital-signs
#' # section of an existing CRF.
#' add_form_field(
#'   design_id    = 1,
#'   section_id   = 2,                    # from add_form_section()
#'   field_code   = "sbp",
#'   field_label  = "Systolic blood pressure (mmHg)",
#'   field_type   = "numeric",
#'   is_required  = TRUE,
#'   placeholder  = "e.g., 120",
#'   help_text    = "Seated; average of two readings"
#' )
#' }
#' @export
add_form_field <- function(design_id, field_code, field_label, field_type,
                            section_id = NULL, field_row = 1, field_column = 1,
                            field_width = 100, is_required = FALSE,
                            placeholder = NULL, help_text = NULL,
                            default_value = NULL, widget_file = NULL,
                            help_detail = NULL, user_id = NULL) {
  tryCatch({
    valid_types <- names(get_designer_field_types())
    if (!field_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid field_type:", field_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    field_id <- DBI::dbGetQuery(con, "
      INSERT INTO designer_fields (
        design_id, section_id, field_code, field_label, field_type,
        field_row, field_column, field_width, is_required,
        placeholder, help_text, default_value, widget_file, help_detail
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING field_id AS id
    ", params = list(
      design_id,
      if (is.null(section_id)) NA_integer_ else as.integer(section_id),
      field_code, field_label, field_type,
      as.integer(field_row), as.integer(field_column),
      as.integer(field_width), as.integer(is_required),
      safe_scalar_cd(placeholder), safe_scalar_cd(help_text),
      safe_scalar_cd(default_value), safe_scalar_cd(widget_file),
      safe_scalar_cd(help_detail)
    ))$id[1]

    audit_cd_event(
      event_type = "INSERT", table_name = "designer_fields",
      record_id = field_id, user_id = user_id,
      operation = paste("Added field", field_code, "to design", design_id),
      details = paste0("field_type=", field_type, "; field_label=", field_label)
    )

    list(success = TRUE, field_id = field_id)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add a Form Field Identified by Form Code
#'
#' Combines the manual steps
#' `vignette('promotion-tracker-add-field-walkthrough')` describes for
#' applying a Data Dictionary addition to the live database into one
#' call: look up `design_id` from `form_code`, check for a duplicate
#' `field_code` on that form, insert the field via `add_form_field()`,
#' and read the row back to confirm it was written with the requested
#' label/type/position/required-flag/help text. `field_type` must
#' still be one of the upper-case constants from
#' `get_designer_field_types()` (e.g. `"DATE"`), the same requirement
#' `add_form_field()` has -- this function does not upper-case a
#' Sheet-style lower-case value for you, since that translation is the
#' Google Sheets importer's job, not this one's.
#'
#' This does not remove every manual step: you still need
#' `DB_ENCRYPTION_KEY`/`ZZEDC_SALT` exported in the current R session
#' before calling this (same precondition `connect_encrypted_db()`
#' always enforces). The returned `verified` flag confirms the
#' database side only; it cannot detect a stale reactive cache in an
#' already-open browser tab, so a hard reload of the running app is
#' still worth doing, but a `verified = TRUE` result does mean that if
#' the field still does not appear there, the cause is the browser
#' tab, not the data.
#'
#' @param form_code Character: the form's code, matched
#'   case-insensitively against `designer_forms$form_code` (e.g.
#'   `"journal_reviews"` or `"JOURNAL_REVIEWS"` both match the stored
#'   `"JOURNAL_REVIEWS"`).
#' @param field_code Field's unique code within the form
#' @param field_label Display label
#' @param field_type Field type (upper-case constant from
#'   `get_designer_field_types()`, e.g. `"DATE"`)
#' @param field_row Display row/position (matches the Data Dictionary's
#'   `field_order`)
#' @param field_column Display column
#' @param field_width Width percentage
#' @param is_required Whether required
#' @param placeholder Placeholder text
#' @param help_text Help text
#' @param default_value Default value
#' @param widget_file Name of a custom widget to attach to this field,
#'   or `NULL` for none (see `add_form_field()`)
#' @param help_detail Optional long-form help content (see
#'   `add_form_field()`)
#' @param user_id Optional: the user performing this change, passed
#'   through to `add_form_field()`'s audit-trail entry. `NULL`
#'   records an unattributed entry rather than failing the operation.
#' @return List with `success`. On success, also `design_id`,
#'   `field_id`, `verified` (logical: `TRUE` if the row read back from
#'   `designer_fields` matches every argument passed in), `mismatches`
#'   (character vector naming which fields did not match, empty when
#'   `verified` is `TRUE`), and `field` (the row as read back). On
#'   failure, `error` and (once `form_code` resolves) `design_id`,
#'   describing which step failed: the form code did not resolve to a
#'   `designer_forms` row, the field already exists on that form (not
#'   re-added), or `add_form_field()` itself failed (invalid
#'   `field_type`, missing encryption key, etc.).
#'
#' @examples
#' \dontrun{
#' add_form_field_by_code(
#'   form_code    = "journal_reviews",
#'   field_code   = "review_assigned_date",
#'   field_label  = "Review Assigned Date",
#'   field_type   = "DATE",
#'   field_row    = 35,
#'   is_required  = FALSE,
#'   help_text    = "Date the editor assigned this manuscript for review"
#' )
#' }
#' @export
add_form_field_by_code <- function(form_code, field_code, field_label,
                                   field_type, field_row = 1,
                                   field_column = 1, field_width = 100,
                                   is_required = FALSE, placeholder = NULL,
                                   help_text = NULL, default_value = NULL,
                                   widget_file = NULL, help_detail = NULL,
                                   user_id = NULL) {
  tryCatch({
    # Each step below opens and closes its own connection rather than
    # holding one open across add_form_field()'s own connect() call.
    # On DuckDB, a connection's snapshot is fixed when it starts; a
    # connection opened before add_form_field()'s write and reused
    # afterward does not see that write (confirmed directly: a stale
    # connection held open across the insert reports 0 rows where a
    # fresh connection reports 1), even though auto-commit elsewhere
    # makes the write immediately visible to any new connection.
    # SQLite does not have this failure mode, but the fix (never
    # span a connection across another connection's write) is cheap
    # enough to apply unconditionally rather than special-casing it
    # per backend.
    design_id <- local({
      con <- connect_encrypted_db()
      on.exit(DBI::dbDisconnect(con))
      DBI::dbGetQuery(con, "
        SELECT design_id FROM designer_forms WHERE UPPER(form_code) = UPPER(?)
      ", params = list(form_code))
    })

    if (nrow(design_id) == 0) {
      return(list(success = FALSE,
                  error = paste("No form found with form_code:", form_code)))
    }
    design_id <- design_id$design_id[1]

    existing <- local({
      con <- connect_encrypted_db()
      on.exit(DBI::dbDisconnect(con))
      DBI::dbGetQuery(con, "
        SELECT field_id FROM designer_fields
        WHERE design_id = ? AND field_code = ?
      ", params = list(design_id, field_code))
    })

    if (nrow(existing) > 0) {
      return(list(
        success = FALSE, design_id = design_id,
        field_id = existing$field_id[1],
        error = paste0("Field '", field_code, "' already exists on ",
                        form_code, " (field_id ", existing$field_id[1],
                        ") -- not re-added")
      ))
    }

    result <- add_form_field(
      design_id = design_id, field_code = field_code,
      field_label = field_label, field_type = field_type,
      field_row = field_row, field_column = field_column,
      field_width = field_width, is_required = is_required,
      placeholder = placeholder, help_text = help_text,
      default_value = default_value, widget_file = widget_file,
      help_detail = help_detail, user_id = user_id
    )

    if (!isTRUE(result$success)) {
      return(list(success = FALSE, design_id = design_id,
                  error = result$error))
    }

    # Re-read the row we just wrote and compare it against what was
    # requested. This is the data-layer equivalent of the
    # walkthrough's manual browser check (field present, right type/
    # position, required flag, help text) -- it cannot catch a stale
    # reactive cache in an already-open browser tab (that is a
    # client-side rendering concern, not a database one), but it does
    # rule the database out as the cause if the field still does not
    # appear live, narrowing that check to "reload the browser" rather
    # than "re-check the data".
    written <- local({
      con <- connect_encrypted_db()
      on.exit(DBI::dbDisconnect(con))
      DBI::dbGetQuery(con, "
        SELECT field_label, field_type, field_row, field_column,
               field_width, is_required, help_text
        FROM designer_fields WHERE field_id = ?
      ", params = list(result$field_id))
    })

    mismatches <- character(0)
    check_field <- function(expected, actual, label) {
      if (!identical(expected, actual)) {
        mismatches <<- c(mismatches, sprintf(
          "%s: expected %s, got %s", label, format(expected), format(actual)
        ))
      }
    }
    check_field(field_label, written$field_label[1], "field_label")
    check_field(field_type, written$field_type[1], "field_type")
    check_field(as.integer(field_row), as.integer(written$field_row[1]), "field_row")
    check_field(as.integer(is_required), as.integer(written$is_required[1]), "is_required")
    check_field(safe_scalar_cd(help_text), written$help_text[1], "help_text")

    list(
      success = TRUE, design_id = design_id, field_id = result$field_id,
      verified = length(mismatches) == 0,
      mismatches = mismatches,
      field = written
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Field Option
#' @param field_id Field ID
#' @param option_value Option value
#' @param option_label Option label
#' @param option_order Order
#' @param is_default Whether default
#' @param user_id Optional: the user performing this change, recorded
#'   in the audit trail (see `audit_cd_event()`). `NULL` records an
#'   unattributed entry rather than failing the operation.
#' @return List with success status
#' @keywords internal
#' @export
add_field_option <- function(field_id, option_value, option_label,
                              option_order = 1, is_default = FALSE,
                              user_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO designer_field_options (
        field_id, option_value, option_label, option_order, is_default
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(
      field_id, option_value, option_label,
      as.integer(option_order), as.integer(is_default)
    ))

    audit_cd_event(
      event_type = "INSERT", table_name = "designer_field_options",
      record_id = field_id, user_id = user_id,
      operation = paste("Added option", option_value, "to field", field_id)
    )

    list(success = TRUE, message = "Field option added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update Field Position
#' @param field_id Field ID
#' @param field_row New row
#' @param field_column New column
#' @param section_id New section
#' @param user_id Optional: the user performing this change, recorded
#'   in the audit trail (see `audit_cd_event()`). `NULL` records an
#'   unattributed entry rather than failing the operation.
#' @return List with success status
#' @keywords internal
#' @export
update_field_position <- function(field_id, field_row = NULL,
                                   field_column = NULL, section_id = NULL,
                                   user_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    updates <- c()
    params <- list()
    changed <- c()

    if (!is.null(field_row)) {
      updates <- c(updates, "field_row = ?")
      params <- append(params, list(as.integer(field_row)))
      changed <- c(changed, paste0("field_row=", field_row))
    }
    if (!is.null(field_column)) {
      updates <- c(updates, "field_column = ?")
      params <- append(params, list(as.integer(field_column)))
      changed <- c(changed, paste0("field_column=", field_column))
    }
    if (!is.null(section_id)) {
      updates <- c(updates, "section_id = ?")
      params <- append(params, list(as.integer(section_id)))
      changed <- c(changed, paste0("section_id=", section_id))
    }

    if (length(updates) == 0) {
      return(list(success = FALSE, error = "No updates specified"))
    }

    params <- append(params, list(field_id))

    DBI::dbExecute(con, paste(
      "UPDATE designer_fields SET",
      paste(updates, collapse = ", "),
      "WHERE field_id = ?"
    ), params = params)

    audit_cd_event(
      event_type = "UPDATE", table_name = "designer_fields",
      record_id = field_id, user_id = user_id,
      operation = paste("Updated position of field", field_id),
      details = paste(changed, collapse = "; ")
    )

    list(success = TRUE, message = "Field position updated")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update Form Status
#' @param design_id Design ID
#' @param new_status New status
#' @param updated_by User updating
#' @return List with success status
#' @keywords internal
#' @export
update_form_status <- function(design_id, new_status, updated_by) {
  tryCatch({
    valid_statuses <- names(get_form_statuses())
    if (!new_status %in% valid_statuses) {
      return(list(success = FALSE, error = "Invalid status"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE designer_forms
      SET status = ?, updated_at = ?, updated_by = ?
      WHERE design_id = ?
    ", params = list(
      new_status, format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      updated_by, design_id
    ))

    audit_cd_event(
      event_type = "UPDATE", table_name = "designer_forms",
      record_id = design_id, user_id = updated_by,
      operation = paste("Status changed to", new_status)
    )

    list(success = TRUE, message = "Form status updated")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Lock Form Design
#' @param design_id Design ID
#' @param locked_by User locking
#' @return List with success status
#' @keywords internal
#' @export
lock_form_design <- function(design_id, locked_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE designer_forms
      SET is_locked = 1, updated_at = ?, updated_by = ?
      WHERE design_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      locked_by, design_id
    ))

    audit_cd_event(
      event_type = "UPDATE", table_name = "designer_forms",
      record_id = design_id, user_id = locked_by,
      operation = "Form design locked"
    )

    list(success = TRUE, message = "Form design locked")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Designer Form
#' @param design_id Design ID
#' @return List with form details
#' @keywords internal
#' @export
get_designer_form <- function(design_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    form <- DBI::dbGetQuery(con, "
      SELECT * FROM designer_forms WHERE design_id = ?
    ", params = list(design_id))

    if (nrow(form) == 0) {
      return(list(success = FALSE, error = "Form not found"))
    }

    sections <- DBI::dbGetQuery(con, "
      SELECT * FROM designer_sections WHERE design_id = ?
      ORDER BY section_order
    ", params = list(design_id))

    fields <- DBI::dbGetQuery(con, "
      SELECT * FROM designer_fields WHERE design_id = ?
      ORDER BY section_id, field_row, field_column
    ", params = list(design_id))

    list(
      success = TRUE,
      form = as.list(form),
      sections = sections,
      fields = fields
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Designer Forms List
#' @param status Optional status filter
#' @return List with forms
#' @keywords internal
#' @export
get_designer_forms <- function(status = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(status)) {
      forms <- DBI::dbGetQuery(con, "
        SELECT * FROM designer_forms ORDER BY created_at DESC
      ")
    } else {
      forms <- DBI::dbGetQuery(con, "
        SELECT * FROM designer_forms WHERE status = ?
        ORDER BY created_at DESC
      ", params = list(status))
    }

    list(success = TRUE, forms = forms, count = nrow(forms))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Section Fields
#' @param section_id Section ID
#' @return List with fields
#' @keywords internal
#' @export
get_section_fields <- function(section_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    fields <- DBI::dbGetQuery(con, "
      SELECT * FROM designer_fields WHERE section_id = ?
      ORDER BY field_row, field_column
    ", params = list(section_id))

    list(success = TRUE, fields = fields, count = nrow(fields))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Field Options
#' @param field_id Field ID
#' @return List with options
#' @keywords internal
#' @export
get_field_options <- function(field_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    options <- DBI::dbGetQuery(con, "
      SELECT * FROM designer_field_options WHERE field_id = ?
      ORDER BY option_order
    ", params = list(field_id))

    list(success = TRUE, options = options, count = nrow(options))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Delete Form Field
#' @param field_id Field ID
#' @param user_id Optional: the user performing this change, recorded
#'   in the audit trail (see `audit_cd_event()`). `NULL` records an
#'   unattributed entry rather than failing the operation.
#' @return List with success status
#' @keywords internal
#' @export
delete_form_field <- function(field_id, user_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    # Read back identifying details before the row is gone, so the
    # audit entry records what was deleted rather than just its id.
    deleted <- DBI::dbGetQuery(con, "
      SELECT field_code, design_id FROM designer_fields WHERE field_id = ?
    ", params = list(field_id))

    DBI::dbExecute(con, "
      DELETE FROM designer_field_options WHERE field_id = ?
    ", params = list(field_id))

    DBI::dbExecute(con, "
      DELETE FROM designer_fields WHERE field_id = ?
    ", params = list(field_id))

    audit_cd_event(
      event_type = "DELETE", table_name = "designer_fields",
      record_id = field_id, user_id = user_id,
      operation = paste("Deleted field", field_id),
      details = if (nrow(deleted) > 0) {
        paste0("field_code=", deleted$field_code[1],
               "; design_id=", deleted$design_id[1])
      } else {
        NULL
      }
    )

    list(success = TRUE, message = "Field deleted")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CRF Designer Statistics
#' @return List with statistics
#' @keywords internal
#' @export
get_crf_designer_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        (SELECT COUNT(*) FROM designer_forms) as total_forms,
        (SELECT COUNT(*) FROM designer_forms WHERE status = 'ACTIVE')
          as active_forms,
        (SELECT COUNT(*) FROM designer_sections) as total_sections,
        (SELECT COUNT(*) FROM designer_fields) as total_fields
    ")

    by_status <- DBI::dbGetQuery(con, "
      SELECT status, COUNT(*) as count
      FROM designer_forms
      GROUP BY status
    ")

    by_type <- DBI::dbGetQuery(con, "
      SELECT field_type, COUNT(*) as count
      FROM designer_fields
      GROUP BY field_type
    ")

    list(success = TRUE, statistics = as.list(stats),
         by_status = by_status, by_type = by_type)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
