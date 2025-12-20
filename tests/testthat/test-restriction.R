# test-restriction.R
# Test suite for GDPR Article 18 Right to Restrict Processing

# ============================================================================
# TEST SETUP
# ============================================================================

setup_test_db <- function() {
  test_dir <- tempdir()
  test_db <- file.path(test_dir, paste0("test_restr_", Sys.getpid(), ".db"))

  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_12345678901234567890123")
  Sys.setenv(ZZEDC_DB_PATH = test_db)

  init_result <- initialize_encrypted_database(db_path = test_db)
  if (!isTRUE(init_result$success)) {
    stop("Failed to initialize database: ", init_result$error)
  }

  audit_result <- init_audit_logging()
  if (!isTRUE(audit_result$success)) {
    stop("Failed to initialize audit logging: ", audit_result$error)
  }

  erasure_result <- init_erasure()
  if (!isTRUE(erasure_result$success)) {
    stop("Failed to initialize erasure: ", erasure_result$error)
  }

  rest_result <- init_restriction()
  if (!isTRUE(rest_result$success)) {
    stop("Failed to initialize restriction: ", rest_result$error)
  }

  test_db
}

cleanup_test_db <- function(test_db) {
  if (file.exists(test_db)) {
    try(file.remove(test_db), silent = TRUE)
  }
  Sys.unsetenv("ZZEDC_ENCRYPTION_KEY")
  Sys.unsetenv("ZZEDC_DB_PATH")
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

test_that("init_restriction creates all required tables", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  tables <- DBI::dbListTables(con)

  expect_true("restriction_requests" %in% tables)
  expect_true("restriction_items" %in% tables)
  expect_true("restriction_history" %in% tables)
  expect_true("restriction_third_parties" %in% tables)
  expect_true("processing_attempts" %in% tables)
})

test_that("init_restriction is idempotent", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- init_restriction()
  expect_true(result$success)
})

# ============================================================================
# REFERENCE DATA TESTS
# ============================================================================

test_that("get_restriction_grounds returns valid grounds", {
  grounds <- get_restriction_grounds()

  expect_type(grounds, "character")
  expect_true(length(grounds) >= 4)
  expect_true("ACCURACY_CONTESTED" %in% names(grounds))
  expect_true("UNLAWFUL_PROCESSING" %in% names(grounds))
  expect_true("LEGAL_CLAIMS" %in% names(grounds))
  expect_true("OBJECTION_PENDING" %in% names(grounds))
})

test_that("get_restriction_statuses returns valid statuses", {
  statuses <- get_restriction_statuses()

  expect_type(statuses, "character")
  expect_true("RECEIVED" %in% names(statuses))
  expect_true("ACTIVE" %in% names(statuses))
  expect_true("LIFTED" %in% names(statuses))
  expect_true("REJECTED" %in% names(statuses))
})

test_that("get_restriction_scopes returns valid scopes", {
  scopes <- get_restriction_scopes()

  expect_type(scopes, "character")
  expect_true("FULL" %in% names(scopes))
  expect_true("STORAGE_ONLY" %in% names(scopes))
  expect_true("CONSENT_ONLY" %in% names(scopes))
  expect_true("LEGAL_CLAIMS" %in% names(scopes))
})

test_that("get_allowed_processing_during_restriction returns allowed types", {
  allowed <- get_allowed_processing_during_restriction()

  expect_type(allowed, "character")
  expect_true("STORAGE" %in% names(allowed))
  expect_true("CONSENT_PROCESSING" %in% names(allowed))
  expect_true("LEGAL_CLAIMS" %in% names(allowed))
  expect_true("BACKUP" %in% names(allowed))
})

# ============================================================================
# REQUEST CREATION TESTS
# ============================================================================

test_that("create_restriction_request creates request successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  expect_true(result$success)
  expect_true(!is.null(result$request_id))
  expect_true(grepl("^RESTR-", result$request_number))
  expect_equal(result$status, "RECEIVED")
  expect_false(result$is_held)
})

test_that("create_restriction_request requires email", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_restriction_request(
    subject_email = "",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("subject_email", result$error))
})

test_that("create_restriction_request validates grounds", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "INVALID_GROUNDS",
    requested_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid restriction_grounds", result$error))
})

test_that("create_restriction_request sets 30-day due date", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  expect_true(result$success)

  expected_due <- format(Sys.Date() + 30, "%Y-%m-%d")
  expect_equal(result$due_date, expected_due)
})

