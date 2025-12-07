# GDPR Database Extensions for ZZedc
# Add GDPR compliance tables to existing database

library(RSQLite)
library(DBI)

#' Add GDPR compliance tables to existing database
#'
#' @param db_connection Database connection object
add_gdpr_tables <- function(db_connection) {

  cat("🔒 Adding GDPR Compliance Tables...\n")
  cat("===================================\n")

  # 1. Consent Management Table
  cat("📝 Creating consent management table...\n")
  dbExecute(db_connection, "
    CREATE TABLE IF NOT EXISTS consent_log (
      consent_id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT,
      subject_id TEXT,
      consent_type TEXT NOT NULL CHECK(consent_type IN (
        'privacy_notice', 'data_processing', 'special_category',
        'marketing', 'research_participation', 'data_sharing'
      )),
      consent_version TEXT DEFAULT '1.0',
      status TEXT NOT NULL CHECK(status IN ('given', 'withdrawn', 'expired')),
      legal_basis TEXT CHECK(legal_basis IN (
        'consent', 'contract', 'legal_obligation', 'vital_interests',
        'public_task', 'legitimate_interests', 'research_exemption'
      )),
      purpose_category TEXT NOT NULL,
      consent_method TEXT CHECK(consent_method IN ('web_form', 'paper', 'verbal', 'implied')),
      consent_text TEXT,
      withdrawal_reason TEXT,
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      expiry_date DATE,
      ip_address TEXT,
      user_agent TEXT,
      evidence_location TEXT,
      created_by TEXT,
      FOREIGN KEY (user_id) REFERENCES edc_users(user_id),
      FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
    )
  ")

  # Create indexes for consent log
  dbExecute(db_connection, "CREATE INDEX IF NOT EXISTS idx_consent_subject_id ON consent_log(subject_id)")
  dbExecute(db_connection, "CREATE INDEX IF NOT EXISTS idx_consent_type_status ON consent_log(consent_type, status)")
  dbExecute(db_connection, "CREATE INDEX IF NOT EXISTS idx_consent_timestamp ON consent_log(timestamp)")

  # 2. Data Subject Requests Table (Articles 15-22 GDPR)
  cat("📋 Creating data subject requests table...\n")
  dbExecute(db_connection, "
    CREATE TABLE IF NOT EXISTS data_subject_requests (
      request_id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT,
      subject_id TEXT,
      request_type TEXT NOT NULL CHECK(request_type IN (
        'access', 'rectification', 'erasure', 'restrict_processing',
        'portability', 'object', 'consent_withdrawal', 'complaint'
      )),
      request_description TEXT,
      contact_email TEXT NOT NULL,
      contact_phone TEXT,
      identity_verified BOOLEAN DEFAULT 0,
      verification_method TEXT,
      status TEXT DEFAULT 'pending' CHECK(status IN (
        'pending', 'in_progress', 'completed', 'rejected', 'partially_fulfilled'
      )),
      priority TEXT DEFAULT 'normal' CHECK(priority IN ('low', 'normal', 'high', 'urgent')),
      legal_assessment TEXT,
      response_due_date DATE,
      response_sent_date DATE,
      response_method TEXT CHECK(response_method IN ('email', 'post', 'in_person', 'secure_portal')),
      fulfillment_notes TEXT,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      assigned_to TEXT,
      completed_by TEXT,
      FOREIGN KEY (user_id) REFERENCES edc_users(user_id),
      FOREIGN KEY (subject_id) REFERENCES subjects(subject_id),
      FOREIGN KEY (assigned_to) REFERENCES edc_users(user_id)
    )
  ")

  # 3. Data Processing Activities (Article 30 GDPR)
  cat("📊 Creating processing activities register...\n")
  dbExecute(db_connection, "
    CREATE TABLE IF NOT EXISTS processing_activities (
      activity_id INTEGER PRIMARY KEY AUTOINCREMENT,
      activity_name TEXT NOT NULL,
      description TEXT NOT NULL,
      controller_name TEXT NOT NULL,
      controller_contact TEXT,
      dpo_contact TEXT,
      legal_basis_regular TEXT CHECK(legal_basis_regular IN (
        'consent', 'contract', 'legal_obligation', 'vital_interests',
        'public_task', 'legitimate_interests'
      )),
      legal_basis_special TEXT CHECK(legal_basis_special IN (
        'explicit_consent', 'employment_law', 'vital_interests', 'nonprofit_activities',
        'made_public', 'legal_claims', 'substantial_public_interest',
        'health_care', 'public_health', 'research_statistics'
      )),
      data_categories TEXT NOT NULL,
      special_categories BOOLEAN DEFAULT 0,
      data_subjects TEXT NOT NULL,
      recipients TEXT,
      international_transfers BOOLEAN DEFAULT 0,
      transfer_safeguards TEXT,
      retention_period TEXT NOT NULL,
      security_measures TEXT NOT NULL,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      last_reviewed DATE,
      status TEXT DEFAULT 'active' CHECK(status IN ('active', 'inactive', 'archived'))
    )
  ")

  # 4. Breach Incidents (Articles 33-34 GDPR)
  cat("🚨 Creating breach incident tracking table...\n")
  dbExecute(db_connection, "
    CREATE TABLE IF NOT EXISTS breach_incidents (
      incident_id INTEGER PRIMARY KEY AUTOINCREMENT,
      incident_ref TEXT UNIQUE NOT NULL,
      severity_level TEXT CHECK(severity_level IN ('low', 'medium', 'high', 'critical')),
      breach_type TEXT CHECK(breach_type IN (
        'confidentiality', 'integrity', 'availability', 'combined'
      )),
      description TEXT NOT NULL,
      affected_data_types TEXT NOT NULL,
      affected_individuals_count INTEGER DEFAULT 0,
      likely_consequences TEXT,
      risk_assessment TEXT CHECK(risk_assessment IN ('low', 'medium', 'high')),
      detected_date TIMESTAMP NOT NULL,
      reported_internally_date TIMESTAMP,
      dpa_notification_required BOOLEAN DEFAULT 0,
      dpa_notification_date TIMESTAMP,
      dpa_reference TEXT,
      individual_notification_required BOOLEAN DEFAULT 0,
      individual_notification_date TIMESTAMP,
      containment_measures TEXT,
      remedial_actions TEXT,
      status TEXT DEFAULT 'detected' CHECK(status IN (
        'detected', 'investigating', 'contained', 'resolved', 'closed'
      )),
      lessons_learned TEXT,
      created_by TEXT,
      assigned_to TEXT,
      FOREIGN KEY (created_by) REFERENCES edc_users(user_id),
      FOREIGN KEY (assigned_to) REFERENCES edc_users(user_id)
    )
  ")

  # 5. Data Retention Schedule
  cat("🗄️  Creating data retention schedule table...\n")
  dbExecute(db_connection, "
    CREATE TABLE IF NOT EXISTS data_retention_schedule (
      retention_id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      data_category TEXT NOT NULL,
      legal_basis TEXT NOT NULL,
      retention_period_months INTEGER NOT NULL,
      retention_trigger TEXT CHECK(retention_trigger IN (
        'creation_date', 'last_activity', 'study_completion', 'consent_withdrawal',
        'regulatory_deadline', 'business_end'
      )),
      deletion_method TEXT CHECK(deletion_method IN (
        'secure_deletion', 'anonymization', 'pseudonymization', 'archival'
      )),
      exceptions TEXT,
      review_frequency_months INTEGER DEFAULT 12,
      last_review_date DATE,
      next_review_date DATE,
      status TEXT DEFAULT 'active' CHECK(status IN ('active', 'suspended', 'archived')),
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ")

  # 6. Privacy Impact Assessments (Article 35 GDPR)
  cat("🔍 Creating privacy impact assessment table...\n")
  dbExecute(db_connection, "
    CREATE TABLE IF NOT EXISTS privacy_impact_assessments (
      pia_id INTEGER PRIMARY KEY AUTOINCREMENT,
      assessment_name TEXT NOT NULL,
      description TEXT NOT NULL,
      processing_activity_id INTEGER,
      high_risk_factors TEXT NOT NULL,
      necessity_assessment TEXT NOT NULL,
      proportionality_assessment TEXT NOT NULL,
      data_subject_rights_impact TEXT NOT NULL,
      security_measures TEXT NOT NULL,
      risk_level TEXT CHECK(risk_level IN ('low', 'medium', 'high', 'critical')),
      mitigation_measures TEXT NOT NULL,
      residual_risk TEXT,
      dpo_consultation_date DATE,
      dpo_opinion TEXT,
      authority_consultation_required BOOLEAN DEFAULT 0,
      authority_consultation_date DATE,
      status TEXT DEFAULT 'draft' CHECK(status IN (
        'draft', 'review', 'approved', 'implemented', 'monitoring'
      )),
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      reviewed_date DATE,
      approved_by TEXT,
      FOREIGN KEY (processing_activity_id) REFERENCES processing_activities(activity_id),
      FOREIGN KEY (approved_by) REFERENCES edc_users(user_id)
    )
  ")

  # 7. Data Minimization Tracking
  cat("📉 Creating data minimization tracking table...\n")
  dbExecute(db_connection, "
    CREATE TABLE IF NOT EXISTS data_minimization_log (
      log_id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      field_name TEXT NOT NULL,
      action_type TEXT CHECK(action_type IN (
        'field_removed', 'data_anonymized', 'retention_reduced',
        'purpose_limited', 'access_restricted'
      )),
      justification TEXT NOT NULL,
      data_subjects_affected INTEGER DEFAULT 0,
      implemented_date DATE,
      verification_date DATE,
      responsible_person TEXT,
      approval_required BOOLEAN DEFAULT 0,
      approved_by TEXT,
      approval_date DATE,
      FOREIGN KEY (responsible_person) REFERENCES edc_users(user_id),
      FOREIGN KEY (approved_by) REFERENCES edc_users(user_id)
    )
  ")

  # Insert default processing activities
  cat("📝 Inserting default processing activities...\n")
  default_activities <- data.frame(
    activity_name = c(
      "Clinical Trial Data Collection",
      "User Account Management",
      "System Security Monitoring",
      "Regulatory Reporting"
    ),
    description = c(
      "Collection and processing of health data for clinical research purposes",
      "Management of user accounts and authentication for EDC system access",
      "Monitoring system access and security events for protection",
      "Preparation of reports for regulatory authorities"
    ),
    controller_name = rep("Clinical Research Organization", 4),
    controller_contact = rep("dpo@yourorg.org", 4),
    legal_basis_regular = c("legitimate_interests", "contract", "legitimate_interests", "legal_obligation"),
    legal_basis_special = c("research_statistics", NA, NA, "research_statistics"),
    data_categories = c(
      "Health data, demographics, assessment scores",
      "Contact information, authentication data",
      "IP addresses, access logs, system events",
      "Aggregated clinical trial results"
    ),
    special_categories = c(1, 0, 0, 1),
    data_subjects = c("Clinical trial participants", "EDC system users", "All users", "Trial participants"),
    retention_period = c("25 years post-study", "1 year post-employment", "7 years", "Permanent (public health)"),
    security_measures = rep("Encryption, access control, audit logging", 4),
    status = rep("active", 4)
  )

  dbWriteTable(db_connection, "processing_activities", default_activities, append = TRUE, row.names = FALSE)

  # Insert default retention schedules
  cat("🗓️  Inserting default retention schedules...\n")
  retention_schedules <- data.frame(
    table_name = c("demographics", "cognitive_assessments", "audit_trail", "consent_log", "edc_users"),
    data_category = c("Health data", "Health data", "System logs", "Consent records", "User accounts"),
    legal_basis = c("research_exemption", "research_exemption", "legitimate_interests", "consent", "contract"),
    retention_period_months = c(300, 300, 84, 300, 12),
    retention_trigger = c("study_completion", "study_completion", "creation_date", "consent_withdrawal", "last_activity"),
    deletion_method = c("secure_deletion", "secure_deletion", "secure_deletion", "secure_deletion", "anonymization"),
    status = rep("active", 5)
  )

  dbWriteTable(db_connection, "data_retention_schedule", retention_schedules, append = TRUE, row.names = FALSE)

  cat("✅ GDPR compliance tables created successfully\n")
  cat("✅ Default processing activities added\n")
  cat("✅ Default retention schedules configured\n")

  invisible(TRUE)
}

#' Generate GDPR compliance report
#'
#' @param db_connection Database connection
#' @return List with compliance metrics
generate_gdpr_compliance_report <- function(db_connection) {

  report <- list()

  # Consent statistics
  consent_stats <- dbGetQuery(db_connection, "
    SELECT
      consent_type,
      status,
      COUNT(*) as count
    FROM consent_log
    GROUP BY consent_type, status
  ")
  report$consent_overview <- consent_stats

  # Data subject requests
  request_stats <- dbGetQuery(db_connection, "
    SELECT
      request_type,
      status,
      COUNT(*) as count,
      AVG(JULIANDAY(response_sent_date) - JULIANDAY(created_date)) as avg_response_days
    FROM data_subject_requests
    GROUP BY request_type, status
  ")
  report$data_subject_requests <- request_stats

  # Breach incidents
  breach_stats <- dbGetQuery(db_connection, "
    SELECT
      severity_level,
      status,
      COUNT(*) as count
    FROM breach_incidents
    GROUP BY severity_level, status
  ")
  report$breach_incidents <- breach_stats

  # Processing activities compliance
  processing_stats <- dbGetQuery(db_connection, "
    SELECT
      COUNT(*) as total_activities,
      SUM(CASE WHEN last_reviewed >= date('now', '-12 months') THEN 1 ELSE 0 END) as reviewed_last_year,
      SUM(special_categories) as special_category_activities
    FROM processing_activities
    WHERE status = 'active'
  ")
  report$processing_activities <- processing_stats

  report$generated_date <- Sys.time()
  report$compliance_score <- calculate_compliance_score(report)

  return(report)
}

#' Calculate compliance score
#'
#' @param report_data Report data from generate_gdpr_compliance_report
#' @return Numeric compliance score (0-100)
calculate_compliance_score <- function(report_data) {

  score <- 100

  # Deduct points for issues
  if (nrow(report_data$breach_incidents) > 0) {
    high_severity_breaches <- sum(report_data$breach_incidents$count[
      report_data$breach_incidents$severity_level %in% c("high", "critical")
    ])
    score <- score - (high_severity_breaches * 10)
  }

  # Deduct points for overdue requests
  if (nrow(report_data$data_subject_requests) > 0) {
    overdue_requests <- sum(report_data$data_subject_requests$count[
      report_data$data_subject_requests$status == "pending" &
      !is.na(report_data$data_subject_requests$avg_response_days) &
      report_data$data_subject_requests$avg_response_days > 30
    ], na.rm = TRUE)
    score <- score - (overdue_requests * 5)
  }

  # Cap at 0
  max(0, score)
}

# Usage example:
# con <- dbConnect(SQLite(), "data/memory001_study.db")
# add_gdpr_tables(con)
# compliance_report <- generate_gdpr_compliance_report(con)
# dbDisconnect(con)