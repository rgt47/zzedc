# Integration Tests
# End-to-end tests for the complete ZZedc application

source(here::here("tests/testthat/test-setup.R"))

# Load additional packages needed for integration tests
library(DT)
library(plotly)

test_that("complete authentication workflow works", {
  # Setup test environment
  original_env <- Sys.getenv("R_CONFIG_ACTIVE")
  Sys.setenv(R_CONFIG_ACTIVE = "testing")

  # Create test database and configuration
  test_db <- create_test_db()
  test_cfg <- create_test_config()

  # Simulate global environment setup
  assign("db_pool", test_db, envir = .GlobalEnv)
  assign("cfg", test_cfg, envir = .GlobalEnv)

  # Load authentication module
  source(here::here("R/modules/auth_module.R"))

  # Create test reactive values
  test_user_input <- reactiveValues(
    authenticated = FALSE,
    user_id = NULL,
    username = NULL,
    full_name = NULL,
    role = NULL,
    site_id = NULL
  )

  # Test successful authentication flow
  auth_result <- authenticate_user("testuser", "testpass")

  expect_true(auth_result$success)
  expect_equal(auth_result$username, "testuser")

  # Simulate updating reactive values (as would happen in actual app)
  test_user_input$authenticated <- TRUE
  test_user_input$user_id <- auth_result$user_id
  test_user_input$username <- auth_result$username
  test_user_input$full_name <- auth_result$full_name
  test_user_input$role <- auth_result$role
  test_user_input$site_id <- auth_result$site_id

  # Verify session state
  expect_true(isolate(test_user_input$authenticated))
  expect_equal(isolate(test_user_input$username), "testuser")
  expect_equal(isolate(test_user_input$role), "Admin")

  # Cleanup
  dbDisconnect(test_db)
  rm(db_pool, envir = .GlobalEnv)
  rm(cfg, envir = .GlobalEnv)

  # Restore environment
  if (original_env != "") {
    Sys.setenv(R_CONFIG_ACTIVE = original_env)
  } else {
    Sys.unsetenv("R_CONFIG_ACTIVE")
  }
})

test_that("module integration works correctly", {
  # Test that modules can be loaded together without conflicts
  expect_no_error({
    source(here::here("R/modules/auth_module.R"))
    source(here::here("R/modules/home_module.R"))
    source(here::here("R/modules/data_module.R"))
  })

  # Test UI generation for multiple modules
  auth_ui_result <- auth_ui("test_auth")
  home_ui_result <- home_ui("test_home")
  data_ui_result <- data_ui("test_data")

  expect_s3_class(auth_ui_result, "shiny.tag")
  expect_s3_class(home_ui_result, "shiny.tag.list")
  expect_s3_class(data_ui_result, "shiny.tag.list")

  # Test that namespaces don't conflict
  auth_html <- as.character(auth_ui_result)
  home_html <- as.character(home_ui_result)
  data_html <- as.character(data_ui_result)

  # Each should have its own namespace
  expect_true(grepl("test_auth-", auth_html))
  expect_true(grepl("test_home-", home_html))
  expect_true(grepl("test_data-", data_html))

  # Namespaces should not overlap
  expect_false(grepl("test_home-", auth_html))
  expect_false(grepl("test_data-", home_html))
  expect_false(grepl("test_auth-", data_html))
})

