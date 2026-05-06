## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(eval = FALSE)

## -----------------------------------------------------------------------------
# install.packages("zzedc")

## -----------------------------------------------------------------------------
# install.packages("RPostgres")   # PostgreSQL
# install.packages("RMariaDB")    # MySQL / MariaDB
# install.packages("duckdb")      # DuckDB
# # ClickHouse: see vignette('backend-quickstart') Appendix E

## -----------------------------------------------------------------------------
# install.packages("renv")
# renv::init()
# renv::snapshot()

## -----------------------------------------------------------------------------
# library(zzedc)
# packageVersion("zzedc")

## -----------------------------------------------------------------------------
# library(zzedc)
# key <- generate_db_key()
# verify_db_key(key)               # checks 64-hex-char format

## -----------------------------------------------------------------------------
# key <- get_encryption_key(
#   aws_kms_key_id = "zzedc/db-encryption-key"
# )

## -----------------------------------------------------------------------------
# init <- initialize_encrypted_database(
#   db_path   = "/srv/zzedc/MEMORY-001/study.db",
#   overwrite = FALSE
# )
# init$success           # TRUE
# init$key               # SAVE THIS; treat as a password

## -----------------------------------------------------------------------------
# conn <- connect_encrypted_db(
#   db_path = "/srv/zzedc/MEMORY-001/study.db"
# )
# res <- DBI::dbGetQuery(conn, "SELECT COUNT(*) FROM subjects")
# DBI::dbDisconnect(conn)

## -----------------------------------------------------------------------------
# verification <- verify_database_encryption(
#   db_path = "/srv/zzedc/MEMORY-001/study.db"
# )
# verification$encrypted     # TRUE only if SQLCipher is active
# verification$message

## -----------------------------------------------------------------------------
# result <- migrate_to_encrypted(
#   old_db_path = "/srv/zzedc/MEMORY-001/legacy.db",
#   backup_dir  = "/srv/zzedc/MEMORY-001/backups"
# )
# result$success
# result$records_migrated
# result$new_path

## -----------------------------------------------------------------------------
# verify_migration(
#   old_db_path = "/srv/zzedc/MEMORY-001/legacy.db",
#   new_db_path = "/srv/zzedc/MEMORY-001/legacy_encrypted.db"
# )

## -----------------------------------------------------------------------------
# rollback_migration(
#   backup_path = "/srv/zzedc/MEMORY-001/backups/legacy_*.db",
#   restore_to  = "/srv/zzedc/MEMORY-001/legacy.db"
# )

## -----------------------------------------------------------------------------
# audit_res <- init_audit_logging(
#   db_path = "/srv/zzedc/MEMORY-001/study.db"
# )
# audit_res$success

## -----------------------------------------------------------------------------
# result <- create_wizard_database(
#   config_list = list(
#     study_name        = "Memory Study 001",
#     protocol_id       = "MEMORY-001",
#     pi_name           = "Jane Smith, MD",
#     pi_email          = "jsmith@example.org",
#     study_phase       = "II",
#     target_enrollment = 60,
#     admin_username    = "admin",
#     admin_password    = "TempPass!2026-CHANGEME",
#     admin_fullname    = "Trial Admin",
#     admin_email       = "admin@example.org",
#     security_salt     = Sys.getenv("ZZEDC_SALT")
#   ),
#   db_path = "/srv/zzedc/MEMORY-001/study.db",
#   backend = "sqlite"
# )

## -----------------------------------------------------------------------------
# library(googlesheets4)
# gs4_auth(email = "svc-zzedc@example.iam.gserviceaccount.com")

## -----------------------------------------------------------------------------
# library(zzedc)
# result <- setup_zzedc_from_gsheets(
#   sheet_id = "https://docs.google.com/spreadsheets/d/SHEET_ID/edit",
#   db_path  = "/srv/zzedc/MEMORY-001/study.db",
#   imported_by = "tech_lead"
# )
# 
# result$success                 # TRUE
# result$users$imported          # number of users created
# result$forms$imported_forms    # number of CRFs created
# result$forms$imported_fields   # number of fields across CRFs
# result$validation_rules$imported  # number of rules
# length(result$skipped_rules)   # rules that need manual review

