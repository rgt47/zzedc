# Test Master Field Library System
# Feature #22 - CRF Design Implementation

library(testthat)

setup_fl_test_env <- function() {
  if (!exists("test_db_initialized", envir = .GlobalEnv) ||
      !get("test_db_initialized", envir = .GlobalEnv)) {
    Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
    Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_fieldlib_testing32!")
    initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
    init_audit_logging()
    assign("test_db_initialized", TRUE, envir = .GlobalEnv)
  }
}

test_that("init_field_library creates required tables", {
  setup_fl_test_env()
  result <- init_field_library()
  expect_true(result$success)

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("field_library" %in% tables)
  expect_true("field_library_versions" %in% tables)
  expect_true("field_library_usage" %in% tables)
  expect_true("field_categories" %in% tables)
})

test_that("reference data functions return valid values", {
  categories <- get_field_library_categories()
  expect_true("DEMOGRAPHICS" %in% names(categories))
  expect_true("VITAL_SIGNS" %in% names(categories))

  data_types <- get_field_data_types()
  expect_true("TEXT" %in% names(data_types))
  expect_true("INTEGER" %in% names(data_types))
  expect_true("DATE" %in% names(data_types))

  domains <- get_cdisc_domains()
  expect_true("DM" %in% names(domains))
  expect_true("VS" %in% names(domains))
  expect_true("AE" %in% names(domains))
})

test_that("create_field_category creates category", {
  setup_fl_test_env()
  init_field_library()

  result <- create_field_category(
    category_code = "CUSTOM_CAT",
    category_name = "Custom Category",
    category_description = "A custom field category",
    display_order = 100
  )

  expect_true(result$success)
  expect_true(!is.null(result$category_id))
})

test_that("get_field_categories retrieves categories", {
  setup_fl_test_env()

  create_field_category(
    category_code = paste0("CAT_", format(Sys.time(), "%H%M%S")),
    category_name = "Test Category"
  )

  result <- get_field_categories()
  expect_true(result$success)
  expect_true(result$count > 0)
})

test_that("add_library_field adds field successfully", {
  setup_fl_test_env()
  init_field_library()

  code <- paste0("FLD_", format(Sys.time(), "%H%M%S"))

  result <- add_library_field(
    field_code = code,
    field_name = "Test Field",
    field_label = "Test Field Label",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "developer",
    description = "A test field for unit testing",
    is_required = TRUE
  )

  expect_true(result$success)
  expect_true(!is.null(result$field_lib_id))
  expect_equal(result$field_code, code)
})

test_that("add_library_field validates required fields", {
  result1 <- add_library_field(
    field_code = "",
    field_name = "Test",
    field_label = "Test",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )
  expect_false(result1$success)

  result2 <- add_library_field(
    field_code = "TEST",
    field_name = "Test",
    field_label = "",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )
  expect_false(result2$success)
})

test_that("add_library_field rejects duplicate codes", {
  setup_fl_test_env()

  code <- paste0("DUP_", format(Sys.time(), "%H%M%S"))

  add_library_field(
    field_code = code,
    field_name = "First Field",
    field_label = "First",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )

  result <- add_library_field(
    field_code = code,
    field_name = "Duplicate",
    field_label = "Duplicate",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )

  expect_false(result$success)
  expect_match(result$error, "already exists")
})

test_that("add_library_field stores all properties", {
  setup_fl_test_env()

  code <- paste0("PROP_", format(Sys.time(), "%H%M%S"))

  add_library_field(
    field_code = code,
    field_name = "Property Test Field",
    field_label = "Test with Properties",
    field_type = "NUMBER",
    field_category = "VITAL_SIGNS",
    created_by = "developer",
    is_cdisc_standard = TRUE,
    cdisc_variable = "TESTVAR",
    cdisc_domain = "VS",
    data_type = "FLOAT",
    valid_range_min = "10",
    valid_range_max = "100",
    units = "units",
    is_required = TRUE,
    validation_rules = "Must be positive",
    completion_instruction = "Enter the value"
  )

  result <- get_library_field(code)
  expect_true(result$success)
  expect_equal(result$field$is_cdisc_standard, 1)
  expect_equal(result$field$cdisc_domain, "VS")
  expect_equal(result$field$units, "units")
  expect_equal(result$field$is_required, 1)
})

test_that("get_library_fields retrieves fields", {
  setup_fl_test_env()

  result <- get_library_fields()
  expect_true(result$success)
  expect_true("fields" %in% names(result))
})

test_that("get_library_fields filters by category", {
  setup_fl_test_env()

  code <- paste0("CAT_", format(Sys.time(), "%H%M%S"))

  add_library_field(
    field_code = code,
    field_name = "Category Test",
    field_label = "Category Test",
    field_type = "TEXT",
    field_category = "LAB_RESULTS",
    created_by = "user"
  )

  result <- get_library_fields(field_category = "LAB_RESULTS")
  expect_true(result$success)
  if (result$count > 0) {
    expect_true(all(result$fields$field_category == "LAB_RESULTS"))
  }
})

test_that("get_library_fields filters by CDISC domain", {
  setup_fl_test_env()

  code <- paste0("DOM_", format(Sys.time(), "%H%M%S"))

  add_library_field(
    field_code = code,
    field_name = "Domain Test",
    field_label = "Domain Test",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user",
    is_cdisc_standard = TRUE,
    cdisc_domain = "DM"
  )

  result <- get_library_fields(cdisc_domain = "DM")
  expect_true(result$success)
  if (result$count > 0) {
    expect_true(all(result$fields$cdisc_domain == "DM"))
  }
})

