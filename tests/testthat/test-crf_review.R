# Test CRF Design Review Workflow System
# Feature #21 - CRF Design Implementation

library(testthat)

setup_review_test_env <- function() {
  if (!exists("test_db_initialized", envir = .GlobalEnv) ||
      !get("test_db_initialized", envir = .GlobalEnv)) {
    Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
    Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_review_testing_32c!")
    initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
    init_audit_logging()
    init_crf_version()
    assign("test_db_initialized", TRUE, envir = .GlobalEnv)
  }
}

test_that("init_crf_review creates required tables", {
  setup_review_test_env()
  result <- init_crf_review()
  expect_true(result$success)

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("crf_review_cycles" %in% tables)
  expect_true("crf_review_stages" %in% tables)
  expect_true("crf_reviewers" %in% tables)
  expect_true("crf_review_comments" %in% tables)
  expect_true("crf_review_decisions" %in% tables)
})

test_that("reference data functions return valid values", {
  types <- get_review_cycle_types()
  expect_true("INITIAL" %in% names(types))
  expect_true("REVISION" %in% names(types))

  statuses <- get_review_cycle_statuses()
  expect_true("OPEN" %in% names(statuses))
  expect_true("APPROVED" %in% names(statuses))

  stage_types <- get_review_stage_types()
  expect_true("TECHNICAL" %in% names(stage_types))
  expect_true("CLINICAL" %in% names(stage_types))

  decisions <- get_review_decisions()
  expect_true("APPROVE" %in% names(decisions))
  expect_true("REJECT" %in% names(decisions))

  comment_types <- get_review_comment_types()
  expect_true("QUESTION" %in% names(comment_types))
  expect_true("ISSUE" %in% names(comment_types))

  severities <- get_review_comment_severities()
  expect_true("CRITICAL" %in% names(severities))
  expect_true("LOW" %in% names(severities))
})

test_that("create_review_cycle creates cycle successfully", {
  setup_review_test_env()
  init_crf_review()

  code <- paste0("REV_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Review Test CRF",
    created_by = "developer"
  )

  result <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Initial Design Review",
    created_by = "manager",
    cycle_description = "First review of demographics CRF"
  )

  expect_true(result$success)
  expect_true(!is.null(result$cycle_id))
  expect_equal(result$cycle_number, 1)
})

test_that("create_review_cycle validates inputs", {
  result1 <- create_review_cycle(
    crf_id = NULL,
    cycle_type = "INITIAL",
    cycle_title = "Test",
    created_by = "user"
  )
  expect_false(result1$success)

  result2 <- create_review_cycle(
    crf_id = 1,
    cycle_type = "INVALID",
    cycle_title = "Test",
    created_by = "user"
  )
  expect_false(result2$success)
})

test_that("get_review_cycles retrieves cycles", {
  setup_review_test_env()

  code <- paste0("GRC_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Get Cycles Test",
    created_by = "developer"
  )

  create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "First Review",
    created_by = "manager"
  )

  result <- get_review_cycles(crf$crf_id)
  expect_true(result$success)
  expect_equal(result$count, 1)
})

test_that("start_review_cycle updates status", {
  setup_review_test_env()

  code <- paste0("SRC_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Start Cycle Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Start Test Review",
    created_by = "manager"
  )

  result <- start_review_cycle(cycle$cycle_id, "manager")
  expect_true(result$success)

  cycles <- get_review_cycles(crf$crf_id)
  expect_equal(cycles$cycles$cycle_status[1], "IN_PROGRESS")
})

test_that("complete_review_cycle sets final status", {
  setup_review_test_env()

  code <- paste0("CRC_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Complete Cycle Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Complete Test Review",
    created_by = "manager"
  )

  result <- complete_review_cycle(cycle$cycle_id, "APPROVED", "director")
  expect_true(result$success)

  cycles <- get_review_cycles(crf$crf_id)
  expect_equal(cycles$cycles$cycle_status[1], "APPROVED")
})

