# Test Protocol Compliance Monitoring System
# Feature #8: FDA-compliant protocol adherence tracking

library(testthat)

pkg_root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(pkg_root, "R/encryption_utils.R"))
source(file.path(pkg_root, "R/aws_kms_utils.R"))
source(file.path(pkg_root, "R/db_connection.R"))
source(file.path(pkg_root, "R/secure_export.R"))
source(file.path(pkg_root, "R/audit_logging.R"))
source(file.path(pkg_root, "R/db_migration.R"))
source(file.path(pkg_root, "R/version_control.R"))
source(file.path(pkg_root, "R/protocol_compliance.R"))

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

  version_result <- init_version_control(db_path = test_db)
  if (!version_result$success) {
    stop("Failed to initialize version control: ", version_result$error)
  }

  compliance_result <- init_protocol_compliance(db_path = test_db)
  if (!compliance_result$success) {
    stop("Failed to initialize protocol compliance: ", compliance_result$error)
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

test_that("init_protocol_compliance creates required tables", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  conn <- connect_encrypted_db(db_path = test_db)
  tables <- DBI::dbListTables(conn)
  DBI::dbDisconnect(conn)

  expect_true("protocol_definitions" %in% tables)
  expect_true("protocol_visits" %in% tables)
  expect_true("protocol_assessments" %in% tables)
  expect_true("subject_visits" %in% tables)
  expect_true("protocol_deviations" %in% tables)
  expect_true("eligibility_criteria" %in% tables)
  expect_true("eligibility_checks" %in% tables)
})


# =============================================================================
# Protocol Definition Tests
# =============================================================================

test_that("create_protocol creates new protocol successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_protocol(
    protocol_code = "PROTO-001",
    protocol_title = "Test Clinical Trial",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    sponsor = "Test Sponsor",
    principal_investigator = "Dr. Smith",
    description = "A test protocol for unit testing",
    created_by = "admin",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$protocol_code, "PROTO-001")
  expect_true(result$protocol_id > 0)
})


test_that("get_protocol retrieves protocol by ID", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_result <- create_protocol(
    protocol_code = "PROTO-002",
    protocol_title = "Second Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  protocol <- get_protocol(protocol_id = create_result$protocol_id, db_path = test_db)

  expect_equal(nrow(protocol), 1)
  expect_equal(protocol$protocol_code, "PROTO-002")
  expect_equal(protocol$protocol_title, "Second Protocol")
  expect_equal(protocol$status, "ACTIVE")
})


test_that("get_protocol retrieves protocol by code", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_protocol(
    protocol_code = "PROTO-003",
    protocol_title = "Third Protocol",
    protocol_version = "2.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  protocol <- get_protocol(protocol_code = "PROTO-003", db_path = test_db)

  expect_equal(nrow(protocol), 1)
  expect_equal(protocol$protocol_code, "PROTO-003")
  expect_equal(protocol$protocol_version, "2.0")
})


test_that("duplicate protocol codes are rejected", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_protocol(
    protocol_code = "DUP-001",
    protocol_title = "First Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  result <- create_protocol(
    protocol_code = "DUP-001",
    protocol_title = "Duplicate Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("UNIQUE constraint", result$error, ignore.case = TRUE))
})


# =============================================================================
# Visit Schedule Tests
# =============================================================================

test_that("add_protocol_visit adds visit successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "VISIT-001",
    protocol_title = "Visit Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  result <- add_protocol_visit(
    protocol_id = protocol$protocol_id,
    visit_code = "V1",
    visit_name = "Screening Visit",
    visit_order = 1,
    target_day = 0,
    window_before = 7,
    window_after = 0,
    is_required = TRUE,
    visit_type = "SCREENING",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(result$visit_id > 0)
})


