library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# test-consent.R
# Test suite for GDPR Article 7 Consent Management System

# ============================================================================
# TEST SETUP
# ============================================================================

setup_test_db <- function() {
  test_dir <- tempdir()
  test_db <- file.path(test_dir, paste0("test_consent_", Sys.getpid(), ".db"))

  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_12345678901234567890123")
  Sys.setenv(ZZEDC_DB_PATH = test_db)

  init_result <- initialize_encrypted_database(db_path = test_db)
  Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
  if (!isTRUE(init_result$success)) {
    stop("Failed to initialize database: ", init_result$error)
  }

  audit_result <- init_audit_logging()
  if (!isTRUE(audit_result$success)) {
    stop("Failed to initialize audit logging: ", audit_result$error)
  }

  consent_result <- init_consent()
  if (!isTRUE(consent_result$success)) {
    stop("Failed to initialize consent: ", consent_result$error)
  }

  test_db
}

cleanup_test_db <- function(test_db) {
  if (file.exists(test_db)) try(file.remove(test_db), silent = TRUE)
  Sys.unsetenv("ZZEDC_ENCRYPTION_KEY")
  Sys.unsetenv("ZZEDC_DB_PATH")
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

# Test: init_consent creates all required tables
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    tables <- DBI::dbListTables(con)
    expect_true("consent_purposes" %in% tables)
    expect_true("consent_records" %in% tables)
    expect_true("consent_history" %in% tables)
    expect_true("consent_withdrawal_requests" %in% tables)
    expect_true("consent_preferences" %in% tables)

})
# ============================================================================
# REFERENCE DATA TESTS
# ============================================================================

# Test: get_consent_methods returns valid methods
local({
    methods <- get_consent_methods()
    expect_equal(typeof(methods), "character")
    expect_true("CHECKBOX" %in% names(methods))
    expect_true("SIGNATURE" %in% names(methods))
    expect_true("DOUBLE_OPT_IN" %in% names(methods))

})
# Test: get_consent_legal_bases returns valid bases
local({
    bases <- get_consent_legal_bases()
    expect_equal(typeof(bases), "character")
    expect_true("CONSENT" %in% names(bases))
    expect_true("EXPLICIT_CONSENT" %in% names(bases))

})
# Test: get_withdrawal_scopes returns valid scopes
local({
    scopes <- get_withdrawal_scopes()
    expect_equal(typeof(scopes), "character")
    expect_true("ALL" %in% names(scopes))
    expect_true("SPECIFIC" %in% names(scopes))

})
# Test: get_consent_statuses returns valid statuses
local({
    statuses <- get_consent_statuses()
    expect_equal(typeof(statuses), "character")
    expect_true("PENDING" %in% names(statuses))
    expect_true("GIVEN" %in% names(statuses))
    expect_true("WITHDRAWN" %in% names(statuses))

})
# ============================================================================
# PURPOSE MANAGEMENT TESTS
# ============================================================================

# Test: create_consent_purpose creates purpose
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_consent_purpose(
      purpose_code = "MARKETING",
      purpose_name = "Marketing Communications",
      purpose_description = "We will use your data to send you marketing communications about our products and services.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    expect_true(result$success)
    expect_true(!is.null(result$purpose_id))
    expect_equal(result$purpose_code, "MARKETING")

})
# Test: create_consent_purpose validates purpose_code required
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_consent_purpose(
      purpose_code = "",
      purpose_name = "Test",
      purpose_description = "This is a test description that is long enough.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    expect_false(result$success)
    expect_true(grepl("purpose_code", result$error))

})
# Test: create_consent_purpose validates description length
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_consent_purpose(
      purpose_code = "TEST",
      purpose_name = "Test Purpose",
      purpose_description = "Too short",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    expect_false(result$success)
    expect_true(grepl("20 characters", result$error))

})
# Test: create_consent_purpose validates legal basis
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_consent_purpose(
      purpose_code = "TEST",
      purpose_name = "Test Purpose",
      purpose_description = "This is a test description that is long enough.",
      legal_basis = "INVALID",
      created_by = "admin"
    )

    expect_false(result$success)
    expect_true(grepl("Invalid legal_basis", result$error))

})
# Test: create_consent_purpose prevents duplicate codes
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    create_consent_purpose(
      purpose_code = "UNIQUE",
      purpose_name = "First Purpose",
      purpose_description = "This is a test description that is long enough.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    result <- create_consent_purpose(
      purpose_code = "UNIQUE",
      purpose_name = "Second Purpose",
      purpose_description = "This is another test description that is long enough.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    expect_false(result$success)
    expect_true(grepl("already exists", result$error))

})
# Test: get_consent_purposes retrieves purposes
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    create_consent_purpose(
      purpose_code = "PURPOSE1",
      purpose_name = "Purpose One",
      purpose_description = "This is purpose one with a long description.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    result <- get_consent_purposes()

    expect_true(result$success)
    expect_true(result$count >= 1)
    expect_true("PURPOSE1" %in% result$purposes$purpose_code)

})
# Test: deactivate_consent_purpose deactivates
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "TODEACTIVATE",
      purpose_name = "To Deactivate",
      purpose_description = "This purpose will be deactivated for testing.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    result <- deactivate_consent_purpose(
      purpose_id = purpose$purpose_id,
      deactivated_by = "admin"
    )

    expect_true(result$success)

    active <- get_consent_purposes(include_inactive = FALSE)
    expect_false("TODEACTIVATE" %in% active$purposes$purpose_code)

})
# ============================================================================
# CONSENT RECORDING TESTS
# ============================================================================

