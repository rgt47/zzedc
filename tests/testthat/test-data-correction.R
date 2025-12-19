# Test suite for Data Correction Workflow
# FDA 21 CFR Part 11 compliant data correction system

library(testthat)
library(DBI)
library(RSQLite)

find_pkg_root <- function() {
  candidates <- c(
    getwd(),
    file.path(getwd(), "..", ".."),
    Sys.getenv("ZZEDC_PKG_ROOT", unset = NA)
  )
  for (path in candidates) {
    if (!is.na(path) && file.exists(file.path(path, "R", "data_correction.R"))) {
      return(normalizePath(path))
    }
  }
  stop("Could not find package root directory")
}

pkg_root <- find_pkg_root()
source(file.path(pkg_root, "R", "encryption_utils.R"))
source(file.path(pkg_root, "R", "db_connection.R"))
source(file.path(pkg_root, "R", "audit_logging.R"))
source(file.path(pkg_root, "R", "version_control.R"))
source(file.path(pkg_root, "R", "data_correction.R"))

# =============================================================================
# Test Setup
# =============================================================================

setup_test_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") {
    Sys.setenv("ZZEDC_OLD_KEY" = old_key)
  }

  test_db <- tempfile(fileext = ".db")
  init_result <- initialize_encrypted_database(db_path = test_db,
                                                overwrite = TRUE)
  if (!init_result$success) {
    stop("Failed to initialize database: ", init_result$error)
  }

  audit_result <- init_audit_logging(db_path = test_db)
  version_result <- init_version_control(db_path = test_db)
  correction_result <- init_data_correction(db_path = test_db)

  conn <- connect_encrypted_db(db_path = test_db)
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS test_data (
      id INTEGER PRIMARY KEY,
      subject_id TEXT,
      age INTEGER,
      weight REAL,
      status TEXT
    )
  ")
  DBI::dbExecute(conn, "
    INSERT INTO test_data (subject_id, age, weight, status)
    VALUES ('S001', 45, 70.5, 'enrolled'),
           ('S002', 32, 65.0, 'enrolled'),
           ('S003', 58, 82.3, 'completed')
  ")
  DBI::dbDisconnect(conn)

  test_db
}

cleanup_test_db <- function(test_db) {
  if (file.exists(test_db)) {
    unlink(test_db)
  }
  old_key <- Sys.getenv("ZZEDC_OLD_KEY")
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    Sys.unsetenv("ZZEDC_OLD_KEY")
  }
}

# =============================================================================
# Initialization Tests
# =============================================================================

test_that("init_data_correction creates required tables", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  conn <- connect_encrypted_db(db_path = test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tables <- DBI::dbListTables(conn)
  expect_true("correction_requests" %in% tables)
  expect_true("correction_approvers" %in% tables)
  expect_true("correction_history" %in% tables)
  expect_true("correction_overrides" %in% tables)
})

test_that("get_correction_reasons returns valid reasons", {
  reasons <- get_correction_reasons()

  expect_type(reasons, "list")
  expect_true(length(reasons) >= 9)
  expect_true("TYPO" %in% names(reasons))
  expect_true("SOURCE_DOC_ERROR" %in% names(reasons))
  expect_true("CALCULATION_ERROR" %in% names(reasons))
  expect_true("OTHER" %in% names(reasons))
})

# =============================================================================
# Correction Request Tests
# =============================================================================

test_that("create_correction_request creates valid request", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    reason_details = "Incorrect transcription from source",
    requested_by = "coordinator1",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(!is.null(result$request_id))
  expect_equal(result$status, "PENDING")
  expect_true(nchar(result$request_hash) == 64)
})

test_that("create_correction_request requires reason details for OTHER", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "OTHER",
    reason_details = "short",
    requested_by = "coordinator1",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Reason details required", result$error))
})

test_that("create_correction_request rejects invalid reason", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "INVALID_REASON",
    requested_by = "coordinator1",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid correction reason", result$error))
})

test_that("get_correction_request retrieves request with history", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "weight",
    original_value = "70.5",
    corrected_value = "71.0",
    correction_reason = "TRANSCRIPTION_ERROR",
    requested_by = "coordinator1",
    db_path = test_db
  )

  result <- get_correction_request(create_result$request_id, db_path = test_db)

  expect_true(result$success)
  expect_equal(nrow(result$request), 1)
  expect_equal(result$request$field_name, "weight")
  expect_true(nrow(result$history) >= 1)
  expect_equal(result$history$action[1], "CREATED")
})

