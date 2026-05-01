library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Test Data Subject Access Request (DSAR) System
# Feature #10: GDPR Article 15 compliant access request management

# Skip all tests if DSAR functions are not available
if (!(exists("init_dsar"))) exit_file("DSAR functions not available")

setup_test_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") {
    Sys.setenv("ZZEDC_OLD_KEY" = old_key)
  }

  test_db <- tempfile(fileext = ".db")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
  if (!init_result$success) {
    stop("Failed to initialize encrypted database: ", init_result$error)
  }

  audit_result <- init_audit_logging(db_path = test_db)
  if (!audit_result$success) {
    stop("Failed to initialize audit logging: ", audit_result$error)
  }

  dsar_result <- init_dsar(db_path = test_db)
  if (!dsar_result$success) {
    stop("Failed to initialize DSAR: ", dsar_result$error)
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

# Test: init_dsar creates required tables
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    conn <- connect_encrypted_db(db_path = test_db)
    tables <- DBI::dbListTables(conn)
    DBI::dbDisconnect(conn)

    expect_true("dsar_requests" %in% tables)
    expect_true("dsar_identity_documents" %in% tables)
    expect_true("dsar_data_sources" %in% tables)
    expect_true("dsar_collected_data" %in% tables)
    expect_true("dsar_responses" %in% tables)
    expect_true("dsar_audit_log" %in% tables)

})

# =============================================================================
# Reference Data Tests
# =============================================================================

# Test: get_dsar_request_types returns all GDPR rights
local({
    types <- get_dsar_request_types()

    expect_true(is.list(types))
    expect_true("ACCESS" %in% names(types))
    expect_true("RECTIFICATION" %in% names(types))
    expect_true("ERASURE" %in% names(types))
    expect_true("RESTRICTION" %in% names(types))
    expect_true("PORTABILITY" %in% names(types))
    expect_true("OBJECTION" %in% names(types))

})

# Test: get_dsar_statuses returns all status values
local({
    statuses <- get_dsar_statuses()

    expect_true(is.list(statuses))
    expect_true("RECEIVED" %in% names(statuses))
    expect_true("IDENTITY_VERIFIED" %in% names(statuses))
    expect_true("IN_PROGRESS" %in% names(statuses))
    expect_true("COMPLETED" %in% names(statuses))
    expect_true("REJECTED" %in% names(statuses))
    expect_true("EXTENDED" %in% names(statuses))

})

# Test: get_data_categories returns all categories
local({
    categories <- get_data_categories()

    expect_true(is.list(categories))
    expect_true("IDENTITY" %in% names(categories))
    expect_true("CONTACT" %in% names(categories))
    expect_true("HEALTH" %in% names(categories))
    expect_true("CONSENT" %in% names(categories))

})

# =============================================================================
# Request Creation Tests
# =============================================================================

# Test: create_dsar_request creates ACCESS request
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "john.doe@example.com",
      subject_name = "John Doe",
      created_by = "dpo",
      subject_phone = "+1-555-1234",
      request_details = "I request a copy of all my personal data",
      db_path = test_db
    )

    expect_true(result$success)
    expect_true(result$request_id > 0)
    expect_true(grepl("^DSAR-ACC-", result$request_number))

    due_date <- as.Date(result$due_date)
    expect_equal(due_date, Sys.Date() + 30)

})

# Test: create_dsar_request creates ERASURE request
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_dsar_request(
      request_type = "ERASURE",
      subject_email = "jane.doe@example.com",
      subject_name = "Jane Doe",
      created_by = "dpo",
      db_path = test_db
    )

    expect_true(result$success)
    expect_true(grepl("^DSAR-ERA-", result$request_number))

})

# Test: create_dsar_request validates request type
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_dsar_request(
      request_type = "INVALID",
      subject_email = "test@example.com",
      subject_name = "Test User",
      created_by = "dpo",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("Invalid request type", result$error))

})

# Test: create_dsar_request validates priority
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "test@example.com",
      subject_name = "Test User",
      created_by = "dpo",
      priority = "INVALID",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("Priority must be", result$error))

})

