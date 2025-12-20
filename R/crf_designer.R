#' WYSIWYG CRF Designer (Feature #32)
#'
#' Drag-and-drop CRF design interface with form sections,
#' field placement, and layout management.
#'
#' @name crf_designer
#' @docType package
NULL

#' @keywords internal
safe_scalar_cd <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize CRF Designer System
#' @return List with success status
#' @export
init_crf_designer <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS designer_forms (
        design_id INTEGER PRIMARY KEY AUTOINCREMENT,
        form_code TEXT UNIQUE NOT NULL,
        form_name TEXT NOT NULL,
        form_category TEXT,
        form_description TEXT,
        layout_type TEXT DEFAULT 'SINGLE_COLUMN',
        status TEXT DEFAULT 'DRAFT',
        is_locked INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS designer_sections (
        section_id INTEGER PRIMARY KEY AUTOINCREMENT,
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
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS designer_fields (
        field_id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        FOREIGN KEY (design_id) REFERENCES designer_forms(design_id),
        FOREIGN KEY (section_id) REFERENCES designer_sections(section_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS designer_field_options (
        option_id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_id INTEGER NOT NULL,
        option_value TEXT NOT NULL,
        option_label TEXT NOT NULL,
        option_order INTEGER DEFAULT 1,
        is_default INTEGER DEFAULT 0,
        FOREIGN KEY (field_id) REFERENCES designer_fields(field_id)
      )
    ")

    list(success = TRUE, message = "CRF designer system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Layout Types
#' @return Named character vector
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

    DBI::dbExecute(con, "
      INSERT INTO designer_forms (
        form_code, form_name, form_category, form_description,
        layout_type, created_by
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      form_code, form_name, safe_scalar_cd(form_category),
      safe_scalar_cd(form_description), layout_type, created_by
    ))

    design_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

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
#' @return List with success status
#' @export
add_form_section <- function(design_id, section_code, section_name,
                              section_order = 1, is_repeating = FALSE,
                              columns = 1) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO designer_sections (
        design_id, section_code, section_name, section_order,
        is_repeating, columns
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      design_id, section_code, section_name, as.integer(section_order),
      as.integer(is_repeating), as.integer(columns)
    ))

    section_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

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
#' @return List with success status
#' @export
add_form_field <- function(design_id, field_code, field_label, field_type,
                            section_id = NULL, field_row = 1, field_column = 1,
                            field_width = 100, is_required = FALSE,
                            placeholder = NULL, help_text = NULL,
                            default_value = NULL) {
  tryCatch({
    valid_types <- names(get_designer_field_types())
    if (!field_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid field_type:", field_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO designer_fields (
        design_id, section_id, field_code, field_label, field_type,
        field_row, field_column, field_width, is_required,
        placeholder, help_text, default_value
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      design_id,
      if (is.null(section_id)) NA_integer_ else as.integer(section_id),
      field_code, field_label, field_type,
      as.integer(field_row), as.integer(field_column),
      as.integer(field_width), as.integer(is_required),
      safe_scalar_cd(placeholder), safe_scalar_cd(help_text),
      safe_scalar_cd(default_value)
    ))

    field_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, field_id = field_id)
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
#' @return List with success status
#' @export
add_field_option <- function(field_id, option_value, option_label,
                              option_order = 1, is_default = FALSE) {
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
#' @return List with success status
#' @export
update_field_position <- function(field_id, field_row = NULL,
                                   field_column = NULL, section_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    updates <- c()
    params <- list()

    if (!is.null(field_row)) {
      updates <- c(updates, "field_row = ?")
      params <- append(params, list(as.integer(field_row)))
    }
    if (!is.null(field_column)) {
      updates <- c(updates, "field_column = ?")
      params <- append(params, list(as.integer(field_column)))
    }
    if (!is.null(section_id)) {
      updates <- c(updates, "section_id = ?")
      params <- append(params, list(as.integer(section_id)))
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

    list(success = TRUE, message = "Form status updated")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Lock Form Design
#' @param design_id Design ID
#' @param locked_by User locking
#' @return List with success status
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

    list(success = TRUE, message = "Form design locked")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Designer Form
#' @param design_id Design ID
#' @return List with form details
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
#' @return List with success status
#' @export
delete_form_field <- function(field_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      DELETE FROM designer_field_options WHERE field_id = ?
    ", params = list(field_id))

    DBI::dbExecute(con, "
      DELETE FROM designer_fields WHERE field_id = ?
    ", params = list(field_id))

    list(success = TRUE, message = "Field deleted")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CRF Designer Statistics
#' @return List with statistics
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