test_that("get_protocol_visits retrieves all visits in order", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "VISIT-002",
    protocol_title = "Multi-Visit Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  add_protocol_visit(protocol$protocol_id, "V1", "Screening", 1, 0,
                     window_before = 7, window_after = 0, visit_type = "SCREENING",
                     db_path = test_db)
  add_protocol_visit(protocol$protocol_id, "V2", "Baseline", 2, 1,
                     window_before = 0, window_after = 3, visit_type = "BASELINE",
                     db_path = test_db)
  add_protocol_visit(protocol$protocol_id, "V3", "Week 4", 3, 28,
                     window_before = 3, window_after = 3, visit_type = "SCHEDULED",
                     db_path = test_db)
  add_protocol_visit(protocol$protocol_id, "V4", "Week 8", 4, 56,
                     window_before = 3, window_after = 3, visit_type = "SCHEDULED",
                     db_path = test_db)

  visits <- get_protocol_visits(protocol$protocol_id, db_path = test_db)

  expect_equal(nrow(visits), 4)
  expect_equal(visits$visit_code, c("V1", "V2", "V3", "V4"))
  expect_equal(visits$visit_order, c(1, 2, 3, 4))
  expect_equal(visits$target_day, c(0, 1, 28, 56))
})


test_that("visit windows are correctly defined", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "WINDOW-001",
    protocol_title = "Window Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  add_protocol_visit(protocol$protocol_id, "V1", "Week 2", 1, 14,
                     window_before = 2, window_after = 2,
                     db_path = test_db)

  visits <- get_protocol_visits(protocol$protocol_id, db_path = test_db)

  expect_equal(visits$target_day[1], 14)
  expect_equal(visits$window_before[1], 2)
  expect_equal(visits$window_after[1], 2)
})


# =============================================================================
# Subject Visit Tracking Tests
# =============================================================================

test_that("schedule_subject_visit schedules visit successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "SUBJ-001",
    protocol_title = "Subject Visit Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  visit <- add_protocol_visit(protocol$protocol_id, "V1", "Baseline", 1, 0,
                              db_path = test_db)

  baseline_date <- Sys.Date()
  result <- schedule_subject_visit(
    subject_id = "SUBJ001",
    protocol_id = protocol$protocol_id,
    visit_id = visit$visit_id,
    scheduled_date = baseline_date,
    baseline_date = baseline_date,
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(result$subject_visit_id > 0)
})


test_that("complete_subject_visit within window returns WITHIN_WINDOW", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "COMPLETE-001",
    protocol_title = "Completion Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  visit <- add_protocol_visit(protocol$protocol_id, "V1", "Week 2", 1, 14,
                              window_before = 3, window_after = 3,
                              db_path = test_db)

  baseline_date <- Sys.Date() - 14
  actual_date <- Sys.Date()

  result <- complete_subject_visit(
    subject_id = "SUBJ001",
    protocol_id = protocol$protocol_id,
    visit_id = visit$visit_id,
    actual_date = actual_date,
    baseline_date = baseline_date,
    completed_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$window_status, "WITHIN_WINDOW")
  expect_equal(result$days_from_baseline, 14)
  expect_false(result$deviation_created)
})


test_that("complete_subject_visit early creates deviation", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "EARLY-001",
    protocol_title = "Early Visit Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  visit <- add_protocol_visit(protocol$protocol_id, "V1", "Week 4", 1, 28,
                              window_before = 3, window_after = 3,
                              db_path = test_db)

  baseline_date <- Sys.Date() - 20
  actual_date <- Sys.Date()

  result <- complete_subject_visit(
    subject_id = "SUBJ001",
    protocol_id = protocol$protocol_id,
    visit_id = visit$visit_id,
    actual_date = actual_date,
    baseline_date = baseline_date,
    completed_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$window_status, "EARLY")
  expect_equal(result$days_from_baseline, 20)
  expect_true(result$deviation_created)
  expect_true(result$deviation_id > 0)
})


