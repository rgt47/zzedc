# tests/testthat/test-rectification.R
#
# Test suite for Right to Rectification (GDPR Article 16)

suppressPackageStartupMessages({
  library(testthat)
  library(DBI)
})

pkg_root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(pkg_root, "R/encryption_utils.R"))
source(file.path(pkg_root, "R/aws_kms_utils.R"))
source(file.path(pkg_root, "R/db_connection.R"))
source(file.path(pkg_root, "R/audit_logging.R"))
source(file.path(pkg_root, "R/rectification.R"))

setup_test_db <- function() {
  test_dir <- tempdir()
  test_db <- file.path(test_dir, paste0("test_rect_", Sys.getpid(), ".db"))

  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_12345678901234567890123")
  Sys.setenv(ZZEDC_DB_PATH = test_db)

  init_result <- initialize_encrypted_database(db_path = test_db)

  if (!init_result$success) {
    stop("Failed to initialize test database: ", init_result$error)
  }

  audit_result <- init_audit_logging(db_path = test_db)
  if (!audit_result$success) {
    stop("Failed to initialize audit logging: ", audit_result$error)
  }

  rect_result <- init_rectification(db_path = test_db)
  if (!rect_result$success) {
    stop("Failed to initialize rectification: ", rect_result$error)
  }

  test_db
}

cleanup_test_db <- function(db_path) {
  Sys.unsetenv("ZZEDC_ENCRYPTION_KEY")
  Sys.unsetenv("ZZEDC_DB_PATH")
  if (file.exists(db_path)) {
    try(unlink(db_path, force = TRUE), silent = TRUE)
  }
}

# =============================================================================
# Initialization Tests
# =============================================================================

test_that("init_rectification creates required tables", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  conn <- connect_encrypted_db(db_path = test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE, after = FALSE)

  tables <- DBI::dbListTables(conn)

  expect_true("rectification_requests" %in% tables)
  expect_true("rectification_items" %in% tables)
  expect_true("rectification_history" %in% tables)
  expect_true("third_party_recipients" %in% tables)
  expect_true("rectification_notifications" %in% tables)
})

test_that("init_rectification is idempotent", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result2 <- init_rectification(db_path = test_db)
  expect_true(result2$success)
})


# =============================================================================
# Reference Data Tests
# =============================================================================

test_that("get_rectification_types returns valid types", {
  types <- get_rectification_types()

  expect_type(types, "list")
  expect_true("CORRECTION" %in% names(types))
  expect_true("COMPLETION" %in% names(types))
  expect_true("BOTH" %in% names(types))
  expect_equal(length(types), 3)
})

test_that("get_rectification_statuses returns valid statuses", {
  statuses <- get_rectification_statuses()

  expect_type(statuses, "list")
  expect_true("RECEIVED" %in% names(statuses))
  expect_true("UNDER_REVIEW" %in% names(statuses))
  expect_true("APPROVED" %in% names(statuses))
  expect_true("PARTIALLY_APPROVED" %in% names(statuses))
  expect_true("REJECTED" %in% names(statuses))
  expect_true("COMPLETED" %in% names(statuses))
  expect_true("CLOSED" %in% names(statuses))
  expect_equal(length(statuses), 7)
})


# =============================================================================
# Request Creation Tests
# =============================================================================

test_that("create_rectification_request creates request successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_rectification_request(
    subject_email = "john.doe@example.com",
    subject_name = "John Doe",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(!is.null(result$request_id))
  expect_true(grepl("^RECT-", result$request_number))
  expect_true(!is.null(result$due_date))
})

test_that("create_rectification_request sets 30-day due date", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_rectification_request(
    subject_email = "jane.doe@example.com",
    subject_name = "Jane Doe",
    request_type = "COMPLETION",
    requested_by = "dpo",
    db_path = test_db
  )

  expect_true(result$success)
  expected_due <- as.character(Sys.Date() + 30)
  expect_equal(result$due_date, expected_due)
})

test_that("create_rectification_request validates request type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "INVALID_TYPE",
    requested_by = "dpo",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid request type", result$error))
})

