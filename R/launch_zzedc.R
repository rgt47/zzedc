#' Launch the ZZedc Shiny Application
#'
#' This function launches the interactive 'Shiny' application for electronic
#' data capture (EDC) in clinical trials.
#'
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}
#' @param launch.browser Logical, whether to launch the app in browser. 
#'   Default is \code{TRUE}.
#' @param host Character string of IP address to listen on. Default is "127.0.0.1".
#' @param port Integer specifying the port to listen on. Default is \code{NULL}
#'   (random port).
#'
#' @return No return value, launches the Shiny application
#' 
#' @details 
#' The application provides comprehensive electronic data capture for clinical 
#' trials with the following features:
#' \itemize{
#'   \item Secure user authentication with role-based access
#'   \item Data entry forms with validation and quality control
#'   \item Comprehensive reporting system (basic, quality, statistical)
#'   \item Advanced data exploration and visualization tools
#'   \item Flexible export capabilities with multiple formats
#'   \item Modern responsive design using Bootstrap 5 via bslib
#' }
#'
#' @examples
#' \dontrun{
#' # Launch the application
#' launch_zzedc()
#' 
#' # Launch on specific port
#' launch_zzedc(port = 3838)
#' 
#' # Launch without opening browser
#' launch_zzedc(launch.browser = FALSE)
#' }
#'
#' @export
#' @importFrom shiny runApp
launch_zzedc <- function(..., launch.browser = TRUE, host = "127.0.0.1", port = NULL) {

  # Ensure required directories exist in working directory
  if (!dir.exists("data")) {
    dir.create("data", showWarnings = FALSE)
    message("Created 'data/' directory")
  }

  if (!dir.exists("credentials")) {
    dir.create("credentials", showWarnings = FALSE)
    message("Created 'credentials/' directory")
  }

  # Scaffold the EDC `forms/` directory on first run. The three
  # files (blfieldlist.R, renderpanels.R, save.R) are study-
  # specific and live in the working directory rather than the
  # package. Ship demonstration stubs in inst/extdata/forms/ so a
  # bare `launch_zzedc()` call lands a working EDC tab; users
  # then replace the stubs with their study's actual scaffolding.
  if (!dir.exists("forms")) {
    forms_src <- system.file("extdata", "forms", package = "zzedc")
    if (nzchar(forms_src) && dir.exists(forms_src)) {
      dir.create("forms", showWarnings = FALSE)
      file.copy(
        from = list.files(forms_src, full.names = TRUE),
        to   = "forms",
        overwrite = FALSE
      )
      message(
        "Created 'forms/' directory with demonstration stubs.\n",
        "  Replace forms/blfieldlist.R, forms/renderpanels.R, ",
        "and forms/save.R\n  with your study's case-report-form ",
        "scaffolding."
      )
    }
  }

 # Check for config.yml and create default if missing
  if (!file.exists("config.yml")) {
    message("\n")
    message("No config.yml found in current directory: ", getwd())
    message("\n")

    # Check if running interactively
    if (interactive()) {
      response <- readline("Create default config.yml? (y/n): ")
      if (tolower(substr(response, 1, 1)) == "y") {
        create_default_config()
        message("Created config.yml with default settings")
      } else {
        stop(
          "config.yml is required. Create one manually or run launch_zzedc() ",
          "again and choose 'y' to create a default.",
          call. = FALSE
        )
      }
    } else {
      # Non-interactive: create default automatically
      create_default_config()
      message("Created config.yml with default settings (non-interactive mode)")
    }
  }

  # Find the app directory from installed package
  app_dir <- system.file("app", package = "zzedc")

  if (app_dir == "") {
    stop(
      "Cannot find zzedc app directory. ",
      "Please reinstall the package with: devtools::install()",
      call. = FALSE
    )
  }

  # Pass config path and working directory to the app via environment
  # variables. Save prior values and restore them when the function
  # exits so the caller's environment is left unchanged (CRAN policy:
  # packages must not modify the user's environment without restoration).
  prior_config <- Sys.getenv("ZZEDC_CONFIG_PATH", unset = NA)
  prior_workdir <- Sys.getenv("ZZEDC_WORK_DIR", unset = NA)
  on.exit({
    if (is.na(prior_config)) {
      Sys.unsetenv("ZZEDC_CONFIG_PATH")
    } else {
      Sys.setenv(ZZEDC_CONFIG_PATH = prior_config)
    }
    if (is.na(prior_workdir)) {
      Sys.unsetenv("ZZEDC_WORK_DIR")
    } else {
      Sys.setenv(ZZEDC_WORK_DIR = prior_workdir)
    }
  }, add = TRUE)

  config_path <- normalizePath("config.yml", mustWork = FALSE)
  if (file.exists(config_path)) {
    Sys.setenv(ZZEDC_CONFIG_PATH = config_path)
    message("Using config: ", config_path)
  }

  Sys.setenv(ZZEDC_WORK_DIR = normalizePath(getwd()))

  # Check if database needs initialization
  cfg <- config::get(file = config_path)
  db_path <- cfg$database$path
  if (!grepl("^/|^[A-Za-z]:", db_path)) {
    db_path <- file.path(getwd(), db_path)
  }

  if (!file.exists(db_path) || !check_database_initialized(db_path)) {
    message("\n")
    message("Database not initialized: ", db_path)
    message("\n")

    if (interactive()) {
      response <- readline("Initialize database with default admin user? (y/n): ")
      if (tolower(substr(response, 1, 1)) == "y") {
        init_result <- initialize_default_database(db_path)
        if (init_result$success) {
          message("\nDatabase initialized successfully!")
          message("Login credentials:")
          message("  Username: admin")
          message("  Password: admin123\n")
          message("IMPORTANT: Change this password after first login.\n")
        } else {
          stop("Database initialization failed: ", init_result$message, call. = FALSE)
        }
      } else {
        message("\nTo initialize manually, run:")
        message("  zzedc::initialize_default_database('", db_path, "')")
        message("\nOr use create_wizard_database() for custom setup.\n")
        stop("Database must be initialized before launching.", call. = FALSE)
      }
    } else {
      # Non-interactive: initialize automatically
      init_result <- initialize_default_database(db_path)
      if (init_result$success) {
        message("Database initialized (non-interactive mode)")
        message("Default credentials - Username: admin, Password: admin123")
      } else {
        stop("Database initialization failed: ", init_result$message, call. = FALSE)
      }
    }
  }

  # Run the app
  shiny::runApp(
    appDir = app_dir,
    launch.browser = launch.browser,
    host = host,
    port = port,
    ...
  )
}