test_that("complete_subject_visit late creates deviation", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "LATE-001",
    protocol_title = "Late Visit Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  visit <- add_protocol_visit(protocol$protocol_id, "V1", "Week 2", 1, 14,
                              window_before = 2, window_after = 2,
                              db_path = test_db)

  baseline_date <- Sys.Date() - 20
  actual_date <- Sys.Date()

  result <- complete_subject_visit(
    subject_id = "SUBJ001",
    protocol_id = protocol$protocol_id,
    visit_id = visit$visit_id,
    actual_date = actual_date,
    baseline_date = baseline_date,
    completed_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$window_status, "LATE")
  expect_equal(result$days_from_baseline, 20)
  expect_true(result$deviation_created)
})


test_that("get_subject_visit_status returns visit status", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "STATUS-001",
    protocol_title = "Status Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  visit1 <- add_protocol_visit(protocol$protocol_id, "V1", "Baseline", 1, 0,
                               db_path = test_db)
  visit2 <- add_protocol_visit(protocol$protocol_id, "V2", "Week 2", 2, 14,
                               window_before = 3, window_after = 3,
                               db_path = test_db)

  baseline_date <- Sys.Date()

  complete_subject_visit(
    subject_id = "SUBJ001",
    protocol_id = protocol$protocol_id,
    visit_id = visit1$visit_id,
    actual_date = baseline_date,
    baseline_date = baseline_date,
    completed_by = "coordinator",
    db_path = test_db
  )

  status <- get_subject_visit_status("SUBJ001", protocol$protocol_id, db_path = test_db)

  expect_equal(nrow(status), 2)
  expect_equal(status$visit_code, c("V1", "V2"))
  expect_equal(status$status[1], "COMPLETED")
  expect_true(is.na(status$status[2]))
})


# =============================================================================
# Protocol Deviation Tests
# =============================================================================

test_that("get_deviation_types returns all valid types", {
  types <- get_deviation_types()

  expect_true(is.list(types))
  expect_true("VISIT_TIMING" %in% names(types))
  expect_true("MISSED_VISIT" %in% names(types))
  expect_true("MISSED_ASSESSMENT" %in% names(types))
  expect_true("ELIGIBILITY" %in% names(types))
  expect_true("DOSING" %in% names(types))
  expect_true("PROCEDURE" %in% names(types))
  expect_true("DOCUMENTATION" %in% names(types))
  expect_true("OTHER" %in% names(types))
})


test_that("create_protocol_deviation creates deviation with hash chain", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "DEV-001",
    protocol_title = "Deviation Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  result <- create_protocol_deviation(
    protocol_id = protocol$protocol_id,
    subject_id = "SUBJ001",
    deviation_type = "DOSING",
    severity = "MINOR",
    deviation_date = Sys.Date(),
    description = "Subject missed morning dose",
    root_cause = "Patient forgot",
    corrective_action = "Patient re-educated on dosing schedule",
    reported_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(result$deviation_id > 0)
  expect_true(nchar(result$deviation_hash) == 64)
})


test_that("create_protocol_deviation validates deviation type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "DEV-002",
    protocol_title = "Validation Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  result <- create_protocol_deviation(
    protocol_id = protocol$protocol_id,
    subject_id = "SUBJ001",
    deviation_type = "INVALID_TYPE",
    severity = "MINOR",
    deviation_date = Sys.Date(),
    description = "Test deviation",
    reported_by = "coordinator",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid deviation type", result$error))
})


test_that("create_protocol_deviation validates severity", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "DEV-003",
    protocol_title = "Severity Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  result <- create_protocol_deviation(
    protocol_id = protocol$protocol_id,
    subject_id = "SUBJ001",
    deviation_type = "DOSING",
    severity = "LOW",
    deviation_date = Sys.Date(),
    description = "Test deviation",
    reported_by = "coordinator",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Severity must be MINOR, MAJOR, or CRITICAL", result$error))
})


