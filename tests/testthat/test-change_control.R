# Test Change Control System
# Feature #27

library(testthat)

# Fresh setup for each test
setup_cc_test <- function() {
  Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_change_control_32!")
  initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
  init_audit_logging()
  init_change_control()
}

cleanup_cc_test <- function() {
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) {
    try(unlink(db_path), silent = TRUE)
  }
}

test_that("init_change_control creates tables", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("change_requests" %in% tables)
  expect_true("change_impact_assessment" %in% tables)
  expect_true("change_approvals" %in% tables)
  expect_true("change_implementation" %in% tables)
})

test_that("reference functions return values", {
  expect_true("CRF_MODIFICATION" %in% names(get_change_request_types()))
  expect_true("CRITICAL" %in% names(get_change_categories()))
  expect_true("HIGH" %in% names(get_change_priorities()))
  expect_true("DRAFT" %in% names(get_change_statuses()))
  expect_true("HIGH" %in% names(get_impact_levels()))
})

test_that("create_change_request creates request", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  result <- create_change_request(
    request_title = "Add new field to Demographics",
    request_type = "CRF_MODIFICATION",
    change_category = "MINOR",
    description = "Add occupation field to demographics form",
    requested_by = "data_manager",
    priority = "MEDIUM",
    justification = "Sponsor request for additional data"
  )

  expect_true(result$success)
  expect_true(!is.null(result$request_id))
  expect_true(grepl("^CR-", result$request_number))
})

test_that("create_change_request validates inputs", {
  result <- create_change_request(
    request_title = "",
    request_type = "CRF_MODIFICATION",
    change_category = "MINOR",
    description = "Test",
    requested_by = "user"
  )
  expect_false(result$success)

  setup_cc_test()
  on.exit(cleanup_cc_test())

  result2 <- create_change_request(
    request_title = "Test",
    request_type = "INVALID_TYPE",
    change_category = "MINOR",
    description = "Test",
    requested_by = "user"
  )
  expect_false(result2$success)
})

test_that("submit_change_request submits", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Submit Test",
    request_type = "SYSTEM_CONFIG",
    change_category = "MINOR",
    description = "Test submission",
    requested_by = "user"
  )

  result <- submit_change_request(request$request_id)
  expect_true(result$success)
})

test_that("add_impact_assessment adds assessment", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Impact Test",
    request_type = "CRF_MODIFICATION",
    change_category = "MAJOR",
    description = "Major form change",
    requested_by = "dm"
  )
  submit_change_request(request$request_id)

  result <- add_impact_assessment(
    request_id = request$request_id,
    impact_area = "Data Collection",
    impact_level = "MEDIUM",
    assessed_by = "analyst",
    impact_description = "Affects 3 forms",
    mitigation_strategy = "Phase implementation",
    affected_subjects = 50,
    affected_records = 500
  )

  expect_true(result$success)
})

test_that("add_impact_assessment validates level", {
  result <- add_impact_assessment(
    request_id = 1,
    impact_area = "Test",
    impact_level = "INVALID",
    assessed_by = "analyst"
  )
  expect_false(result$success)
})

test_that("get_impact_assessments retrieves assessments", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Get Impact Test",
    request_type = "CRF_MODIFICATION",
    change_category = "MAJOR",
    description = "Test",
    requested_by = "dm"
  )

  add_impact_assessment(
    request_id = request$request_id,
    impact_area = "Area 1",
    impact_level = "HIGH",
    assessed_by = "analyst"
  )

  result <- get_impact_assessments(request$request_id)
  expect_true(result$success)
  expect_equal(result$count, 1)
})

test_that("add_change_approval adds approval", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Approval Test",
    request_type = "SYSTEM_CONFIG",
    change_category = "MINOR",
    description = "Test approval",
    requested_by = "dm"
  )

  result <- add_change_approval(
    request_id = request$request_id,
    approval_role = "Data Manager",
    approver_name = "John Smith",
    decision = "APPROVE",
    comments = "Approved for implementation"
  )

  expect_true(result$success)
})

test_that("add_change_approval validates decision", {
  result <- add_change_approval(
    request_id = 1,
    approval_role = "DM",
    approver_name = "User",
    decision = "MAYBE"
  )
  expect_false(result$success)
})

test_that("get_change_approvals retrieves approvals", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Get Approval Test",
    request_type = "CRF_MODIFICATION",
    change_category = "MINOR",
    description = "Test",
    requested_by = "dm"
  )

  add_change_approval(
    request_id = request$request_id,
    approval_role = "DM",
    approver_name = "User1",
    decision = "APPROVE"
  )

  result <- get_change_approvals(request$request_id)
  expect_true(result$success)
  expect_equal(result$count, 1)
})

