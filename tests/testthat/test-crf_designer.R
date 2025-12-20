# Test WYSIWYG CRF Designer
# Feature #32

library(testthat)

setup_cd_test <- function() {
  Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_crf_designer_32!")
  initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
  init_audit_logging()
  init_crf_designer()
}

cleanup_cd_test <- function() {
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) {
    try(unlink(db_path), silent = TRUE)
  }
}

test_that("init_crf_designer creates tables", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("designer_forms" %in% tables)
  expect_true("designer_sections" %in% tables)
  expect_true("designer_fields" %in% tables)
  expect_true("designer_field_options" %in% tables)
})

test_that("reference functions return values", {
  expect_true("SINGLE_COLUMN" %in% names(get_layout_types()))
  expect_true("TEXT" %in% names(get_designer_field_types()))
  expect_true("DRAFT" %in% names(get_form_statuses()))
})

test_that("create_designer_form creates form", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  result <- create_designer_form(
    form_code = "DM_FORM",
    form_name = "Demographics Form",
    created_by = "designer",
    form_category = "DEMOGRAPHICS",
    form_description = "Basic demographics",
    layout_type = "TWO_COLUMN"
  )

  expect_true(result$success)
  expect_true(!is.null(result$design_id))
})

test_that("create_designer_form validates inputs", {
  result <- create_designer_form(
    form_code = "",
    form_name = "Test",
    created_by = "user"
  )
  expect_false(result$success)

  setup_cd_test()
  on.exit(cleanup_cd_test())

  result2 <- create_designer_form(
    form_code = "TEST",
    form_name = "Test",
    created_by = "user",
    layout_type = "INVALID"
  )
  expect_false(result2$success)
})

test_that("add_form_section adds section", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "SECTION_TEST",
    form_name = "Section Test",
    created_by = "designer"
  )

  result <- add_form_section(
    design_id = form$design_id,
    section_code = "BASIC_INFO",
    section_name = "Basic Information",
    section_order = 1,
    columns = 2
  )

  expect_true(result$success)
  expect_true(!is.null(result$section_id))
})

test_that("add_form_field adds field", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "FIELD_TEST",
    form_name = "Field Test",
    created_by = "designer"
  )

  section <- add_form_section(
    design_id = form$design_id,
    section_code = "SEC1",
    section_name = "Section 1",
    section_order = 1
  )

  result <- add_form_field(
    design_id = form$design_id,
    field_code = "SUBJID",
    field_label = "Subject ID",
    field_type = "TEXT",
    section_id = section$section_id,
    field_row = 1,
    field_column = 1,
    is_required = TRUE,
    placeholder = "Enter subject ID",
    help_text = "Unique identifier for the subject"
  )

  expect_true(result$success)
  expect_true(!is.null(result$field_id))
})

test_that("add_form_field validates type", {
  result <- add_form_field(
    design_id = 1,
    field_code = "TEST",
    field_label = "Test",
    field_type = "INVALID_TYPE"
  )
  expect_false(result$success)
})

test_that("add_field_option adds option", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "OPTION_TEST",
    form_name = "Option Test",
    created_by = "designer"
  )

  field <- add_form_field(
    design_id = form$design_id,
    field_code = "SEX",
    field_label = "Sex",
    field_type = "RADIO"
  )

  result1 <- add_field_option(
    field_id = field$field_id,
    option_value = "M",
    option_label = "Male",
    option_order = 1
  )

  result2 <- add_field_option(
    field_id = field$field_id,
    option_value = "F",
    option_label = "Female",
    option_order = 2
  )

  expect_true(result1$success)
  expect_true(result2$success)
})

test_that("update_field_position updates position", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "POS_TEST",
    form_name = "Position Test",
    created_by = "designer"
  )

  field <- add_form_field(
    design_id = form$design_id,
    field_code = "FIELD1",
    field_label = "Field 1",
    field_type = "TEXT"
  )

  result <- update_field_position(
    field_id = field$field_id,
    field_row = 2,
    field_column = 2
  )

  expect_true(result$success)
})

test_that("update_field_position requires updates", {
  result <- update_field_position(field_id = 1)
  expect_false(result$success)
})

