# ADHD Clinical Trial Data Loader
# This script loads all CSV files for the ADHD trial workflow
#
# Usage:
#   source("load_adhd_trial_data.R")
#   adhd_data <- load_adhd_trial_csvs()
#
# Or use individual functions:
#   users <- load_users_csv()
#   forms <- load_forms_overview_csv()

library(readr)
library(dplyr)

# Set the path to CSV files directory
csv_dir <- "adhd_trial_csv_files"

#' Load all ADHD trial CSV files into a named list
#' @param csv_directory Path to directory containing CSV files
#' @return Named list with all loaded data frames
load_adhd_trial_csvs <- function(csv_directory = csv_dir) {

  cat("Loading ADHD Clinical Trial CSV Files...\n")
  cat("=====================================\n")

  # Initialize result list
  adhd_data <- list()

  # Authentication and setup files
  cat("📋 Loading authentication and setup files...\n")
  adhd_data$users <- load_users_csv(csv_directory)
  adhd_data$roles <- load_roles_csv(csv_directory)
  adhd_data$sites <- load_sites_csv(csv_directory)
  adhd_data$forms_overview <- load_forms_overview_csv(csv_directory)

  # Form definition files
  cat("📝 Loading form definitions...\n")
  adhd_data$form_screening <- load_form_csv("form_screening", csv_directory)
  adhd_data$form_demographics <- load_form_csv("form_demographics", csv_directory)
  adhd_data$form_medical_history <- load_form_csv("form_medical_history", csv_directory)
  adhd_data$form_adhd_rating <- load_form_csv("form_adhd_rating", csv_directory)
  adhd_data$form_side_effects <- load_form_csv("form_side_effects", csv_directory)
  adhd_data$form_vital_signs <- load_form_csv("form_vital_signs", csv_directory)
  adhd_data$form_medication_compliance <- load_form_csv("form_medication_compliance", csv_directory)
  adhd_data$form_adverse_events <- load_form_csv("form_adverse_events", csv_directory)
  adhd_data$form_study_completion <- load_form_csv("form_study_completion", csv_directory)

  cat("✅ All files loaded successfully!\n")
  cat(sprintf("📊 Loaded %d data tables\n", length(adhd_data)))

  return(adhd_data)
}

#' Load users CSV file
#' @param csv_directory Path to CSV directory
#' @return Data frame with user information
load_users_csv <- function(csv_directory = csv_dir) {
  file_path <- file.path(csv_directory, "users.csv")

  if (!file.exists(file_path)) {
    stop("Users CSV file not found: ", file_path)
  }

  users <- read_csv(file_path, show_col_types = FALSE)
  cat(sprintf("  👥 Users: %d records loaded\n", nrow(users)))

  return(users)
}

#' Load roles CSV file
#' @param csv_directory Path to CSV directory
#' @return Data frame with role definitions
load_roles_csv <- function(csv_directory = csv_dir) {
  file_path <- file.path(csv_directory, "roles.csv")

  if (!file.exists(file_path)) {
    stop("Roles CSV file not found: ", file_path)
  }

  roles <- read_csv(file_path, show_col_types = FALSE)
  cat(sprintf("  🎭 Roles: %d records loaded\n", nrow(roles)))

  return(roles)
}

#' Load sites CSV file
#' @param csv_directory Path to CSV directory
#' @return Data frame with site information
load_sites_csv <- function(csv_directory = csv_dir) {
  file_path <- file.path(csv_directory, "sites.csv")

  if (!file.exists(file_path)) {
    stop("Sites CSV file not found: ", file_path)
  }

  sites <- read_csv(file_path, show_col_types = FALSE)
  cat(sprintf("  🏥 Sites: %d records loaded\n", nrow(sites)))

  return(sites)
}

#' Load forms overview CSV file
#' @param csv_directory Path to CSV directory
#' @return Data frame with forms overview
load_forms_overview_csv <- function(csv_directory = csv_dir) {
  file_path <- file.path(csv_directory, "forms_overview.csv")

  if (!file.exists(file_path)) {
    stop("Forms overview CSV file not found: ", file_path)
  }

  forms <- read_csv(file_path, show_col_types = FALSE)
  cat(sprintf("  📋 Forms overview: %d forms defined\n", nrow(forms)))

  return(forms)
}

#' Load individual form definition CSV file
#' @param form_name Name of the form (without .csv extension)
#' @param csv_directory Path to CSV directory
#' @return Data frame with form field definitions
load_form_csv <- function(form_name, csv_directory = csv_dir) {
  file_path <- file.path(csv_directory, paste0(form_name, ".csv"))

  if (!file.exists(file_path)) {
    warning("Form CSV file not found: ", file_path)
    return(NULL)
  }

  form_data <- read_csv(file_path, show_col_types = FALSE)
  cat(sprintf("  📝 %s: %d fields defined\n", form_name, nrow(form_data)))

  return(form_data)
}

#' Generate summary of all loaded data
#' @param adhd_data List of loaded data frames
#' @return Summary data frame
summarize_adhd_data <- function(adhd_data) {

  summary_data <- data.frame(
    table_name = names(adhd_data),
    record_count = sapply(adhd_data, nrow),
    column_count = sapply(adhd_data, ncol),
    stringsAsFactors = FALSE
  )

  # Add table types
  summary_data$table_type <- case_when(
    summary_data$table_name %in% c("users", "roles", "sites") ~ "Authentication",
    summary_data$table_name == "forms_overview" ~ "Configuration",
    grepl("^form_", summary_data$table_name) ~ "Form Definition",
    TRUE ~ "Other"
  )

  return(summary_data)
}