test_that("review_protocol_deviation updates deviation status", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "REVIEW-001",
    protocol_title = "Review Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  deviation <- create_protocol_deviation(
    protocol_id = protocol$protocol_id,
    subject_id = "SUBJ001",
    deviation_type = "PROCEDURE",
    severity = "MAJOR",
    deviation_date = Sys.Date(),
    description = "Required blood draw not performed",
    reported_by = "coordinator",
    db_path = test_db
  )

  result <- review_protocol_deviation(
    deviation_id = deviation$deviation_id,
    reviewed_by = "pi",
    review_status = "APPROVED",
    resolution_notes = "Deviation documented, no further action needed",
    resolution_date = Sys.Date(),
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$review_status, "APPROVED")
})


test_that("review_protocol_deviation validates status", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- review_protocol_deviation(
    deviation_id = 1,
    reviewed_by = "pi",
    review_status = "INVALID_STATUS",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Review status must be", result$error))
})


test_that("get_protocol_deviations retrieves filtered deviations", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "FILTER-001",
    protocol_title = "Filter Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  create_protocol_deviation(protocol$protocol_id, "SUBJ001", "DOSING", "MINOR",
                            Sys.Date(), "Minor deviation 1", reported_by = "coord",
                            db_path = test_db)
  create_protocol_deviation(protocol$protocol_id, "SUBJ001", "PROCEDURE", "MAJOR",
                            Sys.Date(), "Major deviation 1", reported_by = "coord",
                            db_path = test_db)
  create_protocol_deviation(protocol$protocol_id, "SUBJ002", "DOSING", "MINOR",
                            Sys.Date(), "Minor deviation 2", reported_by = "coord",
                            db_path = test_db)

  all_deviations <- get_protocol_deviations(protocol_id = protocol$protocol_id,
                                            db_path = test_db)
  expect_equal(nrow(all_deviations), 3)

  subj001_deviations <- get_protocol_deviations(protocol_id = protocol$protocol_id,
                                                subject_id = "SUBJ001",
                                                db_path = test_db)
  expect_equal(nrow(subj001_deviations), 2)

  major_deviations <- get_protocol_deviations(protocol_id = protocol$protocol_id,
                                              severity = "MAJOR",
                                              db_path = test_db)
  expect_equal(nrow(major_deviations), 1)
})


# =============================================================================
# Eligibility Tests
# =============================================================================

test_that("add_eligibility_criterion creates inclusion criteria", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "ELIG-001",
    protocol_title = "Eligibility Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  result <- add_eligibility_criterion(
    protocol_id = protocol$protocol_id,
    criterion_type = "INCLUSION",
    criterion_code = "INC01",
    criterion_text = "Age 18 years or older",
    field_name = "age",
    operator = "GE",
    value = "18",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(result$criterion_id > 0)
})


test_that("add_eligibility_criterion creates exclusion criteria", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "ELIG-002",
    protocol_title = "Exclusion Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  result <- add_eligibility_criterion(
    protocol_id = protocol$protocol_id,
    criterion_type = "EXCLUSION",
    criterion_code = "EXC01",
    criterion_text = "Pregnant or nursing females",
    field_name = "pregnant",
    operator = "EQ",
    value = "YES",
    db_path = test_db
  )

  expect_true(result$success)
})


test_that("add_eligibility_criterion validates criterion type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- add_eligibility_criterion(
    protocol_id = 1,
    criterion_type = "INVALID",
    criterion_code = "INV01",
    criterion_text = "Invalid criterion",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("INCLUSION or EXCLUSION", result$error))
})


test_that("check_subject_eligibility passes for eligible subject", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "CHECK-001",
    protocol_title = "Check Eligibility Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  add_eligibility_criterion(protocol$protocol_id, "INCLUSION", "INC01",
                            "Age 18-65", "age", "GE", "18",
                            db_path = test_db)
  add_eligibility_criterion(protocol$protocol_id, "INCLUSION", "INC02",
                            "Age 18-65", "age", "LE", "65",
                            db_path = test_db)
  add_eligibility_criterion(protocol$protocol_id, "EXCLUSION", "EXC01",
                            "Pregnant", "pregnant", "EQ", "YES",
                            db_path = test_db)

  subject_data <- list(age = 35, pregnant = "NO")

  result <- check_subject_eligibility(
    subject_id = "SUBJ001",
    protocol_id = protocol$protocol_id,
    subject_data = subject_data,
    checked_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(result$eligible)
  expect_true(result$all_inclusion_met)
  expect_false(result$any_exclusion_met)
})


