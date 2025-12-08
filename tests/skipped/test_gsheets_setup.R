# Test Google Sheets Integration Setup
# This script tests the Google Sheets integration functionality

# Load required libraries
library(RSQLite)

# Source the integration modules
source("gsheets_integration.R")
source("gsheets_auth_builder.R")
source("gsheets_dd_builder.R")
source("setup_from_gsheets.R")

# Test configuration
TEST_CONFIG <- list(
  test_db_path = "data/test_gsheets.db",
  test_forms_dir = "forms_test"
)

#' Test Google Sheets integration without actually connecting to Google Sheets
#' Uses mock data to test the database building functionality
test_gsheets_integration_offline <- function() {
  message("=== Testing Google Sheets Integration (Offline Mode) ===")

  # Create test data that mimics Google Sheets structure
  mock_auth_data <- create_mock_auth_data()
  mock_dd_data <- create_mock_dd_data()

  # Test authentication table building
  message("\n--- Testing Authentication System ---")
  auth_success <- test_auth_system(mock_auth_data)

  # Test data dictionary building
  message("\n--- Testing Data Dictionary System ---")
  dd_success <- test_dd_system(mock_dd_data)

  # Test form generation
  message("\n--- Testing Form Generation ---")
  forms_success <- test_form_generation(mock_dd_data)

  # Cleanup test files
  cleanup_test_files()

  # Summary
  overall_success <- auth_success && dd_success && forms_success

  message("\n=== Test Results ===")
  message(ifelse(auth_success, "✓", "✗"), " Authentication system: ", ifelse(auth_success, "PASS", "FAIL"))
  message(ifelse(dd_success, "✓", "✗"), " Data dictionary system: ", ifelse(dd_success, "PASS", "FAIL"))
  message(ifelse(forms_success, "✓", "✗"), " Form generation: ", ifelse(forms_success, "PASS", "FAIL"))
  message(ifelse(overall_success, "✓", "✗"), " Overall: ", ifelse(overall_success, "PASS", "FAIL"))

  return(overall_success)
}

#' Create mock authentication data
create_mock_auth_data <- function() {
  users <- data.frame(
    username = c("testuser1", "testuser2", "admin"),
    password = c("password123", "password456", "admin123"),
    full_name = c("Test User One", "Test User Two", "Admin User"),
    email = c("test1@example.com", "test2@example.com", "admin@example.com"),
    role = c("User", "Coordinator", "Admin"),
    site_id = c(1, 1, 1),
    active = c(1, 1, 1),
    stringsAsFactors = FALSE
  )

  roles <- data.frame(
    role = c("Admin", "Coordinator", "User"),
    description = c("Full access", "Research coordinator", "Standard user"),
    permissions = c("all", "read_write", "read_only"),
    stringsAsFactors = FALSE
  )

  sites <- data.frame(
    site_id = 1,
    site_name = "Test Site",
    site_code = "TS",
    active = 1,
    stringsAsFactors = FALSE
  )

  return(list(users = users, roles = roles, sites = sites))
}

