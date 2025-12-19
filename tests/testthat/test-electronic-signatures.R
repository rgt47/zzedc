# Test suite for Electronic Signatures
# FDA 21 CFR Part 11 compliant electronic signature system

library(testthat)
library(DBI)
library(RSQLite)

find_pkg_root <- function() {
  candidates <- c(
    getwd(),
    file.path(getwd(), "..", ".."),
    Sys.getenv("ZZEDC_PKG_ROOT", unset = NA)
  )
  for (path in candidates) {
    if (!is.na(path) && file.exists(file.path(path, "R", "electronic_signatures.R"))) {
      return(normalizePath(path))
    }
  }
  stop("Could not find package root directory")
}

pkg_root <- find_pkg_root()
source(file.path(pkg_root, "R", "encryption_utils.R"))
source(file.path(pkg_root, "R", "db_connection.R"))
source(file.path(pkg_root, "R", "audit_logging.R"))
source(file.path(pkg_root, "R", "electronic_signatures.R"))

# =============================================================================
# Test Setup
# =============================================================================

setup_test_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") {
    Sys.setenv("ZZEDC_OLD_KEY" = old_key)
  }

  test_db <- tempfile(fileext = ".db")
  init_result <- initialize_encrypted_database(db_path = test_db,
                                                overwrite = TRUE)
  if (!init_result$success) {
    stop("Failed to initialize database: ", init_result$error)
  }

  audit_result <- init_audit_logging(db_path = test_db)
  sig_result <- init_electronic_signatures(db_path = test_db)

  conn <- connect_encrypted_db(db_path = test_db)
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS test_records (
      id INTEGER PRIMARY KEY,
      subject_id TEXT,
      data_value TEXT,
      status TEXT
    )
  ")
  DBI::dbExecute(conn, "
    INSERT INTO test_records (subject_id, data_value, status)
    VALUES ('S001', 'Test Data 1', 'draft'),
           ('S002', 'Test Data 2', 'draft'),
           ('S003', 'Test Data 3', 'completed')
  ")
  DBI::dbDisconnect(conn)

  test_db
}

cleanup_test_db <- function(test_db) {
  if (file.exists(test_db)) {
    unlink(test_db)
  }
  old_key <- Sys.getenv("ZZEDC_OLD_KEY")
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    Sys.unsetenv("ZZEDC_OLD_KEY")
  }
}

get_test_password_hash <- function(password = "testpassword123") {
  digest::digest(password, algo = "sha256")
}

# =============================================================================
# Initialization Tests
# =============================================================================

test_that("init_electronic_signatures creates required tables", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  conn <- connect_encrypted_db(db_path = test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  tables <- DBI::dbListTables(conn)
  expect_true("electronic_signatures" %in% tables)
  expect_true("signature_attempts" %in% tables)
  expect_true("signature_requirements" %in% tables)
  expect_true("signature_delegations" %in% tables)
})

test_that("get_signature_meanings returns valid meanings", {
  meanings <- get_signature_meanings()

  expect_type(meanings, "list")
  expect_true(length(meanings) >= 8)
  expect_true("CREATED_BY" %in% names(meanings))
  expect_true("REVIEWED_BY" %in% names(meanings))
  expect_true("APPROVED_BY" %in% names(meanings))
  expect_true("VERIFIED_BY" %in% names(meanings))
})

test_that("get_signature_statement returns correct statement", {
  statement <- get_signature_statement("APPROVED_BY")

  expect_type(statement, "character")
  expect_true(nchar(statement) > 10)
  expect_true(grepl("approve", statement, ignore.case = TRUE))
})

# =============================================================================
# Signature Application Tests
# =============================================================================

test_that("apply_electronic_signature creates valid signature", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  result <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "CREATED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(!is.null(result$signature_id))
  expect_true(!is.null(result$signature_code))
  expect_true(grepl("^SIG", result$signature_code))
  expect_true(nchar(result$signature_hash) == 64)
})

test_that("apply_electronic_signature fails with wrong password", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password_hash <- get_test_password_hash("correctpassword")

  result <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "CREATED_BY",
    password = "wrongpassword",
    password_hash = password_hash,
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Password verification failed", result$error))

  conn <- connect_encrypted_db(db_path = test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  attempts <- DBI::dbGetQuery(conn, "
    SELECT * FROM signature_attempts WHERE attempt_result = 'FAILED_PASSWORD'
  ")
  expect_equal(nrow(attempts), 1)
})

test_that("apply_electronic_signature fails with invalid meaning", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  result <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "INVALID_MEANING",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  expect_false(result$success)
  expect_true(grepl("Invalid signature meaning", result$error))
})

