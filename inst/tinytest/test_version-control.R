library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Feature #4: Enhanced Version Control System - Test Suite
#
# Tests for record versioning functionality including:
# - Version creation
# - Version retrieval
# - Version comparison
# - Version restoration
# - Integrity verification
# - Record locking

# Skip all tests if version control functions are not available
if (!(exists("init_version_control"))) exit_file("Version control functions not available")

setup_test_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") {
    Sys.setenv("ZZEDC_OLD_KEY" = old_key)
  }

  test_db <- tempfile(fileext = ".db")
  init_result <- initialize_encrypted_database(db_path = test_db,
                                                overwrite = TRUE)
  if (!init_result$success) {
    stop("Failed to initialize database")
  }
  Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
  audit_result <- init_audit_logging(db_path = test_db)
  version_result <- init_version_control(db_path = test_db)
  test_db
}

cleanup_test_db <- function(test_db) {
  if (file.exists(test_db)) {
    unlink(test_db)
  }
  old_key <- Sys.getenv("ZZEDC_OLD_KEY")
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    Sys.unsetenv("ZZEDC_OLD_KEY")
  }
}

# =============================================================================
# Test Section 1: Initialization
# =============================================================================

# Test: init_version_control creates required tables
local({
    test_db <- setup_test_db()

    conn <- connect_encrypted_db(db_path = test_db)

    tables <- DBI::dbListTables(conn)
    expect_true("record_versions" %in% tables)
    expect_true("version_metadata" %in% tables)
    expect_true("version_locks" %in% tables)

    DBI::dbDisconnect(conn)
    cleanup_test_db(test_db)

})
# =============================================================================
# Test Section 2: Version Creation
# =============================================================================

# Test: create_record_version creates first version
local({
    test_db <- setup_test_db()

    result <- create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 45),
      change_type = "CREATE",
      change_reason = "Initial enrollment",
      changed_by = "coordinator",
      db_path = test_db
    )

    expect_true(result$success)
    expect_equal(result$version_number, 1)
    expect_true(nchar(result$version_hash) > 0)

    cleanup_test_db(test_db)

})
# Test: create_record_version increments version number
local({
    test_db <- setup_test_db()

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 45),
      change_type = "CREATE",
      changed_by = "coordinator",
      db_path = test_db
    )

    result <- create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 46),
      change_type = "UPDATE",
      change_reason = "Age correction",
      changed_by = "data_manager",
      field_changes = list(
        age = list(old_value = "45", new_value = "46")
      ),
      db_path = test_db
    )

    expect_true(result$success)
    expect_equal(result$version_number, 2)

    cleanup_test_db(test_db)

})
# Test: create_record_version validates change_type
local({
    test_db <- setup_test_db()

    expect_error(
      create_record_version(
        table_name = "subjects",
        record_id = "S001",
        data = list(name = "Test"),
        change_type = "INVALID",
        changed_by = "user",
        db_path = test_db
      ),
      "change_type must be one of"
    )

    cleanup_test_db(test_db)

})
# =============================================================================
# Test Section 3: Version Retrieval
# =============================================================================

# Test: get_version_history returns all versions
local({
    test_db <- setup_test_db()

    for (i in 1:3) {
      create_record_version(
        table_name = "subjects",
        record_id = "S001",
        data = list(name = "John Doe", visits = i),
        change_type = ifelse(i == 1, "CREATE", "UPDATE"),
        changed_by = "user",
        db_path = test_db
      )
    }

    history <- get_version_history(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )

    expect_equal(nrow(history), 3)
    expect_equal(history$version_number, c(3, 2, 1))

    cleanup_test_db(test_db)

})
# Test: get_record_version retrieves specific version
local({
    test_db <- setup_test_db()

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 45),
      change_type = "CREATE",
      changed_by = "user",
      db_path = test_db
    )

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 46),
      change_type = "UPDATE",
      changed_by = "user",
      db_path = test_db
    )

    version1 <- get_record_version(
      table_name = "subjects",
      record_id = "S001",
      version_number = 1,
      db_path = test_db
    )

    expect_true(version1$found)
    expect_equal(version1$version_number, 1)
    expect_equal(version1$data$age, 45)

    cleanup_test_db(test_db)

})
# Test: get_current_version returns latest version
local({
    test_db <- setup_test_db()

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", status = "enrolled"),
      change_type = "CREATE",
      changed_by = "user",
      db_path = test_db
    )

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", status = "completed"),
      change_type = "UPDATE",
      changed_by = "user",
      db_path = test_db
    )

    current <- get_current_version(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )

    expect_true(current$found)
    expect_equal(current$version_number, 2)
    expect_equal(current$data$status, "completed")

    cleanup_test_db(test_db)

})
# =============================================================================
# Test Section 4: Version Comparison
# =============================================================================

