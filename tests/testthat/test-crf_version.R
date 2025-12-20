# Test CRF Version Control & Change Log System
# Feature #20 - CRF Design Implementation

library(testthat)

# ============================================================================
# TEST SETUP
# ============================================================================

setup_crfv_test_env <- function() {
  if (!exists("test_db_initialized", envir = .GlobalEnv) ||
      !get("test_db_initialized", envir = .GlobalEnv)) {
    Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
    Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_crfv_testing_32ch!")
    initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
    init_audit_logging()
    assign("test_db_initialized", TRUE, envir = .GlobalEnv)
  }
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

test_that("init_crf_version creates required tables", {
  setup_crfv_test_env()

  result <- init_crf_version()
  expect_true(result$success)

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  tables <- DBI::dbListTables(con)
  expect_true("crf_definitions" %in% tables)
  expect_true("crf_versions" %in% tables)
  expect_true("crf_change_log" %in% tables)
  expect_true("crf_version_snapshots" %in% tables)
  expect_true("crf_version_comparisons" %in% tables)
})

test_that("init_crf_version is idempotent", {
  setup_crfv_test_env()

  result1 <- init_crf_version()
  result2 <- init_crf_version()

  expect_true(result1$success)
  expect_true(result2$success)
})

# ============================================================================
# REFERENCE DATA TESTS
# ============================================================================

test_that("get_crf_version_types returns valid types", {
  types <- get_crf_version_types()

  expect_type(types, "character")
  expect_true(length(types) > 0)
  expect_true("MAJOR" %in% names(types))
  expect_true("MINOR" %in% names(types))
  expect_true("PATCH" %in% names(types))
  expect_true("HOTFIX" %in% names(types))
})

test_that("get_crf_version_statuses returns valid statuses", {
  statuses <- get_crf_version_statuses()

  expect_type(statuses, "character")
  expect_true("DRAFT" %in% names(statuses))
  expect_true("REVIEW" %in% names(statuses))
  expect_true("APPROVED" %in% names(statuses))
  expect_true("ACTIVE" %in% names(statuses))
  expect_true("SUPERSEDED" %in% names(statuses))
})

test_that("get_crf_change_types returns valid types", {
  types <- get_crf_change_types()

  expect_type(types, "character")
  expect_true("ADD" %in% names(types))
  expect_true("REMOVE" %in% names(types))
  expect_true("MODIFY" %in% names(types))
  expect_true("VALIDATION" %in% names(types))
})

test_that("get_crf_change_categories returns valid categories", {
  categories <- get_crf_change_categories()

  expect_type(categories, "character")
  expect_true("FIELD" %in% names(categories))
  expect_true("SECTION" %in% names(categories))
  expect_true("FORM" %in% names(categories))
  expect_true("VALIDATION" %in% names(categories))
})

# ============================================================================
# CRF DEFINITION TESTS
# ============================================================================

test_that("create_crf_definition creates CRF successfully", {
  setup_crfv_test_env()
  init_crf_version()

  crf_code <- paste0("DM_", format(Sys.time(), "%H%M%S"))

  result <- create_crf_definition(
    crf_code = crf_code,
    crf_name = "Demographics CRF",
    created_by = "developer",
    crf_description = "Demographics data collection",
    crf_category = "DEMOGRAPHICS"
  )

  expect_true(result$success)
  expect_true(!is.null(result$crf_id))
  expect_equal(result$crf_code, crf_code)
})

test_that("create_crf_definition validates required fields", {
  setup_crfv_test_env()

  result1 <- create_crf_definition(
    crf_code = "",
    crf_name = "Test CRF",
    created_by = "user"
  )
  expect_false(result1$success)
  expect_match(result1$error, "crf_code")

  result2 <- create_crf_definition(
    crf_code = "TEST",
    crf_name = "",
    created_by = "user"
  )
  expect_false(result2$success)
  expect_match(result2$error, "crf_name")
})

test_that("create_crf_definition rejects duplicate codes", {
  setup_crfv_test_env()

  code <- paste0("DUP_", format(Sys.time(), "%H%M%S"))

  result1 <- create_crf_definition(
    crf_code = code,
    crf_name = "First CRF",
    created_by = "user"
  )
  expect_true(result1$success)

  result2 <- create_crf_definition(
    crf_code = code,
    crf_name = "Duplicate CRF",
    created_by = "user"
  )
  expect_false(result2$success)
  expect_match(result2$error, "already exists")
})

test_that("get_crf_definitions retrieves CRFs", {
  setup_crfv_test_env()

  result <- get_crf_definitions()
  expect_true(result$success)
  expect_true("crfs" %in% names(result))
})

test_that("lock_crf_definition locks CRF", {
  setup_crfv_test_env()

  code <- paste0("LOCK_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Lock Test CRF",
    created_by = "user"
  )

  result <- lock_crf_definition(
    crf_id = crf$crf_id,
    locked_by = "admin",
    lock_reason = "Production deployment - no changes allowed"
  )

  expect_true(result$success)

  crfs <- get_crf_definitions()
  locked <- crfs$crfs[crfs$crfs$crf_id == crf$crf_id, ]
  expect_equal(locked$is_locked, 1)
})

test_that("lock_crf_definition validates lock_reason length", {
  setup_crfv_test_env()

  code <- paste0("LOCK2_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Lock Validation Test",
    created_by = "user"
  )

  result <- lock_crf_definition(
    crf_id = crf$crf_id,
    locked_by = "admin",
    lock_reason = "Short"
  )

  expect_false(result$success)
  expect_match(result$error, "at least 10 characters")
})

test_that("unlock_crf_definition unlocks CRF", {
  setup_crfv_test_env()

  code <- paste0("UNLOCK_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Unlock Test CRF",
    created_by = "user"
  )

  lock_crf_definition(
    crf_id = crf$crf_id,
    locked_by = "admin",
    lock_reason = "Temporary lock for testing"
  )

  result <- unlock_crf_definition(
    crf_id = crf$crf_id,
    unlocked_by = "admin",
    unlock_reason = "Testing complete, unlocking"
  )

  expect_true(result$success)

  crfs <- get_crf_definitions()
  unlocked <- crfs$crfs[crfs$crfs$crf_id == crf$crf_id, ]
  expect_equal(unlocked$is_locked, 0)
})

# ============================================================================
# VERSION MANAGEMENT TESTS
# ============================================================================

test_that("create_crf_version creates version successfully", {
  setup_crfv_test_env()
  init_crf_version()

  code <- paste0("VER_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Version Test CRF",
    created_by = "developer"
  )

  result <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Added new demographic fields for enhanced data collection",
    created_by = "developer"
  )

  expect_true(result$success)
  expect_true(!is.null(result$version_id))
  expect_equal(result$version_number, "1.1.0")
  expect_equal(result$version_type, "MINOR")
})