test_that("multiple signatures create hash chain", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  sig1 <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "CREATED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  sig2 <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user002",
    signer_full_name = "Jane Doe",
    signature_meaning = "REVIEWED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  expect_true(sig1$success)
  expect_true(sig2$success)
  expect_true(sig1$signature_hash != sig2$signature_hash)

  conn <- connect_encrypted_db(db_path = test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  sigs <- DBI::dbGetQuery(conn, "
    SELECT signature_hash, previous_signature_hash
    FROM electronic_signatures
    ORDER BY signature_id ASC
  ")

  expect_equal(sigs$previous_signature_hash[1], "GENESIS")
  expect_equal(sigs$previous_signature_hash[2], sigs$signature_hash[1])
})

# =============================================================================
# Signature Verification Tests
# =============================================================================

test_that("verify_electronic_signature validates signature", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  sig_result <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "CREATED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  verify_result <- verify_electronic_signature(
    signature_code = sig_result$signature_code,
    db_path = test_db
  )

  expect_true(verify_result$success)
  expect_true(verify_result$is_valid)
  expect_true(verify_result$record_unchanged)
})

test_that("verify_electronic_signature detects invalid signature", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  verify_result <- verify_electronic_signature(
    signature_code = "SIG_NONEXISTENT_12345",
    db_path = test_db
  )

  expect_true(verify_result$success)
  expect_false(verify_result$is_valid)
  expect_true(grepl("not found", verify_result$error))
})

test_that("get_record_signatures returns all signatures", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "CREATED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user002",
    signer_full_name = "Jane Doe",
    signature_meaning = "REVIEWED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  signatures <- get_record_signatures(
    table_name = "test_records",
    record_id = "1",
    db_path = test_db
  )

  expect_equal(nrow(signatures), 2)
  expect_true("CREATED_BY" %in% signatures$signature_meaning)
  expect_true("REVIEWED_BY" %in% signatures$signature_meaning)
})

# =============================================================================
# Signature Invalidation Tests
# =============================================================================

test_that("invalidate_signature marks signature as invalid", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  sig_result <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "CREATED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  invalid_result <- invalidate_signature(
    signature_code = sig_result$signature_code,
    invalidated_by = "admin",
    reason = "Signature applied in error - wrong record selected",
    db_path = test_db
  )

  expect_true(invalid_result$success)

  verify_result <- verify_electronic_signature(
    signature_code = sig_result$signature_code,
    db_path = test_db
  )

  expect_false(verify_result$is_valid)
  expect_true(grepl("invalidated", verify_result$error))
})

test_that("invalidate_signature requires reason", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  sig_result <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "CREATED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  invalid_result <- invalidate_signature(
    signature_code = sig_result$signature_code,
    invalidated_by = "admin",
    reason = "short",
    db_path = test_db
  )

  expect_false(invalid_result$success)
  expect_true(grepl("min 10 characters", invalid_result$error))
})

# =============================================================================
# Statistics and Reporting Tests
# =============================================================================

test_that("get_signature_statistics returns correct counts", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  for (i in 1:5) {
    apply_electronic_signature(
      table_name = "test_records",
      record_id = as.character(i %% 3 + 1),
      signer_user_id = paste0("user00", i),
      signer_full_name = paste("User", i),
      signature_meaning = c("CREATED_BY", "REVIEWED_BY", "APPROVED_BY")[i %% 3 + 1],
      password = password,
      password_hash = password_hash,
      db_path = test_db
    )
  }

  stats <- get_signature_statistics(db_path = test_db)

  expect_true(stats$success)
  expect_equal(stats$summary$total_signatures, 5)
  expect_equal(stats$summary$valid_signatures, 5)
  expect_true(nrow(stats$by_meaning) >= 1)
  expect_true(nrow(stats$by_table) >= 1)
})

test_that("generate_signature_report creates text report", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  for (i in 1:3) {
    apply_electronic_signature(
      table_name = "test_records",
      record_id = as.character(i),
      signer_user_id = paste0("user00", i),
      signer_full_name = paste("User", i),
      signature_meaning = "CREATED_BY",
      password = password,
      password_hash = password_hash,
      db_path = test_db
    )
  }

  report_file <- tempfile(fileext = ".txt")
  on.exit(unlink(report_file), add = TRUE)

  result <- generate_signature_report(
    output_file = report_file,
    format = "txt",
    organization = "Test Organization",
    prepared_by = "Test User",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(report_file))
  expect_equal(result$signature_count, 3)

  content <- readLines(report_file)
  expect_true(any(grepl("ELECTRONIC SIGNATURE REPORT", content)))
  expect_true(any(grepl("Test Organization", content)))
  expect_true(any(grepl("21 CFR Part 11", content)))
})

