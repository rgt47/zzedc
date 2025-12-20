# test-portability.R
# Test suite for GDPR Article 20 Right to Data Portability

# ============================================================================
# TEST SETUP
# ============================================================================

setup_test_db <- function() {
  test_dir <- tempdir()
  test_db <- file.path(test_dir, paste0("test_port_", Sys.getpid(), ".db"))

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

  port_result <- init_portability()
  if (!isTRUE(port_result$success)) {
    stop("Failed to initialize portability: ", port_result$error)
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

test_that("init_portability creates all required tables", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  tables <- DBI::dbListTables(con)

  expect_true("portability_requests" %in% tables)
  expect_true("portability_datasets" %in% tables)
  expect_true("portability_exports" %in% tables)
  expect_true("portability_transfers" %in% tables)
  expect_true("portability_history" %in% tables)
})

test_that("init_portability is idempotent", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- init_portability()
  expect_true(result$success)
})

# ============================================================================
# REFERENCE DATA TESTS
# ============================================================================

test_that("get_portability_request_types returns valid types", {
  types <- get_portability_request_types()

  expect_type(types, "character")
  expect_true("RECEIVE" %in% names(types))
  expect_true("TRANSMIT" %in% names(types))
  expect_true("BOTH" %in% names(types))
})

test_that("get_portability_legal_bases returns valid bases", {
  bases <- get_portability_legal_bases()

  expect_type(bases, "character")
  expect_true("CONSENT" %in% names(bases))
  expect_true("CONTRACT" %in% names(bases))
})

test_that("get_portability_export_formats returns valid formats", {
  formats <- get_portability_export_formats()

  expect_type(formats, "character")
  expect_true("JSON" %in% names(formats))
  expect_true("CSV" %in% names(formats))
  expect_true("XML" %in% names(formats))
  expect_true("XLSX" %in% names(formats))
})

test_that("get_portability_statuses returns valid statuses", {
  statuses <- get_portability_statuses()

  expect_type(statuses, "character")
  expect_true("RECEIVED" %in% names(statuses))
  expect_true("EXPORTED" %in% names(statuses))
  expect_true("COMPLETED" %in% names(statuses))
})

test_that("get_transfer_methods returns valid methods", {
  methods <- get_transfer_methods()

  expect_type(methods, "character")
  expect_true("SECURE_EMAIL" %in% names(methods))
  expect_true("API" %in% names(methods))
})

test_that("get_portability_exceptions returns valid exceptions", {
  exceptions <- get_portability_exceptions()

  expect_type(exceptions, "character")
  expect_true("RIGHTS_OF_OTHERS" %in% names(exceptions))
  expect_true("NOT_PROVIDED_BY_SUBJECT" %in% names(exceptions))
})

test_that("get_data_source_types returns valid sources", {
  sources <- get_data_source_types()

  expect_type(sources, "character")
  expect_true("PROVIDED" %in% names(sources))
  expect_true("OBSERVED" %in% names(sources))
  expect_true("DERIVED" %in% names(sources))
})

# ============================================================================
# REQUEST CREATION TESTS
# ============================================================================

test_that("create_portability_request creates RECEIVE request", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  expect_true(result$success)
  expect_true(!is.null(result$request_id))
  expect_true(grepl("^PORT-", result$request_number))
  expect_equal(result$status, "RECEIVED")
})

test_that("create_portability_request requires target for TRANSMIT", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "TRANSMIT",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("target_controller", result$error))
})

test_that("create_portability_request creates TRANSMIT request with target", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "TRANSMIT",
    legal_basis = "CONTRACT",
    requested_by = "dpo",
    target_controller = "Other Company",
    target_controller_contact = "dpo@other.com"
  )

  expect_true(result$success)
  expect_equal(result$status, "RECEIVED")
})

test_that("create_portability_request validates legal basis", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "INVALID",
    requested_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid legal_basis", result$error))
})