test_that("create_rectification_request with optional subject_id", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_rectification_request(
    subject_email = "subject123@example.com",
    subject_name = "Subject 123",
    request_type = "BOTH",
    requested_by = "coordinator",
    subject_id = "SUBJ-123",
    db_path = test_db
  )

  expect_true(result$success)

  request <- get_rectification_request(
    request_id = result$request_id,
    db_path = test_db
  )
  expect_equal(request$subject_id, "SUBJ-123")
})

test_that("create_rectification_request creates hash chain", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result1 <- create_rectification_request(
    subject_email = "first@example.com",
    subject_name = "First User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  result2 <- create_rectification_request(
    subject_email = "second@example.com",
    subject_name = "Second User",
    request_type = "COMPLETION",
    requested_by = "dpo",
    db_path = test_db
  )

  req1 <- get_rectification_request(request_id = result1$request_id, db_path = test_db)
  req2 <- get_rectification_request(request_id = result2$request_id, db_path = test_db)

  expect_equal(req1$previous_hash, "GENESIS")
  expect_equal(req2$previous_hash, req1$request_hash)
})


# =============================================================================
# Rectification Item Tests
# =============================================================================

test_that("add_rectification_item adds item successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  expect_true(item$success)
  expect_true(!is.null(item$item_id))
})

test_that("add_rectification_item validates rectification type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "INVALID",
    added_by = "dpo",
    db_path = test_db
  )

  expect_false(item$success)
  expect_true(grepl("CORRECTION or COMPLETION", item$error))
})

test_that("add_rectification_item stores justification and evidence", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "demographics",
    record_id = "DEMO-001",
    field_name = "date_of_birth",
    current_value = "1990-01-01",
    requested_value = "1990-01-15",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    justification = "Birth certificate shows correct date",
    supporting_evidence = "Scanned birth certificate DOC-12345",
    db_path = test_db
  )

  expect_true(item$success)

  items <- get_rectification_items(request$request_id, db_path = test_db)
  expect_equal(nrow(items), 1)
  expect_equal(items$justification[1], "Birth certificate shows correct date")
  expect_equal(items$supporting_evidence[1], "Scanned birth certificate DOC-12345")
})


# =============================================================================
# Item Review Tests
# =============================================================================

test_that("review_rectification_item approves item successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review <- review_rectification_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  expect_true(review$success)
  expect_equal(review$decision, "APPROVED")

  items <- get_rectification_items(request$request_id, db_path = test_db)
  expect_equal(items$status[1], "APPROVED")
})

test_that("review_rectification_item rejects with reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "study_id",
    current_value = "STUDY-001",
    requested_value = "STUDY-999",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review <- review_rectification_item(
    item_id = item$item_id,
    decision = "REJECTED",
    reviewed_by = "admin",
    rejection_reason = "Study ID cannot be modified after enrollment",
    db_path = test_db
  )

  expect_true(review$success)
  expect_equal(review$decision, "REJECTED")

  items <- get_rectification_items(request$request_id, db_path = test_db)
  expect_equal(items$status[1], "REJECTED")
  expect_equal(items$rejection_reason[1], "Study ID cannot be modified after enrollment")
})

test_that("review_rectification_item requires rejection reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review <- review_rectification_item(
    item_id = item$item_id,
    decision = "REJECTED",
    reviewed_by = "admin",
    rejection_reason = "Short",
    db_path = test_db
  )

  expect_false(review$success)
  expect_true(grepl("at least 10 characters", review$error))
})

test_that("review_rectification_item validates decision", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- review_rectification_item(
    item_id = 999,
    decision = "INVALID",
    reviewed_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("APPROVED or REJECTED", result$error))
})


# =============================================================================
# Apply Rectification Tests
# =============================================================================

test_that("apply_rectification_item applies approved item", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "phone",
    current_value = "+1-555-0100",
    requested_value = "+1-555-0200",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review_rectification_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  apply_result <- apply_rectification_item(
    item_id = item$item_id,
    applied_by = "data_manager",
    db_path = test_db
  )

  expect_true(apply_result$success)
  expect_equal(apply_result$old_value, "+1-555-0100")
  expect_equal(apply_result$new_value, "+1-555-0200")

  items <- get_rectification_items(request$request_id, db_path = test_db)
  expect_equal(items$status[1], "APPLIED")
})