test_that("create_restriction_request logs action", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  expect_true(result$success)

  history <- get_restriction_history(request_id = result$request_id)
  expect_true(history$success)
  expect_true(any(history$history$action == "REQUEST_CREATED"))
})

test_that("create_restriction_request detects legal hold", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  hold <- create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA 21 CFR Part 11 retention requirement",
    legal_basis = "21 CFR Part 11.10(c)",
    created_by = "compliance",
    affected_subjects = "SUBJ-001"
  )
  expect_true(hold$success)

  result <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo",
    subject_id = "SUBJ-001"
  )

  expect_true(result$success)
  expect_equal(result$status, "LEGAL_HOLD")
  expect_true(result$is_held)
})

# ============================================================================
# ITEM MANAGEMENT TESTS
# ============================================================================

test_that("add_restriction_item adds item successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )
  expect_true(request$success)

  result <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  expect_true(result$success)
  expect_true(!is.null(result$item_id))
  expect_equal(result$status, "PENDING")
})

test_that("add_restriction_item validates scope", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo",
    restriction_scope = "INVALID_SCOPE"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid restriction_scope", result$error))
})

test_that("add_restriction_item detects legal hold on category", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  hold <- create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA 21 CFR Part 11 retention requirement",
    legal_basis = "21 CFR Part 11",
    created_by = "compliance",
    affected_data_categories = "HEALTH"
  )
  expect_true(hold$success)

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- add_restriction_item(
    request_id = request$request_id,
    table_name = "medical_records",
    record_id = "MED-001",
    data_category = "HEALTH",
    added_by = "dpo"
  )

  expect_true(result$success)
  expect_equal(result$status, "ON_HOLD")
  expect_true(result$is_on_hold)
})

# ============================================================================
# ITEM REVIEW TESTS
# ============================================================================

test_that("review_restriction_item approves item", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  result <- review_restriction_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin"
  )

  expect_true(result$success)
  expect_equal(result$status, "APPROVED")
})

test_that("review_restriction_item rejects with reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  result <- review_restriction_item(
    item_id = item$item_id,
    decision = "REJECTED",
    reviewed_by = "admin",
    rejection_reason = "Data accuracy verified as correct"
  )

  expect_true(result$success)
  expect_equal(result$status, "REJECTED")
})

test_that("review_restriction_item requires rejection reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  result <- review_restriction_item(
    item_id = item$item_id,
    decision = "REJECTED",
    reviewed_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("rejection_reason required", result$error))
})

test_that("review_restriction_item blocks on_hold items", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  hold <- create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA 21 CFR Part 11 retention requirement",
    legal_basis = "21 CFR Part 11",
    created_by = "compliance",
    affected_data_categories = "HEALTH"
  )

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "medical",
    record_id = "MED-001",
    data_category = "HEALTH",
    added_by = "dpo"
  )
  expect_equal(item$status, "ON_HOLD")

  result <- review_restriction_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("on hold", result$error))
})

# ============================================================================
# APPLY RESTRICTION TESTS
# ============================================================================

test_that("apply_restriction_item applies approved restriction", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  review_restriction_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin"
  )

  result <- apply_restriction_item(
    item_id = item$item_id,
    applied_by = "data_manager"
  )

  expect_true(result$success)
  expect_equal(result$status, "ACTIVE")
  expect_true(!is.null(result$applied_at))
})

test_that("apply_restriction_item requires approval first", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  result <- apply_restriction_item(
    item_id = item$item_id,
    applied_by = "data_manager"
  )

  expect_false(result$success)
  expect_true(grepl("must be approved", result$error))
})

# ============================================================================
# LIFT RESTRICTION TESTS
# ============================================================================

test_that("lift_restriction_item lifts active restriction", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  review_restriction_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin"
  )

  apply_restriction_item(
    item_id = item$item_id,
    applied_by = "data_manager"
  )

  result <- lift_restriction_item(
    item_id = item$item_id,
    lifted_by = "dpo",
    lift_reason = "Accuracy dispute resolved in favor of original data"
  )

  expect_true(result$success)
  expect_equal(result$status, "LIFTED")
})

test_that("lift_restriction_item requires minimum reason length", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  review_restriction_item(item_id = item$item_id, decision = "APPROVED",
                          reviewed_by = "admin")
  apply_restriction_item(item_id = item$item_id, applied_by = "data_manager")

  result <- lift_restriction_item(
    item_id = item$item_id,
    lifted_by = "dpo",
    lift_reason = "Short"
  )

  expect_false(result$success)
  expect_true(grepl("20 characters", result$error))
})