# Test: record_consent creates consent record
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "RESEARCH",
      purpose_name = "Research Participation",
      purpose_description = "We will use your data for research purposes.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    result <- record_consent(
      subject_id = "SUBJ-001",
      subject_email = "subject@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    expect_true(result$success)
    expect_true(!is.null(result$consent_id))
    expect_true(grepl("^CONS-", result$consent_code))

})
# Test: record_consent validates required fields
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- record_consent(
      subject_id = "",
      subject_email = "test@example.com",
      purpose_id = 1,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    expect_false(result$success)
    expect_true(grepl("subject_id", result$error))

})
# Test: record_consent validates consent method
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "TEST",
      purpose_name = "Test Purpose",
      purpose_description = "This is a test description that is long enough.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    result <- record_consent(
      subject_id = "SUBJ-001",
      subject_email = "test@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "INVALID",
      recorded_by = "system"
    )

    expect_false(result$success)
    expect_true(grepl("Invalid consent_method", result$error))

})
# Test: record_consent requires active purpose
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "INACTIVE",
      purpose_name = "Inactive Purpose",
      purpose_description = "This purpose will be deactivated for testing.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    deactivate_consent_purpose(purpose$purpose_id, "admin")

    result <- record_consent(
      subject_id = "SUBJ-001",
      subject_email = "test@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    expect_false(result$success)
    expect_true(grepl("not active", result$error))

})
# Test: record_consent creates audit history
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "AUDIT",
      purpose_name = "Audit Test",
      purpose_description = "This is for testing audit trail creation.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    consent <- record_consent(
      subject_id = "SUBJ-002",
      subject_email = "audit@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "SIGNATURE",
      recorded_by = "admin"
    )

    history <- get_consent_history(consent$consent_id)

    expect_true(history$success)
    expect_true(history$count >= 1)
    expect_true("CONSENT_GIVEN" %in% history$history$action)

})
# ============================================================================
# CONSENT WITHDRAWAL TESTS
# ============================================================================