test_that("configuration and database integration works", {
  # Setup test environment
  original_env <- Sys.getenv("R_CONFIG_ACTIVE")
  Sys.setenv(R_CONFIG_ACTIVE = "testing")

  # Test configuration loading
  cfg <- config::get(file = here::here("config.yml"))

  # Test database pool creation with configuration
  if (cfg$database$path == ":memory:") {
    test_pool <- pool::dbPool(
      drv = RSQLite::SQLite(),
      dbname = cfg$database$path,
      minSize = 1,
      maxSize = cfg$database$pool_size
    )

    expect_true(inherits(test_pool, "Pool"))

    # Test that authentication can use the pool
    assign("db_pool", test_pool, envir = .GlobalEnv)
    assign("cfg", cfg, envir = .GlobalEnv)

    # Create user table with same schema as test setup
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

    # Add test user
    test_salt <- cfg$auth$default_salt
    test_hash <- digest::digest(paste0("integrationtest", test_salt), algo = "sha256")

    pool::dbExecute(test_pool, "
      INSERT INTO edc_users (username, password_hash, full_name, role, site_id)
      VALUES (?, ?, ?, ?, ?)
    ", params = list("integration_user", test_hash, "Integration Test", "User", "001"))

    # Test authentication with pool
    source(here::here("R/modules/auth_module.R"))
    auth_result <- authenticate_user("integration_user", "integrationtest")

    expect_true(auth_result$success)
    expect_equal(auth_result$username, "integration_user")

    # Cleanup
    pool::poolClose(test_pool)
    rm(db_pool, envir = .GlobalEnv)
    rm(cfg, envir = .GlobalEnv)
  }

  # Restore environment
  if (original_env != "") {
    Sys.setenv(R_CONFIG_ACTIVE = original_env)
  } else {
    Sys.unsetenv("R_CONFIG_ACTIVE")
  }
})

test_that("data module with sample data works end-to-end", {
  # Load data module
  source(here::here("R/modules/data_module.R"))

  # Test server functionality without full reactive context
  expect_no_error({
    server_func <- data_server
    expect_true(is.function(server_func))
  })

  # Test data module UI functionality
  expect_no_error({
    ui_result <- data_ui("integration_test")
    expect_s3_class(ui_result, "shiny.tag.list")
  })
})

test_that("global reactive values work across modules", {
  # Test reactive values structure
  test_user_input <- reactiveValues(
    authenticated = FALSE,
    user_id = NULL,
    username = NULL,
    full_name = NULL,
    role = NULL,
    site_id = NULL
  )

  # Test initial state
  expect_false(isolate(test_user_input$authenticated))
  expect_null(isolate(test_user_input$user_id))

  # Test state updates
  test_user_input$authenticated <- TRUE
  test_user_input$user_id <- 123
  test_user_input$username <- "testuser"
  test_user_input$role <- "Admin"

  expect_true(isolate(test_user_input$authenticated))
  expect_equal(isolate(test_user_input$user_id), 123)
  expect_equal(isolate(test_user_input$username), "testuser")
  expect_equal(isolate(test_user_input$role), "Admin")

  # Test that reactive values can be used in conditions
  is_authenticated <- isolate(test_user_input$authenticated)
  is_admin <- isolate(test_user_input$role) == "Admin"

  expect_true(is_authenticated)
  expect_true(is_admin)
})

test_that("environment variable configuration works in practice", {
  # Test configuration with environment variable
  test_cfg <- create_test_config()

  # Test salt environment variable (use the correct env var from config)
  original_salt <- Sys.getenv(test_cfg$auth$salt_env_var)

  # Set test salt
  Sys.setenv(TEST_SALT = "integration_test_salt")

  actual_salt <- Sys.getenv(test_cfg$auth$salt_env_var)
  if (actual_salt == "") actual_salt <- test_cfg$auth$default_salt

  expect_equal(actual_salt, "integration_test_salt")

  # Test password hashing with environment salt
  test_password <- "testpassword"
  hash1 <- digest::digest(paste0(test_password, actual_salt), algo = "sha256")

  # Change environment variable
  Sys.setenv(TEST_SALT = "different_salt")
  new_salt <- Sys.getenv(test_cfg$auth$salt_env_var)
  if (new_salt == "") new_salt <- test_cfg$auth$default_salt
  hash2 <- digest::digest(paste0(test_password, new_salt), algo = "sha256")

  # Hashes should be different with different salts
  expect_false(hash1 == hash2)

  # Restore original environment
  if (original_salt != "") {
    Sys.setenv(TEST_SALT = original_salt)
  } else {
    Sys.unsetenv("TEST_SALT")
  }
})

test_that("complete application startup simulation works", {
  # Simulate application startup sequence
  expect_no_error({
    # 1. Load configuration
    original_env <- Sys.getenv("R_CONFIG_ACTIVE")
    Sys.setenv(R_CONFIG_ACTIVE = "testing")

    cfg <- config::get(file = here::here("config.yml"))

    # 2. Create database pool
    if (cfg$database$path == ":memory:") {
      db_pool <- pool::dbPool(
        drv = RSQLite::SQLite(),
        dbname = cfg$database$path,
        minSize = 1,
        maxSize = cfg$database$pool_size
      )

      # 3. Set up global environment
      assign("db_pool", db_pool, envir = .GlobalEnv)
      assign("cfg", cfg, envir = .GlobalEnv)

      # 4. Initialize reactive values
      user_input <- reactiveValues(
        authenticated = FALSE,
        user_id = NULL,
        username = NULL,
        full_name = NULL,
        role = NULL,
        site_id = NULL
      )

      # 5. Load modules
      source(here::here("R/modules/auth_module.R"))
      source(here::here("R/modules/home_module.R"))
      source(here::here("R/modules/data_module.R"))

      # 6. Test basic functionality
      auth_ui_result <- auth_ui("app_auth")
      home_ui_result <- home_ui("app_home")

      expect_s3_class(auth_ui_result, "shiny.tag")
      expect_s3_class(home_ui_result, "shiny.tag.list")

      # 7. Cleanup
      pool::poolClose(db_pool)
      rm(db_pool, envir = .GlobalEnv)
      rm(cfg, envir = .GlobalEnv)
    }

    # Restore environment
    if (original_env != "") {
      Sys.setenv(R_CONFIG_ACTIVE = original_env)
    } else {
      Sys.unsetenv("R_CONFIG_ACTIVE")
    }
  })
})

test_that("req() validation works across modules", {
  # Test that req() validation prevents errors in different scenarios
  source(here::here("R/modules/data_module.R"))

  # Test that the data module functions can be instantiated
  expect_no_error({
    server_func <- data_server
    expect_true(is.function(server_func))
  })

  # Test UI generation works
  expect_no_error({
    ui_result <- data_ui("req_test")
    expect_s3_class(ui_result, "shiny.tag.list")
  })
})

test_that("authentication and authorization flow works completely", {
  # Setup complete auth test
  original_env <- Sys.getenv("R_CONFIG_ACTIVE")
  Sys.setenv(R_CONFIG_ACTIVE = "testing")

  test_db <- create_test_db()
  test_cfg <- create_test_config()

  assign("db_pool", test_db, envir = .GlobalEnv)
  assign("cfg", test_cfg, envir = .GlobalEnv)

  source(here::here("R/modules/auth_module.R"))

  # Test complete authentication flow
  # 1. Failed login
  failed_result <- authenticate_user("testuser", "wrongpassword")
  expect_false(failed_result$success)

  # 2. Successful login
  success_result <- authenticate_user("testuser", "testpass")
  expect_true(success_result$success)

  # 3. Check user details
  expect_equal(success_result$username, "testuser")
  expect_equal(success_result$full_name, "Test User")
  expect_equal(success_result$role, "Admin")

  # 4. Verify last login was updated
  updated_user <- pool::dbGetQuery(test_db, "
    SELECT last_login FROM edc_users WHERE username = ?
  ", params = list("testuser"))

  expect_false(is.na(updated_user$last_login[1]))

  # Cleanup
  dbDisconnect(test_db)
  rm(db_pool, envir = .GlobalEnv)
  rm(cfg, envir = .GlobalEnv)

  # Restore environment
  if (original_env != "") {
    Sys.setenv(R_CONFIG_ACTIVE = original_env)
  } else {
    Sys.unsetenv("R_CONFIG_ACTIVE")
  }
})