# ============================================================================
# PROCESSING CONTROL TESTS
# ============================================================================

test_that("check_restriction_status detects active restriction", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  review_restriction_item(item_id = item$item_id, decision = "APPROVED",
                          reviewed_by = "admin")
  apply_restriction_item(item_id = item$item_id, applied_by = "data_manager")

  result <- check_restriction_status(
    table_name = "subjects",
    record_id = "SUBJ-001"
  )

  expect_true(result$success)
  expect_true(result$is_restricted)
  expect_true(!is.null(result$allowed_processing))
})

test_that("check_restriction_status returns false when no restriction", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- check_restriction_status(
    table_name = "subjects",
    record_id = "SUBJ-999"
  )

  expect_true(result$success)
  expect_false(result$is_restricted)
})

test_that("log_processing_attempt logs blocked attempt", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo",
    subject_id = "SUBJ-001"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  review_restriction_item(item_id = item$item_id, decision = "APPROVED",
                          reviewed_by = "admin")
  apply_restriction_item(item_id = item$item_id, applied_by = "data_manager")

  result <- log_processing_attempt(
    table_name = "subjects",
    record_id = "SUBJ-001",
    operation_type = "UPDATE",
    attempted_by = "user123",
    subject_id = "SUBJ-001",
    was_blocked = TRUE
  )

  expect_true(result$success)
  expect_true(result$was_blocked)

  attempts <- get_processing_attempts(subject_id = "SUBJ-001")
  expect_true(attempts$count > 0)
})

test_that("log_processing_attempt logs allowed override", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- log_processing_attempt(
    table_name = "subjects",
    record_id = "SUBJ-001",
    operation_type = "BACKUP",
    attempted_by = "system",
    was_blocked = FALSE,
    override_reason = "Backup is allowed processing during restriction",
    override_authorized_by = "dpo"
  )

  expect_true(result$success)
  expect_false(result$was_blocked)
})

# ============================================================================
# THIRD-PARTY NOTIFICATION TESTS
# ============================================================================

test_that("add_restriction_third_party adds recipient", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- add_restriction_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Partner",
    recipient_type = "PROCESSOR",
    added_by = "dpo",
    contact_email = "privacy@analytics.com"
  )

  expect_true(result$success)
  expect_true(!is.null(result$recipient_id))
})

test_that("notify_restriction_third_party records notification", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  recipient <- add_restriction_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Partner",
    recipient_type = "PROCESSOR",
    added_by = "dpo"
  )

  result <- notify_restriction_third_party(
    recipient_id = recipient$recipient_id,
    sent_by = "dpo"
  )

  expect_true(result$success)
  expect_true(!is.null(result$notification_sent_date))
})

test_that("confirm_restriction_third_party requires notification first", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  recipient <- add_restriction_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Partner",
    recipient_type = "PROCESSOR",
    added_by = "dpo"
  )

  result <- confirm_restriction_third_party(
    recipient_id = recipient$recipient_id,
    confirmed_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("notification first", result$error))
})

test_that("confirm_restriction_third_party records confirmation", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  recipient <- add_restriction_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Partner",
    recipient_type = "PROCESSOR",
    added_by = "dpo"
  )

  notify_restriction_third_party(
    recipient_id = recipient$recipient_id,
    sent_by = "dpo"
  )

  result <- confirm_restriction_third_party(
    recipient_id = recipient$recipient_id,
    confirmed_by = "dpo"
  )

  expect_true(result$success)
  expect_true(!is.null(result$restriction_confirmed_date))
})

test_that("notify_lift_third_party records lift notification", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  recipient <- add_restriction_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Partner",
    recipient_type = "PROCESSOR",
    added_by = "dpo"
  )

  result <- notify_lift_third_party(
    recipient_id = recipient$recipient_id,
    sent_by = "dpo"
  )

  expect_true(result$success)
  expect_true(!is.null(result$lift_notification_sent_date))
})

# ============================================================================
# REQUEST APPROVAL AND ACTIVATION TESTS
# ============================================================================

test_that("approve_restriction_request approves request", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- approve_restriction_request(
    request_id = request$request_id,
    approved_by = "admin",
    review_notes = "Request verified"
  )

  expect_true(result$success)
  expect_equal(result$status, "APPROVED")
})