test_that("create_crf_version validates required fields", {
  setup_crfv_test_env()

  result <- create_crf_version(
    crf_id = NULL,
    version_number = "1.0.0",
    version_type = "MINOR",
    change_summary = "Test changes",
    created_by = "user"
  )
  expect_false(result$success)
  expect_match(result$error, "crf_id")
})

test_that("create_crf_version validates version_type", {
  setup_crfv_test_env()

  code <- paste0("VTYPE_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Version Type Test",
    created_by = "user"
  )

  result <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "INVALID",
    change_summary = "Test changes for validation",
    created_by = "user"
  )

  expect_false(result$success)
  expect_match(result$error, "Invalid version_type")
})

test_that("create_crf_version rejects locked CRF", {
  setup_crfv_test_env()

  code <- paste0("VLCK_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Locked Version Test",
    created_by = "user"
  )

  lock_crf_definition(
    crf_id = crf$crf_id,
    locked_by = "admin",
    lock_reason = "Locked for production"
  )

  result <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Attempt to version locked CRF",
    created_by = "developer"
  )

  expect_false(result$success)
  expect_match(result$error, "locked")
})

test_that("create_crf_version creates hash chain", {
  setup_crfv_test_env()

  code <- paste0("HASH_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Hash Chain Test",
    created_by = "user"
  )

  v1 <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "MAJOR",
    change_summary = "Initial version creation",
    created_by = "developer"
  )

  v2 <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Second version with changes",
    created_by = "developer"
  )

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  versions <- DBI::dbGetQuery(con, "
    SELECT version_hash, previous_hash FROM crf_versions
    WHERE crf_id = ? ORDER BY version_id
  ", params = list(crf$crf_id))

  expect_equal(nrow(versions), 2)
  expect_false(is.na(versions$version_hash[1]))
  expect_equal(versions$previous_hash[2], versions$version_hash[1])
})

