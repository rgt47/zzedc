#' CRF Completion Guidelines (CCG) System
#'
#' Generates and manages Case Report Form completion guidelines
#' for clinical trial data entry staff. Provides field-by-field
#' instructions, valid values, examples, and skip patterns.
#'
#' @name ccg
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' @keywords internal
safe_scalar_ccg <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' @keywords internal
safe_int_ccg <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

#' @keywords internal
generate_ccg_id <- function(prefix = "CCG") {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(c(0:9, LETTERS), 4, replace = TRUE), collapse = "")
  paste0(prefix, "-", timestamp, "-", random)
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize CCG System Tables
#'
#' Creates the database tables required for CRF Completion
#' Guidelines management.
#'
#' @return List with success status and message
#' @export
init_ccg <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS ccg_forms (
        form_id INTEGER PRIMARY KEY AUTOINCREMENT,
        form_code TEXT UNIQUE NOT NULL,
        form_name TEXT NOT NULL,
        form_description TEXT,
        form_category TEXT,
        version TEXT DEFAULT '1.0',
        status TEXT DEFAULT 'DRAFT',
        visit_type TEXT,
        estimated_duration_minutes INTEGER,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT,
        approved_at TEXT,
        approved_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS ccg_fields (
        field_id INTEGER PRIMARY KEY AUTOINCREMENT,
        form_id INTEGER NOT NULL,
        field_code TEXT NOT NULL,
        field_name TEXT NOT NULL,
        field_label TEXT NOT NULL,
        field_type TEXT NOT NULL,
        field_order INTEGER NOT NULL,
        section_name TEXT,
        is_required INTEGER DEFAULT 0,
        is_key_field INTEGER DEFAULT 0,
        instruction TEXT,
        detailed_guidance TEXT,
        valid_values TEXT,
        valid_range_min TEXT,
        valid_range_max TEXT,
        units TEXT,
        format_pattern TEXT,
        example_entries TEXT,
        common_errors TEXT,
        source_document TEXT,
        skip_condition TEXT,
        skip_instruction TEXT,
        edit_checks TEXT,
        query_text TEXT,
        sdtm_variable TEXT,
        sdtm_domain TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT,
        FOREIGN KEY (form_id) REFERENCES ccg_forms(form_id),
        UNIQUE(form_id, field_code)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS ccg_versions (
        version_id INTEGER PRIMARY KEY AUTOINCREMENT,
        form_id INTEGER NOT NULL,
        version_number TEXT NOT NULL,
        version_date TEXT NOT NULL,
        change_summary TEXT,
        change_details TEXT,
        previous_version TEXT,
        status TEXT DEFAULT 'DRAFT',
        effective_date TEXT,
        created_by TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        approved_by TEXT,
        approved_at TEXT,
        version_hash TEXT NOT NULL,
        FOREIGN KEY (form_id) REFERENCES ccg_forms(form_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS ccg_generated (
        generation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        form_id INTEGER NOT NULL,
        version_id INTEGER,
        output_format TEXT NOT NULL,
        output_file TEXT,
        generated_at TEXT DEFAULT (datetime('now')),
        generated_by TEXT NOT NULL,
        include_examples INTEGER DEFAULT 1,
        include_edit_checks INTEGER DEFAULT 1,
        include_sdtm_mapping INTEGER DEFAULT 0,
        generation_hash TEXT NOT NULL,
        FOREIGN KEY (form_id) REFERENCES ccg_forms(form_id),
        FOREIGN KEY (version_id) REFERENCES ccg_versions(version_id)
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ccg_fields_form
                         ON ccg_fields(form_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ccg_fields_order
                         ON ccg_fields(form_id, field_order)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ccg_versions_form
                         ON ccg_versions(form_id)")

    list(success = TRUE, message = "CCG system initialized")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Field Types
#' @return Named character vector of field types
#' @export
get_ccg_field_types <- function() {
  c(
    TEXT = "Free text entry",
    NUMBER = "Numeric value",
    INTEGER = "Whole number",
    DATE = "Date (YYYY-MM-DD)",
    TIME = "Time (HH:MM)",
    DATETIME = "Date and time",
    CHECKBOX = "Yes/No checkbox",
    RADIO = "Single selection from options",
    DROPDOWN = "Dropdown selection",
    MULTISELECT = "Multiple selections allowed",
    TEXTAREA = "Multi-line text",
    CALCULATED = "Calculated/derived field",
    SIGNATURE = "Electronic signature"
  )
}

#' Get Form Categories
#' @return Named character vector of form categories
#' @export
get_ccg_form_categories <- function() {
  c(
    DEMOGRAPHICS = "Subject demographics",
    ELIGIBILITY = "Eligibility criteria",
    MEDICAL_HISTORY = "Medical history",
    PHYSICAL_EXAM = "Physical examination",
    VITAL_SIGNS = "Vital signs",
    LAB_RESULTS = "Laboratory results",
    CONCOMITANT_MEDS = "Concomitant medications",
    ADVERSE_EVENTS = "Adverse events",
    EFFICACY = "Efficacy assessments",
    STUDY_DRUG = "Study drug administration",
    PROTOCOL_DEVIATION = "Protocol deviations",
    END_OF_STUDY = "End of study"
  )
}

#' Get Form Statuses
#' @return Named character vector of form statuses
#' @export
get_ccg_form_statuses <- function() {
  c(
    DRAFT = "In development",
    REVIEW = "Under review",
    APPROVED = "Approved for use",
    SUPERSEDED = "Replaced by newer version",
    RETIRED = "No longer in use"
  )
}

#' Get Visit Types
#' @return Named character vector of visit types
#' @export
get_ccg_visit_types <- function() {
  c(
    SCREENING = "Screening visit",
    BASELINE = "Baseline visit",
    TREATMENT = "Treatment visit",
    FOLLOW_UP = "Follow-up visit",
    UNSCHEDULED = "Unscheduled visit",
    EARLY_TERM = "Early termination",
    END_OF_STUDY = "End of study visit"
  )
}

# ============================================================================
# FORM MANAGEMENT
# ============================================================================

#' Create CCG Form
#'
#' Creates a new CRF form for CCG documentation.
#'
#' @param form_code Unique form code
#' @param form_name Form name
#' @param created_by User creating the form
#' @param form_description Optional description
#' @param form_category Category from get_ccg_form_categories()
#' @param visit_type Visit type from get_ccg_visit_types()
#' @param estimated_duration_minutes Estimated completion time
#'
#' @return List with success status and form details
#' @export
create_ccg_form <- function(form_code,
                             form_name,
                             created_by,
                             form_description = NULL,
                             form_category = NULL,
                             visit_type = NULL,
                             estimated_duration_minutes = NULL) {
  tryCatch({
    if (missing(form_code) || is.null(form_code) || form_code == "") {
      return(list(success = FALSE, error = "form_code is required"))
    }
    if (missing(form_name) || is.null(form_name) || form_name == "") {
      return(list(success = FALSE, error = "form_name is required"))
    }

    if (!is.null(form_category)) {
      valid_categories <- names(get_ccg_form_categories())
      if (!form_category %in% valid_categories) {
        return(list(
          success = FALSE,
          error = paste("Invalid form_category. Must be one of:",
                       paste(valid_categories, collapse = ", "))
        ))
      }
    }

    if (!is.null(visit_type)) {
      valid_visits <- names(get_ccg_visit_types())
      if (!visit_type %in% valid_visits) {
        return(list(
          success = FALSE,
          error = paste("Invalid visit_type. Must be one of:",
                       paste(valid_visits, collapse = ", "))
        ))
      }
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    existing <- DBI::dbGetQuery(con, "
      SELECT form_id FROM ccg_forms WHERE form_code = ?
    ", params = list(form_code))

    if (nrow(existing) > 0) {
      return(list(success = FALSE, error = "form_code already exists"))
    }

    DBI::dbExecute(con, "
      INSERT INTO ccg_forms (
        form_code, form_name, form_description, form_category,
        visit_type, estimated_duration_minutes, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      form_code,
      form_name,
      safe_scalar_ccg(form_description),
      safe_scalar_ccg(form_category),
      safe_scalar_ccg(visit_type),
      safe_int_ccg(estimated_duration_minutes),
      created_by
    ))

    form_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      form_id = form_id,
      form_code = form_code,
      message = "CCG form created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CCG Forms
#'
#' Retrieves CCG forms.
#'
#' @param include_inactive Include inactive forms
#' @param form_category Optional filter by category
#' @param status Optional filter by status
#'
#' @return List with success status and forms
#' @export
get_ccg_forms <- function(include_inactive = FALSE,
                           form_category = NULL,
                           status = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM ccg_forms WHERE 1=1"
    params <- list()

    if (!include_inactive) {
      query <- paste(query, "AND is_active = 1")
    }

    if (!is.null(form_category)) {
      query <- paste(query, "AND form_category = ?")
      params <- append(params, list(form_category))
    }

    if (!is.null(status)) {
      query <- paste(query, "AND status = ?")
      params <- append(params, list(status))
    }

    query <- paste(query, "ORDER BY form_category, form_name")

    if (length(params) > 0) {
      forms <- DBI::dbGetQuery(con, query, params = params)
    } else {
      forms <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, forms = forms, count = nrow(forms))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update CCG Form Status
#'
#' Updates the status of a CCG form.
#'
#' @param form_id Form ID
#' @param status New status from get_ccg_form_statuses()
#' @param updated_by User updating the form
#'
#' @return List with success status
#' @export
update_ccg_form_status <- function(form_id, status, updated_by) {
  tryCatch({
    valid_statuses <- names(get_ccg_form_statuses())
    if (!status %in% valid_statuses) {
      return(list(
        success = FALSE,
        error = paste("Invalid status. Must be one of:",
                     paste(valid_statuses, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    updated_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    if (status == "APPROVED") {
      DBI::dbExecute(con, "
        UPDATE ccg_forms
        SET status = ?, updated_at = ?, updated_by = ?,
            approved_at = ?, approved_by = ?
        WHERE form_id = ?
      ", params = list(status, updated_at, updated_by,
                       updated_at, updated_by, form_id))
    } else {
      DBI::dbExecute(con, "
        UPDATE ccg_forms
        SET status = ?, updated_at = ?, updated_by = ?
        WHERE form_id = ?
      ", params = list(status, updated_at, updated_by, form_id))
    }

    list(success = TRUE, message = paste("Form status updated to", status))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# FIELD MANAGEMENT
# ============================================================================

#' Add CCG Field
#'
#' Adds a field to a CCG form with completion guidelines.
#'
#' @param form_id Form ID
#' @param field_code Unique field code within form
#' @param field_name Field name
#' @param field_label Display label
#' @param field_type Type from get_ccg_field_types()
#' @param field_order Display order
#' @param section_name Optional section name
#' @param is_required Whether field is required
#' @param is_key_field Whether field is a key identifier
#' @param instruction Brief completion instruction
#' @param detailed_guidance Detailed guidance text
#' @param valid_values Valid values (for selection fields)
#' @param valid_range_min Minimum valid value
#' @param valid_range_max Maximum valid value
#' @param units Units of measurement
#' @param format_pattern Expected format pattern
#' @param example_entries Example entries
#' @param common_errors Common errors to avoid
#' @param source_document Source document reference
#' @param skip_condition When to skip this field
#' @param skip_instruction Instructions if skipped
#' @param edit_checks Edit check rules
#' @param query_text Standard query text
#' @param sdtm_variable SDTM variable mapping
#' @param sdtm_domain SDTM domain
#'
#' @return List with success status and field details
#' @export
add_ccg_field <- function(form_id,
                           field_code,
                           field_name,
                           field_label,
                           field_type,
                           field_order,
                           section_name = NULL,
                           is_required = FALSE,
                           is_key_field = FALSE,
                           instruction = NULL,
                           detailed_guidance = NULL,
                           valid_values = NULL,
                           valid_range_min = NULL,
                           valid_range_max = NULL,
                           units = NULL,
                           format_pattern = NULL,
                           example_entries = NULL,
                           common_errors = NULL,
                           source_document = NULL,
                           skip_condition = NULL,
                           skip_instruction = NULL,
                           edit_checks = NULL,
                           query_text = NULL,
                           sdtm_variable = NULL,
                           sdtm_domain = NULL) {
  tryCatch({
    if (missing(form_id) || is.null(form_id)) {
      return(list(success = FALSE, error = "form_id is required"))
    }
    if (missing(field_code) || is.null(field_code) || field_code == "") {
      return(list(success = FALSE, error = "field_code is required"))
    }
    if (missing(field_label) || is.null(field_label) || field_label == "") {
      return(list(success = FALSE, error = "field_label is required"))
    }

    valid_types <- names(get_ccg_field_types())
    if (!field_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid field_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    form <- DBI::dbGetQuery(con, "
      SELECT form_id FROM ccg_forms WHERE form_id = ?
    ", params = list(form_id))

    if (nrow(form) == 0) {
      return(list(success = FALSE, error = "Form not found"))
    }

    existing <- DBI::dbGetQuery(con, "
      SELECT field_id FROM ccg_fields WHERE form_id = ? AND field_code = ?
    ", params = list(form_id, field_code))

    if (nrow(existing) > 0) {
      return(list(success = FALSE,
                  error = "field_code already exists in this form"))
    }

    DBI::dbExecute(con, "
      INSERT INTO ccg_fields (
        form_id, field_code, field_name, field_label, field_type,
        field_order, section_name, is_required, is_key_field,
        instruction, detailed_guidance, valid_values,
        valid_range_min, valid_range_max, units, format_pattern,
        example_entries, common_errors, source_document,
        skip_condition, skip_instruction, edit_checks, query_text,
        sdtm_variable, sdtm_domain
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      form_id,
      field_code,
      field_name,
      field_label,
      field_type,
      as.integer(field_order),
      safe_scalar_ccg(section_name),
      as.integer(is_required),
      as.integer(is_key_field),
      safe_scalar_ccg(instruction),
      safe_scalar_ccg(detailed_guidance),
      safe_scalar_ccg(valid_values),
      safe_scalar_ccg(valid_range_min),
      safe_scalar_ccg(valid_range_max),
      safe_scalar_ccg(units),
      safe_scalar_ccg(format_pattern),
      safe_scalar_ccg(example_entries),
      safe_scalar_ccg(common_errors),
      safe_scalar_ccg(source_document),
      safe_scalar_ccg(skip_condition),
      safe_scalar_ccg(skip_instruction),
      safe_scalar_ccg(edit_checks),
      safe_scalar_ccg(query_text),
      safe_scalar_ccg(sdtm_variable),
      safe_scalar_ccg(sdtm_domain)
    ))

    field_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      field_id = field_id,
      field_code = field_code,
      message = "Field added to CCG"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CCG Fields
#'
#' Retrieves fields for a CCG form.
#'
#' @param form_id Form ID
#' @param section_name Optional filter by section
#'
#' @return List with success status and fields
#' @export
get_ccg_fields <- function(form_id, section_name = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(section_name)) {
      fields <- DBI::dbGetQuery(con, "
        SELECT * FROM ccg_fields
        WHERE form_id = ?
        ORDER BY field_order
      ", params = list(form_id))
    } else {
      fields <- DBI::dbGetQuery(con, "
        SELECT * FROM ccg_fields
        WHERE form_id = ? AND section_name = ?
        ORDER BY field_order
      ", params = list(form_id, section_name))
    }

    list(success = TRUE, fields = fields, count = nrow(fields))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update CCG Field
#'
#' Updates a field's completion guidelines.
#'
#' @param field_id Field ID
#' @param instruction New instruction
#' @param detailed_guidance New detailed guidance
#' @param valid_values New valid values
#' @param example_entries New examples
#' @param common_errors New common errors
#'
#' @return List with success status
#' @export
update_ccg_field <- function(field_id,
                              instruction = NULL,
                              detailed_guidance = NULL,
                              valid_values = NULL,
                              example_entries = NULL,
                              common_errors = NULL) {
  tryCatch({
    if (missing(field_id) || is.null(field_id)) {
      return(list(success = FALSE, error = "field_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    updates <- c()
    params <- list()

    if (!is.null(instruction)) {
      updates <- c(updates, "instruction = ?")
      params <- append(params, list(instruction))
    }
    if (!is.null(detailed_guidance)) {
      updates <- c(updates, "detailed_guidance = ?")
      params <- append(params, list(detailed_guidance))
    }
    if (!is.null(valid_values)) {
      updates <- c(updates, "valid_values = ?")
      params <- append(params, list(valid_values))
    }
    if (!is.null(example_entries)) {
      updates <- c(updates, "example_entries = ?")
      params <- append(params, list(example_entries))
    }
    if (!is.null(common_errors)) {
      updates <- c(updates, "common_errors = ?")
      params <- append(params, list(common_errors))
    }

    if (length(updates) == 0) {
      return(list(success = FALSE, error = "No updates provided"))
    }

    updates <- c(updates, "updated_at = ?")
    params <- append(params, list(format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
    params <- append(params, list(field_id))

    query <- paste("UPDATE ccg_fields SET",
                   paste(updates, collapse = ", "),
                   "WHERE field_id = ?")

    DBI::dbExecute(con, query, params = params)

    list(success = TRUE, message = "Field updated")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# VERSION MANAGEMENT
# ============================================================================

#' Create CCG Version
#'
#' Creates a new version of a CCG form.
#'
#' @param form_id Form ID
#' @param version_number Version number (e.g., "2.0")
#' @param change_summary Summary of changes
#' @param created_by User creating version
#' @param change_details Detailed change description
#' @param effective_date When version becomes effective
#'
#' @return List with success status and version details
#' @export
create_ccg_version <- function(form_id,
                                version_number,
                                change_summary,
                                created_by,
                                change_details = NULL,
                                effective_date = NULL) {
  tryCatch({
    if (missing(form_id) || is.null(form_id)) {
      return(list(success = FALSE, error = "form_id is required"))
    }
    if (missing(version_number) || is.null(version_number) ||
        version_number == "") {
      return(list(success = FALSE, error = "version_number is required"))
    }
    if (missing(change_summary) || is.null(change_summary) ||
        nchar(change_summary) < 10) {
      return(list(success = FALSE,
                  error = "change_summary must be at least 10 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    form <- DBI::dbGetQuery(con, "
      SELECT form_id, version FROM ccg_forms WHERE form_id = ?
    ", params = list(form_id))

    if (nrow(form) == 0) {
      return(list(success = FALSE, error = "Form not found"))
    }

    previous_version <- form$version[1]
    version_date <- format(Sys.Date(), "%Y-%m-%d")

    hash_content <- paste(
      form_id,
      version_number,
      version_date,
      change_summary,
      created_by,
      sep = "|"
    )
    version_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO ccg_versions (
        form_id, version_number, version_date, change_summary,
        change_details, previous_version, effective_date,
        created_by, version_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      form_id,
      version_number,
      version_date,
      change_summary,
      safe_scalar_ccg(change_details),
      previous_version,
      safe_scalar_ccg(effective_date),
      created_by,
      version_hash
    ))

    version_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    DBI::dbExecute(con, "
      UPDATE ccg_forms SET version = ?, updated_at = ?, updated_by = ?
      WHERE form_id = ?
    ", params = list(version_number, format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                     created_by, form_id))

    list(
      success = TRUE,
      version_id = version_id,
      version_number = version_number,
      previous_version = previous_version,
      message = "CCG version created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CCG Versions
#'
#' Retrieves version history for a CCG form.
#'
#' @param form_id Form ID
#'
#' @return List with success status and versions
#' @export
get_ccg_versions <- function(form_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    versions <- DBI::dbGetQuery(con, "
      SELECT * FROM ccg_versions
      WHERE form_id = ?
      ORDER BY version_id DESC
    ", params = list(form_id))

    list(success = TRUE, versions = versions, count = nrow(versions))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Approve CCG Version
#'
#' Approves a CCG version for use.
#'
#' @param version_id Version ID
#' @param approved_by User approving
#'
#' @return List with success status
#' @export
approve_ccg_version <- function(version_id, approved_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    approved_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE ccg_versions
      SET status = 'APPROVED', approved_by = ?, approved_at = ?
      WHERE version_id = ?
    ", params = list(approved_by, approved_at, version_id))

    list(success = TRUE, approved_at = approved_at,
         message = "Version approved")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# CCG GENERATION
# ============================================================================

#' Generate CCG Document
#'
#' Generates a CRF Completion Guidelines document.
#'
#' @param form_id Form ID
#' @param output_file Output file path
#' @param format Output format: "txt", "md", or "html"
#' @param generated_by User generating document
#' @param include_examples Include example entries
#' @param include_edit_checks Include edit check rules
#' @param include_sdtm_mapping Include SDTM mappings
#' @param study_name Optional study name for header
#' @param protocol_number Optional protocol number
#'
#' @return List with success status and output file
#' @export
generate_ccg <- function(form_id,
                          output_file,
                          format = "txt",
                          generated_by,
                          include_examples = TRUE,
                          include_edit_checks = TRUE,
                          include_sdtm_mapping = FALSE,
                          study_name = NULL,
                          protocol_number = NULL) {
  tryCatch({
    if (missing(form_id) || is.null(form_id)) {
      return(list(success = FALSE, error = "form_id is required"))
    }
    if (missing(output_file) || is.null(output_file) || output_file == "") {
      return(list(success = FALSE, error = "output_file is required"))
    }
    if (!format %in% c("txt", "md", "html")) {
      return(list(success = FALSE,
                  error = "format must be 'txt', 'md', or 'html'"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    form <- DBI::dbGetQuery(con, "
      SELECT * FROM ccg_forms WHERE form_id = ?
    ", params = list(form_id))

    if (nrow(form) == 0) {
      return(list(success = FALSE, error = "Form not found"))
    }

    fields <- DBI::dbGetQuery(con, "
      SELECT * FROM ccg_fields
      WHERE form_id = ?
      ORDER BY field_order
    ", params = list(form_id))

    if (nrow(fields) == 0) {
      return(list(success = FALSE, error = "No fields defined for this form"))
    }

    if (format == "txt") {
      content <- generate_ccg_txt(form, fields, include_examples,
                                  include_edit_checks, include_sdtm_mapping,
                                  study_name, protocol_number)
    } else if (format == "md") {
      content <- generate_ccg_md(form, fields, include_examples,
                                 include_edit_checks, include_sdtm_mapping,
                                 study_name, protocol_number)
    } else {
      content <- generate_ccg_html(form, fields, include_examples,
                                   include_edit_checks, include_sdtm_mapping,
                                   study_name, protocol_number)
    }

    writeLines(content, output_file)

    hash_content <- paste(
      form_id,
      format,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      generated_by,
      sep = "|"
    )
    generation_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO ccg_generated (
        form_id, output_format, output_file, generated_by,
        include_examples, include_edit_checks, include_sdtm_mapping,
        generation_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      form_id,
      format,
      output_file,
      generated_by,
      as.integer(include_examples),
      as.integer(include_edit_checks),
      as.integer(include_sdtm_mapping),
      generation_hash
    ))

    list(
      success = TRUE,
      output_file = output_file,
      format = format,
      field_count = nrow(fields),
      message = paste("CCG generated:", output_file)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' @keywords internal
generate_ccg_txt <- function(form, fields, include_examples,
                              include_edit_checks, include_sdtm_mapping,
                              study_name, protocol_number) {
  lines <- c(
    paste(rep("=", 78), collapse = ""),
    "           CRF COMPLETION GUIDELINES",
    paste(rep("=", 78), collapse = ""),
    ""
  )

  if (!is.null(study_name)) {
    lines <- c(lines, paste("Study:", study_name))
  }
  if (!is.null(protocol_number)) {
    lines <- c(lines, paste("Protocol:", protocol_number))
  }

  lines <- c(lines,
    paste("Form:", form$form_name[1]),
    paste("Form Code:", form$form_code[1]),
    paste("Version:", form$version[1]),
    paste("Category:", form$form_category[1]),
    paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    paste(rep("-", 78), collapse = ""),
    ""
  )

  if (!is.na(form$form_description[1]) && form$form_description[1] != "") {
    lines <- c(lines,
      "PURPOSE:",
      form$form_description[1],
      ""
    )
  }

  if (!is.na(form$estimated_duration_minutes[1])) {
    lines <- c(lines,
      paste("Estimated Completion Time:",
            form$estimated_duration_minutes[1], "minutes"),
      ""
    )
  }

  lines <- c(lines,
    paste(rep("=", 78), collapse = ""),
    "           FIELD-BY-FIELD INSTRUCTIONS",
    paste(rep("=", 78), collapse = ""),
    ""
  )

  current_section <- ""

  for (i in seq_len(nrow(fields))) {
    f <- fields[i, ]

    if (!is.na(f$section_name) && f$section_name != current_section) {
      current_section <- f$section_name
      lines <- c(lines,
        "",
        paste(rep("-", 78), collapse = ""),
        paste("SECTION:", current_section),
        paste(rep("-", 78), collapse = ""),
        ""
      )
    }

    required_mark <- if (f$is_required == 1) " [REQUIRED]" else ""
    key_mark <- if (f$is_key_field == 1) " [KEY]" else ""

    lines <- c(lines,
      paste0("FIELD: ", f$field_label, required_mark, key_mark),
      paste0("  Code: ", f$field_code),
      paste0("  Type: ", f$field_type)
    )

    if (!is.na(f$instruction) && f$instruction != "") {
      lines <- c(lines, paste0("  Instruction: ", f$instruction))
    }

    if (!is.na(f$detailed_guidance) && f$detailed_guidance != "") {
      lines <- c(lines, paste0("  Guidance: ", f$detailed_guidance))
    }

    if (!is.na(f$valid_values) && f$valid_values != "") {
      lines <- c(lines, paste0("  Valid Values: ", f$valid_values))
    }

    if (!is.na(f$valid_range_min) || !is.na(f$valid_range_max)) {
      range_str <- paste0("  Valid Range: ",
                          if (!is.na(f$valid_range_min)) f$valid_range_min else "",
                          " - ",
                          if (!is.na(f$valid_range_max)) f$valid_range_max else "")
      if (!is.na(f$units) && f$units != "") {
        range_str <- paste0(range_str, " ", f$units)
      }
      lines <- c(lines, range_str)
    }

    if (!is.na(f$format_pattern) && f$format_pattern != "") {
      lines <- c(lines, paste0("  Format: ", f$format_pattern))
    }

    if (include_examples && !is.na(f$example_entries) &&
        f$example_entries != "") {
      lines <- c(lines, paste0("  Examples: ", f$example_entries))
    }

    if (!is.na(f$common_errors) && f$common_errors != "") {
      lines <- c(lines, paste0("  Common Errors: ", f$common_errors))
    }

    if (!is.na(f$source_document) && f$source_document != "") {
      lines <- c(lines, paste0("  Source: ", f$source_document))
    }

    if (!is.na(f$skip_condition) && f$skip_condition != "") {
      lines <- c(lines, paste0("  Skip If: ", f$skip_condition))
      if (!is.na(f$skip_instruction) && f$skip_instruction != "") {
        lines <- c(lines, paste0("  Skip Action: ", f$skip_instruction))
      }
    }

    if (include_edit_checks && !is.na(f$edit_checks) && f$edit_checks != "") {
      lines <- c(lines, paste0("  Edit Checks: ", f$edit_checks))
    }

    if (!is.na(f$query_text) && f$query_text != "") {
      lines <- c(lines, paste0("  Query Text: ", f$query_text))
    }

    if (include_sdtm_mapping) {
      if (!is.na(f$sdtm_domain) && f$sdtm_domain != "") {
        lines <- c(lines, paste0("  SDTM Domain: ", f$sdtm_domain))
      }
      if (!is.na(f$sdtm_variable) && f$sdtm_variable != "") {
        lines <- c(lines, paste0("  SDTM Variable: ", f$sdtm_variable))
      }
    }

    lines <- c(lines, "")
  }

  lines <- c(lines,
    paste(rep("=", 78), collapse = ""),
    "           END OF CRF COMPLETION GUIDELINES",
    paste(rep("=", 78), collapse = ""),
    ""
  )

  lines
}

#' @keywords internal
generate_ccg_md <- function(form, fields, include_examples,
                             include_edit_checks, include_sdtm_mapping,
                             study_name, protocol_number) {
  lines <- c(
    "# CRF Completion Guidelines",
    ""
  )

  if (!is.null(study_name)) {
    lines <- c(lines, paste("**Study:**", study_name))
  }
  if (!is.null(protocol_number)) {
    lines <- c(lines, paste("**Protocol:**", protocol_number))
  }

  lines <- c(lines,
    paste("**Form:**", form$form_name[1]),
    paste("**Form Code:**", form$form_code[1]),
    paste("**Version:**", form$version[1]),
    paste("**Generated:**", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    "---",
    ""
  )

  if (!is.na(form$form_description[1]) && form$form_description[1] != "") {
    lines <- c(lines,
      "## Purpose",
      "",
      form$form_description[1],
      ""
    )
  }

  lines <- c(lines,
    "## Field Instructions",
    ""
  )

  current_section <- ""

  for (i in seq_len(nrow(fields))) {
    f <- fields[i, ]

    if (!is.na(f$section_name) && f$section_name != current_section) {
      current_section <- f$section_name
      lines <- c(lines,
        paste("###", current_section),
        ""
      )
    }

    required_mark <- if (f$is_required == 1) " `[REQUIRED]`" else ""
    key_mark <- if (f$is_key_field == 1) " `[KEY]`" else ""

    lines <- c(lines,
      paste0("#### ", f$field_label, required_mark, key_mark),
      "",
      paste0("- **Code:** ", f$field_code),
      paste0("- **Type:** ", f$field_type)
    )

    if (!is.na(f$instruction) && f$instruction != "") {
      lines <- c(lines, paste0("- **Instruction:** ", f$instruction))
    }

    if (!is.na(f$valid_values) && f$valid_values != "") {
      lines <- c(lines, paste0("- **Valid Values:** ", f$valid_values))
    }

    if (include_examples && !is.na(f$example_entries) &&
        f$example_entries != "") {
      lines <- c(lines, paste0("- **Examples:** ", f$example_entries))
    }

    if (!is.na(f$common_errors) && f$common_errors != "") {
      lines <- c(lines, paste0("- **Avoid:** ", f$common_errors))
    }

    lines <- c(lines, "")
  }

  lines
}

#' @keywords internal
generate_ccg_html <- function(form, fields, include_examples,
                               include_edit_checks, include_sdtm_mapping,
                               study_name, protocol_number) {
  html <- c(
    "<!DOCTYPE html>",
    "<html>",
    "<head>",
    "<meta charset='UTF-8'>",
    paste0("<title>CCG - ", form$form_name[1], "</title>"),
    "<style>",
    "body { font-family: Arial, sans-serif; margin: 40px; }",
    "h1 { color: #333; }",
    "h2 { color: #555; border-bottom: 1px solid #ccc; }",
    "h3 { color: #666; }",
    ".field { margin: 20px 0; padding: 15px; background: #f9f9f9; }",
    ".required { color: #c00; font-weight: bold; }",
    ".key { color: #00c; font-weight: bold; }",
    "dt { font-weight: bold; }",
    "dd { margin-bottom: 10px; }",
    "</style>",
    "</head>",
    "<body>",
    "<h1>CRF Completion Guidelines</h1>"
  )

  html <- c(html,
    paste0("<p><strong>Form:</strong> ", form$form_name[1], "</p>"),
    paste0("<p><strong>Version:</strong> ", form$version[1], "</p>"),
    paste0("<p><strong>Generated:</strong> ",
           format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "</p>"),
    "<hr>"
  )

  html <- c(html, "<h2>Field Instructions</h2>")

  current_section <- ""

  for (i in seq_len(nrow(fields))) {
    f <- fields[i, ]

    if (!is.na(f$section_name) && f$section_name != current_section) {
      current_section <- f$section_name
      html <- c(html, paste0("<h3>", current_section, "</h3>"))
    }

    required_mark <- if (f$is_required == 1) {
      " <span class='required'>[REQUIRED]</span>"
    } else ""
    key_mark <- if (f$is_key_field == 1) {
      " <span class='key'>[KEY]</span>"
    } else ""

    html <- c(html,
      "<div class='field'>",
      paste0("<h4>", f$field_label, required_mark, key_mark, "</h4>"),
      "<dl>",
      paste0("<dt>Code:</dt><dd>", f$field_code, "</dd>"),
      paste0("<dt>Type:</dt><dd>", f$field_type, "</dd>")
    )

    if (!is.na(f$instruction) && f$instruction != "") {
      html <- c(html,
        paste0("<dt>Instruction:</dt><dd>", f$instruction, "</dd>"))
    }

    if (!is.na(f$valid_values) && f$valid_values != "") {
      html <- c(html,
        paste0("<dt>Valid Values:</dt><dd>", f$valid_values, "</dd>"))
    }

    if (include_examples && !is.na(f$example_entries) &&
        f$example_entries != "") {
      html <- c(html,
        paste0("<dt>Examples:</dt><dd>", f$example_entries, "</dd>"))
    }

    html <- c(html, "</dl>", "</div>")
  }

  html <- c(html, "</body>", "</html>")

  html
}

# ============================================================================
# STATISTICS AND REPORTING
# ============================================================================

#' Get CCG Statistics
#'
#' Returns CCG system statistics.
#'
#' @return List with statistics
#' @export
get_ccg_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    form_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'DRAFT' THEN 1 ELSE 0 END) as draft,
        SUM(CASE WHEN status = 'APPROVED' THEN 1 ELSE 0 END) as approved,
        SUM(is_active) as active
      FROM ccg_forms
    ")

    field_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(is_required) as required_fields,
        SUM(is_key_field) as key_fields
      FROM ccg_fields
    ")

    generation_stats <- DBI::dbGetQuery(con, "
      SELECT COUNT(*) as total FROM ccg_generated
    ")

    by_category <- DBI::dbGetQuery(con, "
      SELECT form_category, COUNT(*) as count
      FROM ccg_forms
      WHERE form_category IS NOT NULL
      GROUP BY form_category
    ")

    list(
      success = TRUE,
      forms = as.list(form_stats),
      fields = as.list(field_stats),
      generations = generation_stats$total[1],
      by_category = by_category
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
