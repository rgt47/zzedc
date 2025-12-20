# tests/testthat/test-erasure.R
#
# Test suite for Right to Erasure with Legal Hold (GDPR Article 17)

suppressPackageStartupMessages({
  library(testthat)
  library(DBI)
})

pkg_root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(pkg_root, "R/encryption_utils.R"))
source(file.path(pkg_root, "R/aws_kms_utils.R"))
source(file.path(pkg_root, "R/db_connection.R"))
source(file.path(pkg_root, "R/audit_logging.R"))
source(file.path(pkg_root, "R/erasure.R"))

setup_test_db <- function() {
  test_dir <- tempdir()
  test_db <- file.path(test_dir, paste0("test_erasure_", Sys.getpid(), ".db"))

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

  erasure_result <- init_erasure(db_path = test_db)
  if (!erasure_result$success) {
    stop("Failed to initialize erasure: ", erasure_result$error)
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

test_that("init_erasure creates required tables", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  conn <- connect_encrypted_db(db_path = test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE, after = FALSE)

  tables <- DBI::dbListTables(conn)

  expect_true("erasure_requests" %in% tables)
  expect_true("erasure_items" %in% tables)
  expect_true("legal_holds" %in% tables)
  expect_true("erasure_history" %in% tables)
  expect_true("erasure_third_parties" %in% tables)
})

test_that("init_erasure is idempotent", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result2 <- init_erasure(db_path = test_db)
  expect_true(result2$success)
})


# =============================================================================
# Reference Data Tests
# =============================================================================

test_that("get_erasure_grounds returns valid grounds", {
  grounds <- get_erasure_grounds()

  expect_type(grounds, "list")
  expect_true("NO_LONGER_NECESSARY" %in% names(grounds))
  expect_true("CONSENT_WITHDRAWN" %in% names(grounds))
  expect_true("OBJECTION" %in% names(grounds))
  expect_true("UNLAWFUL_PROCESSING" %in% names(grounds))
  expect_true("LEGAL_OBLIGATION" %in% names(grounds))
  expect_true("CHILD_DATA" %in% names(grounds))
  expect_equal(length(grounds), 6)
})

test_that("get_erasure_statuses returns valid statuses", {
  statuses <- get_erasure_statuses()

  expect_type(statuses, "list")
  expect_true("RECEIVED" %in% names(statuses))
  expect_true("LEGAL_HOLD" %in% names(statuses))
  expect_true("COMPLETED" %in% names(statuses))
  expect_equal(length(statuses), 8)
})

test_that("get_legal_hold_types returns valid types", {
  types <- get_legal_hold_types()

  expect_type(types, "list")
  expect_true("REGULATORY" %in% names(types))
  expect_true("LITIGATION" %in% names(types))
  expect_true("AUDIT" %in% names(types))
  expect_true("INVESTIGATION" %in% names(types))
  expect_true("OTHER" %in% names(types))
  expect_equal(length(types), 5)
})

test_that("get_erasure_methods returns valid methods", {
  methods <- get_erasure_methods()

  expect_type(methods, "list")
  expect_true("DELETE" %in% names(methods))
  expect_true("ANONYMIZE" %in% names(methods))
  expect_true("PSEUDONYMIZE" %in% names(methods))
  expect_equal(length(methods), 3)
})

test_that("get_erasure_exceptions returns valid exceptions", {
  exceptions <- get_erasure_exceptions()

  expect_type(exceptions, "list")
  expect_true("FREE_EXPRESSION" %in% names(exceptions))
  expect_true("LEGAL_OBLIGATION" %in% names(exceptions))
  expect_true("PUBLIC_HEALTH" %in% names(exceptions))
  expect_true("ARCHIVING" %in% names(exceptions))
  expect_true("LEGAL_CLAIMS" %in% names(exceptions))
  expect_equal(length(exceptions), 5)
})


# =============================================================================
# Legal Hold Tests
# =============================================================================