test_that("create_portability_request sets 30-day due date", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  expect_true(result$success)
  expected_due <- format(Sys.Date() + 30, "%Y-%m-%d")
  expect_equal(result$due_date, expected_due)
})

test_that("create_portability_request logs action", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  result <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  history <- get_portability_history(request_id = result$request_id)
  expect_true(any(history$history$action == "REQUEST_CREATED"))
})

# ============================================================================
# DATASET MANAGEMENT TESTS
# ============================================================================

test_that("add_portability_dataset adds eligible dataset", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo",
    record_count = 10
  )

  expect_true(result$success)
  expect_true(result$is_eligible)
  expect_true(!is.null(result$dataset_id))
})

test_that("add_portability_dataset marks derived data ineligible", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "risk_scores",
    data_category = "ANALYTICS",
    data_source = "DERIVED",
    added_by = "dpo"
  )

  expect_true(result$success)
  expect_false(result$is_eligible)
  expect_true(grepl("Derived", result$ineligibility_reason))
})

test_that("add_portability_dataset validates data source", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "INVALID",
    added_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid data_source", result$error))
})

test_that("review_portability_dataset updates eligibility", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  dataset <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo"
  )

  result <- review_portability_dataset(
    dataset_id = dataset$dataset_id,
    is_eligible = TRUE,
    reviewed_by = "admin"
  )

  expect_true(result$success)
  expect_equal(result$status, "APPROVED")
})

test_that("review_portability_dataset requires reason for ineligible", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  dataset <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo"
  )

  result <- review_portability_dataset(
    dataset_id = dataset$dataset_id,
    is_eligible = FALSE,
    reviewed_by = "admin"
  )

  expect_false(result$success)
  expect_true(grepl("ineligibility_reason required", result$error))
})

# ============================================================================
# EXPORT GENERATION TESTS
# ============================================================================

test_that("generate_portability_export creates JSON export", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  dataset <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo",
    record_count = 5
  )

  review_portability_dataset(
    dataset_id = dataset$dataset_id,
    is_eligible = TRUE,
    reviewed_by = "admin"
  )

  output_dir <- tempdir()
  result <- generate_portability_export(
    request_id = request$request_id,
    export_format = "JSON",
    generated_by = "dpo",
    output_dir = output_dir
  )

  expect_true(result$success)
  expect_true(!is.null(result$export_id))
  expect_true(file.exists(result$file_path))
  expect_true(!is.null(result$checksum))

  unlink(result$file_path)
})

test_that("generate_portability_export creates CSV export", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  dataset <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo",
    record_count = 5
  )

  review_portability_dataset(
    dataset_id = dataset$dataset_id,
    is_eligible = TRUE,
    reviewed_by = "admin"
  )

  output_dir <- tempdir()
  result <- generate_portability_export(
    request_id = request$request_id,
    export_format = "CSV",
    generated_by = "dpo",
    output_dir = output_dir
  )

  expect_true(result$success)
  expect_true(grepl("\\.csv$", result$file_name))

  unlink(result$file_path)
})

test_that("generate_portability_export requires eligible datasets", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  output_dir <- tempdir()
  result <- generate_portability_export(
    request_id = request$request_id,
    export_format = "JSON",
    generated_by = "dpo",
    output_dir = output_dir
  )

  expect_false(result$success)
  expect_true(grepl("No eligible datasets", result$error))
})

test_that("record_export_download increments count", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  dataset <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo",
    record_count = 5
  )

  review_portability_dataset(
    dataset_id = dataset$dataset_id,
    is_eligible = TRUE,
    reviewed_by = "admin"
  )

  output_dir <- tempdir()
  export <- generate_portability_export(
    request_id = request$request_id,
    export_format = "JSON",
    generated_by = "dpo",
    output_dir = output_dir
  )

  result <- record_export_download(
    export_id = export$export_id,
    downloaded_by = "subject"
  )

  expect_true(result$success)
  expect_equal(result$download_count, 1)

  result2 <- record_export_download(
    export_id = export$export_id,
    downloaded_by = "subject"
  )
  expect_equal(result2$download_count, 2)

  unlink(export$file_path)
})