test_that("activate_restriction_request activates with active items", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  review_restriction_item(item_id = item$item_id, decision = "APPROVED",
                          reviewed_by = "admin")
  apply_restriction_item(item_id = item$item_id, applied_by = "data_manager")

  approve_restriction_request(request_id = request$request_id,
                              approved_by = "admin")

  result <- activate_restriction_request(
    request_id = request$request_id,
    activated_by = "dpo"
  )

  expect_true(result$success)
  expect_equal(result$status, "ACTIVE")
  expect_equal(result$active_items, 1)
})

test_that("activate_restriction_request requires approved status", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- activate_restriction_request(
    request_id = request$request_id,
    activated_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("must be approved", result$error))
})

# ============================================================================
# LIFT REQUEST TESTS
# ============================================================================

test_that("lift_restriction_request lifts all active items", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  review_restriction_item(item_id = item$item_id, decision = "APPROVED",
                          reviewed_by = "admin")
  apply_restriction_item(item_id = item$item_id, applied_by = "data_manager")
  approve_restriction_request(request_id = request$request_id,
                              approved_by = "admin")
  activate_restriction_request(request_id = request$request_id,
                               activated_by = "dpo")

  result <- lift_restriction_request(
    request_id = request$request_id,
    lifted_by = "dpo",
    lift_reason = "Accuracy verification complete - data confirmed correct"
  )

  expect_true(result$success)
  expect_equal(result$status, "LIFTED")

  items <- get_restriction_items(request_id = request$request_id)
  expect_equal(items$items$status[1], "LIFTED")
})

# ============================================================================
# REJECT REQUEST TESTS
# ============================================================================

test_that("reject_restriction_request rejects with reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- reject_restriction_request(
    request_id = request$request_id,
    rejection_reason = "Request does not meet GDPR Article 18(1) criteria",
    rejected_by = "legal"
  )

  expect_true(result$success)
  expect_equal(result$status, "REJECTED")
})

test_that("reject_restriction_request requires minimum reason length", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- reject_restriction_request(
    request_id = request$request_id,
    rejection_reason = "No",
    rejected_by = "legal"
  )

  expect_false(result$success)
  expect_true(grepl("20 characters", result$error))
})

# ============================================================================
# RETRIEVAL TESTS
# ============================================================================

test_that("get_restriction_request retrieves by ID", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  created <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- get_restriction_request(request_id = created$request_id)

  expect_true(result$success)
  expect_equal(result$request$subject_email[1], "john@example.com")
})

test_that("get_restriction_request retrieves by number", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  created <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  result <- get_restriction_request(request_number = created$request_number)

  expect_true(result$success)
  expect_equal(result$request$request_id[1], created$request_id)
})

test_that("get_restriction_items filters by status", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-002",
    data_category = "DEMOGRAPHIC",
    added_by = "dpo"
  )

  result <- get_restriction_items(request_id = request$request_id,
                                  status = "PENDING")
  expect_equal(result$count, 2)
})

test_that("get_pending_restriction_requests returns pending requests", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  create_restriction_request(
    subject_email = "jane@example.com",
    subject_name = "Jane Doe",
    restriction_grounds = "UNLAWFUL_PROCESSING",
    requested_by = "dpo"
  )

  result <- get_pending_restriction_requests()

  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("get_active_restrictions returns active restrictions", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  item <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  review_restriction_item(item_id = item$item_id, decision = "APPROVED",
                          reviewed_by = "admin")
  apply_restriction_item(item_id = item$item_id, applied_by = "data_manager")
  approve_restriction_request(request_id = request$request_id,
                              approved_by = "admin")
  activate_restriction_request(request_id = request$request_id,
                               activated_by = "dpo")

  result <- get_active_restrictions()

  expect_true(result$success)
  expect_true(result$count >= 1)
})

# ============================================================================
# STATISTICS TESTS
# ============================================================================

test_that("get_restriction_statistics returns comprehensive stats", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )

  result <- get_restriction_statistics()

  expect_true(result$success)
  expect_true(!is.null(result$requests))
  expect_true(!is.null(result$items))
  expect_true(!is.null(result$third_party))
  expect_true(!is.null(result$processing_attempts))
  expect_true(!is.null(result$by_grounds))
})

# ============================================================================
# REPORT GENERATION TESTS
# ============================================================================