# Test: create_dsar_request creates hash chain
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    create_dsar_request("ACCESS", "user1@example.com", "User 1", "dpo", db_path = test_db)
    create_dsar_request("ERASURE", "user2@example.com", "User 2", "dpo", db_path = test_db)

    conn <- connect_encrypted_db(db_path = test_db)
    requests <- DBI::dbGetQuery(conn, "
      SELECT request_id, request_hash, previous_hash FROM dsar_requests ORDER BY request_id
    ")
    DBI::dbDisconnect(conn)

    expect_equal(requests$previous_hash[1], "GENESIS")
    expect_equal(requests$previous_hash[2], requests$request_hash[1])

})

# =============================================================================
# Identity Verification Tests
# =============================================================================

# Test: verify_subject_identity verifies identity
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "john@example.com",
      subject_name = "John Smith",
      created_by = "dpo",
      db_path = test_db
    )

    result <- verify_subject_identity(
      request_id = request$request_id,
      verification_method = "DOCUMENT_CHECK",
      verified_by = "dpo",
      document_type = "PASSPORT",
      document_reference = "AB123456",
      verification_notes = "Passport verified against photo ID",
      db_path = test_db
    )

    expect_true(result$success)

    updated <- get_dsar_request(request_id = request$request_id, db_path = test_db)
    expect_equal(updated$identity_verified, 1)
    expect_equal(updated$status, "IDENTITY_VERIFIED")

})

# Test: verify_subject_identity validates method
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- verify_subject_identity(
      request_id = 1,
      verification_method = "INVALID",
      verified_by = "dpo",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("Invalid verification method", result$error))

})

# =============================================================================
# Data Collection Tests
# =============================================================================

# Test: add_dsar_data_source adds source
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    result <- add_dsar_data_source(
      request_id = request$request_id,
      source_name = "Clinical Database",
      source_type = "DATABASE",
      table_name = "subjects",
      db_path = test_db
    )

    expect_true(result$success)
    expect_true(result$source_id > 0)

})

# Test: add_dsar_data_source validates source type
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- add_dsar_data_source(
      request_id = 1,
      source_name = "Test",
      source_type = "INVALID",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("Invalid source type", result$error))

})

# Test: record_data_collection records collection
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    source <- add_dsar_data_source(
      request_id = request$request_id,
      source_name = "Clinical DB",
      source_type = "DATABASE",
      db_path = test_db
    )

    result <- record_data_collection(
      request_id = request$request_id,
      data_category = "HEALTH",
      record_count = 25,
      collected_by = "data_manager",
      source_id = source$source_id,
      data_description = "Clinical visit records",
      data_format = "CSV",
      db_path = test_db
    )

    expect_true(result$success)
    expect_true(result$collection_id > 0)

})

# Test: complete_data_collection updates status
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    result <- complete_data_collection(
      request_id = request$request_id,
      completed_by = "data_manager",
      db_path = test_db
    )

    expect_true(result$success)

    updated <- get_dsar_request(request_id = request$request_id, db_path = test_db)
    expect_equal(updated$status, "DATA_COLLECTED")

})

# =============================================================================
# Response Tests
# =============================================================================

# Test: create_dsar_response creates response
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    result <- create_dsar_response(
      request_id = request$request_id,
      response_type = "FULL_DISCLOSURE",
      response_content = "Please find attached all personal data we hold about you.",
      prepared_by = "dpo",
      delivery_method = "EMAIL",
      attachments = "data_export.zip",
      db_path = test_db
    )

    expect_true(result$success)
    expect_true(result$response_id > 0)

})

# Test: create_dsar_response validates response type
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_dsar_response(
      request_id = 1,
      response_type = "INVALID",
      response_content = "Test",
      prepared_by = "dpo",
      delivery_method = "EMAIL",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("Invalid response type", result$error))

})

# Test: create_dsar_response validates delivery method
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_dsar_response(
      request_id = 1,
      response_type = "FULL_DISCLOSURE",
      response_content = "Test",
      prepared_by = "dpo",
      delivery_method = "INVALID",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("Invalid delivery method", result$error))

})

# Test: complete_dsar_request marks as completed
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    create_dsar_response(
      request_id = request$request_id,
      response_type = "FULL_DISCLOSURE",
      response_content = "Response content",
      prepared_by = "dpo",
      delivery_method = "EMAIL",
      db_path = test_db
    )

    result <- complete_dsar_request(
      request_id = request$request_id,
      completed_by = "dpo",
      response_method = "EMAIL",
      db_path = test_db
    )

    expect_true(result$success)

    updated <- get_dsar_request(request_id = request$request_id, db_path = test_db)
    expect_equal(updated$status, "COMPLETED")
    expect_false(is.na(updated$completed_date))

})

