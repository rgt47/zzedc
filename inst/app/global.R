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

  # Google Sheets integration
  "googlesheets4"
)

# Note: 'config' package is NOT in the list above.
# We use config::get() with explicit file path to avoid the package's
# automatic config.yml search which fails when running from installed app dir.

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
# Check for config in: 1) ZZEDC_CONFIG env var, 2) original working dir, 3) fallback
cfg <- NULL
if (requireNamespace("config", quietly = TRUE)) {
  config_path <- Sys.getenv("ZZEDC_CONFIG_PATH", "")

  if (config_path != "" && file.exists(config_path)) {
    cfg <- config::get(file = config_path)
    message("Loaded config from: ", config_path)
  }
}

# Fallback configuration if no config file found
if (is.null(cfg)) {
  message("Using default configuration (no config.yml found)")
  cfg <- list(
    database = list(path = "data/zzedc.db", pool_size = 5),
    auth = list(max_failed_attempts = 3, session_timeout_minutes = 30),
    app = list(name = "ZZedc - Electronic Data Capture", debug = TRUE)
  )
}

# Get working directory (where user launched from)
work_dir <- Sys.getenv("ZZEDC_WORK_DIR", getwd())

# Resolve database path relative to working directory
db_path <- cfg$database$path
if (!grepl("^/|^[A-Za-z]:", db_path)) {
  # Relative path - make it relative to work_dir
  db_path <- file.path(work_dir, db_path)
}

# Ensure data directory exists
db_dir <- dirname(db_path)
if (!dir.exists(db_dir)) {
  dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
  message("Created database directory: ", db_dir)
}

# Database connection pool (if pool package available)
if (requireNamespace("pool", quietly = TRUE) && requireNamespace("RSQLite", quietly = TRUE)) {
  db_pool <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = db_path,
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

# Modules and utilities are now part of the zzedc package namespace
# They are loaded automatically when library(zzedc) is called
# No need to source them separately here

# Verify zzedc package is loaded (provides all modules and utilities)
if (!requireNamespace("zzedc", quietly = TRUE)) {
  stop("zzedc package must be loaded. Run: library(zzedc)")
}

# All Shiny modules (auth_module, home_module, etc.) are defined in the zzedc
# package namespace and loaded via library(zzedc) before runApp() is called.
# No manual sourcing required.

requ <- function(label) {
  tagList(span("*", class = "req_star"), label)
}

#siteslist = dget(".forms/sitelist.R")

data_dir <- file.path(".dat")


