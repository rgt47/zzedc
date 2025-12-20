# Test Protocol-CRF Linkage System
# Feature #25

library(testthat)

setup_pl_test_env <- function() {
  if (!exists("test_db_initialized", envir = .GlobalEnv) ||
      !get("test_db_initialized", envir = .GlobalEnv)) {
    Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
    Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_protocol_linkage32!")
    initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
    init_audit_logging()
    assign("test_db_initialized", TRUE, envir = .GlobalEnv)
  }
}

test_that("init_protocol_linkage creates tables", {
  setup_pl_test_env()
  result <- init_protocol_linkage()
  expect_true(result$success)

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("protocol_definitions" %in% tables)
  expect_true("protocol_objectives" %in% tables)
  expect_true("protocol_crf_links" %in% tables)
})

test_that("create_protocol_definition creates protocol", {
  setup_pl_test_env()
  init_protocol_linkage()

  result <- create_protocol_definition(
    protocol_number = paste0("PROT-", format(Sys.time(), "%H%M%S")),
    protocol_title = "Test Protocol",
    created_by = "developer",
    therapeutic_area = "Oncology",
    phase = "Phase 2",
    sponsor = "Test Pharma"
  )

  expect_true(result$success)
  expect_true(!is.null(result$protocol_id))
})

test_that("create_protocol_definition validates required fields", {
  result <- create_protocol_definition(
    protocol_number = "",
    protocol_title = "Test",
    created_by = "user"
  )
  expect_false(result$success)
  expect_true(grepl("required", result$error, ignore.case = TRUE))
})

test_that("add_protocol_objective adds objective", {
  setup_pl_test_env()
  init_protocol_linkage()

  protocol <- create_protocol_definition(
    protocol_number = paste0("OBJ-", format(Sys.time(), "%H%M%S")),
    protocol_title = "Objective Test Protocol",
    created_by = "developer"
  )

  result <- add_protocol_objective(
    protocol_id = protocol$protocol_id,
    objective_type = "PRIMARY",
    objective_description = "Evaluate efficacy of treatment",
    is_primary = TRUE
  )

  expect_true(result$success)
})

test_that("add_protocol_objective supports multiple objectives", {
  setup_pl_test_env()

  protocol <- create_protocol_definition(
    protocol_number = paste0("MULTI-", format(Sys.time(), "%H%M%S")),
    protocol_title = "Multi-Objective Protocol",
    created_by = "developer"
  )

  result1 <- add_protocol_objective(
    protocol_id = protocol$protocol_id,
    objective_type = "PRIMARY",
    objective_description = "Primary efficacy endpoint",
    is_primary = TRUE
  )

  result2 <- add_protocol_objective(
    protocol_id = protocol$protocol_id,
    objective_type = "SECONDARY",
    objective_description = "Secondary safety endpoint",
    is_primary = FALSE
  )

  result3 <- add_protocol_objective(
    protocol_id = protocol$protocol_id,
    objective_type = "EXPLORATORY",
    objective_description = "Exploratory biomarker analysis",
    is_primary = FALSE
  )

  expect_true(result1$success)
  expect_true(result2$success)
  expect_true(result3$success)
})

test_that("link_crf_to_protocol creates link", {
  setup_pl_test_env()
  init_protocol_linkage()

  protocol <- create_protocol_definition(
    protocol_number = paste0("LINK-", format(Sys.time(), "%H%M%S")),
    protocol_title = "Link Test Protocol",
    created_by = "developer"
  )

  result <- link_crf_to_protocol(
    protocol_id = protocol$protocol_id,
    created_by = "crf_designer",
    crf_id = 1,
    form_id = 10,
    field_code = "AETERM",
    link_rationale = "Captures adverse event data for safety objective",
    is_critical = TRUE
  )

  expect_true(result$success)
})

test_that("link_crf_to_protocol with objective", {
  setup_pl_test_env()

  protocol <- create_protocol_definition(
    protocol_number = paste0("LOBJ-", format(Sys.time(), "%H%M%S")),
    protocol_title = "Linked Objective Protocol",
    created_by = "developer"
  )

  add_protocol_objective(
    protocol_id = protocol$protocol_id,
    objective_type = "PRIMARY",
    objective_description = "Efficacy endpoint",
    is_primary = TRUE
  )

  con <- connect_encrypted_db()
  objective_id <- DBI::dbGetQuery(con, "
    SELECT objective_id FROM protocol_objectives ORDER BY objective_id DESC LIMIT 1
  ")$objective_id[1]
  DBI::dbDisconnect(con)

  result <- link_crf_to_protocol(
    protocol_id = protocol$protocol_id,
    created_by = "designer",
    objective_id = objective_id,
    field_code = "EFFICACY_SCORE",
    link_rationale = "Primary efficacy measure",
    is_critical = TRUE
  )

  expect_true(result$success)
})

test_that("get_protocol_definitions retrieves protocols", {
  setup_pl_test_env()
  result <- get_protocol_definitions()
  expect_true(result$success)
  expect_true("protocols" %in% names(result))
  expect_true("count" %in% names(result))
})

test_that("get_protocol_definitions filters inactive", {
  setup_pl_test_env()

  active <- get_protocol_definitions(include_inactive = FALSE)
  all_protocols <- get_protocol_definitions(include_inactive = TRUE)

  expect_true(active$success)
  expect_true(all_protocols$success)
  expect_true(all_protocols$count >= active$count)
})

test_that("get_protocol_crf_links retrieves links", {
  setup_pl_test_env()
  init_protocol_linkage()

  protocol <- create_protocol_definition(
    protocol_number = paste0("GETL-", format(Sys.time(), "%H%M%S")),
    protocol_title = "Get Links Protocol",
    created_by = "developer"
  )

  link_crf_to_protocol(
    protocol_id = protocol$protocol_id,
    created_by = "designer",
    form_id = 1,
    field_code = "FIELD1"
  )

  link_crf_to_protocol(
    protocol_id = protocol$protocol_id,
    created_by = "designer",
    form_id = 2,
    field_code = "FIELD2"
  )

  result <- get_protocol_crf_links(protocol$protocol_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("get_protocol_linkage_statistics returns stats", {
  setup_pl_test_env()
  result <- get_protocol_linkage_statistics()
  expect_true(result$success)
  expect_true("statistics" %in% names(result))
  expect_true("active_protocols" %in% names(result$statistics))
  expect_true("total_links" %in% names(result$statistics))
  expect_true("critical_links" %in% names(result$statistics))
})

test_that("cleanup test environment", {
  if (exists("test_db_initialized", envir = .GlobalEnv)) {
    rm("test_db_initialized", envir = .GlobalEnv)
  }
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) unlink(db_path)
  expect_true(TRUE)
})