# =============================================================================
# Extension Tests
# =============================================================================

# Test: extend_dsar_deadline extends by allowed days
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    result <- extend_dsar_deadline(
      request_id = request$request_id,
      extension_days = 30,
      extension_reason = "Complex request requiring additional time for data collection",
      extended_by = "dpo",
      db_path = test_db
    )

    expect_true(result$success)
    expected_date <- as.Date(result$original_due_date) + 30
    expect_equal(as.Date(result$extended_due_date), expected_date)

    updated <- get_dsar_request(request_id = request$request_id, db_path = test_db)
    expect_equal(updated$status, "EXTENDED")

})

# Test: extend_dsar_deadline rejects over 60 days
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    result <- extend_dsar_deadline(
      request_id = request$request_id,
      extension_days = 61,
      extension_reason = "Too long extension",
      extended_by = "dpo",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("1 and 60 days", result$error))

})

# Test: extend_dsar_deadline prevents double extension
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    extend_dsar_deadline(
      request_id = request$request_id,
      extension_days = 30,
      extension_reason = "First extension for complex request",
      extended_by = "dpo",
      db_path = test_db
    )

    result <- extend_dsar_deadline(
      request_id = request$request_id,
      extension_days = 30,
      extension_reason = "Second extension attempt",
      extended_by = "dpo",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("already been extended", result$error))

})

# Test: extend_dsar_deadline requires reason
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- extend_dsar_deadline(
      request_id = 1,
      extension_days = 30,
      extension_reason = "Short",
      extended_by = "dpo",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("at least 10 characters", result$error))

})

# =============================================================================
# Rejection Tests
# =============================================================================

# Test: reject_dsar_request rejects with reason
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ERASURE",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    result <- reject_dsar_request(
      request_id = request$request_id,
      rejection_reason = "Request rejected due to legal hold on data for ongoing litigation",
      rejected_by = "dpo",
      db_path = test_db
    )

    expect_true(result$success)

    updated <- get_dsar_request(request_id = request$request_id, db_path = test_db)
    expect_equal(updated$status, "REJECTED")
    expect_false(is.na(updated$rejection_reason))

})

# Test: reject_dsar_request requires reason
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- reject_dsar_request(
      request_id = 1,
      rejection_reason = "Short reason",
      rejected_by = "dpo",
      db_path = test_db
    )

    expect_false(result$success)
    expect_true(grepl("at least 20 characters", result$error))

})

# =============================================================================
# Retrieval Tests
# =============================================================================

# Test: get_dsar_request retrieves by ID
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "john@example.com",
      subject_name = "John Doe",
      created_by = "dpo",
      db_path = test_db
    )

    retrieved <- get_dsar_request(request_id = request$request_id, db_path = test_db)

    expect_equal(nrow(retrieved), 1)
    expect_equal(retrieved$subject_name, "John Doe")
    expect_equal(retrieved$request_type, "ACCESS")

})

# Test: get_dsar_request retrieves by number
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "PORTABILITY",
      subject_email = "jane@example.com",
      subject_name = "Jane Doe",
      created_by = "dpo",
      db_path = test_db
    )

    retrieved <- get_dsar_request(request_number = request$request_number, db_path = test_db)

    expect_equal(nrow(retrieved), 1)
    expect_equal(retrieved$subject_name, "Jane Doe")

})

# Test: get_pending_dsar_requests returns pending
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    create_dsar_request("ACCESS", "user1@example.com", "User 1", "dpo", db_path = test_db)
    create_dsar_request("ERASURE", "user2@example.com", "User 2", "dpo", db_path = test_db)

    request3 <- create_dsar_request("RECTIFICATION", "user3@example.com", "User 3",
                                     "dpo", db_path = test_db)
    complete_dsar_request(request3$request_id, "dpo", "EMAIL", db_path = test_db)

    pending <- get_pending_dsar_requests(db_path = test_db)

    expect_equal(nrow(pending), 2)

})