test_that("update_form_status updates status", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "STATUS_TEST",
    form_name = "Status Test",
    created_by = "designer"
  )

  result <- update_form_status(
    design_id = form$design_id,
    new_status = "REVIEW",
    updated_by = "manager"
  )

  expect_true(result$success)
})

test_that("update_form_status validates status", {
  result <- update_form_status(
    design_id = 1,
    new_status = "INVALID",
    updated_by = "user"
  )
  expect_false(result$success)
})

test_that("lock_form_design locks form", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "LOCK_TEST",
    form_name = "Lock Test",
    created_by = "designer"
  )

  result <- lock_form_design(form$design_id, "admin")
  expect_true(result$success)

  con <- connect_encrypted_db()
  locked <- DBI::dbGetQuery(con, "
    SELECT is_locked FROM designer_forms WHERE design_id = ?
  ", params = list(form$design_id))$is_locked[1]
  DBI::dbDisconnect(con)

  expect_equal(locked, 1)
})

test_that("get_designer_form returns full details", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "GET_TEST",
    form_name = "Get Test",
    created_by = "designer"
  )

  section <- add_form_section(
    design_id = form$design_id,
    section_code = "SEC1",
    section_name = "Section 1",
    section_order = 1
  )

  add_form_field(
    design_id = form$design_id,
    field_code = "F1",
    field_label = "Field 1",
    field_type = "TEXT",
    section_id = section$section_id
  )

  result <- get_designer_form(form$design_id)
  expect_true(result$success)
  expect_true("form" %in% names(result))
  expect_true("sections" %in% names(result))
  expect_true("fields" %in% names(result))
})

test_that("get_designer_form handles not found", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  result <- get_designer_form(99999)
  expect_false(result$success)
})

test_that("get_designer_forms retrieves list", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  create_designer_form(
    form_code = "LIST_TEST",
    form_name = "List Test",
    created_by = "designer"
  )

  result <- get_designer_forms()
  expect_true(result$success)
  expect_true(result$count >= 1)
})

test_that("get_designer_forms filters by status", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "FILTER_TEST",
    form_name = "Filter Test",
    created_by = "designer"
  )
  update_form_status(form$design_id, "ACTIVE", "admin")

  result <- get_designer_forms(status = "ACTIVE")
  expect_true(result$success)
})

test_that("get_section_fields retrieves section fields", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "SEC_FIELDS_TEST",
    form_name = "Section Fields Test",
    created_by = "designer"
  )

  section <- add_form_section(
    design_id = form$design_id,
    section_code = "SEC1",
    section_name = "Section 1",
    section_order = 1
  )

  add_form_field(
    design_id = form$design_id,
    field_code = "F1",
    field_label = "Field 1",
    field_type = "TEXT",
    section_id = section$section_id
  )

  add_form_field(
    design_id = form$design_id,
    field_code = "F2",
    field_label = "Field 2",
    field_type = "NUMBER",
    section_id = section$section_id
  )

  result <- get_section_fields(section$section_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("get_field_options retrieves options", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "OPTIONS_TEST",
    form_name = "Options Test",
    created_by = "designer"
  )

  field <- add_form_field(
    design_id = form$design_id,
    field_code = "STATUS",
    field_label = "Status",
    field_type = "SELECT"
  )

  add_field_option(field$field_id, "A", "Active", 1)
  add_field_option(field$field_id, "I", "Inactive", 2)

  result <- get_field_options(field$field_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("delete_form_field deletes field", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  form <- create_designer_form(
    form_code = "DELETE_TEST",
    form_name = "Delete Test",
    created_by = "designer"
  )

  field <- add_form_field(
    design_id = form$design_id,
    field_code = "TO_DELETE",
    field_label = "To Delete",
    field_type = "TEXT"
  )

  result <- delete_form_field(field$field_id)
  expect_true(result$success)

  form_data <- get_designer_form(form$design_id)
  expect_equal(nrow(form_data$fields), 0)
})

test_that("get_crf_designer_statistics returns stats", {
  setup_cd_test()
  on.exit(cleanup_cd_test())

  result <- get_crf_designer_statistics()
  expect_true(result$success)
  expect_true("statistics" %in% names(result))
  expect_true("by_status" %in% names(result))
  expect_true("by_type" %in% names(result))
})
