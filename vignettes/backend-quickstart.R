## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = '#>',
  eval = FALSE
)

## ----check_r------------------------------------------------------------------
# R.version.string
# # Should print 'R version 4.1.0' or higher.

## ----install_github-----------------------------------------------------------
# if (!requireNamespace('devtools', quietly = TRUE)) {
#   install.packages('devtools')
# }
# devtools::install_github('rgt47/zzedc')

## ----install_local------------------------------------------------------------
# # Clone first:
# #   git clone https://github.com/rgt47/zzedc.git
# #   cd zzedc
# devtools::install('.')

## ----verify-------------------------------------------------------------------
# library(zzedc)
# packageVersion('zzedc')

## ----project_layout-----------------------------------------------------------
# project_dir <- 'my_study'
# dir.create(project_dir, showWarnings = FALSE)
# for (sub in c('data', 'logs', 'exports', 'backups')) {
#   dir.create(file.path(project_dir, sub), showWarnings = FALSE)
# }
# setwd(project_dir)

## ----init_db------------------------------------------------------------------
# library(zzedc)
# 
# config <- list(
#   db_backend = 'sqlite',
#   sqlite = list(path = 'data/my_study.db'),
# 
#   study_name        = 'My Clinical Trial',
#   protocol_id       = 'STUDY-2026-001',
#   pi_name           = 'Dr. Investigator',
#   pi_email          = 'investigator@example.org',
#   study_phase       = 'Phase 2',
#   target_enrollment = 50,
# 
#   admin_username = 'admin',
#   admin_password = 'ChangeMe!2026',
#   admin_fullname = 'Study Administrator',
#   admin_email    = 'admin@example.org',
# 
#   security_salt = paste0(
#     sample(c(letters, LETTERS, 0:9), 32, replace = TRUE),
#     collapse = ''
#   ),
#   session_timeout    = 30,
#   max_login_attempts = 3
# )
# 
# adapter <- create_db_adapter(config)
# conn    <- adapter$connect()
# on.exit(adapter$disconnect(conn), add = TRUE)
# 
# result <- create_wizard_database(
#   config,
#   config$sqlite$path,
#   backend = config$db_backend
# )
# 
# if (!isTRUE(result$success)) {
#   stop('Database initialisation failed: ', result$message)
# }

## ----default_config-----------------------------------------------------------
# config <- default_db_config(
#   'postgresql',
#   host     = 'db.example.org',
#   name     = 'my_clinical_trial',
#   user     = 'zzedc_user',
#   password = Sys.getenv('ZZEDC_DB_PASSWORD')
# )
# adapter <- create_db_adapter(config)

## ----wizard-------------------------------------------------------------------
# library(zzedc)
# launch_setup_wizard()

## ----launch-------------------------------------------------------------------
# library(zzedc)
# 
# Sys.setenv(ZZEDC_DB_BACKEND = 'sqlite')
# Sys.setenv(ZZEDC_DB_PATH    = 'data/my_study.db')
# 
# launch_zzedc(port = 3838)

## ----launch_server------------------------------------------------------------
# Sys.setenv(ZZEDC_DB_BACKEND = 'postgresql')
# Sys.setenv(ZZEDC_DB_HOST    = 'localhost')
# Sys.setenv(ZZEDC_DB_PORT    = '5432')
# Sys.setenv(ZZEDC_DB_NAME    = 'my_clinical_trial')
# Sys.setenv(ZZEDC_DB_USER    = 'zzedc_user')
# Sys.setenv(ZZEDC_DB_PASSWORD = '...')
# 
# launch_zzedc(port = 3838)

## ----migrate------------------------------------------------------------------
# library(zzedc)
# 
# source_config <- default_db_config(
#   'sqlite',
#   path = 'data/my_study.db'
# )
# dest_config <- default_db_config(
#   'postgresql',
#   host     = 'db.example.org',
#   name     = 'my_clinical_trial',
#   user     = 'zzedc_user',
#   password = Sys.getenv('ZZEDC_DB_PASSWORD')
# )
# 
# result <- migrate_between_backends(source_config, dest_config)
# result$tables  # per-table row counts and timing

## ----sqlite_driver------------------------------------------------------------
# install.packages('RSQLite')

## ----sqlite_backup------------------------------------------------------------
# backup_path <- sprintf(
#   'backups/my_study_%s.db',
#   format(Sys.time(), '%Y%m%d_%H%M%S')
# )
# file.copy('data/my_study.db', backup_path)

## ----sqlite_vacuum------------------------------------------------------------
# library(DBI)
# library(RSQLite)
# conn <- dbConnect(SQLite(), 'data/my_study.db')
# dbExecute(conn, 'VACUUM')
# dbExecute(conn, 'ANALYZE')
# dbDisconnect(conn)

## ----duckdb_driver------------------------------------------------------------
# install.packages('duckdb')
# library(duckdb)
# packageVersion('duckdb')

## ----duckdb_parquet-----------------------------------------------------------
# library(duckdb)
# conn <- dbConnect(duckdb(), 'data/my_study.duckdb')
# 
# # Export a single table.
# dbExecute(conn, "
#   COPY subjects
#   TO 'exports/subjects.parquet'
#   (FORMAT PARQUET)
# ")
# 
# # Export a join result with ZSTD compression.
# dbExecute(conn, "
#   COPY (
#     SELECT s.*, r.treatment_arm
#     FROM subjects s
#     LEFT JOIN randomization r ON s.subject_id = r.subject_id
#   ) TO 'exports/subjects_with_treatment.parquet'
#   (FORMAT PARQUET, COMPRESSION ZSTD)
# ")
# 
# dbDisconnect(conn)

## ----mysql_driver-------------------------------------------------------------
# install.packages('RMariaDB')
# # Optional, for multi-user Shiny deployments:
# install.packages('pool')

## ----postgres_driver----------------------------------------------------------
# install.packages('RPostgres')
# library(RPostgres)
# packageVersion('RPostgres')

## ----clickhouse_driver--------------------------------------------------------
# install.packages('RClickhouse')
# library(RClickhouse)
# packageVersion('RClickhouse')

## ----ch_create----------------------------------------------------------------
# library(RClickhouse)
# conn <- dbConnect(
#   RClickhouse::clickhouse(),
#   host = 'localhost', port = 9000,
#   db = 'my_clinical_trial',
#   user = 'zzedc_user',
#   password = Sys.getenv('ZZEDC_DB_PASSWORD')
# )
# 
# dbExecute(conn, "
#   CREATE TABLE IF NOT EXISTS subjects (
#     subject_id      UInt32,
#     study_id        String,
#     site_id         String,
#     enrollment_date Date,
#     status          String,
#     treatment_arm   String,
#     created_at      DateTime DEFAULT now(),
#     updated_at      DateTime DEFAULT now()
#   ) ENGINE = MergeTree()
#   ORDER BY (site_id, subject_id)
# ")
# 
# dbExecute(conn, "
#   CREATE TABLE IF NOT EXISTS audit_trail (
#     audit_id     UInt64,
#     user_id      UInt32,
#     action       String,
#     table_name   String,
#     record_id    String,
#     old_value    String,
#     new_value    String,
#     action_date  DateTime DEFAULT now(),
#     ip_address   String
#   ) ENGINE = MergeTree()
#   ORDER BY (action_date, user_id)
#   TTL action_date + INTERVAL 7 YEAR
# ")
# 
# dbDisconnect(conn)

