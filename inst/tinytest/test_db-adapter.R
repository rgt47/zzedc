library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Database Adapter Tests
# Tests for the database abstraction layer across all backends

# ============================================================================
# Core Adapter Functionality
# ============================================================================

with_test_backends("adapter connects and disconnects", function(ctx, conn, adapter) {
  # Connection was already established by with_test_backends

  expect_true(!is.null(conn))

  # Query should work
  result <- adapter$query(conn, "SELECT 1 as test_value")
  expect_equal(nrow(result), 1)
})

with_test_backends("adapter executes INSERT and SELECT", function(ctx, conn, adapter) {
  # Insert a new user
  adapter$execute(conn, "
    INSERT INTO edc_users (user_id, username, password_hash, full_name, role)
    VALUES (2, 'newuser', 'hash123', 'New User', 'User')
  ")

  # Verify insert
  result <- adapter$query(conn, "SELECT * FROM edc_users WHERE username = 'newuser'")
  expect_equal(nrow(result), 1)
  expect_equal(result$full_name[1], "New User")
})

with_test_backends("adapter executes parameterized queries", function(ctx, conn, adapter) {
  username <- "paramtest"
  full_name <- "Param Test User"
  dialect <- adapter$dialect()

  # Use dialect-aware placeholders
  p1 <- dialect$numbered_placeholder(1)
  p2 <- dialect$numbered_placeholder(2)

  insert_sql <- sprintf("
    INSERT INTO edc_users (user_id, username, password_hash, full_name, role)
    VALUES (3, %s, 'hash456', %s, 'User')
  ", p1, p2)

  adapter$execute(conn, insert_sql, params = list(username, full_name))

  select_sql <- sprintf("SELECT * FROM edc_users WHERE username = %s", p1)
  result <- adapter$query(conn, select_sql, params = list(username))
  expect_equal(nrow(result), 1)
  expect_equal(result$full_name[1], full_name)
})

with_test_backends("adapter provides dialect information", function(ctx, conn, adapter) {
  dialect <- adapter$dialect()

  expect_true(is.list(dialect))
  expect_true("auto_increment" %in% names(dialect))
  expect_true("timestamp_now" %in% names(dialect))
})

# ============================================================================
# Transaction Support
# ============================================================================

with_test_backends("adapter supports transactions - commit", function(ctx, conn, adapter) {
  # Skip for ClickHouse which has limited transaction support
  if (ctx$backend == "clickhouse") {
    skip("ClickHouse has limited transaction support")
  }

  initial_count <- adapter$query(conn, "SELECT COUNT(*) as n FROM subjects")$n

  adapter$begin(conn)
  adapter$execute(conn, "
    INSERT INTO subjects (subject_id, study_id, site_id, status)
    VALUES ('SUBJ-TX-001', 'TEST-001', '001', 'Enrolled')
  ")
  adapter$commit(conn)

  final_count <- adapter$query(conn, "SELECT COUNT(*) as n FROM subjects")$n
  expect_equal(final_count, initial_count + 1)
})

with_test_backends("adapter supports transactions - rollback", function(ctx, conn, adapter) {
  if (ctx$backend == "clickhouse") {
    skip("ClickHouse has limited transaction support")
  }

  initial_count <- adapter$query(conn, "SELECT COUNT(*) as n FROM subjects")$n

  adapter$begin(conn)
  adapter$execute(conn, "
    INSERT INTO subjects (subject_id, study_id, site_id, status)
    VALUES ('SUBJ-TX-002', 'TEST-001', '001', 'Enrolled')
  ")
  adapter$rollback(conn)

  final_count <- adapter$query(conn, "SELECT COUNT(*) as n FROM subjects")$n
  expect_equal(final_count, initial_count)
})

# ============================================================================
# Schema Operations
# ============================================================================

with_test_backends("test tables exist after setup", function(ctx, conn, adapter) {
  expect_true("edc_users" %in% DBI::dbListTables(conn))
  expect_true("subjects" %in% DBI::dbListTables(conn))
  expect_true("audit_trail" %in% DBI::dbListTables(conn))
  expect_true("validation_rules" %in% DBI::dbListTables(conn))
})

with_test_backends("test data was inserted", function(ctx, conn, adapter) {
  # Check that test data exists
  users <- adapter$query(conn, "SELECT * FROM edc_users WHERE username = 'testuser'")
  expect_equal(nrow(users), 1)

  subjects <- adapter$query(conn, "SELECT * FROM subjects WHERE subject_id = 'SUBJ-001'")
  expect_equal(nrow(subjects), 1)
})

# ============================================================================
# Backend-Specific Tests
# ============================================================================

with_backend("duckdb", "DuckDB exports to Parquet", function(ctx, conn, adapter) {
  # This tests DuckDB-specific functionality
  if (!inherits(adapter, "DuckDBAdapter")) {
    skip("Not a DuckDB adapter")
  }

  parquet_path <- tempfile(fileext = ".parquet")
  on.exit(unlink(parquet_path))

  adapter$export_parquet(conn, "subjects", parquet_path)
  expect_true(file.exists(parquet_path))
})

with_backend("postgresql", "PostgreSQL SERIAL generates IDs", function(ctx, conn, adapter) {
  # First delete the test data to reset SERIAL sequence issue
  adapter$execute(conn, "DELETE FROM edc_users WHERE user_id = 1")

  # Insert without specifying user_id - SERIAL should auto-generate
  adapter$execute(conn, "
    INSERT INTO edc_users (username, password_hash, full_name, role)
    VALUES ('autoid_user', 'hash789', 'Auto ID User', 'User')
  ")

  result <- adapter$query(conn, "
    SELECT user_id FROM edc_users WHERE username = 'autoid_user'
  ")
  expect_equal(nrow(result), 1)
  expect_true(is.numeric(result$user_id) || is.integer(result$user_id))
})

with_backend("clickhouse", "ClickHouse MergeTree engine works", function(ctx, conn, adapter) {
  # Test ClickHouse-specific columnar operations
  # Insert multiple rows for aggregation test
  adapter$execute(conn, "
    INSERT INTO subjects (subject_id, study_id, site_id, status)
    VALUES ('SUBJ-CH-001', 'TEST-001', '001', 'Enrolled')
  ")
  adapter$execute(conn, "
    INSERT INTO subjects (subject_id, study_id, site_id, status)
    VALUES ('SUBJ-CH-002', 'TEST-001', '001', 'Enrolled')
  ")
  adapter$execute(conn, "
    INSERT INTO subjects (subject_id, study_id, site_id, status)
    VALUES ('SUBJ-CH-003', 'TEST-001', '002', 'Withdrawn')
  ")

  # ClickHouse excels at aggregations
  result <- adapter$query(conn, "
    SELECT site_id, count(*) as subject_count
    FROM subjects
    GROUP BY site_id
    ORDER BY site_id
  ")

  expect_equal(nrow(result), 2)
  expect_true("subject_count" %in% names(result))
})

with_backend("clickhouse", "ClickHouse handles DateTime types", function(ctx, conn, adapter) {
  # ClickHouse has native DateTime support
  result <- adapter$query(conn, "SELECT now() as current_time")
  expect_equal(nrow(result), 1)
  expect_true("current_time" %in% names(result))
})

with_backend("clickhouse", "ClickHouse array functions work", function(ctx, conn, adapter) {
  # Test ClickHouse-specific array functionality
  result <- adapter$query(conn, "
    SELECT arrayJoin([1, 2, 3]) as val
  ")
  expect_equal(nrow(result), 3)
  expect_equal(result$val, c(1, 2, 3))
})

# ============================================================================
# Error Handling
# ============================================================================

with_test_backends("adapter handles invalid SQL gracefully", function(ctx, conn, adapter) {
  expect_error(
    adapter$query(conn, "SELECT * FROM nonexistent_table_xyz"),
    pattern = "."
  )
})

with_test_backends("adapter handles constraint violations", function(ctx, conn, adapter) {
  # Try to insert duplicate username (UNIQUE constraint)
  expect_error(
    adapter$execute(conn, "
      INSERT INTO edc_users (user_id, username, password_hash, full_name, role)
      VALUES (99, 'testuser', 'hash', 'Duplicate', 'User')
    ")
  )
})
