## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  eval = FALSE
)

## ----prereq_install-----------------------------------------------------------
# install.packages("googlesheets4")

## ----auth_interactive---------------------------------------------------------
# library(googlesheets4)
# 
# # Interactive mode (one-time browser consent):
# gs4_auth(email = "your-google-account@example.org")

## ----auth_service_account-----------------------------------------------------
# # Service-account mode (unattended):
# gs4_auth(
#   path = "/path/to/zzedc-service-account.json",
#   scopes = "https://www.googleapis.com/auth/spreadsheets"
# )

## ----template_validation------------------------------------------------------
# library(zzedc)
# 
# template <- create_validation_rules_template(
#   sheet_name       = "ToyTrial_ValidationRules",
#   include_examples = TRUE
# )
# template$sheet_url

## ----import_one_call----------------------------------------------------------
# library(zzedc)
# 
# db_path <- "~/zzedc_demonstration_trial_gsheets/data/demonstration_trial.db"
# dir.create(dirname(db_path), recursive = TRUE,
#            showWarnings = FALSE)
# 
# sheet_id <- "1AbC...your-sheet-id..."  # from the Sheet URL
# 
# result <- setup_zzedc_from_gsheets(
#   sheet_id     = sheet_id,
#   db_path      = db_path,
#   imported_by  = "data_manager",
#   overwrite    = TRUE
# )
# 
# # Per-stage status
# result$success                   # overall pass/fail
# result$users$imported            # number of users imported
# result$forms$imported_forms      # number of CRFs created
# result$forms$imported_fields     # number of fields across all CRFs
# result$validation_rules$imported # number of validation rules imported
# 
# # The encryption key is needed for any subsequent operations in
# # this R session.
# Sys.setenv(DB_ENCRYPTION_KEY = result$key)

## ----dryrun-------------------------------------------------------------------
# preview <- setup_zzedc_from_gsheets(
#   sheet_id  = sheet_id,
#   db_path   = db_path,
#   dry_run   = TRUE
# )
# preview$validation_rules$skipped  # rule rows with syntax errors
# preview$validation_rules$errors   # named list of error messages

## ----import_rules_only--------------------------------------------------------
# result <- import_validation_rules_from_gsheets(
#   sheet_id        = sheet_id,
#   sheet_name      = "validation_rules",
#   imported_by     = "data_manager",
#   validate_syntax = TRUE,
#   dry_run         = FALSE
# )

## ----sync---------------------------------------------------------------------
# sync_result <- sync_dsl_rules_from_gsheets(
#   sheet_id     = sheet_id,
#   imported_by  = "data_manager",
#   delete_missing = FALSE
# )
# 
# sync_result$added
# sync_result$updated
# sync_result$deleted

## ----verify-------------------------------------------------------------------
# conn <- connect_encrypted_db(db_path = db_path,
#                               key = init_result$key)
# on.exit(DBI::dbDisconnect(conn), add = TRUE)
# 
# # Roster
# DBI::dbGetQuery(conn, "SELECT username, role FROM edc_users")
# 
# # Form / field counts
# DBI::dbGetQuery(conn, "
#   SELECT crf_code, COUNT(*) AS n_fields
#   FROM crf_definitions cd
#   JOIN designer_fields df ON df.design_id = cd.crf_id
#   GROUP BY crf_code
# ")
# 
# # Validation rules
# DBI::dbGetQuery(conn, "
#   SELECT rule_id, field_code, severity FROM validation_rules
# ")

## ----launch-------------------------------------------------------------------
# library(zzedc)
# Sys.setenv(ZZEDC_DB_PATH = db_path)
# launch_zzedc()

