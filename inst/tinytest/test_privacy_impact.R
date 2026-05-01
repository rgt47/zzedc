library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Test Privacy Impact Assessment (PIA) Tool
# Feature #28
setup_pia_test <- function() {
  Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_privacy_impact_32!")
  .init_res <- initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
  Sys.setenv(DB_ENCRYPTION_KEY = .init_res$key)
  init_audit_logging()
  init_pia_system()
}

cleanup_pia_test <- function() {
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) {
    try(unlink(db_path), silent = TRUE)
  }
}

# Test: init_pia_system creates tables
local({
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
# Test: reference functions return values
local({
    expect_true("DRAFT" %in% names(get_pia_statuses()))
    expect_true("CONSENT" %in% names(get_gdpr_legal_bases()))
    expect_true("DATA_BREACH" %in% names(get_pia_risk_categories()))
    expect_true("CRITICAL" %in% names(get_pia_risk_levels()))

})
# Test: create_pia_assessment creates assessment
local({
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
# Test: create_pia_assessment validates inputs
local({
    result <- create_pia_assessment(
      assessment_title = "",
      processing_description = "Test",
      data_controller = "Test",
      created_by = "user"
    )
    expect_false(result$success)

})
# Test: add_processing_purpose adds purpose
local({
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
# Test: add_processing_purpose validates legal basis
local({
    result <- add_processing_purpose(
      assessment_id = 1,
      purpose_category = "Test",
      purpose_description = "Test",
      legal_basis = "INVALID_BASIS"
    )
    expect_false(result$success)

})
# Test: add_data_category adds category
local({
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
# Test: special category triggers DPIA requirement
local({
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
# Test: add_risk_assessment adds risk
local({
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
# Test: add_risk_assessment validates levels
local({
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
# Test: risk matrix calculates correctly
local({
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
# Test: get_risk_assessments retrieves risks
local({
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
# Test: add_consultation records consultation
local({
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
# Test: calculate_overall_risk calculates risk
local({
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
# Test: submit_pia_for_review submits
local({
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
# Test: approve_pia approves
local({
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
# Test: get_pia_assessment returns full details
local({
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
# Test: get_pia_assessment handles not found
local({
    setup_pia_test()
    on.exit(cleanup_pia_test())

    result <- get_pia_assessment(99999)
    expect_false(result$success)

})
# Test: get_pia_assessments retrieves list
local({
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
# Test: get_pia_assessments filters by status
local({
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
# Test: get_pia_statistics returns stats
local({
    setup_pia_test()
    on.exit(cleanup_pia_test())

    result <- get_pia_statistics()
    expect_true(result$success)
    expect_true("statistics" %in% names(result))
    expect_true("by_risk" %in% names(result))

})