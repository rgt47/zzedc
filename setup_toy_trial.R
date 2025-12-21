#!/usr/bin/env Rscript
#
# ZZedc Toy Trial Complete Setup Script
#
# This script automates the complete setup process for new users:
#   - Installs R dependencies
#   - Installs zzedc.validation package
#   - Installs zzedc package
#   - Creates toy trial database with 20 subjects
#   - Adds test users
#   - Verifies the setup
#
# Usage:
#   From the zzedc directory:
#     Rscript setup_toy_trial.R
#
#   Or from R:
#     source("setup_toy_trial.R")
#

cat("\n")
cat("========================================================\n")
cat("  ZZedc Toy Trial - Complete Setup Script\n")
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
  if (file.exists("setup_toy_trial.R")) {
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

# Step 2: Install zzedc.validation
cat("Step 2/5: Installing zzedc.validation...\n")
cat("------------------------------------------------------\n")

validation_installed <- requireNamespace("zzedc.validation", quietly = TRUE)

if (!validation_installed) {
  # Try to find sibling directory first
  parent_dir <- dirname(zzedc_dir)
  validation_dir <- file.path(parent_dir, "zzedc-validation")

  if (dir.exists(validation_dir)) {
    cat("  Found local zzedc-validation at:", validation_dir, "\n")
    cat("  Installing from local directory...\n")
    devtools::install(validation_dir, quiet = TRUE, upgrade = "never")
  } else {
    cat("  Installing from GitHub (rgt47/zzedc-validation)...\n")
    devtools::install_github("rgt47/zzedc-validation", quiet = TRUE,
                             upgrade = "never")
  }
  cat("  zzedc.validation installed.\n")
} else {
  cat("  zzedc.validation already installed (version:",
      as.character(packageVersion("zzedc.validation")), ")\n")
}
cat("\n")

# Step 3: Install zzedc
cat("Step 3/5: Installing zzedc...\n")
cat("------------------------------------------------------\n")

cat("  Installing from:", zzedc_dir, "\n")
devtools::install(zzedc_dir, quiet = TRUE, upgrade = "never")
cat("  zzedc installed (version:",
    as.character(packageVersion("zzedc")), ")\n")
cat("\n")

# Step 4: Run toy trial setup scripts
cat("Step 4/5: Setting up toy trial database...\n")
cat("------------------------------------------------------\n")

toy_trial_scripts <- file.path(zzedc_dir, "vignettes", "toy-trial", "scripts")

# Run scripts using system() to ensure correct working directory detection
run_script <- function(script_name, description) {
  script_path <- file.path(toy_trial_scripts, script_name)
  cat("  ", description, "...\n", sep = "")
  result <- system2("Rscript", args = script_path, stdout = TRUE, stderr = TRUE)
  cat(paste("    ", result, collapse = "\n"), "\n")
  invisible(result)
}

# Setup database
run_script("01-setup_toy_trial.R", "Creating database with 20 subjects")

# Add users
run_script("02-add_users.R", "Adding test users")

cat("\n")

# Step 5: Verify setup
cat("Step 5/5: Verifying setup...\n")
cat("------------------------------------------------------\n")
run_script("03-verify_toy_trial.R", "Verifying data")

# Final summary
cat("\n")
cat("========================================================\n")
cat("  SETUP COMPLETE\n")
cat("========================================================\n\n")

db_path <- file.path(zzedc_dir, "vignettes", "toy-trial", "data", "toy_trial.db")

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

cat("To launch ZZedc with the toy trial:\n\n")
cat("  library(zzedc)\n")
cat("  Sys.setenv(ZZEDC_DB_PATH = \"", db_path, "\")\n", sep = "")
cat("  launch_zzedc()\n\n")

cat("Or run this one-liner:\n\n")
cat("  Rscript -e 'library(zzedc); Sys.setenv(ZZEDC_DB_PATH=\"",
    db_path, "\"); launch_zzedc()'\n\n", sep = "")

cat("========================================================\n")