test_that("apply_rectification_item rejects unapproved item", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "phone",
    current_value = "+1-555-0100",
    requested_value = "+1-555-0200",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  apply_result <- apply_rectification_item(
    item_id = item$item_id,
    applied_by = "data_manager",
    db_path = test_db
  )

  expect_false(apply_result$success)
  expect_true(grepl("must be approved", apply_result$error))
})


# =============================================================================
# Third-Party Recipient Tests
# =============================================================================

test_that("add_third_party_recipient adds recipient successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  recipient <- add_third_party_recipient(
    request_id = request$request_id,
    recipient_name = "Laboratory Services Inc",
    recipient_type = "PROCESSOR",
    data_shared = "Lab results and demographics",
    added_by = "dpo",
    contact_email = "compliance@labservices.com",
    contact_name = "Jane Smith",
    db_path = test_db
  )

  expect_true(recipient$success)
  expect_true(!is.null(recipient$recipient_id))

  recipients <- get_third_party_recipients(request$request_id, db_path = test_db)
  expect_equal(nrow(recipients), 1)
  expect_equal(recipients$recipient_name[1], "Laboratory Services Inc")
  expect_equal(recipients$recipient_type[1], "PROCESSOR")
})

test_that("add_third_party_recipient validates recipient type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  recipient <- add_third_party_recipient(
    request_id = request$request_id,
    recipient_name = "Unknown Org",
    recipient_type = "INVALID_TYPE",
    data_shared = "Some data",
    added_by = "dpo",
    db_path = test_db
  )

  expect_false(recipient$success)
  expect_true(grepl("Invalid recipient type", recipient$error))
})

test_that("add_third_party_recipient supports all valid types", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  valid_types <- c("PROCESSOR", "CONTROLLER", "THIRD_PARTY", "REGULATOR")
  for (rtype in valid_types) {
    result <- add_third_party_recipient(
      request_id = request$request_id,
      recipient_name = paste("Org", rtype),
      recipient_type = rtype,
      data_shared = "Data",
      added_by = "dpo",
      db_path = test_db
    )
    expect_true(result$success, info = paste("Type:", rtype))
  }

  recipients <- get_third_party_recipients(request$request_id, db_path = test_db)
  expect_equal(nrow(recipients), 4)
})


# =============================================================================
# Third-Party Notification Tests
# =============================================================================

test_that("send_third_party_notification records notification", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  recipient <- add_third_party_recipient(
    request_id = request$request_id,
    recipient_name = "Analytics Corp",
    recipient_type = "PROCESSOR",
    data_shared = "Usage data",
    added_by = "dpo",
    contact_email = "privacy@analytics.com",
    db_path = test_db
  )

  notification <- send_third_party_notification(
    recipient_id = recipient$recipient_id,
    notification_method = "EMAIL",
    sent_by = "dpo",
    notification_content = "Please update records per GDPR Article 19",
    db_path = test_db
  )

  expect_true(notification$success)
  expect_equal(notification$recipient_name, "Analytics Corp")

  recipients <- get_third_party_recipients(request$request_id, db_path = test_db)
  expect_equal(recipients$notification_sent[1], 1)
  expect_equal(recipients$notification_method[1], "EMAIL")
})

test_that("send_third_party_notification validates method", {
  result <- send_third_party_notification(
    recipient_id = 999,
    notification_method = "INVALID",
    sent_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid method", result$error))
})

test_that("send_third_party_notification supports all methods", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  methods <- c("EMAIL", "API", "POSTAL", "MANUAL")
  for (method in methods) {
    recipient <- add_third_party_recipient(
      request_id = request$request_id,
      recipient_name = paste("Org", method),
      recipient_type = "PROCESSOR",
      data_shared = "Data",
      added_by = "dpo",
      db_path = test_db
    )

    result <- send_third_party_notification(
      recipient_id = recipient$recipient_id,
      notification_method = method,
      sent_by = "dpo",
      db_path = test_db
    )
    expect_true(result$success, info = paste("Method:", method))
  }
})


# =============================================================================
# Acknowledgment Tests
# =============================================================================