# Test: get_dsar_audit_log returns audit trail
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    verify_subject_identity(
      request_id = request$request_id,
      verification_method = "EMAIL_CONFIRMATION",
      verified_by = "dpo",
      db_path = test_db
    )

    complete_data_collection(
      request_id = request$request_id,
      completed_by = "data_manager",
      db_path = test_db
    )

    audit_log <- get_dsar_audit_log(request$request_id, db_path = test_db)

    expect_true(nrow(audit_log) >= 3)
    expect_true(any(audit_log$action == "REQUEST_CREATED"))
    expect_true(any(audit_log$action == "IDENTITY_VERIFIED"))
    expect_true(any(audit_log$action == "DATA_COLLECTION_COMPLETE"))

})

# Test: get_dsar_collected_data returns collected data
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    source1 <- add_dsar_data_source(
      request_id = request$request_id,
      source_name = "Clinical DB",
      source_type = "DATABASE",
      db_path = test_db
    )

    source2 <- add_dsar_data_source(
      request_id = request$request_id,
      source_name = "Contact System",
      source_type = "DATABASE",
      db_path = test_db
    )

    record_data_collection(
      request_id = request$request_id,
      data_category = "HEALTH",
      record_count = 10,
      collected_by = "dm",
      source_id = source1$source_id,
      db_path = test_db
    )

    record_data_collection(
      request_id = request$request_id,
      data_category = "CONTACT",
      record_count = 5,
      collected_by = "dm",
      source_id = source2$source_id,
      db_path = test_db
    )

    collected <- get_dsar_collected_data(request$request_id, db_path = test_db)

    expect_equal(nrow(collected), 2)
    expect_true("HEALTH" %in% collected$data_category)
    expect_true("CONTACT" %in% collected$data_category)

})

# =============================================================================
# Statistics Tests
# =============================================================================

# Test: get_dsar_statistics returns comprehensive stats
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    create_dsar_request("ACCESS", "user1@example.com", "User 1", "dpo", db_path = test_db)
    create_dsar_request("ERASURE", "user2@example.com", "User 2", "dpo", db_path = test_db)

    req3 <- create_dsar_request("RECTIFICATION", "user3@example.com", "User 3",
                                 "dpo", db_path = test_db)
    complete_dsar_request(req3$request_id, "dpo", "EMAIL", db_path = test_db)

    stats <- get_dsar_statistics(db_path = test_db)

    expect_true(stats$success)
    expect_equal(stats$overall$total_requests, 3)
    expect_equal(stats$overall$completed, 1)
    expect_equal(stats$overall$pending, 2)
    expect_true(nrow(stats$by_type) > 0)

})

# =============================================================================
# Report Generation Tests
# =============================================================================

# Test: generate_dsar_report creates TXT report
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    create_dsar_request("ACCESS", "user@example.com", "Test User", "dpo", db_path = test_db)

    output_file <- tempfile(fileext = ".txt")
    on.exit(unlink(output_file), add = TRUE)

    result <- generate_dsar_report(
      output_file = output_file,
      format = "txt",
      organization = "Test Org",
      prepared_by = "DPO",
      db_path = test_db
    )

    expect_true(result$success)
    expect_true(file.exists(output_file))

    content <- readLines(output_file)
    expect_true(any(grepl("DSAR COMPLIANCE REPORT", content)))
    expect_true(any(grepl("Test Org", content)))

})

# Test: generate_dsar_report creates JSON report
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    create_dsar_request("ERASURE", "user@example.com", "Test User", "dpo", db_path = test_db)

    output_file <- tempfile(fileext = ".json")
    on.exit(unlink(output_file), add = TRUE)

    result <- generate_dsar_report(
      output_file = output_file,
      format = "json",
      organization = "Test Org",
      db_path = test_db
    )

    expect_true(result$success)
    expect_true(file.exists(output_file))

    json_content <- jsonlite::read_json(output_file)
    expect_equal(json_content$report_type, "DSAR Compliance Report")
    expect_equal(json_content$organization, "Test Org")

})

# =============================================================================
# Integration Tests
# =============================================================================