test_that("generate_signature_report creates JSON report", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "user001",
    signer_full_name = "John Smith",
    signature_meaning = "CREATED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )

  report_file <- tempfile(fileext = ".json")
  on.exit(unlink(report_file), add = TRUE)

  result <- generate_signature_report(
    output_file = report_file,
    format = "json",
    organization = "Test Organization",
    db_path = test_db
  )

  expect_true(result$success)
  expect_true(file.exists(report_file))

  json_content <- jsonlite::read_json(report_file)
  expect_equal(json_content$organization, "Test Organization")
  expect_equal(json_content$report_type, "Electronic Signature Report")
})

# =============================================================================
# Chain Integrity Tests
# =============================================================================

test_that("verify_signature_chain detects valid chain", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  for (i in 1:5) {
    apply_electronic_signature(
      table_name = "test_records",
      record_id = as.character(i %% 3 + 1),
      signer_user_id = paste0("user00", i),
      signer_full_name = paste("User", i),
      signature_meaning = "CREATED_BY",
      password = password,
      password_hash = password_hash,
      db_path = test_db
    )
  }

  result <- verify_signature_chain(db_path = test_db)

  expect_true(result$success)
  expect_true(result$is_valid)
  expect_equal(result$total_signatures, 5)
  expect_equal(length(result$invalid_records), 0)
})

# =============================================================================
# Integration Tests
# =============================================================================

test_that("complete signature workflow works end-to-end", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password <- "testpassword123"
  password_hash <- get_test_password_hash(password)

  created_sig <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "coordinator",
    signer_full_name = "Research Coordinator",
    signature_meaning = "CREATED_BY",
    password = password,
    password_hash = password_hash,
    ip_address = "192.168.1.100",
    session_id = "SESSION123",
    db_path = test_db
  )
  expect_true(created_sig$success)

  reviewed_sig <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "data_manager",
    signer_full_name = "Data Manager",
    signature_meaning = "REVIEWED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )
  expect_true(reviewed_sig$success)

  approved_sig <- apply_electronic_signature(
    table_name = "test_records",
    record_id = "1",
    signer_user_id = "pi",
    signer_full_name = "Principal Investigator",
    signature_meaning = "APPROVED_BY",
    password = password,
    password_hash = password_hash,
    db_path = test_db
  )
  expect_true(approved_sig$success)

  signatures <- get_record_signatures(
    table_name = "test_records",
    record_id = "1",
    db_path = test_db
  )
  expect_equal(nrow(signatures), 3)

  meanings <- signatures$signature_meaning
  expect_true("CREATED_BY" %in% meanings)
  expect_true("REVIEWED_BY" %in% meanings)
  expect_true("APPROVED_BY" %in% meanings)

  for (sig_code in signatures$signature_code) {
    verify_result <- verify_electronic_signature(sig_code, db_path = test_db)
    expect_true(verify_result$is_valid)
  }

  chain_result <- verify_signature_chain(db_path = test_db)
  expect_true(chain_result$is_valid)

  stats <- get_signature_statistics(db_path = test_db)
  expect_equal(stats$summary$total_signatures, 3)
  expect_equal(stats$summary$valid_signatures, 3)
})

test_that("failed signature attempts are logged", {
  skip_if_not_installed("RSQLite")

  test_db <- setup_test_db()
  on.exit(cleanup_test_db(test_db), add = TRUE)

  password_hash <- get_test_password_hash("correctpassword")

  for (i in 1:3) {
    apply_electronic_signature(
      table_name = "test_records",
      record_id = "1",
      signer_user_id = "user001",
      signer_full_name = "John Smith",
      signature_meaning = "CREATED_BY",
      password = "wrongpassword",
      password_hash = password_hash,
      db_path = test_db
    )
  }

  conn <- connect_encrypted_db(db_path = test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  attempts <- DBI::dbGetQuery(conn, "
    SELECT * FROM signature_attempts WHERE attempt_result = 'FAILED_PASSWORD'
  ")

  expect_equal(nrow(attempts), 3)
  expect_true(all(attempts$user_id == "user001"))
})