test_that("check_subject_eligibility fails for ineligible subject - exclusion met", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "CHECK-002",
    protocol_title = "Ineligibility Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  add_eligibility_criterion(protocol$protocol_id, "INCLUSION", "INC01",
                            "Age 18+", "age", "GE", "18",
                            db_path = test_db)
  add_eligibility_criterion(protocol$protocol_id, "EXCLUSION", "EXC01",
                            "Pregnant", "pregnant", "EQ", "YES",
                            db_path = test_db)

  subject_data <- list(age = 30, pregnant = "YES")

  result <- check_subject_eligibility(
    subject_id = "SUBJ002",
    protocol_id = protocol$protocol_id,
    subject_data = subject_data,
    checked_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_false(result$eligible)
  expect_true(result$any_exclusion_met)
})


test_that("check_subject_eligibility fails for ineligible subject - inclusion not met", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "CHECK-003",
    protocol_title = "Inclusion Failure Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  add_eligibility_criterion(protocol$protocol_id, "INCLUSION", "INC01",
                            "Age 18+", "age", "GE", "18",
                            db_path = test_db)

  subject_data <- list(age = 16)

  result <- check_subject_eligibility(
    subject_id = "SUBJ003",
    protocol_id = protocol$protocol_id,
    subject_data = subject_data,
    checked_by = "coordinator",
    db_path = test_db
  )

  expect_true(result$success)
  expect_false(result$eligible)
  expect_false(result$all_inclusion_met)
})


test_that("evaluate_criterion handles different operators", {
  expect_true(evaluate_criterion(25, "GT", "20"))
  expect_true(evaluate_criterion(20, "GE", "20"))
  expect_true(evaluate_criterion(15, "LT", "20"))
  expect_true(evaluate_criterion(20, "LE", "20"))
  expect_true(evaluate_criterion("A", "EQ", "A"))
  expect_true(evaluate_criterion("A", "NE", "B"))
  expect_true(evaluate_criterion("B", "IN", "A,B,C"))
  expect_true(evaluate_criterion("D", "NOT_IN", "A,B,C"))
  expect_true(evaluate_criterion("test123", "REGEX", "test[0-9]+"))
})


# =============================================================================
# Compliance Statistics Tests
# =============================================================================

test_that("get_compliance_statistics returns comprehensive stats", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "STATS-001",
    protocol_title = "Statistics Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  visit1 <- add_protocol_visit(protocol$protocol_id, "V1", "Baseline", 1, 0,
                               db_path = test_db)
  visit2 <- add_protocol_visit(protocol$protocol_id, "V2", "Week 2", 2, 14,
                               window_before = 3, window_after = 3,
                               db_path = test_db)

  baseline_date <- Sys.Date() - 14
  complete_subject_visit("SUBJ001", protocol$protocol_id, visit1$visit_id,
                         baseline_date, baseline_date, "coord", db_path = test_db)
  complete_subject_visit("SUBJ001", protocol$protocol_id, visit2$visit_id,
                         Sys.Date(), baseline_date, "coord", db_path = test_db)

  create_protocol_deviation(protocol$protocol_id, "SUBJ001", "DOSING", "MINOR",
                            Sys.Date(), "Test deviation", reported_by = "coord",
                            db_path = test_db)

  add_eligibility_criterion(protocol$protocol_id, "INCLUSION", "INC01",
                            "Age 18+", "age", "GE", "18",
                            db_path = test_db)
  check_subject_eligibility("SUBJ001", protocol$protocol_id,
                            list(age = 25), "coord", db_path = test_db)

  stats <- get_compliance_statistics(protocol$protocol_id, db_path = test_db)

  expect_true(stats$success)
  expect_true(stats$visits$total > 0)
  expect_true(stats$visits$completed > 0)
  expect_true(stats$deviations$total > 0)
  expect_true(stats$eligibility$total_checks > 0)
})


