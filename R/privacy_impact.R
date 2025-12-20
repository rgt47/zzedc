#' Privacy Impact Assessment (PIA) Tool (Feature #28)
#'
#' GDPR Article 35 compliant privacy impact assessment system for
#' evaluating data processing activities and privacy risks.
#'
#' @name privacy_impact
#' @docType package
NULL

#' @keywords internal
safe_scalar_pia <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize PIA System
#' @return List with success status
#' @export
init_pia_system <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS pia_assessments (
        assessment_id INTEGER PRIMARY KEY AUTOINCREMENT,
        assessment_code TEXT UNIQUE NOT NULL,
        assessment_title TEXT NOT NULL,
        study_id INTEGER,
        processing_description TEXT NOT NULL,
        data_controller TEXT NOT NULL,
        dpo_name TEXT,
        dpo_email TEXT,
        status TEXT DEFAULT 'DRAFT',
        overall_risk_level TEXT,
        requires_dpia INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        submitted_at TEXT,
        approved_at TEXT,
        approved_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS pia_processing_purposes (
        purpose_id INTEGER PRIMARY KEY AUTOINCREMENT,
        assessment_id INTEGER NOT NULL,
        purpose_category TEXT NOT NULL,
        purpose_description TEXT NOT NULL,
        legal_basis TEXT NOT NULL,
        legal_basis_details TEXT,
        FOREIGN KEY (assessment_id) REFERENCES pia_assessments(assessment_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS pia_data_categories (
        category_id INTEGER PRIMARY KEY AUTOINCREMENT,
        assessment_id INTEGER NOT NULL,
        data_category TEXT NOT NULL,
        is_special_category INTEGER DEFAULT 0,
        data_subjects TEXT,
        retention_period TEXT,
        source_of_data TEXT,
        FOREIGN KEY (assessment_id) REFERENCES pia_assessments(assessment_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS pia_risk_assessment (
        risk_id INTEGER PRIMARY KEY AUTOINCREMENT,
        assessment_id INTEGER NOT NULL,
        risk_category TEXT NOT NULL,
        risk_description TEXT NOT NULL,
        likelihood TEXT NOT NULL,
        impact TEXT NOT NULL,
        risk_level TEXT NOT NULL,
        mitigation_measure TEXT,
        residual_risk TEXT,
        assessed_by TEXT NOT NULL,
        assessed_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (assessment_id) REFERENCES pia_assessments(assessment_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS pia_consultations (
        consultation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        assessment_id INTEGER NOT NULL,
        consulted_party TEXT NOT NULL,
        consultation_type TEXT NOT NULL,
        consultation_date TEXT,
        outcome TEXT,
        recommendations TEXT,
        FOREIGN KEY (assessment_id) REFERENCES pia_assessments(assessment_id)
      )
    ")

    list(success = TRUE, message = "PIA system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get PIA Statuses
#' @return Named character vector
#' @export
get_pia_statuses <- function() {
  c(
    DRAFT = "Assessment in progress",
    SUBMITTED = "Submitted for review",
    UNDER_REVIEW = "Under DPO review",
    APPROVED = "Assessment approved",
    REQUIRES_CHANGES = "Changes required",
    REJECTED = "Assessment rejected"
  )
}

#' Get Legal Bases (GDPR Article 6)
#' @return Named character vector
#' @export
get_gdpr_legal_bases <- function() {
  c(
    CONSENT = "Consent of the data subject (Art. 6.1.a)",
    CONTRACT = "Performance of a contract (Art. 6.1.b)",
    LEGAL_OBLIGATION = "Compliance with legal obligation (Art. 6.1.c)",
    VITAL_INTERESTS = "Protection of vital interests (Art. 6.1.d)",
    PUBLIC_INTEREST = "Public interest or official authority (Art. 6.1.e)",
    LEGITIMATE_INTEREST = "Legitimate interests (Art. 6.1.f)"
  )
}

#' Get Risk Categories
#' @return Named character vector
#' @export
get_pia_risk_categories <- function() {
  c(
    UNAUTHORIZED_ACCESS = "Unauthorized access to personal data",
    DATA_BREACH = "Data breach or loss",
    EXCESSIVE_COLLECTION = "Excessive data collection",
    INACCURATE_DATA = "Inaccurate or outdated data",
    LACK_TRANSPARENCY = "Lack of transparency",
    INADEQUATE_CONSENT = "Inadequate consent mechanisms",
    UNLAWFUL_TRANSFER = "Unlawful international transfer",
    PROFILING = "Automated decision-making/profiling",
    RETENTION = "Excessive data retention"
  )
}

#' Get Risk Levels
#' @return Named character vector
#' @export
get_pia_risk_levels <- function() {
  c(
    CRITICAL = "Immediate action required",
    HIGH = "Significant mitigation needed",
    MEDIUM = "Mitigation recommended",
    LOW = "Acceptable with monitoring"
  )
}

#' Create PIA Assessment
#' @param assessment_title Title
#' @param processing_description Description of processing
#' @param data_controller Data controller name
#' @param created_by User creating
#' @param study_id Optional study ID
#' @param dpo_name DPO name
#' @param dpo_email DPO email
#' @return List with success status
#' @export
create_pia_assessment <- function(assessment_title, processing_description,
                                   data_controller, created_by,
                                   study_id = NULL, dpo_name = NULL,
                                   dpo_email = NULL) {
  tryCatch({
    if (missing(assessment_title) || assessment_title == "") {
      return(list(success = FALSE, error = "assessment_title is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    assessment_code <- paste0("PIA-", format(Sys.time(), "%Y%m%d-%H%M%S"))

    DBI::dbExecute(con, "
      INSERT INTO pia_assessments (
        assessment_code, assessment_title, study_id, processing_description,
        data_controller, dpo_name, dpo_email, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      assessment_code, assessment_title,
      if (is.null(study_id)) NA_integer_ else as.integer(study_id),
      processing_description, data_controller,
      safe_scalar_pia(dpo_name), safe_scalar_pia(dpo_email), created_by
    ))

    assessment_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, assessment_id = assessment_id,
         assessment_code = assessment_code)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Processing Purpose
#' @param assessment_id Assessment ID
#' @param purpose_category Category
#' @param purpose_description Description
#' @param legal_basis Legal basis
#' @param legal_basis_details Details
#' @return List with success status
#' @export
add_processing_purpose <- function(assessment_id, purpose_category,
                                    purpose_description, legal_basis,
                                    legal_basis_details = NULL) {
  tryCatch({
    valid_bases <- names(get_gdpr_legal_bases())
    if (!legal_basis %in% valid_bases) {
      return(list(success = FALSE,
                  error = paste("Invalid legal_basis:", legal_basis)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO pia_processing_purposes (
        assessment_id, purpose_category, purpose_description,
        legal_basis, legal_basis_details
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(
      assessment_id, purpose_category, purpose_description, legal_basis,
      safe_scalar_pia(legal_basis_details)
    ))

    list(success = TRUE, message = "Processing purpose added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Data Category
#' @param assessment_id Assessment ID
#' @param data_category Category
#' @param is_special_category Whether special category
#' @param data_subjects Description of data subjects
#' @param retention_period Retention period
#' @param source_of_data Source
#' @return List with success status
#' @export
add_data_category <- function(assessment_id, data_category,
                               is_special_category = FALSE,
                               data_subjects = NULL, retention_period = NULL,
                               source_of_data = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO pia_data_categories (
        assessment_id, data_category, is_special_category,
        data_subjects, retention_period, source_of_data
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      assessment_id, data_category, as.integer(is_special_category),
      safe_scalar_pia(data_subjects), safe_scalar_pia(retention_period),
      safe_scalar_pia(source_of_data)
    ))

    DBI::dbExecute(con, "
      UPDATE pia_assessments SET requires_dpia = 1
      WHERE assessment_id = ? AND ? = 1
    ", params = list(assessment_id, as.integer(is_special_category)))

    list(success = TRUE, message = "Data category added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Risk Assessment
#' @param assessment_id Assessment ID
#' @param risk_category Category
#' @param risk_description Description
#' @param likelihood Likelihood
#' @param impact Impact level
#' @param assessed_by User assessing
#' @param mitigation_measure Mitigation measure
#' @param residual_risk Residual risk
#' @return List with success status
#' @export
add_risk_assessment <- function(assessment_id, risk_category, risk_description,
                                 likelihood, impact, assessed_by,
                                 mitigation_measure = NULL,
                                 residual_risk = NULL) {
  tryCatch({
    valid_levels <- c("CRITICAL", "HIGH", "MEDIUM", "LOW")
    if (!likelihood %in% valid_levels || !impact %in% valid_levels) {
      return(list(success = FALSE,
                  error = "likelihood and impact must be valid levels"))
    }

    risk_matrix <- list(
      CRITICAL = list(CRITICAL = "CRITICAL", HIGH = "CRITICAL",
                      MEDIUM = "HIGH", LOW = "MEDIUM"),
      HIGH = list(CRITICAL = "CRITICAL", HIGH = "HIGH",
                  MEDIUM = "MEDIUM", LOW = "LOW"),
      MEDIUM = list(CRITICAL = "HIGH", HIGH = "MEDIUM",
                    MEDIUM = "MEDIUM", LOW = "LOW"),
      LOW = list(CRITICAL = "MEDIUM", HIGH = "LOW",
                 MEDIUM = "LOW", LOW = "LOW")
    )
    risk_level <- risk_matrix[[likelihood]][[impact]]

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO pia_risk_assessment (
        assessment_id, risk_category, risk_description, likelihood, impact,
        risk_level, mitigation_measure, residual_risk, assessed_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      assessment_id, risk_category, risk_description, likelihood, impact,
      risk_level, safe_scalar_pia(mitigation_measure),
      safe_scalar_pia(residual_risk), assessed_by
    ))

    list(success = TRUE, risk_level = risk_level, message = "Risk added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Risk Assessments
#' @param assessment_id Assessment ID
#' @return List with risks
#' @export
get_risk_assessments <- function(assessment_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    risks <- DBI::dbGetQuery(con, "
      SELECT * FROM pia_risk_assessment
      WHERE assessment_id = ?
      ORDER BY
        CASE risk_level
          WHEN 'CRITICAL' THEN 1
          WHEN 'HIGH' THEN 2
          WHEN 'MEDIUM' THEN 3
          WHEN 'LOW' THEN 4
        END
    ", params = list(assessment_id))

    list(success = TRUE, risks = risks, count = nrow(risks))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Consultation
#' @param assessment_id Assessment ID
#' @param consulted_party Party consulted
#' @param consultation_type Type
#' @param consultation_date Date
#' @param outcome Outcome
#' @param recommendations Recommendations
#' @return List with success status
#' @export
add_consultation <- function(assessment_id, consulted_party, consultation_type,
                              consultation_date = NULL, outcome = NULL,
                              recommendations = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO pia_consultations (
        assessment_id, consulted_party, consultation_type,
        consultation_date, outcome, recommendations
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      assessment_id, consulted_party, consultation_type,
      safe_scalar_pia(consultation_date),
      safe_scalar_pia(outcome), safe_scalar_pia(recommendations)
    ))

    list(success = TRUE, message = "Consultation recorded")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Calculate Overall Risk Level
#' @param assessment_id Assessment ID
#' @return List with overall risk
#' @export
calculate_overall_risk <- function(assessment_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    risks <- DBI::dbGetQuery(con, "
      SELECT risk_level, COUNT(*) as count
      FROM pia_risk_assessment
      WHERE assessment_id = ?
      GROUP BY risk_level
    ", params = list(assessment_id))

    if (nrow(risks) == 0) {
      return(list(success = TRUE, overall_risk = "NOT_ASSESSED"))
    }

    overall <- if ("CRITICAL" %in% risks$risk_level) {
      "CRITICAL"
    } else if ("HIGH" %in% risks$risk_level) {
      "HIGH"
    } else if ("MEDIUM" %in% risks$risk_level) {
      "MEDIUM"
    } else {
      "LOW"
    }

    DBI::dbExecute(con, "
      UPDATE pia_assessments SET overall_risk_level = ?
      WHERE assessment_id = ?
    ", params = list(overall, assessment_id))

    list(success = TRUE, overall_risk = overall, risk_breakdown = risks)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Submit PIA for Review
#' @param assessment_id Assessment ID
#' @return List with success status
#' @export
submit_pia_for_review <- function(assessment_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    calculate_overall_risk(assessment_id)

    DBI::dbExecute(con, "
      UPDATE pia_assessments
      SET status = 'SUBMITTED', submitted_at = ?
      WHERE assessment_id = ?
    ", params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), assessment_id))

    list(success = TRUE, message = "PIA submitted for review")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Approve PIA
#' @param assessment_id Assessment ID
#' @param approved_by Approver name
#' @return List with success status
#' @export
approve_pia <- function(assessment_id, approved_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE pia_assessments
      SET status = 'APPROVED', approved_at = ?, approved_by = ?
      WHERE assessment_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      approved_by, assessment_id
    ))

    list(success = TRUE, message = "PIA approved")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get PIA Assessment
#' @param assessment_id Assessment ID
#' @return List with assessment details
#' @export
get_pia_assessment <- function(assessment_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    assessment <- DBI::dbGetQuery(con, "
      SELECT * FROM pia_assessments WHERE assessment_id = ?
    ", params = list(assessment_id))

    if (nrow(assessment) == 0) {
      return(list(success = FALSE, error = "Assessment not found"))
    }

    purposes <- DBI::dbGetQuery(con, "
      SELECT * FROM pia_processing_purposes WHERE assessment_id = ?
    ", params = list(assessment_id))

    data_cats <- DBI::dbGetQuery(con, "
      SELECT * FROM pia_data_categories WHERE assessment_id = ?
    ", params = list(assessment_id))

    risks <- DBI::dbGetQuery(con, "
      SELECT * FROM pia_risk_assessment WHERE assessment_id = ?
    ", params = list(assessment_id))

    consultations <- DBI::dbGetQuery(con, "
      SELECT * FROM pia_consultations WHERE assessment_id = ?
    ", params = list(assessment_id))

    list(
      success = TRUE,
      assessment = as.list(assessment),
      purposes = purposes,
      data_categories = data_cats,
      risks = risks,
      consultations = consultations
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get PIA Assessments List
#' @param status Optional status filter
#' @return List with assessments
#' @export
get_pia_assessments <- function(status = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(status)) {
      assessments <- DBI::dbGetQuery(con, "
        SELECT * FROM pia_assessments ORDER BY created_at DESC
      ")
    } else {
      assessments <- DBI::dbGetQuery(con, "
        SELECT * FROM pia_assessments WHERE status = ?
        ORDER BY created_at DESC
      ", params = list(status))
    }

    list(success = TRUE, assessments = assessments, count = nrow(assessments))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get PIA Statistics
#' @return List with statistics
#' @export
get_pia_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_assessments,
        SUM(CASE WHEN status = 'APPROVED' THEN 1 ELSE 0 END) as approved,
        SUM(CASE WHEN status = 'DRAFT' THEN 1 ELSE 0 END) as drafts,
        SUM(requires_dpia) as requiring_dpia
      FROM pia_assessments
    ")

    by_risk <- DBI::dbGetQuery(con, "
      SELECT overall_risk_level, COUNT(*) as count
      FROM pia_assessments
      WHERE overall_risk_level IS NOT NULL
      GROUP BY overall_risk_level
    ")

    list(success = TRUE, statistics = as.list(stats), by_risk = by_risk)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