test_that("get_pending_corrections returns pending requests", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  for (i in 1:3) {
    create_correction_request(
      table_name = "test_data",
      record_id = paste0("S00", i),
      field_name = "status",
      original_value = "enrolled",
      corrected_value = "completed",
      correction_reason = "QUERY_RESPONSE",
      requested_by = "coordinator1",
      db_path = test_db
    )
  }

  pending <- get_pending_corrections(db_path = test_db)

  expect_equal(nrow(pending), 3)
  expect_true(all(pending$status == "PENDING"))
})

# =============================================================================
# Approval Workflow Tests
# =============================================================================

test_that("approve_correction approves pending request", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  result <- approve_correction(
    request_id = create_result$request_id,
    reviewed_by = "data_manager",
    review_comments = "Verified against source document",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$status, "APPROVED")

  req <- get_correction_request(create_result$request_id, db_path = test_db)
  expect_equal(req$request$status, "APPROVED")
  expect_equal(req$request$reviewed_by, "data_manager")
})

test_that("approve_correction prevents self-approval", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  result <- approve_correction(
    request_id = create_result$request_id,
    reviewed_by = "coordinator1",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Cannot approve own", result$error))
})

test_that("reject_correction requires reason", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  result <- reject_correction(
    request_id = create_result$request_id,
    reviewed_by = "data_manager",
    review_comments = "short",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Rejection reason required", result$error))
})

test_that("reject_correction rejects with valid reason", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  result <- reject_correction(
    request_id = create_result$request_id,
    reviewed_by = "data_manager",
    review_comments = "Source document shows original value is correct",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$status, "REJECTED")
})

# =============================================================================
# Apply Correction Tests
# =============================================================================

test_that("apply_correction only works on approved requests", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  result <- apply_correction(
    request_id = create_result$request_id,
    applied_by = "data_manager",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("only apply approved", result$error))
})

test_that("apply_correction works after approval", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "1",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  approve_correction(
    request_id = create_result$request_id,
    reviewed_by = "data_manager",
    db_path = test_db
  )

  result <- apply_correction(
    request_id = create_result$request_id,
    applied_by = "data_manager",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$status, "APPLIED")
  expect_equal(result$old_value, "45")
  expect_equal(result$new_value, "46")
})

# =============================================================================
# Override Tests
# =============================================================================

test_that("request_correction_override creates override request", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  result <- request_correction_override(
    request_id = create_result$request_id,
    override_type = "LOCKED_RECORD",
    override_reason = "Critical safety data requires immediate correction despite lock",
    override_by = "coordinator1",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(!is.null(result$override_id))
  expect_equal(result$status, "PENDING_APPROVAL")
})

test_that("request_correction_override requires justification", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  result <- request_correction_override(
    request_id = create_result$request_id,
    override_type = "LOCKED_RECORD",
    override_reason = "short",
    override_by = "coordinator1",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("min 20 characters", result$error))
})

test_that("approve_override works correctly", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  override_result <- request_correction_override(
    request_id = create_result$request_id,
    override_type = "LOCKED_RECORD",
    override_reason = "Critical safety data requires immediate correction",
    override_by = "coordinator1",
    db_path = test_db
  )

  result <- approve_override(
    override_id = override_result$override_id,
    approved_by = "admin",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$request_id, create_result$request_id)
})

test_that("approve_override prevents self-approval", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  override_result <- request_correction_override(
    request_id = create_result$request_id,
    override_type = "LOCKED_RECORD",
    override_reason = "Critical safety data requires immediate correction",
    override_by = "coordinator1",
    db_path = test_db
  )

  result <- approve_override(
    override_id = override_result$override_id,
    approved_by = "coordinator1",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Cannot approve own", result$error))
})

# =============================================================================
# Statistics and Reporting Tests
# =============================================================================

test_that("get_correction_statistics returns correct counts", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  for (i in 1:5) {
    create_correction_request(
      table_name = "test_data",
      record_id = paste0("S00", i),
      field_name = "status",
      original_value = "enrolled",
      corrected_value = "completed",
      correction_reason = "QUERY_RESPONSE",
      requested_by = "coordinator1",
      site_id = "SITE01",
      db_path = test_db
    )
  }

  approve_correction(request_id = 1, reviewed_by = "dm", db_path = test_db)
  approve_correction(request_id = 2, reviewed_by = "dm", db_path = test_db)
  reject_correction(
    request_id = 3,
    reviewed_by = "dm",
    review_comments = "Original value is correct per source",
    db_path = test_db
  )

  stats <- get_correction_statistics(db_path = test_db)

  expect_true(stats$success)
  expect_equal(stats$summary$total_requests, 5)
  expect_equal(stats$summary$pending, 2)
  expect_equal(stats$summary$approved, 2)
  expect_equal(stats$summary$rejected, 1)
})

