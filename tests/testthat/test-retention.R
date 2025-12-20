# test-retention.R
# Test suite for GDPR Article 5(1)(e) Data Retention Enforcement

# ============================================================================
# TEST SETUP
# ============================================================================

setup_test_db <- function() {
  test_dir <- tempdir()
  test_db <- file.path(test_dir, paste0("test_retention_", Sys.getpid(), ".db"))

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

  retention_result <- init_retention()
  if (!isTRUE(retention_result$success)) {
    stop("Failed to initialize retention: ", retention_result$error)
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

test_that("init_retention creates all required tables", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  tables <- DBI::dbListTables(con)
  expect_true("retention_policies" %in% tables)
  expect_true("retention_records" %in% tables)
  expect_true("retention_reviews" %in% tables)
  expect_true("retention_actions" %in% tables)
  expect_true("retention_schedules" %in% tables)
})

# ============================================================================
# REFERENCE DATA TESTS
# ============================================================================

test_that("get_retention_bases returns valid bases", {
  bases <- get_retention_bases()
  expect_type(bases, "character")
  expect_true("LEGAL_REQUIREMENT" %in% names(bases))
  expect_true("CONTRACT" %in% names(bases))
  expect_true("CONSENT" %in% names(bases))
})

test_that("get_retention_actions returns valid actions", {
  action_types <- get_retention_actions()
  expect_type(action_types, "character")
  expect_true("DELETE" %in% names(action_types))
  expect_true("ANONYMIZE" %in% names(action_types))
  expect_true("ARCHIVE" %in% names(action_types))
})

test_that("get_retention_statuses returns valid statuses", {
  statuses <- get_retention_statuses()
  expect_type(statuses, "character")
  expect_true("ACTIVE" %in% names(statuses))
  expect_true("EXPIRED" %in% names(statuses))
  expect_true("DELETED" %in% names(statuses))
})

test_that("get_retention_data_categories returns valid categories", {
  categories <- get_retention_data_categories()
  expect_type(categories, "character")
  expect_true("HEALTH" %in% names(categories))
  expect_true("CONTACT" %in% names(categories))
  expect_true("AUDIT" %in% names(categories))
})

test_that("get_review_types returns valid types", {
  types <- get_review_types()
  expect_type(types, "character")
  expect_true("SCHEDULED" %in% names(types))
  expect_true("MANUAL" %in% names(types))
})

# ============================================================================
# POLICY MANAGEMENT TESTS
# ============================================================================

test_that("create_retention_policy creates policy", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_retention_policy(
    policy_code = "HEALTH_7Y",
    policy_name = "Health Data 7 Year Retention",
    data_category = "HEALTH",
    retention_period_days = 2555,
    retention_basis = "LEGAL_REQUIREMENT",
    created_by = "admin",
    legal_reference = "HIPAA Section 164.530(j)",
    description = "Medical records must be retained for 7 years"
  )

  expect_true(result$success)
  expect_true(!is.null(result$policy_id))
  expect_equal(result$policy_code, "HEALTH_7Y")
})

test_that("create_retention_policy validates policy_code required", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_retention_policy(
    policy_code = "",
    policy_name = "Test",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("policy_code", result$error))
})

test_that("create_retention_policy validates retention_period_days", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_retention_policy(
    policy_code = "TEST",
    policy_name = "Test",
    data_category = "HEALTH",
    retention_period_days = 0,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("at least 1", result$error))
})

test_that("create_retention_policy validates data_category", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_retention_policy(
    policy_code = "TEST",
    policy_name = "Test",
    data_category = "INVALID",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid data_category", result$error))
})

test_that("create_retention_policy validates retention_basis", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_retention_policy(
    policy_code = "TEST",
    policy_name = "Test",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "INVALID",
    created_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid retention_basis", result$error))
})