#' Create mock data dictionary data
create_mock_dd_data <- function() {
  forms_overview <- data.frame(
    workingname = c("demographics", "vitals"),
    fullname = c("Demographics Form", "Vital Signs"),
    visits = c("baseline", "baseline,followup"),
    stringsAsFactors = FALSE
  )

  demographics_form <- data.frame(
    field = c("subject_id", "age", "gender", "dob"),
    prompt = c("Subject ID", "Age (years)", "Gender", "Date of Birth"),
    type = c("C", "N", "L", "D"),
    layout = c("text", "numeric", "radio", "date"),
    req = c(1, 1, 1, 0),
    values = c("", "", "male,female", ""),
    cond = c("", "", "", ""),
    valid = c("", "age >= 18", "", ""),
    validmsg = c("", "Age must be 18 or older", "", ""),
    stringsAsFactors = FALSE
  )

  vitals_form <- data.frame(
    field = c("height", "weight", "bp_systolic", "bp_diastolic"),
    prompt = c("Height (cm)", "Weight (kg)", "Systolic BP", "Diastolic BP"),
    type = c("N", "N", "N", "N"),
    layout = c("numeric", "numeric", "numeric", "numeric"),
    req = c(1, 1, 0, 0),
    values = c("", "", "", ""),
    cond = c("", "", "", ""),
    valid = c("height > 0", "weight > 0", "", ""),
    validmsg = c("Height must be positive", "Weight must be positive", "", ""),
    stringsAsFactors = FALSE
  )

  form_definitions <- list(
    demographics = demographics_form,
    vitals = vitals_form
  )

  visits <- data.frame(
    visit_code = c("baseline", "followup"),
    visit_name = c("Baseline Visit", "Follow-up Visit"),
    visit_order = c(1, 2),
    active = c(1, 1),
    stringsAsFactors = FALSE
  )

  field_types <- data.frame(
    type_code = c("C", "N", "D", "L"),
    type_name = c("Character", "Numeric", "Date", "Logical"),
    description = c("Text field", "Numeric field", "Date field", "Yes/No field"),
    stringsAsFactors = FALSE
  )

  validation_rules <- data.frame(
    field = c("age", "weight"),
    rule = c("age >= 18", "weight > 0"),
    message = c("Age must be 18 or older", "Weight must be positive"),
    stringsAsFactors = FALSE
  )

  return(list(
    forms_overview = forms_overview,
    form_definitions = form_definitions,
    visits = visits,
    field_types = field_types,
    validation_rules = validation_rules,
    form_errors = list()
  ))
}

#' Test authentication system building
test_auth_system <- function(mock_auth_data) {
  tryCatch({
    # Ensure test directory exists
    if (!dir.exists(dirname(TEST_CONFIG$test_db_path))) {
      dir.create(dirname(TEST_CONFIG$test_db_path), recursive = TRUE)
    }

    # Build authentication tables
    success <- build_comprehensive_auth_tables(mock_auth_data, TEST_CONFIG$test_db_path, "test_salt")

    if (!success) {
      message("✗ Failed to build authentication tables")
      return(FALSE)
    }

    # Verify tables were created
    con <- dbConnect(SQLite(), TEST_CONFIG$test_db_path)
    on.exit(dbDisconnect(con))

    tables <- dbListTables(con)
    expected_tables <- c("edc_users", "edc_roles", "edc_sites")
    missing_tables <- setdiff(expected_tables, tables)

    if (length(missing_tables) > 0) {
      message("✗ Missing authentication tables: ", paste(missing_tables, collapse = ", "))
      return(FALSE)
    }

    # Check user count
    user_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users")$count
    if (user_count != 3) {
      message("✗ Expected 3 users, found ", user_count)
      return(FALSE)
    }

    # Test password hashing
    users <- dbGetQuery(con, "SELECT username, password_hash FROM edc_users")
    if (any(nchar(users$password_hash) != 64)) {
      message("✗ Password hashes not properly generated")
      return(FALSE)
    }

    message("✓ Authentication system test passed")
    return(TRUE)

  }, error = function(e) {
    message("✗ Authentication system test failed: ", e$message)
    return(FALSE)
  })
}

#' Test data dictionary system building
test_dd_system <- function(mock_dd_data) {
  tryCatch({
    # Build data dictionary tables
    success <- build_comprehensive_dd_tables(mock_dd_data, TEST_CONFIG$test_db_path)

    if (!success) {
      message("✗ Failed to build data dictionary tables")
      return(FALSE)
    }

    # Verify tables were created
    con <- dbConnect(SQLite(), TEST_CONFIG$test_db_path)
    on.exit(dbDisconnect(con))

    tables <- dbListTables(con)
    expected_tables <- c("edc_forms", "edc_fields", "edc_visits", "edc_field_types")
    missing_tables <- setdiff(expected_tables, tables)

    if (length(missing_tables) > 0) {
      message("✗ Missing data dictionary tables: ", paste(missing_tables, collapse = ", "))
      return(FALSE)
    }

    # Check data tables were created
    data_tables <- tables[grepl("^data_", tables)]
    if (length(data_tables) != 2) {
      message("✗ Expected 2 data tables, found ", length(data_tables))
      return(FALSE)
    }

    # Check field count
    field_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_fields")$count
    if (field_count != 8) {  # 4 demographics + 4 vitals fields
      message("✗ Expected 8 fields, found ", field_count)
      return(FALSE)
    }

    message("✓ Data dictionary system test passed")
    return(TRUE)

  }, error = function(e) {
    message("✗ Data dictionary system test failed: ", e$message)
    return(FALSE)
  })
}