# ============================================================================
# TRANSFER TESTS
# ============================================================================

test_that("initiate_controller_transfer creates transfer", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "TRANSMIT",
    legal_basis = "CONSENT",
    requested_by = "dpo",
    target_controller = "Other Company",
    target_controller_contact = "dpo@other.com"
  )

  result <- initiate_controller_transfer(
    request_id = request$request_id,
    export_id = NULL,
    target_controller = "Other Company",
    target_contact = "dpo@other.com",
    transfer_method = "SECURE_EMAIL",
    initiated_by = "dpo"
  )

  expect_true(result$success)
  expect_true(!is.null(result$transfer_id))
  expect_equal(result$transfer_status, "INITIATED")
})

test_that("initiate_controller_transfer validates method", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "TRANSMIT",
    legal_basis = "CONSENT",
    requested_by = "dpo",
    target_controller = "Other Company",
    target_controller_contact = "dpo@other.com"
  )

  result <- initiate_controller_transfer(
    request_id = request$request_id,
    export_id = NULL,
    target_controller = "Other Company",
    target_contact = "dpo@other.com",
    transfer_method = "INVALID_METHOD",
    initiated_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid transfer_method", result$error))
})

test_that("initiate_controller_transfer requires TRANSMIT type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- initiate_controller_transfer(
    request_id = request$request_id,
    export_id = NULL,
    target_controller = "Other Company",
    target_contact = "dpo@other.com",
    transfer_method = "SECURE_EMAIL",
    initiated_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("not include transmission", result$error))
})

test_that("complete_controller_transfer completes transfer", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "TRANSMIT",
    legal_basis = "CONSENT",
    requested_by = "dpo",
    target_controller = "Other Company",
    target_controller_contact = "dpo@other.com"
  )

  transfer <- initiate_controller_transfer(
    request_id = request$request_id,
    export_id = NULL,
    target_controller = "Other Company",
    target_contact = "dpo@other.com",
    transfer_method = "SECURE_EMAIL",
    initiated_by = "dpo"
  )

  result <- complete_controller_transfer(
    transfer_id = transfer$transfer_id,
    completed_by = "dpo",
    confirmation_reference = "REF-12345"
  )

  expect_true(result$success)
  expect_true(!is.null(result$completed_at))
})

test_that("fail_controller_transfer records failure", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "TRANSMIT",
    legal_basis = "CONSENT",
    requested_by = "dpo",
    target_controller = "Other Company",
    target_controller_contact = "dpo@other.com"
  )

  transfer <- initiate_controller_transfer(
    request_id = request$request_id,
    export_id = NULL,
    target_controller = "Other Company",
    target_contact = "dpo@other.com",
    transfer_method = "API",
    initiated_by = "dpo"
  )

  result <- fail_controller_transfer(
    transfer_id = transfer$transfer_id,
    failure_reason = "Target API unavailable",
    failed_by = "dpo"
  )

  expect_true(result$success)
})

# ============================================================================
# REQUEST COMPLETION TESTS
# ============================================================================

test_that("complete_portability_request completes RECEIVE request", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  dataset <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo",
    record_count = 5
  )

  review_portability_dataset(
    dataset_id = dataset$dataset_id,
    is_eligible = TRUE,
    reviewed_by = "admin"
  )

  output_dir <- tempdir()
  export <- generate_portability_export(
    request_id = request$request_id,
    export_format = "JSON",
    generated_by = "dpo",
    output_dir = output_dir
  )

  result <- complete_portability_request(
    request_id = request$request_id,
    completed_by = "dpo"
  )

  expect_true(result$success)
  expect_equal(result$status, "COMPLETED")

  unlink(export$file_path)
})

test_that("complete_portability_request requires export", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- complete_portability_request(
    request_id = request$request_id,
    completed_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("No exports", result$error))
})