test_that("create_retention_policy prevents duplicate codes", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_retention_policy(
    policy_code = "UNIQUE",
    policy_name = "First",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  result <- create_retention_policy(
    policy_code = "UNIQUE",
    policy_name = "Second",
    data_category = "CONTACT",
    retention_period_days = 180,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("already exists", result$error))
})

test_that("get_retention_policies retrieves policies", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_retention_policy(
    policy_code = "POL1",
    policy_name = "Policy One",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "LEGAL_REQUIREMENT",
    created_by = "admin"
  )

  result <- get_retention_policies()

  expect_true(result$success)
  expect_true(result$count >= 1)
  expect_true("POL1" %in% result$policies$policy_code)
})

test_that("update_retention_policy updates policy", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "UPDATE",
    policy_name = "To Update",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  result <- update_retention_policy(
    policy_id = policy$policy_id,
    updated_by = "admin",
    retention_period_days = 730,
    auto_enforce = TRUE
  )

  expect_true(result$success)

  updated <- get_retention_policies()
  updated_policy <- updated$policies[updated$policies$policy_code == "UPDATE", ]
  expect_equal(updated_policy$retention_period_days, 730)
  expect_equal(updated_policy$auto_enforce, 1)
})

# ============================================================================
# RETENTION RECORD TESTS
# ============================================================================

test_that("register_retention_record registers record", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "REG",
    policy_name = "Registration Test",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "LEGAL_REQUIREMENT",
    created_by = "admin"
  )

  result <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "SUBJ-001",
    created_date = Sys.Date() - 30,
    registered_by = "system",
    subject_id = "SUBJ-001"
  )

  expect_true(result$success)
  expect_true(!is.null(result$record_id))

  expected_end <- Sys.Date() - 30 + 365
  expect_equal(result$retention_end_date, format(expected_end, "%Y-%m-%d"))
})

test_that("register_retention_record validates policy exists", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- register_retention_record(
    policy_id = 9999,
    table_name = "subjects",
    record_key = "SUBJ-001",
    created_date = Sys.Date(),
    registered_by = "system"
  )

  expect_false(result$success)
  expect_true(grepl("not found", result$error))
})

test_that("register_retention_record prevents duplicates", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "DUP",
    policy_name = "Duplicate Test",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "SUBJ-DUP",
    created_date = Sys.Date(),
    registered_by = "system"
  )

  result <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "SUBJ-DUP",
    created_date = Sys.Date(),
    registered_by = "system"
  )

  expect_false(result$success)
  expect_true(grepl("already registered", result$error))
})

test_that("register_retention_record creates audit trail", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "AUDIT",
    policy_name = "Audit Test",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "SUBJ-AUD",
    created_date = Sys.Date(),
    registered_by = "system"
  )

  actions <- get_retention_action_history(record$record_id)

  expect_true(actions$success)
  expect_true(actions$count >= 1)
  expect_true("REGISTERED" %in% actions$actions$action_type)
})

# ============================================================================
# EXPIRY AND REVIEW TESTS
# ============================================================================

test_that("get_expired_records returns expired records", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "EXP",
    policy_name = "Expiry Test",
    data_category = "HEALTH",
    retention_period_days = 30,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "OLD-001",
    created_date = Sys.Date() - 60,
    registered_by = "system"
  )

  register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "NEW-001",
    created_date = Sys.Date() - 10,
    registered_by = "system"
  )

  result <- get_expired_records()

  expect_true(result$success)
  expect_true(result$count >= 1)
  expect_true("OLD-001" %in% result$records$record_key)
  expect_false("NEW-001" %in% result$records$record_key)
})

test_that("get_records_expiring_soon returns upcoming expirations", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "SOON",
    policy_name = "Soon Expiring Test",
    data_category = "HEALTH",
    retention_period_days = 20,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "SOON-001",
    created_date = Sys.Date() - 5,
    registered_by = "system"
  )

  result <- get_records_expiring_soon(days_ahead = 30)

  expect_true(result$success)
  expect_true(result$count >= 1)
  expect_true("SOON-001" %in% result$records$record_key)
})

