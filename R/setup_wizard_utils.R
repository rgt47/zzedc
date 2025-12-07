#' @keywords internal
NULL

#' Create ZZedc Database from Wizard Configuration
#'
#' Creates a complete database with all required tables
#'
#' @param config_list List containing wizard configuration (from wizard_state$system_config)
#' @param db_path Path where database file will be created
#'
#' @return List with success status and messages
#' @examples
#' \dontrun{
#' config <- list(
#'   study_name = "My Study",
#'   protocol_id = "PROTO-001",
#'   admin_username = "admin",
#'   admin_password = "MyPass123!",
#'   security_salt = "abc123..."
#' )
#' create_wizard_database(config, "~/my_study.db")
#' }
#' @export
create_wizard_database <- function(config_list, db_path) {

  tryCatch({
    # Create directory if needed
    db_dir <- dirname(db_path)
    if (!dir.exists(db_dir) && db_dir != ".") {
      dir.create(db_dir, recursive = TRUE)
    }

    # Create connection
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)

    # Create main tables
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS study_info (
        study_id TEXT PRIMARY KEY,
        study_name TEXT NOT NULL,
        protocol_id TEXT UNIQUE NOT NULL,
        principal_investigator TEXT,
        pi_email TEXT,
        study_phase TEXT,
        target_enrollment INTEGER,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_by TEXT,
        updated_date TIMESTAMP,
        updated_by TEXT
      )
    ")

    # Create users table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS edc_users (
        user_id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        full_name TEXT,
        email TEXT,
        role TEXT CHECK(role IN ('Admin', 'PI', 'Coordinator', 'Data Manager', 'Monitor')),
        site_id TEXT,
        active BOOLEAN DEFAULT 1,
        last_login TIMESTAMP,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_by TEXT,
        modified_date TIMESTAMP,
        modified_by TEXT
      )
    ")

    # Create roles table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS edc_roles (
        role_id INTEGER PRIMARY KEY AUTOINCREMENT,
        role_name TEXT UNIQUE NOT NULL,
        description TEXT,
        permissions TEXT,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    # Create subjects table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS subjects (
        subject_id TEXT PRIMARY KEY,
        study_id TEXT NOT NULL REFERENCES study_info(study_id),
        enrollment_date TIMESTAMP,
        enrollment_age INTEGER,
        status TEXT CHECK(status IN ('Active', 'Completed', 'Withdrawn')),
        withdrawal_reason TEXT,
        withdrawal_date TIMESTAMP,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_by TEXT,
        modified_date TIMESTAMP,
        modified_by TEXT,
        site_id TEXT
      )
    ")

    # Create data_entries table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS data_entries (
        entry_id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL REFERENCES subjects(subject_id),
        form_name TEXT NOT NULL,
        visit_label TEXT,
        visit_date TIMESTAMP,
        data_json TEXT,
        is_complete BOOLEAN DEFAULT 0,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_by TEXT NOT NULL,
        modified_date TIMESTAMP,
        modified_by TEXT,
        locked BOOLEAN DEFAULT 0
      )
    ")

    # Create validation_results table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS validation_results (
        validation_id TEXT PRIMARY KEY,
        entry_id TEXT NOT NULL REFERENCES data_entries(entry_id),
        field_name TEXT,
        rule_name TEXT,
        is_valid BOOLEAN,
        error_message TEXT,
        check_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    # Create audit_trail table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS audit_trail (
        audit_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES edc_users(user_id),
        action TEXT,
        entity_type TEXT,
        entity_id TEXT,
        old_values TEXT,
        new_values TEXT,
        action_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        ip_address TEXT,
        user_agent TEXT
      )
    ")

    # Insert study info
    study_id <- paste0("STUDY_", as.integer(Sys.time()))
    DBI::dbExecute(conn, "
      INSERT INTO study_info
      (study_id, study_name, protocol_id, principal_investigator, pi_email,
       study_phase, target_enrollment, created_date, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
    ", params = list(
      study_id,
      config_list$study_name,
      config_list$protocol_id,
      config_list$pi_name,
      config_list$pi_email,
      config_list$study_phase,
      config_list$target_enrollment,
      "setup_wizard"
    ))

    # Create admin user
    admin_id <- paste0("USER_", as.integer(Sys.time()))
    salt <- config_list$security_salt
    password_hash <- digest::digest(paste0(config_list$admin_password, salt), algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO edc_users
      (user_id, username, password_hash, full_name, email, role, active, created_date, created_by)
      VALUES (?, ?, ?, ?, ?, ?, 1, datetime('now'), ?)
    ", params = list(
      admin_id,
      config_list$admin_username,
      password_hash,
      config_list$admin_fullname,
      config_list$admin_email,
      "Admin",
      "setup_wizard"
    ))

    # Insert predefined roles
    roles <- list(
      list("Admin", "Full system access", "all"),
      list("PI", "Principal Investigator - read/write access", "read,write,reports"),
      list("Coordinator", "Data entry and basic reports", "data_entry,read_own"),
      list("Data Manager", "Data management and analysis", "read,write,reports,export"),
      list("Monitor", "Read-only access for monitoring", "read_only")
    )

    for (role in roles) {
      DBI::dbExecute(conn, "
        INSERT INTO edc_roles (role_name, description, permissions, created_date)
        VALUES (?, ?, ?, datetime('now'))
      ", params = role)
    }

    # Add team members if provided
    if (!is.null(config_list$team_members) && nrow(config_list$team_members) > 0) {
      for (i in 1:nrow(config_list$team_members)) {
        member <- config_list$team_members[i, ]
        member_id <- paste0("USER_", as.integer(Sys.time()) + i)

        # Generate temporary password
        temp_password <- paste0(
          sample(c(letters, LETTERS, 0:9), 10, replace = TRUE),
          collapse = ""
        )
        member_hash <- digest::digest(paste0(temp_password, salt), algo = "sha256")

        DBI::dbExecute(conn, "
          INSERT INTO edc_users
          (user_id, username, password_hash, full_name, email, role, active, created_date, created_by)
          VALUES (?, ?, ?, ?, ?, ?, 1, datetime('now'), ?)
        ", params = list(
          member_id,
          member$username,
          member_hash,
          member$full_name,
          member$email,
          member$role,
          "setup_wizard"
        ))
      }
    }

    # Create indexes for performance
    DBI::dbExecute(conn, "CREATE INDEX idx_subjects_study_id ON subjects(study_id)")
    DBI::dbExecute(conn, "CREATE INDEX idx_users_username ON edc_users(username)")
    DBI::dbExecute(conn, "CREATE INDEX idx_data_entries_subject ON data_entries(subject_id)")
    DBI::dbExecute(conn, "CREATE INDEX idx_audit_user_date ON audit_trail(user_id, action_date)")

    # Close connection
    DBI::dbDisconnect(conn)

    return(list(
      success = TRUE,
      message = paste("Database created successfully at", db_path),
      study_id = study_id,
      admin_id = admin_id
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      message = paste("Error creating database:", e$message)
    ))
  })
}


