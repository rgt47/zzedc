# Test Advanced Validation Rules System
# Feature #24

library(testthat)

setup_val_test_env <- function() {
  if (!exists("test_db_initialized", envir = .GlobalEnv) ||
      !get("test_db_initialized", envir = .GlobalEnv)) {
    Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
    Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_validation_test32!")
    initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
    init_audit_logging()
    assign("test_db_initialized", TRUE, envir = .GlobalEnv)
  }
}

test_that("init_validation_rules creates tables", {
  setup_val_test_env()
  result <- init_validation_rules()
  expect_true(result$success)

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("validation_rules" %in% tables)
  expect_true("validation_results" %in% tables)
  expect_true("validation_rule_sets" %in% tables)
})

test_that("reference data functions return values", {
  expect_true("REQUIRED" %in% names(get_validation_rule_categories()))
  expect_true("NOT_NULL" %in% names(get_validation_rule_types()))
  expect_true("ERROR" %in% names(get_validation_severities()))
})

test_that("create_validation_rule creates rule", {
  setup_val_test_env()
  init_validation_rules()

  result <- create_validation_rule(
    rule_code = paste0("VR_", format(Sys.time(), "%H%M%S")),
    rule_name = "Required Age",
    rule_category = "REQUIRED",
    rule_type = "NOT_NULL",
    condition_expression = "AGE IS NOT NULL",
    error_message = "Age is required",
    created_by = "developer",
    target_field = "AGE"
  )

  expect_true(result$success)
  expect_true(!is.null(result$rule_id))
})

test_that("create_validation_rule validates inputs", {
  result <- create_validation_rule(
    rule_code = "",
    rule_name = "Test",
    rule_category = "REQUIRED",
    rule_type = "NOT_NULL",
    condition_expression = "X IS NOT NULL",
    error_message = "Error",
    created_by = "user"
  )
  expect_false(result$success)
})

test_that("get_validation_rules retrieves rules", {
  setup_val_test_env()
  result <- get_validation_rules()
  expect_true(result$success)
})

test_that("record_validation_result records result", {
  setup_val_test_env()
  init_validation_rules()

  rule <- create_validation_rule(
    rule_code = paste0("RES_", format(Sys.time(), "%H%M%S")),
    rule_name = "Test Rule",
    rule_category = "REQUIRED",
    rule_type = "NOT_NULL",
    condition_expression = "X IS NOT NULL",
    error_message = "X is required",
    created_by = "developer"
  )

  result <- record_validation_result(
    rule_id = rule$rule_id,
    validation_status = "FAIL",
    validated_by = "system",
    subject_id = "SUBJ-001",
    field_name = "X",
    error_message = "X is required"
  )

  expect_true(result$success)
})

test_that("get_validation_results retrieves results", {
  setup_val_test_env()
  result <- get_validation_results()
  expect_true(result$success)
})

test_that("resolve_validation_error resolves error", {
  setup_val_test_env()

  rule <- create_validation_rule(
    rule_code = paste0("RSV_", format(Sys.time(), "%H%M%S")),
    rule_name = "Resolve Test",
    rule_category = "REQUIRED",
    rule_type = "NOT_NULL",
    condition_expression = "Y IS NOT NULL",
    error_message = "Y required",
    created_by = "dev"
  )

  record_validation_result(
    rule_id = rule$rule_id,
    validation_status = "FAIL",
    validated_by = "system"
  )

  con <- connect_encrypted_db()
  result_id <- DBI::dbGetQuery(con, "
    SELECT result_id FROM validation_results ORDER BY result_id DESC LIMIT 1
  ")$result_id[1]
  DBI::dbDisconnect(con)

  result <- resolve_validation_error(result_id, "dm", "Fixed the value")
  expect_true(result$success)
})

test_that("create_validation_rule_set creates set", {
  setup_val_test_env()

  result <- create_validation_rule_set(
    set_code = paste0("SET_", format(Sys.time(), "%H%M%S")),
    set_name = "Demographics Validation",
    created_by = "developer",
    set_description = "Rules for demographics form"
  )

  expect_true(result$success)
})

test_that("add_rule_to_set adds rule", {
  setup_val_test_env()

  ruleset <- create_validation_rule_set(
    set_code = paste0("ASET_", format(Sys.time(), "%H%M%S")),
    set_name = "Add Rule Test",
    created_by = "dev"
  )

  rule <- create_validation_rule(
    rule_code = paste0("ARULE_", format(Sys.time(), "%H%M%S")),
    rule_name = "Add Test",
    rule_category = "REQUIRED",
    rule_type = "NOT_NULL",
    condition_expression = "Z IS NOT NULL",
    error_message = "Z required",
    created_by = "dev"
  )

  result <- add_rule_to_set(ruleset$set_id, rule$rule_id)
  expect_true(result$success)
})

test_that("get_validation_statistics returns stats", {
  setup_val_test_env()
  result <- get_validation_statistics()
  expect_true(result$success)
  expect_true("rules" %in% names(result))
  expect_true("results" %in% names(result))
})

test_that("cleanup", {
  if (exists("test_db_initialized", envir = .GlobalEnv)) {
    rm("test_db_initialized", envir = .GlobalEnv)
  }
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) unlink(db_path)
  expect_true(TRUE)
})