test_that("create_retention_review creates review", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_retention_review(
    review_type = "SCHEDULED",
    review_scope = "Monthly health data review",
    performed_by = "admin"
  )

  expect_true(result$success)
  expect_true(!is.null(result$review_id))
  expect_equal(result$review_type, "SCHEDULED")
})

test_that("create_retention_review validates review_type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_retention_review(
    review_type = "INVALID",
    review_scope = "Test",
    performed_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid review_type", result$error))
})

test_that("complete_retention_review completes review", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  review <- create_retention_review(
    review_type = "MANUAL",
    review_scope = "Ad-hoc review",
    performed_by = "admin"
  )

  result <- complete_retention_review(
    review_id = review$review_id,
    completed_by = "admin",
    review_notes = "Completed successfully"
  )

  expect_true(result$success)
  expect_true(!is.null(result$completed_at))
})

# ============================================================================
# RETENTION ACTION TESTS
# ============================================================================

test_that("delete_retention_record marks as deleted", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "DEL",
    policy_name = "Delete Test",
    data_category = "CONTACT",
    retention_period_days = 30,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "contacts",
    record_key = "DEL-001",
    created_date = Sys.Date() - 60,
    registered_by = "system"
  )

  result <- delete_retention_record(
    record_id = record$record_id,
    deleted_by = "admin",
    deletion_reason = "Retention period expired"
  )

  expect_true(result$success)

  deleted <- get_retention_record(record$record_id)
  expect_equal(deleted$record$status, "DELETED")
})

test_that("delete_retention_record blocks for legal hold", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "HOLD",
    policy_name = "Hold Test",
    data_category = "CONTACT",
    retention_period_days = 30,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "contacts",
    record_key = "HOLD-001",
    created_date = Sys.Date() - 60,
    registered_by = "system"
  )

  apply_legal_hold(
    record_id = record$record_id,
    hold_reason = "Litigation pending",
    held_by = "legal"
  )

  result <- delete_retention_record(
    record_id = record$record_id,
    deleted_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("legal hold", result$error))
})

test_that("anonymize_retention_record marks as anonymized", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "ANON",
    policy_name = "Anonymize Test",
    data_category = "HEALTH",
    retention_period_days = 30,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "health_data",
    record_key = "ANON-001",
    created_date = Sys.Date() - 60,
    registered_by = "system",
    subject_id = "SUBJ-ANON"
  )

  result <- anonymize_retention_record(
    record_id = record$record_id,
    anonymized_by = "admin"
  )

  expect_true(result$success)

  anon <- get_retention_record(record$record_id)
  expect_equal(anon$record$status, "ANONYMIZED")
  expect_true(is.na(anon$record$subject_id))
})

test_that("extend_retention extends period", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "EXT",
    policy_name = "Extend Test",
    data_category = "RESEARCH",
    retention_period_days = 30,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "research",
    record_key = "EXT-001",
    created_date = Sys.Date() - 10,
    registered_by = "system"
  )

  original_end <- as.Date(record$retention_end_date)

  result <- extend_retention(
    record_id = record$record_id,
    extension_days = 90,
    extension_reason = "Ongoing research study",
    extended_by = "researcher"
  )

  expect_true(result$success)

  expected_new_end <- original_end + 90
  expect_equal(result$new_retention_end_date,
               format(expected_new_end, "%Y-%m-%d"))
  expect_equal(result$extension_count, 1)
})

test_that("extend_retention requires reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- extend_retention(
    record_id = 1,
    extension_days = 90,
    extension_reason = "",
    extended_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("extension_reason", result$error))
})

# ============================================================================
# LEGAL HOLD TESTS
# ============================================================================