## -----------------------------------------------------------------------------
# str(result$skipped_rules)

## -----------------------------------------------------------------------------
# result <- setup_zzedc_from_csv(
#   csv_dir = "/srv/zzedc/MEMORY-001/incoming/",
#   db_path = "/srv/zzedc/MEMORY-001/study.db",
#   imported_by = "tech_lead"
# )

## -----------------------------------------------------------------------------
# library(DBI)
# conn <- connect_encrypted_db(
#   db_path = "/srv/zzedc/MEMORY-001/study.db",
#   key     = Sys.getenv("DB_ENCRYPTION_KEY")
# )
# on.exit(DBI::dbDisconnect(conn), add = TRUE)
# 
# # How many sites are configured
# DBI::dbGetQuery(conn, "
#   SELECT site_id, COUNT(*) AS n_users
#     FROM edc_users
#    GROUP BY site_id
# ")
# 
# # Per-site user list
# DBI::dbGetQuery(conn, "
#   SELECT site_id, username, role
#     FROM edc_users
#    ORDER BY site_id, username
# ")

## -----------------------------------------------------------------------------
# library(zzedc)
# launch_zzedc()
# # Open http://localhost:3838

## -----------------------------------------------------------------------------
# verify_backup <- function(backup_path, config) {
#   temp_dir <- tempfile("backup_verify_")
#   dir.create(temp_dir)
#   on.exit(unlink(temp_dir, recursive = TRUE))
# 
#   if (grepl("\\.gz$", backup_path)) {
#     out <- file.path(temp_dir, "backup.sql")
#     system2("gunzip", c("-c", backup_path), stdout = out)
#     backup_path <- out
#   }
# 
#   test_config <- config
#   test_config$sqlite$path <- file.path(temp_dir, "verify.db")
#   adapter <- create_db_adapter(test_config)
#   conn <- adapter$connect()
#   on.exit(adapter$disconnect(conn), add = TRUE)
# 
#   tryCatch({
#     sql <- readLines(backup_path)
#     for (stmt in split_sql_statements(sql)) {
#       DBI::dbExecute(conn, stmt)
#     }
#     for (tbl in c("subjects", "forms", "form_data", "audit_log")) {
#       n <- DBI::dbGetQuery(
#         conn, sprintf("SELECT COUNT(*) AS n FROM %s", tbl)
#       )$n
#       message(sprintf("Table %s: %d rows", tbl, n))
#     }
#     list(success = TRUE, message = "Backup verification passed")
#   }, error = function(e) {
#     list(success = FALSE, message = e$message)
#   })
# }

## -----------------------------------------------------------------------------
# check_backup_health <- function(backup_dir, max_age_hours = 25) {
#   issues <- character()
#   files <- list.files(
#     backup_dir,
#     pattern = "\\.(sql\\.gz|db\\.gz|dump)$",
#     full.names = TRUE
#   )
#   if (length(files) == 0) {
#     issues <- c(issues, "No backup files found")
#   } else {
#     latest <- files[which.max(file.mtime(files))]
#     age_h <- as.numeric(
#       difftime(Sys.time(), file.mtime(latest), units = "hours")
#     )
#     if (age_h > max_age_hours) {
#       issues <- c(issues, sprintf("Latest backup %.1fh old", age_h))
#     }
#     if (file.size(latest) < 1000) {
#       issues <- c(issues, "Latest backup suspiciously small")
#     }
#   }
#   list(
#     healthy    = length(issues) == 0,
#     issues     = issues,
#     checked_at = Sys.time()
#   )
# }