test_that("record_third_party_acknowledgment records acknowledgment", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  recipient <- add_third_party_recipient(
    request_id = request$request_id,
    recipient_name = "Partner Org",
    recipient_type = "CONTROLLER",
    data_shared = "Shared data",
    added_by = "dpo",
    db_path = test_db
  )

  send_third_party_notification(
    recipient_id = recipient$recipient_id,
    notification_method = "EMAIL",
    sent_by = "dpo",
    db_path = test_db
  )

  ack <- record_third_party_acknowledgment(
    recipient_id = recipient$recipient_id,
    recorded_by = "dpo",
    db_path = test_db
  )

  expect_true(ack$success)

  recipients <- get_third_party_recipients(request$request_id, db_path = test_db)
  expect_equal(recipients$acknowledgment_received[1], 1)
  expect_true(!is.na(recipients$acknowledgment_date[1]))
})


# =============================================================================
# Request Completion Tests
# =============================================================================

test_that("complete_rectification_request requires all items processed", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  complete <- complete_rectification_request(
    request_id = request$request_id,
    completed_by = "admin",
    db_path = test_db
  )

  expect_false(complete$success)
  expect_true(grepl("pending review", complete$error))
})

test_that("complete_rectification_request requires all approved items applied", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review_rectification_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  complete <- complete_rectification_request(
    request_id = request$request_id,
    completed_by = "admin",
    db_path = test_db
  )

  expect_false(complete$success)
  expect_true(grepl("not yet applied", complete$error))
})

test_that("complete_rectification_request requires all notifications sent", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review_rectification_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  apply_rectification_item(
    item_id = item$item_id,
    applied_by = "data_manager",
    db_path = test_db
  )

  add_third_party_recipient(
    request_id = request$request_id,
    recipient_name = "Partner Org",
    recipient_type = "PROCESSOR",
    data_shared = "Subject data",
    added_by = "dpo",
    db_path = test_db
  )

  complete <- complete_rectification_request(
    request_id = request$request_id,
    completed_by = "admin",
    db_path = test_db
  )

  expect_false(complete$success)
  expect_true(grepl("notifications pending", complete$error))
})

test_that("complete_rectification_request completes successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review_rectification_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  apply_rectification_item(
    item_id = item$item_id,
    applied_by = "data_manager",
    db_path = test_db
  )

  complete <- complete_rectification_request(
    request_id = request$request_id,
    completed_by = "admin",
    db_path = test_db
  )

  expect_true(complete$success)
  expect_equal(complete$status, "COMPLETED")
  expect_equal(complete$items_applied, 1)
  expect_equal(complete$items_rejected, 0)

  req <- get_rectification_request(request_id = request$request_id, db_path = test_db)
  expect_equal(req$status, "COMPLETED")
})


# =============================================================================
# Request Rejection Tests
# =============================================================================

test_that("reject_rectification_request rejects with reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  result <- reject_rectification_request(
    request_id = request$request_id,
    rejection_reason = "Request is manifestly unfounded - data is already accurate",
    rejected_by = "admin",
    db_path = test_db
  )

  expect_true(result$success)

  req <- get_rectification_request(request_id = request$request_id, db_path = test_db)
  expect_equal(req$status, "REJECTED")
  expect_true(grepl("manifestly unfounded", req$rejection_reason))
})

test_that("reject_rectification_request requires reason length", {
  result <- reject_rectification_request(
    request_id = 1,
    rejection_reason = "Too short",
    rejected_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("at least 20 characters", result$error))
})


# =============================================================================
# Retrieval Tests
# =============================================================================

test_that("get_rectification_request retrieves by ID", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create <- create_rectification_request(
    subject_email = "retrieve@example.com",
    subject_name = "Retrieve User",
    request_type = "COMPLETION",
    requested_by = "dpo",
    db_path = test_db
  )

  request <- get_rectification_request(
    request_id = create$request_id,
    db_path = test_db
  )

  expect_equal(nrow(request), 1)
  expect_equal(request$subject_email, "retrieve@example.com")
  expect_equal(request$request_type, "COMPLETION")
})

test_that("get_rectification_request retrieves by number", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create <- create_rectification_request(
    subject_email = "number@example.com",
    subject_name = "Number User",
    request_type = "BOTH",
    requested_by = "dpo",
    db_path = test_db
  )

  request <- get_rectification_request(
    request_number = create$request_number,
    db_path = test_db
  )

  expect_equal(nrow(request), 1)
  expect_equal(request$request_id, create$request_id)
})

