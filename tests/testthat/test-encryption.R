# Feature #1: Data Encryption at Rest - Comprehensive Test Suite
#
# Tests for all encryption-related functionality including:
# - Key generation and verification
# - Database encryption/decryption
# - Secure export with integrity verification
# - Audit trail logging
# - Database migration
#
# Regulatory compliance: GDPR Article 32, FDA 21 CFR Part 11

library(testthat)
library(DBI)
library(RSQLite)
library(digest)

# Source the encryption modules
# Find package root directory (works from multiple contexts)
find_pkg_root <- function() {
  candidates <- c(
    getwd(),
    file.path(getwd(), "..", ".."),
    Sys.getenv("ZZEDC_PKG_ROOT", unset = NA)
  )
  for (path in candidates) {
    if (!is.na(path) && file.exists(file.path(path, "R", "encryption_utils.R"))) {
      return(normalizePath(path))
    }
  }
  stop("Could not find package root directory")
}

pkg_root <- find_pkg_root()
source(file.path(pkg_root, "R", "encryption_utils.R"))
source(file.path(pkg_root, "R", "db_connection.R"))
source(file.path(pkg_root, "R", "secure_export.R"))
source(file.path(pkg_root, "R", "audit_logging.R"))
source(file.path(pkg_root, "R", "db_migration.R"))

# =============================================================================
# Helper Functions
# =============================================================================

# Helper to detect SQLCipher support in RSQLite
# SQLCipher-enabled RSQLite will produce encrypted (non-SQLite) headers
has_sqlcipher_support <- function() {
  test_db <- tempfile(fileext = ".db")
  key <- generate_db_key()
  on.exit(unlink(test_db), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = key)
  DBI::dbWriteTable(conn, "test", data.frame(secret = "TEST_SECRET"))
  DBI::dbDisconnect(conn)

  file_bytes <- readBin(test_db, "raw", n = 16)
  sqlite_sig <- as.raw(c(0x53, 0x51, 0x4c, 0x69, 0x74, 0x65))
  !identical(file_bytes[1:6], sqlite_sig)
}

# =============================================================================
# Test Section 1: Key Generation and Verification
# =============================================================================

test_that("generate_db_key creates valid 256-bit hexadecimal key", {
  key <- generate_db_key()

  expect_type(key, "character")
  expect_length(key, 1)
  expect_equal(nchar(key), 64)
  expect_match(key, "^[0-9a-f]{64}$")
})

test_that("generate_db_key produces cryptographically random keys", {
  keys <- replicate(10, generate_db_key())

  expect_equal(length(unique(keys)), 10)
})

test_that("verify_db_key accepts valid 256-bit hex key", {
  key <- generate_db_key()
  expect_true(verify_db_key(key))
})

test_that("verify_db_key rejects key with incorrect length", {
  expect_error(verify_db_key("abc123"), "64 hexadecimal")
  expect_error(verify_db_key(""), "64 hexadecimal")
  expect_error(verify_db_key(paste0(rep("a", 63), collapse = "")), "64 hex")
  expect_error(verify_db_key(paste0(rep("a", 65), collapse = "")), "64 hex")
})

test_that("verify_db_key rejects non-hexadecimal characters", {
  invalid_key <- paste(rep("g", 64), collapse = "")
  expect_error(verify_db_key(invalid_key), "hexadecimal")

  invalid_key <- paste0("ABCD", paste(rep("a", 60), collapse = ""))
  expect_error(verify_db_key(invalid_key), "lowercase")
})

test_that("verify_db_key rejects non-character input", {
  expect_error(verify_db_key(NULL), "single character")
  expect_error(verify_db_key(123), "single character")
  expect_error(verify_db_key(c("a", "b")), "single character")
})

# =============================================================================
# Test Section 2: Encryption Key Retrieval
# =============================================================================