#' Create Config File from Wizard Configuration
#' @export
#'
#' Creates configuration file with all required application settings
#'
#' @param config_list List containing wizard configuration
#' @param config_path Path where config.yml will be written
#' @param security_salt The security salt for hashing
#'
#' @return List with success status and messages
create_wizard_config <- function(config_list, config_path, security_salt) {

  tryCatch({
    config_dir <- dirname(config_path)
    if (!dir.exists(config_dir) && config_dir != ".") {
      dir.create(config_dir, recursive = TRUE)
    }

    # Create YAML content
    config_yaml <- sprintf("
# ZZedc Configuration - Auto-generated by Setup Wizard
# Study: %s
# Protocol: %s
# Created: %s

database:
  type: sqlite
  path: ./data/zzedc.db
  pool_size: 5

auth:
  salt_env_var: ZZEDC_SALT
  default_salt: %s
  session_timeout_minutes: %d
  max_failed_attempts: %d

security:
  enforce_https: %s
  password_min_length: 8
  password_require_special_chars: true

ui:
  theme: bootstrap
  bootstrap_version: 5
  brand_name: ZZedc

study:
  name: %s
  protocol_id: %s
  pi_name: %s
  pi_email: %s
  phase: %s
  target_enrollment: %d

compliance:
  gdpr_enabled: true
  cfr_part11_enabled: true
  enable_audit_logging: true
  enable_electronic_signatures: false

logging:
  level: info
  file: ./logs/zzedc.log
  max_file_size_mb: 50
  keep_files: 30
",
      config_list$study_name,
      config_list$protocol_id,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      security_salt,
      config_list$session_timeout,
      config_list$max_login_attempts,
      ifelse(config_list$enforce_https == "yes", "true", "false"),
      config_list$study_name,
      config_list$protocol_id,
      config_list$pi_name,
      config_list$pi_email,
      config_list$study_phase,
      config_list$target_enrollment
    )

    # Write config file
    writeLines(config_yaml, config_path)

    return(list(
      success = TRUE,
      message = paste("Configuration file created at", config_path)
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      message = paste("Error creating config:", e$message)
    ))
  })
}


