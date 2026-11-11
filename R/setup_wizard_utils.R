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
#' Supports SQLite (default), DuckDB, PostgreSQL, ClickHouse, and
#' MySQL/MariaDB backends.
#'
#' @param config_list List containing wizard configuration
#' @param db_path Path where database file will be created (for SQLite/DuckDB)
#' @param backend Database backend: "sqlite" (default), "duckdb",
#'   "postgresql", "clickhouse", "mysql", or "mariadb"
#' @param pg_config Server configuration list (required for the server
#'   backends: "postgresql", "clickhouse", "mysql", "mariadb")
#' @param adapter_config Optional complete configuration for
#'   `create_db_adapter()` (for example from `app_database_config()`).
#'   When supplied it is used as is, so settings that `backend`,
#'   `db_path`, and `pg_config` cannot express (an encryption key,
#'   DuckDB extension settings) reach the database being created;
#'   `backend` and `db_path` are then taken from it.
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
                                   backend = "sqlite", pg_config = NULL,
                                   adapter_config = NULL) {

  if (!is.null(adapter_config)) {
    backend <- adapter_config$db_backend
    db_path <- app_database_path(adapter_config)
    if (is.na(db_path)) db_path <- NULL
  }

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
    if (is.null(adapter_config)) {
      adapter_config <- build_adapter_config(backend, db_path, pg_config)
    }

    # Create adapter and connection
    adapter <- create_db_adapter(adapter_config)
    conn <- adapter$connect()
    on.exit({
      adapter$disconnect(conn)
      adapter$shutdown()
    }, add = TRUE)
    dialect <- adapter$dialect()

    # Create all core tables using dialect-aware DDL
    create_core_tables(conn, dialect, backend, adapter)

    # Insert study info
    #
    # Optional config_list fields are coalesced to NA, not left as a
    # raw NULL: an R NULL has length 0, and DuckDB's parameter
    # binding requires every bound value to be length 1, so a NULL
    # element throws "Bind parameter values need to have the same
    # length" (SQLite's binding is lenient and accepts it, which hid
    # this for every backend but DuckDB).
    study_id <- paste0("STUDY_", as.integer(Sys.time()))
    DBI::dbExecute(conn, "
      INSERT INTO study_info
      (study_id, study_name, protocol_id, principal_investigator, pi_email,
       study_phase, target_enrollment, created_date, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
    ", params = list(
      study_id,
      config_list$study_name,
      config_list$protocol_id,
      config_list$pi_name %||% NA_character_,
      config_list$pi_email %||% NA_character_,
      config_list$study_phase %||% NA_character_,
      config_list$target_enrollment %||% NA_integer_,
      "setup_wizard"
    ))

    # Create admin user
    admin_id <- paste0("USER_", as.integer(Sys.time()))
    salt <- config_list$security_salt
    password_hash <- digest::digest(paste0(config_list$admin_password, salt), algo = "sha256")

    # must_change_password = 1: config_list$admin_password is
    # whatever the caller typed (often the documented default,
    # "admin123") -- previously launch_zzedc() only printed a
    # reminder to change it, with nothing enforcing that.
    DBI::dbExecute(conn, "
      INSERT INTO edc_users
      (user_id, username, password_hash, full_name, email, role, active, must_change_password, created_date, password_changed_date, created_by)
      VALUES (?, ?, ?, ?, ?, ?, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?)
    ", params = list(
      admin_id,
      config_list$admin_username,
      password_hash,
      config_list$admin_fullname %||% NA_character_,
      config_list$admin_email %||% NA_character_,
      "Admin",
      "setup_wizard"
    ))

    # Create PI account if provided separately from sysadmin
    if (!is.null(config_list$pi_username) &&
        nzchar(config_list$pi_username) &&
        config_list$pi_username != config_list$admin_username) {
      pi_pw   <- config_list$pi_password %||%
        paste0(sample(c(letters, LETTERS, 0:9), 12, replace = TRUE),
               collapse = '')
      pi_hash <- digest::digest(paste0(pi_pw, salt), algo = 'sha256')
      pi_id   <- paste0('USER_', as.integer(Sys.time()) + 1L)
      DBI::dbExecute(conn, "
        INSERT INTO edc_users
          (user_id, username, password_hash, full_name, email,
           role, active, must_change_password, created_date, password_changed_date, created_by)
        VALUES (?, ?, ?, ?, ?, 'PI', 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?)
      ", params = list(
        pi_id,
        config_list$pi_username,
        pi_hash,
        config_list$pi_fullname %||% config_list$pi_username,
        config_list$pi_email    %||% '',
        'setup_wizard'
      ))
    }

    # Insert predefined roles
    roles <- list(
      list("Admin", "Full system access", "all"),
      list("PI", "Principal Investigator - read/write access", "read,write,reports"),
      list("StudyManager",
           "Coordinating center study manager - configuration and user approval authority",
           "read,write,reports,export,approve_users"),
      list("Coordinator", "Data entry and basic reports", "data_entry,read_own"),
      list("Data Manager", "Data management and analysis", "read,write,reports,export"),
      list("Monitor", "Read-only access for monitoring", "read_only")
    )

    for (role in roles) {
      DBI::dbExecute(conn, "
        INSERT INTO edc_roles (role_name, description, permissions, created_date)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
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
          (user_id, username, password_hash, full_name, email, role, active, must_change_password, created_date, password_changed_date, created_by)
          VALUES (?, ?, ?, ?, ?, ?, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?)
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
#' Creates the application's `config.yml` from the wizard's choices.
#'
#' @param config_list List containing wizard configuration. Database
#'   fields: `db_backend` (default `"sqlite"`) and, for server backends,
#'   `db_settings` (`host`, `port`, `name`, `user`, `ssl`). Security
#'   fields: `security_profile` (default `"regulated"`), `enforce_https`.
#' @param config_path Path where config.yml will be written
#' @param security_salt The security salt for hashing
#'
#' @return List with success status and messages
#'
#' @details
#' Settings are written under `default:`, the schema `config::get()` (and
#' so `launch_zzedc()` and the application) reads. Before 2026-11-10 they
#' were written at the top level, which `config::get()` rejects ("You
#' must provide a default configuration"), so a wizard-created study
#' could not be launched. Secrets are not written: a DuckDB study refers
#' to `${DB_ENCRYPTION_KEY}`, a server study to `${ZZEDC_DB_PASSWORD}`.
#' @keywords internal
#' @export
create_wizard_config <- function(config_list, config_path, security_salt) {

  tryCatch({
    config_dir <- dirname(config_path)
    if (!dir.exists(config_dir) && config_dir != ".") {
      dir.create(config_dir, recursive = TRUE)
    }

    yq <- function(x) {
      x <- if (is.null(x) || length(x) == 0 || is.na(x)) "" else as.character(x)
      paste0('"', gsub('"', '\\\\"', x), '"')
    }
    backend <- config_list$db_backend %||% "sqlite"
    settings <- config_list$db_settings %||% list()

    lines <- c(
      "# ZZedc Configuration - Auto-generated by Setup Wizard",
      paste0("# Study: ", config_list$study_name),
      paste0("# Protocol: ", config_list$protocol_id),
      paste0("# Created: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      "",
      "default:",
      .database_config_yaml(backend, values = settings),
      "",
      "  auth:",
      "    salt_env_var: ZZEDC_SALT",
      paste0("    default_salt: ", yq(security_salt)),
      paste0("    session_timeout_minutes: ", as.integer(config_list$session_timeout %||% 30)),
      paste0("    max_failed_attempts: ", as.integer(config_list$max_login_attempts %||% 3)),
      "    lockout_duration_minutes: 15",
      "    password_expiry_days: 90",
      "",
      .security_config_yaml(
        config_list$security_profile %||% "regulated",
        enforce_https = identical(config_list$enforce_https, "yes")
      ),
      "    password_min_length: 8",
      "    password_require_special_chars: true",
      "",
      "  ui:",
      "    theme: bootstrap",
      "    bootstrap_version: 5",
      "    brand_name: ZZedc",
      "",
      "  study:",
      paste0("    name: ", yq(config_list$study_name)),
      paste0("    protocol_id: ", yq(config_list$protocol_id)),
      paste0("    pi_name: ", yq(config_list$pi_name)),
      paste0("    pi_email: ", yq(config_list$pi_email)),
      paste0("    phase: ", yq(config_list$study_phase)),
      paste0("    target_enrollment: ", as.integer(config_list$target_enrollment %||% 0)),
      "",
      "  compliance:",
      "    gdpr_enabled: true",
      "    cfr_part11_enabled: true",
      "    enable_audit_logging: true",
      "    enable_electronic_signatures: false",
      "",
      "  logging:",
      "    level: info",
      "    file: ./logs/zzedc.log",
      "    max_file_size_mb: 50",
      "    keep_files: 30"
    )

    writeLines(lines, config_path)

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
#' Creates a launch script that starts the application for this study.
#'
#' @param config_list Configuration from wizard
#' @param output_path Path where launch script will be written
#'
#' @return List with success status
#'
#' @details
#' The script changes to the study directory before calling
#' `launch_zzedc()`, which reads `config.yml` from the working directory;
#' without that, running the script from anywhere else created a new
#' default study there instead. For a DuckDB study it stops with
#' instructions if `DB_ENCRYPTION_KEY` is not set, rather than letting the
#' application refuse later.
#'
#' @keywords internal
#' @export
create_launch_script <- function(config_list, output_path) {

  tryCatch({
    study_dir <- normalizePath(dirname(output_path), winslash = "/", mustWork = FALSE)
    key_check <- if (identical(config_list$db_backend, "duckdb")) {
      c(
        "# The study database is encrypted; its key is not stored in the project.",
        "if (!nzchar(Sys.getenv('DB_ENCRYPTION_KEY'))) {",
        "  stop('Set DB_ENCRYPTION_KEY to this study\\'s database encryption key ',",
        "       '(for example in ~/.Renviron or from your secrets manager) ',",
        "       'before launching.', call. = FALSE)",
        "}",
        ""
      )
    }

    lines <- c(
      "#!/usr/bin/env Rscript",
      paste0("# Launch script for ", config_list$study_name),
      "# Auto-generated by Setup Wizard",
      "",
      "# launch_zzedc() reads config.yml from the working directory.",
      paste0("setwd('", study_dir, "')"),
      "",
      "# Set environment variables",
      paste0("Sys.setenv(ZZEDC_SALT = '", config_list$security_salt, "')"),
      "",
      key_check,
      "library(zzedc)",
      "library(shiny)",
      "",
      "cat('\\n')",
      "cat('========================================\\n')",
      paste0("cat('Launching ZZedc - ", gsub("'", "\\\\'", config_list$study_name), "\\n')"),
      paste0("cat('Protocol: ", gsub("'", "\\\\'", config_list$protocol_id), "\\n')"),
      "cat('========================================\\n')",
      "cat('\\n')",
      "cat('Opening browser to http://localhost:3838\\n')",
      "cat('\\n')",
      "",
      "launch_zzedc(",
      "  host = '127.0.0.1',",
      "  port = 3838,",
      "  launch.browser = TRUE",
      ")"
    )

    writeLines(lines, output_path)

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

  # Step 2: Create database, on the backend chosen in the wizard, through
  # the same adapter configuration the application builds from the
  # config.yml written in Step 3. Before 2026-11-10 this always created
  # SQLite at data/zzedc.db.
  adapter_config <- wizard_adapter_config(config_list, base_path)
  backend <- adapter_config$db_backend
  db_path <- app_database_path(adapter_config)

  if (backend == "duckdb" && isTRUE(config_list$install_extensions %||% TRUE)) {
    installed <- tryCatch(
      install_duckdb_extensions(adapter_config$duckdb$extension_directory),
      error = function(e) e
    )
    results$steps$duckdb_extensions <- list(
      success = !inherits(installed, "error") && all(installed$loads_offline),
      message = if (inherits(installed, "error")) conditionMessage(installed) else
        "DuckDB extensions installed for offline use"
    )
  }

  # When the caller chose a security profile (the browser wizard always
  # does), the database is created under it, the profile the study will
  # run under. When it did not, creation follows the session's profile
  # as before; config.yml still records 'regulated', and the summary
  # below says when that will refuse to start.
  if (!is.null(config_list$security_profile)) {
    old_profile <- options(zzedc.security_profile = config_list$security_profile)
    on.exit(options(old_profile), add = TRUE)
  }
  db_result <- create_wizard_database(config_list, adapter_config = adapter_config)
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
    "ZZedc setup complete!\nLocation: %s\nDatabase: %s (%s)\nLaunch: Rscript %s",
    base_path,
    if (is.na(db_path)) paste(backend, "server") else db_path,
    backend,
    script_path
  )

  # Say now, not at first launch, when storage will not satisfy the
  # profile written to config.yml.
  profile <- config_list$security_profile %||% "regulated"
  results$database_encrypted <- if (backend == "sqlite") {
    isTRUE(sqlite_file_is_encrypted(db_path))
  } else if (backend == "duckdb") {
    isTRUE(verify_database_encryption(
      db_path, key = adapter_config$duckdb$encryption_key,
      adapter = create_db_adapter(adapter_config)
    )$encrypted)
  } else {
    NA
  }
  if (!isTRUE(results$database_encrypted) && profile == "regulated") {
    results$summary <- paste0(
      results$summary,
      "\n\nNOTE: The database is not verified as encrypted at rest, and ",
      "config.yml sets security.profile to 'regulated', which will refuse ",
      "to start. Use the DuckDB backend with an encryption key, or set ",
      "security.profile to 'standard' if this study does not require ",
      "encryption at rest."
    )
  }
  if (backend == "duckdb") {
    results$summary <- paste0(
      results$summary,
      "\n\nBefore each launch, set DB_ENCRYPTION_KEY to the encryption key ",
      "shown in the wizard (it is not stored in the project)."
    )
  }

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

    mysql = ,
    mariadb = {
      if (is.null(server_config)) {
        stop("MySQL backend requires server_config")
      }
      list(
        db_backend = backend,
        mysql = list(
          host = server_config$host %||% "localhost",
          port = server_config$port %||% 3306L,
          name = server_config$name %||% server_config$database,
          user = server_config$user,
          password = server_config$password,
          ssl_mode = server_config$ssl_mode
        )
      )
    },

    stop("Unsupported backend: ", backend,
         "\nSupported: sqlite, duckdb, postgresql, clickhouse, mysql, mariadb")
  )
}


#' Create Core Database Tables
#'
#' Creates all required tables for ZZedc using dialect-appropriate DDL.
#'
#' @param conn Database connection
#' @param dialect Dialect object from adapter
#' @param backend Backend name for engine-specific syntax
#' @param adapter DatabaseAdapter instance `conn` was created from.
#'   Required for the `edc_roles.role_id` auto-increment column,
#'   which goes through `adapter$auto_increment_column()` /
#'   `adapter$prepare_auto_increment()` instead of the raw
#'   `dialect$auto_increment` string, because DuckDB needs a
#'   companion `CREATE SEQUENCE` that only those methods know how to
#'   name and create (see
#'   `docs/db-adapter-remediation-plan-2026-11-07.md` Phase B).
#'
#' @return Invisible NULL
#'
#' @keywords internal
create_core_tables <- function(conn, dialect, backend, adapter) {

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
        must_change_password %s DEFAULT %s,
        failed_login_attempts %s DEFAULT 0,
        locked_at %s,
        password_changed_date %s,
        last_login %s,
        created_date %s,
        created_by %s,
        modified_date %s,
        modified_by %s
      ) ENGINE = MergeTree() ORDER BY user_id
    ", text_type, text_type, text_type, text_type, text_type,
       text_type, text_type, bool_type, bool_default_true,
       bool_type, bool_default_false, int_type, ts_type, ts_type,
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
        must_change_password %s DEFAULT %s,
        failed_login_attempts %s DEFAULT 0,
        locked_at %s,
        password_changed_date %s,
        last_login %s,
        created_date %s DEFAULT CURRENT_TIMESTAMP,
        created_by %s,
        modified_date %s,
        modified_by %s
      )
    ", text_type, text_type, text_type, text_type, text_type,
       text_type, text_type, bool_type, bool_default_true,
       bool_type, bool_default_false, int_type, ts_type, ts_type,
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
    adapter$prepare_auto_increment(conn, "edc_roles", "role_id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS edc_roles (
        role_id %s,
        role_name %s UNIQUE NOT NULL,
        description %s,
        permissions %s,
        created_date %s DEFAULT CURRENT_TIMESTAMP
      )
    ", adapter$auto_increment_column("edc_roles", "role_id"),
       text_type, text_type, text_type, ts_type))
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


#' Adapter Configuration for a Wizard-created Study (internal)
#'
#' Builds the flat `database:` settings the wizard collected and passes
#' them through `app_database_config()`, the same translation the
#' application applies to the `config.yml` the wizard writes, so the
#' database is created where the application will look for it.
#'
#' @param config_list Wizard configuration. Uses `db_backend` (default
#'   `"sqlite"`), `db_encryption_key` (DuckDB), and `db_settings` (a list
#'   with `host`, `port`, `name`, `user`, `ssl` for server backends; the
#'   password is read from `ZZEDC_DB_PASSWORD`).
#' @param base_path Study directory.
#' @return A configuration list for `create_db_adapter()`.
#' @keywords internal
wizard_adapter_config <- function(config_list, base_path) {
  backend <- config_list$db_backend %||% "sqlite"
  s <- config_list$db_settings %||% list()
  flat <- switch(
    backend,
    sqlite = list(backend = "sqlite", path = "data/zzedc.db"),
    duckdb = list(backend = "duckdb", path = "data/zzedc.duckdb",
                  encryption_key = config_list$db_encryption_key,
                  extension_directory = "duckdb_extensions"),
    postgresql = list(backend = "postgresql", host = s$host, port = s$port,
                      name = s$name, user = s$user,
                      password = Sys.getenv("ZZEDC_DB_PASSWORD"),
                      sslmode = s$ssl %||% "verify-full"),
    mysql = list(backend = "mysql", host = s$host, port = s$port,
                 name = s$name, user = s$user,
                 password = Sys.getenv("ZZEDC_DB_PASSWORD"),
                 ssl_mode = s$ssl %||% "VERIFY_IDENTITY"),
    stop("Unsupported database backend: ", backend, call. = FALSE)
  )
  flat$pool_size <- 5
  app_database_config(list(database = flat), base_path)
}