# Test: full DSAR workflow - access request
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "john.patient@example.com",
      subject_name = "John Patient",
      created_by = "dpo",
      subject_phone = "+1-555-1234",
      request_details = "I request a complete copy of all personal data you hold about me",
      data_categories = c("HEALTH", "CONTACT", "CONSENT"),
      priority = "NORMAL",
      db_path = test_db
    )

    expect_true(request$success)

    verify_subject_identity(
      request_id = request$request_id,
      verification_method = "DOCUMENT_CHECK",
      verified_by = "dpo",
      document_type = "DRIVERS_LICENSE",
      document_reference = "DL12345",
      db_path = test_db
    )

    source1 <- add_dsar_data_source(
      request_id = request$request_id,
      source_name = "Clinical Database",
      source_type = "DATABASE",
      table_name = "subjects",
      db_path = test_db
    )

    source2 <- add_dsar_data_source(
      request_id = request$request_id,
      source_name = "Consent System",
      source_type = "DATABASE",
      table_name = "consents",
      db_path = test_db
    )

    record_data_collection(
      request_id = request$request_id,
      data_category = "HEALTH",
      record_count = 50,
      collected_by = "data_manager",
      source_id = source1$source_id,
      data_description = "Clinical visit records and lab results",
      data_format = "CSV",
      db_path = test_db
    )

    record_data_collection(
      request_id = request$request_id,
      data_category = "CONTACT",
      record_count = 1,
      collected_by = "data_manager",
      source_id = source1$source_id,
      data_description = "Contact information",
      data_format = "CSV",
      db_path = test_db
    )

    record_data_collection(
      request_id = request$request_id,
      data_category = "CONSENT",
      record_count = 3,
      collected_by = "data_manager",
      source_id = source2$source_id,
      data_description = "Consent records",
      data_format = "CSV",
      db_path = test_db
    )

    complete_data_collection(
      request_id = request$request_id,
      completed_by = "data_manager",
      db_path = test_db
    )

    create_dsar_response(
      request_id = request$request_id,
      response_type = "FULL_DISCLOSURE",
      response_content = "Dear Mr. Patient, please find attached a complete copy of all personal data we hold about you.",
      prepared_by = "dpo",
      delivery_method = "SECURE_PORTAL",
      attachments = "data_export_john_patient.zip",
      db_path = test_db
    )

    complete_dsar_request(
      request_id = request$request_id,
      completed_by = "dpo",
      response_method = "SECURE_PORTAL",
      db_path = test_db
    )

    final_request <- get_dsar_request(request_id = request$request_id, db_path = test_db)
    expect_equal(final_request$status, "COMPLETED")
    expect_equal(final_request$identity_verified, 1)

    audit_log <- get_dsar_audit_log(request$request_id, db_path = test_db)
    expect_true(nrow(audit_log) >= 5)

    collected <- get_dsar_collected_data(request$request_id, db_path = test_db)
    expect_equal(nrow(collected), 3)
    expect_equal(sum(collected$record_count), 54)

    stats <- get_dsar_statistics(db_path = test_db)
    expect_equal(stats$overall$completed, 1)

})

# Test: DSAR workflow with extension
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "PORTABILITY",
      subject_email = "user@example.com",
      subject_name = "Complex User",
      created_by = "dpo",
      request_details = "Export all data in machine-readable format",
      db_path = test_db
    )

    original_due <- as.Date(request$due_date)

    extend_dsar_deadline(
      request_id = request$request_id,
      extension_days = 45,
      extension_reason = "Complex request requiring data from multiple legacy systems",
      extended_by = "dpo",
      db_path = test_db
    )

    updated <- get_dsar_request(request_id = request$request_id, db_path = test_db)
    expect_equal(updated$status, "EXTENDED")
    expect_equal(as.Date(updated$extended_due_date), original_due + 45)

})

# Test: audit log maintains hash chain integrity
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_dsar_request(
      request_type = "ACCESS",
      subject_email = "user@example.com",
      subject_name = "User",
      created_by = "dpo",
      db_path = test_db
    )

    verify_subject_identity(request$request_id, "EMAIL_CONFIRMATION", "dpo", db_path = test_db)
    complete_data_collection(request$request_id, "dm", db_path = test_db)

    conn <- connect_encrypted_db(db_path = test_db)
    audit <- DBI::dbGetQuery(conn, "
      SELECT log_id, log_hash, previous_log_hash
      FROM dsar_audit_log
      WHERE request_id = ?
      ORDER BY log_id
    ", list(request$request_id))
    DBI::dbDisconnect(conn)

    expect_equal(audit$previous_log_hash[1], "GENESIS")
    expect_equal(audit$previous_log_hash[2], audit$log_hash[1])
    expect_equal(audit$previous_log_hash[3], audit$log_hash[2])

})