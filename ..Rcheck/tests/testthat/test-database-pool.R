# Database Connection Pool Tests
# Tests for database pooling functionality and configuration

source(here::here("tests/testthat/test-setup.R"))

test_that("database pool can be created and configured", {
  # Create a temporary database file for testing
  temp_db <- tempfile(fileext = ".db")

  # Create test configuration
  test_cfg <- list(
    database = list(
      path = temp_db,
      pool_size = 3
    )
  )

  # Test pool creation
  test_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = test_cfg$database$path,
    minSize = 1,
    maxSize = test_cfg$database$pool_size
  )

  expect_true(inherits(test_pool, "Pool"))

  # Test pool connection
  expect_no_error({
    pool::dbGetQuery(test_pool, "SELECT 1 as test")
  })

  # Test pool cleanup
  pool::poolClose(test_pool)

  # Cleanup temp file
  unlink(temp_db)
})

test_that("database pool handles basic operations", {
  # Create in-memory database for testing
  test_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = ":memory:",
    minSize = 1,
    maxSize = 2
  )

  # Test table creation
  expect_no_error({
    pool::dbExecute(test_pool, "
      CREATE TABLE test_table (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        value REAL
      )
    ")
  })

  # Test data insertion
  expect_no_error({
    pool::dbExecute(test_pool, "
      INSERT INTO test_table (name, value) VALUES (?, ?)
    ", params = list("test_name", 123.45))
  })

  # Test data retrieval
  result <- pool::dbGetQuery(test_pool, "SELECT * FROM test_table")

  expect_true(is.data.frame(result))
  expect_equal(nrow(result), 1)
  expect_equal(result$name[1], "test_name")
  expect_equal(result$value[1], 123.45)

  # Test data update
  expect_no_error({
    pool::dbExecute(test_pool, "
      UPDATE test_table SET value = ? WHERE name = ?
    ", params = list(678.90, "test_name"))
  })

  # Verify update
  updated_result <- pool::dbGetQuery(test_pool, "SELECT value FROM test_table WHERE name = ?",
                                    params = list("test_name"))
  expect_equal(updated_result$value[1], 678.90)

  # Cleanup
  pool::poolClose(test_pool)
})

test_that("database pool handles concurrent operations", {
  # Create test pool
  test_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = ":memory:",
    minSize = 1,
    maxSize = 3
  )

  # Create test table
  pool::dbExecute(test_pool, "
    CREATE TABLE concurrent_test (
      id INTEGER PRIMARY KEY,
      thread_id TEXT,
      timestamp REAL
    )
  ")

  # Test multiple concurrent operations (simulated)
  expect_no_error({
    for (i in 1:5) {
      pool::dbExecute(test_pool, "
        INSERT INTO concurrent_test (thread_id, timestamp) VALUES (?, ?)
      ", params = list(paste0("thread_", i), as.numeric(Sys.time())))
    }
  })

  # Verify all operations completed
  result <- pool::dbGetQuery(test_pool, "SELECT COUNT(*) as count FROM concurrent_test")
  expect_equal(result$count[1], 5)

  # Cleanup
  pool::poolClose(test_pool)
})

test_that("database pool handles connection errors gracefully", {
  # Test invalid database path
  expect_error({
    invalid_pool <- pool::dbPool(
      drv = RSQLite::SQLite(),
      dbname = "/invalid/path/database.db",
      minSize = 1,
      maxSize = 2
    )
  })
})

test_that("database pool configuration from config works", {
  # Test configuration loading
  test_cfg <- create_test_config()

  expect_true("database" %in% names(test_cfg))
  expect_true("path" %in% names(test_cfg$database))
  expect_true("pool_size" %in% names(test_cfg$database))

  # Test pool creation with config
  if (test_cfg$database$path == ":memory:") {
    test_pool <- pool::dbPool(
      drv = RSQLite::SQLite(),
      dbname = test_cfg$database$path,
      minSize = 1,
      maxSize = test_cfg$database$pool_size
    )

    expect_true(inherits(test_pool, "Pool"))

    # Test basic operation
    result <- pool::dbGetQuery(test_pool, "SELECT 1 as config_test")
    expect_equal(result$config_test[1], 1)

    pool::poolClose(test_pool)
  }
})

test_that("database pool supports authentication table operations", {
  # Create test pool with edc_users table
  test_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = ":memory:",
    minSize = 1,
    maxSize = 2
  )

  # Create edc_users table
  pool::dbExecute(test_pool, "
    CREATE TABLE edc_users (
      user_id INTEGER PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      full_name TEXT,
      role TEXT DEFAULT 'User',
      site_id TEXT DEFAULT '001',
      active INTEGER DEFAULT 1,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      last_login TIMESTAMP
    )
  ")

  # Test user insertion
  expect_no_error({
    pool::dbExecute(test_pool, "
      INSERT INTO edc_users (username, password_hash, full_name, role)
      VALUES (?, ?, ?, ?)
    ", params = list("pooltest", "hashedpassword", "Pool Test User", "Admin"))
  })

  # Test user retrieval
  user_result <- pool::dbGetQuery(test_pool, "
    SELECT * FROM edc_users WHERE username = ? AND active = 1
  ", params = list("pooltest"))

  expect_equal(nrow(user_result), 1)
  expect_equal(user_result$username[1], "pooltest")
  expect_equal(user_result$role[1], "Admin")

  # Test login update
  expect_no_error({
    pool::dbExecute(test_pool, "
      UPDATE edc_users SET last_login = ? WHERE user_id = ?
    ", params = list(Sys.time(), user_result$user_id[1]))
  })

  # Verify login update
  updated_user <- pool::dbGetQuery(test_pool, "
    SELECT last_login FROM edc_users WHERE user_id = ?
  ", params = list(user_result$user_id[1]))

  expect_false(is.na(updated_user$last_login[1]))

  # Cleanup
  pool::poolClose(test_pool)
})

test_that("database pool handles transaction-like operations", {
  test_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = ":memory:",
    minSize = 1,
    maxSize = 2
  )

  # Create test table
  pool::dbExecute(test_pool, "
    CREATE TABLE transaction_test (
      id INTEGER PRIMARY KEY,
      name TEXT,
      status TEXT DEFAULT 'pending'
    )
  ")

  # Test multiple related operations
  expect_no_error({
    # Insert initial record
    pool::dbExecute(test_pool, "
      INSERT INTO transaction_test (name) VALUES (?)
    ", params = list("test_record"))

    # Get the ID
    result <- pool::dbGetQuery(test_pool, "
      SELECT id FROM transaction_test WHERE name = ?
    ", params = list("test_record"))

    # Update the status
    pool::dbExecute(test_pool, "
      UPDATE transaction_test SET status = ? WHERE id = ?
    ", params = list("completed", result$id[1]))
  })

  # Verify final state
  final_result <- pool::dbGetQuery(test_pool, "
    SELECT * FROM transaction_test WHERE name = ?
  ", params = list("test_record"))

  expect_equal(final_result$status[1], "completed")

  # Cleanup
  pool::poolClose(test_pool)
})

test_that("database pool resource cleanup works", {
  # Test that pools can be properly closed
  test_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = ":memory:",
    minSize = 1,
    maxSize = 2
  )

  # Verify pool is active
  expect_true(inherits(test_pool, "Pool"))

  # Test operations work before closing
  result <- pool::dbGetQuery(test_pool, "SELECT 1 as test")
  expect_equal(result$test[1], 1)

  # Close the pool
  expect_no_error({
    pool::poolClose(test_pool)
  })

  # Verify operations fail after closing
  expect_error({
    pool::dbGetQuery(test_pool, "SELECT 1 as test")
  })
})

test_that("database pool handles environment variable configuration", {
  # Test with environment variable for database path
  original_path <- Sys.getenv("ZZEDC_DB_PATH")

  # Set test environment variable
  Sys.setenv(ZZEDC_DB_PATH = ":memory:")

  # Test configuration reading
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path == "") db_path <- "data/default.db"
  expect_equal(db_path, ":memory:")

  # Test pool creation with environment variable
  test_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = db_path,
    minSize = 1,
    maxSize = 2
  )

  expect_true(inherits(test_pool, "Pool"))

  # Cleanup
  pool::poolClose(test_pool)

  # Restore original environment
  if (original_path != "") {
    Sys.setenv(ZZEDC_DB_PATH = original_path)
  } else {
    Sys.unsetenv("ZZEDC_DB_PATH")
  }
})