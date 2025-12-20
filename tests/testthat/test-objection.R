# test-objection.R
# Test suite for GDPR Article 21 Right to Object

setup_test_db <- function() {
  test_dir <- tempdir()
  test_db <- file.path(test_dir, paste0("test_obj_", Sys.getpid(), ".db"))
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_12345678901234567890123")
  Sys.setenv(ZZEDC_DB_PATH = test_db)
  init_result <- initialize_encrypted_database(db_path = test_db)
  audit_result <- init_audit_logging()
  obj_result <- init_objection()
  test_db
}

cleanup_test_db <- function(test_db) {
  if (file.exists(test_db)) try(file.remove(test_db), silent = TRUE)
  Sys.unsetenv("ZZEDC_ENCRYPTION_KEY")
  Sys.unsetenv("ZZEDC_DB_PATH")
}

# INITIALIZATION TESTS
test_that("init_objection creates all required tables", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("objection_requests" %in% tables)
  expect_true("objection_processing_activities" %in% tables)
  expect_true("objection_history" %in% tables)
  expect_true("marketing_preferences" %in% tables)
})

# REFERENCE DATA TESTS
test_that("get_objection_types returns valid types", {
  types <- get_objection_types()
  expect_type(types, "character")
  expect_true("LEGITIMATE_INTEREST" %in% names(types))
  expect_true("DIRECT_MARKETING" %in% names(types))
  expect_true("RESEARCH" %in% names(types))
})

test_that("get_marketing_channels returns valid channels", {
  channels <- get_marketing_channels()
  expect_type(channels, "character")
  expect_true("EMAIL" %in% names(channels))
  expect_true("ALL" %in% names(channels))
})

# REQUEST CREATION TESTS
test_that("create_objection_request creates legitimate interest objection", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  result <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Marketing analytics",
    objection_grounds = "I do not want my data used for analytics purposes",
    requested_by = "dpo"
  )
  expect_true(result$success)
  expect_true(grepl("^OBJ-", result$request_number))
  expect_false(result$is_direct_marketing)
})

test_that("create_objection_request creates direct marketing objection", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  result <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "DIRECT_MARKETING",
    processing_purpose = "Email marketing campaigns",
    objection_grounds = "I do not wish to receive marketing emails",
    requested_by = "dpo"
  )
  expect_true(result$success)
  expect_true(result$is_direct_marketing)
  expect_true(grepl("must stop immediately", result$message))
})

test_that("create_objection_request validates objection type", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  result <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "INVALID_TYPE",
    processing_purpose = "Testing",
    objection_grounds = "Test grounds for objection",
    requested_by = "dpo"
  )
  expect_false(result$success)
  expect_true(grepl("Invalid objection_type", result$error))
})

test_that("create_objection_request requires minimum grounds length", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  result <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Testing",
    objection_grounds = "Short",
    requested_by = "dpo"
  )
  expect_false(result$success)
  expect_true(grepl("10 characters", result$error))
})

# PROCESSING ACTIVITY TESTS
test_that("add_objection_activity adds activity", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics processing",
    requested_by = "dpo"
  )
  result <- add_objection_activity(
    request_id = request$request_id,
    activity_name = "User behavior tracking",
    legal_basis = "LEGITIMATE_INTEREST",
    added_by = "dpo"
  )
  expect_true(result$success)
  expect_true(!is.null(result$activity_id))
})

test_that("stop_processing_activity stops processing", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics processing",
    requested_by = "dpo"
  )
  activity <- add_objection_activity(
    request_id = request$request_id,
    activity_name = "User tracking",
    legal_basis = "LEGITIMATE_INTEREST",
    added_by = "dpo"
  )
  result <- stop_processing_activity(
    activity_id = activity$activity_id,
    stopped_by = "admin"
  )
  expect_true(result$success)
  expect_true(!is.null(result$stopped_at))
})

