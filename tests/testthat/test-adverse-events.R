# Test Adverse Event (AE/SAE) Management System
# Feature #9: FDA-compliant adverse event tracking

library(testthat)

pkg_root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(pkg_root, "R/encryption_utils.R"))
source(file.path(pkg_root, "R/aws_kms_utils.R"))
source(file.path(pkg_root, "R/db_connection.R"))
source(file.path(pkg_root, "R/secure_export.R"))
source(file.path(pkg_root, "R/audit_logging.R"))
source(file.path(pkg_root, "R/db_migration.R"))
source(file.path(pkg_root, "R/version_control.R"))
source(file.path(pkg_root, "R/adverse_events.R"))

setup_test_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") {
    Sys.setenv("ZZEDC_OLD_KEY" = old_key)
  }

  test_db <- tempfile(fileext = ".db")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  if (!init_result$success) {
    stop("Failed to initialize encrypted database: ", init_result$error)
  }

  audit_result <- init_audit_logging(db_path = test_db)
  if (!audit_result$success) {
    stop("Failed to initialize audit logging: ", audit_result$error)
  }

  ae_result <- init_adverse_events(db_path = test_db)
  if (!ae_result$success) {
    stop("Failed to initialize adverse events: ", ae_result$error)
  }

  test_db
}

cleanup_test_db <- function(test_db) {
  if (file.exists(test_db)) {
    unlink(test_db)
  }

  old_key <- Sys.getenv("ZZEDC_OLD_KEY")
  if (old_key != "") {
    Sys.setenv("DB_ENCRYPTION_KEY" = old_key)
    Sys.unsetenv("ZZEDC_OLD_KEY")
  }
}


# =============================================================================
# Initialization Tests
# =============================================================================

test_that("init_adverse_events creates required tables", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  conn <- connect_encrypted_db(db_path = test_db)
  tables <- DBI::dbListTables(conn)
  DBI::dbDisconnect(conn)

  expect_true("adverse_events" %in% tables)
  expect_true("sae_details" %in% tables)
  expect_true("ae_followups" %in% tables)
  expect_true("ae_concomitant_meds" %in% tables)
  expect_true("ae_medical_history" %in% tables)
})


# =============================================================================
# Reference Data Tests
# =============================================================================

test_that("get_ae_severity_grades returns all severity grades", {
  grades <- get_ae_severity_grades()

  expect_true(is.list(grades))
  expect_true("MILD" %in% names(grades))
  expect_true("MODERATE" %in% names(grades))
  expect_true("SEVERE" %in% names(grades))
  expect_equal(length(grades), 3)
})


test_that("get_sae_criteria returns all SAE criteria", {
  criteria <- get_sae_criteria()

  expect_true(is.list(criteria))
  expect_true("DEATH" %in% names(criteria))
  expect_true("LIFE_THREATENING" %in% names(criteria))
  expect_true("HOSPITALIZATION" %in% names(criteria))
  expect_true("DISABILITY" %in% names(criteria))
  expect_true("CONGENITAL_ANOMALY" %in% names(criteria))
  expect_true("OTHER_MEDICALLY_IMPORTANT" %in% names(criteria))
})


test_that("get_causality_categories returns all categories", {
  categories <- get_causality_categories()

  expect_true(is.list(categories))
  expect_true("UNRELATED" %in% names(categories))
  expect_true("UNLIKELY" %in% names(categories))
  expect_true("POSSIBLE" %in% names(categories))
  expect_true("PROBABLE" %in% names(categories))
  expect_true("DEFINITE" %in% names(categories))
})


test_that("get_ae_outcomes returns all outcome categories", {
  outcomes <- get_ae_outcomes()

  expect_true(is.list(outcomes))
  expect_true("RECOVERED" %in% names(outcomes))
  expect_true("RECOVERING" %in% names(outcomes))
  expect_true("FATAL" %in% names(outcomes))
  expect_true("ONGOING" %in% names(outcomes))
})


test_that("get_action_taken_categories returns all categories", {
  actions <- get_action_taken_categories()

  expect_true(is.list(actions))
  expect_true("NONE" %in% names(actions))
  expect_true("DOSE_REDUCED" %in% names(actions))
  expect_true("DRUG_WITHDRAWN" %in% names(actions))
})