test_that("generate_correction_report creates text report", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  for (i in 1:3) {
    create_correction_request(
      table_name = "test_data",
      record_id = paste0("S00", i),
      field_name = "age",
      original_value = as.character(40 + i),
      corrected_value = as.character(41 + i),
      correction_reason = "TYPO",
      requested_by = "coordinator1",
      db_path = test_db
    )
  }

  report_file <- tempfile(fileext = ".txt")
  on.exit(unlink(report_file), add = TRUE)

  result <- generate_correction_report(
    output_file = report_file,
    format = "txt",
    organization = "Test Organization",
    prepared_by = "Test User",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(report_file))
  expect_equal(result$corrections_count, 3)

  content <- readLines(report_file)
  expect_true(any(grepl("DATA CORRECTION REPORT", content)))
  expect_true(any(grepl("Test Organization", content)))
})

test_that("generate_correction_report creates JSON report", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_correction_request(
    table_name = "test_data",
    record_id = "S001",
    field_name = "age",
    original_value = "45",
    corrected_value = "46",
    correction_reason = "TYPO",
    requested_by = "coordinator1",
    db_path = test_db
  )

  report_file <- tempfile(fileext = ".json")
  on.exit(unlink(report_file), add = TRUE)

  result <- generate_correction_report(
    output_file = report_file,
    format = "json",
    organization = "Test Organization",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(report_file))

  json_content <- jsonlite::read_json(report_file)
  expect_equal(json_content$organization, "Test Organization")
  expect_equal(json_content$report_type, "Data Correction Report")
})

# =============================================================================
# Integrity Verification Tests
# =============================================================================

test_that("verify_correction_integrity detects valid chain", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  for (i in 1:5) {
    create_correction_request(
      table_name = "test_data",
      record_id = paste0("S00", i),
      field_name = "status",
      original_value = "enrolled",
      corrected_value = "completed",
      correction_reason = "QUERY_RESPONSE",
      requested_by = "coordinator1",
      db_path = test_db
    )
  }

  result <- verify_correction_integrity(db_path = test_db)

  expect_true(result$success)
  expect_true(result$is_valid)
  expect_equal(result$total_records, 5)
  expect_equal(length(result$invalid_records), 0)
})

# =============================================================================
# Integration Tests
# =============================================================================

test_that("complete correction workflow works end-to-end", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_result <- create_correction_request(
    table_name = "test_data",
    record_id = "1",
    field_name = "weight",
    original_value = "70.5",
    corrected_value = "75.5",
    correction_reason = "TRANSCRIPTION_ERROR",
    reason_details = "Source document shows 75.5 kg, not 70.5 kg",
    requested_by = "coordinator1",
    original_source_doc = "CRF Page 3",
    site_id = "SITE01",
    study_id = "STUDY001",
    subject_id = "S001",
    db_path = test_db
  )
  expect_true(create_result$success)
  expect_equal(create_result$status, "PENDING")

  pending <- get_pending_corrections(db_path = test_db)
  expect_equal(nrow(pending), 1)

  approve_result <- approve_correction(
    request_id = create_result$request_id,
    reviewed_by = "data_manager",
    review_comments = "Verified - source shows 75.5 kg",
    db_path = test_db
  )
  expect_true(approve_result$success)
  expect_equal(approve_result$status, "APPROVED")

  apply_result <- apply_correction(
    request_id = create_result$request_id,
    applied_by = "data_manager",
    db_path = test_db
  )
  expect_true(apply_result$success)
  expect_equal(apply_result$status, "APPLIED")

  final_request <- get_correction_request(create_result$request_id, db_path = test_db)
  expect_equal(final_request$request$status, "APPLIED")
  expect_true(nrow(final_request$history) >= 3)

  history_actions <- final_request$history$action
  expect_true("CREATED" %in% history_actions)
  expect_true("APPROVED" %in% history_actions)
  expect_true("APPLIED" %in% history_actions)

  integrity <- verify_correction_integrity(db_path = test_db)
  expect_true(integrity$is_valid)
})