test_that("add_review_stage adds stage to cycle", {
  setup_review_test_env()
  init_crf_review()

  code <- paste0("ARS_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Add Stage Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Stage Test Review",
    created_by = "manager"
  )

  result <- add_review_stage(
    cycle_id = cycle$cycle_id,
    stage_name = "Technical Review",
    stage_type = "TECHNICAL",
    stage_order = 1,
    created_by = "manager",
    required_approvers = 2,
    instructions = "Review all field definitions"
  )

  expect_true(result$success)
  expect_true(!is.null(result$stage_id))
})

test_that("add_review_stage validates stage_type", {
  result <- add_review_stage(
    cycle_id = 1,
    stage_name = "Test Stage",
    stage_type = "INVALID",
    stage_order = 1,
    created_by = "user"
  )
  expect_false(result$success)
})

test_that("get_review_stages retrieves stages in order", {
  setup_review_test_env()

  code <- paste0("GRS_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Get Stages Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Get Stages Review",
    created_by = "manager"
  )

  add_review_stage(cycle_id = cycle$cycle_id, stage_name = "Stage 2",
                   stage_type = "CLINICAL", stage_order = 2, created_by = "mgr")
  add_review_stage(cycle_id = cycle$cycle_id, stage_name = "Stage 1",
                   stage_type = "TECHNICAL", stage_order = 1, created_by = "mgr")

  result <- get_review_stages(cycle$cycle_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
  expect_equal(result$stages$stage_name[1], "Stage 1")
  expect_equal(result$stages$stage_name[2], "Stage 2")
})

test_that("update_stage_status updates status correctly", {
  setup_review_test_env()

  code <- paste0("USS_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Update Stage Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Update Stage Review",
    created_by = "manager"
  )

  stage <- add_review_stage(
    cycle_id = cycle$cycle_id,
    stage_name = "Technical Review",
    stage_type = "TECHNICAL",
    stage_order = 1,
    created_by = "manager"
  )

  result <- update_stage_status(stage$stage_id, "IN_PROGRESS", "reviewer")
  expect_true(result$success)

  stages <- get_review_stages(cycle$cycle_id)
  expect_equal(stages$stages$stage_status[1], "IN_PROGRESS")
})

test_that("assign_reviewer assigns reviewer to stage", {
  setup_review_test_env()
  init_crf_review()

  code <- paste0("ASR_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Assign Reviewer Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Assign Reviewer Review",
    created_by = "manager"
  )

  stage <- add_review_stage(
    cycle_id = cycle$cycle_id,
    stage_name = "Technical Review",
    stage_type = "TECHNICAL",
    stage_order = 1,
    created_by = "manager"
  )

  result <- assign_reviewer(
    stage_id = stage$stage_id,
    reviewer_id = "jsmith",
    reviewer_name = "John Smith",
    reviewer_role = "Lead Data Manager",
    assigned_by = "manager"
  )

  expect_true(result$success)
  expect_true(!is.null(result$assignment_id))
})

test_that("get_stage_reviewers retrieves reviewers", {
  setup_review_test_env()

  code <- paste0("GSR_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Get Reviewers Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Get Reviewers Review",
    created_by = "manager"
  )

  stage <- add_review_stage(
    cycle_id = cycle$cycle_id,
    stage_name = "Technical Review",
    stage_type = "TECHNICAL",
    stage_order = 1,
    created_by = "manager"
  )

  assign_reviewer(stage_id = stage$stage_id, reviewer_id = "rev1",
                  reviewer_name = "Reviewer 1", reviewer_role = "Technical",
                  assigned_by = "manager")
  assign_reviewer(stage_id = stage$stage_id, reviewer_id = "rev2",
                  reviewer_name = "Reviewer 2", reviewer_role = "Clinical",
                  assigned_by = "manager")

  result <- get_stage_reviewers(stage$stage_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("submit_review_decision records decision", {
  setup_review_test_env()

  code <- paste0("SRD_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Submit Decision Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Decision Test Review",
    created_by = "manager"
  )

  stage <- add_review_stage(
    cycle_id = cycle$cycle_id,
    stage_name = "Technical Review",
    stage_type = "TECHNICAL",
    stage_order = 1,
    created_by = "manager"
  )

  assignment <- assign_reviewer(
    stage_id = stage$stage_id,
    reviewer_id = "reviewer1",
    reviewer_name = "Test Reviewer",
    reviewer_role = "Technical Lead",
    assigned_by = "manager"
  )

  result <- submit_review_decision(
    assignment_id = assignment$assignment_id,
    decision = "APPROVE",
    decision_rationale = "All fields properly defined",
    submitted_by = "reviewer1"
  )

  expect_true(result$success)
  expect_equal(result$decision, "APPROVE")
})

test_that("submit_review_decision validates decision", {
  result <- submit_review_decision(
    assignment_id = 1,
    decision = "INVALID",
    decision_rationale = "Test rationale",
    submitted_by = "user"
  )
  expect_false(result$success)
})

test_that("add_review_comment adds comment", {
  setup_review_test_env()
  init_crf_review()

  code <- paste0("ARC_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Add Comment Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Comment Test Review",
    created_by = "manager"
  )

  result <- add_review_comment(
    cycle_id = cycle$cycle_id,
    comment_type = "ISSUE",
    comment_text = "The date format should be ISO 8601 compliant",
    created_by = "reviewer",
    field_reference = "DOB",
    severity = "HIGH"
  )

  expect_true(result$success)
  expect_true(!is.null(result$comment_id))
})

test_that("add_review_comment validates inputs", {
  result1 <- add_review_comment(
    cycle_id = NULL,
    comment_type = "ISSUE",
    comment_text = "Test comment",
    created_by = "user"
  )
  expect_false(result1$success)

  result2 <- add_review_comment(
    cycle_id = 1,
    comment_type = "INVALID",
    comment_text = "Test comment",
    created_by = "user"
  )
  expect_false(result2$success)
})

test_that("get_review_comments retrieves comments", {
  setup_review_test_env()

  code <- paste0("GCM_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Get Comments Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Get Comments Review",
    created_by = "manager"
  )

  add_review_comment(cycle_id = cycle$cycle_id, comment_type = "ISSUE",
                     comment_text = "Issue comment for testing",
                     created_by = "rev1", severity = "HIGH")
  add_review_comment(cycle_id = cycle$cycle_id, comment_type = "SUGGESTION",
                     comment_text = "Suggestion for improvement",
                     created_by = "rev2", severity = "LOW")

  result <- get_review_comments(cycle$cycle_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("get_review_comments filters by severity", {
  setup_review_test_env()

  code <- paste0("GCF_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Filter Comments Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Filter Comments Review",
    created_by = "manager"
  )

  add_review_comment(cycle_id = cycle$cycle_id, comment_type = "ISSUE",
                     comment_text = "Critical issue found",
                     created_by = "rev1", severity = "CRITICAL")
  add_review_comment(cycle_id = cycle$cycle_id, comment_type = "OBSERVATION",
                     comment_text = "Minor observation noted",
                     created_by = "rev2", severity = "LOW")

  result <- get_review_comments(cycle$cycle_id, severity = "CRITICAL")
  expect_true(result$success)
  expect_equal(result$count, 1)
  expect_equal(result$comments$severity[1], "CRITICAL")
})

test_that("resolve_comment resolves comment", {
  setup_review_test_env()

  code <- paste0("RCM_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Resolve Comment Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Resolve Comment Review",
    created_by = "manager"
  )

  comment <- add_review_comment(
    cycle_id = cycle$cycle_id,
    comment_type = "ISSUE",
    comment_text = "Issue to be resolved",
    created_by = "reviewer"
  )

  result <- resolve_comment(
    comment_id = comment$comment_id,
    resolution = "Fixed the date format as requested",
    resolved_by = "developer"
  )

  expect_true(result$success)

  comments <- get_review_comments(cycle$cycle_id, status = "RESOLVED")
  expect_equal(comments$count, 1)
})

test_that("get_review_statistics returns statistics", {
  setup_review_test_env()
  init_crf_review()

  result <- get_review_statistics()
  expect_true(result$success)
  expect_true("cycles" %in% names(result))
  expect_true("comments" %in% names(result))
})

test_that("complete review workflow works end-to-end", {
  setup_review_test_env()
  init_crf_review()

  code <- paste0("E2E_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "End-to-End Review Test",
    created_by = "developer"
  )

  cycle <- create_review_cycle(
    crf_id = crf$crf_id,
    cycle_type = "INITIAL",
    cycle_title = "Complete Workflow Test",
    created_by = "manager",
    priority = "HIGH"
  )
  expect_true(cycle$success)

  start_review_cycle(cycle$cycle_id, "manager")

  stage1 <- add_review_stage(
    cycle_id = cycle$cycle_id,
    stage_name = "Technical Review",
    stage_type = "TECHNICAL",
    stage_order = 1,
    created_by = "manager",
    required_approvers = 1
  )
  expect_true(stage1$success)

  stage2 <- add_review_stage(
    cycle_id = cycle$cycle_id,
    stage_name = "Clinical Review",
    stage_type = "CLINICAL",
    stage_order = 2,
    created_by = "manager",
    required_approvers = 1
  )
  expect_true(stage2$success)

  assignment1 <- assign_reviewer(
    stage_id = stage1$stage_id,
    reviewer_id = "tech_lead",
    reviewer_name = "Technical Lead",
    reviewer_role = "Technical Reviewer",
    assigned_by = "manager"
  )
  expect_true(assignment1$success)

  update_stage_status(stage1$stage_id, "IN_PROGRESS", "tech_lead")

  add_review_comment(
    cycle_id = cycle$cycle_id,
    stage_id = stage1$stage_id,
    comment_type = "SUGGESTION",
    comment_text = "Consider adding validation for date fields",
    created_by = "tech_lead",
    severity = "MEDIUM"
  )

  decision1 <- submit_review_decision(
    assignment_id = assignment1$assignment_id,
    decision = "APPROVE_WITH_CONDITIONS",
    decision_rationale = "Approved pending date validation",
    submitted_by = "tech_lead",
    conditions = "Add date validation before production",
    follow_up_required = TRUE,
    follow_up_description = "Verify date validation implementation"
  )
  expect_true(decision1$success)

  update_stage_status(stage1$stage_id, "COMPLETED", "tech_lead")

  assignment2 <- assign_reviewer(
    stage_id = stage2$stage_id,
    reviewer_id = "clinical_lead",
    reviewer_name = "Clinical Lead",
    reviewer_role = "Clinical Reviewer",
    assigned_by = "manager"
  )

  update_stage_status(stage2$stage_id, "IN_PROGRESS", "clinical_lead")

  decision2 <- submit_review_decision(
    assignment_id = assignment2$assignment_id,
    decision = "APPROVE",
    decision_rationale = "Clinical content is appropriate",
    submitted_by = "clinical_lead"
  )
  expect_true(decision2$success)

  update_stage_status(stage2$stage_id, "COMPLETED", "clinical_lead")

  complete_result <- complete_review_cycle(cycle$cycle_id, "APPROVED", "director")
  expect_true(complete_result$success)

  stats <- get_review_statistics(crf$crf_id)
  expect_true(stats$success)
  expect_true(stats$cycles$approved >= 1)
})

test_that("cleanup test environment", {
  if (exists("test_db_initialized", envir = .GlobalEnv)) {
    rm("test_db_initialized", envir = .GlobalEnv)
  }
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) {
    unlink(db_path)
  }
  expect_true(TRUE)
})