test_that("create_legal_hold creates hold successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA 21 CFR Part 11 retention requirement for clinical trial data",
    legal_basis = "21 CFR Part 11.10(c)",
    created_by = "compliance_officer",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(!is.null(result$hold_id))
  expect_true(grepl("^HOLD-", result$hold_number))
})

test_that("create_legal_hold validates hold type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_legal_hold(
    hold_type = "INVALID",
    hold_reason = "Some reason that is long enough to pass validation",
    legal_basis = "Some basis",
    created_by = "user",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid hold type", result$error))
})

test_that("create_legal_hold requires minimum reason length", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_legal_hold(
    hold_type = "LITIGATION",
    hold_reason = "Too short",
    legal_basis = "Some basis",
    created_by = "user",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("at least 20 characters", result$error))
})

test_that("create_legal_hold with affected subjects and categories", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_legal_hold(
    hold_type = "LITIGATION",
    hold_reason = "Litigation hold for ongoing lawsuit regarding trial conduct",
    legal_basis = "Court order dated 2025-12-01",
    created_by = "legal_counsel",
    affected_subjects = c("SUBJ-001", "SUBJ-002", "SUBJ-003"),
    affected_data_categories = c("HEALTH", "CONTACT"),
    db_path = test_db
  )

  expect_true(result$success)

  holds <- get_active_legal_holds(db_path = test_db)
  expect_equal(nrow(holds), 1)
  expect_true(grepl("SUBJ-001", holds$affected_subjects[1]))
  expect_true(grepl("HEALTH", holds$affected_data_categories[1]))
})

test_that("release_legal_hold releases hold successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  hold <- create_legal_hold(
    hold_type = "AUDIT",
    hold_reason = "External audit requiring data retention for 90 days",
    legal_basis = "Audit engagement letter",
    created_by = "auditor",
    db_path = test_db
  )

  release <- release_legal_hold(
    hold_id = hold$hold_id,
    release_reason = "Audit completed successfully, data retention no longer required",
    released_by = "auditor",
    db_path = test_db
  )

  expect_true(release$success)

  active <- get_active_legal_holds(db_path = test_db)
  expect_equal(nrow(active), 0)
})

test_that("release_legal_hold requires minimum reason length", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  hold <- create_legal_hold(
    hold_type = "AUDIT",
    hold_reason = "External audit requiring data retention",
    legal_basis = "Audit letter",
    created_by = "auditor",
    db_path = test_db
  )

  release <- release_legal_hold(
    hold_id = hold$hold_id,
    release_reason = "Too short",
    released_by = "auditor",
    db_path = test_db
  )

  expect_false(release$success)
  expect_true(grepl("at least 20 characters", release$error))
})

test_that("check_legal_hold detects matching hold", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA data retention requirement for all subjects",
    legal_basis = "21 CFR Part 11",
    created_by = "compliance",
    affected_subjects = "ALL",
    db_path = test_db
  )

  check <- check_legal_hold(
    subject_id = "SUBJ-001",
    db_path = test_db
  )

  expect_true(check$success)
  expect_true(check$is_held)
  expect_equal(length(check$holds), 1)
})

test_that("check_legal_hold returns no match when no hold applies", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_legal_hold(
    hold_type = "LITIGATION",
    hold_reason = "Hold only for specific subjects in lawsuit",
    legal_basis = "Court order",
    created_by = "legal",
    affected_subjects = "SUBJ-999",
    db_path = test_db
  )

  check <- check_legal_hold(
    subject_id = "SUBJ-001",
    db_path = test_db
  )

  expect_true(check$success)
  expect_false(check$is_held)
})


# =============================================================================
# Erasure Request Tests
# =============================================================================

test_that("create_erasure_request creates request successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_erasure_request(
    subject_email = "john.doe@example.com",
    subject_name = "John Doe",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(!is.null(result$request_id))
  expect_true(grepl("^ERASE-", result$request_number))
  expect_equal(result$status, "RECEIVED")
  expect_false(result$is_held)
})

test_that("create_erasure_request validates erasure grounds", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "INVALID_GROUND",
    requested_by = "dpo",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid erasure grounds", result$error))
})

