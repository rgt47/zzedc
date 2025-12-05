# Centralized package loading for entire application
required_packages <- c(
  # Core Shiny
  "shiny",
  "shinyjs",
  "shinyalert",

  # Modern UI
  "bslib",
  "bsicons",

  # Data handling
  "DT",
  "dplyr",
  "tibble",  # For audit logging and data structures
  "RSQLite",
  "pool",
  "rlang",   # For modern ggplot2 syntax

  # Visualization
  "ggplot2",
  "plotly",

  # Utilities
  "digest",
  "jsonlite",
  "lubridate",
  "stringr",
  "httr",

  # Configuration
  "config",

  # Google Sheets integration
  "googlesheets4"
)

# Load packages with error handling
missing_packages <- c()
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    missing_packages <- c(missing_packages, pkg)
    message("Warning: Package '", pkg, "' not available")
  } else {
    library(pkg, character.only = TRUE, quietly = TRUE)
  }
}

# Report missing packages but continue
if (length(missing_packages) > 0) {
  message("Missing packages: ", paste(missing_packages, collapse = ", "))
  message("Install with: install.packages(c('", paste(missing_packages, collapse = "', '"), "'))")
}

# Initialize shinyjs if available
if ("shinyjs" %in% names(sessionInfo()$otherPkgs) || requireNamespace("shinyjs", quietly = TRUE)) {
  shinyjs::useShinyjs()
}

# Load configuration
if (requireNamespace("config", quietly = TRUE)) {
  cfg <- config::get()
} else {
  # Fallback configuration
  cfg <- list(
    database = list(path = "data/memory001_study.db", pool_size = 5)
  )
}

# Database connection pool (if pool package available)
if (requireNamespace("pool", quietly = TRUE) && requireNamespace("RSQLite", quietly = TRUE)) {
  db_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = cfg$database$path,
    minSize = 1,
    maxSize = cfg$database$pool_size
  )

  # Verify database connection on startup
  tryCatch({
    test_conn <- pool::poolCheckout(db_pool)
    pool::poolReturn(test_conn)
    message("✓ Database pool initialized successfully (pool_size: ", cfg$database$pool_size, ")")
  }, error = function(e) {
    warning("Database pool initialization error: ", e$message)
  })

  # Ensure pool is closed when app stops
  onStop(function() {
    pool::poolClose(db_pool)
  })
} else {
  # Fallback: simple connection function
  db_pool <- NULL
  message("Pool package not available - using direct database connections")
}

trial_name <- "trial0"

# Consolidated session state management
# Single source of truth for all authenticated user information
user_session <- reactiveValues(
  # Authentication state
  authenticated = FALSE,
  authentication_timestamp = NULL,

  # User identity
  user_id = NULL,
  username = NULL,
  full_name = NULL,
  role = NULL,
  site_id = NULL,

  # Session tracking
  last_activity = Sys.time(),
  session_start = NULL
)

# Legacy name for backward compatibility (deprecated - use user_session instead)
# TODO: Refactor references from user_input to user_session
user_input <- user_session

# Load application modules at startup (before server definition)
# Modules must be loaded explicitly, not dynamically in server() for better error handling
module_files <- c(
  "R/modules/auth_module.R",
  "R/modules/home_module.R",
  "R/modules/instrument_import_module.R",
  "R/modules/quality_dashboard_module.R",
  "R/modules/data_module.R",
  "R/modules/privacy_module.R",
  "R/modules/cfr_compliance_module.R"
)

# Load utility service modules
utility_files <- c(
  "R/validation_utils.R",
  "R/audit_logger.R",
  "R/session_timeout.R",
  "R/error_handling.R",
  "R/form_validators.R",
  "R/export_service.R",
  "R/data_pagination.R",
  "R/instrument_library.R"
)

# Load utility files with explicit error handling
for (utility_file in utility_files) {
  if (file.exists(utility_file)) {
    tryCatch({
      source(utility_file, local = FALSE)  # Load into global environment
      utility_name <- tools::file_path_sans_ext(basename(utility_file))
      message("✓ Loaded utility: ", utility_name)
    }, error = function(e) {
      warning("Failed to load utility '", utility_file, "': ", e$message)
    })
  } else {
    message("ℹ Utility not found: ", utility_file, " (optional)")
  }
}

# Load each module with explicit error handling
modules_loaded <- list()
for (module_file in module_files) {
  if (file.exists(module_file)) {
    tryCatch({
      source(module_file, local = FALSE)  # Load into global environment
      module_name <- tools::file_path_sans_ext(basename(module_file))
      modules_loaded[[module_name]] <- TRUE
      message("✓ Loaded module: ", module_name)
    }, error = function(e) {
      warning("Failed to load module '", module_file, "': ", e$message)
      modules_loaded[[basename(module_file)]] <<- FALSE
    })
  } else {
    message("ℹ Module not found: ", module_file, " (optional)")
  }
}

# Verify critical modules are loaded
required_modules <- c("auth_module", "home_module")
missing_modules <- required_modules[which(!required_modules %in% names(modules_loaded))]
if (length(missing_modules) > 0) {
  stop("Critical modules not loaded: ", paste(missing_modules, collapse = ", "))
}

requ <- function(label) {
  tagList(span("*", class = "req_star"), label)
}

#siteslist = dget(".forms/sitelist.R")

data_dir <- file.path(".dat")


