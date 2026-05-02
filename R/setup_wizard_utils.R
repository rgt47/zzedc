#' Setup Wizard Utilities
#'
#' Functions for creating and configuring new ZZedc instances.
#' Supports multiple database backends (SQLite, DuckDB, PostgreSQL).
#'
#' @name setup_wizard_utils
#' @keywords internal
NULL


#' Create ZZedc Database from Wizard Configuration
#'
#' Creates a complete database with all required tables.
#' Supports SQLite (default), DuckDB, and PostgreSQL backends.
#'
#' @param config_list List containing wizard configuration
#' @param db_path Path where database file will be created (for SQLite/DuckDB)
#' @param backend Database backend: "sqlite" (default), "duckdb", or "postgresql"
#' @param pg_config PostgreSQL configuration list (required if backend="postgresql")
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
#'
#' # SQLite (default)
#' create_wizard_database(config, "~/my_study.db")
#'
#' # DuckDB
#' create_wizard_database(config, "~/my_study.duckdb", backend = "duckdb")
#'
#' # PostgreSQL
#' create_wizard_database(config, backend = "postgresql",
#'   pg_config = list(host = "localhost", name = "zzedc",
#'                    user = "admin", password = "secret"))
#' }
#' @export
create_wizard_database <- function(config_list, db_path = NULL,
                                   backend = "sqlite", pg_config = NULL) {

  tryCatch({
    # Validate parent directory exists for file-based backends
    if (backend %in% c("sqlite", "duckdb") && !is.null(db_path)) {
      parent_dir <- dirname(db_path)
      if (!dir.exists(parent_dir)) {
        return(list(
          success = FALSE,
          message = paste("Error: Parent directory does not exist:", parent_dir)
        ))
      }
    }

    # Build adapter configuration
    adapter_config <- build_adapter_config(backend, db_path, pg_config)

    # Create adapter and connection
    adapter <- create_db_adapter(adapter_config)
    conn <- adapter$connect()
    dialect <- adapter$dialect()

    # Create all core tables using dialect-aware DDL
    create_core_tables(conn, dialect, backend)

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
      for (i in seq_len(nrow(config_list$team_members))) {
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

    # Create indexes for performance (IF NOT EXISTS for idempotency)
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_subjects_study_id ON subjects(study_id)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_users_username ON edc_users(username)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_data_entries_subject ON data_entries(subject_id)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_user_date ON audit_trail(user_id, action_date)")

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
#'
#' Creates configuration file with all required application settings
#'
#' @param config_list List containing wizard configuration
#' @param config_path Path where config.yml will be written
#' @param security_salt The security salt for hashing
#'
#' @return List with success status and messages
#' @keywords internal
#' @export
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
#'
#' Creates the directory structure needed for a new ZZedc installation
#'
#' @param base_path Base directory where subdirectories will be created
#'
#' @return List with success status
#' @keywords internal
#' @export
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
#'
#' @keywords internal
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
#' @param base_path Character. Base directory for the new installation.
#'   Required; no default. The function writes a database, configuration
#'   file, launch script, and `.env` file under this path, so the caller
#'   must choose a location explicitly. For testing or examples, pass
#'   `tempfile(pattern = "zzedc_")`. For production, pass a stable
#'   project directory (for example `"~/research/study_001"`).
#'
#' @return List with overall success status and detailed results
#'
#' @examples
#' \dontrun{
#' # Scaffold a fresh study under a temporary directory. In a real
#' # deployment, replace `base_path` with the project root, for
#' # example `"~/research/depress_pilot"`.
#' study_config <- list(
#'   study_name        = "Depression Pilot Study",
#'   protocol_id       = "DEP-001",
#'   pi_name           = "Dr. A. Investigator",
#'   pi_email          = "investigator@example.org",
#'   study_phase       = "Pilot",
#'   target_enrollment = 50,
#'   admin_username    = "admin",
#'   admin_password    = "ChangeMe!2026",
#'   admin_fullname    = "Study Administrator",
#'   admin_email       = "admin@example.org",
#'   security_salt     = paste(sample(letters, 16, replace = TRUE),
#'                             collapse = "")
#' )
#' result <- complete_wizard_setup(
#'   config_list = study_config,
#'   base_path   = tempfile(pattern = "zzedc_")
#' )
#' result$overall_success
#' }
#' @export
complete_wizard_setup <- function(config_list, base_path = NULL) {

  if (is.null(base_path) || !nzchar(base_path)) {
    stop(
      "`base_path` is required. Pass a directory where the ZZedc instance ",
      "should be created, for example `tempfile(pattern = \"zzedc_\")` ",
      "for testing or `\"~/research/study_001\"` for production.",
      call. = FALSE
    )
  }

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


# ============================================================================
# Multi-Backend Support Helpers
# ============================================================================

#' Build Adapter Configuration
#'
#' Constructs configuration list for database adapter based on backend type.
#'
#' @param backend Backend type: "sqlite", "duckdb", "postgresql", "clickhouse"
#' @param db_path Path to database file (for file-based backends)
#' @param server_config Server configuration list (for server-based backends)
#'
#' @return Configuration list suitable for create_db_adapter()
#'
#' @keywords internal
build_adapter_config <- function(backend, db_path = NULL, server_config = NULL) {
  backend <- tolower(backend)

  switch(
    backend,

    sqlite = {
      if (is.null(db_path)) {
        stop("SQLite backend requires db_path")
      }
      # Ensure directory exists
      db_dir <- dirname(db_path)
      if (!dir.exists(db_dir) && db_dir != ".") {
        dir.create(db_dir, recursive = TRUE)
      }
      list(
        db_backend = "sqlite",
        sqlite = list(path = db_path)
      )
    },

    duckdb = {
      if (is.null(db_path)) {
        stop("DuckDB backend requires db_path")
      }
      db_dir <- dirname(db_path)
      if (!dir.exists(db_dir) && db_dir != ".") {
        dir.create(db_dir, recursive = TRUE)
      }
      list(
        db_backend = "duckdb",
        duckdb = list(path = db_path)
      )
    },

    postgresql = ,
    postgres = {
      if (is.null(server_config)) {
        stop("PostgreSQL backend requires server_config")
      }
      list(
        db_backend = "postgresql",
        postgresql = list(
          host = server_config$host %||% "localhost",
          port = server_config$port %||% 5432L,
          name = server_config$name %||% server_config$database,
          user = server_config$user,
          password = server_config$password,
          sslmode = server_config$sslmode %||% "prefer"
        )
      )
    },

    clickhouse = {
      if (is.null(server_config)) {
        stop("ClickHouse backend requires server_config")
      }
      list(
        db_backend = "clickhouse",
        clickhouse = list(
          host = server_config$host %||% "localhost",
          port = server_config$port %||% 8123L,
          database = server_config$database %||% server_config$name,
          user = server_config$user %||% "default",
          password = server_config$password %||% ""
        )
      )
    },

    stop("Unsupported backend: ", backend,
         "\nSupported: sqlite, duckdb, postgresql, clickhouse")
  )
}


#' Create Core Database Tables
#'
#' Creates all required tables for ZZedc using dialect-appropriate DDL.
#'
#' @param conn Database connection
#' @param dialect Dialect object from adapter
#' @param backend Backend name for engine-specific syntax
#'
#' @return Invisible NULL
#'
#' @keywords internal
create_core_tables <- function(conn, dialect, backend) {

  # Get type mappings from dialect
  text_type <- dialect$text_type
  int_type <- dialect$integer_type
  bool_type <- dialect$boolean_type
  ts_type <- dialect$timestamp_type
  bool_default_true <- dialect$boolean_true
  bool_default_false <- dialect$boolean_false

  # ClickHouse requires ENGINE clause
  engine_clause <- if (backend == "clickhouse") {
    "ENGINE = MergeTree() ORDER BY"
  } else {
    ""
  }

  # Study Info table
  if (backend == "clickhouse") {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS study_info (
        study_id %s,
        study_name %s,
        protocol_id %s,
        principal_investigator %s,
        pi_email %s,
        study_phase %s,
        target_enrollment %s,
        created_date %s,
        created_by %s,
        updated_date %s,
        updated_by %s
      ) ENGINE = MergeTree() ORDER BY study_id
    ", text_type, text_type, text_type, text_type, text_type,
       text_type, int_type, ts_type, text_type, ts_type, text_type))
  } else {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS study_info (
        study_id %s PRIMARY KEY,
        study_name %s NOT NULL,
        protocol_id %s UNIQUE NOT NULL,
        principal_investigator %s,
        pi_email %s,
        study_phase %s,
        target_enrollment %s,
        created_date %s DEFAULT CURRENT_TIMESTAMP,
        created_by %s,
        updated_date %s,
        updated_by %s
      )
    ", text_type, text_type, text_type, text_type, text_type,
       text_type, int_type, ts_type, text_type, ts_type, text_type))
  }

  # Users table
  if (backend == "clickhouse") {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS edc_users (
        user_id %s,
        username %s,
        password_hash %s,
        full_name %s,
        email %s,
        role %s,
        site_id %s,
        active %s DEFAULT %s,
        last_login %s,
        created_date %s,
        created_by %s,
        modified_date %s,
        modified_by %s
      ) ENGINE = MergeTree() ORDER BY user_id
    ", text_type, text_type, text_type, text_type, text_type,
       text_type, text_type, bool_type, bool_default_true,
       ts_type, ts_type, text_type, ts_type, text_type))
  } else {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS edc_users (
        user_id %s PRIMARY KEY,
        username %s UNIQUE NOT NULL,
        password_hash %s NOT NULL,
        full_name %s,
        email %s,
        role %s,
        site_id %s,
        active %s DEFAULT %s,
        last_login %s,
        created_date %s DEFAULT CURRENT_TIMESTAMP,
        created_by %s,
        modified_date %s,
        modified_by %s
      )
    ", text_type, text_type, text_type, text_type, text_type,
       text_type, text_type, bool_type, bool_default_true,
       ts_type, ts_type, text_type, ts_type, text_type))
  }

  # Roles table
  if (backend == "clickhouse") {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS edc_roles (
        role_id %s,
        role_name %s,
        description %s,
        permissions %s,
        created_date %s
      ) ENGINE = MergeTree() ORDER BY role_id
    ", int_type, text_type, text_type, text_type, ts_type))
  } else {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS edc_roles (
        role_id %s,
        role_name %s UNIQUE NOT NULL,
        description %s,
        permissions %s,
        created_date %s DEFAULT CURRENT_TIMESTAMP
      )
    ", dialect$auto_increment, text_type, text_type, text_type, ts_type))
  }

  # Subjects table
  if (backend == "clickhouse") {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS subjects (
        subject_id %s,
        study_id %s,
        enrollment_date %s,
        enrollment_age %s,
        status %s,
        withdrawal_reason %s,
        withdrawal_date %s,
        created_date %s,
        created_by %s,
        modified_date %s,
        modified_by %s,
        site_id %s
      ) ENGINE = MergeTree() ORDER BY (study_id, subject_id)
    ", text_type, text_type, ts_type, int_type, text_type,
       text_type, ts_type, ts_type, text_type, ts_type, text_type, text_type))
  } else {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS subjects (
        subject_id %s PRIMARY KEY,
        study_id %s NOT NULL,
        enrollment_date %s,
        enrollment_age %s,
        status %s,
        withdrawal_reason %s,
        withdrawal_date %s,
        created_date %s DEFAULT CURRENT_TIMESTAMP,
        created_by %s,
        modified_date %s,
        modified_by %s,
        site_id %s
      )
    ", text_type, text_type, ts_type, int_type, text_type,
       text_type, ts_type, ts_type, text_type, ts_type, text_type, text_type))
  }

  # Data entries table
  if (backend == "clickhouse") {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS data_entries (
        entry_id %s,
        subject_id %s,
        form_name %s,
        visit_label %s,
        visit_date %s,
        data_json %s,
        is_complete %s DEFAULT %s,
        created_date %s,
        created_by %s,
        modified_date %s,
        modified_by %s,
        locked %s DEFAULT %s
      ) ENGINE = MergeTree() ORDER BY (subject_id, entry_id)
    ", text_type, text_type, text_type, text_type, ts_type,
       text_type, bool_type, bool_default_false, ts_type, text_type,
       ts_type, text_type, bool_type, bool_default_false))
  } else {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS data_entries (
        entry_id %s PRIMARY KEY,
        subject_id %s NOT NULL,
        form_name %s NOT NULL,
        visit_label %s,
        visit_date %s,
        data_json %s,
        is_complete %s DEFAULT %s,
        created_date %s DEFAULT CURRENT_TIMESTAMP,
        created_by %s NOT NULL,
        modified_date %s,
        modified_by %s,
        locked %s DEFAULT %s
      )
    ", text_type, text_type, text_type, text_type, ts_type,
       text_type, bool_type, bool_default_false, ts_type, text_type,
       ts_type, text_type, bool_type, bool_default_false))
  }

  # Validation results table
  if (backend == "clickhouse") {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS validation_results (
        validation_id %s,
        entry_id %s,
        field_name %s,
        rule_name %s,
        is_valid %s,
        error_message %s,
        check_date %s
      ) ENGINE = MergeTree() ORDER BY (entry_id, validation_id)
    ", text_type, text_type, text_type, text_type, bool_type,
       text_type, ts_type))
  } else {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS validation_results (
        validation_id %s PRIMARY KEY,
        entry_id %s NOT NULL,
        field_name %s,
        rule_name %s,
        is_valid %s,
        error_message %s,
        check_date %s DEFAULT CURRENT_TIMESTAMP
      )
    ", text_type, text_type, text_type, text_type, bool_type,
       text_type, ts_type))
  }

  # Audit trail table
  if (backend == "clickhouse") {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS audit_trail (
        audit_id %s,
        user_id %s,
        action %s,
        entity_type %s,
        entity_id %s,
        old_values %s,
        new_values %s,
        action_date %s,
        ip_address %s,
        user_agent %s
      ) ENGINE = MergeTree() ORDER BY (action_date, audit_id)
    ", text_type, text_type, text_type, text_type, text_type,
       text_type, text_type, ts_type, text_type, text_type))
  } else {
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS audit_trail (
        audit_id %s PRIMARY KEY,
        user_id %s NOT NULL,
        action %s,
        entity_type %s,
        entity_id %s,
        old_values %s,
        new_values %s,
        action_date %s DEFAULT CURRENT_TIMESTAMP,
        ip_address %s,
        user_agent %s
      )
    ", text_type, text_type, text_type, text_type, text_type,
       text_type, text_type, ts_type, text_type, text_type))
  }

  # Create indexes (skip for ClickHouse - uses ORDER BY instead)
  if (backend != "clickhouse") {
    tryCatch({
      DBI::dbExecute(conn,
        "CREATE INDEX IF NOT EXISTS idx_subjects_study ON subjects(study_id)")
      DBI::dbExecute(conn,
        "CREATE INDEX IF NOT EXISTS idx_users_username ON edc_users(username)")
      DBI::dbExecute(conn,
        "CREATE INDEX IF NOT EXISTS idx_entries_subject ON data_entries(subject_id)")
      DBI::dbExecute(conn,
        "CREATE INDEX IF NOT EXISTS idx_audit_date ON audit_trail(action_date)")
    }, error = function(e) {
      # Some backends may not support IF NOT EXISTS for indexes
      NULL
    })
  }

  invisible(NULL)
}


# Null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