#' Test form generation
test_form_generation <- function(mock_dd_data) {
  tryCatch({
    # Ensure test directory exists
    if (!dir.exists(TEST_CONFIG$test_forms_dir)) {
      dir.create(TEST_CONFIG$test_forms_dir, recursive = TRUE)
    }

    # Generate form files
    generate_form_files(mock_dd_data, TEST_CONFIG$test_forms_dir)

    # Check if form files were created
    expected_files <- c("demographics_form.R", "vitals_form.R")
    for (file in expected_files) {
      file_path <- file.path(TEST_CONFIG$test_forms_dir, file)
      if (!file.exists(file_path)) {
        message("✗ Form file not created: ", file)
        return(FALSE)
      }
    }

    # Generate validation rules
    generate_validation_rules(mock_dd_data, TEST_CONFIG$test_forms_dir)

    validation_file <- file.path(TEST_CONFIG$test_forms_dir, "validation_rules.R")
    if (!file.exists(validation_file)) {
      message("✗ Validation rules file not created")
      return(FALSE)
    }

    message("✓ Form generation test passed")
    return(TRUE)

  }, error = function(e) {
    message("✗ Form generation test failed: ", e$message)
    return(FALSE)
  })
}

#' Clean up test files
cleanup_test_files <- function() {
  # Remove test database
  if (file.exists(TEST_CONFIG$test_db_path)) {
    unlink(TEST_CONFIG$test_db_path)
  }

  # Remove test forms directory
  if (dir.exists(TEST_CONFIG$test_forms_dir)) {
    unlink(TEST_CONFIG$test_forms_dir, recursive = TRUE)
  }

  message("✓ Test files cleaned up")
}

#' Run comprehensive tests
run_all_tests <- function() {
  message("Starting comprehensive Google Sheets integration tests...")

  # Run offline tests
  offline_success <- test_gsheets_integration_offline()

  # Test utility functions
  utility_success <- test_utility_functions()

  overall_success <- offline_success && utility_success

  message("\n=== Final Test Summary ===")
  message(ifelse(overall_success, "🎉", "❌"), " All tests: ", ifelse(overall_success, "PASSED", "FAILED"))

  return(overall_success)
}

#' Test utility functions
test_utility_functions <- function() {
  message("\n--- Testing Utility Functions ---")

  tryCatch({
    # Test password hashing
    hash1 <- hash_password("test123", "salt1")
    hash2 <- hash_password("test123", "salt2")
    hash3 <- hash_password("test456", "salt1")

    # Same password + salt should produce same hash
    if (hash_password("test123", "salt1") != hash1) {
      message("✗ Password hashing is not consistent")
      return(FALSE)
    }

    # Different salts should produce different hashes
    if (hash1 == hash2) {
      message("✗ Different salts producing same hash")
      return(FALSE)
    }

    # Different passwords should produce different hashes
    if (hash1 == hash3) {
      message("✗ Different passwords producing same hash")
      return(FALSE)
    }

    message("✓ Utility functions test passed")
    return(TRUE)

  }, error = function(e) {
    message("✗ Utility functions test failed: ", e$message)
    return(FALSE)
  })
}

# Auto-run tests if script is sourced interactively
if (interactive()) {
  cat("Google Sheets Integration Test Suite\n")
  cat("====================================\n\n")
  cat("Available test functions:\n")
  cat("- test_gsheets_integration_offline(): Test offline functionality\n")
  cat("- run_all_tests(): Run comprehensive test suite\n")
  cat("- cleanup_test_files(): Clean up test files\n\n")
  cat("Run run_all_tests() to start testing.\n")
}