test_that("add_implementation_step adds step", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Implementation Test",
    request_type = "CRF_MODIFICATION",
    change_category = "MINOR",
    description = "Test",
    requested_by = "dm"
  )

  result <- add_implementation_step(
    request_id = request$request_id,
    implementation_step = "Update form definition",
    step_order = 1
  )

  expect_true(result$success)
})

test_that("complete_implementation_step completes step", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Complete Step Test",
    request_type = "SYSTEM_CONFIG",
    change_category = "MINOR",
    description = "Test",
    requested_by = "dm"
  )

  add_implementation_step(
    request_id = request$request_id,
    implementation_step = "Step 1",
    step_order = 1
  )

  con <- connect_encrypted_db()
  impl_id <- DBI::dbGetQuery(con, "
    SELECT implementation_id FROM change_implementation
    ORDER BY implementation_id DESC LIMIT 1
  ")$implementation_id[1]
  DBI::dbDisconnect(con)

  result <- complete_implementation_step(
    implementation_id = impl_id,
    implemented_by = "developer",
    notes = "Completed successfully"
  )

  expect_true(result$success)
})

test_that("verify_implementation_step verifies step", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Verify Step Test",
    request_type = "CRF_MODIFICATION",
    change_category = "MINOR",
    description = "Test",
    requested_by = "dm"
  )

  add_implementation_step(
    request_id = request$request_id,
    implementation_step = "Verify Step",
    step_order = 1
  )

  con <- connect_encrypted_db()
  impl_id <- DBI::dbGetQuery(con, "
    SELECT implementation_id FROM change_implementation
    ORDER BY implementation_id DESC LIMIT 1
  ")$implementation_id[1]
  DBI::dbDisconnect(con)

  complete_implementation_step(impl_id, "developer")

  result <- verify_implementation_step(
    implementation_id = impl_id,
    verified_by = "qa_analyst",
    verification_result = "PASS"
  )

  expect_true(result$success)
})

test_that("verify_implementation_step validates result", {
  result <- verify_implementation_step(
    implementation_id = 1,
    verified_by = "qa",
    verification_result = "MAYBE"
  )
  expect_false(result$success)
})

test_that("get_implementation_status returns status", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Get Impl Status Test",
    request_type = "CRF_MODIFICATION",
    change_category = "MINOR",
    description = "Test",
    requested_by = "dm"
  )

  add_implementation_step(request$request_id, "Step 1", 1)
  add_implementation_step(request$request_id, "Step 2", 2)

  result <- get_implementation_status(request$request_id)
  expect_true(result$success)
  expect_equal(result$total_steps, 2)
})

test_that("update_change_request_status updates status", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Status Update Test",
    request_type = "SYSTEM_CONFIG",
    change_category = "MINOR",
    description = "Test",
    requested_by = "dm"
  )

  result <- update_change_request_status(request$request_id, "IN_PROGRESS")
  expect_true(result$success)
})

test_that("update_change_request_status validates status", {
  result <- update_change_request_status(1, "INVALID_STATUS")
  expect_false(result$success)
})

test_that("get_change_requests retrieves requests", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  result <- get_change_requests()
  expect_true(result$success)
  expect_true("requests" %in% names(result))
})

test_that("get_change_requests filters by status", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  create_change_request(
    request_title = "Filter Test",
    request_type = "CRF_MODIFICATION",
    change_category = "MINOR",
    description = "Test",
    requested_by = "dm"
  )

  result <- get_change_requests(status = "DRAFT")
  expect_true(result$success)
})

test_that("get_change_request_details returns full details", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  request <- create_change_request(
    request_title = "Details Test",
    request_type = "CRF_MODIFICATION",
    change_category = "MAJOR",
    description = "Test full details",
    requested_by = "dm"
  )

  add_impact_assessment(
    request_id = request$request_id,
    impact_area = "Data",
    impact_level = "MEDIUM",
    assessed_by = "analyst"
  )

  add_change_approval(
    request_id = request$request_id,
    approval_role = "DM",
    approver_name = "Approver",
    decision = "APPROVE"
  )

  result <- get_change_request_details(request$request_id)
  expect_true(result$success)
  expect_true("request" %in% names(result))
  expect_true("assessments" %in% names(result))
  expect_true("approvals" %in% names(result))
})

test_that("get_change_request_details handles not found", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  result <- get_change_request_details(99999)
  expect_false(result$success)
})

test_that("get_change_control_statistics returns stats", {
  setup_cc_test()
  on.exit(cleanup_cc_test())

  result <- get_change_control_statistics()
  expect_true(result$success)
  expect_true("statistics" %in% names(result))
  expect_true("by_type" %in% names(result))
  expect_true("by_category" %in% names(result))
})