# =============================================================================
# Report Generation Tests
# =============================================================================

test_that("generate_compliance_report creates TXT report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "REPORT-001",
    protocol_title = "Report Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  visit <- add_protocol_visit(protocol$protocol_id, "V1", "Baseline", 1, 0,
                              db_path = test_db)

  complete_subject_visit("SUBJ001", protocol$protocol_id, visit$visit_id,
                         Sys.Date(), Sys.Date(), "coord", db_path = test_db)

  output_file <- tempfile(fileext = ".txt")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_compliance_report(
    protocol_id = protocol$protocol_id,
    output_file = output_file,
    format = "txt",
    organization = "Test CRO",
    prepared_by = "Compliance Officer",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))
  expect_equal(result$format, "txt")

  content <- readLines(output_file)
  expect_true(any(grepl("PROTOCOL COMPLIANCE REPORT", content)))
  expect_true(any(grepl("Test CRO", content)))
})


test_that("generate_compliance_report creates JSON report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "REPORT-002",
    protocol_title = "JSON Report Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  output_file <- tempfile(fileext = ".json")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_compliance_report(
    protocol_id = protocol$protocol_id,
    output_file = output_file,
    format = "json",
    organization = "Test CRO",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))
  expect_equal(result$format, "json")

  json_content <- jsonlite::read_json(output_file)
  expect_equal(json_content$report_type, "Protocol Compliance Report")
  expect_equal(json_content$organization, "Test CRO")
})


# =============================================================================
# Integration Tests
# =============================================================================