# =============================================================================
# Adverse Event Creation Tests
# =============================================================================

test_that("create_adverse_event creates AE successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_adverse_event(
    study_id = "STUDY001",
    subject_id = "SUBJ001",
    onset_date = Sys.Date() - 5,
    ae_term = "Headache",
    ae_description = "Mild headache reported by subject",
    severity = "MILD",
    causality = "POSSIBLE",
    outcome = "RECOVERED",
    reported_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(result$ae_id > 0)
  expect_true(grepl("^AE-", result$ae_number))
})


test_that("create_adverse_event validates severity", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_adverse_event(
    study_id = "STUDY001",
    subject_id = "SUBJ001",
    onset_date = Sys.Date(),
    ae_term = "Headache",
    ae_description = "Test",
    severity = "INVALID",
    causality = "POSSIBLE",
    outcome = "ONGOING",
    reported_by = "coordinator",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Severity must be", result$error))
})


test_that("create_adverse_event validates causality", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_adverse_event(
    study_id = "STUDY001",
    subject_id = "SUBJ001",
    onset_date = Sys.Date(),
    ae_term = "Headache",
    ae_description = "Test",
    severity = "MILD",
    causality = "INVALID",
    outcome = "ONGOING",
    reported_by = "coordinator",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid causality", result$error))
})


test_that("create_adverse_event validates outcome", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_adverse_event(
    study_id = "STUDY001",
    subject_id = "SUBJ001",
    onset_date = Sys.Date(),
    ae_term = "Headache",
    ae_description = "Test",
    severity = "MILD",
    causality = "POSSIBLE",
    outcome = "INVALID",
    reported_by = "coordinator",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid outcome", result$error))
})


test_that("create_adverse_event creates hash chain", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae1 <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "Test 1", severity = "MILD",
    causality = "UNRELATED", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  ae2 <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ002", onset_date = Sys.Date(),
    ae_term = "Nausea", ae_description = "Test 2", severity = "MODERATE",
    causality = "POSSIBLE", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  conn <- connect_encrypted_db(db_path = test_db)
  aes <- DBI::dbGetQuery(conn, "
    SELECT ae_id, ae_hash, previous_hash FROM adverse_events ORDER BY ae_id
  ")
  DBI::dbDisconnect(conn)

  expect_equal(aes$previous_hash[1], "GENESIS")
  expect_equal(aes$previous_hash[2], aes$ae_hash[1])
})


# =============================================================================
# SAE Tests
# =============================================================================

test_that("upgrade_to_sae upgrades AE to SAE", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date() - 2,
    ae_term = "Chest Pain", ae_description = "Subject reports chest pain",
    severity = "SEVERE", causality = "POSSIBLE", outcome = "ONGOING",
    reported_by = "coordinator", db_path = test_db
  )

  result <- upgrade_to_sae(
    ae_id = ae$ae_id,
    sae_criteria = c("HOSPITALIZATION"),
    awareness_date = Sys.Date(),
    narrative = "Subject hospitalized for observation due to chest pain",
    upgraded_by = "pi",
    hospitalization = TRUE,
    hospitalization_admission_date = Sys.Date(),
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(grepl("^SAE-", result$sae_number))
  expect_true(!is.null(result$expedited_deadline))
})


test_that("upgrade_to_sae requires at least one criterion", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Test", ae_description = "Test", severity = "MILD",
    causality = "UNRELATED", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  result <- upgrade_to_sae(
    ae_id = ae$ae_id,
    sae_criteria = character(0),
    awareness_date = Sys.Date(),
    narrative = "Test",
    upgraded_by = "pi",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("At least one SAE criterion", result$error))
})


test_that("upgrade_to_sae prevents double upgrade", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Chest Pain", ae_description = "Test", severity = "SEVERE",
    causality = "POSSIBLE", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  upgrade_to_sae(
    ae_id = ae$ae_id, sae_criteria = c("HOSPITALIZATION"),
    awareness_date = Sys.Date(), narrative = "Test",
    upgraded_by = "pi", hospitalization = TRUE, db_path = test_db
  )

  result <- upgrade_to_sae(
    ae_id = ae$ae_id, sae_criteria = c("LIFE_THREATENING"),
    awareness_date = Sys.Date(), narrative = "Test again",
    upgraded_by = "pi", life_threatening = TRUE, db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("already classified as serious", result$error))
})