test_that("get_library_fields searches by term", {
  setup_fl_test_env()

  code <- paste0("SRCH_", format(Sys.time(), "%H%M%S"))

  add_library_field(
    field_code = code,
    field_name = "Searchable Unique Field",
    field_label = "Searchable",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user",
    description = "This field is searchable"
  )

  result <- get_library_fields(search_term = "Searchable")
  expect_true(result$success)
  expect_true(result$count >= 1)
})

test_that("get_library_field retrieves single field", {
  setup_fl_test_env()

  code <- paste0("SNGL_", format(Sys.time(), "%H%M%S"))

  add_library_field(
    field_code = code,
    field_name = "Single Field Test",
    field_label = "Single Test",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )

  result <- get_library_field(code)
  expect_true(result$success)
  expect_equal(result$field$field_code, code)
})

test_that("get_library_field returns error for nonexistent", {
  setup_fl_test_env()

  result <- get_library_field("NONEXISTENT_FIELD_CODE")
  expect_false(result$success)
  expect_match(result$error, "not found")
})

test_that("update_library_field updates field", {
  setup_fl_test_env()

  code <- paste0("UPD_", format(Sys.time(), "%H%M%S"))

  field <- add_library_field(
    field_code = code,
    field_name = "Update Test",
    field_label = "Original Label",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )

  result <- update_library_field(
    field_lib_id = field$field_lib_id,
    updated_by = "editor",
    field_label = "Updated Label",
    description = "New description"
  )

  expect_true(result$success)

  updated <- get_library_field(code)
  expect_equal(updated$field$field_label, "Updated Label")
  expect_equal(updated$field$description, "New description")
})

test_that("update_library_field requires at least one update", {
  result <- update_library_field(field_lib_id = 1, updated_by = "user")
  expect_false(result$success)
  expect_match(result$error, "No updates")
})

test_that("deactivate_library_field deactivates field", {
  setup_fl_test_env()

  code <- paste0("DEA_", format(Sys.time(), "%H%M%S"))

  field <- add_library_field(
    field_code = code,
    field_name = "Deactivate Test",
    field_label = "Deactivate Test",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )

  result <- deactivate_library_field(field$field_lib_id, "admin")
  expect_true(result$success)

  active_fields <- get_library_fields(include_inactive = FALSE)
  deactivated <- active_fields$fields[
    active_fields$fields$field_code == code, ]
  expect_equal(nrow(deactivated), 0)
})

test_that("record_field_usage records usage", {
  setup_fl_test_env()

  code <- paste0("USE_", format(Sys.time(), "%H%M%S"))

  field <- add_library_field(
    field_code = code,
    field_name = "Usage Test",
    field_label = "Usage Test",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )

  result <- record_field_usage(
    field_lib_id = field$field_lib_id,
    used_by = "developer",
    crf_id = 1,
    customizations = "Changed label"
  )

  expect_true(result$success)

  updated <- get_library_field(code)
  expect_equal(updated$field$usage_count, 1)
})

test_that("get_field_usage retrieves usage history", {
  setup_fl_test_env()

  code <- paste0("GUSE_", format(Sys.time(), "%H%M%S"))

  field <- add_library_field(
    field_code = code,
    field_name = "Get Usage Test",
    field_label = "Get Usage",
    field_type = "TEXT",
    field_category = "DEMOGRAPHICS",
    created_by = "user"
  )

  record_field_usage(field$field_lib_id, "user1")
  record_field_usage(field$field_lib_id, "user2")

  result <- get_field_usage(field$field_lib_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("load_cdisc_standard_fields loads CDISC fields", {
  setup_fl_test_env()
  init_field_library()

  result <- load_cdisc_standard_fields("system")

  expect_true(result$success)
  expect_true(result$fields_loaded > 0)

  cdisc_fields <- get_library_fields(is_cdisc_standard = TRUE)
  expect_true(cdisc_fields$count > 0)

  usubjid <- get_library_field("USUBJID")
  if (usubjid$success) {
    expect_equal(usubjid$field$is_cdisc_standard, 1)
    expect_equal(usubjid$field$cdisc_domain, "DM")
  }
})

test_that("get_field_library_statistics returns statistics", {
  setup_fl_test_env()

  result <- get_field_library_statistics()

  expect_true(result$success)
  expect_true("totals" %in% names(result))
  expect_true("by_category" %in% names(result))
  expect_true("most_used" %in% names(result))
})

test_that("complete field library workflow works end-to-end", {
  setup_fl_test_env()
  init_field_library()

  load_cdisc_standard_fields("admin")

  custom_code <- paste0("CUSTOM_", format(Sys.time(), "%H%M%S"))
  custom_field <- add_library_field(
    field_code = custom_code,
    field_name = "Custom Study Field",
    field_label = "Custom Field",
    field_type = "DROPDOWN",
    field_category = "EFFICACY",
    created_by = "developer",
    description = "Custom field for efficacy assessment",
    valid_values = "1=Mild; 2=Moderate; 3=Severe",
    is_required = TRUE,
    completion_instruction = "Select the severity level"
  )
  expect_true(custom_field$success)

  record_field_usage(
    field_lib_id = custom_field$field_lib_id,
    used_by = "crf_designer",
    crf_id = 1
  )

  all_fields <- get_library_fields()
  expect_true(all_fields$success)
  expect_true(all_fields$count > 10)

  cdisc_only <- get_library_fields(is_cdisc_standard = TRUE)
  expect_true(cdisc_only$success)
  expect_true(cdisc_only$count > 0)

  vs_fields <- get_library_fields(cdisc_domain = "VS")
  expect_true(vs_fields$success)

  stats <- get_field_library_statistics()
  expect_true(stats$success)
  expect_true(stats$totals$total_fields > 0)
  expect_true(stats$totals$cdisc_fields > 0)
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