## -----------------------------------------------------------------------------
# recover_deleted_records <- function(config, table_name,
#                                     deletion_time) {
#   adapter <- create_db_adapter(config)
#   conn <- adapter$connect()
#   on.exit(adapter$disconnect(conn))
# 
#   sql <- "
#     SELECT record_id, old_values, changed_at, changed_by
#       FROM audit_log
#      WHERE table_name = ?
#        AND action = 'DELETE'
#        AND changed_at >= ?
#      ORDER BY changed_at
#   "
#   deleted <- DBI::dbGetQuery(
#     conn, sql,
#     params = list(table_name, as.character(deletion_time))
#   )
#   if (nrow(deleted) == 0) {
#     message("No deleted records found in the time range")
#     return(invisible(NULL))
#   }
#   deleted
# }
# 
# restore_from_audit <- function(config, audit_records,
#                                table_name) {
#   adapter <- create_db_adapter(config)
#   conn <- adapter$connect()
#   on.exit(adapter$disconnect(conn))
# 
#   restored <- 0L
#   for (i in seq_len(nrow(audit_records))) {
#     old <- jsonlite::fromJSON(audit_records$old_values[i])
#     cols <- names(old)
#     sql <- sprintf(
#       "INSERT INTO %s (%s) VALUES (%s)",
#       table_name,
#       paste(cols, collapse = ", "),
#       paste(rep("?", length(cols)), collapse = ", ")
#     )
#     tryCatch({
#       DBI::dbExecute(conn, sql, params = as.list(old))
#       restored <- restored + 1L
#     }, error = function(e) {
#       warning(sprintf(
#         "Failed to restore record %s: %s",
#         audit_records$record_id[i], e$message
#       ))
#     })
#   }
#   message(sprintf(
#     "Restored %d of %d records", restored, nrow(audit_records)
#   ))
# }

## -----------------------------------------------------------------------------
# library(zzedc)
# res <- verify_audit_log_integrity(
#   db_path = "/srv/zzedc/MEMORY-001/study.db",
#   key     = Sys.getenv("DB_ENCRYPTION_KEY")
# )
# 
# res$valid                  # TRUE if chain validates end-to-end
# res$first_audit_id         # earliest audit_id in the chain
# res$last_audit_id          # latest
# res$chain_length           # total entries
# res$tampered_entries       # empty if chain valid

## -----------------------------------------------------------------------------
# library(DBI)
# conn <- connect_encrypted_db(
#   db_path = "/srv/zzedc/MEMORY-001/study.db",
#   key     = Sys.getenv("DB_ENCRYPTION_KEY")
# )
# DBI::dbGetQuery(conn,
#   "SELECT timestamp, details FROM audit_log
#      WHERE event_type = 'MIGRATION_AUDIT_GAP'")
# DBI::dbDisconnect(conn)

## -----------------------------------------------------------------------------
# # REST API path (no MySQL access needed):
# result <- import_redcap_to_zzedc_db(
#   source    = "api",
#   api_url   = "https://redcap.example.org/api/",
#   api_token = Sys.getenv("REDCAP_API_TOKEN"),
#   db_path   = "/srv/zzedc/MEMORY-001/study.db",
#   overwrite = TRUE
# )
# 
# result$success                              # TRUE
# result$audit_replay$completeness            # full / partial / empty
# result$audit_replay$marker_inserted         # TRUE if not full
# result$audit_replay$chain_validates         # TRUE
# length(result$skipped_rules)                # rules to manually port

## -----------------------------------------------------------------------------
# # Live MySQL path (faster, audit log always full):
# library(RMariaDB)
# conn <- DBI::dbConnect(
#   MariaDB(),
#   host     = "redcap.example.org",
#   dbname   = "redcap",
#   user     = "redcap_reader",
#   password = Sys.getenv("REDCAP_DB_PASSWORD"))
# 
# result <- import_redcap_to_zzedc_db(
#   source    = "db",
#   conn      = conn,
#   pid       = 42L,
#   db_path   = "/srv/zzedc/MEMORY-001/study.db",
#   overwrite = TRUE
# )
# DBI::dbDisconnect(conn)