test_that("create_sae creates SAE directly", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_sae(
    study_id = "STUDY001",
    subject_id = "SUBJ001",
    onset_date = Sys.Date() - 1,
    ae_term = "Myocardial Infarction",
    ae_description = "Subject experienced myocardial infarction",
    severity = "SEVERE",
    causality = "POSSIBLE",
    outcome = "RECOVERING",
    sae_criteria = c("LIFE_THREATENING", "HOSPITALIZATION"),
    awareness_date = Sys.Date(),
    narrative = "Subject presented with MI, admitted to CCU",
    reported_by = "pi",
    life_threatening = TRUE,
    hospitalization = TRUE,
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(result$ae_id > 0)
  expect_true(result$sae_id > 0)
  expect_true(grepl("^SAE-", result$sae_number))
})


test_that("expedited deadline is 7 days for death/life-threatening", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  awareness_date <- Sys.Date()

  result <- create_sae(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Cardiac Arrest", ae_description = "Life-threatening event",
    severity = "SEVERE", causality = "PROBABLE", outcome = "RECOVERING",
    sae_criteria = c("LIFE_THREATENING"), awareness_date = awareness_date,
    narrative = "Life-threatening event", reported_by = "pi",
    life_threatening = TRUE, db_path = test_db
  )

  expected_deadline <- as.character(awareness_date + 7)
  expect_equal(result$expedited_deadline, expected_deadline)
})


test_that("expedited deadline is 15 days for other SAEs", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  awareness_date <- Sys.Date()

  result <- create_sae(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Hospitalization", ae_description = "Subject hospitalized",
    severity = "MODERATE", causality = "POSSIBLE", outcome = "RECOVERING",
    sae_criteria = c("HOSPITALIZATION"), awareness_date = awareness_date,
    narrative = "Hospitalization event", reported_by = "pi",
    hospitalization = TRUE, db_path = test_db
  )

  expected_deadline <- as.character(awareness_date + 15)
  expect_equal(result$expedited_deadline, expected_deadline)
})


# =============================================================================
# Follow-up Tests
# =============================================================================

test_that("add_ae_followup creates followup record", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "Test", severity = "MILD",
    causality = "POSSIBLE", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  result <- add_ae_followup(
    ae_id = ae$ae_id,
    followup_type = "STATUS_UPDATE",
    notes = "Subject reports improvement",
    recorded_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(result$followup_id > 0)
})


test_that("add_ae_followup validates followup type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- add_ae_followup(
    ae_id = 1,
    followup_type = "INVALID_TYPE",
    notes = "Test",
    recorded_by = "coordinator",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid followup type", result$error))
})


test_that("add_ae_followup maintains hash chain", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "Test", severity = "MILD",
    causality = "POSSIBLE", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  add_ae_followup(ae$ae_id, "STATUS_UPDATE", "Update 1", "coord", db_path = test_db)
  add_ae_followup(ae$ae_id, "STATUS_UPDATE", "Update 2", "coord", db_path = test_db)
  add_ae_followup(ae$ae_id, "STATUS_UPDATE", "Update 3", "coord", db_path = test_db)

  conn <- connect_encrypted_db(db_path = test_db)
  followups <- DBI::dbGetQuery(conn, "
    SELECT followup_id, followup_hash, previous_followup_hash
    FROM ae_followups WHERE ae_id = ? ORDER BY followup_id
  ", list(ae$ae_id))
  DBI::dbDisconnect(conn)

  expect_equal(followups$previous_followup_hash[1], "GENESIS")
  expect_equal(followups$previous_followup_hash[2], followups$followup_hash[1])
  expect_equal(followups$previous_followup_hash[3], followups$followup_hash[2])
})


# =============================================================================
# Resolution Tests
# =============================================================================

test_that("resolve_adverse_event closes AE", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date() - 7,
    ae_term = "Headache", ae_description = "Mild headache",
    severity = "MILD", causality = "UNRELATED", outcome = "ONGOING",
    reported_by = "coord", db_path = test_db
  )

  result <- resolve_adverse_event(
    ae_id = ae$ae_id,
    resolution_date = Sys.Date(),
    outcome = "RECOVERED",
    resolved_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)

  resolved_ae <- get_adverse_event(ae_id = ae$ae_id, db_path = test_db)
  expect_equal(resolved_ae$status, "CLOSED")
  expect_equal(resolved_ae$outcome, "RECOVERED")
})