test_that("resume_processing_activity requires reason", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics processing",
    requested_by = "dpo"
  )
  activity <- add_objection_activity(
    request_id = request$request_id,
    activity_name = "User tracking",
    legal_basis = "LEGITIMATE_INTEREST",
    added_by = "dpo"
  )
  stop_processing_activity(activity_id = activity$activity_id, stopped_by = "admin")
  result <- resume_processing_activity(
    activity_id = activity$activity_id,
    resumed_by = "admin",
    resume_reason = "Short"
  )
  expect_false(result$success)
  expect_true(grepl("20 characters", result$error))
})

test_that("resume_processing_activity blocks for direct marketing", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "DIRECT_MARKETING",
    processing_purpose = "Email marketing",
    objection_grounds = "I do not want marketing emails",
    requested_by = "dpo"
  )
  activity <- add_objection_activity(
    request_id = request$request_id,
    activity_name = "Email campaigns",
    legal_basis = "DIRECT_MARKETING",
    added_by = "dpo"
  )
  stop_processing_activity(activity_id = activity$activity_id, stopped_by = "admin")
  result <- resume_processing_activity(
    activity_id = activity$activity_id,
    resumed_by = "admin",
    resume_reason = "We have compelling business reasons to resume"
  )
  expect_false(result$success)
  expect_true(grepl("absolute", result$error))
})

# MARKETING PREFERENCE TESTS
test_that("opt_out_marketing records opt-out", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  result <- opt_out_marketing(
    subject_email = "john@example.com",
    channel = "EMAIL",
    opted_out_by = "dpo"
  )
  expect_true(result$success)
  expect_equal(result$channels_updated, 1)
})

test_that("opt_out_marketing ALL opts out of all channels", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  result <- opt_out_marketing(
    subject_email = "john@example.com",
    channel = "ALL",
    opted_out_by = "dpo"
  )
  expect_true(result$success)
  expect_true(result$channels_updated > 1)
})

test_that("check_marketing_preference detects opt-out", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  opt_out_marketing(
    subject_email = "john@example.com",
    channel = "EMAIL",
    opted_out_by = "dpo"
  )
  result <- check_marketing_preference(subject_email = "john@example.com")
  expect_true(result$success)
  expect_true(result$opted_out)
  expect_true("EMAIL" %in% result$opted_out_channels)
})

# DECISION TESTS
test_that("uphold_objection upholds and stops processing", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics processing",
    requested_by = "dpo"
  )
  activity <- add_objection_activity(
    request_id = request$request_id,
    activity_name = "User tracking",
    legal_basis = "LEGITIMATE_INTEREST",
    added_by = "dpo"
  )
  result <- uphold_objection(
    request_id = request$request_id,
    upheld_by = "admin"
  )
  expect_true(result$success)
  expect_equal(result$status, "UPHELD")

  activities <- get_objection_activities(request_id = request$request_id)
  expect_equal(activities$activities$processing_stopped[1], 1)
})

test_that("uphold_objection for direct marketing opts out of all channels", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "DIRECT_MARKETING",
    processing_purpose = "Marketing",
    objection_grounds = "No more marketing please",
    requested_by = "dpo"
  )
  uphold_objection(request_id = request$request_id, upheld_by = "admin")

  prefs <- check_marketing_preference(subject_email = "john@example.com")
  expect_true(prefs$opted_out)
  expect_true(length(prefs$opted_out_channels) > 1)
})

test_that("override_objection requires compelling grounds", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics",
    requested_by = "dpo"
  )
  result <- override_objection(
    request_id = request$request_id,
    overridden_by = "admin",
    compelling_grounds = "Short"
  )
  expect_false(result$success)
  expect_true(grepl("50 characters", result$error))
})

test_that("override_objection cannot override direct marketing", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "DIRECT_MARKETING",
    processing_purpose = "Marketing",
    objection_grounds = "No marketing please",
    requested_by = "dpo"
  )
  result <- override_objection(
    request_id = request$request_id,
    overridden_by = "admin",
    compelling_grounds = paste(rep("a", 60), collapse = "")
  )
  expect_false(result$success)
  expect_true(grepl("absolute right", result$error))
})