test_that("complete_portability_request requires completed transfer for TRANSMIT", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "TRANSMIT",
    legal_basis = "CONSENT",
    requested_by = "dpo",
    target_controller = "Other Company",
    target_controller_contact = "dpo@other.com"
  )

  dataset <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo",
    record_count = 5
  )

  review_portability_dataset(
    dataset_id = dataset$dataset_id,
    is_eligible = TRUE,
    reviewed_by = "admin"
  )

  output_dir <- tempdir()
  export <- generate_portability_export(
    request_id = request$request_id,
    export_format = "JSON",
    generated_by = "dpo",
    output_dir = output_dir
  )

  result <- complete_portability_request(
    request_id = request$request_id,
    completed_by = "dpo"
  )

  expect_false(result$success)
  expect_true(grepl("No transfer initiated", result$error))

  unlink(export$file_path)
})

# ============================================================================
# REJECT REQUEST TESTS
# ============================================================================

test_that("reject_portability_request rejects with reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- reject_portability_request(
    request_id = request$request_id,
    rejection_reason = "Processing not based on consent or contract - legitimate interest basis",
    rejected_by = "legal",
    exception_ground = "WRONG_LEGAL_BASIS"
  )

  expect_true(result$success)
  expect_equal(result$status, "REJECTED")
})

test_that("reject_portability_request requires minimum reason length", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- reject_portability_request(
    request_id = request$request_id,
    rejection_reason = "No",
    rejected_by = "legal"
  )

  expect_false(result$success)
  expect_true(grepl("20 characters", result$error))
})

test_that("reject_portability_request validates exception ground", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- reject_portability_request(
    request_id = request$request_id,
    rejection_reason = "Processing not based on consent or contract",
    rejected_by = "legal",
    exception_ground = "INVALID_EXCEPTION"
  )

  expect_false(result$success)
  expect_true(grepl("Invalid exception_ground", result$error))
})

# ============================================================================
# RETRIEVAL TESTS
# ============================================================================

test_that("get_portability_request retrieves by ID", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  created <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- get_portability_request(request_id = created$request_id)

  expect_true(result$success)
  expect_equal(result$request$subject_email[1], "john@example.com")
})

test_that("get_portability_request retrieves by number", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  created <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  result <- get_portability_request(request_number = created$request_number)

  expect_true(result$success)
  expect_equal(result$request$request_id[1], created$request_id)
})

test_that("get_portability_datasets filters by eligibility", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo"
  )

  add_portability_dataset(
    request_id = request$request_id,
    table_name = "risk_scores",
    data_category = "ANALYTICS",
    data_source = "DERIVED",
    added_by = "dpo"
  )

  all_datasets <- get_portability_datasets(request_id = request$request_id)
  expect_equal(all_datasets$count, 2)

  eligible <- get_portability_datasets(
    request_id = request$request_id,
    eligible_only = TRUE
  )
  expect_equal(eligible$count, 1)
})

test_that("get_pending_portability_requests returns pending", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  create_portability_request(
    subject_email = "jane@example.com",
    subject_name = "Jane Doe",
    request_type = "RECEIVE",
    legal_basis = "CONTRACT",
    requested_by = "dpo"
  )

  result <- get_pending_portability_requests()

  expect_true(result$success)
  expect_equal(result$count, 2)
})

# ============================================================================
# STATISTICS TESTS
# ============================================================================

test_that("get_portability_statistics returns comprehensive stats", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo"
  )

  result <- get_portability_statistics()

  expect_true(result$success)
  expect_true(!is.null(result$requests))
  expect_true(!is.null(result$datasets))
  expect_true(!is.null(result$by_type))
})

# ============================================================================
# REPORT GENERATION TESTS
# ============================================================================

test_that("generate_portability_report creates TXT report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  output_file <- tempfile(fileext = ".txt")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_portability_report(
    output_file = output_file,
    format = "txt",
    organization = "Test Organization",
    prepared_by = "Test DPO"
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))

  content <- readLines(output_file)
  expect_true(any(grepl("GDPR ARTICLE 20", content)))
})

