#' Adverse Event (AE/SAE) Management System
#'
#' FDA-compliant adverse event tracking including severity grading,
#' causality assessment, SAE expedited reporting, and outcome tracking.

# =============================================================================
# Helper Functions
# =============================================================================

#' Safe Scalar Conversion for AE
#'
#' @param x Value to convert
#' @param default Default value if NULL
#' @return Character scalar
#' @keywords internal
safe_scalar_ae <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

# =============================================================================
# Database Schema
# =============================================================================

#' Initialize Adverse Events System
#'
#' Creates database tables for adverse event management.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with initialization results
#'
#' @export
init_adverse_events <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS adverse_events (
        ae_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ae_number TEXT NOT NULL UNIQUE,
        study_id TEXT NOT NULL,
        site_id TEXT,
        subject_id TEXT NOT NULL,
        onset_date DATE NOT NULL,
        onset_time TEXT,
        resolution_date DATE,
        resolution_time TEXT,
        ae_term TEXT NOT NULL,
        ae_description TEXT NOT NULL,
        meddra_pt_code TEXT,
        meddra_pt_term TEXT,
        meddra_soc_code TEXT,
        meddra_soc_term TEXT,
        severity TEXT NOT NULL CHECK(severity IN
          ('MILD', 'MODERATE', 'SEVERE')),
        is_serious BOOLEAN NOT NULL DEFAULT 0,
        sae_criteria TEXT,
        causality TEXT NOT NULL CHECK(causality IN
          ('UNRELATED', 'UNLIKELY', 'POSSIBLE', 'PROBABLE', 'DEFINITE')),
        causality_rationale TEXT,
        expectedness TEXT CHECK(expectedness IN
          ('EXPECTED', 'UNEXPECTED', 'NOT_APPLICABLE')),
        outcome TEXT NOT NULL CHECK(outcome IN
          ('RECOVERED', 'RECOVERING', 'NOT_RECOVERED', 'RECOVERED_WITH_SEQUELAE',
           'FATAL', 'UNKNOWN', 'ONGOING')),
        action_taken TEXT CHECK(action_taken IN
          ('NONE', 'DOSE_REDUCED', 'DRUG_INTERRUPTED', 'DRUG_WITHDRAWN',
           'CONCOMITANT_MED_GIVEN', 'NON_DRUG_THERAPY', 'OTHER')),
        action_taken_other TEXT,
        treatment_given BOOLEAN DEFAULT 0,
        treatment_description TEXT,
        sequelae_description TEXT,
        reported_by TEXT NOT NULL,
        reported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_by TEXT,
        updated_at TIMESTAMP,
        status TEXT NOT NULL DEFAULT 'OPEN' CHECK(status IN
          ('OPEN', 'CLOSED', 'FOLLOW_UP_REQUIRED')),
        ae_hash TEXT NOT NULL,
        previous_hash TEXT,
        metadata TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS sae_details (
        sae_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ae_id INTEGER NOT NULL UNIQUE REFERENCES adverse_events(ae_id),
        sae_number TEXT NOT NULL UNIQUE,
        death BOOLEAN DEFAULT 0,
        death_date DATE,
        life_threatening BOOLEAN DEFAULT 0,
        hospitalization BOOLEAN DEFAULT 0,
        hospitalization_admission_date DATE,
        hospitalization_discharge_date DATE,
        disability BOOLEAN DEFAULT 0,
        congenital_anomaly BOOLEAN DEFAULT 0,
        other_medically_important BOOLEAN DEFAULT 0,
        other_medically_important_desc TEXT,
        initial_report_date DATE NOT NULL,
        awareness_date DATE NOT NULL,
        report_type TEXT NOT NULL CHECK(report_type IN
          ('INITIAL', 'FOLLOW_UP', 'FINAL')),
        expedited_report_required BOOLEAN DEFAULT 1,
        expedited_report_deadline DATE,
        expedited_report_sent BOOLEAN DEFAULT 0,
        expedited_report_sent_date DATE,
        irb_notified BOOLEAN DEFAULT 0,
        irb_notification_date DATE,
        sponsor_notified BOOLEAN DEFAULT 0,
        sponsor_notification_date DATE,
        regulatory_notified BOOLEAN DEFAULT 0,
        regulatory_notification_date DATE,
        narrative TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS ae_followups (
        followup_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ae_id INTEGER NOT NULL REFERENCES adverse_events(ae_id),
        followup_date DATE NOT NULL,
        followup_type TEXT NOT NULL CHECK(followup_type IN
          ('STATUS_UPDATE', 'ADDITIONAL_INFO', 'RESOLUTION', 'CAUSALITY_UPDATE',
           'SEVERITY_CHANGE', 'OUTCOME_UPDATE', 'CORRECTION')),
        previous_value TEXT,
        new_value TEXT,
        notes TEXT NOT NULL,
        recorded_by TEXT NOT NULL,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        followup_hash TEXT NOT NULL,
        previous_followup_hash TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS ae_concomitant_meds (
        med_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ae_id INTEGER NOT NULL REFERENCES adverse_events(ae_id),
        medication_name TEXT NOT NULL,
        indication TEXT,
        dose TEXT,
        route TEXT,
        frequency TEXT,
        start_date DATE,
        end_date DATE,
        ongoing BOOLEAN DEFAULT 0,
        recorded_by TEXT NOT NULL,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS ae_medical_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ae_id INTEGER NOT NULL REFERENCES adverse_events(ae_id),
        condition TEXT NOT NULL,
        onset_date DATE,
        resolution_date DATE,
        ongoing BOOLEAN DEFAULT 0,
        relevant_to_ae BOOLEAN DEFAULT 1,
        notes TEXT,
        recorded_by TEXT NOT NULL,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_ae_subject
      ON adverse_events(subject_id)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_ae_study
      ON adverse_events(study_id)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_ae_serious
      ON adverse_events(is_serious)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_ae_status
      ON adverse_events(status)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_sae_deadline
      ON sae_details(expedited_report_deadline)
    ")

    list(
      success = TRUE,
      tables_created = 5,
      message = "Adverse events system initialized successfully"
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    )
  })
}


# =============================================================================
# Reference Data
# =============================================================================

#' Get AE Severity Grades
#'
#' Returns valid severity grades with descriptions.
#'
#' @return Named list of severity grades
#'
#' @export
get_ae_severity_grades <- function() {
  list(
    MILD = "Mild: Awareness of symptoms but easily tolerated",
    MODERATE = "Moderate: Discomfort enough to cause interference with usual activity",
    SEVERE = "Severe: Incapacitating with inability to work or do usual activity"
  )
}


#' Get SAE Criteria
#'
#' Returns SAE seriousness criteria per FDA/ICH definitions.
#'
#' @return Named list of SAE criteria
#'
#' @export
get_sae_criteria <- function() {
  list(
    DEATH = "Results in death",
    LIFE_THREATENING = "Is life-threatening",
    HOSPITALIZATION = "Requires inpatient hospitalization or prolongation of existing hospitalization",
    DISABILITY = "Results in persistent or significant disability/incapacity",
    CONGENITAL_ANOMALY = "Is a congenital anomaly/birth defect",
    OTHER_MEDICALLY_IMPORTANT = "Is a medically important event that may jeopardize the patient or require intervention"
  )
}


#' Get Causality Assessments
#'
#' Returns causality assessment categories.
#'
#' @return Named list of causality categories
#'
#' @export
get_causality_categories <- function() {
  list(
    UNRELATED = "Unrelated: No temporal or causal relationship",
    UNLIKELY = "Unlikely: Little evidence to suggest causality",
    POSSIBLE = "Possible: Some evidence for causality, but other factors may contribute",
    PROBABLE = "Probable: Good evidence for causality, unlikely to be due to other factors",
    DEFINITE = "Definite: Clear evidence for causality, confirmed by rechallenge or other means"
  )
}


#' Get AE Outcomes
#'
#' Returns valid AE outcome categories.
#'
#' @return Named list of outcomes
#'
#' @export
get_ae_outcomes <- function() {
  list(
    RECOVERED = "Recovered/Resolved",
    RECOVERING = "Recovering/Resolving",
    NOT_RECOVERED = "Not recovered/Not resolved",
    RECOVERED_WITH_SEQUELAE = "Recovered/Resolved with sequelae",
    FATAL = "Fatal",
    UNKNOWN = "Unknown",
    ONGOING = "Ongoing at study end"
  )
}


#' Get Action Taken Categories
#'
#' Returns valid action taken categories.
#'
#' @return Named list of action taken
#'
#' @export
get_action_taken_categories <- function() {
  list(
    NONE = "No action taken",
    DOSE_REDUCED = "Dose reduced",
    DRUG_INTERRUPTED = "Drug interrupted",
    DRUG_WITHDRAWN = "Drug withdrawn",
    CONCOMITANT_MED_GIVEN = "Concomitant medication given",
    NON_DRUG_THERAPY = "Non-drug therapy given",
    OTHER = "Other action taken"
  )
}


# =============================================================================
# Adverse Event Recording
# =============================================================================

#' Generate AE Number
#'
#' Generates a unique adverse event number.
#'
#' @param study_id Character: Study ID
#' @param is_serious Logical: Whether SAE
#'
#' @return Character: AE number
#'
#' @keywords internal
generate_ae_number <- function(study_id, is_serious = FALSE) {
  prefix <- if (is_serious) "SAE" else "AE"
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(LETTERS, 4, replace = TRUE), collapse = "")
  paste0(prefix, "-", study_id, "-", timestamp, "-", random)
}


