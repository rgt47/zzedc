## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment  = "#>",
  eval     = FALSE
)

## ----c1-example---------------------------------------------------------------
# library(RMariaDB)
# conn <- DBI::dbConnect(MariaDB(),
#   host     = "redcap.example.org",
#   dbname   = "redcap",
#   user     = "redcap_reader",
#   password = Sys.getenv("REDCAP_DB_PASSWORD"))
# on.exit(DBI::dbDisconnect(conn), add = TRUE)
# 
# result <- import_redcap_to_zzedc(
#   conn       = conn,
#   pid        = 42L,
#   output_dir = "~/zzedc_migration/redcap_42"
# )
# 
# result$counts          # rows per artefact
# length(result$skipped_rules)  # rules needing manual review

## ----recipe-c1----------------------------------------------------------------
# # 1. Connect to your REDCap source database (institutional
# #    MySQL, SQLite hydrated from a dump, or any DBI connection
# #    whose schema matches REDCap's relational layout).
# conn <- DBI::dbConnect(RMariaDB::MariaDB(),
#   host = "redcap.example.org", dbname = "redcap",
#   user = "redcap_reader",
#   password = Sys.getenv("REDCAP_DB_PASSWORD"))
# 
# # 2. Run the C1 importer.
# out <- "~/zzedc_migration/redcap_42"
# result <- import_redcap_to_zzedc(conn, pid = 42L,
#                                   output_dir = out)
# 
# # 3. Review the manifest and `skipped_rules`. Translate any
# #    branching-logic rules manually into the
# #    validation_rules.csv following the patterns in
# #    vignette('content-author-guide').
# 
# # 4. Stage data_dictionary.csv, validation_rules.csv, and
# #    users.csv into a Google Sheets workbook and run
# #    setup_zzedc_from_gsheets() against it; or use the CSV
# #    authoring path documented in
# #    vignette('demonstration-trial-setup').
# DBI::dbDisconnect(conn)

## ----recipe-c2----------------------------------------------------------------
# library(RMariaDB)
# conn <- DBI::dbConnect(MariaDB(),
#   host     = "redcap.example.org",
#   dbname   = "redcap",
#   user     = "redcap_reader",
#   password = Sys.getenv("REDCAP_DB_PASSWORD"))
# on.exit(DBI::dbDisconnect(conn), add = TRUE)
# 
# result <- import_redcap_to_zzedc_db(
#   conn       = conn,
#   pid        = 42L,
#   db_path    = "/srv/zzedc/MIGRATED-001/study.db",
#   overwrite  = FALSE,
#   dry_run    = FALSE
# )
# 
# # Required for any subsequent operation in this R session.
# Sys.setenv(DB_ENCRYPTION_KEY = result$key)
# 
# # Per-stage diagnostics
# result$success                       # overall pass/fail
# result$users$imported                # users created
# result$forms$imported_forms          # CRFs created
# result$forms$imported_fields         # fields across all CRFs
# result$subjects$imported             # subject records seeded
# result$subject_data$imported         # subject form_data rows
# result$audit_replay$imported         # REDCap audit rows replayed
# result$audit_replay$chain_validates  # hash chain valid end-to-end
# length(result$skipped_rules)         # rules deferred to manual review
# result$branching_translated          # branching rules translated

## ----eval = FALSE-------------------------------------------------------------
# library(zzedc)
# 
# result <- import_redcap_to_zzedc_db(
#   source    = "api",
#   api_url   = "https://redcap.example.org/api/",
#   api_token = Sys.getenv("REDCAP_API_TOKEN"),
#   db_path   = "/srv/zzedc/MIGRATED-002/study.db",
#   overwrite = TRUE
# )
# 
# result$success                              # TRUE
# result$audit_replay$completeness            # full / partial / empty
# result$audit_replay$marker_inserted         # TRUE if not full
# result$audit_replay$chain_validates         # TRUE
# length(result$skipped_rules)                # rules needing manual review

## ----eval = FALSE-------------------------------------------------------------
# fake_api <- redcap_api_connect(
#   api_url   = "ignored",
#   api_token = "ignored",
#   ops = list(
#     version  = function() "14.5",
#     metadata = function() my_metadata_df,
#     users    = function() my_users_df,
#     records  = function(fields = NULL) my_records_df,
#     log      = function() my_log_df
#   )
# )
# result <- import_redcap_to_zzedc_db(
#   source = "api", api = fake_api,
#   db_path = tempfile(fileext = ".db"), overwrite = TRUE
# )