test_that("create_erasure_request detects legal hold", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA data retention requirement for all subjects",
    legal_basis = "21 CFR Part 11",
    created_by = "compliance",
    affected_subjects = "SUBJ-001",
    db_path = test_db
  )

  result <- create_erasure_request(
    subject_email = "john.doe@example.com",
    subject_name = "John Doe",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    subject_id = "SUBJ-001",
    db_path = test_db
  )

  expect_true(result$success)
  expect_equal(result$status, "LEGAL_HOLD")
  expect_true(result$is_held)
})

test_that("create_erasure_request sets 30-day due date", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result <- create_erasure_request(
    subject_email = "jane.doe@example.com",
    subject_name = "Jane Doe",
    erasure_grounds = "NO_LONGER_NECESSARY",
    requested_by = "dpo",
    db_path = test_db
  )

  expect_true(result$success)
  expected_due <- as.character(Sys.Date() + 30)
  expect_equal(result$due_date, expected_due)
})

test_that("create_erasure_request creates hash chain", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  result1 <- create_erasure_request(
    subject_email = "first@example.com",
    subject_name = "First User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  result2 <- create_erasure_request(
    subject_email = "second@example.com",
    subject_name = "Second User",
    erasure_grounds = "OBJECTION",
    requested_by = "dpo",
    db_path = test_db
  )

  req1 <- get_erasure_request(request_id = result1$request_id, db_path = test_db)
  req2 <- get_erasure_request(request_id = result2$request_id, db_path = test_db)

  expect_equal(req1$previous_hash, "GENESIS")
  expect_equal(req2$previous_hash, req1$request_hash)
})


# =============================================================================
# Erasure Item Tests
# =============================================================================

test_that("add_erasure_item adds item successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  expect_true(item$success)
  expect_true(!is.null(item$item_id))
  expect_equal(item$status, "PENDING")
  expect_false(item$is_held)
})

test_that("add_erasure_item validates erasure method", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "INVALID",
    added_by = "dpo",
    db_path = test_db
  )

  expect_false(item$success)
  expect_true(grepl("Invalid erasure method", item$error))
})

test_that("add_erasure_item detects category-based legal hold", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "Health data must be retained for regulatory compliance",
    legal_basis = "FDA regulations",
    created_by = "compliance",
    affected_data_categories = "HEALTH",
    db_path = test_db
  )

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "medical_records",
    record_id = "REC-001",
    data_category = "HEALTH",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  expect_true(item$success)
  expect_equal(item$status, "ON_HOLD")
  expect_true(item$is_held)
})


# =============================================================================
# Item Review Tests
# =============================================================================

test_that("review_erasure_item approves item successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  review <- review_erasure_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  expect_true(review$success)
  expect_equal(review$decision, "APPROVED")

  items <- get_erasure_items(request$request_id, db_path = test_db)
  expect_equal(items$status[1], "APPROVED")
})

test_that("review_erasure_item rejects item with reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "audit_log",
    record_id = "LOG-001",
    data_category = "AUDIT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  review <- review_erasure_item(
    item_id = item$item_id,
    decision = "REJECTED",
    reviewed_by = "admin",
    rejection_reason = "Audit logs must be retained for compliance",
    db_path = test_db
  )

  expect_true(review$success)
  expect_equal(review$decision, "REJECTED")
})

test_that("review_erasure_item blocks review of on-hold items", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "All health data retention required by FDA",
    legal_basis = "FDA regulations",
    created_by = "compliance",
    affected_data_categories = "HEALTH",
    db_path = test_db
  )

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "medical_records",
    record_id = "REC-001",
    data_category = "HEALTH",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  expect_equal(item$status, "ON_HOLD")

  review <- review_erasure_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  expect_false(review$success)
  expect_true(grepl("legal hold", review$error))
})


# =============================================================================
# Execute Erasure Tests
# =============================================================================

test_that("execute_erasure_item executes approved item", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  review_erasure_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  execute <- execute_erasure_item(
    item_id = item$item_id,
    executed_by = "data_manager",
    db_path = test_db
  )

  expect_true(execute$success)
  expect_equal(execute$erasure_method, "DELETE")
  expect_true(nchar(execute$verification_hash) == 64)

  items <- get_erasure_items(request$request_id, db_path = test_db)
  expect_equal(items$status[1], "EXECUTED")
})

