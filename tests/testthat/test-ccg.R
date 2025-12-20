# Test CCG System (CRF Completion Guidelines Generator)
# Feature #19 - GDPR/FDA Implementation

library(testthat)

# ============================================================================
# TEST SETUP
# ============================================================================

setup_ccg_test_env <- function() {
  if (!exists("test_db_initialized", envir = .GlobalEnv) ||
      !get("test_db_initialized", envir = .GlobalEnv)) {
    Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
    Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_ccg_testing_32chars!")
    initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
    init_audit_logging()
    assign("test_db_initialized", TRUE, envir = .GlobalEnv)
  }
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

test_that("init_ccg creates required tables", {
  setup_ccg_test_env()

  result <- init_ccg()
  expect_true(result$success)

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  tables <- DBI::dbListTables(con)
  expect_true("ccg_forms" %in% tables)
  expect_true("ccg_fields" %in% tables)
  expect_true("ccg_versions" %in% tables)
  expect_true("ccg_generated" %in% tables)
})

test_that("init_ccg is idempotent", {
  setup_ccg_test_env()

  result1 <- init_ccg()
  result2 <- init_ccg()

  expect_true(result1$success)
  expect_true(result2$success)
})

# ============================================================================
# REFERENCE DATA TESTS
# ============================================================================

test_that("get_ccg_field_types returns valid types", {
  types <- get_ccg_field_types()

  expect_type(types, "character")
  expect_true(length(types) > 0)
  expect_true("TEXT" %in% names(types))
  expect_true("NUMBER" %in% names(types))
  expect_true("DATE" %in% names(types))
  expect_true("CHECKBOX" %in% names(types))
  expect_true("RADIO" %in% names(types))
  expect_true("DROPDOWN" %in% names(types))
  expect_true("CALCULATED" %in% names(types))
  expect_true("SIGNATURE" %in% names(types))
})

test_that("get_ccg_form_categories returns valid categories", {
  categories <- get_ccg_form_categories()

  expect_type(categories, "character")
  expect_true(length(categories) > 0)
  expect_true("DEMOGRAPHICS" %in% names(categories))
  expect_true("ELIGIBILITY" %in% names(categories))
  expect_true("ADVERSE_EVENTS" %in% names(categories))
  expect_true("VITAL_SIGNS" %in% names(categories))
  expect_true("LAB_RESULTS" %in% names(categories))
})

test_that("get_ccg_form_statuses returns valid statuses", {
  statuses <- get_ccg_form_statuses()

  expect_type(statuses, "character")
  expect_true(length(statuses) > 0)
  expect_true("DRAFT" %in% names(statuses))
  expect_true("REVIEW" %in% names(statuses))
  expect_true("APPROVED" %in% names(statuses))
  expect_true("RETIRED" %in% names(statuses))
})

test_that("get_ccg_visit_types returns valid visit types", {
  visits <- get_ccg_visit_types()

  expect_type(visits, "character")
  expect_true(length(visits) > 0)
  expect_true("SCREENING" %in% names(visits))
  expect_true("BASELINE" %in% names(visits))
  expect_true("TREATMENT" %in% names(visits))
  expect_true("FOLLOW_UP" %in% names(visits))
  expect_true("END_OF_STUDY" %in% names(visits))
})

# ============================================================================
# FORM MANAGEMENT TESTS
# ============================================================================

test_that("create_ccg_form creates form successfully", {
  setup_ccg_test_env()
  init_ccg()

  form_code <- paste0("DM_", format(Sys.time(), "%H%M%S"))

  result <- create_ccg_form(
    form_code = form_code,
    form_name = "Demographics Form",
    created_by = "test_user",
    form_description = "Collects subject demographic information",
    form_category = "DEMOGRAPHICS",
    visit_type = "SCREENING",
    estimated_duration_minutes = 10
  )

  expect_true(result$success)
  expect_true(!is.null(result$form_id))
  expect_equal(result$form_code, form_code)
})

test_that("create_ccg_form validates required fields", {
  setup_ccg_test_env()

  result1 <- create_ccg_form(
    form_code = "",
    form_name = "Test Form",
    created_by = "user"
  )
  expect_false(result1$success)
  expect_match(result1$error, "form_code")

  result2 <- create_ccg_form(
    form_code = "TEST",
    form_name = "",
    created_by = "user"
  )
  expect_false(result2$success)
  expect_match(result2$error, "form_name")
})

test_that("create_ccg_form validates category", {
  setup_ccg_test_env()

  result <- create_ccg_form(
    form_code = paste0("TEST_", format(Sys.time(), "%H%M%S")),
    form_name = "Test Form",
    created_by = "user",
    form_category = "INVALID_CATEGORY"
  )

  expect_false(result$success)
  expect_match(result$error, "Invalid form_category")
})

test_that("create_ccg_form validates visit type", {
  setup_ccg_test_env()

  result <- create_ccg_form(
    form_code = paste0("TEST2_", format(Sys.time(), "%H%M%S")),
    form_name = "Test Form",
    created_by = "user",
    visit_type = "INVALID_VISIT"
  )

  expect_false(result$success)
  expect_match(result$error, "Invalid visit_type")
})

test_that("create_ccg_form rejects duplicate form_code", {
  setup_ccg_test_env()

  code <- paste0("DUP_", format(Sys.time(), "%H%M%S"))

  result1 <- create_ccg_form(
    form_code = code,
    form_name = "First Form",
    created_by = "user"
  )
  expect_true(result1$success)

  result2 <- create_ccg_form(
    form_code = code,
    form_name = "Duplicate Form",
    created_by = "user"
  )
  expect_false(result2$success)
  expect_match(result2$error, "already exists")
})

test_that("get_ccg_forms retrieves forms", {
  setup_ccg_test_env()
  init_ccg()

  code <- paste0("GET_", format(Sys.time(), "%H%M%S"))
  create_ccg_form(
    form_code = code,
    form_name = "Retrieval Test Form",
    created_by = "user",
    form_category = "ELIGIBILITY"
  )

  result <- get_ccg_forms()
  expect_true(result$success)
  expect_true(result$count > 0)
  expect_true("forms" %in% names(result))
})

test_that("get_ccg_forms filters by category", {
  setup_ccg_test_env()

  code <- paste0("CAT_", format(Sys.time(), "%H%M%S"))
  create_ccg_form(
    form_code = code,
    form_name = "Category Filter Test",
    created_by = "user",
    form_category = "ADVERSE_EVENTS"
  )

  result <- get_ccg_forms(form_category = "ADVERSE_EVENTS")
  expect_true(result$success)
  if (result$count > 0) {
    expect_true(all(result$forms$form_category == "ADVERSE_EVENTS"))
  }
})

test_that("get_ccg_forms filters by status", {
  setup_ccg_test_env()

  result <- get_ccg_forms(status = "DRAFT")
  expect_true(result$success)
  if (result$count > 0) {
    expect_true(all(result$forms$status == "DRAFT"))
  }
})

test_that("update_ccg_form_status changes status", {
  setup_ccg_test_env()

  code <- paste0("STAT_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = code,
    form_name = "Status Update Test",
    created_by = "user"
  )

  result <- update_ccg_form_status(
    form_id = form$form_id,
    status = "REVIEW",
    updated_by = "reviewer"
  )

  expect_true(result$success)
  expect_match(result$message, "REVIEW")
})

test_that("update_ccg_form_status validates status values", {
  setup_ccg_test_env()

  code <- paste0("INVS_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = code,
    form_name = "Invalid Status Test",
    created_by = "user"
  )

  result <- update_ccg_form_status(
    form_id = form$form_id,
    status = "INVALID_STATUS",
    updated_by = "user"
  )

  expect_false(result$success)
  expect_match(result$error, "Invalid status")
})

test_that("update_ccg_form_status sets approval fields for APPROVED", {
  setup_ccg_test_env()

  code <- paste0("APPR_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = code,
    form_name = "Approval Test",
    created_by = "user"
  )

  result <- update_ccg_form_status(
    form_id = form$form_id,
    status = "APPROVED",
    updated_by = "approver"
  )

  expect_true(result$success)

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  updated <- DBI::dbGetQuery(con, "
    SELECT approved_at, approved_by FROM ccg_forms WHERE form_id = ?
  ", params = list(form$form_id))

  expect_false(is.na(updated$approved_at[1]))
  expect_equal(updated$approved_by[1], "approver")
})

# ============================================================================
# FIELD MANAGEMENT TESTS
# ============================================================================

test_that("add_ccg_field adds field to form", {
  setup_ccg_test_env()
  init_ccg()

  form_code <- paste0("FLD_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Field Test Form",
    created_by = "user"
  )

  result <- add_ccg_field(
    form_id = form$form_id,
    field_code = "SUBJID",
    field_name = "Subject ID",
    field_label = "Subject Identifier",
    field_type = "TEXT",
    field_order = 1,
    is_required = TRUE,
    is_key_field = TRUE,
    instruction = "Enter the unique subject identifier",
    example_entries = "SUBJ-001, SUBJ-002"
  )

  expect_true(result$success)
  expect_true(!is.null(result$field_id))
  expect_equal(result$field_code, "SUBJID")
})

test_that("add_ccg_field validates required parameters", {
  setup_ccg_test_env()

  result <- add_ccg_field(
    form_id = NULL,
    field_code = "TEST",
    field_name = "Test",
    field_label = "Test",
    field_type = "TEXT",
    field_order = 1
  )
  expect_false(result$success)
  expect_match(result$error, "form_id")
})

test_that("add_ccg_field validates field_code", {
  setup_ccg_test_env()

  form_code <- paste0("FLD2_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Field Code Test",
    created_by = "user"
  )

  result <- add_ccg_field(
    form_id = form$form_id,
    field_code = "",
    field_name = "Test",
    field_label = "Test",
    field_type = "TEXT",
    field_order = 1
  )
  expect_false(result$success)
  expect_match(result$error, "field_code")
})

test_that("add_ccg_field validates field_type", {
  setup_ccg_test_env()

  form_code <- paste0("FLD3_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Field Type Test",
    created_by = "user"
  )

  result <- add_ccg_field(
    form_id = form$form_id,
    field_code = "TEST",
    field_name = "Test",
    field_label = "Test",
    field_type = "INVALID_TYPE",
    field_order = 1
  )
  expect_false(result$success)
  expect_match(result$error, "Invalid field_type")
})

test_that("add_ccg_field rejects nonexistent form", {
  setup_ccg_test_env()

  result <- add_ccg_field(
    form_id = 99999,
    field_code = "TEST",
    field_name = "Test",
    field_label = "Test",
    field_type = "TEXT",
    field_order = 1
  )
  expect_false(result$success)
  expect_match(result$error, "Form not found")
})

test_that("add_ccg_field rejects duplicate field_code in same form", {
  setup_ccg_test_env()

  form_code <- paste0("DUPF_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Duplicate Field Test",
    created_by = "user"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "FIELD1",
    field_name = "Field 1",
    field_label = "Field 1",
    field_type = "TEXT",
    field_order = 1
  )

  result <- add_ccg_field(
    form_id = form$form_id,
    field_code = "FIELD1",
    field_name = "Duplicate Field",
    field_label = "Duplicate",
    field_type = "TEXT",
    field_order = 2
  )
  expect_false(result$success)
  expect_match(result$error, "already exists")
})

test_that("add_ccg_field stores all field properties", {
  setup_ccg_test_env()

  form_code <- paste0("PROP_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Property Test Form",
    created_by = "user"
  )

  result <- add_ccg_field(
    form_id = form$form_id,
    field_code = "AGE",
    field_name = "Age",
    field_label = "Subject Age",
    field_type = "INTEGER",
    field_order = 1,
    section_name = "Demographics",
    is_required = TRUE,
    instruction = "Enter age in years",
    detailed_guidance = "Round down to completed years",
    valid_range_min = "18",
    valid_range_max = "120",
    units = "years",
    example_entries = "45, 62, 33",
    common_errors = "Entering age in months",
    source_document = "Medical records",
    edit_checks = "Must be >= 18 for eligibility",
    sdtm_domain = "DM",
    sdtm_variable = "AGE"
  )

  expect_true(result$success)

  fields <- get_ccg_fields(form$form_id)
  expect_true(fields$success)
  expect_equal(nrow(fields$fields), 1)

  field <- fields$fields[1, ]
  expect_equal(field$section_name, "Demographics")
  expect_equal(field$valid_range_min, "18")
  expect_equal(field$valid_range_max, "120")
  expect_equal(field$units, "years")
  expect_equal(field$sdtm_domain, "DM")
  expect_equal(field$sdtm_variable, "AGE")
})

test_that("get_ccg_fields retrieves fields in order", {
  setup_ccg_test_env()

  form_code <- paste0("ORD_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Order Test Form",
    created_by = "user"
  )

  add_ccg_field(form_id = form$form_id, field_code = "F3",
                field_name = "F3", field_label = "F3",
                field_type = "TEXT", field_order = 3)
  add_ccg_field(form_id = form$form_id, field_code = "F1",
                field_name = "F1", field_label = "F1",
                field_type = "TEXT", field_order = 1)
  add_ccg_field(form_id = form$form_id, field_code = "F2",
                field_name = "F2", field_label = "F2",
                field_type = "TEXT", field_order = 2)

  result <- get_ccg_fields(form$form_id)
  expect_true(result$success)
  expect_equal(result$count, 3)
  expect_equal(result$fields$field_code, c("F1", "F2", "F3"))
})

test_that("get_ccg_fields filters by section", {
  setup_ccg_test_env()

  form_code <- paste0("SEC_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Section Test Form",
    created_by = "user"
  )

  add_ccg_field(form_id = form$form_id, field_code = "S1F1",
                field_name = "S1F1", field_label = "S1F1",
                field_type = "TEXT", field_order = 1,
                section_name = "Section A")
  add_ccg_field(form_id = form$form_id, field_code = "S2F1",
                field_name = "S2F1", field_label = "S2F1",
                field_type = "TEXT", field_order = 2,
                section_name = "Section B")

  result <- get_ccg_fields(form$form_id, section_name = "Section A")
  expect_true(result$success)
  expect_equal(result$count, 1)
  expect_equal(result$fields$field_code[1], "S1F1")
})

test_that("update_ccg_field updates field properties", {
  setup_ccg_test_env()

  form_code <- paste0("UPD_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Update Field Test",
    created_by = "user"
  )

  field <- add_ccg_field(
    form_id = form$form_id,
    field_code = "UPD_FIELD",
    field_name = "Update Field",
    field_label = "Field to Update",
    field_type = "TEXT",
    field_order = 1,
    instruction = "Original instruction"
  )

  result <- update_ccg_field(
    field_id = field$field_id,
    instruction = "Updated instruction",
    detailed_guidance = "New detailed guidance",
    example_entries = "Example 1, Example 2"
  )

  expect_true(result$success)

  fields <- get_ccg_fields(form$form_id)
  updated <- fields$fields[1, ]
  expect_equal(updated$instruction, "Updated instruction")
  expect_equal(updated$detailed_guidance, "New detailed guidance")
  expect_equal(updated$example_entries, "Example 1, Example 2")
})

test_that("update_ccg_field requires at least one update", {
  setup_ccg_test_env()

  result <- update_ccg_field(field_id = 1)
  expect_false(result$success)
  expect_match(result$error, "No updates")
})

# ============================================================================
# VERSION MANAGEMENT TESTS
# ============================================================================

test_that("create_ccg_version creates version record", {
  setup_ccg_test_env()
  init_ccg()

  form_code <- paste0("VER_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Version Test Form",
    created_by = "user"
  )

  result <- create_ccg_version(
    form_id = form$form_id,
    version_number = "2.0",
    change_summary = "Added new fields for adverse event reporting",
    created_by = "developer",
    change_details = "Added severity field and outcome field"
  )

  expect_true(result$success)
  expect_true(!is.null(result$version_id))
  expect_equal(result$version_number, "2.0")
  expect_equal(result$previous_version, "1.0")
})

test_that("create_ccg_version validates required fields", {
  setup_ccg_test_env()

  result1 <- create_ccg_version(
    form_id = NULL,
    version_number = "2.0",
    change_summary = "Test changes",
    created_by = "user"
  )
  expect_false(result1$success)
  expect_match(result1$error, "form_id")

  form_code <- paste0("VER2_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Version Validation Test",
    created_by = "user"
  )

  result2 <- create_ccg_version(
    form_id = form$form_id,
    version_number = "",
    change_summary = "Test changes",
    created_by = "user"
  )
  expect_false(result2$success)
  expect_match(result2$error, "version_number")

  result3 <- create_ccg_version(
    form_id = form$form_id,
    version_number = "2.0",
    change_summary = "Short",
    created_by = "user"
  )
  expect_false(result3$success)
  expect_match(result3$error, "at least 10 characters")
})

test_that("create_ccg_version rejects nonexistent form", {
  setup_ccg_test_env()

  result <- create_ccg_version(
    form_id = 99999,
    version_number = "2.0",
    change_summary = "Test changes to nonexistent form",
    created_by = "user"
  )
  expect_false(result$success)
  expect_match(result$error, "Form not found")
})

test_that("create_ccg_version updates form version", {
  setup_ccg_test_env()

  form_code <- paste0("VERUP_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Version Update Test",
    created_by = "user"
  )

  create_ccg_version(
    form_id = form$form_id,
    version_number = "1.5",
    change_summary = "Updated to version 1.5 with bug fixes",
    created_by = "developer"
  )

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  updated <- DBI::dbGetQuery(con, "
    SELECT version FROM ccg_forms WHERE form_id = ?
  ", params = list(form$form_id))

  expect_equal(updated$version[1], "1.5")
})

test_that("get_ccg_versions retrieves version history", {
  setup_ccg_test_env()

  form_code <- paste0("HIST_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "History Test Form",
    created_by = "user"
  )

  create_ccg_version(
    form_id = form$form_id,
    version_number = "1.1",
    change_summary = "First update with minor changes",
    created_by = "dev1"
  )

  create_ccg_version(
    form_id = form$form_id,
    version_number = "1.2",
    change_summary = "Second update with additional fields",
    created_by = "dev2"
  )

  result <- get_ccg_versions(form$form_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
  expect_equal(result$versions$version_number[1], "1.2")
  expect_equal(result$versions$version_number[2], "1.1")
})

test_that("approve_ccg_version approves version", {
  setup_ccg_test_env()

  form_code <- paste0("APVE_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Approval Test Form",
    created_by = "user"
  )

  version <- create_ccg_version(
    form_id = form$form_id,
    version_number = "2.0",
    change_summary = "Major update requiring approval",
    created_by = "developer"
  )

  result <- approve_ccg_version(
    version_id = version$version_id,
    approved_by = "qa_manager"
  )

  expect_true(result$success)
  expect_true(!is.null(result$approved_at))

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  approved <- DBI::dbGetQuery(con, "
    SELECT status, approved_by FROM ccg_versions WHERE version_id = ?
  ", params = list(version$version_id))

  expect_equal(approved$status[1], "APPROVED")
  expect_equal(approved$approved_by[1], "qa_manager")
})

# ============================================================================
# CCG GENERATION TESTS
# ============================================================================

test_that("generate_ccg creates TXT document", {
  setup_ccg_test_env()
  init_ccg()

  form_code <- paste0("GTXT_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "TXT Generation Test",
    created_by = "user",
    form_description = "Test form for TXT generation",
    form_category = "DEMOGRAPHICS"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "SUBJID",
    field_name = "Subject ID",
    field_label = "Subject Identifier",
    field_type = "TEXT",
    field_order = 1,
    is_required = TRUE,
    is_key_field = TRUE,
    instruction = "Enter unique subject identifier",
    example_entries = "SUBJ-001"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "DOB",
    field_name = "Date of Birth",
    field_label = "Date of Birth",
    field_type = "DATE",
    field_order = 2,
    is_required = TRUE,
    instruction = "Enter date of birth",
    format_pattern = "YYYY-MM-DD"
  )

  output_file <- tempfile(fileext = ".txt")

  result <- generate_ccg(
    form_id = form$form_id,
    output_file = output_file,
    format = "txt",
    generated_by = "tester",
    study_name = "Test Study",
    protocol_number = "PROT-001"
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))
  expect_equal(result$format, "txt")
  expect_equal(result$field_count, 2)

  content <- readLines(output_file)
  expect_true(any(grepl("CRF COMPLETION GUIDELINES", content)))
  expect_true(any(grepl("Subject Identifier", content)))
  expect_true(any(grepl("REQUIRED", content)))
  expect_true(any(grepl("PROT-001", content)))

  unlink(output_file)
})

test_that("generate_ccg creates MD document", {
  setup_ccg_test_env()

  form_code <- paste0("GMD_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "MD Generation Test",
    created_by = "user"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "WEIGHT",
    field_name = "Weight",
    field_label = "Body Weight",
    field_type = "NUMBER",
    field_order = 1,
    is_required = TRUE,
    instruction = "Enter weight in kg",
    valid_range_min = "30",
    valid_range_max = "250",
    units = "kg"
  )

  output_file <- tempfile(fileext = ".md")

  result <- generate_ccg(
    form_id = form$form_id,
    output_file = output_file,
    format = "md",
    generated_by = "tester"
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))

  content <- readLines(output_file)
  expect_true(any(grepl("^# CRF Completion Guidelines", content)))
  expect_true(any(grepl("Body Weight", content)))
  expect_true(any(grepl("\\*\\*Code:\\*\\*", content)))

  unlink(output_file)
})

test_that("generate_ccg creates HTML document", {
  setup_ccg_test_env()

  form_code <- paste0("GHTML_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "HTML Generation Test",
    created_by = "user"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "HEIGHT",
    field_name = "Height",
    field_label = "Body Height",
    field_type = "NUMBER",
    field_order = 1,
    instruction = "Enter height in cm",
    section_name = "Anthropometrics"
  )

  output_file <- tempfile(fileext = ".html")

  result <- generate_ccg(
    form_id = form$form_id,
    output_file = output_file,
    format = "html",
    generated_by = "tester"
  )

  expect_true(result$success)
  expect_true(file.exists(output_file))

  content <- paste(readLines(output_file), collapse = "\n")
  expect_true(grepl("<!DOCTYPE html>", content))
  expect_true(grepl("<h1>CRF Completion Guidelines</h1>", content))
  expect_true(grepl("Body Height", content))
  expect_true(grepl("Anthropometrics", content))

  unlink(output_file)
})

test_that("generate_ccg validates required parameters", {
  setup_ccg_test_env()

  result1 <- generate_ccg(
    form_id = NULL,
    output_file = "test.txt",
    generated_by = "user"
  )
  expect_false(result1$success)
  expect_match(result1$error, "form_id")

  result2 <- generate_ccg(
    form_id = 1,
    output_file = "",
    generated_by = "user"
  )
  expect_false(result2$success)
  expect_match(result2$error, "output_file")

  result3 <- generate_ccg(
    form_id = 1,
    output_file = "test.xyz",
    format = "xyz",
    generated_by = "user"
  )
  expect_false(result3$success)
  expect_match(result3$error, "format must be")
})

test_that("generate_ccg rejects nonexistent form", {
  setup_ccg_test_env()

  result <- generate_ccg(
    form_id = 99999,
    output_file = tempfile(fileext = ".txt"),
    generated_by = "user"
  )
  expect_false(result$success)
  expect_match(result$error, "Form not found")
})

test_that("generate_ccg rejects form with no fields", {
  setup_ccg_test_env()

  form_code <- paste0("EMPTY_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Empty Form",
    created_by = "user"
  )

  result <- generate_ccg(
    form_id = form$form_id,
    output_file = tempfile(fileext = ".txt"),
    generated_by = "user"
  )
  expect_false(result$success)
  expect_match(result$error, "No fields")
})

test_that("generate_ccg includes SDTM mapping when requested", {
  setup_ccg_test_env()

  form_code <- paste0("SDTM_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "SDTM Test Form",
    created_by = "user"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "AGE",
    field_name = "Age",
    field_label = "Subject Age",
    field_type = "INTEGER",
    field_order = 1,
    sdtm_domain = "DM",
    sdtm_variable = "AGE"
  )

  output_file <- tempfile(fileext = ".txt")

  result <- generate_ccg(
    form_id = form$form_id,
    output_file = output_file,
    format = "txt",
    generated_by = "tester",
    include_sdtm_mapping = TRUE
  )

  expect_true(result$success)

  content <- readLines(output_file)
  expect_true(any(grepl("SDTM Domain: DM", content)))
  expect_true(any(grepl("SDTM Variable: AGE", content)))

  unlink(output_file)
})

test_that("generate_ccg logs generation to database", {
  setup_ccg_test_env()

  form_code <- paste0("LOG_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Log Test Form",
    created_by = "user"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "TEST",
    field_name = "Test",
    field_label = "Test Field",
    field_type = "TEXT",
    field_order = 1
  )

  output_file <- tempfile(fileext = ".txt")

  generate_ccg(
    form_id = form$form_id,
    output_file = output_file,
    format = "txt",
    generated_by = "log_tester"
  )

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  generated <- DBI::dbGetQuery(con, "
    SELECT * FROM ccg_generated WHERE form_id = ?
  ", params = list(form$form_id))

  expect_equal(nrow(generated), 1)
  expect_equal(generated$generated_by[1], "log_tester")
  expect_equal(generated$output_format[1], "txt")
  expect_false(is.na(generated$generation_hash[1]))

  unlink(output_file)
})

# ============================================================================
# STATISTICS TESTS
# ============================================================================

test_that("get_ccg_statistics returns statistics", {
  setup_ccg_test_env()
  init_ccg()

  form_code <- paste0("STAT_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Statistics Test Form",
    created_by = "user",
    form_category = "VITAL_SIGNS"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "STAT_F1",
    field_name = "Stat Field 1",
    field_label = "Field 1",
    field_type = "TEXT",
    field_order = 1,
    is_required = TRUE,
    is_key_field = TRUE
  )

  result <- get_ccg_statistics()

  expect_true(result$success)
  expect_true("forms" %in% names(result))
  expect_true("fields" %in% names(result))
  expect_true("generations" %in% names(result))
  expect_true("by_category" %in% names(result))

  expect_true(result$forms$total >= 1)
  expect_true(result$fields$total >= 1)
  expect_true(result$fields$required_fields >= 1)
  expect_true(result$fields$key_fields >= 1)
})

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

test_that("complete CCG workflow works end-to-end", {
  setup_ccg_test_env()
  init_ccg()

  form_code <- paste0("INT_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Integration Test - Demographics CRF",
    created_by = "crf_developer",
    form_description = "Comprehensive demographics form for clinical trials",
    form_category = "DEMOGRAPHICS",
    visit_type = "SCREENING",
    estimated_duration_minutes = 15
  )
  expect_true(form$success)

  field1 <- add_ccg_field(
    form_id = form$form_id,
    field_code = "SUBJID",
    field_name = "Subject ID",
    field_label = "Subject Identifier",
    field_type = "TEXT",
    field_order = 1,
    section_name = "Identification",
    is_required = TRUE,
    is_key_field = TRUE,
    instruction = "Enter unique subject identifier assigned at screening",
    detailed_guidance = paste(
      "Format: SITE-XXXX where SITE is 3-letter site code",
      "and XXXX is sequential 4-digit number"
    ),
    format_pattern = "AAA-0000",
    example_entries = "NYC-0001, LAX-0042",
    common_errors = "Using lowercase letters, missing hyphen",
    sdtm_domain = "DM",
    sdtm_variable = "USUBJID"
  )
  expect_true(field1$success)

  field2 <- add_ccg_field(
    form_id = form$form_id,
    field_code = "BRTHDTC",
    field_name = "Birth Date",
    field_label = "Date of Birth",
    field_type = "DATE",
    field_order = 2,
    section_name = "Demographics",
    is_required = TRUE,
    instruction = "Enter date of birth from verified source",
    format_pattern = "YYYY-MM-DD",
    source_document = "Government-issued ID or medical records",
    sdtm_domain = "DM",
    sdtm_variable = "BRTHDTC"
  )
  expect_true(field2$success)

  field3 <- add_ccg_field(
    form_id = form$form_id,
    field_code = "SEX",
    field_name = "Sex",
    field_label = "Biological Sex",
    field_type = "RADIO",
    field_order = 3,
    section_name = "Demographics",
    is_required = TRUE,
    instruction = "Select biological sex at birth",
    valid_values = "M = Male; F = Female; U = Unknown/Not specified",
    edit_checks = "Must be provided for all subjects",
    sdtm_domain = "DM",
    sdtm_variable = "SEX"
  )
  expect_true(field3$success)

  field4 <- add_ccg_field(
    form_id = form$form_id,
    field_code = "ETHNIC",
    field_name = "Ethnicity",
    field_label = "Ethnicity",
    field_type = "DROPDOWN",
    field_order = 4,
    section_name = "Demographics",
    is_required = FALSE,
    instruction = "Select ethnicity as reported by subject",
    valid_values = paste(
      "HISPANIC OR LATINO;",
      "NOT HISPANIC OR LATINO;",
      "NOT REPORTED;",
      "UNKNOWN"
    ),
    sdtm_domain = "DM",
    sdtm_variable = "ETHNIC"
  )
  expect_true(field4$success)

  review_result <- update_ccg_form_status(
    form_id = form$form_id,
    status = "REVIEW",
    updated_by = "qa_reviewer"
  )
  expect_true(review_result$success)

  version <- create_ccg_version(
    form_id = form$form_id,
    version_number = "1.1",
    change_summary = "Initial CCG version after QA review",
    created_by = "crf_developer",
    change_details = "Added detailed guidance for all fields",
    effective_date = format(Sys.Date() + 7, "%Y-%m-%d")
  )
  expect_true(version$success)

  approval <- approve_ccg_version(
    version_id = version$version_id,
    approved_by = "study_manager"
  )
  expect_true(approval$success)

  form_approval <- update_ccg_form_status(
    form_id = form$form_id,
    status = "APPROVED",
    updated_by = "study_manager"
  )
  expect_true(form_approval$success)

  output_txt <- tempfile(fileext = ".txt")
  gen_txt <- generate_ccg(
    form_id = form$form_id,
    output_file = output_txt,
    format = "txt",
    generated_by = "doc_controller",
    include_examples = TRUE,
    include_edit_checks = TRUE,
    include_sdtm_mapping = TRUE,
    study_name = "XYZ-123 Phase III Trial",
    protocol_number = "XYZ-123-PROT-001"
  )
  expect_true(gen_txt$success)
  expect_equal(gen_txt$field_count, 4)

  txt_content <- readLines(output_txt)
  expect_true(any(grepl("XYZ-123", txt_content)))
  expect_true(any(grepl("Subject Identifier", txt_content)))
  expect_true(any(grepl("SDTM Domain: DM", txt_content)))
  expect_true(any(grepl("Demographics", txt_content)))
  unlink(output_txt)

  output_md <- tempfile(fileext = ".md")
  gen_md <- generate_ccg(
    form_id = form$form_id,
    output_file = output_md,
    format = "md",
    generated_by = "doc_controller"
  )
  expect_true(gen_md$success)
  unlink(output_md)

  output_html <- tempfile(fileext = ".html")
  gen_html <- generate_ccg(
    form_id = form$form_id,
    output_file = output_html,
    format = "html",
    generated_by = "doc_controller"
  )
  expect_true(gen_html$success)
  unlink(output_html)

  stats <- get_ccg_statistics()
  expect_true(stats$success)
  expect_true(stats$forms$total >= 1)
  expect_true(stats$forms$approved >= 1)
  expect_true(stats$fields$total >= 4)
  expect_true(stats$generations >= 3)

  versions <- get_ccg_versions(form$form_id)
  expect_true(versions$success)
  expect_equal(versions$count, 1)
  expect_equal(versions$versions$status[1], "APPROVED")

  forms <- get_ccg_forms(status = "APPROVED")
  expect_true(forms$success)
  expect_true(any(forms$forms$form_code == form_code))
})

test_that("CCG handles skip conditions correctly", {
  setup_ccg_test_env()
  init_ccg()

  form_code <- paste0("SKIP_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Skip Logic Test Form",
    created_by = "user"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "PREGNANT",
    field_name = "Pregnancy Status",
    field_label = "Is subject pregnant?",
    field_type = "RADIO",
    field_order = 1,
    valid_values = "Y = Yes; N = No; NA = Not Applicable (Male)",
    instruction = "Select NA for male subjects"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "PREGTEST",
    field_name = "Pregnancy Test",
    field_label = "Pregnancy Test Date",
    field_type = "DATE",
    field_order = 2,
    skip_condition = "PREGNANT = 'NA' or PREGNANT = 'N'",
    skip_instruction = "Skip if male or not pregnant",
    instruction = "Enter date of pregnancy test"
  )

  output_file <- tempfile(fileext = ".txt")

  result <- generate_ccg(
    form_id = form$form_id,
    output_file = output_file,
    format = "txt",
    generated_by = "tester"
  )

  expect_true(result$success)

  content <- readLines(output_file)
  expect_true(any(grepl("Skip If:", content)))
  expect_true(any(grepl("PREGNANT = 'NA'", content)))
  expect_true(any(grepl("Skip if male", content)))

  unlink(output_file)
})

test_that("CCG handles sections correctly in output", {
  setup_ccg_test_env()
  init_ccg()

  form_code <- paste0("SECT_", format(Sys.time(), "%H%M%S"))
  form <- create_ccg_form(
    form_code = form_code,
    form_name = "Section Test Form",
    created_by = "user"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "ID1",
    field_name = "ID 1",
    field_label = "Identifier 1",
    field_type = "TEXT",
    field_order = 1,
    section_name = "Identification"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "ID2",
    field_name = "ID 2",
    field_label = "Identifier 2",
    field_type = "TEXT",
    field_order = 2,
    section_name = "Identification"
  )

  add_ccg_field(
    form_id = form$form_id,
    field_code = "VS1",
    field_name = "VS 1",
    field_label = "Vital Sign 1",
    field_type = "NUMBER",
    field_order = 3,
    section_name = "Vital Signs"
  )

  output_file <- tempfile(fileext = ".txt")

  result <- generate_ccg(
    form_id = form$form_id,
    output_file = output_file,
    format = "txt",
    generated_by = "tester"
  )

  expect_true(result$success)

  content <- readLines(output_file)
  expect_true(any(grepl("SECTION: Identification", content)))
  expect_true(any(grepl("SECTION: Vital Signs", content)))

  id_section_line <- which(grepl("SECTION: Identification", content))[1]
  vs_section_line <- which(grepl("SECTION: Vital Signs", content))[1]
  expect_true(id_section_line < vs_section_line)

  unlink(output_file)
})

# ============================================================================
# CLEANUP
# ============================================================================

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