test_that("resolve_adverse_event validates outcome", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "Test", severity = "MILD",
    causality = "UNRELATED", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  result <- resolve_adverse_event(
    ae_id = ae$ae_id,
    resolution_date = Sys.Date(),
    outcome = "ONGOING",
    resolved_by = "coordinator",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Resolution outcome must be", result$error))
})


# =============================================================================
# Causality Update Tests
# =============================================================================

test_that("update_ae_causality updates causality with history", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Rash", ae_description = "Skin rash developed",
    severity = "MODERATE", causality = "POSSIBLE", outcome = "ONGOING",
    reported_by = "coord", db_path = test_db
  )

  result <- update_ae_causality(
    ae_id = ae$ae_id,
    causality = "PROBABLE",
    rationale = "Positive rechallenge confirmed relationship",
    updated_by = "pi",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$previous_causality, "POSSIBLE")
  expect_equal(result$new_causality, "PROBABLE")

  followups <- get_ae_followups(ae$ae_id, db_path = test_db)
  expect_true(any(followups$followup_type == "CAUSALITY_UPDATE"))
})


test_that("update_ae_causality validates causality", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- update_ae_causality(
    ae_id = 1,
    causality = "INVALID",
    rationale = "Test",
    updated_by = "pi",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid causality", result$error))
})


# =============================================================================
# SAE Notification Tests
# =============================================================================

test_that("record_sae_notification records notification", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  sae <- create_sae(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Hospitalization", ae_description = "Test",
    severity = "MODERATE", causality = "POSSIBLE", outcome = "RECOVERING",
    sae_criteria = c("HOSPITALIZATION"), awareness_date = Sys.Date(),
    narrative = "Test", reported_by = "pi", hospitalization = TRUE,
    db_path = test_db
  )

  result <- record_sae_notification(
    sae_id = sae$sae_id,
    notification_type = "EXPEDITED",
    notification_date = Sys.Date(),
    recorded_by = "safety_officer",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$notification_type, "EXPEDITED")
})


test_that("record_sae_notification validates notification type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- record_sae_notification(
    sae_id = 1,
    notification_type = "INVALID",
    notification_date = Sys.Date(),
    recorded_by = "officer",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Notification type must be", result$error))
})


test_that("get_pending_sae_reports returns pending reports", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_sae(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "SAE 1", ae_description = "Test",
    severity = "SEVERE", causality = "POSSIBLE", outcome = "RECOVERING",
    sae_criteria = c("HOSPITALIZATION"), awareness_date = Sys.Date(),
    narrative = "Test", reported_by = "pi", hospitalization = TRUE,
    db_path = test_db
  )

  create_sae(
    study_id = "STUDY001", subject_id = "SUBJ002", onset_date = Sys.Date(),
    ae_term = "SAE 2", ae_description = "Test",
    severity = "SEVERE", causality = "POSSIBLE", outcome = "RECOVERING",
    sae_criteria = c("LIFE_THREATENING"), awareness_date = Sys.Date(),
    narrative = "Test", reported_by = "pi", life_threatening = TRUE,
    db_path = test_db
  )

  pending <- get_pending_sae_reports(study_id = "STUDY001", db_path = test_db)

  expect_equal(nrow(pending), 2)
})


# =============================================================================
# Retrieval Tests
# =============================================================================

test_that("get_adverse_event retrieves AE by ID", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "Test headache",
    severity = "MILD", causality = "POSSIBLE", outcome = "ONGOING",
    reported_by = "coord", db_path = test_db
  )

  retrieved <- get_adverse_event(ae_id = ae$ae_id, db_path = test_db)

  expect_equal(nrow(retrieved), 1)
  expect_equal(retrieved$ae_term, "Headache")
  expect_equal(retrieved$severity, "MILD")
})


test_that("get_adverse_event retrieves AE by number", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Nausea", ae_description = "Test nausea",
    severity = "MODERATE", causality = "PROBABLE", outcome = "ONGOING",
    reported_by = "coord", db_path = test_db
  )

  retrieved <- get_adverse_event(ae_number = ae$ae_number, db_path = test_db)

  expect_equal(nrow(retrieved), 1)
  expect_equal(retrieved$ae_term, "Nausea")
})