test_that("get_rectification_items retrieves all items", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "items@example.com",
    subject_name = "Items User",
    request_type = "BOTH",
    requested_by = "dpo",
    db_path = test_db
  )

  add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "middle_name",
    current_value = NA,
    requested_value = "James",
    rectification_type = "COMPLETION",
    added_by = "dpo",
    db_path = test_db
  )

  items <- get_rectification_items(request$request_id, db_path = test_db)
  expect_equal(nrow(items), 2)
})

test_that("get_rectification_items filters by status", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "filter@example.com",
    subject_name = "Filter User",
    request_type = "BOTH",
    requested_by = "dpo",
    db_path = test_db
  )

  item1 <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "phone",
    current_value = "123",
    requested_value = "456",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review_rectification_item(
    item_id = item1$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  pending <- get_rectification_items(
    request$request_id,
    status = "PENDING",
    db_path = test_db
  )
  expect_equal(nrow(pending), 1)

  approved <- get_rectification_items(
    request$request_id,
    status = "APPROVED",
    db_path = test_db
  )
  expect_equal(nrow(approved), 1)
})

test_that("get_rectification_history retrieves history", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "history@example.com",
    subject_name = "History User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  review_rectification_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  history <- get_rectification_history(request$request_id, db_path = test_db)
  expect_gte(nrow(history), 2)
  expect_true("REQUEST_CREATED" %in% history$action)
  expect_true("ITEM_ADDED" %in% history$action)
})

test_that("get_pending_rectification_requests retrieves pending", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_rectification_request(
    subject_email = "pending1@example.com",
    subject_name = "Pending User 1",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  req2 <- create_rectification_request(
    subject_email = "pending2@example.com",
    subject_name = "Pending User 2",
    request_type = "COMPLETION",
    requested_by = "dpo",
    db_path = test_db
  )

  reject_rectification_request(
    request_id = req2$request_id,
    rejection_reason = "This is a test rejection that is long enough",
    rejected_by = "admin",
    db_path = test_db
  )

  pending <- get_pending_rectification_requests(db_path = test_db)
  expect_equal(nrow(pending), 1)
  expect_equal(pending$subject_email[1], "pending1@example.com")
})


# =============================================================================
# Statistics Tests
# =============================================================================

test_that("get_rectification_statistics returns statistics", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "stats@example.com",
    subject_name = "Stats User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "new@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    db_path = test_db
  )

  add_third_party_recipient(
    request_id = request$request_id,
    recipient_name = "Partner Org",
    recipient_type = "PROCESSOR",
    data_shared = "Data",
    added_by = "dpo",
    db_path = test_db
  )

  stats <- get_rectification_statistics(db_path = test_db)

  expect_true(stats$success)
  expect_equal(stats$requests$total, 1)
  expect_equal(stats$requests$pending, 1)
  expect_equal(stats$items$total, 1)
  expect_equal(stats$items$pending, 1)
  expect_equal(stats$third_party$total_recipients, 1)
  expect_gte(nrow(stats$by_type), 1)
})


# =============================================================================
# Report Generation Tests
# =============================================================================

test_that("generate_rectification_report creates TXT report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_rectification_request(
    subject_email = "report@example.com",
    subject_name = "Report User",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  report_file <- tempfile(fileext = ".txt")
  on.exit(unlink(report_file), add = TRUE)

  result <- generate_rectification_report(
    output_file = report_file,
    format = "txt",
    organization = "Test Organization",
    prepared_by = "Test DPO",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(report_file))

  content <- readLines(report_file)
  expect_true(any(grepl("RECTIFICATION COMPLIANCE REPORT", content)))
  expect_true(any(grepl("Test Organization", content)))
  expect_true(any(grepl("GDPR Article 16", content)))
})

test_that("generate_rectification_report creates JSON report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_rectification_request(
    subject_email = "json@example.com",
    subject_name = "JSON User",
    request_type = "BOTH",
    requested_by = "dpo",
    db_path = test_db
  )

  report_file <- tempfile(fileext = ".json")
  on.exit(unlink(report_file), add = TRUE)

  result <- generate_rectification_report(
    output_file = report_file,
    format = "json",
    organization = "JSON Organization",
    prepared_by = "JSON DPO",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(report_file))

  content <- jsonlite::read_json(report_file)
  expect_equal(content$report_type, "Rectification Compliance Report")
  expect_equal(content$organization, "JSON Organization")
  expect_true(!is.null(content$statistics))
})