# Test: compare_versions identifies differences
local({
    test_db <- setup_test_db()

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 45, status = "enrolled"),
      change_type = "CREATE",
      changed_by = "user",
      db_path = test_db
    )

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 46, status = "active"),
      change_type = "UPDATE",
      changed_by = "user",
      db_path = test_db
    )

    comparison <- compare_versions(
      table_name = "subjects",
      record_id = "S001",
      version_a = 1,
      version_b = 2,
      db_path = test_db
    )

    expect_true(comparison$success)
    expect_false(comparison$identical)
    expect_equal(comparison$fields_changed, 2)
    expect_true("age" %in% names(comparison$differences))
    expect_true("status" %in% names(comparison$differences))

    cleanup_test_db(test_db)

})
# Test: compare_versions returns identical for same data
local({
    test_db <- setup_test_db()

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 45),
      change_type = "CREATE",
      changed_by = "user",
      db_path = test_db
    )

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 45),
      change_type = "UPDATE",
      changed_by = "user",
      db_path = test_db
    )

    comparison <- compare_versions(
      table_name = "subjects",
      record_id = "S001",
      version_a = 1,
      version_b = 2,
      db_path = test_db
    )

    expect_true(comparison$success)
    expect_true(comparison$identical)
    expect_equal(comparison$fields_changed, 0)

    cleanup_test_db(test_db)

})
# Test: get_version_diff_summary returns readable output
local({
    test_db <- setup_test_db()

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 45),
      change_type = "CREATE",
      changed_by = "user",
      db_path = test_db
    )

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 46),
      change_type = "UPDATE",
      changed_by = "user",
      db_path = test_db
    )

    summary <- get_version_diff_summary(
      table_name = "subjects",
      record_id = "S001",
      version_a = 1,
      version_b = 2,
      db_path = test_db
    )

    expect_equal(typeof(summary), "character")
    expect_true(any(grepl("age", summary)))

    cleanup_test_db(test_db)

})
# =============================================================================
# Test Section 5: Version Restoration
# =============================================================================

# Test: restore_record_version creates new version from old
local({
    test_db <- setup_test_db()

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 45),
      change_type = "CREATE",
      changed_by = "user",
      db_path = test_db
    )

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(name = "John Doe", age = 99),
      change_type = "UPDATE",
      changed_by = "user",
      db_path = test_db
    )

    result <- restore_record_version(
      table_name = "subjects",
      record_id = "S001",
      version_number = 1,
      restore_reason = "Incorrect age entry",
      restored_by = "admin",
      db_path = test_db
    )

    expect_true(result$success)
    expect_equal(result$version_number, 3)
    expect_equal(result$restored_from_version, 1)

    current <- get_current_version(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )

    expect_equal(current$data$age, 45)

    cleanup_test_db(test_db)

})
# =============================================================================
# Test Section 6: Integrity Verification
# =============================================================================

# Test: verify_version_integrity validates hash chain
local({
    test_db <- setup_test_db()

    for (i in 1:5) {
      create_record_version(
        table_name = "subjects",
        record_id = "S001",
        data = list(name = "John Doe", visits = i),
        change_type = ifelse(i == 1, "CREATE", "UPDATE"),
        changed_by = "user",
        db_path = test_db
      )
    }

    result <- verify_version_integrity(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )

    expect_true(result$valid)
    expect_equal(result$versions_checked, 5)
    expect_equal(result$errors_found, 0)

    cleanup_test_db(test_db)

})
# =============================================================================
# Test Section 7: Record Locking
# =============================================================================