test_that("execute_erasure_item rejects unapproved item", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  execute <- execute_erasure_item(
    item_id = item$item_id,
    executed_by = "data_manager",
    db_path = test_db
  )

  expect_false(execute$success)
  expect_true(grepl("must be approved", execute$error))
})


# =============================================================================
# Third Party Tests
# =============================================================================

test_that("add_erasure_third_party adds recipient successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  recipient <- add_erasure_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Corp",
    recipient_type = "PROCESSOR",
    data_shared = "User behavior data",
    added_by = "dpo",
    contact_email = "privacy@analytics.com",
    db_path = test_db
  )

  expect_true(recipient$success)
  expect_true(!is.null(recipient$recipient_id))

  third_parties <- get_erasure_third_parties(request$request_id, db_path = test_db)
  expect_equal(nrow(third_parties), 1)
  expect_equal(third_parties$recipient_name[1], "Analytics Corp")
})

test_that("notify_erasure_third_party records notification", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  recipient <- add_erasure_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Corp",
    recipient_type = "PROCESSOR",
    data_shared = "User data",
    added_by = "dpo",
    db_path = test_db
  )

  notify <- notify_erasure_third_party(
    recipient_id = recipient$recipient_id,
    sent_by = "dpo",
    db_path = test_db
  )

  expect_true(notify$success)

  third_parties <- get_erasure_third_parties(request$request_id, db_path = test_db)
  expect_equal(third_parties$notification_sent[1], 1)
})

test_that("confirm_erasure_third_party records confirmation", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  recipient <- add_erasure_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Corp",
    recipient_type = "PROCESSOR",
    data_shared = "User data",
    added_by = "dpo",
    db_path = test_db
  )

  notify_erasure_third_party(
    recipient_id = recipient$recipient_id,
    sent_by = "dpo",
    db_path = test_db
  )

  confirm <- confirm_erasure_third_party(
    recipient_id = recipient$recipient_id,
    confirmed_by = "dpo",
    db_path = test_db
  )

  expect_true(confirm$success)

  third_parties <- get_erasure_third_parties(request$request_id, db_path = test_db)
  expect_equal(third_parties$erasure_confirmed[1], 1)
})


# =============================================================================
# Request Completion Tests
# =============================================================================

test_that("complete_erasure_request requires all items processed", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  complete <- complete_erasure_request(
    request_id = request$request_id,
    completed_by = "admin",
    db_path = test_db
  )

  expect_false(complete$success)
  expect_true(grepl("pending review", complete$error))
})

test_that("complete_erasure_request completes successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  review_erasure_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )

  execute_erasure_item(
    item_id = item$item_id,
    executed_by = "data_manager",
    db_path = test_db
  )

  complete <- complete_erasure_request(
    request_id = request$request_id,
    completed_by = "admin",
    db_path = test_db
  )

  expect_true(complete$success)
  expect_equal(complete$status, "COMPLETED")
  expect_equal(complete$items_executed, 1)
})


# =============================================================================
# Request Rejection Tests
# =============================================================================

test_that("reject_erasure_request rejects with reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  result <- reject_erasure_request(
    request_id = request$request_id,
    rejection_reason = "Data required for ongoing legal proceedings",
    rejected_by = "legal_counsel",
    exception_ground = "LEGAL_CLAIMS",
    db_path = test_db
  )

  expect_true(result$success)

  req <- get_erasure_request(request_id = request$request_id, db_path = test_db)
  expect_equal(req$status, "REJECTED")
  expect_true(grepl("LEGAL_CLAIMS", req$rejection_reason))
})

test_that("reject_erasure_request validates exception ground", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "test@example.com",
    subject_name = "Test User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  result <- reject_erasure_request(
    request_id = request$request_id,
    rejection_reason = "Some valid rejection reason here",
    rejected_by = "admin",
    exception_ground = "INVALID_EXCEPTION",
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid exception ground", result$error))
})


