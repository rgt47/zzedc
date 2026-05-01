#!/usr/bin/env Rscript
#
# ZZedc Demonstration Trial Complete Setup Script
#
# This script automates the complete setup process for new users:
#   - Installs R dependencies
#   - Installs zzedc package
#   - Creates demonstration trial database with 20 subjects
#   - Adds test users
#   - Verifies the setup
#
# Usage:
#   From the zzedc directory:
#     Rscript setup_demonstration_trial.R
#
#   Or from R:
#     source("setup_demonstration_trial.R")
#

cat("\n")
cat("========================================================\n")
cat("  ZZedc Demonstration Trial - Complete Setup Script\n")
cat("========================================================\n\n")

# Determine script location
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg))))
  }
  for (i in seq_len(sys.nframe())) {
    if (!is.null(sys.frame(i)$ofile)) {
      return(dirname(normalizePath(sys.frame(i)$ofile)))
    }
  }
  if (file.exists("setup_demonstration_trial.R")) {
    return(normalizePath("."))
  }
  stop("Cannot determine script directory. Run from zzedc package root.")
}

zzedc_dir <- get_script_dir()
cat("ZZedc directory:", zzedc_dir, "\n\n")

# Step 1: Check and install R dependencies
cat("Step 1/5: Checking R dependencies...\n")
cat("------------------------------------------------------\n")

required_packages <- c(
 "shiny", "bslib", "bsicons", "shinyjs", "DT",
  "ggplot2", "plotly", "dplyr", "jsonlite", "digest",
  "writexl", "RSQLite", "pool", "config", "lubridate",
  "stringr", "httr", "shinyalert", "googlesheets4",
  "devtools", "DBI"
)

missing_packages <- required_packages[!sapply(required_packages, requireNamespace,
                                               quietly = TRUE)]

if (length(missing_packages) > 0) {
  cat("  Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
  install.packages(missing_packages, repos = "https://cloud.r-project.org",
                   quiet = TRUE)
  cat("  Packages installed.\n")
} else {
  cat("  All dependencies already installed.\n")
}
cat("\n")

# Step 2: Install zzedc
cat("Step 2/4: Installing zzedc...\n")
cat("------------------------------------------------------\n")

cat("  Installing from:", zzedc_dir, "\n")
devtools::install(zzedc_dir, quiet = TRUE, upgrade = "never")
cat("  zzedc installed (version:",
    as.character(packageVersion("zzedc")), ")\n")
cat("\n")

# Step 3: Run demonstration trial setup scripts
cat("Step 3/4: Setting up demonstration trial database...\n")
cat("------------------------------------------------------\n")

demonstration_trial_scripts <- file.path(zzedc_dir, "vignettes", "demonstration-trial", "scripts")

# Run scripts using system() to ensure correct working directory detection
run_script <- function(script_name, description) {
  script_path <- file.path(demonstration_trial_scripts, script_name)
  cat("  ", description, "...\n", sep = "")
  result <- system2("Rscript", args = script_path, stdout = TRUE, stderr = TRUE)
  cat(paste("    ", result, collapse = "\n"), "\n")
  invisible(result)
}

# Setup database
run_script("01-setup_demonstration_trial.R", "Creating database with 20 subjects")

# Add users
run_script("02-add_users.R", "Adding test users")

cat("\n")

# Step 4: Verify setup
cat("Step 4/4: Verifying setup...\n")
cat("------------------------------------------------------\n")
run_script("03-verify_demonstration_trial.R", "Verifying data")

# Final summary
cat("\n")
cat("========================================================\n")
cat("  SETUP COMPLETE\n")
cat("========================================================\n\n")

db_path <- file.path(zzedc_dir, "vignettes", "demonstration-trial", "data", "demonstration_trial.db")

cat("Database location:\n")
cat("  ", db_path, "\n\n")

cat("Test Credentials:\n")
cat("  +--------------+--------------+-------------+\n")
cat("  | Username     | Password     | Role        |\n")
cat("  +--------------+--------------+-------------+\n")
cat("  | admin        | admin123     | Admin       |\n")
cat("  | jane_smith   | jane123      | Coordinator |\n")
cat("  | bob_johnson  | bob123       | Coordinator |\n")
cat("  | researcher   | research123  | Researcher  |\n")
cat("  +--------------+--------------+-------------+\n\n")

cat("To launch ZZedc with the demonstration trial:\n\n")
cat("  library(zzedc)\n")
cat("  Sys.setenv(ZZEDC_DB_PATH = \"", db_path, "\")\n", sep = "")
cat("  launch_zzedc()\n\n")

cat("Or run this one-liner:\n\n")
cat("  Rscript -e 'library(zzedc); Sys.setenv(ZZEDC_DB_PATH=\"",
    db_path, "\"); launch_zzedc()'\n\n", sep = "")

cat("========================================================\n")
