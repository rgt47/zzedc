#' Master Field Library System
#'
#' Centralized library of standard field definitions for reuse
#' across CRFs. Supports CDISC-compliant fields, custom fields,
#' and field templates with validation rules.
#'
#' @name field_library
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' @keywords internal
safe_scalar_fl <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' @keywords internal
safe_int_fl <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize Field Library System
#'
#' Creates database tables for the master field library.
#'
#' @return List with success status and message
#' @export
init_field_library <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS field_library (
        field_lib_id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_code TEXT UNIQUE NOT NULL,
        field_name TEXT NOT NULL,
        field_label TEXT NOT NULL,
        field_type TEXT NOT NULL,
        field_category TEXT NOT NULL,
        field_domain TEXT,
        is_cdisc_standard INTEGER DEFAULT 0,
        cdisc_variable TEXT,
        cdisc_domain TEXT,
        controlled_terminology TEXT,
        description TEXT,
        data_type TEXT,
        length INTEGER,
        decimal_places INTEGER,
        valid_values TEXT,
        valid_range_min TEXT,
        valid_range_max TEXT,
        units TEXT,
        format_pattern TEXT,
        default_value TEXT,
        is_required INTEGER DEFAULT 0,
        is_key_field INTEGER DEFAULT 0,
        is_derived INTEGER DEFAULT 0,
        derivation_rule TEXT,
        validation_rules TEXT,
        completion_instruction TEXT,
        source_guidance TEXT,
        is_active INTEGER DEFAULT 1,
        usage_count INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS field_library_versions (
        version_id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_lib_id INTEGER NOT NULL,
        version_number INTEGER NOT NULL,
        change_description TEXT NOT NULL,
        field_snapshot TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        version_hash TEXT NOT NULL,
        FOREIGN KEY (field_lib_id) REFERENCES field_library(field_lib_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS field_library_usage (
        usage_id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_lib_id INTEGER NOT NULL,
        crf_id INTEGER,
        form_id INTEGER,
        used_at TEXT DEFAULT (datetime('now')),
        used_by TEXT NOT NULL,
        customizations TEXT,
        FOREIGN KEY (field_lib_id) REFERENCES field_library(field_lib_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS field_categories (
        category_id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_code TEXT UNIQUE NOT NULL,
        category_name TEXT NOT NULL,
        category_description TEXT,
        parent_category_id INTEGER,
        display_order INTEGER,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (parent_category_id) REFERENCES field_categories(category_id)
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_field_lib_code
                         ON field_library(field_code)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_field_lib_category
                         ON field_library(field_category)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_field_lib_cdisc
                         ON field_library(cdisc_domain, cdisc_variable)")

    list(success = TRUE, message = "Field library system initialized")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Field Categories
#' @return Named character vector of field categories
#' @export
get_field_library_categories <- function() {
  c(
    SUBJECT_ID = "Subject identification fields",
    DEMOGRAPHICS = "Demographic information",
    VITAL_SIGNS = "Vital signs measurements",
    LAB_RESULTS = "Laboratory results",
    MEDICAL_HISTORY = "Medical history",
    PHYSICAL_EXAM = "Physical examination",
    CONCOMITANT_MEDS = "Concomitant medications",
    ADVERSE_EVENTS = "Adverse event reporting",
    EFFICACY = "Efficacy assessments",
    STUDY_DRUG = "Study drug administration",
    DATES = "Date fields",
    ADMINISTRATIVE = "Administrative fields",
    CUSTOM = "Custom fields"
  )
}

#' Get Field Data Types
#' @return Named character vector of data types
#' @export
get_field_data_types <- function() {
  c(
    TEXT = "Character/text data",
    INTEGER = "Whole numbers",
    FLOAT = "Decimal numbers",
    DATE = "Date (YYYY-MM-DD)",
    TIME = "Time (HH:MM:SS)",
    DATETIME = "Date and time",
    BOOLEAN = "Yes/No values",
    CODED = "Coded values from terminology"
  )
}

#' Get CDISC Domains
#' @return Named character vector of CDISC domains
#' @export
get_cdisc_domains <- function() {
  c(
    DM = "Demographics",
    VS = "Vital Signs",
    LB = "Laboratory",
    AE = "Adverse Events",
    CM = "Concomitant Medications",
    MH = "Medical History",
    PE = "Physical Examination",
    EX = "Exposure",
    DS = "Disposition",
    SV = "Subject Visits",
    EG = "ECG",
    IE = "Inclusion/Exclusion",
    SC = "Subject Characteristics",
    QS = "Questionnaires"
  )
}

# ============================================================================
# CATEGORY MANAGEMENT
# ============================================================================

#' Create Field Category
#'
#' Creates a new category for organizing fields.
#'
#' @param category_code Unique category code
#' @param category_name Category name
#' @param category_description Optional description
#' @param parent_category_id Optional parent for hierarchy
#' @param display_order Optional display order
#'
#' @return List with success status
#' @export
create_field_category <- function(category_code,
                                   category_name,
                                   category_description = NULL,
                                   parent_category_id = NULL,
                                   display_order = NULL) {
  tryCatch({
    if (missing(category_code) || category_code == "") {
      return(list(success = FALSE, error = "category_code is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO field_categories (
        category_code, category_name, category_description,
        parent_category_id, display_order
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(
      category_code,
      category_name,
      safe_scalar_fl(category_description),
      safe_int_fl(parent_category_id),
      safe_int_fl(display_order)
    ))

    category_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, category_id = category_id, message = "Category created")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Field Categories from Database
#'
#' Retrieves field categories.
#'
#' @param include_inactive Include inactive categories
#'
#' @return List with success status and categories
#' @export
get_field_categories <- function(include_inactive = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (include_inactive) {
      categories <- DBI::dbGetQuery(con, "
        SELECT * FROM field_categories ORDER BY display_order, category_name
      ")
    } else {
      categories <- DBI::dbGetQuery(con, "
        SELECT * FROM field_categories
        WHERE is_active = 1
        ORDER BY display_order, category_name
      ")
    }

    list(success = TRUE, categories = categories, count = nrow(categories))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# FIELD LIBRARY MANAGEMENT
# ============================================================================

#' Add Field to Library
#'
#' Adds a new field definition to the master library.
#'
#' @param field_code Unique field code
#' @param field_name Field name
#' @param field_label Display label
#' @param field_type Field input type
#' @param field_category Category
#' @param created_by User creating field
#' @param field_domain Optional domain
#' @param is_cdisc_standard Whether CDISC standard
#' @param cdisc_variable CDISC variable name
#' @param cdisc_domain CDISC domain
#' @param controlled_terminology Controlled terminology reference
#' @param description Field description
#' @param data_type Data type
#' @param length Maximum length
#' @param decimal_places Decimal places for numbers
#' @param valid_values Valid values for coded fields
#' @param valid_range_min Minimum value
#' @param valid_range_max Maximum value
#' @param units Units of measurement
#' @param format_pattern Format pattern
#' @param default_value Default value
#' @param is_required Whether required
#' @param is_key_field Whether key field
#' @param is_derived Whether derived
#' @param derivation_rule Derivation rule
#' @param validation_rules Validation rules
#' @param completion_instruction Completion instruction
#' @param source_guidance Source guidance
#'
#' @return List with success status and field details
#' @export
add_library_field <- function(field_code,
                               field_name,
                               field_label,
                               field_type,
                               field_category,
                               created_by,
                               field_domain = NULL,
                               is_cdisc_standard = FALSE,
                               cdisc_variable = NULL,
                               cdisc_domain = NULL,
                               controlled_terminology = NULL,
                               description = NULL,
                               data_type = NULL,
                               length = NULL,
                               decimal_places = NULL,
                               valid_values = NULL,
                               valid_range_min = NULL,
                               valid_range_max = NULL,
                               units = NULL,
                               format_pattern = NULL,
                               default_value = NULL,
                               is_required = FALSE,
                               is_key_field = FALSE,
                               is_derived = FALSE,
                               derivation_rule = NULL,
                               validation_rules = NULL,
                               completion_instruction = NULL,
                               source_guidance = NULL) {
  tryCatch({
    if (missing(field_code) || is.null(field_code) || field_code == "") {
      return(list(success = FALSE, error = "field_code is required"))
    }
    if (missing(field_label) || is.null(field_label) || field_label == "") {
      return(list(success = FALSE, error = "field_label is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    existing <- DBI::dbGetQuery(con, "
      SELECT field_lib_id FROM field_library WHERE field_code = ?
    ", params = list(field_code))

    if (nrow(existing) > 0) {
      return(list(success = FALSE, error = "field_code already exists"))
    }

    DBI::dbExecute(con, "
      INSERT INTO field_library (
        field_code, field_name, field_label, field_type, field_category,
        field_domain, is_cdisc_standard, cdisc_variable, cdisc_domain,
        controlled_terminology, description, data_type, length,
        decimal_places, valid_values, valid_range_min, valid_range_max,
        units, format_pattern, default_value, is_required, is_key_field,
        is_derived, derivation_rule, validation_rules, completion_instruction,
        source_guidance, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      field_code, field_name, field_label, field_type, field_category,
      safe_scalar_fl(field_domain),
      as.integer(is_cdisc_standard),
      safe_scalar_fl(cdisc_variable),
      safe_scalar_fl(cdisc_domain),
      safe_scalar_fl(controlled_terminology),
      safe_scalar_fl(description),
      safe_scalar_fl(data_type),
      safe_int_fl(length),
      safe_int_fl(decimal_places),
      safe_scalar_fl(valid_values),
      safe_scalar_fl(valid_range_min),
      safe_scalar_fl(valid_range_max),
      safe_scalar_fl(units),
      safe_scalar_fl(format_pattern),
      safe_scalar_fl(default_value),
      as.integer(is_required),
      as.integer(is_key_field),
      as.integer(is_derived),
      safe_scalar_fl(derivation_rule),
      safe_scalar_fl(validation_rules),
      safe_scalar_fl(completion_instruction),
      safe_scalar_fl(source_guidance),
      created_by
    ))

    field_lib_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      field_lib_id = field_lib_id,
      field_code = field_code,
      message = "Field added to library"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Library Fields
#'
#' Retrieves fields from the library.
#'
#' @param field_category Optional category filter
#' @param cdisc_domain Optional CDISC domain filter
#' @param is_cdisc_standard Optional filter for CDISC fields
#' @param include_inactive Include inactive fields
#' @param search_term Optional search term
#'
#' @return List with success status and fields
#' @export
get_library_fields <- function(field_category = NULL,
                                cdisc_domain = NULL,
                                is_cdisc_standard = NULL,
                                include_inactive = FALSE,
                                search_term = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM field_library WHERE 1=1"
    params <- list()

    if (!include_inactive) {
      query <- paste(query, "AND is_active = 1")
    }

    if (!is.null(field_category)) {
      query <- paste(query, "AND field_category = ?")
      params <- append(params, list(field_category))
    }

    if (!is.null(cdisc_domain)) {
      query <- paste(query, "AND cdisc_domain = ?")
      params <- append(params, list(cdisc_domain))
    }

    if (!is.null(is_cdisc_standard)) {
      query <- paste(query, "AND is_cdisc_standard = ?")
      params <- append(params, list(as.integer(is_cdisc_standard)))
    }

    if (!is.null(search_term)) {
      query <- paste(query, "AND (field_code LIKE ? OR field_name LIKE ? OR",
                     "field_label LIKE ? OR description LIKE ?)")
      search_pattern <- paste0("%", search_term, "%")
      params <- append(params, list(search_pattern, search_pattern,
                                    search_pattern, search_pattern))
    }

    query <- paste(query, "ORDER BY field_category, field_code")

    if (length(params) > 0) {
      fields <- DBI::dbGetQuery(con, query, params = params)
    } else {
      fields <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, fields = fields, count = nrow(fields))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Library Field by Code
#'
#' Retrieves a single field by code.
#'
#' @param field_code Field code
#'
#' @return List with success status and field details
#' @export
get_library_field <- function(field_code) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    field <- DBI::dbGetQuery(con, "
      SELECT * FROM field_library WHERE field_code = ?
    ", params = list(field_code))

    if (nrow(field) == 0) {
      return(list(success = FALSE, error = "Field not found"))
    }

    list(success = TRUE, field = as.list(field[1, ]))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update Library Field
#'
#' Updates a field in the library.
#'
#' @param field_lib_id Field library ID
#' @param updated_by User updating
#' @param field_label New label
#' @param description New description
#' @param valid_values New valid values
#' @param validation_rules New validation rules
#' @param completion_instruction New completion instruction
#'
#' @return List with success status
#' @export
update_library_field <- function(field_lib_id,
                                  updated_by,
                                  field_label = NULL,
                                  description = NULL,
                                  valid_values = NULL,
                                  validation_rules = NULL,
                                  completion_instruction = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    updates <- c()
    params <- list()

    if (!is.null(field_label)) {
      updates <- c(updates, "field_label = ?")
      params <- append(params, list(field_label))
    }
    if (!is.null(description)) {
      updates <- c(updates, "description = ?")
      params <- append(params, list(description))
    }
    if (!is.null(valid_values)) {
      updates <- c(updates, "valid_values = ?")
      params <- append(params, list(valid_values))
    }
    if (!is.null(validation_rules)) {
      updates <- c(updates, "validation_rules = ?")
      params <- append(params, list(validation_rules))
    }
    if (!is.null(completion_instruction)) {
      updates <- c(updates, "completion_instruction = ?")
      params <- append(params, list(completion_instruction))
    }

    if (length(updates) == 0) {
      return(list(success = FALSE, error = "No updates provided"))
    }

    updates <- c(updates, "updated_at = ?", "updated_by = ?")
    params <- append(params, list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                                  updated_by))
    params <- append(params, list(field_lib_id))

    query <- paste("UPDATE field_library SET",
                   paste(updates, collapse = ", "),
                   "WHERE field_lib_id = ?")

    DBI::dbExecute(con, query, params = params)

    list(success = TRUE, message = "Field updated")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Deactivate Library Field
#'
#' Deactivates a field (soft delete).
#'
#' @param field_lib_id Field library ID
#' @param deactivated_by User deactivating
#'
#' @return List with success status
#' @export
deactivate_library_field <- function(field_lib_id, deactivated_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE field_library
      SET is_active = 0, updated_at = ?, updated_by = ?
      WHERE field_lib_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      deactivated_by,
      field_lib_id
    ))

    list(success = TRUE, message = "Field deactivated")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# FIELD USAGE TRACKING
# ============================================================================

#' Record Field Usage
#'
#' Records when a library field is used in a CRF.
#'
#' @param field_lib_id Field library ID
#' @param used_by User using the field
#' @param crf_id Optional CRF ID
#' @param form_id Optional form ID
#' @param customizations Optional customizations applied
#'
#' @return List with success status
#' @export
record_field_usage <- function(field_lib_id,
                                used_by,
                                crf_id = NULL,
                                form_id = NULL,
                                customizations = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO field_library_usage (
        field_lib_id, crf_id, form_id, used_by, customizations
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(
      field_lib_id,
      safe_int_fl(crf_id),
      safe_int_fl(form_id),
      used_by,
      safe_scalar_fl(customizations)
    ))

    DBI::dbExecute(con, "
      UPDATE field_library
      SET usage_count = usage_count + 1
      WHERE field_lib_id = ?
    ", params = list(field_lib_id))

    list(success = TRUE, message = "Usage recorded")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Field Usage
#'
#' Retrieves usage history for a field.
#'
#' @param field_lib_id Field library ID
#'
#' @return List with success status and usage records
#' @export
get_field_usage <- function(field_lib_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    usage <- DBI::dbGetQuery(con, "
      SELECT * FROM field_library_usage
      WHERE field_lib_id = ?
      ORDER BY used_at DESC
    ", params = list(field_lib_id))

    list(success = TRUE, usage = usage, count = nrow(usage))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# CDISC STANDARD FIELDS
# ============================================================================

#' Load CDISC Standard Fields
#'
#' Loads standard CDISC SDTM fields into the library.
#'
#' @param loaded_by User loading the fields
#'
#' @return List with success status and count
#' @export
load_cdisc_standard_fields <- function(loaded_by) {
  tryCatch({
    cdisc_fields <- list(
      list(code = "USUBJID", name = "Unique Subject Identifier",
           label = "Unique Subject Identifier", domain = "DM",
           type = "TEXT", category = "SUBJECT_ID",
           description = "Identifier for each subject unique within the study"),
      list(code = "SUBJID", name = "Subject Identifier for Study",
           label = "Subject Identifier", domain = "DM",
           type = "TEXT", category = "SUBJECT_ID",
           description = "Subject identifier used within the study"),
      list(code = "SITEID", name = "Study Site Identifier",
           label = "Site Identifier", domain = "DM",
           type = "TEXT", category = "SUBJECT_ID",
           description = "Unique identifier for a site within the study"),
      list(code = "BRTHDTC", name = "Date of Birth",
           label = "Date of Birth", domain = "DM",
           type = "DATE", category = "DEMOGRAPHICS",
           description = "Date of birth in ISO 8601 format"),
      list(code = "AGE", name = "Age",
           label = "Age", domain = "DM",
           type = "INTEGER", category = "DEMOGRAPHICS",
           description = "Age of subject at time of informed consent"),
      list(code = "SEX", name = "Sex",
           label = "Sex", domain = "DM",
           type = "RADIO", category = "DEMOGRAPHICS",
           description = "Sex of subject",
           valid_values = "M=Male; F=Female; U=Unknown"),
      list(code = "RACE", name = "Race",
           label = "Race", domain = "DM",
           type = "CHECKBOX", category = "DEMOGRAPHICS",
           description = "Race of the subject"),
      list(code = "ETHNIC", name = "Ethnicity",
           label = "Ethnicity", domain = "DM",
           type = "RADIO", category = "DEMOGRAPHICS",
           description = "Ethnicity of the subject"),
      list(code = "SYSBP", name = "Systolic Blood Pressure",
           label = "Systolic BP", domain = "VS",
           type = "INTEGER", category = "VITAL_SIGNS",
           description = "Systolic blood pressure",
           units = "mmHg", valid_range_min = "60", valid_range_max = "250"),
      list(code = "DIABP", name = "Diastolic Blood Pressure",
           label = "Diastolic BP", domain = "VS",
           type = "INTEGER", category = "VITAL_SIGNS",
           description = "Diastolic blood pressure",
           units = "mmHg", valid_range_min = "40", valid_range_max = "150"),
      list(code = "PULSE", name = "Pulse Rate",
           label = "Heart Rate", domain = "VS",
           type = "INTEGER", category = "VITAL_SIGNS",
           description = "Heart rate/pulse",
           units = "bpm", valid_range_min = "40", valid_range_max = "200"),
      list(code = "TEMP", name = "Temperature",
           label = "Body Temperature", domain = "VS",
           type = "NUMBER", category = "VITAL_SIGNS",
           description = "Body temperature",
           units = "C", valid_range_min = "35", valid_range_max = "42"),
      list(code = "HEIGHT", name = "Height",
           label = "Height", domain = "VS",
           type = "NUMBER", category = "VITAL_SIGNS",
           description = "Subject height",
           units = "cm", valid_range_min = "50", valid_range_max = "250"),
      list(code = "WEIGHT", name = "Weight",
           label = "Weight", domain = "VS",
           type = "NUMBER", category = "VITAL_SIGNS",
           description = "Subject weight",
           units = "kg", valid_range_min = "20", valid_range_max = "300")
    )

    count <- 0
    for (f in cdisc_fields) {
      result <- add_library_field(
        field_code = f$code,
        field_name = f$name,
        field_label = f$label,
        field_type = f$type,
        field_category = f$category,
        created_by = loaded_by,
        is_cdisc_standard = TRUE,
        cdisc_variable = f$code,
        cdisc_domain = f$domain,
        description = f$description,
        valid_values = if (!is.null(f$valid_values)) f$valid_values else NULL,
        valid_range_min = if (!is.null(f$valid_range_min)) f$valid_range_min
                          else NULL,
        valid_range_max = if (!is.null(f$valid_range_max)) f$valid_range_max
                          else NULL,
        units = if (!is.null(f$units)) f$units else NULL
      )
      if (result$success) count <- count + 1
    }

    list(success = TRUE, fields_loaded = count,
         message = paste(count, "CDISC standard fields loaded"))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# STATISTICS
# ============================================================================

#' Get Field Library Statistics
#'
#' Returns statistics about the field library.
#'
#' @return List with statistics
#' @export
get_field_library_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    total_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_fields,
        SUM(is_active) as active_fields,
        SUM(is_cdisc_standard) as cdisc_fields,
        SUM(usage_count) as total_usage
      FROM field_library
    ")

    by_category <- DBI::dbGetQuery(con, "
      SELECT field_category, COUNT(*) as count
      FROM field_library
      WHERE is_active = 1
      GROUP BY field_category
      ORDER BY count DESC
    ")

    most_used <- DBI::dbGetQuery(con, "
      SELECT field_code, field_name, usage_count
      FROM field_library
      WHERE is_active = 1
      ORDER BY usage_count DESC
      LIMIT 10
    ")

    list(
      success = TRUE,
      totals = as.list(total_stats),
      by_category = by_category,
      most_used = most_used
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
