## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  eval = FALSE
)

## ----prereq_install-----------------------------------------------------------
# # 2. Install R dependencies
# install.packages(c(
#   "shiny", "bslib", "bsicons", "shinyjs", "DT",
#   "ggplot2", "plotly", "dplyr", "jsonlite", "digest",
#   "writexl", "RSQLite", "pool", "config", "lubridate",
#   "stringr", "httr", "shinyalert", "googlesheets4",
#   "devtools"
# ))
# 
# # 3. Install zzedc
# devtools::install("~/zzedc-project/zzedc")

## ----quick_launch-------------------------------------------------------------
# library(zzedc)
# Sys.setenv(ZZEDC_DB_PATH = "vignettes/demonstration-trial/data/demonstration_trial.db")
# launch_zzedc()

## -----------------------------------------------------------------------------
# # Create main project directory
# project_dir <- "~/zzedc_demonstration_trial"
# dir.create(project_dir, showWarnings = FALSE)
# 
# # Create subdirectories
# dir.create(file.path(project_dir, "data"), showWarnings = FALSE)
# dir.create(file.path(project_dir, "scripts"), showWarnings = FALSE)
# dir.create(file.path(project_dir, "logs"), showWarnings = FALSE)
# dir.create(file.path(project_dir, "exports"), showWarnings = FALSE)
# 
# # Verify structure
# list.files(project_dir, recursive = TRUE)

## ----sqlite_setup-------------------------------------------------------------
# library(zzedc)
# 
# # Configure for SQLite (default)
# config <- list(
#   db_backend = "sqlite",
#   sqlite = list(
#     path = "data/demonstration_trial.db"
#   )
# )
# 
# # Create database adapter
# adapter <- create_db_adapter(config)
# conn <- adapter$connect()
# 
# # Create study tables
# # ... (setup continues below)
# 
# adapter$disconnect(conn)

## ----duckdb_setup-------------------------------------------------------------
# library(zzedc)
# 
# # Configure for DuckDB
# config <- list(
#   db_backend = "duckdb",
#   duckdb = list(
#     path = "data/demonstration_trial.duckdb"
#   )
# )
# 
# # Create database adapter
# adapter <- create_db_adapter(config)
# conn <- adapter$connect()
# 
# # DuckDB-specific: Direct Parquet export for statisticians
# # adapter$export_parquet(conn, "subjects", "exports/subjects.parquet")
# 
# adapter$disconnect(conn)

## ----postgresql_setup---------------------------------------------------------
# library(zzedc)
# 
# # Configure for PostgreSQL
# config <- list(
#   db_backend = "postgresql",
#   postgresql = list(
#     host = "localhost",
#     port = 5432,
#     name = "demonstration_trial",
#     user = "zzedc_user",
#     password = Sys.getenv("ZZEDC_PG_PASSWORD")
#   )
# )
# 
# # Create database adapter
# adapter <- create_db_adapter(config)
# conn <- adapter$connect()
# 
# # PostgreSQL uses SERIAL for auto-increment primary keys
# # Transactions are fully ACID compliant
# 
# adapter$disconnect(conn)

## ----clickhouse_setup---------------------------------------------------------
# library(zzedc)
# 
# # Configure for ClickHouse
# config <- list(
#   db_backend = "clickhouse",
#   clickhouse = list(
#     host = "localhost",
#     port = 9000,
#     database = "demonstration_trial",
#     user = "default",
#     password = ""
#   )
# )
# 
# # Create database adapter
# adapter <- create_db_adapter(config)
# conn <- adapter$connect()
# 
# # ClickHouse uses MergeTree engine for efficient columnar storage
# # Excellent for audit trail queries across millions of records
# 
# adapter$disconnect(conn)

## -----------------------------------------------------------------------------
# # Path to demonstration trial vignette directory
# vignette_dir <- system.file("doc/demonstration-trial", package = "zzedc")
# 
# # Run setup script
# source(file.path(vignette_dir, "scripts/01-setup_demonstration_trial.R"))

## -----------------------------------------------------------------------------
# # Run add users script
# source(file.path(vignette_dir, "scripts/02-add_users.R"))

## -----------------------------------------------------------------------------
# # Run verification script
# source(file.path(vignette_dir, "scripts/03-verify_demonstration_trial.R"))

## -----------------------------------------------------------------------------
# # 1. Setup database
# source("vignettes/demonstration-trial/scripts/01-setup_demonstration_trial.R")
# 
# # 2. Add test users
# source("vignettes/demonstration-trial/scripts/02-add_users.R")
# 
# # 3. Verify data
# source("vignettes/demonstration-trial/scripts/03-verify_demonstration_trial.R")
# 
# # 4. Query the database directly
# library(DBI)
# library(RSQLite)
# conn <- dbConnect(SQLite(), "data/demonstration_trial.db")
# 
# # View all subjects
# subjects <- dbGetQuery(conn, "SELECT * FROM subjects LIMIT 5")
# print(subjects)
# 
# # View randomization
# randomization <- dbGetQuery(conn, "SELECT * FROM randomization LIMIT 5")
# print(randomization)
# 
# # Close connection
# dbDisconnect(conn)

## -----------------------------------------------------------------------------
# # Set up environment variables
# Sys.setenv(
#   ZZEDC_DB_PATH = "data/demonstration_trial.db",
#   ZZEDC_STUDY = "TOY-TRIAL-001"
# )
# 
# # Launch the application
# library(zzedc)
# launch_zzedc(port = 3838)

## -----------------------------------------------------------------------------
# # Read database directly - data visible in plaintext
# library(RSQLite)
# conn <- dbConnect(SQLite(), "data/demonstration_trial.db")
# subjects <- dbGetQuery(conn, "SELECT * FROM subjects")
# print(subjects)  # Can read subject names, ages, etc.
# dbDisconnect(conn)

## -----------------------------------------------------------------------------
# # Database encrypted with SQLCipher
# # Data only accessible with correct key
# library(zzedc)
# key <- get_encryption_key()  # From Feature #1
# 
# # Database connection now transparent
# conn <- dbConnect(RSQLite::SQLite(), "data/demonstration_trial_encrypted.db", key = key)
# subjects <- dbGetQuery(conn, "SELECT * FROM subjects")
# print(subjects)  # Still works - encryption is transparent
# dbDisconnect(conn)

## -----------------------------------------------------------------------------
# # Verify file is encrypted (binary, not plaintext)
# file_content <- readBin("data/demonstration_trial_encrypted.db", "raw", n = 100)
# # Should be random binary data, not readable text

## -----------------------------------------------------------------------------
# # Remove old database
# file.remove("data/demonstration_trial.db")
# 
# # Run setup script again
# source("vignettes/demonstration-trial/scripts/01-setup_demonstration_trial.R")

## -----------------------------------------------------------------------------
# csv_dir <- system.file("doc/demonstration-trial/csv_templates", package = "zzedc")
# list.files(csv_dir)  # Should show all CSV files

## -----------------------------------------------------------------------------
# # Use absolute paths
# script_path <- system.file("doc/demonstration-trial/scripts/01-setup_demonstration_trial.R",
#                            package = "zzedc")
# source(script_path)