test_that("get_encryption_key retrieves key from environment variable", {
  test_key <- generate_db_key()
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  Sys.setenv(DB_ENCRYPTION_KEY = test_key)
  retrieved_key <- get_encryption_key()

  expect_equal(retrieved_key, test_key)

  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("get_encryption_key returns error when no key available", {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  old_aws <- Sys.getenv("USE_AWS_KMS")

  Sys.unsetenv("DB_ENCRYPTION_KEY")
  Sys.unsetenv("USE_AWS_KMS")

  expect_error(get_encryption_key(), "encryption key not found")

  if (old_key != "") Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  if (old_aws != "") Sys.setenv(USE_AWS_KMS = old_aws)
})

# =============================================================================
# Test Section 3: Database Path Resolution
# =============================================================================

test_that("get_db_path returns default path when not set", {
  old_path <- Sys.getenv("ZZEDC_DB_PATH")
  Sys.unsetenv("ZZEDC_DB_PATH")

  db_path <- get_db_path()

  expect_match(db_path, "zzedc\\.db$")

  if (old_path != "") Sys.setenv(ZZEDC_DB_PATH = old_path)
})

test_that("get_db_path respects environment variable", {
  old_path <- Sys.getenv("ZZEDC_DB_PATH")

  test_path <- tempfile(fileext = ".db")
  Sys.setenv(ZZEDC_DB_PATH = test_path)

  db_path <- get_db_path()

  expect_equal(normalizePath(db_path, mustWork = FALSE),
               normalizePath(test_path, mustWork = FALSE))

  if (old_path != "") {
    Sys.setenv(ZZEDC_DB_PATH = old_path)
  } else {
    Sys.unsetenv("ZZEDC_DB_PATH")
  }
})

test_that("get_db_path creates parent directory if needed", {
  old_path <- Sys.getenv("ZZEDC_DB_PATH")

  temp_dir <- file.path(tempdir(), "test_db_dir", "subdir")
  test_path <- file.path(temp_dir, "test.db")
  Sys.setenv(ZZEDC_DB_PATH = test_path)

  get_db_path()

  expect_true(dir.exists(dirname(test_path)))

  unlink(temp_dir, recursive = TRUE)
  if (old_path != "") {
    Sys.setenv(ZZEDC_DB_PATH = old_path)
  } else {
    Sys.unsetenv("ZZEDC_DB_PATH")
  }
})

# =============================================================================
# Test Section 4: Database Initialization and Connection
# =============================================================================

test_that("initialize_encrypted_database creates new database", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  result <- initialize_encrypted_database(db_path = test_db, overwrite = FALSE)

  expect_true(result$success)
  expect_true(file.exists(test_db))
  expect_true(result$key_stored)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("initialize_encrypted_database fails if file exists and overwrite=FALSE", {
  test_db <- tempfile(fileext = ".db")
  file.create(test_db)

  result <- initialize_encrypted_database(db_path = test_db, overwrite = FALSE)

  expect_false(result$success)
  expect_match(result$error, "already exists")

  unlink(test_db)
})

test_that("initialize_encrypted_database overwrites when requested", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  file.create(test_db)
  old_size <- file.size(test_db)

  result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)

  expect_true(result$success)
  expect_true(file.exists(test_db))

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("connect_encrypted_db connects to initialized database", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  expect_true(init_result$success)

  conn <- connect_encrypted_db(db_path = test_db)

  expect_s4_class(conn, "SQLiteConnection")
  expect_true(DBI::dbIsValid(conn))

  DBI::dbDisconnect(conn)
  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("connect_encrypted_db fails for non-existent database", {
  test_db <- tempfile(fileext = ".db")
  key <- generate_db_key()
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  Sys.setenv(DB_ENCRYPTION_KEY = key)

  expect_error(connect_encrypted_db(db_path = test_db), "not found")

  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 5: Encryption Functionality
# =============================================================================

test_that("test_encryption verifies SQLCipher is working", {
  skip_if_not(has_sqlcipher_support(), "SQLCipher not compiled into RSQLite")

  key <- generate_db_key()
  test_db <- tempfile(fileext = ".db")

  result <- test_encryption(test_db, key)

  expect_true(result)
  expect_false(file.exists(test_db))
})

test_that("encrypted database content is not readable as plaintext", {
  skip_if_not(has_sqlcipher_support(), "SQLCipher not compiled into RSQLite")

  test_db <- tempfile(fileext = ".db")
  key <- generate_db_key()

  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = key)
  test_data <- data.frame(
    id = 1:5,
    secret = c("CONFIDENTIAL", "PRIVATE", "SENSITIVE", "SECRET", "CLASSIFIED")
  )
  DBI::dbWriteTable(conn, "secrets", test_data, overwrite = TRUE)
  DBI::dbDisconnect(conn)

  file_bytes <- readBin(test_db, "raw", n = file.size(test_db))
  file_text <- tryCatch(rawToChar(file_bytes), error = function(e) "")

  expect_false(grepl("CONFIDENTIAL", file_text, fixed = TRUE))
  expect_false(grepl("PRIVATE", file_text, fixed = TRUE))
  expect_false(grepl("SENSITIVE", file_text, fixed = TRUE))

  unlink(test_db)
})

test_that("data is readable with correct encryption key", {
  test_db <- tempfile(fileext = ".db")
  key <- generate_db_key()

  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = key)
  test_data <- data.frame(id = 1:3, value = c("alpha", "beta", "gamma"))
  DBI::dbWriteTable(conn, "test_table", test_data, overwrite = TRUE)
  DBI::dbDisconnect(conn)

  conn2 <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = key)
  retrieved <- DBI::dbReadTable(conn2, "test_table")
  DBI::dbDisconnect(conn2)

  expect_equal(nrow(retrieved), 3)
  expect_equal(retrieved$value, c("alpha", "beta", "gamma"))

  unlink(test_db)
})

# =============================================================================
# Test Section 6: Database Verification
# =============================================================================

test_that("verify_database_encryption confirms encryption status", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  expect_true(init_result$success)

  verification <- verify_database_encryption(db_path = test_db)

  expect_true(verification$connection_works)
  expect_true(verification$data_intact)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 7: Migration Functions
# =============================================================================

test_that("prepare_migration validates database and creates backup", {
  test_db <- tempfile(fileext = ".db")
  backup_dir <- file.path(tempdir(), "test_backups")

  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  DBI::dbWriteTable(conn, "test_data", data.frame(id = 1:10, value = letters[1:10]))
  DBI::dbDisconnect(conn)

  result <- prepare_migration(test_db, backup_dir = backup_dir)

  expect_true(result$valid)
  expect_true(file.exists(result$backup_path))
  expect_equal(result$total_records, 10)
  expect_true("test_data" %in% result$tables)

  unlink(test_db)
  unlink(backup_dir, recursive = TRUE)
})

test_that("prepare_migration fails for non-existent database", {
  result <- prepare_migration("/non/existent/database.db")

  expect_false(result$valid)
  expect_match(result$error, "not found")
})

test_that("migrate_to_encrypted converts unencrypted database", {
  old_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  backup_dir <- file.path(tempdir(), "migration_backups")

  conn <- DBI::dbConnect(RSQLite::SQLite(), old_db)
  DBI::dbWriteTable(conn, "patients", data.frame(
    id = 1:5,
    name = c("Alice", "Bob", "Carol", "David", "Eve")
  ))
  DBI::dbDisconnect(conn)

  result <- migrate_to_encrypted(
    old_db_path = old_db,
    backup_dir = backup_dir
  )

  expect_true(result$success)
  expect_equal(result$records_migrated, 5)
  expect_true(result$integrity_verified)
  expect_true(file.exists(result$new_path))

  unlink(old_db)
  unlink(result$new_path)
  unlink(backup_dir, recursive = TRUE)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("verify_migration confirms data integrity after migration", {
  skip_if_not(has_sqlcipher_support(), "SQLCipher required for migration verification")

  old_db <- tempfile(fileext = ".db")
  backup_dir <- file.path(tempdir(), "verify_backups")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  conn <- DBI::dbConnect(RSQLite::SQLite(), old_db)
  test_data <- data.frame(id = 1:20, value = runif(20))
  DBI::dbWriteTable(conn, "measurements", test_data)
  DBI::dbDisconnect(conn)

  migration_result <- migrate_to_encrypted(
    old_db_path = old_db,
    backup_dir = backup_dir
  )
  expect_true(migration_result$success)

  verification <- verify_migration(old_db, migration_result$new_path)

  expect_true(verification$valid)
  expect_true(verification$tables_match)
  expect_true(verification$record_counts_match)
  expect_equal(verification$data_integrity, "100%")

  unlink(old_db)
  unlink(migration_result$new_path)
  unlink(backup_dir, recursive = TRUE)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("rollback_migration restores from backup", {
  backup_path <- tempfile(fileext = ".db")
  restore_path <- tempfile(fileext = ".db")

  conn <- DBI::dbConnect(RSQLite::SQLite(), backup_path)
  DBI::dbWriteTable(conn, "original", data.frame(id = 1:3))
  DBI::dbDisconnect(conn)

  result <- rollback_migration(backup_path, restore_to = restore_path)

  expect_true(result)
  expect_true(file.exists(restore_path))

  conn <- DBI::dbConnect(RSQLite::SQLite(), restore_path)
  data <- DBI::dbReadTable(conn, "original")
  DBI::dbDisconnect(conn)
  expect_equal(nrow(data), 3)

  unlink(backup_path)
  unlink(restore_path)
})

# =============================================================================
# Test Section 8: Secure Export
# =============================================================================

test_that("export_encrypted_data creates CSV file", {
  test_db <- tempfile(fileext = ".db")
  export_dir <- file.path(tempdir(), "test_exports")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  expect_true(init_result$success)

  conn <- connect_encrypted_db(db_path = test_db)
  DBI::dbWriteTable(conn, "export_test", data.frame(
    id = 1:5,
    value = c("A", "B", "C", "D", "E")
  ))
  DBI::dbDisconnect(conn)

  export_path <- suppressWarnings(export_encrypted_data(
    query = "SELECT * FROM export_test",
    format = "csv",
    export_dir = export_dir,
    db_path = test_db
  ))

  expect_true(file.exists(export_path))
  expect_match(export_path, "\\.csv$")

  exported_data <- read.csv(export_path)
  expect_equal(nrow(exported_data), 5)

  unlink(test_db)
  unlink(export_dir, recursive = TRUE)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("export_encrypted_data creates integrity hash file", {
  test_db <- tempfile(fileext = ".db")
  export_dir <- file.path(tempdir(), "hash_exports")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  expect_true(init_result$success)

  conn <- connect_encrypted_db(db_path = test_db)
  DBI::dbWriteTable(conn, "hash_test", data.frame(id = 1:3))
  DBI::dbDisconnect(conn)

  export_path <- suppressWarnings(export_encrypted_data(
    query = "SELECT * FROM hash_test",
    format = "csv",
    include_hash = TRUE,
    export_dir = export_dir,
    db_path = test_db
  ))

  hash_file <- paste0(export_path, ".sha256")
  expect_true(file.exists(hash_file))

  hash_content <- readLines(hash_file)
  expect_match(hash_content, "^[0-9a-f]{64}$")

  unlink(test_db)
  unlink(export_dir, recursive = TRUE)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("verify_exported_data detects valid exports", {
  test_file <- tempfile(fileext = ".csv")
  hash_file <- paste0(test_file, ".sha256")

  write.csv(data.frame(id = 1:5), test_file, row.names = FALSE)

  file_content <- readBin(test_file, "raw", file.size(test_file))
  file_hash <- digest::digest(file_content, algo = "sha256")
  writeLines(file_hash, hash_file)

  result <- verify_exported_data(test_file, hash_file)

  expect_true(result$valid)
  expect_equal(result$file_hash, result$stored_hash)

 unlink(test_file)
  unlink(hash_file)
})

test_that("verify_exported_data detects tampered files", {
  test_file <- tempfile(fileext = ".csv")
  hash_file <- paste0(test_file, ".sha256")

  write.csv(data.frame(id = 1:5), test_file, row.names = FALSE)

  file_content <- readBin(test_file, "raw", file.size(test_file))
  file_hash <- digest::digest(file_content, algo = "sha256")
  writeLines(file_hash, hash_file)

  write.csv(data.frame(id = 1:10), test_file, row.names = FALSE)

  result <- verify_exported_data(test_file, hash_file)

  expect_false(result$valid)
  expect_false(result$file_hash == result$stored_hash)

  unlink(test_file)
  unlink(hash_file)
})

# =============================================================================
# Test Section 9: Audit Logging
# =============================================================================

test_that("init_audit_logging creates required tables", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  expect_true(init_result$success)

  audit_result <- init_audit_logging(db_path = test_db)

  expect_true(audit_result$success)
  expect_equal(audit_result$tables_created, 3)

  conn <- connect_encrypted_db(db_path = test_db)
  tables <- DBI::dbListTables(conn)
  DBI::dbDisconnect(conn)

  expect_true("audit_log" %in% tables)
  expect_true("audit_events" %in% tables)
  expect_true("audit_chain" %in% tables)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("log_audit_event records events to audit trail", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  expect_true(init_result$success)

  audit_init <- init_audit_logging(db_path = test_db)
  expect_true(audit_init$success)

  result <- log_audit_event(
    event_type = "INSERT",
    table_name = "test_table",
    record_id = "REC001",
    operation = "Created test record",
    details = '{"test": true}',
    user_id = "test_user",
    db_path = test_db
  )

  expect_true(result)

  conn <- connect_encrypted_db(db_path = test_db)
  audit_records <- DBI::dbGetQuery(conn, "SELECT * FROM audit_log")
  DBI::dbDisconnect(conn)

  expect_gt(nrow(audit_records), 0)
  expect_true(any(audit_records$event_type == "INSERT"))
  expect_true(any(audit_records$table_name == "test_table"))

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("log_audit_event validates event types", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_init <- init_audit_logging(db_path = test_db)

  result <- suppressWarnings(log_audit_event(
    event_type = "INVALID_EVENT",
    table_name = "test",
    operation = "test operation",
    db_path = test_db
  ))

  expect_false(result)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 10: Integration Tests
# =============================================================================

test_that("full encryption workflow: init -> write -> export -> verify", {
  test_db <- tempfile(fileext = ".db")
  export_dir <- file.path(tempdir(), "workflow_exports")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  expect_true(init_result$success)

  audit_result <- init_audit_logging(db_path = test_db)
  expect_true(audit_result$success)

  conn <- connect_encrypted_db(db_path = test_db)
  clinical_data <- data.frame(
    patient_id = paste0("PT", sprintf("%03d", 1:10)),
    visit = rep(c("Baseline", "Week4"), each = 5),
    score = sample(50:100, 10, replace = TRUE)
  )
  DBI::dbWriteTable(conn, "assessments", clinical_data)
  DBI::dbDisconnect(conn)

  export_path <- suppressWarnings(export_encrypted_data(
    query = "SELECT * FROM assessments",
    format = "csv",
    include_hash = TRUE,
    export_dir = export_dir,
    db_path = test_db
  ))

  verification <- verify_exported_data(export_path)
  expect_true(verification$valid)

  exported_data <- read.csv(export_path)
  expect_equal(nrow(exported_data), 10)
  expect_true(all(c("patient_id", "visit", "score") %in% names(exported_data)))

  unlink(test_db)
  unlink(export_dir, recursive = TRUE)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("migration workflow preserves all data integrity", {
  skip_if_not(has_sqlcipher_support(), "SQLCipher required for migration verification")

  unencrypted_db <- tempfile(fileext = ".db")
  backup_dir <- file.path(tempdir(), "migration_test_backups")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  conn <- DBI::dbConnect(RSQLite::SQLite(), unencrypted_db)
  original_data <- data.frame(
    subject_id = paste0("SUBJ", 1:100),
    age = sample(18:80, 100, replace = TRUE),
    gender = sample(c("M", "F"), 100, replace = TRUE),
    score = rnorm(100, mean = 50, sd = 10)
  )
  DBI::dbWriteTable(conn, "clinical_trial", original_data)
  DBI::dbDisconnect(conn)

  migration_result <- migrate_to_encrypted(
    old_db_path = unencrypted_db,
    backup_dir = backup_dir
  )
  expect_true(migration_result$success)
  expect_equal(migration_result$records_migrated, 100)

  verification <- verify_migration(unencrypted_db, migration_result$new_path)
  expect_true(verification$valid)
  expect_equal(verification$data_integrity, "100%")

  conn <- connect_encrypted_db(db_path = migration_result$new_path)
  migrated_data <- DBI::dbReadTable(conn, "clinical_trial")
  DBI::dbDisconnect(conn)

  expect_equal(nrow(migrated_data), 100)
  expect_equal(sort(migrated_data$subject_id), sort(original_data$subject_id))

  unlink(unencrypted_db)
  unlink(migration_result$new_path)
  unlink(backup_dir, recursive = TRUE)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 11: Performance Tests
# =============================================================================

test_that("encryption adds acceptable overhead (<5% for queries)", {
  skip_on_cran()

  unencrypted_db <- tempfile(fileext = ".db")
  encrypted_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  conn_plain <- DBI::dbConnect(RSQLite::SQLite(), unencrypted_db)
  large_data <- data.frame(
    id = 1:1000,
    value = rnorm(1000),
    category = sample(LETTERS[1:5], 1000, replace = TRUE)
  )
  DBI::dbWriteTable(conn_plain, "benchmark", large_data)

  plain_start <- Sys.time()
  for (i in 1:100) {
    DBI::dbGetQuery(conn_plain, "SELECT * FROM benchmark WHERE category = 'A'")
  }
  plain_time <- as.numeric(difftime(Sys.time(), plain_start, units = "secs"))
  DBI::dbDisconnect(conn_plain)

  key <- generate_db_key()
  Sys.setenv(DB_ENCRYPTION_KEY = key)
  conn_enc <- DBI::dbConnect(RSQLite::SQLite(), encrypted_db, key = key)
  DBI::dbWriteTable(conn_enc, "benchmark", large_data)

  enc_start <- Sys.time()
  for (i in 1:100) {
    DBI::dbGetQuery(conn_enc, "SELECT * FROM benchmark WHERE category = 'A'")
  }
  enc_time <- as.numeric(difftime(Sys.time(), enc_start, units = "secs"))
  DBI::dbDisconnect(conn_enc)

  overhead_pct <- ((enc_time - plain_time) / plain_time) * 100
  expect_lt(overhead_pct, 50)

  unlink(unencrypted_db)
  unlink(encrypted_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("large dataset migration completes successfully (10K+ records)", {
  skip_on_cran()

  large_db <- tempfile(fileext = ".db")
  backup_dir <- file.path(tempdir(), "large_migration_backup")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  conn <- DBI::dbConnect(RSQLite::SQLite(), large_db)
  large_data <- data.frame(
    id = 1:10000,
    timestamp = Sys.time() + (1:10000),
    value = rnorm(10000),
    category = sample(letters, 10000, replace = TRUE)
  )
  DBI::dbWriteTable(conn, "large_table", large_data)
  DBI::dbDisconnect(conn)

  migration_result <- migrate_to_encrypted(
    old_db_path = large_db,
    backup_dir = backup_dir
  )

  expect_true(migration_result$success)
  expect_equal(migration_result$records_migrated, 10000)

  new_conn <- connect_encrypted_db(db_path = migration_result$new_path)
  new_tables <- DBI::dbListTables(new_conn)
  expect_true("large_table" %in% new_tables)
  migrated_count <- DBI::dbGetQuery(new_conn, "SELECT COUNT(*) AS n FROM large_table")$n
  expect_equal(migrated_count, 10000)
  DBI::dbDisconnect(new_conn)

  unlink(large_db)
  unlink(migration_result$new_path)
  unlink(backup_dir, recursive = TRUE)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 12: Security Tests
# =============================================================================

test_that("database file header is encrypted (no SQLite signature)", {
  skip_if_not(has_sqlcipher_support(), "SQLCipher not compiled into RSQLite")

  test_db <- tempfile(fileext = ".db")
  key <- generate_db_key()

  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = key)
  DBI::dbWriteTable(conn, "test", data.frame(id = 1))
  DBI::dbDisconnect(conn)

  header_bytes <- readBin(test_db, "raw", n = 16)
  sqlite_sig <- as.raw(c(0x53, 0x51, 0x4c, 0x69, 0x74, 0x65))
  expect_false(identical(header_bytes[1:6], sqlite_sig))

  unlink(test_db)
})

test_that("key is not stored in plaintext in database file", {
  test_db <- tempfile(fileext = ".db")
  key <- generate_db_key()

  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = key)
  DBI::dbWriteTable(conn, "test", data.frame(id = 1:10))
  DBI::dbDisconnect(conn)

  file_content <- readBin(test_db, "raw", file.size(test_db))
  file_hex <- paste0(as.character(file_content), collapse = "")

  expect_false(grepl(key, file_hex, fixed = TRUE))

  unlink(test_db)
})