# Test: withdraw_consent withdraws consent
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "WITHDRAW",
      purpose_name = "Withdrawal Test",
      purpose_description = "This is for testing consent withdrawal.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    consent <- record_consent(
      subject_id = "SUBJ-003",
      subject_email = "withdraw@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    result <- withdraw_consent(
      consent_id = consent$consent_id,
      withdrawn_by = "subject",
      withdrawn_reason = "No longer interested"
    )

    expect_true(result$success)
    expect_true(!is.null(result$withdrawn_date))

})
# Test: withdraw_consent prevents double withdrawal
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "DOUBLE",
      purpose_name = "Double Withdrawal Test",
      purpose_description = "This is for testing double withdrawal prevention.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    consent <- record_consent(
      subject_id = "SUBJ-004",
      subject_email = "double@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    withdraw_consent(consent$consent_id, "subject")

    result <- withdraw_consent(consent$consent_id, "subject")

    expect_false(result$success)
    expect_true(grepl("already withdrawn", result$error))

})
# Test: withdraw_all_consents withdraws all subject consents
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose1 <- create_consent_purpose(
      purpose_code = "ALL1",
      purpose_name = "Purpose One",
      purpose_description = "First purpose for bulk withdrawal test.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    purpose2 <- create_consent_purpose(
      purpose_code = "ALL2",
      purpose_name = "Purpose Two",
      purpose_description = "Second purpose for bulk withdrawal test.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    record_consent(
      subject_id = "SUBJ-BULK",
      subject_email = "bulk@example.com",
      purpose_id = purpose1$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    record_consent(
      subject_id = "SUBJ-BULK",
      subject_email = "bulk@example.com",
      purpose_id = purpose2$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    result <- withdraw_all_consents(
      subject_id = "SUBJ-BULK",
      withdrawn_by = "subject"
    )

    expect_true(result$success)
    expect_equal(result$withdrawn_count, 2)

})
# Test: withdraw_all_consents returns 0 if no active consents
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- withdraw_all_consents(
      subject_id = "NONEXISTENT",
      withdrawn_by = "subject"
    )

    expect_true(result$success)
    expect_equal(result$withdrawn_count, 0)

})
# ============================================================================
# WITHDRAWAL REQUEST TESTS
# ============================================================================

# Test: create_withdrawal_request creates request
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_withdrawal_request(
      subject_id = "SUBJ-REQ",
      subject_email = "request@example.com",
      withdrawal_scope = "ALL",
      requested_by = "dpo"
    )

    expect_true(result$success)
    expect_true(!is.null(result$request_id))
    expect_true(grepl("^WDRL-", result$request_number))
    expect_equal(result$status, "RECEIVED")

})
# Test: create_withdrawal_request validates scope
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_withdrawal_request(
      subject_id = "SUBJ-REQ",
      subject_email = "request@example.com",
      withdrawal_scope = "INVALID",
      requested_by = "dpo"
    )

    expect_false(result$success)
    expect_true(grepl("Invalid withdrawal_scope", result$error))

})
# Test: create_withdrawal_request requires purpose_ids for SPECIFIC scope
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- create_withdrawal_request(
      subject_id = "SUBJ-REQ",
      subject_email = "request@example.com",
      withdrawal_scope = "SPECIFIC",
      requested_by = "dpo"
    )

    expect_false(result$success)
    expect_true(grepl("purpose_ids required", result$error))

})
# Test: process_withdrawal_request processes ALL scope
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "PROCESS",
      purpose_name = "Process Test",
      purpose_description = "This is for testing withdrawal request processing.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    record_consent(
      subject_id = "SUBJ-PROC",
      subject_email = "proc@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    request <- create_withdrawal_request(
      subject_id = "SUBJ-PROC",
      subject_email = "proc@example.com",
      withdrawal_scope = "ALL",
      requested_by = "dpo"
    )

    result <- process_withdrawal_request(
      request_id = request$request_id,
      processed_by = "admin"
    )

    expect_true(result$success)
    expect_equal(result$status, "COMPLETED")
    expect_equal(result$withdrawn_count, 1)

})
# Test: process_withdrawal_request prevents double processing
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    request <- create_withdrawal_request(
      subject_id = "SUBJ-DBL",
      subject_email = "dbl@example.com",
      withdrawal_scope = "ALL",
      requested_by = "dpo"
    )

    process_withdrawal_request(request$request_id, "admin")

    result <- process_withdrawal_request(request$request_id, "admin")

    expect_false(result$success)
    expect_true(grepl("already processed", result$error))

})
# Test: get_pending_withdrawal_requests returns pending
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    create_withdrawal_request(
      subject_id = "SUBJ-PND",
      subject_email = "pending@example.com",
      withdrawal_scope = "ALL",
      requested_by = "dpo"
    )

    result <- get_pending_withdrawal_requests()

    expect_true(result$success)
    expect_true(result$count >= 1)
    expect_true("SUBJ-PND" %in% result$requests$subject_id)

})
# ============================================================================
# CONSENT CHECKING TESTS
# ============================================================================