test_that("get_subject_adverse_events retrieves all subject AEs", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date() - 5,
    ae_term = "Headache", ae_description = "Test 1", severity = "MILD",
    causality = "POSSIBLE", outcome = "RECOVERED", reported_by = "coord",
    db_path = test_db
  )

  create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date() - 3,
    ae_term = "Nausea", ae_description = "Test 2", severity = "MODERATE",
    causality = "PROBABLE", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ002", onset_date = Sys.Date(),
    ae_term = "Fatigue", ae_description = "Test 3", severity = "MILD",
    causality = "UNRELATED", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  subj001_aes <- get_subject_adverse_events("SUBJ001", db_path = test_db)
  expect_equal(nrow(subj001_aes), 2)

  subj002_aes <- get_subject_adverse_events("SUBJ002", db_path = test_db)
  expect_equal(nrow(subj002_aes), 1)
})


test_that("get_ae_followups retrieves followup history", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "Test", severity = "MILD",
    causality = "POSSIBLE", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  add_ae_followup(ae$ae_id, "STATUS_UPDATE", "Improving", "coord", db_path = test_db)
  add_ae_followup(ae$ae_id, "ADDITIONAL_INFO", "More details", "coord", db_path = test_db)

  followups <- get_ae_followups(ae$ae_id, db_path = test_db)

  expect_equal(nrow(followups), 2)
  expect_equal(followups$followup_type[1], "STATUS_UPDATE")
  expect_equal(followups$followup_type[2], "ADDITIONAL_INFO")
})


# =============================================================================
# Statistics Tests
# =============================================================================

test_that("get_ae_statistics returns comprehensive stats", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "AE 1", ae_description = "Test", severity = "MILD",
    causality = "UNRELATED", outcome = "RECOVERED", reported_by = "coord",
    db_path = test_db
  )

  create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ002", onset_date = Sys.Date(),
    ae_term = "AE 2", ae_description = "Test", severity = "MODERATE",
    causality = "POSSIBLE", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  create_sae(
    study_id = "STUDY001", subject_id = "SUBJ003", onset_date = Sys.Date(),
    ae_term = "SAE 1", ae_description = "Test", severity = "SEVERE",
    causality = "PROBABLE", outcome = "RECOVERING",
    sae_criteria = c("HOSPITALIZATION"), awareness_date = Sys.Date(),
    narrative = "Test", reported_by = "pi", hospitalization = TRUE,
    db_path = test_db
  )

  stats <- get_ae_statistics("STUDY001", db_path = test_db)

  expect_true(stats$success)
  expect_equal(stats$overall$total_ae, 3)
  expect_equal(stats$overall$total_sae, 1)
  expect_equal(stats$overall$subjects_with_ae, 3)
  expect_true(nrow(stats$by_severity) > 0)
  expect_true(nrow(stats$by_causality) > 0)
})


# =============================================================================
# Report Generation Tests
# =============================================================================

test_that("generate_ae_report creates TXT report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "Test", severity = "MILD",
    causality = "POSSIBLE", outcome = "RECOVERED", reported_by = "coord",
    db_path = test_db
  )

  output_file <- tempfile(fileext = ".txt")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_ae_report(
    study_id = "STUDY001",
    output_file = output_file,
    format = "txt",
    organization = "Test CRO",
    prepared_by = "Safety Officer",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))

  content <- readLines(output_file)
  expect_true(any(grepl("ADVERSE EVENT SUMMARY REPORT", content)))
  expect_true(any(grepl("Test CRO", content)))
  expect_true(any(grepl("Headache", content)))
})


test_that("generate_ae_report creates JSON report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_adverse_event(
    study_id = "STUDY001", subject_id = "SUBJ001", onset_date = Sys.Date(),
    ae_term = "Nausea", ae_description = "Test", severity = "MODERATE",
    causality = "PROBABLE", outcome = "ONGOING", reported_by = "coord",
    db_path = test_db
  )

  output_file <- tempfile(fileext = ".json")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_ae_report(
    study_id = "STUDY001",
    output_file = output_file,
    format = "json",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))

  json_content <- jsonlite::read_json(output_file)
  expect_equal(json_content$report_type, "Adverse Event Summary Report")
  expect_equal(json_content$study_id, "STUDY001")
})


