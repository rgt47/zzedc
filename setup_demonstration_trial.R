#!/usr/bin/env Rscript
# Complete Demonstration Trial Setup Script
# Run this script to set up the entire demonstration trial environment

cat("
============================================================
ZZedc Demonstration Clinical Trial - Complete Setup
============================================================
")

# Get the directory where this script is located
script_dir <- if (interactive()) {

  "."
} else {
  dirname(sys.frame(1)$ofile)
}

demonstration_trial_dir <- file.path(script_dir, "vignettes", "demonstration-trial")

# Check if vignette directory exists
if (!dir.exists(demonstration_trial_dir)) {
 stop("Cannot find vignettes/demonstration-trial directory. ",
       "Please run this script from the zzedc package root directory.")
}

cat("\nStep 1: Checking R dependencies...\n")
required_packages <- c(
 "shiny", "bslib", "bsicons", "shinyjs", "DT",
 "ggplot2", "plotly", "dplyr", "jsonlite", "digest",
  "writexl", "RSQLite", "pool", "config", "lubridate",
  "stringr", "httr", "shinyalert", "googlesheets4",
  "devtools", "R6"
)

missing_packages <- required_packages[
  !sapply(required_packages, requireNamespace, quietly = TRUE)
]

if (length(missing_packages) > 0) {
  cat("Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
  install.packages(missing_packages)
} else {
  cat("All required packages are installed.\n")
}

cat("\nStep 2: Loading zzedc package...\n")
if (!requireNamespace("zzedc", quietly = TRUE)) {
  cat("Installing zzedc package from local source...\n")
  devtools::install(script_dir, quiet = TRUE)
}
library(zzedc)

cat("\nStep 3: Setting up demonstration trial database...\n")
source(file.path(demonstration_trial_dir, "scripts", "01-setup_demonstration_trial.R"))

cat("\nStep 4: Adding test users...\n")
source(file.path(demonstration_trial_dir, "scripts", "02-add_users.R"))

cat("\nStep 5: Verifying setup...\n")
source(file.path(demonstration_trial_dir, "scripts", "03-verify_demonstration_trial.R"))

cat("
============================================================
SUCCESS: Toy trial setup complete!
============================================================

Database location: vignettes/demonstration-trial/data/demonstration_trial.db

Test Credentials:
  Username      | Password    | Role
  ------------- | ----------- | -----------
  admin         | admin123    | Admin
 jane_smith    | jane123     | Coordinator
  bob_johnson   | bob123      | Coordinator
  researcher    | research123 | Researcher

To launch ZZedc with the demonstration trial:

  library(zzedc)
  Sys.setenv(ZZEDC_DB_PATH = 'vignettes/demonstration-trial/data/demonstration_trial.db')
  launch_zzedc()

============================================================
")