test_that("apply_legal_hold places hold", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "LH",
    policy_name = "Legal Hold Test",
    data_category = "FINANCIAL",
    retention_period_days = 30,
    retention_basis = "LEGAL_REQUIREMENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "financial",
    record_key = "LH-001",
    created_date = Sys.Date() - 60,
    registered_by = "system"
  )

  result <- apply_legal_hold(
    record_id = record$record_id,
    hold_reason = "SEC investigation",
    held_by = "legal"
  )

  expect_true(result$success)

  held <- get_retention_record(record$record_id)
  expect_equal(held$record$status, "LEGAL_HOLD")
  expect_equal(held$record$legal_hold, 1)
})

test_that("apply_legal_hold requires reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- apply_legal_hold(
    record_id = 1,
    hold_reason = "",
    held_by = "legal"
  )

  expect_false(result$success)
  expect_true(grepl("hold_reason", result$error))
})

test_that("release_retention_hold releases hold", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "REL",
    policy_name = "Release Test",
    data_category = "FINANCIAL",
    retention_period_days = 365,
    retention_basis = "LEGAL_REQUIREMENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "financial",
    record_key = "REL-001",
    created_date = Sys.Date() - 10,
    registered_by = "system"
  )

  apply_legal_hold(
    record_id = record$record_id,
    hold_reason = "Investigation",
    held_by = "legal"
  )

  result <- release_retention_hold(
    record_id = record$record_id,
    released_by = "legal",
    release_reason = "Investigation concluded"
  )

  expect_true(result$success)
  expect_equal(result$new_status, "ACTIVE")

  released <- get_retention_record(record$record_id)
  expect_equal(released$record$legal_hold, 0)
})

# ============================================================================
# RETRIEVAL TESTS
# ============================================================================

test_that("get_retention_record retrieves record", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "GET",
    policy_name = "Get Test",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "GET-001",
    created_date = Sys.Date(),
    registered_by = "system"
  )

  result <- get_retention_record(record$record_id)

  expect_true(result$success)
  expect_equal(result$record$record_key, "GET-001")
  expect_equal(result$record$policy_code, "GET")
})

test_that("get_subject_retention_records retrieves subject records", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "SUBJ",
    policy_name = "Subject Test",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  register_retention_record(
    policy_id = policy$policy_id,
    table_name = "health",
    record_key = "REC-001",
    created_date = Sys.Date(),
    registered_by = "system",
    subject_id = "SUBJ-TEST"
  )

  register_retention_record(
    policy_id = policy$policy_id,
    table_name = "health",
    record_key = "REC-002",
    created_date = Sys.Date(),
    registered_by = "system",
    subject_id = "SUBJ-TEST"
  )

  result <- get_subject_retention_records(subject_id = "SUBJ-TEST")

  expect_true(result$success)
  expect_equal(result$count, 2)
})

# ============================================================================
# STATISTICS TESTS
# ============================================================================

test_that("get_retention_statistics returns stats", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "STATS",
    policy_name = "Stats Test",
    data_category = "HEALTH",
    retention_period_days = 365,
    retention_basis = "CONSENT",
    created_by = "admin"
  )

  register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "STAT-001",
    created_date = Sys.Date(),
    registered_by = "system"
  )

  result <- get_retention_statistics()

  expect_true(result$success)
  expect_true(!is.null(result$policies))
  expect_true(!is.null(result$records))
  expect_true(result$policies$total >= 1)
  expect_true(result$records$total >= 1)
})

# ============================================================================
# REPORT GENERATION TESTS
# ============================================================================

test_that("generate_retention_report creates TXT report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  output_file <- tempfile(fileext = ".txt")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_retention_report(
    output_file = output_file,
    format = "txt",
    organization = "Test Organization",
    prepared_by = "Test DPO"
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))

  content <- readLines(output_file)
  expect_true(any(grepl("GDPR ARTICLE 5", content)))
  expect_true(any(grepl("Test Organization", content)))
})