# =============================================================================
# Integration Tests
# =============================================================================

test_that("full AE lifecycle workflow", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  ae <- create_adverse_event(
    study_id = "STUDY001",
    subject_id = "SUBJ001",
    onset_date = Sys.Date() - 10,
    ae_term = "Skin Rash",
    ae_description = "Subject developed mild skin rash on arms",
    severity = "MILD",
    causality = "POSSIBLE",
    outcome = "ONGOING",
    reported_by = "coordinator",
    site_id = "SITE01",
    action_taken = "CONCOMITANT_MED_GIVEN",
    treatment_given = TRUE,
    treatment_description = "Topical corticosteroid cream applied",
    db_path = test_db
  )

  expect_true(ae$success)

  add_ae_followup(
    ae_id = ae$ae_id,
    followup_type = "STATUS_UPDATE",
    notes = "Rash improving with treatment",
    recorded_by = "coordinator",
    db_path = test_db
  )

  add_ae_followup(
    ae_id = ae$ae_id,
    followup_type = "STATUS_UPDATE",
    notes = "Rash mostly resolved",
    recorded_by = "coordinator",
    db_path = test_db
  )

  update_ae_causality(
    ae_id = ae$ae_id,
    causality = "PROBABLE",
    rationale = "Temporal relationship and positive dechallenge suggest drug relationship",
    updated_by = "pi",
    db_path = test_db
  )

  resolve_adverse_event(
    ae_id = ae$ae_id,
    resolution_date = Sys.Date(),
    outcome = "RECOVERED",
    resolved_by = "coordinator",
    db_path = test_db
  )

  final_ae <- get_adverse_event(ae_id = ae$ae_id, db_path = test_db)
  expect_equal(final_ae$status, "CLOSED")
  expect_equal(final_ae$outcome, "RECOVERED")
  expect_equal(final_ae$causality, "PROBABLE")

  followups <- get_ae_followups(ae$ae_id, db_path = test_db)
  expect_true(nrow(followups) >= 3)

  stats <- get_ae_statistics("STUDY001", db_path = test_db)
  expect_equal(stats$overall$closed_ae, 1)
})


test_that("SAE expedited reporting workflow", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  sae <- create_sae(
    study_id = "STUDY001",
    subject_id = "SUBJ001",
    onset_date = Sys.Date() - 2,
    ae_term = "Severe Allergic Reaction",
    ae_description = "Subject experienced anaphylaxis requiring epinephrine",
    severity = "SEVERE",
    causality = "PROBABLE",
    outcome = "RECOVERING",
    sae_criteria = c("LIFE_THREATENING", "HOSPITALIZATION"),
    awareness_date = Sys.Date() - 1,
    narrative = "Subject developed anaphylaxis 30 minutes after drug administration",
    reported_by = "pi",
    life_threatening = TRUE,
    hospitalization = TRUE,
    expectedness = "UNEXPECTED",
    action_taken = "DRUG_WITHDRAWN",
    db_path = test_db
  )

  expect_true(sae$success)

  pending <- get_pending_sae_reports(study_id = "STUDY001", db_path = test_db)
  expect_equal(nrow(pending), 1)

  record_sae_notification(
    sae_id = sae$sae_id,
    notification_type = "EXPEDITED",
    notification_date = Sys.Date(),
    recorded_by = "safety_officer",
    db_path = test_db
  )

  record_sae_notification(
    sae_id = sae$sae_id,
    notification_type = "IRB",
    notification_date = Sys.Date(),
    recorded_by = "regulatory_affairs",
    db_path = test_db
  )

  record_sae_notification(
    sae_id = sae$sae_id,
    notification_type = "SPONSOR",
    notification_date = Sys.Date(),
    recorded_by = "safety_officer",
    db_path = test_db
  )

  pending_after <- get_pending_sae_reports(study_id = "STUDY001", db_path = test_db)
  expect_equal(nrow(pending_after), 0)

  stats <- get_ae_statistics("STUDY001", db_path = test_db)
  expect_equal(stats$overall$total_sae, 1)
  expect_equal(stats$pending_sae_reports, 0)
})