#' Create Adverse Event
#'
#' Records a new adverse event with full clinical details.
#'
#' @param study_id Character: Study ID
#' @param subject_id Character: Subject ID
#' @param onset_date Date: Event onset date
#' @param ae_term Character: AE preferred term
#' @param ae_description Character: Detailed description
#' @param severity Character: MILD, MODERATE, or SEVERE
#' @param causality Character: Causality assessment
#' @param outcome Character: Current outcome
#' @param reported_by Character: Reporter user ID
#' @param site_id Character: Site ID (optional)
#' @param onset_time Character: Onset time (optional)
#' @param meddra_pt_code Character: MedDRA PT code (optional)
#' @param meddra_pt_term Character: MedDRA PT term (optional)
#' @param expectedness Character: EXPECTED/UNEXPECTED (optional)
#' @param action_taken Character: Action taken (optional)
#' @param treatment_given Logical: Treatment given (optional)
#' @param treatment_description Character: Treatment description (optional)
#' @param causality_rationale Character: Causality rationale (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
create_adverse_event <- function(study_id,
                                  subject_id,
                                  onset_date,
                                  ae_term,
                                  ae_description,
                                  severity,
                                  causality,
                                  outcome,
                                  reported_by,
                                  site_id = NULL,
                                  onset_time = NULL,
                                  meddra_pt_code = NULL,
                                  meddra_pt_term = NULL,
                                  expectedness = NULL,
                                  action_taken = "NONE",
                                  treatment_given = FALSE,
                                  treatment_description = NULL,
                                  causality_rationale = NULL,
                                  db_path = NULL) {

  if (!severity %in% c("MILD", "MODERATE", "SEVERE")) {
    return(list(
      success = FALSE,
      error = "Severity must be MILD, MODERATE, or SEVERE"
    ))
  }

  if (!causality %in% names(get_causality_categories())) {
    return(list(
      success = FALSE,
      error = paste("Invalid causality. Must be one of:",
                    paste(names(get_causality_categories()), collapse = ", "))
    ))
  }

  if (!outcome %in% names(get_ae_outcomes())) {
    return(list(
      success = FALSE,
      error = paste("Invalid outcome. Must be one of:",
                    paste(names(get_ae_outcomes()), collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    ae_number <- generate_ae_number(study_id, is_serious = FALSE)

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT ae_hash FROM adverse_events
      ORDER BY ae_id DESC LIMIT 1
    ")
    previous_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$ae_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      ae_number, study_id, subject_id, onset_date, ae_term,
      severity, causality, outcome, reported_by, timestamp, previous_hash,
      sep = "|"
    )
    ae_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO adverse_events (
        ae_number, study_id, site_id, subject_id, onset_date, onset_time,
        ae_term, ae_description, meddra_pt_code, meddra_pt_term,
        severity, is_serious, causality, causality_rationale,
        expectedness, outcome, action_taken, treatment_given,
        treatment_description, reported_by, ae_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      ae_number,
      safe_scalar_ae(study_id),
      safe_scalar_ae(site_id),
      safe_scalar_ae(subject_id),
      safe_scalar_ae(as.character(onset_date)),
      safe_scalar_ae(onset_time),
      safe_scalar_ae(ae_term),
      safe_scalar_ae(ae_description),
      safe_scalar_ae(meddra_pt_code),
      safe_scalar_ae(meddra_pt_term),
      safe_scalar_ae(severity),
      0L,
      safe_scalar_ae(causality),
      safe_scalar_ae(causality_rationale),
      safe_scalar_ae(expectedness),
      safe_scalar_ae(outcome),
      safe_scalar_ae(action_taken),
      as.integer(treatment_given),
      safe_scalar_ae(treatment_description),
      safe_scalar_ae(reported_by),
      ae_hash,
      previous_hash
    ))

    ae_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    tryCatch({
      log_audit_event(
        event_type = "INSERT",
        user_id = reported_by,
        table_name = "adverse_events",
        record_id = as.character(ae_id),
        details = paste("AE created:", ae_term, "| Severity:", severity,
                        "| Subject:", subject_id)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      ae_id = ae_id,
      ae_number = ae_number,
      message = "Adverse event recorded successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Upgrade AE to SAE
#'
#' Upgrades an existing AE to a Serious Adverse Event.
#'
#' @param ae_id Integer: AE ID to upgrade
#' @param sae_criteria Character vector: SAE criteria met
#' @param awareness_date Date: Date sponsor became aware
#' @param narrative Character: SAE narrative
#' @param upgraded_by Character: User upgrading to SAE
#' @param death Logical: Death occurred
#' @param death_date Date: Death date (if applicable)
#' @param life_threatening Logical: Life-threatening
#' @param hospitalization Logical: Hospitalization required
#' @param hospitalization_admission_date Date: Admission date (if applicable)
#' @param hospitalization_discharge_date Date: Discharge date (if applicable)
#' @param disability Logical: Persistent disability
#' @param congenital_anomaly Logical: Congenital anomaly
#' @param other_medically_important Logical: Other medically important
#' @param other_medically_important_desc Character: Description (if other)
#' @param db_path Character: Database path (optional)
#'
#' @return List with upgrade result
#'
#' @export
upgrade_to_sae <- function(ae_id,
                            sae_criteria,
                            awareness_date,
                            narrative,
                            upgraded_by,
                            death = FALSE,
                            death_date = NULL,
                            life_threatening = FALSE,
                            hospitalization = FALSE,
                            hospitalization_admission_date = NULL,
                            hospitalization_discharge_date = NULL,
                            disability = FALSE,
                            congenital_anomaly = FALSE,
                            other_medically_important = FALSE,
                            other_medically_important_desc = NULL,
                            db_path = NULL) {

  if (length(sae_criteria) == 0) {
    return(list(
      success = FALSE,
      error = "At least one SAE criterion must be specified"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    ae <- DBI::dbGetQuery(conn, "
      SELECT * FROM adverse_events WHERE ae_id = ?
    ", list(ae_id))

    if (nrow(ae) == 0) {
      return(list(success = FALSE, error = "Adverse event not found"))
    }

    if (ae$is_serious == 1) {
      return(list(success = FALSE, error = "Event is already classified as serious"))
    }

    sae_number <- generate_ae_number(ae$study_id, is_serious = TRUE)
    initial_report_date <- Sys.Date()

    expedited_deadline <- if (death || life_threatening) {
      as.Date(awareness_date) + 7
    } else {
      as.Date(awareness_date) + 15
    }

    DBI::dbExecute(conn, "
      UPDATE adverse_events
      SET is_serious = 1,
          sae_criteria = ?,
          updated_by = ?,
          updated_at = ?
      WHERE ae_id = ?
    ", list(
      paste(sae_criteria, collapse = ";"),
      safe_scalar_ae(upgraded_by),
      as.character(Sys.time()),
      ae_id
    ))

    DBI::dbExecute(conn, "
      INSERT INTO sae_details (
        ae_id, sae_number, death, death_date, life_threatening,
        hospitalization, hospitalization_admission_date, hospitalization_discharge_date,
        disability, congenital_anomaly, other_medically_important,
        other_medically_important_desc, initial_report_date, awareness_date,
        report_type, expedited_report_required, expedited_report_deadline, narrative
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      ae_id,
      sae_number,
      as.integer(death),
      safe_scalar_ae(as.character(death_date)),
      as.integer(life_threatening),
      as.integer(hospitalization),
      safe_scalar_ae(as.character(hospitalization_admission_date)),
      safe_scalar_ae(as.character(hospitalization_discharge_date)),
      as.integer(disability),
      as.integer(congenital_anomaly),
      as.integer(other_medically_important),
      safe_scalar_ae(other_medically_important_desc),
      as.character(initial_report_date),
      safe_scalar_ae(as.character(awareness_date)),
      "INITIAL",
      1L,
      as.character(expedited_deadline),
      safe_scalar_ae(narrative)
    ))

    sae_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    add_ae_followup(
      ae_id = ae_id,
      followup_type = "STATUS_UPDATE",
      previous_value = "Non-serious AE",
      new_value = paste("Upgraded to SAE:", sae_number),
      notes = paste("Event upgraded to SAE. Criteria:", paste(sae_criteria, collapse = ", ")),
      recorded_by = upgraded_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      sae_id = sae_id,
      sae_number = sae_number,
      expedited_deadline = as.character(expedited_deadline),
      message = "AE upgraded to SAE successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Create SAE Directly
#'
#' Creates a new Serious Adverse Event directly.
#'
#' @param study_id Character: Study ID
#' @param subject_id Character: Subject ID
#' @param onset_date Date: Event onset date
#' @param ae_term Character: AE preferred term
#' @param ae_description Character: Detailed description
#' @param severity Character: MILD, MODERATE, or SEVERE
#' @param causality Character: Causality assessment
#' @param outcome Character: Current outcome
#' @param sae_criteria Character vector: SAE criteria met
#' @param awareness_date Date: Date sponsor became aware
#' @param narrative Character: SAE narrative
#' @param reported_by Character: Reporter user ID
#' @param death Logical: Death occurred
#' @param death_date Date: Death date (if applicable)
#' @param life_threatening Logical: Life-threatening
#' @param hospitalization Logical: Hospitalization required
#' @param disability Logical: Persistent disability
#' @param congenital_anomaly Logical: Congenital anomaly
#' @param other_medically_important Logical: Other medically important
#' @param site_id Character: Site ID (optional)
#' @param expectedness Character: EXPECTED/UNEXPECTED (optional)
#' @param action_taken Character: Action taken (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
create_sae <- function(study_id,
                        subject_id,
                        onset_date,
                        ae_term,
                        ae_description,
                        severity,
                        causality,
                        outcome,
                        sae_criteria,
                        awareness_date,
                        narrative,
                        reported_by,
                        death = FALSE,
                        death_date = NULL,
                        life_threatening = FALSE,
                        hospitalization = FALSE,
                        disability = FALSE,
                        congenital_anomaly = FALSE,
                        other_medically_important = FALSE,
                        site_id = NULL,
                        expectedness = "UNEXPECTED",
                        action_taken = "NONE",
                        db_path = NULL) {

  ae_result <- create_adverse_event(
    study_id = study_id,
    subject_id = subject_id,
    onset_date = onset_date,
    ae_term = ae_term,
    ae_description = ae_description,
    severity = severity,
    causality = causality,
    outcome = outcome,
    reported_by = reported_by,
    site_id = site_id,
    expectedness = expectedness,
    action_taken = action_taken,
    db_path = db_path
  )

  if (!ae_result$success) {
    return(ae_result)
  }

  sae_result <- upgrade_to_sae(
    ae_id = ae_result$ae_id,
    sae_criteria = sae_criteria,
    awareness_date = awareness_date,
    narrative = narrative,
    upgraded_by = reported_by,
    death = death,
    death_date = death_date,
    life_threatening = life_threatening,
    hospitalization = hospitalization,
    disability = disability,
    congenital_anomaly = congenital_anomaly,
    other_medically_important = other_medically_important,
    db_path = db_path
  )

  if (!sae_result$success) {
    return(sae_result)
  }

  list(
    success = TRUE,
    ae_id = ae_result$ae_id,
    ae_number = ae_result$ae_number,
    sae_id = sae_result$sae_id,
    sae_number = sae_result$sae_number,
    expedited_deadline = sae_result$expedited_deadline,
    message = "SAE created successfully"
  )
}


# =============================================================================
# AE Follow-up and Updates
# =============================================================================

#' Add AE Follow-up
#'
#' Records a follow-up entry for an adverse event.
#'
#' @param ae_id Integer: AE ID
#' @param followup_type Character: Type of follow-up
#' @param notes Character: Follow-up notes
#' @param recorded_by Character: User recording follow-up
#' @param previous_value Character: Previous value (optional)
#' @param new_value Character: New value (optional)
#' @param followup_date Date: Follow-up date (defaults to today)
#' @param db_path Character: Database path (optional)
#'
#' @return List with follow-up result
#'
#' @export
add_ae_followup <- function(ae_id,
                             followup_type,
                             notes,
                             recorded_by,
                             previous_value = NULL,
                             new_value = NULL,
                             followup_date = Sys.Date(),
                             db_path = NULL) {

  valid_types <- c("STATUS_UPDATE", "ADDITIONAL_INFO", "RESOLUTION",
                   "CAUSALITY_UPDATE", "SEVERITY_CHANGE", "OUTCOME_UPDATE",
                   "CORRECTION")

  if (!followup_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid followup type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT followup_hash FROM ae_followups
      WHERE ae_id = ?
      ORDER BY followup_id DESC LIMIT 1
    ", list(ae_id))

    previous_followup_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$followup_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      ae_id, followup_type, notes, recorded_by, timestamp, previous_followup_hash,
      sep = "|"
    )
    followup_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO ae_followups (
        ae_id, followup_date, followup_type, previous_value, new_value,
        notes, recorded_by, followup_hash, previous_followup_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      ae_id,
      safe_scalar_ae(as.character(followup_date)),
      safe_scalar_ae(followup_type),
      safe_scalar_ae(previous_value),
      safe_scalar_ae(new_value),
      safe_scalar_ae(notes),
      safe_scalar_ae(recorded_by),
      followup_hash,
      previous_followup_hash
    ))

    followup_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    list(
      success = TRUE,
      followup_id = followup_id,
      message = "Follow-up recorded successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Resolve Adverse Event
#'
#' Records resolution of an adverse event.
#'
#' @param ae_id Integer: AE ID
#' @param resolution_date Date: Resolution date
#' @param outcome Character: Final outcome
#' @param resolved_by Character: User recording resolution
#' @param resolution_time Character: Resolution time (optional)
#' @param sequelae_description Character: Sequelae description (if applicable)
#' @param db_path Character: Database path (optional)
#'
#' @return List with resolution result
#'
#' @export
resolve_adverse_event <- function(ae_id,
                                   resolution_date,
                                   outcome,
                                   resolved_by,
                                   resolution_time = NULL,
                                   sequelae_description = NULL,
                                   db_path = NULL) {

  if (!outcome %in% c("RECOVERED", "RECOVERED_WITH_SEQUELAE", "FATAL")) {
    return(list(
      success = FALSE,
      error = "Resolution outcome must be RECOVERED, RECOVERED_WITH_SEQUELAE, or FATAL"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    ae <- DBI::dbGetQuery(conn, "
      SELECT outcome FROM adverse_events WHERE ae_id = ?
    ", list(ae_id))

    if (nrow(ae) == 0) {
      return(list(success = FALSE, error = "Adverse event not found"))
    }

    DBI::dbExecute(conn, "
      UPDATE adverse_events
      SET resolution_date = ?,
          resolution_time = ?,
          outcome = ?,
          sequelae_description = ?,
          status = 'CLOSED',
          updated_by = ?,
          updated_at = ?
      WHERE ae_id = ?
    ", list(
      safe_scalar_ae(as.character(resolution_date)),
      safe_scalar_ae(resolution_time),
      safe_scalar_ae(outcome),
      safe_scalar_ae(sequelae_description),
      safe_scalar_ae(resolved_by),
      as.character(Sys.time()),
      ae_id
    ))

    add_ae_followup(
      ae_id = ae_id,
      followup_type = "RESOLUTION",
      previous_value = ae$outcome,
      new_value = outcome,
      notes = paste("AE resolved on", resolution_date, "with outcome:", outcome),
      recorded_by = resolved_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      ae_id = ae_id,
      message = "Adverse event resolved successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Update AE Causality
#'
#' Updates the causality assessment for an adverse event.
#'
#' @param ae_id Integer: AE ID
#' @param causality Character: New causality assessment
#' @param rationale Character: Rationale for change
#' @param updated_by Character: User updating causality
#' @param db_path Character: Database path (optional)
#'
#' @return List with update result
#'
#' @export
update_ae_causality <- function(ae_id,
                                 causality,
                                 rationale,
                                 updated_by,
                                 db_path = NULL) {

  if (!causality %in% names(get_causality_categories())) {
    return(list(
      success = FALSE,
      error = paste("Invalid causality. Must be one of:",
                    paste(names(get_causality_categories()), collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    ae <- DBI::dbGetQuery(conn, "
      SELECT causality FROM adverse_events WHERE ae_id = ?
    ", list(ae_id))

    if (nrow(ae) == 0) {
      return(list(success = FALSE, error = "Adverse event not found"))
    }

    previous_causality <- ae$causality

    DBI::dbExecute(conn, "
      UPDATE adverse_events
      SET causality = ?,
          causality_rationale = ?,
          updated_by = ?,
          updated_at = ?
      WHERE ae_id = ?
    ", list(
      safe_scalar_ae(causality),
      safe_scalar_ae(rationale),
      safe_scalar_ae(updated_by),
      as.character(Sys.time()),
      ae_id
    ))

    add_ae_followup(
      ae_id = ae_id,
      followup_type = "CAUSALITY_UPDATE",
      previous_value = previous_causality,
      new_value = causality,
      notes = paste("Causality updated. Rationale:", rationale),
      recorded_by = updated_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      ae_id = ae_id,
      previous_causality = previous_causality,
      new_causality = causality,
      message = "Causality updated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# SAE Expedited Reporting
# =============================================================================

#' Record SAE Notification
#'
#' Records that an SAE notification was sent.
#'
#' @param sae_id Integer: SAE ID
#' @param notification_type Character: EXPEDITED, IRB, SPONSOR, or REGULATORY
#' @param notification_date Date: Notification date
#' @param recorded_by Character: User recording notification
#' @param db_path Character: Database path (optional)
#'
#' @return List with recording result
#'
#' @export
record_sae_notification <- function(sae_id,
                                     notification_type,
                                     notification_date,
                                     recorded_by,
                                     db_path = NULL) {

  if (!notification_type %in% c("EXPEDITED", "IRB", "SPONSOR", "REGULATORY")) {
    return(list(
      success = FALSE,
      error = "Notification type must be EXPEDITED, IRB, SPONSOR, or REGULATORY"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    update_field <- switch(notification_type,
      "EXPEDITED" = "expedited_report_sent = 1, expedited_report_sent_date = ?",
      "IRB" = "irb_notified = 1, irb_notification_date = ?",
      "SPONSOR" = "sponsor_notified = 1, sponsor_notification_date = ?",
      "REGULATORY" = "regulatory_notified = 1, regulatory_notification_date = ?"
    )

    query <- paste0("UPDATE sae_details SET ", update_field, " WHERE sae_id = ?")

    DBI::dbExecute(conn, query, list(
      safe_scalar_ae(as.character(notification_date)),
      sae_id
    ))

    sae <- DBI::dbGetQuery(conn, "
      SELECT ae_id FROM sae_details WHERE sae_id = ?
    ", list(sae_id))

    if (nrow(sae) > 0) {
      add_ae_followup(
        ae_id = sae$ae_id,
        followup_type = "STATUS_UPDATE",
        new_value = paste(notification_type, "notification sent"),
        notes = paste(notification_type, "notification sent on", notification_date),
        recorded_by = recorded_by,
        db_path = db_path
      )
    }

    list(
      success = TRUE,
      sae_id = sae_id,
      notification_type = notification_type,
      message = paste(notification_type, "notification recorded successfully")
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Get Pending SAE Reports
#'
#' Returns SAEs with pending expedited reports.
#'
#' @param study_id Character: Study ID (optional)
#' @param include_overdue Logical: Include only overdue (default FALSE)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with pending SAE reports
#'
#' @export
get_pending_sae_reports <- function(study_id = NULL,
                                     include_overdue = FALSE,
                                     db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    query <- "
      SELECT ae.*, sd.*
      FROM adverse_events ae
      INNER JOIN sae_details sd ON ae.ae_id = sd.ae_id
      WHERE sd.expedited_report_required = 1
        AND sd.expedited_report_sent = 0
    "
    params <- list()

    if (!is.null(study_id)) {
      query <- paste(query, "AND ae.study_id = ?")
      params <- c(params, list(safe_scalar_ae(study_id)))
    }

    if (include_overdue) {
      query <- paste(query, "AND sd.expedited_report_deadline < date('now')")
    }

    query <- paste(query, "ORDER BY sd.expedited_report_deadline ASC")

    if (length(params) > 0) {
      DBI::dbGetQuery(conn, query, params)
    } else {
      DBI::dbGetQuery(conn, query)
    }

  }, error = function(e) data.frame())
}


# =============================================================================
# Retrieval Functions
# =============================================================================

#' Get Adverse Event
#'
#' Retrieves an adverse event with full details.
#'
#' @param ae_id Integer: AE ID (optional)
#' @param ae_number Character: AE number (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with AE details
#'
#' @export
get_adverse_event <- function(ae_id = NULL,
                               ae_number = NULL,
                               db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (!is.null(ae_id)) {
      DBI::dbGetQuery(conn, "
        SELECT ae.*, sd.sae_number, sd.death, sd.life_threatening,
               sd.hospitalization, sd.disability, sd.expedited_report_deadline,
               sd.expedited_report_sent, sd.narrative
        FROM adverse_events ae
        LEFT JOIN sae_details sd ON ae.ae_id = sd.ae_id
        WHERE ae.ae_id = ?
      ", list(ae_id))
    } else if (!is.null(ae_number)) {
      DBI::dbGetQuery(conn, "
        SELECT ae.*, sd.sae_number, sd.death, sd.life_threatening,
               sd.hospitalization, sd.disability, sd.expedited_report_deadline,
               sd.expedited_report_sent, sd.narrative
        FROM adverse_events ae
        LEFT JOIN sae_details sd ON ae.ae_id = sd.ae_id
        WHERE ae.ae_number = ?
      ", list(safe_scalar_ae(ae_number)))
    } else {
      data.frame()
    }

  }, error = function(e) data.frame())
}


#' Get Subject Adverse Events
#'
#' Retrieves all adverse events for a subject.
#'
#' @param subject_id Character: Subject ID
#' @param study_id Character: Study ID (optional)
#' @param include_resolved Logical: Include resolved AEs (default TRUE)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with AEs
#'
#' @export
get_subject_adverse_events <- function(subject_id,
                                        study_id = NULL,
                                        include_resolved = TRUE,
                                        db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    query <- "
      SELECT ae.*, sd.sae_number
      FROM adverse_events ae
      LEFT JOIN sae_details sd ON ae.ae_id = sd.ae_id
      WHERE ae.subject_id = ?
    "
    params <- list(safe_scalar_ae(subject_id))

    if (!is.null(study_id)) {
      query <- paste(query, "AND ae.study_id = ?")
      params <- c(params, list(safe_scalar_ae(study_id)))
    }

    if (!include_resolved) {
      query <- paste(query, "AND ae.status != 'CLOSED'")
    }

    query <- paste(query, "ORDER BY ae.onset_date DESC")

    DBI::dbGetQuery(conn, query, params)

  }, error = function(e) data.frame())
}


#' Get AE Follow-ups
#'
#' Retrieves follow-up history for an adverse event.
#'
#' @param ae_id Integer: AE ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with follow-ups
#'
#' @export
get_ae_followups <- function(ae_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM ae_followups
      WHERE ae_id = ?
      ORDER BY recorded_at ASC
    ", list(ae_id))

  }, error = function(e) data.frame())
}


# =============================================================================
# Statistics and Reporting
# =============================================================================

#' Get AE Statistics
#'
#' Returns adverse event statistics for a study.
#'
#' @param study_id Character: Study ID
#' @param db_path Character: Database path (optional)
#'
#' @return List with AE statistics
#'
#' @export
get_ae_statistics <- function(study_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    overall <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_ae,
        SUM(CASE WHEN is_serious = 1 THEN 1 ELSE 0 END) as total_sae,
        SUM(CASE WHEN status = 'OPEN' THEN 1 ELSE 0 END) as open_ae,
        SUM(CASE WHEN status = 'CLOSED' THEN 1 ELSE 0 END) as closed_ae,
        COUNT(DISTINCT subject_id) as subjects_with_ae
      FROM adverse_events
      WHERE study_id = ?
    ", list(safe_scalar_ae(study_id)))

    by_severity <- DBI::dbGetQuery(conn, "
      SELECT severity, COUNT(*) as count
      FROM adverse_events
      WHERE study_id = ?
      GROUP BY severity
    ", list(safe_scalar_ae(study_id)))

    by_causality <- DBI::dbGetQuery(conn, "
      SELECT causality, COUNT(*) as count
      FROM adverse_events
      WHERE study_id = ?
      GROUP BY causality
    ", list(safe_scalar_ae(study_id)))

    by_outcome <- DBI::dbGetQuery(conn, "
      SELECT outcome, COUNT(*) as count
      FROM adverse_events
      WHERE study_id = ?
      GROUP BY outcome
    ", list(safe_scalar_ae(study_id)))

    pending_sae <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as count
      FROM adverse_events ae
      INNER JOIN sae_details sd ON ae.ae_id = sd.ae_id
      WHERE ae.study_id = ?
        AND sd.expedited_report_required = 1
        AND sd.expedited_report_sent = 0
    ", list(safe_scalar_ae(study_id)))

    overdue_sae <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as count
      FROM adverse_events ae
      INNER JOIN sae_details sd ON ae.ae_id = sd.ae_id
      WHERE ae.study_id = ?
        AND sd.expedited_report_required = 1
        AND sd.expedited_report_sent = 0
        AND sd.expedited_report_deadline < date('now')
    ", list(safe_scalar_ae(study_id)))

    list(
      success = TRUE,
      overall = list(
        total_ae = overall$total_ae,
        total_sae = overall$total_sae,
        open_ae = overall$open_ae,
        closed_ae = overall$closed_ae,
        subjects_with_ae = overall$subjects_with_ae
      ),
      by_severity = by_severity,
      by_causality = by_causality,
      by_outcome = by_outcome,
      pending_sae_reports = pending_sae$count,
      overdue_sae_reports = overdue_sae$count
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Generate AE Report
#'
#' Generates an adverse event summary report.
#'
#' @param study_id Character: Study ID
#' @param output_file Character: Output file path
#' @param format Character: Report format (txt or json)
#' @param organization Character: Organization name
#' @param prepared_by Character: Report preparer
#' @param db_path Character: Database path (optional)
#'
#' @return List with report generation status
#'
#' @export
generate_ae_report <- function(study_id,
                                output_file,
                                format = "txt",
                                organization = "Clinical Research Organization",
                                prepared_by = "Safety Officer",
                                db_path = NULL) {
  tryCatch({
    stats <- get_ae_statistics(study_id, db_path = db_path)

    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    all_ae <- DBI::dbGetQuery(conn, "
      SELECT ae.*, sd.sae_number, sd.death, sd.life_threatening,
             sd.expedited_report_sent, sd.expedited_report_deadline
      FROM adverse_events ae
      LEFT JOIN sae_details sd ON ae.ae_id = sd.ae_id
      WHERE ae.study_id = ?
      ORDER BY ae.onset_date DESC
    ", list(safe_scalar_ae(study_id)))

    if (format == "json") {
      report_data <- list(
        report_type = "Adverse Event Summary Report",
        organization = organization,
        study_id = study_id,
        generated_at = as.character(Sys.time()),
        prepared_by = prepared_by,
        statistics = stats,
        adverse_events = all_ae
      )

      jsonlite::write_json(report_data, output_file, pretty = TRUE, auto_unbox = TRUE)

    } else {
      lines <- c(
        "===============================================================================",
        "                    ADVERSE EVENT SUMMARY REPORT",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Study ID:", study_id),
        paste("Generated:", Sys.time()),
        paste("Prepared By:", prepared_by),
        "",
        "-------------------------------------------------------------------------------",
        "                              SUMMARY",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Adverse Events:", stats$overall$total_ae),
        paste("Total Serious Adverse Events:", stats$overall$total_sae),
        paste("Open AEs:", stats$overall$open_ae),
        paste("Closed AEs:", stats$overall$closed_ae),
        paste("Subjects with AEs:", stats$overall$subjects_with_ae),
        "",
        paste("Pending SAE Reports:", stats$pending_sae_reports),
        paste("Overdue SAE Reports:", stats$overdue_sae_reports),
        ""
      )

      if (nrow(stats$by_severity) > 0) {
        lines <- c(lines, "By Severity:")
        for (i in seq_len(nrow(stats$by_severity))) {
          lines <- c(lines, sprintf("  %-15s %d",
                                    stats$by_severity$severity[i],
                                    stats$by_severity$count[i]))
        }
        lines <- c(lines, "")
      }

      if (nrow(stats$by_causality) > 0) {
        lines <- c(lines, "By Causality:")
        for (i in seq_len(nrow(stats$by_causality))) {
          lines <- c(lines, sprintf("  %-15s %d",
                                    stats$by_causality$causality[i],
                                    stats$by_causality$count[i]))
        }
        lines <- c(lines, "")
      }

      lines <- c(lines,
        "-------------------------------------------------------------------------------",
        "                          ADVERSE EVENT LISTING",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(all_ae) > 0) {
        for (i in seq_len(nrow(all_ae))) {
          ae <- all_ae[i, ]
          sae_flag <- if (ae$is_serious == 1) " [SAE]" else ""
          lines <- c(lines,
            paste0(ae$ae_number, sae_flag),
            paste("  Subject:", ae$subject_id),
            paste("  Term:", ae$ae_term),
            paste("  Onset:", ae$onset_date),
            paste("  Severity:", ae$severity),
            paste("  Causality:", ae$causality),
            paste("  Outcome:", ae$outcome),
            paste("  Status:", ae$status),
            ""
          )
        }
      } else {
        lines <- c(lines, "No adverse events recorded.", "")
      }

      lines <- c(lines,
        "===============================================================================",
        "                              END OF REPORT",
        "==============================================================================="
      )

      writeLines(lines, output_file)
    }

    list(
      success = TRUE,
      output_file = output_file,
      format = format,
      message = "Report generated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
