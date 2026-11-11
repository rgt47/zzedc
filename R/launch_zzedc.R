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
#' @param backend Database backend for a new study (`"sqlite"`, `"duckdb"`,
#'   `"postgresql"`, or `"mysql"`; see `describe_backends()`). Used only
#'   when the working directory has no `config.yml`. When `NULL` in an
#'   interactive session, a menu compares the backends and asks; when
#'   `NULL` otherwise, SQLite is used.
#' @param profile Security profile for a new study's `config.yml`
#'   (default `"regulated"`; see `resolve_security_profile()`). Used only
#'   when there is no `config.yml`.
#' @param setup Logical. `TRUE` opens the setup wizard in a browser to
#'   create a new study (`launch_setup_wizard()`) instead of launching
#'   the application; the wizard can launch the application when it
#'   finishes.
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
#'
#' # New study on encrypted DuckDB (needs DB_ENCRYPTION_KEY set, or an
#' # interactive session, which generates one)
#' launch_zzedc(backend = "duckdb")
#'
#' # Create a new study with the setup wizard
#' launch_zzedc(setup = TRUE)
#' }
#'
#' @export
#' @importFrom shiny runApp
launch_zzedc <- function(..., launch.browser = TRUE, host = "127.0.0.1", port = NULL,
                         backend = NULL, profile = "regulated", setup = FALSE) {

  if (isTRUE(setup)) {
    outcome <- launch_setup_wizard(base_path = getwd(),
                                   launch.browser = launch.browser,
                                   host = host, port = port,
                                   show_choice = FALSE)
    if (!identical(outcome, "launch")) {
      return(invisible(outcome))
    }
  }

  # inst/app/*.R files (e.g. edc.R's renderPanel(blfieldlist) call)
  # reference several zzedc-exported functions unqualified, relying
  # on zzedc being attached to the search path. zzedc::launch_zzedc()
  # only loads the namespace, it does not attach it, so those calls
  # fail with "could not find function" unless the caller remembered
  # to library(zzedc) first. Attach it here so launch_zzedc() works
  # the same way regardless of how it was called.
  if (!"package:zzedc" %in% search()) {
    suppressPackageStartupMessages(
      library("zzedc", quietly = TRUE)
    )
  }

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

  # Check for config.yml and create one for the chosen backend if missing
  if (!file.exists("config.yml")) {
    message("\n")
    message("No config.yml found in current directory: ", getwd())
    message("\n")

    if (is.null(backend) && interactive()) {
      choice <- .choose_backend_interactive()
      if (identical(choice, "wizard")) {
        return(invisible(launch_zzedc(..., launch.browser = launch.browser,
                                      host = host, port = port, setup = TRUE)))
      }
      backend <- choice
      if (backend == "sqlite" && profile == "regulated" && !sqlite_cipher_available()) {
        message(
          "\nSQLite cannot be encrypted with the standard CRAN build of RSQLite, ",
          "and the 'regulated' security profile refuses unencrypted storage."
        )
        answer <- readline(
          "Does this study need its stored data encrypted (regulated data)? (y/n): "
        )
        if (tolower(substr(answer, 1, 1)) == "y") {
          stop("Choose DuckDB for encrypted storage: run launch_zzedc() again and ",
               "pick DuckDB, or launch_zzedc(backend = \"duckdb\").", call. = FALSE)
        }
        profile <- "standard"
      }
    }
    backend <- backend %||% "sqlite"

    # Prepare first (key, extensions), so that a failure leaves no
    # half-created study behind.
    .prepare_new_backend(backend)
    create_default_config(backend = backend, profile = profile)
    message("Created config.yml for backend '", backend, "' with security profile '",
            profile, "'")
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

  # Check if database needs initialization. The configured backend
  # (config.yml database.backend; SQLite by default) is used for every
  # step below, the same one the application's pool will open
  # (inst/app/global.R), so initialization and migrations reach the
  # study database whatever backend it is on.
  cfg <- config::get(file = config_path)
  db_config <- app_database_config(cfg, getwd())
  db_path <- app_database_path(db_config)
  db_label <- if (is.na(db_path)) paste(db_config$db_backend, "server") else db_path

  # Apply a restore staged from the Backup tab before anything opens the
  # database (see ?database_restore).
  apply_pending_restore(db_config)

  # Apply the security profile before touching the database, so that a
  # configuration the profile refuses is reported as that, not as an
  # uninitialized database followed by a failed initialization.
  # check_storage_encryption() fixes the profile for the R session; the
  # caller's option is restored when this function returns.
  prior_profile <- getOption("zzedc.security_profile")
  on.exit(options(zzedc.security_profile = prior_profile), add = TRUE)
  check_storage_encryption(adapter = create_db_adapter(db_config),
                           config_profile = cfg$security$profile)

  if (!check_database_initialized(db_path, adapter_config = db_config)) {
    message("\n")
    message("Database not initialized: ", db_label)
    message("\n")

    if (interactive()) {
      response <- readline("Initialize database with default admin user? (y/n): ")
      if (tolower(substr(response, 1, 1)) == "y") {
        init_result <- initialize_default_database(db_path, adapter_config = db_config,
                                                   salt = resolve_auth_salt(cfg))
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
        message("  zzedc::initialize_default_database('", db_label, "')")
        message("\nOr use create_wizard_database() for custom setup.\n")
        stop("Database must be initialized before launching.", call. = FALSE)
      }
    } else {
      # Non-interactive: initialize automatically. The administrator's
      # password is hashed with the salt the login will use; it used
      # the built-in salt, so the default account could not log in
      # whenever the configuration's salt variable (ZZEDC_SALT) was set.
      init_result <- initialize_default_database(db_path, adapter_config = db_config,
                                                 salt = resolve_auth_salt(cfg))
      if (init_result$success) {
        message("Database initialized (non-interactive mode)")
        message("Default credentials - Username: admin, Password: admin123")
      } else {
        stop("Database initialization failed: ", init_result$message, call. = FALSE)
      }
    }
  }

  # `data_entries` is normally created lazily, on first submission
  # (ensure_data_entries_table(), called from save_crf_entry()). A
  # database that has never had a submission -- including one just
  # rebuilt from setup_zzedc_from_gsheets(overwrite = TRUE) -- would
  # otherwise reach the app with no `data_entries` table at all.
  # get_data_entries() (R/edc_reports.R) now tolerates that itself,
  # but several session-start reactives (Reports, Data Explorer, the
  # EDC tab's own tracking-ID prefill) call it before anyone has
  # necessarily submitted anything, so guaranteeing the table exists
  # here -- once, before the app starts -- is cheap insurance against
  # relying on every call site's own defensiveness.
  #
  # `edc_users` may exist but predate the `must_change_password`
  # column (any study database provisioned before this feature), and
  # ensure_edc_users_table() both creates the table if missing and
  # migrates an existing one that lacks the column (see its own
  # roxygen for why the migrated default is 0, not 1).
  #
  # §11.10(i) training records: user_training has no CREATE TABLE
  # anywhere else, unlike edc_users/data_entries -- ensuring it here
  # means the Compliance tab's "Record Training" button
  # (R/cfr_compliance_module.R) has somewhere to write to from the
  # very first app launch.
  #
  # These used to open the file with RSQLite directly, whatever the
  # configured backend. One adapter connection now serves all three,
  # and is closed (for DuckDB, the instance shut down) before the
  # application opens its own pool.
  local({
    adapter <- create_db_adapter(db_config)
    on.exit(adapter$shutdown(), add = TRUE)
    conn <- adapter$connect()
    on.exit(adapter$disconnect(conn), add = TRUE, after = FALSE)
    for (step in list(
      list(ensure_data_entries_table, "data_entries table exists"),
      list(ensure_edc_users_table, "edc_users table is current"),
      list(ensure_user_training_table, "user_training table is current")
    )) {
      tryCatch(step[[1]](conn), error = function(e) {
        message("Could not ensure ", step[[2]], ": ", e$message)
      })
    }
  })

  # The hash-chained audit tables (audit_log, audit_events,
  # audit_chain) were never created by the launcher's default
  # initialization, so log_audit_event() and the security events it
  # records (login lockouts, unlocks) failed in every freshly launched
  # deployment. init_audit_logging() is idempotent (CREATE TABLE IF NOT
  # EXISTS) and reaches the study database through the cached adapter,
  # which is set here to the configured backend; the application
  # replaces it with its own adapter when global.R runs.
  local({
    adapter <- get_db_adapter(config = db_config, force_new = TRUE)
    on.exit(adapter$shutdown(), add = TRUE)
    result <- init_audit_logging(db_path = if (is.na(db_path)) NULL else db_path)
    if (!isTRUE(result$success)) {
      message("Could not initialize audit logging tables: ",
              result$error %||% result$message %||% "unknown error")
    }
  })

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
#' @param db_path Path to the database file (SQLite or DuckDB); ignored
#'   for server backends.
#' @param adapter_config Optional configuration for
#'   `create_db_adapter()`. When `NULL`, `db_path` is treated as a
#'   SQLite file.
#' @return TRUE if database has required tables, FALSE otherwise
#' @keywords internal
check_database_initialized <- function(db_path, adapter_config = NULL) {
  if (is.null(adapter_config)) {
    adapter_config <- list(db_backend = "sqlite", sqlite = list(path = db_path))
  }
  if (!is.na(db_path %||% NA) && !file.exists(db_path)) {
    return(FALSE)
  }

  tryCatch({
    adapter <- create_db_adapter(adapter_config)
    on.exit(adapter$shutdown(), add = TRUE)
    conn <- adapter$connect()
    on.exit(adapter$disconnect(conn), add = TRUE, after = FALSE)

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
#' @param adapter_config Optional configuration for
#'   `create_db_adapter()` (see `app_database_config()`); when supplied,
#'   the database is created on that backend, with its encryption
#'   settings.
#' @param salt Password salt for the default administrator. It must be
#'   the salt the application's login will use; `launch_zzedc()` passes
#'   `resolve_auth_salt(cfg)`. Defaults to the package's built-in salt,
#'   which is what a `create_default_config()` configuration resolves to.
#' @return List with success status and message
#' @keywords internal
#' @export
initialize_default_database <- function(db_path, adapter_config = NULL,
                                        salt = DEFAULT_SECURITY_SALT) {
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
    security_salt = salt
  )

  create_wizard_database(config, db_path = db_path, adapter_config = adapter_config)
}

# Default salt used for password hashing when no custom salt is configured
# This should be overridden in production environments
DEFAULT_SECURITY_SALT <- "zzedc_default_salt_change_in_production_2024"

#' Create default configuration file
#'
#' Creates a commented config.yml for the chosen database backend and
#' security profile.
#'
#' @param path Path to create config file. Default is "config.yml".
#' @param backend Database backend: `"sqlite"` (default), `"duckdb"`,
#'   `"postgresql"`, or `"mysql"`. See `describe_backends()`.
#' @param profile Security profile written to the file: `"regulated"`
#'   (default), `"standard"`, or `"development"`. Under `regulated`, a
#'   SQLite database on the standard CRAN build of RSQLite is refused at
#'   startup; DuckDB with an encryption key is the CRAN-only route.
#'
#' @return Invisibly returns the path to the created file.
#'
#' @details
#' Secrets are not written to the file. A DuckDB configuration refers to
#' `${DB_ENCRYPTION_KEY}`, and server configurations to
#' `${ZZEDC_DB_HOST}`, `${ZZEDC_DB_USER}`, and `${ZZEDC_DB_PASSWORD}`,
#' which are read from the environment when the application starts.
#'
#' @examples
#' # Write a default configuration to a temporary file (the
#' # production call writes to the current working directory).
#' tmp_config <- tempfile(fileext = ".yml")
#' create_default_config(path = tmp_config, backend = "duckdb")
#' file.exists(tmp_config)
#' @export
create_default_config <- function(path = "config.yml", backend = "sqlite",
                                  profile = "regulated") {
  backend <- match.arg(backend, names(.backend_catalog))
  profile <- match.arg(profile, .security_profile_levels)
  lines <- c(
    "default:",
    .database_config_yaml(backend),
    "",
    "  auth:",
    "    max_failed_attempts: 3",
    "    lockout_duration_minutes: 15",
    "    password_expiry_days: 90",
    "    session_timeout_minutes: 30",
    sprintf('    default_salt: "%s"', DEFAULT_SECURITY_SALT),
    "",
    .security_config_yaml(profile),
    "",
    "  app:",
    '    name: "ZZedc - Electronic Data Capture"',
    '    version: "1.0.0"',
    "    debug: true",
    "",
    "  ui:",
    '    theme: "flatly"'
  )
  writeLines(lines, path)
  invisible(path)
}
