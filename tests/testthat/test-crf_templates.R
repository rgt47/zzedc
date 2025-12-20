# Test CRF Template Library System
# Feature #23 - CRF Design Implementation

library(testthat)

setup_tpl_test_env <- function() {
  if (!exists("test_db_initialized", envir = .GlobalEnv) ||
      !get("test_db_initialized", envir = .GlobalEnv)) {
    Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
    Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_template_testing32!")
    initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
    init_audit_logging()
    assign("test_db_initialized", TRUE, envir = .GlobalEnv)
  }
}

test_that("init_crf_templates creates required tables", {
  setup_tpl_test_env()
  result <- init_crf_templates()
  expect_true(result$success)

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("crf_templates" %in% tables)
  expect_true("crf_template_fields" %in% tables)
  expect_true("crf_template_usage" %in% tables)
})

test_that("get_template_categories returns categories", {
  categories <- get_template_categories()
  expect_true("DEMOGRAPHICS" %in% names(categories))
  expect_true("VITAL_SIGNS" %in% names(categories))
  expect_true("ADVERSE_EVENTS" %in% names(categories))
})

test_that("create_crf_template creates template", {
  setup_tpl_test_env()
  init_crf_templates()

  code <- paste0("TPL_", format(Sys.time(), "%H%M%S"))
  result <- create_crf_template(
    template_code = code,
    template_name = "Test Template",
    template_category = "DEMOGRAPHICS",
    created_by = "developer",
    template_description = "A test template"
  )

  expect_true(result$success)
  expect_true(!is.null(result$template_id))
})

test_that("create_crf_template validates required fields", {
  result <- create_crf_template(
    template_code = "",
    template_name = "Test",
    template_category = "DEMOGRAPHICS",
    created_by = "user"
  )
  expect_false(result$success)
})

test_that("add_template_field adds field", {
  setup_tpl_test_env()

  code <- paste0("TPLF_", format(Sys.time(), "%H%M%S"))
  template <- create_crf_template(
    template_code = code,
    template_name = "Field Test Template",
    template_category = "DEMOGRAPHICS",
    created_by = "developer"
  )

  result <- add_template_field(
    template_id = template$template_id,
    field_code = "SUBJID",
    field_name = "Subject ID",
    field_label = "Subject Identifier",
    field_type = "TEXT",
    field_order = 1,
    section_name = "Identification",
    is_required = TRUE
  )

  expect_true(result$success)
})

test_that("get_crf_templates retrieves templates", {
  setup_tpl_test_env()

  result <- get_crf_templates()
  expect_true(result$success)
  expect_true("templates" %in% names(result))
})

test_that("get_crf_templates filters by category", {
  setup_tpl_test_env()

  code <- paste0("CAT_", format(Sys.time(), "%H%M%S"))
  create_crf_template(
    template_code = code,
    template_name = "Category Test",
    template_category = "VITAL_SIGNS",
    created_by = "developer"
  )

  result <- get_crf_templates(template_category = "VITAL_SIGNS")
  expect_true(result$success)
  if (result$count > 0) {
    expect_true(all(result$templates$template_category == "VITAL_SIGNS"))
  }
})

test_that("get_template_fields retrieves fields in order", {
  setup_tpl_test_env()

  code <- paste0("ORD_", format(Sys.time(), "%H%M%S"))
  template <- create_crf_template(
    template_code = code,
    template_name = "Order Test",
    template_category = "DEMOGRAPHICS",
    created_by = "developer"
  )

  add_template_field(template$template_id, "F2", "F2", "Field 2", "TEXT", 2)
  add_template_field(template$template_id, "F1", "F1", "Field 1", "TEXT", 1)

  result <- get_template_fields(template$template_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
  expect_equal(result$fields$field_code[1], "F1")
})

test_that("use_template records usage", {
  setup_tpl_test_env()

  code <- paste0("USE_", format(Sys.time(), "%H%M%S"))
  template <- create_crf_template(
    template_code = code,
    template_name = "Usage Test",
    template_category = "DEMOGRAPHICS",
    created_by = "developer"
  )

  result <- use_template(
    template_id = template$template_id,
    used_by = "crf_designer",
    study_name = "Test Study"
  )

  expect_true(result$success)
})

test_that("load_standard_templates loads templates", {
  setup_tpl_test_env()
  init_crf_templates()

  result <- load_standard_templates("admin")

  expect_true(result$success)
  expect_true(result$templates_loaded >= 3)

  templates <- get_crf_templates()
  expect_true(templates$count >= 3)
})

test_that("get_template_statistics returns statistics", {
  setup_tpl_test_env()

  result <- get_template_statistics()
  expect_true(result$success)
  expect_true("totals" %in% names(result))
  expect_true("by_category" %in% names(result))
})

test_that("cleanup test environment", {
  if (exists("test_db_initialized", envir = .GlobalEnv)) {
    rm("test_db_initialized", envir = .GlobalEnv)
  }
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) unlink(db_path)
  expect_true(TRUE)
})
