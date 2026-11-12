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
    auth = list(max_failed_attempts = 3, lockout_duration_minutes = 15,
                password_expiry_days = 90, session_timeout_minutes = 30),
    app = list(name = "ZZedc - Electronic Data Capture", debug = TRUE)
  )
}

# One password-salt rule for the whole application: package modules
# (user management) read it from this option, and the login, the
# change-password form, and the launcher compute it from the same
# configuration (zzedc::resolve_auth_salt()).
options(zzedc.auth_salt = zzedc::resolve_auth_salt(cfg))

# Get working directory (where user launched from)
work_dir <- Sys.getenv("ZZEDC_WORK_DIR", getwd())

# Build the database configuration from config.yml's `database:`
# section (backend: sqlite, duckdb, postgresql, mysql; default
# sqlite). Until 2026-11-10 this file ignored the backend and always
# opened SQLite with RSQLite, so the app could not use any other
# backend, nor any encryption a backend provides.
db_config <- zzedc::app_database_config(cfg, work_dir)

# A restore requested from the Backup tab is applied here, before any
# connection to the database is opened (see ?zzedc::database_restore).
zzedc::apply_pending_restore(db_config)

# Cache the adapter, so package functions the app calls
# (connect_encrypted_db() and everything built on it) open the same
# backend and the same file as the pool below.
db_adapter <- zzedc::get_db_adapter(config = db_config, force_new = TRUE)

# File path for file backends (SQLite, DuckDB); NA for server backends.
db_path <- zzedc::app_database_path(db_config)
if (!is.na(db_path) && !identical(db_path, ":memory:")) {
  db_dir <- dirname(db_path)
  if (!dir.exists(db_dir)) {
    dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
    message("Created database directory: ", db_dir)
  }
}

# Apply the security profile before any connection is opened. Under
# the 'regulated' profile this stops the app when the database cannot
# be shown to be encrypted at rest.
storage_state <- zzedc::check_storage_encryption(adapter = db_adapter,
                                                 config_profile = cfg$security$profile)

# The database key must come from the environment or a secrets
# manager, not be written into config.yml ('regulated' refuses it).
zzedc::check_key_custody(cfg)

# Connection pool from the adapter: applies the backend's encryption
# (DuckDB ENCRYPTION_KEY, SQLCipher key) and extension settings.
db_pool <- db_adapter$pool()

# Audit tables, and the triggers that make them append-only (on
# SQLite, PostgreSQL, MySQL/MariaDB; DuckDB has no triggers). This also
# installs the triggers on databases created before they existed.
audit_protection <- local({
  conn <- pool::poolCheckout(db_pool)
  on.exit(pool::poolReturn(conn))
  zzedc:::.ensure_audit_tables(conn)
  zzedc::audit_protection_status(conn)
})

# Record in the audit log that the database key was loaded, and from
# where (never the key itself).
key_source <- zzedc:::.key_source_description(cfg)
if (!is.null(key_source)) zzedc::log_key_access(key_source)

# Record the security configuration actually in force (profile,
# backend, at-rest mechanism, TLS, key source, extensions, HTTPS) as a
# COMPLIANCE_CHECK audit event: evidence for the validation report.
compliance_check <- zzedc::compliance_self_check(cfg, storage_state, db_config,
                                                 audit_protection = audit_protection)
zzedc::record_compliance_check(compliance_check)

# External checkpoint of the audit chain (audit.checkpoint_dir in
# config.yml; key in ZZEDC_AUDIT_CHECKPOINT_KEY). Without checkpoints,
# someone able to write to the database could rewrite the trail and
# recompute every hash undetected. See ?audit_protection.
checkpoint_dir <- cfg$audit$checkpoint_dir
if (!is.null(checkpoint_dir) && nzchar(checkpoint_dir)) {
  local({
    conn <- pool::poolCheckout(db_pool)
    on.exit(pool::poolReturn(conn))
    zzedc::audit_checkpoint(checkpoint_dir, conn = conn,
                            database = if (is.na(db_path)) db_config$db_backend else basename(db_path))
  })
} else if (zzedc::get_security_profile() == "regulated") {
  warning("No audit.checkpoint_dir is configured, so the audit trail is ",
          "not checkpointed outside the database (see ?audit_protection).",
          call. = FALSE, immediate. = TRUE)
}

# Verify database connection on startup
tryCatch({
  test_conn <- pool::poolCheckout(db_pool)
  pool::poolReturn(test_conn)
  message("Database pool initialized (backend: ", db_config$db_backend,
          ", max pool size: ", cfg$database$pool_size %||% 5, ")")
}, error = function(e) {
  warning("Database pool initialization error: ", e$message)
})

onStop(function() {
  pool::poolClose(db_pool)
})

trial_name <- "trial0"

# `user_session`/`user_input` (authenticated, username, full_name,
# role, ...) is deliberately NOT created here. global.R runs once per
# R process, shared by every concurrent browser session -- a
# reactiveValues object created here would be that same single
# shared object for every session, not one per logged-in user.
# Confirmed empirically: a brand-new browser tab landed on the EDC
# tab already "logged in" as whoever had last authenticated in any
# other tab, with no login step of its own. It is created fresh
# inside server() instead (inst/app/server.R), once per session,
# before auth.R/edc.R and the rest of the per-session chain are
# sourced, so each session gets its own authentication state.

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