# Test: check_consent returns true for active consent
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "CHECK",
      purpose_name = "Check Test",
      purpose_description = "This is for testing consent checking.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    record_consent(
      subject_id = "SUBJ-CHK",
      subject_email = "check@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    result <- check_consent(
      subject_id = "SUBJ-CHK",
      purpose_id = purpose$purpose_id
    )

    expect_true(result$success)
    expect_true(result$has_consent)

})
# Test: check_consent returns false for no consent
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    result <- check_consent(
      subject_id = "NONEXISTENT",
      purpose_id = 999
    )

    expect_true(result$success)
    expect_false(result$has_consent)
    expect_equal(result$reason, "No consent record found")

})
# Test: check_consent returns false for withdrawn consent
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "WITHCHECK",
      purpose_name = "Withdrawn Check Test",
      purpose_description = "This is for testing withdrawn consent checking.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    consent <- record_consent(
      subject_id = "SUBJ-WC",
      subject_email = "wc@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    withdraw_consent(consent$consent_id, "subject")

    result <- check_consent(
      subject_id = "SUBJ-WC",
      purpose_id = purpose$purpose_id
    )

    expect_true(result$success)
    expect_false(result$has_consent)

})
# Test: get_subject_consents retrieves all consents
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "GETALL",
      purpose_name = "Get All Test",
      purpose_description = "This is for testing get subject consents.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    record_consent(
      subject_id = "SUBJ-GA",
      subject_email = "ga@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    result <- get_subject_consents(subject_id = "SUBJ-GA")

    expect_true(result$success)
    expect_true(result$count >= 1)

})
# ============================================================================
# CONSENT REFRESH TESTS
# ============================================================================

# Test: refresh_consent refreshes existing consent
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "REFRESH",
      purpose_name = "Refresh Test",
      purpose_description = "This is for testing consent refresh.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    consent <- record_consent(
      subject_id = "SUBJ-REF",
      subject_email = "refresh@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    result <- refresh_consent(
      consent_id = consent$consent_id,
      consent_method = "DOUBLE_OPT_IN",
      refreshed_by = "system",
      new_version = "2.0"
    )

    expect_true(result$success)
    expect_true(!is.null(result$refreshed_at))

})
# Test: refresh_consent creates audit history
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "REFAUDIT",
      purpose_name = "Refresh Audit Test",
      purpose_description = "This is for testing refresh audit history.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    consent <- record_consent(
      subject_id = "SUBJ-RA",
      subject_email = "ra@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    refresh_consent(
      consent_id = consent$consent_id,
      consent_method = "SIGNATURE",
      refreshed_by = "admin"
    )

    history <- get_consent_history(consent$consent_id)

    expect_true(history$success)
    expect_true("CONSENT_REFRESHED" %in% history$history$action)

})
# ============================================================================
# STATISTICS TESTS
# ============================================================================

# Test: get_consent_statistics returns stats
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "STATS",
      purpose_name = "Stats Test",
      purpose_description = "This is for testing consent statistics.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    record_consent(
      subject_id = "SUBJ-ST",
      subject_email = "stats@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    result <- get_consent_statistics()

    expect_true(result$success)
    expect_true(!is.null(result$consents))
    expect_true(!is.null(result$purposes))
    expect_true(!is.null(result$withdrawals))

})
# ============================================================================
# REPORT GENERATION TESTS
# ============================================================================

# Test: generate_consent_report creates TXT report
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    output_file <- tempfile(fileext = ".txt")
    on.exit(unlink(output_file), add = TRUE)

    result <- generate_consent_report(
      output_file = output_file,
      format = "txt",
      organization = "Test Organization",
      prepared_by = "Test DPO"
    )

    expect_true(result$success)
    expect_true(file.exists(output_file))

    content <- readLines(output_file)
    expect_true(any(grepl("GDPR ARTICLE 7", content)))
    expect_true(any(grepl("Test Organization", content)))

})
# Test: generate_consent_report creates JSON report
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    output_file <- tempfile(fileext = ".json")
    on.exit(unlink(output_file), add = TRUE)

    result <- generate_consent_report(
      output_file = output_file,
      format = "json",
      organization = "Test Organization",
      prepared_by = "Test DPO"
    )

    expect_true(result$success)
    expect_true(file.exists(output_file))

    content <- jsonlite::fromJSON(output_file)
    expect_equal(content$organization, "Test Organization")

})
# ============================================================================
# INTEGRATION TESTS
# ============================================================================

