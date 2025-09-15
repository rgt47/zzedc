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
  "RSQLite",
  "pool",

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

user_input <- reactiveValues(
  authenticated = FALSE,
  authenticated_enroll = FALSE,  # Fixed naming consistency
  valid_credentials = FALSE,
  user_id = NULL,
  username = NULL,
  full_name = NULL,
  role = NULL,
  site_id = NULL
)

requ <- function(label) {
  tagList(span("*", class = "req_star"), label)
}

#siteslist = dget(".forms/sitelist.R")

data_dir <- file.path(".dat")