#' Check if database is initialized
#'
#' @param db_path Path to the database file
#' @return TRUE if database has required tables, FALSE otherwise
#' @keywords internal
check_database_initialized <- function(db_path) {
  if (!file.exists(db_path)) {
    return(FALSE)
  }


  tryCatch({
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    tables <- DBI::dbListTables(conn)
    required_tables <- c("edc_users", "study_info")

    all(required_tables %in% tables)
  }, error = function(e) {
    FALSE
  })
}

#' Initialize database with default configuration
#'
#' Creates a minimal database with an admin user for first-time setup.
#'
#' @param db_path Path where database will be created
#' @return List with success status and message
#' @keywords internal
#' @export
initialize_default_database <- function(db_path) {
  config <- list(
    study_name = "New Study",
    protocol_id = "PROTO-001",
    pi_name = "Principal Investigator",
    pi_email = "pi@example.com",
    study_phase = "Setup",
    target_enrollment = 100,
    admin_username = "admin",
    admin_password = "admin123",
    admin_fullname = "System Administrator",
    admin_email = "admin@example.com",
    security_salt = DEFAULT_SECURITY_SALT
  )

  create_wizard_database(config, db_path = db_path)
}

# Default salt used for password hashing when no custom salt is configured
# This should be overridden in production environments
DEFAULT_SECURITY_SALT <- "zzedc_default_salt_change_in_production_2024"

#' Create default configuration file
#'
#' Creates a minimal config.yml in the current working directory.
#'
#' @param path Path to create config file. Default is "config.yml".
#'
#' @return Invisibly returns the path to the created file.
#'
#' @examples
#' # Write a default configuration to a temporary file (the
#' # production call writes to the current working directory).
#' tmp_config <- tempfile(fileext = ".yml")
#' create_default_config(path = tmp_config)
#' file.exists(tmp_config)
#' @export
create_default_config <- function(path = "config.yml") {
  config_content <- sprintf('default:
  database:
    path: "data/zzedc.db"
    pool_size: 5

  auth:
    max_failed_attempts: 3
    session_timeout_minutes: 30
    default_salt: "%s"

  app:
    name: "ZZedc - Electronic Data Capture"
    version: "1.0.0"
    debug: true

  ui:
    theme: "flatly"
', DEFAULT_SECURITY_SALT)
  writeLines(config_content, path)
  invisible(path)
}