#' Validate ADHD trial data structure
#' @param adhd_data List of loaded data frames
#' @return List with validation results
validate_adhd_data <- function(adhd_data) {

  cat("🔍 Validating ADHD trial data structure...\n")

  validation_results <- list(
    missing_tables = character(),
    validation_errors = character(),
    warnings = character()
  )

  # Required tables
  required_tables <- c("users", "roles", "sites", "forms_overview",
                      "form_screening", "form_demographics", "form_adhd_rating")

  missing_tables <- setdiff(required_tables, names(adhd_data))
  if (length(missing_tables) > 0) {
    validation_results$missing_tables <- missing_tables
    cat("❌ Missing required tables:", paste(missing_tables, collapse = ", "), "\n")
  }

  # Validate users table
  if ("users" %in% names(adhd_data)) {
    users <- adhd_data$users
    required_user_cols <- c("username", "password", "full_name", "email", "role", "site_id", "active")
    missing_user_cols <- setdiff(required_user_cols, names(users))
    if (length(missing_user_cols) > 0) {
      validation_results$validation_errors <- c(validation_results$validation_errors,
                                               paste("Users table missing columns:", paste(missing_user_cols, collapse = ", ")))
    }
  }

  # Validate forms have required columns
  form_tables <- names(adhd_data)[grepl("^form_", names(adhd_data))]
  required_form_cols <- c("field", "prompt", "type", "layout", "req")

  for (form_table in form_tables) {
    form_data <- adhd_data[[form_table]]
    missing_form_cols <- setdiff(required_form_cols, names(form_data))
    if (length(missing_form_cols) > 0) {
      validation_results$validation_errors <- c(validation_results$validation_errors,
                                               paste(form_table, "missing columns:", paste(missing_form_cols, collapse = ", ")))
    }
  }

  # Summary
  if (length(validation_results$validation_errors) == 0 && length(validation_results$missing_tables) == 0) {
    cat("✅ All validation checks passed!\n")
  } else {
    cat("⚠️ Validation issues found. Check validation_results for details.\n")
  }

  return(validation_results)
}

#' Export data to Google Sheets format
#' @param adhd_data List of loaded data frames
#' @param output_dir Directory to save Google Sheets compatible CSVs
export_for_google_sheets <- function(adhd_data, output_dir = "google_sheets_export") {

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  cat("📤 Exporting data for Google Sheets...\n")

  # Create authentication sheet with multiple tabs
  auth_file <- file.path(output_dir, "ADHD_Trial_Auth.csv")

  # Combine auth data with tab indicators
  auth_combined <- rbind(
    cbind(tab = "users", adhd_data$users),
    cbind(tab = "roles", data.frame(role = adhd_data$roles$role,
                                   description = adhd_data$roles$description,
                                   permissions = adhd_data$roles$permissions)),
    cbind(tab = "sites", adhd_data$sites)
  )

  write_csv(auth_combined, auth_file)
  cat(sprintf("  📊 Authentication data exported to: %s\n", auth_file))

  # Create data dictionary sheet
  dd_file <- file.path(output_dir, "ADHD_Trial_DataDict.csv")

  # Combine all form definitions
  dd_combined <- rbind(
    cbind(tab = "forms_overview", adhd_data$forms_overview),
    cbind(tab = "form_screening", adhd_data$form_screening),
    cbind(tab = "form_demographics", adhd_data$form_demographics),
    cbind(tab = "form_adhd_rating", adhd_data$form_adhd_rating),
    cbind(tab = "form_side_effects", adhd_data$form_side_effects)
  )

  write_csv(dd_combined, dd_file)
  cat(sprintf("  📊 Data dictionary exported to: %s\n", dd_file))

  cat("✅ Google Sheets export completed!\n")
  cat("📝 Instructions:\n")
  cat("  1. Upload these CSV files to Google Sheets\n")
  cat("  2. Split tabs by the 'tab' column\n")
  cat("  3. Remove the 'tab' column from each sheet\n")
  cat("  4. Use with ZZedc Google Sheets integration\n")
}

# Example usage function
demo_adhd_data_usage <- function() {
  cat("🎯 ADHD Trial Data Usage Demo\n")
  cat("============================\n")

  # Load all data
  adhd_data <- load_adhd_trial_csvs()

  # Generate summary
  cat("\n📊 Data Summary:\n")
  summary <- summarize_adhd_data(adhd_data)
  print(summary)

  # Validate data
  cat("\n🔍 Data Validation:\n")
  validation <- validate_adhd_data(adhd_data)

  # Show example data access
  cat("\n💡 Example Data Access:\n")
  cat("Number of users:", nrow(adhd_data$users), "\n")
  cat("Number of ADHD rating scale items:", nrow(adhd_data$form_adhd_rating), "\n")
  cat("Available forms:", paste(adhd_data$forms_overview$workingname, collapse = ", "), "\n")

  return(adhd_data)
}

# Print instructions when script is sourced
cat("🎯 ADHD Clinical Trial CSV Data Loader\n")
cat("=====================================\n")
cat("Available functions:\n")
cat("  load_adhd_trial_csvs()    - Load all CSV files\n")
cat("  summarize_adhd_data()     - Generate data summary\n")
cat("  validate_adhd_data()      - Validate data structure\n")
cat("  export_for_google_sheets() - Export for Google Sheets\n")
cat("  demo_adhd_data_usage()    - Run complete demo\n")
cat("\nQuick start:\n")
cat("  adhd_data <- load_adhd_trial_csvs()\n")
cat("  summary(adhd_data)\n")