test_that("full compliance workflow with multiple subjects", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "INTEG-001",
    protocol_title = "Integration Test Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    sponsor = "Pharma Co",
    principal_investigator = "Dr. Jones",
    created_by = "admin",
    db_path = test_db
  )

  visit1 <- add_protocol_visit(protocol$protocol_id, "SCR", "Screening", 1, -7,
                               window_before = 7, window_after = 0,
                               visit_type = "SCREENING", db_path = test_db)
  visit2 <- add_protocol_visit(protocol$protocol_id, "BL", "Baseline", 2, 0,
                               window_before = 0, window_after = 3,
                               visit_type = "BASELINE", db_path = test_db)
  visit3 <- add_protocol_visit(protocol$protocol_id, "W4", "Week 4", 3, 28,
                               window_before = 3, window_after = 3,
                               visit_type = "SCHEDULED", db_path = test_db)
  visit4 <- add_protocol_visit(protocol$protocol_id, "W8", "Week 8", 4, 56,
                               window_before = 3, window_after = 3,
                               visit_type = "SCHEDULED", db_path = test_db)

  add_eligibility_criterion(protocol$protocol_id, "INCLUSION", "INC01",
                            "Age 18-65", "age", "GE", "18", db_path = test_db)
  add_eligibility_criterion(protocol$protocol_id, "INCLUSION", "INC02",
                            "Age 18-65", "age", "LE", "65", db_path = test_db)
  add_eligibility_criterion(protocol$protocol_id, "EXCLUSION", "EXC01",
                            "Active cancer", "active_cancer", "EQ", "YES",
                            db_path = test_db)

  subjects <- list(
    list(id = "S001", age = 45, active_cancer = "NO"),
    list(id = "S002", age = 32, active_cancer = "NO"),
    list(id = "S003", age = 17, active_cancer = "NO")
  )

  for (subj in subjects) {
    result <- check_subject_eligibility(
      subject_id = subj$id,
      protocol_id = protocol$protocol_id,
      subject_data = subj,
      checked_by = "screener",
      db_path = test_db
    )

    if (subj$id == "S003") {
      expect_false(result$eligible)
    } else {
      expect_true(result$eligible)
    }
  }

  baseline_s001 <- Sys.Date() - 30
  baseline_s002 <- Sys.Date() - 28

  complete_subject_visit("S001", protocol$protocol_id, visit1$visit_id,
                         baseline_s001 - 5, baseline_s001, "coord", db_path = test_db)
  complete_subject_visit("S001", protocol$protocol_id, visit2$visit_id,
                         baseline_s001, baseline_s001, "coord", db_path = test_db)
  complete_subject_visit("S001", protocol$protocol_id, visit3$visit_id,
                         baseline_s001 + 28, baseline_s001, "coord", db_path = test_db)

  complete_subject_visit("S002", protocol$protocol_id, visit1$visit_id,
                         baseline_s002 - 5, baseline_s002, "coord", db_path = test_db)
  complete_subject_visit("S002", protocol$protocol_id, visit2$visit_id,
                         baseline_s002, baseline_s002, "coord", db_path = test_db)
  late_result <- complete_subject_visit("S002", protocol$protocol_id, visit3$visit_id,
                                        baseline_s002 + 35, baseline_s002, "coord",
                                        db_path = test_db)

  expect_equal(late_result$window_status, "LATE")
  expect_true(late_result$deviation_created)

  create_protocol_deviation(
    protocol_id = protocol$protocol_id,
    subject_id = "S001",
    deviation_type = "DOSING",
    severity = "MINOR",
    deviation_date = baseline_s001 + 15,
    description = "Subject missed evening dose on Day 15",
    root_cause = "Subject traveling",
    corrective_action = "Subject counseled on dose timing",
    reported_by = "coordinator",
    db_path = test_db
  )

  stats <- get_compliance_statistics(protocol$protocol_id, db_path = test_db)

  expect_true(stats$success)
  expect_equal(stats$visits$completed, 6)
  expect_true(stats$deviations$total >= 2)

  output_file <- tempfile(fileext = ".txt")
  on.exit(unlink(output_file), add = TRUE)

  report <- generate_compliance_report(
    protocol_id = protocol$protocol_id,
    output_file = output_file,
    format = "txt",
    organization = "Clinical Research Center",
    prepared_by = "Compliance Manager",
    db_path = test_db
  )

  expect_true(report$success)
  expect_true(file.exists(output_file))
})


test_that("deviation hash chain maintains integrity", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  protocol <- create_protocol(
    protocol_code = "HASH-001",
    protocol_title = "Hash Chain Protocol",
    protocol_version = "1.0",
    effective_date = Sys.Date(),
    created_by = "admin",
    db_path = test_db
  )

  dev1 <- create_protocol_deviation(protocol$protocol_id, "S001", "DOSING",
                                    "MINOR", Sys.Date(), "Deviation 1",
                                    reported_by = "coord", db_path = test_db)
  dev2 <- create_protocol_deviation(protocol$protocol_id, "S001", "PROCEDURE",
                                    "MAJOR", Sys.Date(), "Deviation 2",
                                    reported_by = "coord", db_path = test_db)
  dev3 <- create_protocol_deviation(protocol$protocol_id, "S002", "DOCUMENTATION",
                                    "MINOR", Sys.Date(), "Deviation 3",
                                    reported_by = "coord", db_path = test_db)

  conn <- connect_encrypted_db(db_path = test_db)
  deviations <- DBI::dbGetQuery(conn, "
    SELECT deviation_id, deviation_hash, previous_hash
    FROM protocol_deviations
    ORDER BY deviation_id ASC
  ")
  DBI::dbDisconnect(conn)

  expect_equal(deviations$previous_hash[1], "GENESIS")
  expect_equal(deviations$previous_hash[2], deviations$deviation_hash[1])
  expect_equal(deviations$previous_hash[3], deviations$deviation_hash[2])

  expect_true(all(nchar(deviations$deviation_hash) == 64))
})