# =============================================================================
# Retrieval Tests
# =============================================================================

test_that("get_erasure_request retrieves by ID", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create <- create_erasure_request(
    subject_email = "retrieve@example.com",
    subject_name = "Retrieve User",
    erasure_grounds = "NO_LONGER_NECESSARY",
    requested_by = "dpo",
    db_path = test_db
  )

  request <- get_erasure_request(
    request_id = create$request_id,
    db_path = test_db
  )

  expect_equal(nrow(request), 1)
  expect_equal(request$subject_email, "retrieve@example.com")
})

test_that("get_pending_erasure_requests excludes held by default", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_erasure_request(
    subject_email = "pending@example.com",
    subject_name = "Pending User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA data retention requirement",
    legal_basis = "FDA regulations",
    created_by = "compliance",
    affected_subjects = "HELD-001",
    db_path = test_db
  )

  create_erasure_request(
    subject_email = "held@example.com",
    subject_name = "Held User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    subject_id = "HELD-001",
    db_path = test_db
  )

  pending <- get_pending_erasure_requests(db_path = test_db)
  expect_equal(nrow(pending), 1)
  expect_equal(pending$subject_email[1], "pending@example.com")

  all_pending <- get_pending_erasure_requests(include_held = TRUE, db_path = test_db)
  expect_equal(nrow(all_pending), 2)
})

test_that("get_erasure_history retrieves history", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "history@example.com",
    subject_name = "History User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  history <- get_erasure_history(request$request_id, db_path = test_db)
  expect_gte(nrow(history), 2)
  expect_true("REQUEST_CREATED" %in% history$action)
  expect_true("ITEM_ADDED" %in% history$action)
})


# =============================================================================
# Statistics Tests
# =============================================================================

test_that("get_erasure_statistics returns statistics", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_legal_hold(
    hold_type = "AUDIT",
    hold_reason = "Audit hold for compliance review",
    legal_basis = "Audit engagement",
    created_by = "auditor",
    db_path = test_db
  )

  request <- create_erasure_request(
    subject_email = "stats@example.com",
    subject_name = "Stats User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-001",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )

  add_erasure_third_party(
    request_id = request$request_id,
    recipient_name = "Partner",
    recipient_type = "PROCESSOR",
    data_shared = "Data",
    added_by = "dpo",
    db_path = test_db
  )

  stats <- get_erasure_statistics(db_path = test_db)

  expect_true(stats$success)
  expect_equal(stats$requests$total, 1)
  expect_equal(stats$items$total, 1)
  expect_equal(stats$legal_holds$active, 1)
  expect_equal(stats$third_parties$total, 1)
})


# =============================================================================
# Report Generation Tests
# =============================================================================

test_that("generate_erasure_report creates TXT report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_erasure_request(
    subject_email = "report@example.com",
    subject_name = "Report User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )

  report_file <- tempfile(fileext = ".txt")
  on.exit(unlink(report_file), add = TRUE)

  result <- generate_erasure_report(
    output_file = report_file,
    format = "txt",
    organization = "Test Organization",
    prepared_by = "Test DPO",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(report_file))

  content <- readLines(report_file)
  expect_true(any(grepl("ERASURE COMPLIANCE REPORT", content)))
  expect_true(any(grepl("GDPR Article 17", content)))
})

test_that("generate_erasure_report creates JSON report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  create_erasure_request(
    subject_email = "json@example.com",
    subject_name = "JSON User",
    erasure_grounds = "NO_LONGER_NECESSARY",
    requested_by = "dpo",
    db_path = test_db
  )

  report_file <- tempfile(fileext = ".json")
  on.exit(unlink(report_file), add = TRUE)

  result <- generate_erasure_report(
    output_file = report_file,
    format = "json",
    organization = "JSON Organization",
    prepared_by = "JSON DPO",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(report_file))

  content <- jsonlite::read_json(report_file)
  expect_equal(content$report_type, "Erasure Compliance Report")
  expect_true(!is.null(content$statistics))
})


# =============================================================================
# Integration Tests
# =============================================================================

