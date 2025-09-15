# Test Setup and Configuration
# Shared setup for all tests

library(testthat)
library(shiny)
library(bslib)
library(RSQLite)
library(pool)
library(config)
library(digest)

#' Create a test database in memory
#'
#' @return Database connection
create_test_db <- function() {
  con <- dbConnect(RSQLite::SQLite(), ":memory:")

  # Create edc_users table for authentication tests
  dbExecute(con, "
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

  # Insert test user
  test_salt <- "test_salt_123"
  test_password_hash <- digest(paste0("testpass", test_salt), algo = "sha256")

  dbExecute(con, "
    INSERT INTO edc_users (username, password_hash, full_name, role, site_id)
    VALUES (?, ?, ?, ?, ?)
  ", params = list("testuser", test_password_hash, "Test User", "Admin", "001"))

  con
}

#' Create test configuration
#'
#' @return Configuration list
create_test_config <- function() {
  list(
    database = list(
      path = ":memory:",
      pool_size = 2
    ),
    auth = list(
      salt_env_var = "TEST_SALT",
      default_salt = "test_salt_123",
      max_failed_attempts = 3,
      session_timeout_minutes = 30
    ),
    app = list(
      name = "ZZedc Test",
      version = "1.0.0-test",
      debug = TRUE
    )
  )
}

#' Create test database pool
#'
#' @return Pool connection
create_test_pool <- function() {
  test_db <- create_test_db()

  # For testing, we'll use a simple connection rather than pool
  # since :memory: databases don't work well with pool
  test_db
}

#' Setup test environment variables
setup_test_env <- function() {
  Sys.setenv(TEST_SALT = "test_salt_123")
  Sys.setenv(R_CONFIG_ACTIVE = "testing")
}

#' Cleanup test environment
cleanup_test_env <- function() {
  Sys.unsetenv("TEST_SALT")
  Sys.unsetenv("R_CONFIG_ACTIVE")
}

# Set up test environment by default
setup_test_env()