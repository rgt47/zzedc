#' CRF Template Library System
#'
#' Provides pre-built CRF templates for common clinical trial forms.
#' Templates can be customized and used as starting points for new CRFs.
#'
#' @name crf_templates
#' @docType package
NULL

#' @keywords internal
safe_scalar_tpl <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize CRF Template System
#' @return List with success status
#' @export
init_crf_templates <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_templates (
        template_id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_code TEXT UNIQUE NOT NULL,
        template_name TEXT NOT NULL,
        template_category TEXT NOT NULL,
        template_description TEXT,
        therapeutic_area TEXT,
        regulatory_standard TEXT,
        is_cdisc_compliant INTEGER DEFAULT 0,
        version TEXT DEFAULT '1.0',
        usage_count INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_template_fields (
        template_field_id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_id INTEGER NOT NULL,
        field_lib_id INTEGER,
        field_code TEXT NOT NULL,
        field_name TEXT NOT NULL,
        field_label TEXT NOT NULL,
        field_type TEXT NOT NULL,
        field_order INTEGER NOT NULL,
        section_name TEXT,
        is_required INTEGER DEFAULT 0,
        default_value TEXT,
        validation_rule TEXT,
        help_text TEXT,
        FOREIGN KEY (template_id) REFERENCES crf_templates(template_id),
        FOREIGN KEY (field_lib_id) REFERENCES field_library(field_lib_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_template_usage (
        usage_id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_id INTEGER NOT NULL,
        crf_id INTEGER,
        study_name TEXT,
        used_at TEXT DEFAULT (datetime('now')),
        used_by TEXT NOT NULL,
        customizations TEXT,
        FOREIGN KEY (template_id) REFERENCES crf_templates(template_id)
      )
    ")

    list(success = TRUE, message = "CRF template system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Template Categories
#' @return Named character vector
#' @export
get_template_categories <- function() {
  c(
    DEMOGRAPHICS = "Demographics forms",
    ELIGIBILITY = "Eligibility/screening forms",
    VITAL_SIGNS = "Vital signs forms",
    PHYSICAL_EXAM = "Physical examination forms",
    MEDICAL_HISTORY = "Medical history forms",
    CONCOMITANT_MEDS = "Concomitant medications",
    ADVERSE_EVENTS = "Adverse event forms",
    LABORATORY = "Laboratory results",
    EFFICACY = "Efficacy assessment forms",
    STUDY_DRUG = "Study drug administration",
    DISPOSITION = "Subject disposition",
    QUALITY_OF_LIFE = "Quality of life questionnaires"
  )
}

#' Create CRF Template
#' @param template_code Unique template code
#' @param template_name Template name
#' @param template_category Category
#' @param created_by User creating template
#' @param template_description Optional description
#' @param therapeutic_area Optional therapeutic area
#' @param is_cdisc_compliant Whether CDISC compliant
#' @return List with success status
#' @export
create_crf_template <- function(template_code, template_name, template_category,
                                 created_by, template_description = NULL,
                                 therapeutic_area = NULL,
                                 is_cdisc_compliant = FALSE) {
  tryCatch({
    if (missing(template_code) || template_code == "") {
      return(list(success = FALSE, error = "template_code is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO crf_templates (
        template_code, template_name, template_category, template_description,
        therapeutic_area, is_cdisc_compliant, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      template_code, template_name, template_category,
      safe_scalar_tpl(template_description),
      safe_scalar_tpl(therapeutic_area),
      as.integer(is_cdisc_compliant), created_by
    ))

    template_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, template_id = template_id,
         message = "Template created")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Field to Template
#' @param template_id Template ID
#' @param field_code Field code
#' @param field_name Field name
#' @param field_label Field label
#' @param field_type Field type
#' @param field_order Display order
#' @param section_name Optional section
#' @param is_required Whether required
#' @param field_lib_id Optional link to library field
#' @param help_text Optional help text
#' @return List with success status
#' @export
add_template_field <- function(template_id, field_code, field_name,
                                field_label, field_type, field_order,
                                section_name = NULL, is_required = FALSE,
                                field_lib_id = NULL, help_text = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO crf_template_fields (
        template_id, field_lib_id, field_code, field_name, field_label,
        field_type, field_order, section_name, is_required, help_text
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      template_id,
      if (is.null(field_lib_id)) NA_integer_ else as.integer(field_lib_id),
      field_code, field_name, field_label, field_type, as.integer(field_order),
      safe_scalar_tpl(section_name), as.integer(is_required),
      safe_scalar_tpl(help_text)
    ))

    list(success = TRUE, message = "Field added to template")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CRF Templates
#' @param template_category Optional category filter
#' @param include_inactive Include inactive templates
#' @return List with templates
#' @export
get_crf_templates <- function(template_category = NULL,
                               include_inactive = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM crf_templates WHERE 1=1"
    params <- list()

    if (!include_inactive) {
      query <- paste(query, "AND is_active = 1")
    }
    if (!is.null(template_category)) {
      query <- paste(query, "AND template_category = ?")
      params <- append(params, list(template_category))
    }

    query <- paste(query, "ORDER BY template_category, template_name")

    if (length(params) > 0) {
      templates <- DBI::dbGetQuery(con, query, params = params)
    } else {
      templates <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, templates = templates, count = nrow(templates))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Template Fields
#' @param template_id Template ID
#' @return List with fields
#' @export
get_template_fields <- function(template_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    fields <- DBI::dbGetQuery(con, "
      SELECT * FROM crf_template_fields
      WHERE template_id = ?
      ORDER BY field_order
    ", params = list(template_id))

    list(success = TRUE, fields = fields, count = nrow(fields))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Use Template
#' @param template_id Template ID
#' @param used_by User
#' @param study_name Optional study name
#' @param crf_id Optional CRF ID
#' @return List with success status
#' @export
use_template <- function(template_id, used_by, study_name = NULL,
                          crf_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO crf_template_usage (template_id, crf_id, study_name, used_by)
      VALUES (?, ?, ?, ?)
    ", params = list(
      template_id,
      if (is.null(crf_id)) NA_integer_ else as.integer(crf_id),
      safe_scalar_tpl(study_name), used_by
    ))

    DBI::dbExecute(con, "
      UPDATE crf_templates SET usage_count = usage_count + 1
      WHERE template_id = ?
    ", params = list(template_id))

    list(success = TRUE, message = "Template usage recorded")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Load Standard Templates
#' @param loaded_by User loading templates
#' @return List with count
#' @export
load_standard_templates <- function(loaded_by) {
  tryCatch({
    templates <- list(
      list(code = "TPL_DM_BASIC", name = "Basic Demographics",
           cat = "DEMOGRAPHICS", desc = "Standard demographics form",
           fields = list(
             list(code = "SUBJID", name = "Subject ID",
                  label = "Subject Identifier", type = "TEXT", order = 1,
                  section = "Identification", required = TRUE),
             list(code = "BRTHDTC", name = "Birth Date",
                  label = "Date of Birth", type = "DATE", order = 2,
                  section = "Demographics", required = TRUE),
             list(code = "SEX", name = "Sex", label = "Sex",
                  type = "RADIO", order = 3, section = "Demographics",
                  required = TRUE),
             list(code = "RACE", name = "Race", label = "Race",
                  type = "CHECKBOX", order = 4, section = "Demographics"),
             list(code = "ETHNIC", name = "Ethnicity",
                  label = "Ethnicity", type = "RADIO", order = 5,
                  section = "Demographics")
           )),
      list(code = "TPL_VS_STANDARD", name = "Standard Vital Signs",
           cat = "VITAL_SIGNS", desc = "Standard vital signs form",
           fields = list(
             list(code = "VSDTC", name = "Date", label = "Assessment Date",
                  type = "DATE", order = 1, section = "Visit", required = TRUE),
             list(code = "SYSBP", name = "Systolic BP",
                  label = "Systolic Blood Pressure", type = "INTEGER",
                  order = 2, section = "Blood Pressure", required = TRUE),
             list(code = "DIABP", name = "Diastolic BP",
                  label = "Diastolic Blood Pressure", type = "INTEGER",
                  order = 3, section = "Blood Pressure", required = TRUE),
             list(code = "PULSE", name = "Pulse", label = "Heart Rate",
                  type = "INTEGER", order = 4, section = "Vitals"),
             list(code = "TEMP", name = "Temperature",
                  label = "Body Temperature", type = "NUMBER", order = 5,
                  section = "Vitals"),
             list(code = "RESP", name = "Respiratory Rate",
                  label = "Respiratory Rate", type = "INTEGER", order = 6,
                  section = "Vitals")
           )),
      list(code = "TPL_AE_STANDARD", name = "Standard Adverse Events",
           cat = "ADVERSE_EVENTS", desc = "Standard AE reporting form",
           fields = list(
             list(code = "AETERM", name = "AE Term",
                  label = "Adverse Event Term", type = "TEXT", order = 1,
                  section = "Event Details", required = TRUE),
             list(code = "AESTDTC", name = "Start Date",
                  label = "Start Date", type = "DATE", order = 2,
                  section = "Dates", required = TRUE),
             list(code = "AEENDTC", name = "End Date",
                  label = "End Date", type = "DATE", order = 3,
                  section = "Dates"),
             list(code = "AESEV", name = "Severity",
                  label = "Severity", type = "RADIO", order = 4,
                  section = "Assessment", required = TRUE),
             list(code = "AESER", name = "Serious",
                  label = "Serious Event?", type = "RADIO", order = 5,
                  section = "Assessment", required = TRUE),
             list(code = "AEREL", name = "Relationship",
                  label = "Relationship to Study Drug", type = "RADIO",
                  order = 6, section = "Assessment")
           ))
    )

    count <- 0
    for (t in templates) {
      result <- create_crf_template(
        template_code = t$code,
        template_name = t$name,
        template_category = t$cat,
        created_by = loaded_by,
        template_description = t$desc,
        is_cdisc_compliant = TRUE
      )

      if (result$success) {
        count <- count + 1
        for (f in t$fields) {
          add_template_field(
            template_id = result$template_id,
            field_code = f$code,
            field_name = f$name,
            field_label = f$label,
            field_type = f$type,
            field_order = f$order,
            section_name = f$section,
            is_required = if (!is.null(f$required)) f$required else FALSE
          )
        }
      }
    }

    list(success = TRUE, templates_loaded = count,
         message = paste(count, "standard templates loaded"))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Template Statistics
#' @return List with statistics
#' @export
get_template_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_templates,
        SUM(is_active) as active_templates,
        SUM(is_cdisc_compliant) as cdisc_templates,
        SUM(usage_count) as total_usage
      FROM crf_templates
    ")

    by_category <- DBI::dbGetQuery(con, "
      SELECT template_category, COUNT(*) as count
      FROM crf_templates WHERE is_active = 1
      GROUP BY template_category
    ")

    list(success = TRUE, totals = as.list(stats), by_category = by_category)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