# Test: full consent lifecycle completes
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "LIFECYCLE",
      purpose_name = "Lifecycle Test",
      purpose_description = "This is for testing the complete consent lifecycle.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )
    expect_true(purpose$success)

    consent <- record_consent(
      subject_id = "SUBJ-LC",
      subject_email = "lifecycle@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system",
      consent_version = "1.0"
    )
    expect_true(consent$success)

    check1 <- check_consent("SUBJ-LC", purpose$purpose_id)
    expect_true(check1$has_consent)

    refresh <- refresh_consent(
      consent_id = consent$consent_id,
      consent_method = "DOUBLE_OPT_IN",
      refreshed_by = "system",
      new_version = "2.0"
    )
    expect_true(refresh$success)

    check2 <- check_consent("SUBJ-LC", purpose$purpose_id)
    expect_true(check2$has_consent)

    withdrawal <- withdraw_consent(
      consent_id = consent$consent_id,
      withdrawn_by = "subject",
      withdrawn_reason = "Testing complete lifecycle"
    )
    expect_true(withdrawal$success)

    check3 <- check_consent("SUBJ-LC", purpose$purpose_id)
    expect_false(check3$has_consent)

    history <- get_consent_history(consent$consent_id)
    expect_true(history$success)
    expect_true(history$count >= 3)
    expect_true("CONSENT_GIVEN" %in% history$history$action)
    expect_true("CONSENT_REFRESHED" %in% history$history$action)
    expect_true("CONSENT_WITHDRAWN" %in% history$history$action)

})
# Test: full withdrawal request workflow completes
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose1 <- create_consent_purpose(
      purpose_code = "WRK1",
      purpose_name = "Workflow Purpose 1",
      purpose_description = "First purpose for workflow testing.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    purpose2 <- create_consent_purpose(
      purpose_code = "WRK2",
      purpose_name = "Workflow Purpose 2",
      purpose_description = "Second purpose for workflow testing.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    record_consent(
      subject_id = "SUBJ-WRK",
      subject_email = "workflow@example.com",
      purpose_id = purpose1$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    record_consent(
      subject_id = "SUBJ-WRK",
      subject_email = "workflow@example.com",
      purpose_id = purpose2$purpose_id,
      consent_method = "SIGNATURE",
      recorded_by = "system"
    )

    consents_before <- get_subject_consents("SUBJ-WRK")
    expect_equal(consents_before$count, 2)

    request <- create_withdrawal_request(
      subject_id = "SUBJ-WRK",
      subject_email = "workflow@example.com",
      withdrawal_scope = "ALL",
      requested_by = "dpo",
      withdrawal_reason = "Subject requested full withdrawal"
    )
    expect_true(request$success)

    pending <- get_pending_withdrawal_requests()
    expect_true("SUBJ-WRK" %in% pending$requests$subject_id)

    process <- process_withdrawal_request(
      request_id = request$request_id,
      processed_by = "admin"
    )
    expect_true(process$success)
    expect_equal(process$withdrawn_count, 2)

    consents_after <- get_subject_consents("SUBJ-WRK")
    expect_equal(consents_after$count, 0)

    pending_after <- get_pending_withdrawal_requests()
    expect_false("SUBJ-WRK" %in% pending_after$requests$subject_id)

})
# Test: hash chain integrity for consent records
local({
    test_db <- setup_test_db()
    on.exit(cleanup_test_db(test_db))

    purpose <- create_consent_purpose(
      purpose_code = "HASH",
      purpose_name = "Hash Chain Test",
      purpose_description = "This is for testing hash chain integrity.",
      legal_basis = "CONSENT",
      created_by = "admin"
    )

    c1 <- record_consent(
      subject_id = "SUBJ-HASH",
      subject_email = "hash@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "CHECKBOX",
      recorded_by = "system"
    )

    c2 <- record_consent(
      subject_id = "SUBJ-HASH",
      subject_email = "hash@example.com",
      purpose_id = purpose$purpose_id,
      consent_method = "SIGNATURE",
      recorded_by = "system"
    )

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    records <- DBI::dbGetQuery(con, "
      SELECT consent_id, consent_hash, previous_hash
      FROM consent_records
      WHERE subject_id = ?
      ORDER BY consent_id
    ", params = list("SUBJ-HASH"))

    expect_equal(nrow(records), 2)

    expect_equal(records$previous_hash[2], records$consent_hash[1])

})