test_that("get_crf_versions retrieves versions", {
  setup_crfv_test_env()

  code <- paste0("GVER_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Get Versions Test",
    created_by = "user"
  )

  create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "MAJOR",
    change_summary = "Initial release version",
    created_by = "developer"
  )

  create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Minor update version",
    created_by = "developer"
  )

  result <- get_crf_versions(crf$crf_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
  expect_equal(result$versions$version_number[1], "1.1.0")
})

test_that("update_crf_version_status updates status", {
  setup_crfv_test_env()

  code <- paste0("STAT_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Status Update Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "MAJOR",
    change_summary = "Initial version for status test",
    created_by = "developer"
  )

  result <- update_crf_version_status(
    version_id = version$version_id,
    status = "REVIEW",
    updated_by = "qa"
  )

  expect_true(result$success)

  versions <- get_crf_versions(crf$crf_id)
  expect_equal(versions$versions$version_status[1], "REVIEW")
})

test_that("update_crf_version_status validates status", {
  setup_crfv_test_env()

  result <- update_crf_version_status(
    version_id = 1,
    status = "INVALID_STATUS",
    updated_by = "user"
  )

  expect_false(result$success)
  expect_match(result$error, "Invalid status")
})

# ============================================================================
# CHANGE LOG TESTS
# ============================================================================

test_that("log_crf_change logs change successfully", {
  setup_crfv_test_env()
  init_crf_version()

  code <- paste0("CHG_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Change Log Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Version for change logging",
    created_by = "developer"
  )

  result <- log_crf_change(
    version_id = version$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added new field for date of birth",
    created_by = "developer",
    field_code = "DOB",
    field_name = "Date of Birth"
  )

  expect_true(result$success)
  expect_true(!is.null(result$change_id))
  expect_equal(result$change_type, "ADD")
})

test_that("log_crf_change validates change_type", {
  setup_crfv_test_env()

  result <- log_crf_change(
    version_id = 1,
    change_type = "INVALID",
    change_category = "FIELD",
    change_description = "Test change description",
    created_by = "user"
  )

  expect_false(result$success)
  expect_match(result$error, "Invalid change_type")
})

test_that("log_crf_change validates change_category", {
  setup_crfv_test_env()

  result <- log_crf_change(
    version_id = 1,
    change_type = "ADD",
    change_category = "INVALID",
    change_description = "Test change description",
    created_by = "user"
  )

  expect_false(result$success)
  expect_match(result$error, "Invalid change_category")
})

test_that("log_crf_change stores old and new values", {
  setup_crfv_test_env()

  code <- paste0("VAL_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Value Change Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Version for value change test",
    created_by = "developer"
  )

  log_crf_change(
    version_id = version$version_id,
    change_type = "MODIFY",
    change_category = "FIELD",
    change_description = "Changed field label for clarity",
    created_by = "developer",
    field_code = "NAME",
    attribute_changed = "label",
    old_value = "Name",
    new_value = "Full Legal Name"
  )

  changes <- get_crf_change_log(version$version_id)
  expect_true(changes$success)
  expect_equal(changes$changes$old_value[1], "Name")
  expect_equal(changes$changes$new_value[1], "Full Legal Name")
})