test_that("generate_restriction_report creates TXT report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  output_file <- tempfile(fileext = ".txt")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_restriction_report(
    output_file = output_file,
    format = "txt",
    organization = "Test Organization",
    prepared_by = "Test DPO"
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))

  content <- readLines(output_file)
  expect_true(any(grepl("GDPR ARTICLE 18", content)))
  expect_true(any(grepl("Test Organization", content)))
})

test_that("generate_restriction_report creates JSON report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo"
  )

  output_file <- tempfile(fileext = ".json")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_restriction_report(
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

test_that("full restriction workflow completes successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo",
    subject_id = "SUBJ-001"
  )
  expect_true(request$success)
  expect_equal(request$status, "RECEIVED")

  item1 <- add_restriction_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    added_by = "dpo"
  )
  expect_true(item1$success)

  item2 <- add_restriction_item(
    request_id = request$request_id,
    table_name = "demographics",
    record_id = "SUBJ-001",
    data_category = "DEMOGRAPHIC",
    added_by = "dpo",
    restriction_scope = "STORAGE_ONLY"
  )
  expect_true(item2$success)

  review1 <- review_restriction_item(
    item_id = item1$item_id,
    decision = "APPROVED",
    reviewed_by = "admin"
  )
  expect_true(review1$success)

  review2 <- review_restriction_item(
    item_id = item2$item_id,
    decision = "APPROVED",
    reviewed_by = "admin"
  )
  expect_true(review2$success)

  apply1 <- apply_restriction_item(
    item_id = item1$item_id,
    applied_by = "data_manager"
  )
  expect_true(apply1$success)

  apply2 <- apply_restriction_item(
    item_id = item2$item_id,
    applied_by = "data_manager"
  )
  expect_true(apply2$success)

  status_check <- check_restriction_status(
    table_name = "subjects",
    record_id = "SUBJ-001"
  )
  expect_true(status_check$is_restricted)

  recipient <- add_restriction_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Partner",
    recipient_type = "PROCESSOR",
    added_by = "dpo"
  )
  expect_true(recipient$success)

  notify <- notify_restriction_third_party(
    recipient_id = recipient$recipient_id,
    sent_by = "dpo"
  )
  expect_true(notify$success)

  confirm <- confirm_restriction_third_party(
    recipient_id = recipient$recipient_id,
    confirmed_by = "dpo"
  )
  expect_true(confirm$success)

  approve <- approve_restriction_request(
    request_id = request$request_id,
    approved_by = "admin"
  )
  expect_true(approve$success)

  activate <- activate_restriction_request(
    request_id = request$request_id,
    activated_by = "dpo"
  )
  expect_true(activate$success)
  expect_equal(activate$status, "ACTIVE")

  attempt <- log_processing_attempt(
    table_name = "subjects",
    record_id = "SUBJ-001",
    operation_type = "UPDATE",
    attempted_by = "user123",
    subject_id = "SUBJ-001",
    was_blocked = TRUE
  )
  expect_true(attempt$success)
  expect_true(attempt$was_blocked)

  lift <- lift_restriction_request(
    request_id = request$request_id,
    lifted_by = "dpo",
    lift_reason = "Accuracy verification complete - original data confirmed correct"
  )
  expect_true(lift$success)
  expect_equal(lift$status, "LIFTED")

  final_check <- check_restriction_status(
    table_name = "subjects",
    record_id = "SUBJ-001"
  )
  expect_false(final_check$is_restricted)

  history <- get_restriction_history(request_id = request$request_id)
  expect_true(history$count >= 10)
})

test_that("restriction blocked by legal hold workflow", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  hold <- create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA 21 CFR Part 11 retention requirement",
    legal_basis = "21 CFR Part 11.10(c)",
    created_by = "compliance",
    affected_subjects = "SUBJ-001"
  )
  expect_true(hold$success)

  request <- create_restriction_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    restriction_grounds = "ACCURACY_CONTESTED",
    requested_by = "dpo",
    subject_id = "SUBJ-001"
  )

  expect_true(request$success)
  expect_equal(request$status, "LEGAL_HOLD")
  expect_true(request$is_held)

  release <- release_legal_hold(
    hold_id = hold$hold_id,
    release_reason = "Retention period complete and FDA compliance met",
    released_by = "compliance"
  )
  expect_true(release$success)

  check <- check_legal_hold(subject_id = "SUBJ-001")
  expect_false(check$is_held)
})