test_that("reject_objection cannot reject direct marketing", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "DIRECT_MARKETING",
    processing_purpose = "Marketing",
    objection_grounds = "No marketing please",
    requested_by = "dpo"
  )
  result <- reject_objection(
    request_id = request$request_id,
    rejected_by = "admin",
    decision_reason = "We believe marketing is important for our business"
  )
  expect_false(result$success)
  expect_true(grepl("absolute right", result$error))
})

test_that("reject_objection works for non-marketing objections", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Fraud prevention",
    objection_grounds = "I object to fraud prevention processing",
    requested_by = "dpo"
  )
  result <- reject_objection(
    request_id = request$request_id,
    rejected_by = "admin",
    decision_reason = "Fraud prevention is necessary for security of all users"
  )
  expect_true(result$success)
  expect_equal(result$status, "REJECTED")
})

# COMPLETION TESTS
test_that("complete_objection_request requires decision first", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics",
    requested_by = "dpo"
  )
  result <- complete_objection_request(
    request_id = request$request_id,
    completed_by = "admin"
  )
  expect_false(result$success)
  expect_true(grepl("decision", result$error))
})

test_that("complete_objection_request completes after decision", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics",
    requested_by = "dpo"
  )
  uphold_objection(request_id = request$request_id, upheld_by = "admin")
  result <- complete_objection_request(
    request_id = request$request_id,
    completed_by = "dpo"
  )
  expect_true(result$success)
  expect_equal(result$status, "COMPLETED")
})

# RETRIEVAL TESTS
test_that("get_objection_request retrieves by ID", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  created <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics",
    requested_by = "dpo"
  )
  result <- get_objection_request(request_id = created$request_id)
  expect_true(result$success)
  expect_equal(result$request$subject_email[1], "john@example.com")
})

test_that("get_pending_objection_requests returns pending", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Analytics",
    objection_grounds = "I object to analytics",
    requested_by = "dpo"
  )
  result <- get_pending_objection_requests()
  expect_true(result$success)
  expect_equal(result$count, 1)
})

# STATISTICS TESTS
test_that("get_objection_statistics returns stats", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "DIRECT_MARKETING",
    processing_purpose = "Marketing",
    objection_grounds = "No marketing",
    requested_by = "dpo"
  )
  result <- get_objection_statistics()
  expect_true(result$success)
  expect_true(!is.null(result$requests))
  expect_equal(result$requests$direct_marketing, 1)
})

# REPORT TESTS
test_that("generate_objection_report creates TXT report", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))
  output_file <- tempfile(fileext = ".txt")
  on.exit(unlink(output_file), add = TRUE)
  result <- generate_objection_report(
    output_file = output_file,
    format = "txt",
    organization = "Test Org",
    prepared_by = "DPO"
  )
  expect_true(result$success)
  expect_true(file.exists(output_file))
})

# INTEGRATION TEST
test_that("full objection workflow completes", {
  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db))

  request <- create_objection_request(
    subject_email = "john@example.com",
    subject_name = "John Doe",
    objection_type = "LEGITIMATE_INTEREST",
    processing_purpose = "Behavioral analytics and profiling",
    objection_grounds = "I object to my data being used for behavioral analytics and profiling",
    requested_by = "dpo",
    subject_id = "SUBJ-001"
  )
  expect_true(request$success)

  activity <- add_objection_activity(
    request_id = request$request_id,
    activity_name = "User behavior tracking",
    legal_basis = "LEGITIMATE_INTEREST",
    added_by = "dpo",
    activity_description = "Tracking user behavior for personalization"
  )
  expect_true(activity$success)

  uphold <- uphold_objection(
    request_id = request$request_id,
    upheld_by = "admin",
    review_notes = "Valid objection - user has right to object"
  )
  expect_true(uphold$success)

  activities <- get_objection_activities(request_id = request$request_id)
  expect_equal(activities$activities$processing_stopped[1], 1)

  complete <- complete_objection_request(
    request_id = request$request_id,
    completed_by = "dpo"
  )
  expect_true(complete$success)

  history <- get_objection_history(request_id = request$request_id)
  expect_true(history$count >= 4)
})
