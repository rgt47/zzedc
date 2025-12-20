# Test Privacy Impact Assessment (PIA) Tool
# Feature #28

library(testthat)

setup_pia_test <- function() {
  Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_privacy_impact_32!")
  initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
  init_audit_logging()
  init_pia_system()
}

cleanup_pia_test <- function() {
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) {
    try(unlink(db_path), silent = TRUE)
  }
}

test_that("init_pia_system creates tables", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("pia_assessments" %in% tables)
  expect_true("pia_processing_purposes" %in% tables)
  expect_true("pia_data_categories" %in% tables)
  expect_true("pia_risk_assessment" %in% tables)
  expect_true("pia_consultations" %in% tables)
})

test_that("reference functions return values", {
  expect_true("DRAFT" %in% names(get_pia_statuses()))
  expect_true("CONSENT" %in% names(get_gdpr_legal_bases()))
  expect_true("DATA_BREACH" %in% names(get_pia_risk_categories()))
  expect_true("CRITICAL" %in% names(get_pia_risk_levels()))
})

test_that("create_pia_assessment creates assessment", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  result <- create_pia_assessment(
    assessment_title = "Clinical Trial Data Processing",
    processing_description = "Collection and processing of participant data",
    data_controller = "University Hospital",
    created_by = "dpo_assistant",
    dpo_name = "Jane Smith",
    dpo_email = "dpo@hospital.org"
  )

  expect_true(result$success)
  expect_true(!is.null(result$assessment_id))
  expect_true(grepl("^PIA-", result$assessment_code))
})

test_that("create_pia_assessment validates inputs", {
  result <- create_pia_assessment(
    assessment_title = "",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )
  expect_false(result$success)
})

test_that("add_processing_purpose adds purpose", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Purpose Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  result <- add_processing_purpose(
    assessment_id = pia$assessment_id,
    purpose_category = "Research",
    purpose_description = "Scientific research for clinical trial",
    legal_basis = "CONSENT",
    legal_basis_details = "Explicit informed consent obtained"
  )

  expect_true(result$success)
})

test_that("add_processing_purpose validates legal basis", {
  result <- add_processing_purpose(
    assessment_id = 1,
    purpose_category = "Test",
    purpose_description = "Test",
    legal_basis = "INVALID_BASIS"
  )
  expect_false(result$success)
})

test_that("add_data_category adds category", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Data Category Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  result <- add_data_category(
    assessment_id = pia$assessment_id,
    data_category = "Health Data",
    is_special_category = TRUE,
    data_subjects = "Clinical trial participants",
    retention_period = "15 years post-trial",
    source_of_data = "Direct from participants"
  )

  expect_true(result$success)
})

test_that("special category triggers DPIA requirement", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "DPIA Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  add_data_category(
    assessment_id = pia$assessment_id,
    data_category = "Genetic Data",
    is_special_category = TRUE
  )

  con <- connect_encrypted_db()
  assessment <- DBI::dbGetQuery(con, "
    SELECT requires_dpia FROM pia_assessments WHERE assessment_id = ?
  ", params = list(pia$assessment_id))
  DBI::dbDisconnect(con)

  expect_equal(assessment$requires_dpia[1], 1)
})

test_that("add_risk_assessment adds risk", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Risk Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  result <- add_risk_assessment(
    assessment_id = pia$assessment_id,
    risk_category = "DATA_BREACH",
    risk_description = "Potential unauthorized access to database",
    likelihood = "MEDIUM",
    impact = "HIGH",
    assessed_by = "security_analyst",
    mitigation_measure = "Implement encryption at rest"
  )

  expect_true(result$success)
  expect_equal(result$risk_level, "MEDIUM")
})

test_that("add_risk_assessment validates levels", {
  result <- add_risk_assessment(
    assessment_id = 1,
    risk_category = "DATA_BREACH",
    risk_description = "Test",
    likelihood = "VERY_HIGH",
    impact = "HIGH",
    assessed_by = "user"
  )
  expect_false(result$success)
})

test_that("risk matrix calculates correctly", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Risk Matrix Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  result_crit <- add_risk_assessment(
    assessment_id = pia$assessment_id,
    risk_category = "DATA_BREACH",
    risk_description = "Critical risk",
    likelihood = "CRITICAL",
    impact = "HIGH",
    assessed_by = "user"
  )
  expect_equal(result_crit$risk_level, "CRITICAL")

  result_low <- add_risk_assessment(
    assessment_id = pia$assessment_id,
    risk_category = "INACCURATE_DATA",
    risk_description = "Low risk",
    likelihood = "LOW",
    impact = "LOW",
    assessed_by = "user"
  )
  expect_equal(result_low$risk_level, "LOW")
})