test_that("full erasure workflow completes successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  request <- create_erasure_request(
    subject_email = "workflow@example.com",
    subject_name = "Workflow User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    subject_id = "SUBJ-WORKFLOW",
    db_path = test_db
  )
  expect_true(request$success)

  item1 <- add_erasure_item(
    request_id = request$request_id,
    table_name = "subjects",
    record_id = "SUBJ-WORKFLOW",
    data_category = "CONTACT",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )
  expect_true(item1$success)

  item2 <- add_erasure_item(
    request_id = request$request_id,
    table_name = "preferences",
    record_id = "PREF-001",
    data_category = "PREFERENCES",
    erasure_method = "ANONYMIZE",
    added_by = "dpo",
    db_path = test_db
  )
  expect_true(item2$success)

  review1 <- review_erasure_item(
    item_id = item1$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )
  expect_true(review1$success)

  review2 <- review_erasure_item(
    item_id = item2$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )
  expect_true(review2$success)

  exec1 <- execute_erasure_item(
    item_id = item1$item_id,
    executed_by = "data_manager",
    db_path = test_db
  )
  expect_true(exec1$success)

  exec2 <- execute_erasure_item(
    item_id = item2$item_id,
    executed_by = "data_manager",
    db_path = test_db
  )
  expect_true(exec2$success)

  recipient <- add_erasure_third_party(
    request_id = request$request_id,
    recipient_name = "Analytics Partner",
    recipient_type = "PROCESSOR",
    data_shared = "User contact data",
    added_by = "dpo",
    db_path = test_db
  )
  expect_true(recipient$success)

  notify <- notify_erasure_third_party(
    recipient_id = recipient$recipient_id,
    sent_by = "dpo",
    db_path = test_db
  )
  expect_true(notify$success)

  confirm <- confirm_erasure_third_party(
    recipient_id = recipient$recipient_id,
    confirmed_by = "dpo",
    db_path = test_db
  )
  expect_true(confirm$success)

  complete <- complete_erasure_request(
    request_id = request$request_id,
    completed_by = "admin",
    db_path = test_db
  )
  expect_true(complete$success)
  expect_equal(complete$items_executed, 2)

  final_request <- get_erasure_request(
    request_id = request$request_id,
    db_path = test_db
  )
  expect_equal(final_request$status, "COMPLETED")

  history <- get_erasure_history(request$request_id, db_path = test_db)
  expect_gte(nrow(history), 5)

  stats <- get_erasure_statistics(db_path = test_db)
  expect_equal(stats$requests$completed, 1)
  expect_equal(stats$items$executed, 2)
})

test_that("legal hold blocks erasure workflow", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  hold <- create_legal_hold(
    hold_type = "REGULATORY",
    hold_reason = "FDA clinical trial data retention requirement",
    legal_basis = "21 CFR Part 11.10(c) - 2 year retention after study close",
    created_by = "compliance_officer",
    affected_data_categories = "HEALTH; CLINICAL",
    db_path = test_db
  )
  expect_true(hold$success)

  request <- create_erasure_request(
    subject_email = "held@example.com",
    subject_name = "Held User",
    erasure_grounds = "CONSENT_WITHDRAWN",
    requested_by = "dpo",
    db_path = test_db
  )
  expect_true(request$success)

  item <- add_erasure_item(
    request_id = request$request_id,
    table_name = "clinical_data",
    record_id = "CLIN-001",
    data_category = "CLINICAL",
    erasure_method = "DELETE",
    added_by = "dpo",
    db_path = test_db
  )
  expect_true(item$success)
  expect_equal(item$status, "ON_HOLD")
  expect_true(item$is_held)

  review <- review_erasure_item(
    item_id = item$item_id,
    decision = "APPROVED",
    reviewed_by = "admin",
    db_path = test_db
  )
  expect_false(review$success)

  release <- release_legal_hold(
    hold_id = hold$hold_id,
    release_reason = "Study closed and 2-year retention period completed",
    released_by = "compliance_officer",
    db_path = test_db
  )
  expect_true(release$success)
})
