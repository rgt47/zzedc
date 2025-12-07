# ZZedc Setup from Google Sheets
# Main orchestration script to build complete EDC system from Google Sheets configuration

# Load all required modules
source("gsheets_integration.R")
source("gsheets_auth_builder.R")
source("gsheets_dd_builder.R")

#' Complete ZZedc setup from Google Sheets configuration
#' This is the main function that orchestrates the entire process
#' @param auth_sheet_name Name of Google Sheet containing authentication data
#' @param dd_sheet_name Name of Google Sheet containing data dictionary
#' @param project_name Name of the EDC project (used for database naming)
#' @param db_path Path to SQLite database file (optional)
#' @param salt Salt for password hashing
#' @param token_file Path to Google Sheets authentication token
#' @param forms_dir Directory for generated form files
#' @param backup_existing Whether to backup existing database
setup_zzedc_from_gsheets_complete <- function(
  auth_sheet_name = "zzedc_auth",
  dd_sheet_name = "zzedc_data_dictionary",
  project_name = "zzedc_project",
  db_path = NULL,
  salt = "zzedc_default_salt",
  token_file = "googlesheets_token.rds",
  forms_dir = "forms_generated",
  backup_existing = TRUE
) {

  # Set default database path if not provided
  if (is.null(db_path)) {
    db_path <- file.path("data", paste0(project_name, "_gsheets.db"))
  }

  message("=====================================")
  message("ZZedc Setup from Google Sheets")
  message("=====================================")
  message("Project: ", project_name)
  message("Authentication sheet: ", auth_sheet_name)
  message("Data dictionary sheet: ", dd_sheet_name)
  message("Database: ", db_path)
  message("Forms directory: ", forms_dir)
  message("=====================================")

  # Create directories
  ensure_directories(db_path, forms_dir)

  # Backup existing database if it exists
  if (backup_existing && file.exists(db_path)) {
    backup_database(db_path)
  }

  # Step 1: Setup Google Sheets authentication
  message("\n=== Step 1: Google Sheets Authentication ===")
  tryCatch({
    setup_google_auth(token_file)
    message("✓ Google Sheets authentication successful")
  }, error = function(e) {
    stop("✗ Google Sheets authentication failed: ", e$message)
  })

  # Step 2: Validate Google Sheets access
  message("\n=== Step 2: Validating Google Sheets Access ===")
  sheets_valid <- validate_sheets_access(auth_sheet_name, dd_sheet_name)
  if (!sheets_valid) {
    stop("✗ Cannot access required Google Sheets")
  }

  # Step 3: Build authentication system
  message("\n=== Step 3: Building Authentication System ===")
  auth_success <- tryCatch({
    build_advanced_auth_system(auth_sheet_name, db_path, salt, validate_roles = TRUE)
    verify_auth_system(db_path, salt)
  }, error = function(e) {
    message("✗ Authentication system build failed: ", e$message)
    FALSE
  })

  if (!auth_success) {
    stop("Authentication system setup failed")
  }

  # Step 4: Build data dictionary system
  message("\n=== Step 4: Building Data Dictionary System ===")
  dd_success <- tryCatch({
    build_advanced_dd_system(dd_sheet_name, db_path, forms_dir)
    verify_dd_system(db_path)
  }, error = function(e) {
    message("✗ Data dictionary system build failed: ", e$message)
    FALSE
  })

  if (!dd_success) {
    stop("Data dictionary system setup failed")
  }

  # Step 5: Generate configuration files for ZZedc
  message("\n=== Step 5: Generating Configuration Files ===")
  config_success <- generate_zzedc_config(project_name, db_path, forms_dir)

  # Step 6: Create launch scripts
  message("\n=== Step 6: Creating Launch Scripts ===")
  scripts_success <- create_launch_scripts(project_name, db_path)

  # Step 7: Final validation
  message("\n=== Step 7: Final System Validation ===")
  final_validation <- perform_final_validation(db_path)

  # Summary
  message("\n=====================================")
  message("ZZedc Setup Summary")
  message("=====================================")
  message("✓ Google Sheets authentication: SUCCESS")
  message(ifelse(auth_success, "✓", "✗"), " Authentication system: ", ifelse(auth_success, "SUCCESS", "FAILED"))
  message(ifelse(dd_success, "✓", "✗"), " Data dictionary system: ", ifelse(dd_success, "SUCCESS", "FAILED"))
  message(ifelse(config_success, "✓", "✗"), " Configuration files: ", ifelse(config_success, "SUCCESS", "FAILED"))
  message(ifelse(scripts_success, "✓", "✗"), " Launch scripts: ", ifelse(scripts_success, "SUCCESS", "FAILED"))
  message(ifelse(final_validation, "✓", "✗"), " Final validation: ", ifelse(final_validation, "SUCCESS", "FAILED"))

  overall_success <- auth_success && dd_success && config_success && scripts_success && final_validation

  if (overall_success) {
    message("\n🎉 ZZedc setup completed successfully!")
    message("Database: ", db_path)
    message("Forms: ", forms_dir)
    message("\nNext steps:")
    message("1. Review generated configuration files")
    message("2. Test authentication with generated users")
    message("3. Launch ZZedc: source('launch_", project_name, ".R')")
    message("=====================================")
  } else {
    message("\n❌ ZZedc setup completed with errors")
    message("Check the error messages above")
    message("=====================================")
  }

  return(overall_success)
}