test_that("get_risk_assessments retrieves risks", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Get Risks Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  add_risk_assessment(
    assessment_id = pia$assessment_id,
    risk_category = "DATA_BREACH",
    risk_description = "Risk 1",
    likelihood = "HIGH",
    impact = "HIGH",
    assessed_by = "user"
  )

  result <- get_risk_assessments(pia$assessment_id)
  expect_true(result$success)
  expect_equal(result$count, 1)
})

test_that("add_consultation records consultation", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Consultation Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  result <- add_consultation(
    assessment_id = pia$assessment_id,
    consulted_party = "Data Protection Authority",
    consultation_type = "PRIOR_CONSULTATION",
    consultation_date = "2025-01-15",
    outcome = "Approved with recommendations",
    recommendations = "Implement additional security measures"
  )

  expect_true(result$success)
})

test_that("calculate_overall_risk calculates risk", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Overall Risk Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  add_risk_assessment(
    assessment_id = pia$assessment_id,
    risk_category = "DATA_BREACH",
    risk_description = "High risk",
    likelihood = "HIGH",
    impact = "HIGH",
    assessed_by = "user"
  )

  add_risk_assessment(
    assessment_id = pia$assessment_id,
    risk_category = "RETENTION",
    risk_description = "Low risk",
    likelihood = "LOW",
    impact = "LOW",
    assessed_by = "user"
  )

  result <- calculate_overall_risk(pia$assessment_id)
  expect_true(result$success)
  expect_equal(result$overall_risk, "HIGH")
})

test_that("submit_pia_for_review submits", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Submit Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  result <- submit_pia_for_review(pia$assessment_id)
  expect_true(result$success)

  con <- connect_encrypted_db()
  status <- DBI::dbGetQuery(con, "
    SELECT status FROM pia_assessments WHERE assessment_id = ?
  ", params = list(pia$assessment_id))$status[1]
  DBI::dbDisconnect(con)

  expect_equal(status, "SUBMITTED")
})

test_that("approve_pia approves", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Approve Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  result <- approve_pia(pia$assessment_id, "dpo")
  expect_true(result$success)

  con <- connect_encrypted_db()
  status <- DBI::dbGetQuery(con, "
    SELECT status FROM pia_assessments WHERE assessment_id = ?
  ", params = list(pia$assessment_id))$status[1]
  DBI::dbDisconnect(con)

  expect_equal(status, "APPROVED")
})

test_that("get_pia_assessment returns full details", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Get Details Test",
    processing_description = "Test processing",
    data_controller = "Test Controller",
    created_by = "user"
  )

  add_processing_purpose(
    assessment_id = pia$assessment_id,
    purpose_category = "Research",
    purpose_description = "Clinical research",
    legal_basis = "CONSENT"
  )

  add_data_category(
    assessment_id = pia$assessment_id,
    data_category = "Health",
    is_special_category = TRUE
  )

  result <- get_pia_assessment(pia$assessment_id)
  expect_true(result$success)
  expect_true("assessment" %in% names(result))
  expect_true("purposes" %in% names(result))
  expect_true("data_categories" %in% names(result))
})

test_that("get_pia_assessment handles not found", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  result <- get_pia_assessment(99999)
  expect_false(result$success)
})

test_that("get_pia_assessments retrieves list", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  create_pia_assessment(
    assessment_title = "Test 1",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )

  result <- get_pia_assessments()
  expect_true(result$success)
  expect_true(result$count >= 1)
})

test_that("get_pia_assessments filters by status", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  pia <- create_pia_assessment(
    assessment_title = "Filter Test",
    processing_description = "Test",
    data_controller = "Test",
    created_by = "user"
  )
  approve_pia(pia$assessment_id, "dpo")

  result <- get_pia_assessments(status = "APPROVED")
  expect_true(result$success)
  expect_true(result$count >= 1)
})

test_that("get_pia_statistics returns stats", {
  setup_pia_test()
  on.exit(cleanup_pia_test())

  result <- get_pia_statistics()
  expect_true(result$success)
  expect_true("statistics" %in% names(result))
  expect_true("by_risk" %in% names(result))
})