# Test: lock_record acquires lock
local({
    test_db <- setup_test_db()

    result <- lock_record(
      table_name = "subjects",
      record_id = "S001",
      locked_by = "user1",
      lock_reason = "Editing",
      db_path = test_db
    )

    expect_true(result$success)
    expect_equal(result$action, "ACQUIRED")

    cleanup_test_db(test_db)

})
# Test: lock_record prevents second lock
local({
    test_db <- setup_test_db()

    lock_record(
      table_name = "subjects",
      record_id = "S001",
      locked_by = "user1",
      db_path = test_db
    )

    result <- lock_record(
      table_name = "subjects",
      record_id = "S001",
      locked_by = "user2",
      db_path = test_db
    )

    expect_false(result$success)
    expect_equal(result$locked_by, "user1")

    cleanup_test_db(test_db)

})
# Test: lock_record extends for same user
local({
    test_db <- setup_test_db()

    lock_record(
      table_name = "subjects",
      record_id = "S001",
      locked_by = "user1",
      db_path = test_db
    )

    result <- lock_record(
      table_name = "subjects",
      record_id = "S001",
      locked_by = "user1",
      db_path = test_db
    )

    expect_true(result$success)
    expect_equal(result$action, "EXTENDED")

    cleanup_test_db(test_db)

})
# Test: unlock_record releases lock
local({
    test_db <- setup_test_db()

    lock_record(
      table_name = "subjects",
      record_id = "S001",
      locked_by = "user1",
      db_path = test_db
    )

    result <- unlock_record(
      table_name = "subjects",
      record_id = "S001",
      unlocked_by = "user1",
      db_path = test_db
    )

    expect_true(result$success)

    status <- check_record_lock(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )

    expect_false(status$locked)

    cleanup_test_db(test_db)

})
# Test: check_record_lock returns correct status
local({
    test_db <- setup_test_db()

    status1 <- check_record_lock(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )

    expect_false(status1$locked)

    lock_record(
      table_name = "subjects",
      record_id = "S001",
      locked_by = "user1",
      lock_reason = "Testing",
      db_path = test_db
    )

    status2 <- check_record_lock(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )

    expect_true(status2$locked)
    expect_equal(status2$locked_by, "user1")
    expect_equal(status2$lock_reason, "Testing")

    cleanup_test_db(test_db)

})
# =============================================================================
# Test Section 8: Statistics
# =============================================================================

# Test: get_version_statistics returns correct counts
local({
    test_db <- setup_test_db()

    for (i in 1:3) {
      create_record_version(
        table_name = "subjects",
        record_id = "S001",
        data = list(name = "John", v = i),
        change_type = ifelse(i == 1, "CREATE", "UPDATE"),
        changed_by = "user",
        db_path = test_db
      )
    }

    stats <- get_version_statistics(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )

    expect_equal(stats$statistics$total_versions, 3)
    expect_true(!is.null(stats$by_change_type))

    cleanup_test_db(test_db)

})
# =============================================================================
# Test Section 9: Integration Tests
# =============================================================================

# Test: complete version workflow functions correctly
local({
    test_db <- setup_test_db()

    lock_result <- lock_record(
      table_name = "subjects",
      record_id = "S001",
      locked_by = "coordinator",
      db_path = test_db
    )
    expect_true(lock_result$success)

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(subject_id = "S001", name = "Jane Smith", age = 35,
                  status = "screening"),
      change_type = "CREATE",
      change_reason = "New enrollment",
      changed_by = "coordinator",
      db_path = test_db
    )

    create_record_version(
      table_name = "subjects",
      record_id = "S001",
      data = list(subject_id = "S001", name = "Jane Smith", age = 35,
                  status = "enrolled"),
      change_type = "UPDATE",
      change_reason = "Passed screening",
      changed_by = "coordinator",
      field_changes = list(
        status = list(old_value = "screening", new_value = "enrolled")
      ),
      db_path = test_db
    )

    unlock_record(
      table_name = "subjects",
      record_id = "S001",
      unlocked_by = "coordinator",
      db_path = test_db
    )

    history <- get_version_history(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )
    expect_equal(nrow(history), 2)

    current <- get_current_version(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )
    expect_equal(current$data$status, "enrolled")

    integrity <- verify_version_integrity(
      table_name = "subjects",
      record_id = "S001",
      db_path = test_db
    )
    expect_true(integrity$valid)

    cleanup_test_db(test_db)

})