#' Ensure required directories exist
ensure_directories <- function(db_path, forms_dir) {
  # Create data directory
  data_dir <- dirname(db_path)
  if (!dir.exists(data_dir)) {
    dir.create(data_dir, recursive = TRUE)
    message("Created data directory: ", data_dir)
  }

  # Create forms directory
  if (!dir.exists(forms_dir)) {
    dir.create(forms_dir, recursive = TRUE)
    message("Created forms directory: ", forms_dir)
  }

  # Create backup directory
  backup_dir <- "backups"
  if (!dir.exists(backup_dir)) {
    dir.create(backup_dir, recursive = TRUE)
    message("Created backup directory: ", backup_dir)
  }
}

#' Backup existing database
backup_database <- function(db_path) {
  if (file.exists(db_path)) {
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    backup_name <- paste0("backup_", basename(db_path), "_", timestamp)
    backup_path <- file.path("backups", backup_name)
    file.copy(db_path, backup_path)
    message("Backed up existing database to: ", backup_path)
  }
}

#' Validate access to required Google Sheets
validate_sheets_access <- function(auth_sheet_name, dd_sheet_name) {
  tryCatch({
    # Try to list sheets accessible to the authenticated user
    available_sheets <- gs4_find()

    # Check if required sheets exist
    auth_exists <- auth_sheet_name %in% available_sheets$name
    dd_exists <- dd_sheet_name %in% available_sheets$name

    if (!auth_exists) {
      message("✗ Authentication sheet not found: ", auth_sheet_name)
      message("Available sheets: ", paste(head(available_sheets$name, 10), collapse = ", "))
    } else {
      message("✓ Found authentication sheet: ", auth_sheet_name)
    }

    if (!dd_exists) {
      message("✗ Data dictionary sheet not found: ", dd_sheet_name)
      message("Available sheets: ", paste(head(available_sheets$name, 10), collapse = ", "))
    } else {
      message("✓ Found data dictionary sheet: ", dd_sheet_name)
    }

    return(auth_exists && dd_exists)

  }, error = function(e) {
    message("✗ Error validating Google Sheets access: ", e$message)
    return(FALSE)
  })
}

#' Generate configuration files for ZZedc integration
generate_zzedc_config <- function(project_name, db_path, forms_dir) {
  tryCatch({
    # Generate config.yml file
    config_content <- paste0(
      "# Generated configuration for ", project_name, "\n",
      "# Generated on: ", Sys.time(), "\n\n",
      "default:\n",
      "  database:\n",
      "    path: '", db_path, "'\n",
      "    pool_size: 5\n",
      "  auth:\n",
      "    salt_env_var: 'ZZEDC_SALT'\n",
      "    default_salt: 'zzedc_default_salt'\n",
      "  app:\n",
      "    title: '", project_name, " EDC'\n",
      "    forms_dir: '", forms_dir, "'\n",
      "  logging:\n",
      "    level: 'INFO'\n",
      "    file: 'logs/zzedc.log'\n"
    )

    writeLines(config_content, "config.yml")
    message("✓ Generated config.yml")

    # Update global.R to use the Google Sheets database
    update_global_r(db_path)

    return(TRUE)

  }, error = function(e) {
    message("✗ Error generating configuration files: ", e$message)
    return(FALSE)
  })
}

#' Update global.R to use the new database
update_global_r <- function(db_path) {
  global_r_path <- "global.R"

  if (file.exists(global_r_path)) {
    # Read existing global.R
    global_content <- readLines(global_r_path)

    # Find and update database path
    db_line_idx <- grep("dbname.*=", global_content)
    if (length(db_line_idx) > 0) {
      # Update existing database path
      global_content[db_line_idx[1]] <- paste0("  dbname = '", db_path, "',")
      writeLines(global_content, global_r_path)
      message("✓ Updated global.R database path")
    } else {
      message("⚠ Could not find database configuration in global.R")
    }
  } else {
    message("⚠ global.R not found - manual configuration may be required")
  }
}