test_that("generate_portability_report creates JSON report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  output_file <- tempfile(fileext = ".json")
  on.exit(unlink(output_file), add = TRUE)

  result <- generate_portability_report(
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

test_that("full RECEIVE portability workflow completes successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo",
    subject_id = "SUBJ-001",
    preferred_format = "JSON"
  )
  expect_true(request$success)

  dataset1 <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo",
    record_count = 10
  )
  expect_true(dataset1$success)
  expect_true(dataset1$is_eligible)

  dataset2 <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "risk_scores",
    data_category = "ANALYTICS",
    data_source = "DERIVED",
    added_by = "dpo",
    record_count = 5
  )
  expect_true(dataset2$success)
  expect_false(dataset2$is_eligible)

  review1 <- review_portability_dataset(
    dataset_id = dataset1$dataset_id,
    is_eligible = TRUE,
    reviewed_by = "admin"
  )
  expect_true(review1$success)

  output_dir <- tempdir()
  export <- generate_portability_export(
    request_id = request$request_id,
    export_format = "JSON",
    generated_by = "dpo",
    output_dir = output_dir
  )
  expect_true(export$success)
  expect_true(file.exists(export$file_path))
  expect_equal(export$record_count, 10)

  download <- record_export_download(
    export_id = export$export_id,
    downloaded_by = "subject"
  )
  expect_true(download$success)

  complete <- complete_portability_request(
    request_id = request$request_id,
    completed_by = "dpo"
  )
  expect_true(complete$success)
  expect_equal(complete$status, "COMPLETED")

  history <- get_portability_history(request_id = request$request_id)
  expect_true(history$count >= 5)

  unlink(export$file_path)
})

test_that("full TRANSMIT portability workflow completes successfully", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "TRANSMIT",
    legal_basis = "CONTRACT",
    requested_by = "dpo",
    subject_id = "SUBJ-001",
    target_controller = "New Provider",
    target_controller_contact = "dpo@newprovider.com"
  )
  expect_true(request$success)

  dataset <- add_portability_dataset(
    request_id = request$request_id,
    table_name = "subjects",
    data_category = "CONTACT",
    data_source = "PROVIDED",
    added_by = "dpo",
    record_count = 10
  )

  review_portability_dataset(
    dataset_id = dataset$dataset_id,
    is_eligible = TRUE,
    reviewed_by = "admin"
  )

  output_dir <- tempdir()
  export <- generate_portability_export(
    request_id = request$request_id,
    export_format = "JSON",
    generated_by = "dpo",
    output_dir = output_dir
  )

  transfer <- initiate_controller_transfer(
    request_id = request$request_id,
    export_id = export$export_id,
    target_controller = "New Provider",
    target_contact = "dpo@newprovider.com",
    transfer_method = "SECURE_EMAIL",
    initiated_by = "dpo"
  )
  expect_true(transfer$success)

  complete_transfer <- complete_controller_transfer(
    transfer_id = transfer$transfer_id,
    completed_by = "dpo",
    confirmation_reference = "REF-2025-001"
  )
  expect_true(complete_transfer$success)

  complete <- complete_portability_request(
    request_id = request$request_id,
    completed_by = "dpo"
  )
  expect_true(complete$success)
  expect_equal(complete$status, "COMPLETED")

  unlink(export$file_path)
})

test_that("rejection workflow works correctly", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_portability_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    request_type = "RECEIVE",
    legal_basis = "CONSENT",
    requested_by = "dpo"
  )

  reject <- reject_portability_request(
    request_id = request$request_id,
    rejection_reason = "Data was not provided by subject - received from employer",
    rejected_by = "legal",
    exception_ground = "NOT_PROVIDED_BY_SUBJECT"
  )

  expect_true(reject$success)
  expect_equal(reject$status, "REJECTED")

  final <- get_portability_request(request_id = request$request_id)
  expect_equal(final$request$status[1], "REJECTED")
  expect_equal(final$request$exception_ground[1], "NOT_PROVIDED_BY_SUBJECT")
})