#' Create Directories for New ZZedc Instance
#' @export
#'
#' Creates the directory structure needed for a new ZZedc installation
#'
#' @param base_path Base directory where subdirectories will be created
#'
#' @return List with success status
create_wizard_directories <- function(base_path) {

  tryCatch({
    dirs_to_create <- c(
      "data",           # Database files
      "logs",           # Application logs
      "forms",          # Form definitions
      "backups",        # Database backups
      "exports",        # Data exports
      "uploads",        # File uploads
      "config",         # Configuration files
      "www"             # Static web assets
    )

    for (dir in dirs_to_create) {
      dir_path <- file.path(base_path, dir)
      if (!dir.exists(dir_path)) {
        dir.create(dir_path, recursive = TRUE)
      }
    }

    return(list(
      success = TRUE,
      message = "Directory structure created successfully"
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      message = paste("Error creating directories:", e$message)
    ))
  })
}


#' Create Launch Script for New ZZedc Instance
#'
#' Creates a customized launch script file that users can run to start the application
#'
#' @param config_list Configuration from wizard
#' @param output_path Path where launch script will be written
#'
#' @return List with success status
#' @export
create_launch_script <- function(config_list, output_path) {

  tryCatch({
    script_content <- sprintf("
#!/usr/bin/env Rscript
# Launch script for %s
# Auto-generated by Setup Wizard

# Set environment variables
Sys.setenv(ZZEDC_SALT = '%s')

# Load required packages
library(zzedc)
library(shiny)

# Launch application
cat('\\n')
cat('========================================\\n')
cat('Launching ZZedc - %s\\n')
cat('Protocol: %s\\n')
cat('========================================\\n')
cat('\\n')
cat('Opening browser to http://localhost:3838\\n')
cat('\\n')

# Launch the app
launch_zzedc(
  host = '127.0.0.1',
  port = 3838,
  launch.browser = TRUE
)
",
      config_list$study_name,
      config_list$security_salt,
      config_list$study_name,
      config_list$protocol_id
    )

    # Write script
    writeLines(script_content, output_path)

    # Make executable on Unix systems
    if (.Platform$OS.type == "unix") {
      Sys.chmod(output_path, mode = "0755")
    }

    return(list(
      success = TRUE,
      message = paste("Launch script created at", output_path)
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      message = paste("Error creating launch script:", e$message)
    ))
  })
}


#' Complete Setup Wizard Orchestration
#'
#' Orchestrates all setup steps for initializing a new ZZedc instance
#'
#' @param config_list Complete configuration from wizard
#' @param base_path Base directory for new installation
#'
#' @return List with overall success status and detailed results
#' @export
complete_wizard_setup <- function(config_list, base_path = "~/zzedc_instance") {

  results <- list(
    overall_success = TRUE,
    steps = list()
  )

  # Step 1: Create directories
  dir_result <- create_wizard_directories(base_path)
  results$steps$directories <- dir_result
  if (!dir_result$success) {
    results$overall_success <- FALSE
    return(results)
  }

  # Step 2: Create database
  db_path <- file.path(base_path, "data", "zzedc.db")
  db_result <- create_wizard_database(config_list, db_path)
  results$steps$database <- db_result
  if (!db_result$success) {
    results$overall_success <- FALSE
    return(results)
  }

  # Step 3: Create config
  config_path <- file.path(base_path, "config.yml")
  config_result <- create_wizard_config(config_list, config_path, config_list$security_salt)
  results$steps$config <- config_result
  if (!config_result$success) {
    results$overall_success <- FALSE
    return(results)
  }

  # Step 4: Create launch script
  script_path <- file.path(base_path, "launch_app.R")
  script_result <- create_launch_script(config_list, script_path)
  results$steps$launch_script <- script_result

  # Step 5: Create environment file for security salt
  env_path <- file.path(base_path, ".env")
  env_content <- sprintf("# Environment variables for ZZedc\nZZEDC_SALT=%s\n", config_list$security_salt)
  writeLines(env_content, env_path)
  results$steps$env_file <- list(
    success = TRUE,
    message = paste("Environment file created at", env_path)
  )

  results$summary <- sprintf(
    "ZZedc setup complete!\nLocation: %s\nDatabase: %s\nLaunch: Rscript %s",
    base_path,
    db_path,
    script_path
  )

  return(results)
}