#' Create launch scripts for the EDC system
create_launch_scripts <- function(project_name, db_path) {
  tryCatch({
    # Create launch script
    launch_script_name <- paste0("launch_", gsub("[^A-Za-z0-9]", "_", project_name), ".R")

    launch_content <- paste0(
      "# Launch script for ", project_name, " EDC\n",
      "# Generated on: ", Sys.time(), "\n\n",
      "# Load required libraries\n",
      "library(shiny)\n",
      "library(pacman)\n\n",
      "# Set working directory to script location\n",
      "setwd(dirname(rstudioapi::getSourceEditorContext()$path))\n\n",
      "# Verify database exists\n",
      "if (!file.exists('", db_path, "')) {\n",
      "  stop('Database not found: ", db_path, "')\n",
      "}\n\n",
      "# Launch the application\n",
      "message('Launching ", project_name, " EDC...')\n",
      "message('Database: ", db_path, "')\n",
      "message('Navigate to http://localhost:3838 when ready')\n\n",
      "shiny::runApp(\n",
      "  appDir = '.', \n",
      "  port = 3838, \n",
      "  launch.browser = TRUE\n",
      ")\n"
    )

    writeLines(launch_content, launch_script_name)
    message("✓ Created launch script: ", launch_script_name)

    # Create test script
    test_script_name <- paste0("test_", gsub("[^A-Za-z0-9]", "_", project_name), ".R")

    test_content <- paste0(
      "# Test script for ", project_name, " EDC\n",
      "# Generated on: ", Sys.time(), "\n\n",
      "library(RSQLite)\n",
      "library(DT)\n\n",
      "# Test database connection\n",
      "con <- dbConnect(SQLite(), '", db_path, "')\n\n",
      "# List all tables\n",
      "cat('=== Database Tables ===\\n')\n",
      "print(dbListTables(con))\n\n",
      "# Show user accounts\n",
      "cat('\\n=== User Accounts ===\\n')\n",
      "users <- dbGetQuery(con, 'SELECT username, full_name, role, active FROM edc_users')\n",
      "print(users)\n\n",
      "# Show forms\n",
      "cat('\\n=== Available Forms ===\\n')\n",
      "forms <- dbGetQuery(con, 'SELECT workingname, fullname FROM edc_forms')\n",
      "print(forms)\n\n",
      "# Test authentication function\n",
      "source('auth.R')\n",
      "cat('\\n=== Testing Authentication ===\\n')\n",
      "if (nrow(users) > 0) {\n",
      "  test_user <- users$username[1]\n",
      "  cat('Testing user:', test_user, '\\n')\n",
      "  # Note: You'll need to know the password to test\n",
      "} else {\n",
      "  cat('No users found to test\\n')\n",
      "}\n\n",
      "dbDisconnect(con)\n",
      "cat('\\n=== Test completed ===\\n')\n"
    )

    writeLines(test_content, test_script_name)
    message("✓ Created test script: ", test_script_name)

    return(TRUE)

  }, error = function(e) {
    message("✗ Error creating launch scripts: ", e$message)
    return(FALSE)
  })
}

#' Perform final validation of the complete system
perform_final_validation <- function(db_path) {
  tryCatch({
    message("Performing final system validation...")

    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))

    # Check all required tables exist
    tables <- dbListTables(con)
    required_tables <- c("edc_users", "edc_forms", "edc_fields", "edc_sites", "edc_roles")
    missing_tables <- setdiff(required_tables, tables)

    if (length(missing_tables) > 0) {
      message("✗ Missing required tables: ", paste(missing_tables, collapse = ", "))
      return(FALSE)
    }

    # Check data integrity
    user_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users WHERE active = 1")$count
    form_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_forms")$count
    field_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_fields")$count

    if (user_count == 0) {
      message("✗ No active users found")
      return(FALSE)
    }

    if (form_count == 0) {
      message("✗ No forms found")
      return(FALSE)
    }

    if (field_count == 0) {
      message("✗ No form fields found")
      return(FALSE)
    }

    # Test views
    tryCatch({
      dbGetQuery(con, "SELECT * FROM v_users_detailed LIMIT 1")
      dbGetQuery(con, "SELECT * FROM v_forms_detailed LIMIT 1")
    }, error = function(e) {
      message("✗ Database views not working: ", e$message)
      return(FALSE)
    })

    message("✓ Final validation passed")
    message("  - Active users: ", user_count)
    message("  - Forms: ", form_count)
    message("  - Fields: ", field_count)

    return(TRUE)

  }, error = function(e) {
    message("✗ Final validation failed: ", e$message)
    return(FALSE)
  })
}

# Convenience function for quick setup with default parameters
quick_setup <- function(auth_sheet = "zzedc_auth", dd_sheet = "zzedc_data_dictionary") {
  setup_zzedc_from_gsheets_complete(
    auth_sheet_name = auth_sheet,
    dd_sheet_name = dd_sheet,
    project_name = "quick_zzedc"
  )
}

# Example usage function
example_usage <- function() {
  cat("=== ZZedc Google Sheets Setup - Example Usage ===\n\n")
  cat("1. Basic setup with default parameters:\n")
  cat("   setup_zzedc_from_gsheets_complete()\n\n")

  cat("2. Setup with custom sheet names:\n")
  cat("   setup_zzedc_from_gsheets_complete(\n")
  cat("     auth_sheet_name = 'my_auth_sheet',\n")
  cat("     dd_sheet_name = 'my_data_dictionary',\n")
  cat("     project_name = 'my_clinical_trial'\n")
  cat("   )\n\n")

  cat("3. Quick setup (uses defaults):\n")
  cat("   quick_setup('my_auth_sheet', 'my_dd_sheet')\n\n")

  cat("Required Google Sheets structure:\n")
  cat("- Authentication sheet with tabs: users, roles, sites\n")
  cat("- Data dictionary sheet with tabs: forms_overview, form_[name], visits\n\n")
}

# Print usage instructions when sourced
if (interactive()) {
  example_usage()
}