# =============================================================================
# Integration Tests
# =============================================================================

test_that("full rectification workflow completes successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_rectification_request(
    subject_email = "workflow@example.com",
    subject_name = "Workflow User",
    request_type = "BOTH",
    requested_by = "dpo",
    subject_id = "SUBJ-WORKFLOW",
    db_path = test_db
  )
  expect_true(request$success)

  item1 <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-WORKFLOW",
    field_name = "email",
    current_value = "old@example.com",
    requested_value = "workflow@example.com",
    rectification_type = "CORRECTION",
    added_by = "dpo",
    justification = "Correcting typo in email address",
    db_path = test_db
  )
  expect_true(item1$success)

  item2 <- add_rectification_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-WORKFLOW",
    field_name = "middle_name",
    current_value = NA,
    requested_value = "Alexander",
    rectification_type = "COMPLETION",
    added_by = "dpo",
    justification = "Adding missing middle name",
    db_path = test_db
  )
  expect_true(item2$success)

  review1 <- review_rectification_item(
    item_id = item1$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )
  expect_true(review1$success)

  review2 <- review_rectification_item(
    item_id = item2$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )
  expect_true(review2$success)

  apply1 <- apply_rectification_item(
    item_id = item1$item_id,
    applied_by = "data_manager",
    db_path = test_db
  )
  expect_true(apply1$success)

  apply2 <- apply_rectification_item(
    item_id = item2$item_id,
    applied_by = "data_manager",
    db_path = test_db
  )
  expect_true(apply2$success)

  recipient <- add_third_party_recipient(
    request_id = request$request_id,
    recipient_name = "Analytics Partner",
    recipient_type = "PROCESSOR",
    data_shared = "Subject email",
    added_by = "dpo",
    contact_email = "privacy@analytics.example.com",
    db_path = test_db
  )
  expect_true(recipient$success)

  notification <- send_third_party_notification(
    recipient_id = recipient$recipient_id,
    notification_method = "EMAIL",
    sent_by = "dpo",
    notification_content = "Data has been rectified per GDPR Article 19",
    db_path = test_db
  )
  expect_true(notification$success)

  ack <- record_third_party_acknowledgment(
    recipient_id = recipient$recipient_id,
    recorded_by = "dpo",
    db_path = test_db
  )
  expect_true(ack$success)

  complete <- complete_rectification_request(
    request_id = request$request_id,
    completed_by = "admin",
    db_path = test_db
  )
  expect_true(complete$success)
  expect_equal(complete$items_applied, 2)

  final_request <- get_rectification_request(
    request_id = request$request_id,
    db_path = test_db
  )
  expect_equal(final_request$status, "COMPLETED")

  history <- get_rectification_history(request$request_id, db_path = test_db)
  expect_gte(nrow(history), 5)

  stats <- get_rectification_statistics(db_path = test_db)
  expect_equal(stats$requests$completed, 1)
  expect_equal(stats$items$applied, 2)
  expect_equal(stats$third_party$notified, 1)
  expect_equal(stats$third_party$acknowledged, 1)
})

test_that("hash chain integrity maintained across operations", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  req1 <- create_rectification_request(
    subject_email = "hash1@example.com",
    subject_name = "Hash User 1",
    request_type = "CORRECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  req2 <- create_rectification_request(
    subject_email = "hash2@example.com",
    subject_name = "Hash User 2",
    request_type = "COMPLETION",
    requested_by = "dpo",
    db_path = test_db
  )

  req3 <- create_rectification_request(
    subject_email = "hash3@example.com",
    subject_name = "Hash User 3",
    request_type = "BOTH",
    requested_by = "dpo",
    db_path = test_db
  )

  r1 <- get_rectification_request(request_id = req1$request_id, db_path = test_db)
  r2 <- get_rectification_request(request_id = req2$request_id, db_path = test_db)
  r3 <- get_rectification_request(request_id = req3$request_id, db_path = test_db)

  expect_equal(r1$previous_hash, "GENESIS")
  expect_equal(r2$previous_hash, r1$request_hash)
  expect_equal(r3$previous_hash, r2$request_hash)

  expect_true(nchar(r1$request_hash) == 64)
  expect_true(nchar(r2$request_hash) == 64)
  expect_true(nchar(r3$request_hash) == 64)
})
