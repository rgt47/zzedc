#' First-Time Detection and Setup Mode
#'
#' Detect if ZZedc is being launched for the first time (not yet configured)
#' and guide user through setup if needed.
#'
#' @keywords internal

#' Check if ZZedc is Already Configured
#'
#' Returns TRUE if database and config files exist
#'
#' @param db_path Path to database file
#' @param config_path Path to config file
#'
#' @return Logical. TRUE if fully configured, FALSE if needs setup
#'
#' @keywords internal
#' @export
is_configured <- function(db_path = "./data/zzedc.db", config_path = "./config.yml") {
  file.exists(db_path) && file.exists(config_path)
}


#' Detect Configuration Status
#'
#' Comprehensive check of setup status
#'
#' @return List with status information
#'
#' @keywords internal
#' @export
detect_setup_status <- function() {
  db_exists <- file.exists("./data/zzedc.db")
  config_exists <- file.exists("./config.yml")
  .env_exists <- file.exists("./.env")

  list(
    db_exists = db_exists,
    config_exists = config_exists,
    env_exists = .env_exists,
    is_configured = db_exists && config_exists,
    needs_setup = !(db_exists && config_exists),
    partially_configured = (db_exists || config_exists) && !(db_exists && config_exists)
  )
}


#' Launch Setup Mode if Needed
#'
#' Checks if ZZedc is configured. If not, shows setup options.
#' Called from app startup to intercept first-time users.
#'
#' @param db_path Path to database file
#' @param config_path Path to config file
#'
#' @return Invisibly returns setup status
#'
#' @keywords internal
#' @export
launch_setup_if_needed <- function(db_path = "./data/zzedc.db",
                                   config_path = "./config.yml") {

  status <- detect_setup_status()

  if (!status$needs_setup) {
    # Already configured, proceed normally
    return(invisible(list(configured = TRUE, setup_needed = FALSE)))
  }

  # Needs setup - this will be handled by app to show setup choice page
  return(invisible(list(configured = FALSE, setup_needed = TRUE, status = status)))
}


#' Get Setup Instructions
#'
#' Returns helpful instructions for completing setup
#'
#' @return Character string with setup instructions
#'
#' @keywords internal
#' @export
get_setup_instructions <- function() {
  instructions <- "
# ZZedc Setup Instructions
# ========================

## Option 1: Interactive Setup (Recommended for Novices)
```r
zzedc::init()
```
This will guide you through a series of prompts to configure your study.
Estimated time: 5 minutes

## Option 2: Config File Setup (Recommended for DevOps/AWS)
```r
zzedc::init(mode = 'config', config_file = 'zzedc_config.yml')
```
First, create a config file using the template:
```bash
cp inst/templates/zzedc_config_template.yml zzedc_config.yml
# Edit zzedc_config.yml with your settings
# Then run the init command above
```

## Option 3: Setup Wizard (In Web Browser)
After running either option above, visit:
http://localhost:3838
and follow the visual setup wizard.
"
  return(instructions)
}