test_that("generate_retention_report creates JSON report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  output_file <- tempfile(fileext = ".json")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_retention_report(
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

test_that("full retention lifecycle completes", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "LIFECYCLE",
    policy_name = "Lifecycle Test",
    data_category = "HEALTH",
    retention_period_days = 30,
    retention_basis = "LEGAL_REQUIREMENT",
    created_by = "admin",
    action_on_expiry = "DELETE"
  )
  expect_true(policy$success)

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "subjects",
    record_key = "LC-001",
    created_date = Sys.Date() - 60,
    registered_by = "system",
    subject_id = "SUBJ-LC"
  )
  expect_true(record$success)

  expired <- get_expired_records()
  expect_true(expired$count >= 1)
  expect_true("LC-001" %in% expired$records$record_key)

  review <- create_retention_review(
    review_type = "SCHEDULED",
    review_scope = "Monthly retention review",
    performed_by = "dpo"
  )
  expect_true(review$success)

  deletion <- delete_retention_record(
    record_id = record$record_id,
    deleted_by = "dpo",
    review_id = review$review_id,
    deletion_reason = "Retention period expired"
  )
  expect_true(deletion$success)

  completed <- complete_retention_review(
    review_id = review$review_id,
    completed_by = "dpo",
    review_notes = "1 record deleted"
  )
  expect_true(completed$success)
  expect_equal(completed$records_deleted, 1)

  final <- get_retention_record(record$record_id)
  expect_equal(final$record$status, "DELETED")

  actions <- get_retention_action_history(record$record_id)
  expect_true(actions$count >= 2)
  expect_true("REGISTERED" %in% actions$actions$action_type)
  expect_true("DELETED" %in% actions$actions$action_type)
})

test_that("legal hold blocks all destructive actions", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "HOLDBLOCK",
    policy_name = "Hold Block Test",
    data_category = "FINANCIAL",
    retention_period_days = 30,
    retention_basis = "LEGAL_REQUIREMENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "financial",
    record_key = "HB-001",
    created_date = Sys.Date() - 60,
    registered_by = "system"
  )

  hold <- apply_legal_hold(
    record_id = record$record_id,
    hold_reason = "Regulatory investigation",
    held_by = "legal"
  )
  expect_true(hold$success)

  delete_attempt <- delete_retention_record(
    record_id = record$record_id,
    deleted_by = "admin"
  )
  expect_false(delete_attempt$success)

  anon_attempt <- anonymize_retention_record(
    record_id = record$record_id,
    anonymized_by = "admin"
  )
  expect_false(anon_attempt$success)

  release <- release_retention_hold(
    record_id = record$record_id,
    released_by = "legal",
    release_reason = "Investigation concluded"
  )
  expect_true(release$success)

  delete_after <- delete_retention_record(
    record_id = record$record_id,
    deleted_by = "admin"
  )
  expect_true(delete_after$success)
})

test_that("hash chain integrity for retention actions", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  policy <- create_retention_policy(
    policy_code = "HASH",
    policy_name = "Hash Test",
    data_category = "AUDIT",
    retention_period_days = 365,
    retention_basis = "LEGAL_REQUIREMENT",
    created_by = "admin"
  )

  record <- register_retention_record(
    policy_id = policy$policy_id,
    table_name = "audit",
    record_key = "HASH-001",
    created_date = Sys.Date(),
    registered_by = "system"
  )

  extend_retention(
    record_id = record$record_id,
    extension_days = 30,
    extension_reason = "Extended for review",
    extended_by = "admin"
  )

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  actions <- DBI::dbGetQuery(con, "
    SELECT action_id, action_hash, previous_action_hash
    FROM retention_actions
    WHERE record_id = ?
    ORDER BY action_id
  ", params = list(record$record_id))

  expect_equal(nrow(actions), 2)

  expect_equal(actions$previous_action_hash[2], actions$action_hash[1])
})