test_that("get_crf_change_log retrieves changes", {
  setup_crfv_test_env()

  code <- paste0("GCHG_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Get Changes Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Version for get changes test",
    created_by = "developer"
  )

  log_crf_change(
    version_id = version$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added field one for testing",
    created_by = "developer"
  )

  log_crf_change(
    version_id = version$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added field two for testing",
    created_by = "developer"
  )

  result <- get_crf_change_log(version$version_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("get_crf_change_log filters by type", {
  setup_crfv_test_env()

  code <- paste0("FCHG_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Filter Changes Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Version for filter test",
    created_by = "developer"
  )

  log_crf_change(
    version_id = version$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added new field for testing",
    created_by = "developer"
  )

  log_crf_change(
    version_id = version$version_id,
    change_type = "MODIFY",
    change_category = "FIELD",
    change_description = "Modified existing field",
    created_by = "developer"
  )

  result <- get_crf_change_log(version$version_id, change_type = "ADD")
  expect_true(result$success)
  expect_equal(result$count, 1)
  expect_equal(result$changes$change_type[1], "ADD")
})

test_that("get_crf_full_history retrieves complete history", {
  setup_crfv_test_env()

  code <- paste0("HIST_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Full History Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Version for history test",
    created_by = "developer"
  )

  log_crf_change(
    version_id = version$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added field for history",
    created_by = "developer",
    field_code = "HIST_FIELD"
  )

  result <- get_crf_full_history(crf$crf_id)
  expect_true(result$success)
  expect_true(result$count > 0)
  expect_true("version_number" %in% names(result$history))
  expect_true("change_type" %in% names(result$history))
})

# ============================================================================
# SNAPSHOT TESTS
# ============================================================================

test_that("create_version_snapshot creates snapshot", {
  setup_crfv_test_env()
  init_crf_version()

  code <- paste0("SNAP_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Snapshot Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "MAJOR",
    change_summary = "Version for snapshot test",
    created_by = "developer"
  )

  snapshot_data <- '{"fields": [{"code": "SUBJID", "type": "TEXT"}]}'

  result <- create_version_snapshot(
    version_id = version$version_id,
    snapshot_type = "FIELDS",
    snapshot_data = snapshot_data,
    created_by = "developer"
  )

  expect_true(result$success)
  expect_true(!is.null(result$snapshot_id))
  expect_equal(result$snapshot_type, "FIELDS")
})

test_that("create_version_snapshot validates snapshot_type", {
  setup_crfv_test_env()

  result <- create_version_snapshot(
    version_id = 1,
    snapshot_type = "INVALID",
    snapshot_data = "{}",
    created_by = "user"
  )

  expect_false(result$success)
  expect_match(result$error, "snapshot_type")
})

test_that("get_version_snapshots retrieves snapshots", {
  setup_crfv_test_env()

  code <- paste0("GSNP_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Get Snapshot Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "MAJOR",
    change_summary = "Version for get snapshot test",
    created_by = "developer"
  )

  create_version_snapshot(
    version_id = version$version_id,
    snapshot_type = "FULL",
    snapshot_data = '{"full": "data"}',
    created_by = "developer"
  )

  result <- get_version_snapshots(version$version_id)
  expect_true(result$success)
  expect_equal(result$count, 1)
})

# ============================================================================
# VERSION COMPARISON TESTS
# ============================================================================

test_that("compare_crf_versions compares versions", {
  setup_crfv_test_env()
  init_crf_version()

  code <- paste0("CMP_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Comparison Test",
    created_by = "user"
  )

  v1 <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "MAJOR",
    change_summary = "Initial version for comparison",
    created_by = "developer"
  )

  v2 <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Updated version for comparison",
    created_by = "developer"
  )

  log_crf_change(
    version_id = v2$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added new field in version 1.1.0",
    created_by = "developer"
  )

  log_crf_change(
    version_id = v2$version_id,
    change_type = "MODIFY",
    change_category = "FIELD",
    change_description = "Modified existing field in version 1.1.0",
    created_by = "developer"
  )

  result <- compare_crf_versions(
    version_id_old = v1$version_id,
    version_id_new = v2$version_id,
    compared_by = "qa"
  )

  expect_true(result$success)
  expect_true(!is.null(result$comparison_id))
  expect_equal(result$fields_added, 1)
  expect_equal(result$fields_modified, 1)
})

test_that("get_version_comparisons retrieves comparisons", {
  setup_crfv_test_env()

  result <- get_version_comparisons()
  expect_true(result$success)
  expect_true("comparisons" %in% names(result))
})

# ============================================================================
# STATISTICS TESTS
# ============================================================================

test_that("get_crf_version_statistics returns statistics", {
  setup_crfv_test_env()
  init_crf_version()

  code <- paste0("STAT_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Statistics Test",
    created_by = "user"
  )

  version <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "MAJOR",
    change_summary = "Version for statistics test",
    created_by = "developer"
  )

  log_crf_change(
    version_id = version$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added field for statistics",
    created_by = "developer"
  )

  result <- get_crf_version_statistics()

  expect_true(result$success)
  expect_true("crfs" %in% names(result))
  expect_true("versions" %in% names(result))
  expect_true("changes" %in% names(result))
  expect_true(result$crfs$total_crfs >= 1)
  expect_true(result$versions$total_versions >= 1)
  expect_true(result$changes$total_changes >= 1)
})

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

