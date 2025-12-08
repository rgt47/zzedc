# Authentication Module Tests
# Tests for the auth_module.R functionality

# Load required modules and setup
source(here::here("R/modules/auth_module.R"))
source(here::here("tests/testthat/test-setup.R"))

test_that("authenticate_user function works correctly", {
  # Setup test database and config
  test_con <- create_test_db()
  assign("db_pool", test_con, envir = .GlobalEnv)
  assign("cfg", create_test_config(), envir = .GlobalEnv)

  # Test successful authentication
  result <- authenticate_user("testuser", "testpass")

  expect_true(result$success)
  expect_equal(result$username, "testuser")
  expect_equal(result$full_name, "Test User")
  expect_equal(result$role, "Admin")
  expect_equal(result$site_id, "001")

  # Test failed authentication - wrong password
  result_fail <- authenticate_user("testuser", "wrongpassword")

  expect_false(result_fail$success)
  expect_match(result_fail$message, "Invalid password")

  # Test failed authentication - nonexistent user
  result_nouser <- authenticate_user("nonexistent", "password")

  expect_false(result_nouser$success)
  expect_match(result_nouser$message, "Invalid username")

  # Cleanup
  dbDisconnect(test_con)
  rm(db_pool, envir = .GlobalEnv)
  rm(cfg, envir = .GlobalEnv)
})

test_that("authenticate_user handles database errors gracefully", {
  # Test without database pool
  if (exists("db_pool", envir = .GlobalEnv)) {
    rm(db_pool, envir = .GlobalEnv)
  }

  result <- authenticate_user("testuser", "testpass")

  expect_false(result$success)
  expect_match(result$message, "Database pool not initialized")
})

test_that("auth_ui function generates correct UI", {
  ui_output <- auth_ui("test")

  expect_s3_class(ui_output, "shiny.tag")
  expect_equal(ui_output$name, "div")
  expect_equal(ui_output$attribs$id, "test-auth_container")
})

test_that("password hashing works consistently", {
  # Setup
  assign("cfg", create_test_config(), envir = .GlobalEnv)

  password <- "testpassword"
  salt <- cfg$auth$default_salt

  # Test hash consistency
  hash1 <- digest(paste0(password, salt), algo = "sha256")
  hash2 <- digest(paste0(password, salt), algo = "sha256")

  expect_equal(hash1, hash2)
  expect_type(hash1, "character")
  expect_true(nchar(hash1) == 64)  # SHA256 produces 64-character hex string

  # Test different passwords produce different hashes
  hash_different <- digest(paste0("different_password", salt), algo = "sha256")
  expect_false(hash1 == hash_different)

  # Cleanup
  rm(cfg, envir = .GlobalEnv)
})

test_that("authentication module integrates with reactive values", {
  # Setup test environment
  test_con <- create_test_db()
  assign("db_pool", test_con, envir = .GlobalEnv)
  assign("cfg", create_test_config(), envir = .GlobalEnv)

  # Create test reactive values
  test_user_input <- reactiveValues(
    authenticated = FALSE,
    user_id = NULL,
    username = NULL,
    full_name = NULL,
    role = NULL,
    site_id = NULL
  )

  # Test authentication success updates reactive values
  auth_result <- authenticate_user("testuser", "testpass")

  if (auth_result$success) {
    test_user_input$authenticated <- TRUE
    test_user_input$user_id <- auth_result$user_id
    test_user_input$username <- auth_result$username
    test_user_input$full_name <- auth_result$full_name
    test_user_input$role <- auth_result$role
    test_user_input$site_id <- auth_result$site_id
  }

  # Access reactive values in isolated context
  expect_true(isolate(test_user_input$authenticated))
  expect_equal(isolate(test_user_input$username), "testuser")
  expect_equal(isolate(test_user_input$full_name), "Test User")
  expect_equal(isolate(test_user_input$role), "Admin")

  # Cleanup
  dbDisconnect(test_con)
  rm(db_pool, envir = .GlobalEnv)
  rm(cfg, envir = .GlobalEnv)
})

test_that("authentication handles edge cases", {
  # Setup
  test_con <- create_test_db()
  assign("db_pool", test_con, envir = .GlobalEnv)
  assign("cfg", create_test_config(), envir = .GlobalEnv)

  # Test empty username/password
  result_empty_user <- authenticate_user("", "password")
  expect_false(result_empty_user$success)

  result_empty_pass <- authenticate_user("testuser", "")
  expect_false(result_empty_pass$success)

  # Test NULL inputs (should be handled gracefully)
  result_null <- tryCatch({
    authenticate_user(NULL, NULL)
  }, error = function(e) {
    list(success = FALSE, message = "Input validation error")
  })
  expect_false(result_null$success)

  # Test very long inputs
  long_username <- paste(rep("a", 1000), collapse = "")
  long_password <- paste(rep("b", 1000), collapse = "")

  result_long <- authenticate_user(long_username, long_password)
  expect_false(result_long$success)

  # Cleanup
  dbDisconnect(test_con)
  rm(db_pool, envir = .GlobalEnv)
  rm(cfg, envir = .GlobalEnv)
})

test_that("authentication respects user active status", {
  # Setup
  test_con <- create_test_db()
  assign("db_pool", test_con, envir = .GlobalEnv)
  assign("cfg", create_test_config(), envir = .GlobalEnv)

  # Add inactive user
  test_salt <- cfg$auth$default_salt
  inactive_hash <- digest(paste0("inactivepass", test_salt), algo = "sha256")

  dbExecute(test_con, "
    INSERT INTO edc_users (username, password_hash, full_name, role, active)
    VALUES (?, ?, ?, ?, ?)
  ", params = list("inactive_user", inactive_hash, "Inactive User", "User", 0))

  # Test authentication fails for inactive user
  result <- authenticate_user("inactive_user", "inactivepass")

  expect_false(result$success)
  expect_match(result$message, "Invalid username or account inactive")

  # Cleanup
  dbDisconnect(test_con)
  rm(db_pool, envir = .GlobalEnv)
  rm(cfg, envir = .GlobalEnv)
})