test_that("complete CRF version workflow works end-to-end", {
  setup_crfv_test_env()
  init_crf_version()

  code <- paste0("INT_", format(Sys.time(), "%H%M%S"))
  crf <- create_crf_definition(
    crf_code = code,
    crf_name = "Integration Test - Demographics CRF",
    created_by = "crf_developer",
    crf_description = "Comprehensive demographics form",
    crf_category = "DEMOGRAPHICS"
  )
  expect_true(crf$success)

  v1 <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.0.0",
    version_type = "MAJOR",
    change_summary = "Initial release of demographics CRF",
    created_by = "developer",
    change_rationale = "New study requirement",
    regulatory_impact = "None - new form",
    effective_date = format(Sys.Date(), "%Y-%m-%d")
  )
  expect_true(v1$success)

  log_crf_change(
    version_id = v1$version_id,
    change_type = "ADD",
    change_category = "FORM",
    change_description = "Created new demographics form with initial fields",
    created_by = "developer"
  )

  log_crf_change(
    version_id = v1$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added Subject ID field as primary identifier",
    created_by = "developer",
    field_code = "SUBJID",
    field_name = "Subject ID"
  )

  update_crf_version_status(
    version_id = v1$version_id,
    status = "APPROVED",
    updated_by = "qa_manager"
  )

  snapshot_data <- jsonlite::toJSON(list(
    fields = list(
      list(code = "SUBJID", type = "TEXT", required = TRUE)
    )
  ))

  create_version_snapshot(
    version_id = v1$version_id,
    snapshot_type = "FULL",
    snapshot_data = as.character(snapshot_data),
    created_by = "developer"
  )

  v2 <- create_crf_version(
    crf_id = crf$crf_id,
    version_number = "1.1.0",
    version_type = "MINOR",
    change_summary = "Added date of birth field per protocol amendment",
    created_by = "developer",
    change_rationale = "Protocol Amendment 2 requirement",
    regulatory_impact = "Requires IRB notification",
    backwards_compatible = TRUE,
    requires_retraining = FALSE
  )
  expect_true(v2$success)

  log_crf_change(
    version_id = v2$version_id,
    change_type = "ADD",
    change_category = "FIELD",
    change_description = "Added Date of Birth field per amendment",
    created_by = "developer",
    field_code = "DOB",
    field_name = "Date of Birth",
    change_justification = "Protocol Amendment 2",
    impact_assessment = "No impact on existing data"
  )

  comparison <- compare_crf_versions(
    version_id_old = v1$version_id,
    version_id_new = v2$version_id,
    compared_by = "qa"
  )
  expect_true(comparison$success)
  expect_equal(comparison$fields_added, 1)

  history <- get_crf_full_history(crf$crf_id)
  expect_true(history$success)
  expect_true(history$count > 0)

  stats <- get_crf_version_statistics()
  expect_true(stats$success)
  expect_true(stats$crfs$total_crfs >= 1)
  expect_true(stats$versions$total_versions >= 2)

  versions <- get_crf_versions(crf$crf_id)
  expect_true(versions$success)
  expect_equal(versions$count, 2)
  expect_equal(versions$versions$version_number[1], "1.1.0")
  expect_equal(versions$versions$version_number[2], "1.0.0")
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
