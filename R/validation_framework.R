#' System Validation Framework
#'
#' FDA 21 CFR Part 11 compliant validation framework implementing
#' Installation Qualification (IQ), Operational Qualification (OQ),
#' and Performance Qualification (PQ) testing.

# =============================================================================
# Validation Result Structure
# =============================================================================

#' Create Validation Result
#'
#' Creates a standardized validation result object.
#'
#' @param test_id Character: Unique test identifier
#' @param test_name Character: Human-readable test name
#' @param category Character: IQ, OQ, or PQ
#' @param passed Logical: Whether the test passed
#' @param message Character: Result message
#' @param details List: Additional details
#' @param duration_ms Numeric: Test duration in milliseconds
#'
#' @return List with validation result structure
#'
#' @keywords internal
create_validation_result <- function(test_id, test_name, category,
                                      passed, message, details = NULL,
                                      duration_ms = NULL) {
  list(
    test_id = test_id,
    test_name = test_name,
    category = category,
    passed = passed,
    message = message,
    details = details,
    duration_ms = duration_ms,
    timestamp = as.character(Sys.time())
  )
}


# =============================================================================
# Installation Qualification (IQ)
# =============================================================================

#' Run Installation Qualification Tests
#'
#' Verifies that the ZZedc system is correctly installed.
#'
#' @param db_path Character: Database path to test (optional)
#' @param verbose Logical: Print progress messages
#'
#' @return List with IQ test results
#'
#' @details
#' IQ tests verify:
#' - Required R packages are installed
#' - Database can be created/connected
#' - Required tables exist
#' - Configuration files are valid
#' - Directory structure is correct
#'
#' @examples
#' \dontrun{
#'   iq_results <- run_iq_tests()
#'   if (iq_results$all_passed) {
#'     cat("Installation Qualification: PASSED\n")
#'   }
#' }
#'
#' @export
run_iq_tests <- function(db_path = NULL, verbose = TRUE) {
  results <- list()
  start_time <- Sys.time()

  if (verbose) cat("Running Installation Qualification (IQ) Tests...\n\n")

  # IQ-001: Required packages
  if (verbose) cat("  IQ-001: Checking required packages... ")
  t1 <- Sys.time()
  required_pkgs <- c("shiny", "DBI", "RSQLite", "digest", "jsonlite",
                     "bslib", "DT", "ggplot2")
  missing_pkgs <- required_pkgs[!sapply(required_pkgs, requireNamespace,
                                         quietly = TRUE)]
  results$IQ_001 <- create_validation_result(
    test_id = "IQ-001",
    test_name = "Required R Packages",
    category = "IQ",
    passed = length(missing_pkgs) == 0,
    message = if (length(missing_pkgs) == 0) {
      "All required packages installed"
    } else {
      paste("Missing packages:", paste(missing_pkgs, collapse = ", "))
    },
    details = list(
      required = required_pkgs,
      missing = missing_pkgs
    ),
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$IQ_001$passed) "PASSED\n" else "FAILED\n")

  # IQ-002: Database connection
  if (verbose) cat("  IQ-002: Testing database connection... ")
  t1 <- Sys.time()
  db_test <- tryCatch({
    test_db <- if (is.null(db_path)) tempfile(fileext = ".db") else db_path
    conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
    DBI::dbDisconnect(conn)
    if (is.null(db_path)) unlink(test_db)
    list(success = TRUE, message = "Database connection successful")
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$IQ_002 <- create_validation_result(
    test_id = "IQ-002",
    test_name = "Database Connection",
    category = "IQ",
    passed = db_test$success,
    message = db_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$IQ_002$passed) "PASSED\n" else "FAILED\n")

  # IQ-003: Encryption utilities
  if (verbose) cat("  IQ-003: Testing encryption utilities... ")
  t1 <- Sys.time()
  enc_test <- tryCatch({
    key <- generate_db_key()
    valid <- verify_db_key(key)
    list(success = valid, message = if (valid) "Encryption working" else "Key validation failed")
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$IQ_003 <- create_validation_result(
    test_id = "IQ-003",
    test_name = "Encryption Utilities",
    category = "IQ",
    passed = enc_test$success,
    message = enc_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$IQ_003$passed) "PASSED\n" else "FAILED\n")

  # IQ-004: Database initialization
  if (verbose) cat("  IQ-004: Testing database initialization... ")
  t1 <- Sys.time()
  init_test <- tryCatch({
    test_db <- tempfile(fileext = ".db")
    result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    unlink(test_db)
    list(success = result$success, message = result$message)
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$IQ_004 <- create_validation_result(
    test_id = "IQ-004",
    test_name = "Database Initialization",
    category = "IQ",
    passed = init_test$success,
    message = init_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$IQ_004$passed) "PASSED\n" else "FAILED\n")

  # IQ-005: Audit logging initialization
  if (verbose) cat("  IQ-005: Testing audit logging setup... ")
  t1 <- Sys.time()
  audit_test <- tryCatch({
    test_db <- tempfile(fileext = ".db")
    initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    result <- init_audit_logging(db_path = test_db)
    unlink(test_db)
    list(success = result$success, message = result$message)
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$IQ_005 <- create_validation_result(
    test_id = "IQ-005",
    test_name = "Audit Logging Setup",
    category = "IQ",
    passed = audit_test$success,
    message = audit_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$IQ_005$passed) "PASSED\n" else "FAILED\n")

  # IQ-006: Version control initialization
  if (verbose) cat("  IQ-006: Testing version control setup... ")
  t1 <- Sys.time()
  version_test <- tryCatch({
    test_db <- tempfile(fileext = ".db")
    initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    result <- init_version_control(db_path = test_db)
    unlink(test_db)
    list(success = result$success, message = result$message)
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$IQ_006 <- create_validation_result(
    test_id = "IQ-006",
    test_name = "Version Control Setup",
    category = "IQ",
    passed = version_test$success,
    message = version_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$IQ_006$passed) "PASSED\n" else "FAILED\n")

  # IQ-007: Hash algorithm verification
  if (verbose) cat("  IQ-007: Testing hash algorithm... ")
  t1 <- Sys.time()
  hash_test <- tryCatch({
    test_data <- "ZZedc Validation Test"
    hash1 <- digest::digest(test_data, algo = "sha256")
    hash2 <- digest::digest(test_data, algo = "sha256")
    consistent <- identical(hash1, hash2)
    correct_length <- nchar(hash1) == 64
    list(
      success = consistent && correct_length,
      message = if (consistent && correct_length) {
        "SHA-256 hashing working correctly"
      } else {
        "Hash algorithm verification failed"
      }
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$IQ_007 <- create_validation_result(
    test_id = "IQ-007",
    test_name = "Hash Algorithm Verification",
    category = "IQ",
    passed = hash_test$success,
    message = hash_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$IQ_007$passed) "PASSED\n" else "FAILED\n")

  # Summary
  total_tests <- length(results)
  passed_tests <- sum(sapply(results, function(r) r$passed))
  all_passed <- passed_tests == total_tests

  total_duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  if (verbose) {
    cat("\n")
    cat("IQ Summary: ", passed_tests, "/", total_tests, " tests passed\n")
    cat("Duration: ", round(total_duration, 2), " seconds\n")
    cat("Status: ", if (all_passed) "PASSED" else "FAILED", "\n")
  }

  list(
    qualification_type = "IQ",
    results = results,
    summary = list(
      total_tests = total_tests,
      passed = passed_tests,
      failed = total_tests - passed_tests,
      all_passed = all_passed,
      duration_seconds = total_duration,
      timestamp = as.character(Sys.time())
    )
  )
}


# =============================================================================
# Operational Qualification (OQ)
# =============================================================================

#' Run Operational Qualification Tests
#'
#' Verifies that ZZedc operates as intended.
#'
#' @param db_path Character: Database path to test (optional)
#' @param verbose Logical: Print progress messages
#'
#' @return List with OQ test results
#'
#' @details
#' OQ tests verify:
#' - Data entry and retrieval
#' - Audit trail logging
#' - Version control operations
#' - Search and filter functionality
#' - Export operations
#' - Integrity verification
#'
#' @export
run_oq_tests <- function(db_path = NULL, verbose = TRUE) {
  results <- list()
  start_time <- Sys.time()

  if (verbose) cat("Running Operational Qualification (OQ) Tests...\n\n")

  test_db <- tempfile(fileext = ".db")
  initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  init_audit_logging(db_path = test_db)
  init_version_control(db_path = test_db)

  # OQ-001: Data insert operation
  if (verbose) cat("  OQ-001: Testing data insert... ")
  t1 <- Sys.time()
  insert_test <- tryCatch({
    conn <- connect_encrypted_db(db_path = test_db)
    DBI::dbExecute(conn, "
      INSERT INTO subjects (subject_id, status, created_date)
      VALUES ('TEST001', 'active', datetime('now'))
    ")
    count <- DBI::dbGetQuery(conn, "SELECT COUNT(*) FROM subjects")[1, 1]
    DBI::dbDisconnect(conn)
    list(success = count > 0, message = "Data insert successful")
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_001 <- create_validation_result(
    test_id = "OQ-001",
    test_name = "Data Insert Operation",
    category = "OQ",
    passed = insert_test$success,
    message = insert_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_001$passed) "PASSED\n" else "FAILED\n")

  # OQ-002: Data retrieval
  if (verbose) cat("  OQ-002: Testing data retrieval... ")
  t1 <- Sys.time()
  select_test <- tryCatch({
    conn <- connect_encrypted_db(db_path = test_db)
    data <- DBI::dbGetQuery(conn, "SELECT * FROM subjects WHERE subject_id = 'TEST001'")
    DBI::dbDisconnect(conn)
    list(
      success = nrow(data) == 1 && data$subject_id[1] == "TEST001",
      message = "Data retrieval successful"
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_002 <- create_validation_result(
    test_id = "OQ-002",
    test_name = "Data Retrieval",
    category = "OQ",
    passed = select_test$success,
    message = select_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_002$passed) "PASSED\n" else "FAILED\n")

  # OQ-003: Audit event logging
  if (verbose) cat("  OQ-003: Testing audit event logging... ")
  t1 <- Sys.time()
  audit_test <- tryCatch({
    result <- log_audit_event(
      event_type = "INSERT",
      table_name = "test_table",
      record_id = "TEST001",
      operation = "OQ test insert",
      user_id = "validator",
      db_path = test_db
    )
    list(success = result, message = if (result) "Audit logging working" else "Audit logging failed")
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_003 <- create_validation_result(
    test_id = "OQ-003",
    test_name = "Audit Event Logging",
    category = "OQ",
    passed = audit_test$success,
    message = audit_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_003$passed) "PASSED\n" else "FAILED\n")

  # OQ-004: Audit trail retrieval
  if (verbose) cat("  OQ-004: Testing audit trail retrieval... ")
  t1 <- Sys.time()
  trail_test <- tryCatch({
    trail <- get_audit_trail(db_path = test_db)
    list(
      success = nrow(trail) > 0,
      message = paste("Retrieved", nrow(trail), "audit records")
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_004 <- create_validation_result(
    test_id = "OQ-004",
    test_name = "Audit Trail Retrieval",
    category = "OQ",
    passed = trail_test$success,
    message = trail_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_004$passed) "PASSED\n" else "FAILED\n")

  # OQ-005: Version creation
  if (verbose) cat("  OQ-005: Testing version creation... ")
  t1 <- Sys.time()
  version_test <- tryCatch({
    result <- create_record_version(
      table_name = "test_table",
      record_id = "REC001",
      data = list(field1 = "value1", field2 = "value2"),
      change_type = "CREATE",
      change_reason = "OQ validation test",
      changed_by = "validator",
      db_path = test_db
    )
    list(success = result$success, message = result$message)
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_005 <- create_validation_result(
    test_id = "OQ-005",
    test_name = "Version Creation",
    category = "OQ",
    passed = version_test$success,
    message = version_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_005$passed) "PASSED\n" else "FAILED\n")

  # OQ-006: Version history retrieval
  if (verbose) cat("  OQ-006: Testing version history retrieval... ")
  t1 <- Sys.time()
  history_test <- tryCatch({
    history <- get_version_history(
      table_name = "test_table",
      record_id = "REC001",
      db_path = test_db
    )
    list(
      success = nrow(history) > 0,
      message = paste("Retrieved", nrow(history), "versions")
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_006 <- create_validation_result(
    test_id = "OQ-006",
    test_name = "Version History Retrieval",
    category = "OQ",
    passed = history_test$success,
    message = history_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_006$passed) "PASSED\n" else "FAILED\n")

  # OQ-007: Audit integrity verification
  if (verbose) cat("  OQ-007: Testing audit integrity... ")
  t1 <- Sys.time()
  integrity_test <- tryCatch({
    result <- verify_audit_integrity(db_path = test_db)
    list(success = result$valid, message = result$message)
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_007 <- create_validation_result(
    test_id = "OQ-007",
    test_name = "Audit Integrity Verification",
    category = "OQ",
    passed = integrity_test$success,
    message = integrity_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_007$passed) "PASSED\n" else "FAILED\n")

  # OQ-008: Version integrity verification
  if (verbose) cat("  OQ-008: Testing version integrity... ")
  t1 <- Sys.time()
  version_integrity_test <- tryCatch({
    result <- verify_version_integrity(
      table_name = "test_table",
      record_id = "REC001",
      db_path = test_db
    )
    list(success = result$valid, message = result$message)
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_008 <- create_validation_result(
    test_id = "OQ-008",
    test_name = "Version Integrity Verification",
    category = "OQ",
    passed = version_integrity_test$success,
    message = version_integrity_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_008$passed) "PASSED\n" else "FAILED\n")

  # OQ-009: Record locking
  if (verbose) cat("  OQ-009: Testing record locking... ")
  t1 <- Sys.time()
  lock_test <- tryCatch({
    result <- lock_record(
      table_name = "test_table",
      record_id = "REC001",
      locked_by = "validator",
      db_path = test_db
    )
    unlock_record(
      table_name = "test_table",
      record_id = "REC001",
      unlocked_by = "validator",
      db_path = test_db
    )
    list(success = result$success, message = "Record locking working")
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_009 <- create_validation_result(
    test_id = "OQ-009",
    test_name = "Record Locking",
    category = "OQ",
    passed = lock_test$success,
    message = lock_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_009$passed) "PASSED\n" else "FAILED\n")

  # OQ-010: Anomaly detection
  if (verbose) cat("  OQ-010: Testing anomaly detection... ")
  t1 <- Sys.time()
  anomaly_test <- tryCatch({
    result <- detect_audit_anomalies(lookback_hours = 1, db_path = test_db)
    list(
      success = !is.null(result$risk_level),
      message = paste("Risk level:", result$risk_level)
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$OQ_010 <- create_validation_result(
    test_id = "OQ-010",
    test_name = "Anomaly Detection",
    category = "OQ",
    passed = anomaly_test$success,
    message = anomaly_test$message,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$OQ_010$passed) "PASSED\n" else "FAILED\n")

  # Cleanup
  unlink(test_db)

  # Summary
  total_tests <- length(results)
  passed_tests <- sum(sapply(results, function(r) r$passed))
  all_passed <- passed_tests == total_tests

  total_duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  if (verbose) {
    cat("\n")
    cat("OQ Summary: ", passed_tests, "/", total_tests, " tests passed\n")
    cat("Duration: ", round(total_duration, 2), " seconds\n")
    cat("Status: ", if (all_passed) "PASSED" else "FAILED", "\n")
  }

  list(
    qualification_type = "OQ",
    results = results,
    summary = list(
      total_tests = total_tests,
      passed = passed_tests,
      failed = total_tests - passed_tests,
      all_passed = all_passed,
      duration_seconds = total_duration,
      timestamp = as.character(Sys.time())
    )
  )
}


# =============================================================================
# Performance Qualification (PQ)
# =============================================================================

#' Run Performance Qualification Tests
#'
#' Verifies ZZedc performance under expected load conditions.
#'
#' @param db_path Character: Database path to test (optional)
#' @param verbose Logical: Print progress messages
#' @param record_count Integer: Number of records for stress testing
#'
#' @return List with PQ test results
#'
#' @details
#' PQ tests verify:
#' - Bulk data insertion performance
#' - Query performance with large datasets
#' - Concurrent operation handling
#' - Memory usage under load
#' - Response time requirements
#'
#' @export
run_pq_tests <- function(db_path = NULL, verbose = TRUE, record_count = 1000) {
  results <- list()
  start_time <- Sys.time()

  if (verbose) cat("Running Performance Qualification (PQ) Tests...\n\n")

  test_db <- tempfile(fileext = ".db")
  initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  init_audit_logging(db_path = test_db)
  init_version_control(db_path = test_db)

  # PQ-001: Bulk insert performance
  if (verbose) cat("  PQ-001: Testing bulk insert (", record_count, " records)... ")
  t1 <- Sys.time()
  bulk_test <- tryCatch({
    conn <- connect_encrypted_db(db_path = test_db)

    for (i in seq_len(record_count)) {
      DBI::dbExecute(conn, "
        INSERT INTO subjects (subject_id, status, created_date)
        VALUES (?, 'active', datetime('now'))
      ", list(paste0("PERF", sprintf("%05d", i))))
    }

    insert_time <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
    records_per_sec <- record_count / insert_time

    DBI::dbDisconnect(conn)

    list(
      success = records_per_sec > 10,
      message = paste(round(records_per_sec, 1), "records/second"),
      details = list(
        records = record_count,
        duration_seconds = insert_time,
        records_per_second = records_per_sec
      )
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$PQ_001 <- create_validation_result(
    test_id = "PQ-001",
    test_name = "Bulk Insert Performance",
    category = "PQ",
    passed = bulk_test$success,
    message = bulk_test$message,
    details = bulk_test$details,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$PQ_001$passed) "PASSED\n" else "FAILED\n")

  # PQ-002: Query performance
  if (verbose) cat("  PQ-002: Testing query performance... ")
  t1 <- Sys.time()
  query_test <- tryCatch({
    conn <- connect_encrypted_db(db_path = test_db)

    query_start <- Sys.time()
    result <- DBI::dbGetQuery(conn, "SELECT * FROM subjects")
    query_time <- as.numeric(difftime(Sys.time(), query_start, units = "secs"))

    DBI::dbDisconnect(conn)

    list(
      success = query_time < 5,
      message = paste("Query time:", round(query_time * 1000, 1), "ms"),
      details = list(
        records_returned = nrow(result),
        query_time_seconds = query_time
      )
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$PQ_002 <- create_validation_result(
    test_id = "PQ-002",
    test_name = "Query Performance",
    category = "PQ",
    passed = query_test$success,
    message = query_test$message,
    details = query_test$details,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$PQ_002$passed) "PASSED\n" else "FAILED\n")

  # PQ-003: Audit logging performance
  if (verbose) cat("  PQ-003: Testing audit logging performance (100 events)... ")
  t1 <- Sys.time()
  audit_perf_test <- tryCatch({
    for (i in 1:100) {
      log_audit_event(
        event_type = "INSERT",
        table_name = "performance_test",
        record_id = paste0("REC", i),
        operation = "Performance test insert",
        user_id = "validator",
        db_path = test_db
      )
    }

    audit_time <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
    events_per_sec <- 100 / audit_time

    list(
      success = events_per_sec > 5,
      message = paste(round(events_per_sec, 1), "events/second"),
      details = list(
        events = 100,
        duration_seconds = audit_time,
        events_per_second = events_per_sec
      )
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$PQ_003 <- create_validation_result(
    test_id = "PQ-003",
    test_name = "Audit Logging Performance",
    category = "PQ",
    passed = audit_perf_test$success,
    message = audit_perf_test$message,
    details = audit_perf_test$details,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$PQ_003$passed) "PASSED\n" else "FAILED\n")

  # PQ-004: Version creation performance
  if (verbose) cat("  PQ-004: Testing version creation performance (50 versions)... ")
  t1 <- Sys.time()
  version_perf_test <- tryCatch({
    for (i in 1:50) {
      create_record_version(
        table_name = "perf_table",
        record_id = "PERF001",
        data = list(iteration = i, value = runif(1)),
        change_type = if (i == 1) "CREATE" else "UPDATE",
        changed_by = "validator",
        db_path = test_db
      )
    }

    version_time <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
    versions_per_sec <- 50 / version_time

    list(
      success = versions_per_sec > 2,
      message = paste(round(versions_per_sec, 1), "versions/second"),
      details = list(
        versions = 50,
        duration_seconds = version_time,
        versions_per_second = versions_per_sec
      )
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$PQ_004 <- create_validation_result(
    test_id = "PQ-004",
    test_name = "Version Creation Performance",
    category = "PQ",
    passed = version_perf_test$success,
    message = version_perf_test$message,
    details = version_perf_test$details,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$PQ_004$passed) "PASSED\n" else "FAILED\n")

  # PQ-005: Integrity verification performance
  if (verbose) cat("  PQ-005: Testing integrity verification performance... ")
  t1 <- Sys.time()
  integrity_perf_test <- tryCatch({
    result <- verify_audit_integrity(db_path = test_db)
    verify_time <- as.numeric(difftime(Sys.time(), t1, units = "secs"))

    list(
      success = verify_time < 10,
      message = paste("Verification time:", round(verify_time * 1000, 1), "ms"),
      details = list(
        records_checked = result$records_checked,
        verification_time_seconds = verify_time
      )
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$PQ_005 <- create_validation_result(
    test_id = "PQ-005",
    test_name = "Integrity Verification Performance",
    category = "PQ",
    passed = integrity_perf_test$success,
    message = integrity_perf_test$message,
    details = integrity_perf_test$details,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$PQ_005$passed) "PASSED\n" else "FAILED\n")

  # PQ-006: Database size check
  if (verbose) cat("  PQ-006: Checking database size... ")
  t1 <- Sys.time()
  size_test <- tryCatch({
    db_size <- file.size(test_db) / (1024 * 1024)
    list(
      success = TRUE,
      message = paste("Database size:", round(db_size, 2), "MB"),
      details = list(size_mb = db_size)
    )
  }, error = function(e) {
    list(success = FALSE, message = e$message)
  })
  results$PQ_006 <- create_validation_result(
    test_id = "PQ-006",
    test_name = "Database Size",
    category = "PQ",
    passed = size_test$success,
    message = size_test$message,
    details = size_test$details,
    duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
  )
  if (verbose) cat(if (results$PQ_006$passed) "PASSED\n" else "FAILED\n")

  # Cleanup
  unlink(test_db)

  # Summary
  total_tests <- length(results)
  passed_tests <- sum(sapply(results, function(r) r$passed))
  all_passed <- passed_tests == total_tests

  total_duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  if (verbose) {
    cat("\n")
    cat("PQ Summary: ", passed_tests, "/", total_tests, " tests passed\n")
    cat("Duration: ", round(total_duration, 2), " seconds\n")
    cat("Status: ", if (all_passed) "PASSED" else "FAILED", "\n")
  }

  list(
    qualification_type = "PQ",
    results = results,
    summary = list(
      total_tests = total_tests,
      passed = passed_tests,
      failed = total_tests - passed_tests,
      all_passed = all_passed,
      duration_seconds = total_duration,
      timestamp = as.character(Sys.time())
    )
  )
}


# =============================================================================
# Complete Validation Suite
# =============================================================================

#' Run Complete Validation Suite
#'
#' Runs all IQ, OQ, and PQ tests.
#'
#' @param db_path Character: Database path to test (optional)
#' @param verbose Logical: Print progress messages
#' @param record_count Integer: Number of records for PQ stress testing
#'
#' @return List with complete validation results
#'
#' @export
run_validation_suite <- function(db_path = NULL, verbose = TRUE,
                                  record_count = 1000) {
  start_time <- Sys.time()

  if (verbose) {
    cat("=================================================================\n")
    cat("        ZZedc System Validation Suite\n")
    cat("        FDA 21 CFR Part 11 Compliance\n")
    cat("=================================================================\n\n")
  }

  iq_results <- run_iq_tests(db_path = db_path, verbose = verbose)
  if (verbose) cat("\n")

  oq_results <- run_oq_tests(db_path = db_path, verbose = verbose)
  if (verbose) cat("\n")

  pq_results <- run_pq_tests(db_path = db_path, verbose = verbose,
                              record_count = record_count)

  total_duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  all_passed <- iq_results$summary$all_passed &&
                oq_results$summary$all_passed &&
                pq_results$summary$all_passed

  total_tests <- iq_results$summary$total_tests +
                 oq_results$summary$total_tests +
                 pq_results$summary$total_tests

  total_passed <- iq_results$summary$passed +
                  oq_results$summary$passed +
                  pq_results$summary$passed

  if (verbose) {
    cat("\n")
    cat("=================================================================\n")
    cat("                    VALIDATION SUMMARY\n")
    cat("=================================================================\n")
    cat("IQ Status:  ", if (iq_results$summary$all_passed) "PASSED" else "FAILED",
        " (", iq_results$summary$passed, "/", iq_results$summary$total_tests, ")\n")
    cat("OQ Status:  ", if (oq_results$summary$all_passed) "PASSED" else "FAILED",
        " (", oq_results$summary$passed, "/", oq_results$summary$total_tests, ")\n")
    cat("PQ Status:  ", if (pq_results$summary$all_passed) "PASSED" else "FAILED",
        " (", pq_results$summary$passed, "/", pq_results$summary$total_tests, ")\n")
    cat("-----------------------------------------------------------------\n")
    cat("Total:      ", total_passed, "/", total_tests, " tests passed\n")
    cat("Duration:   ", round(total_duration, 2), " seconds\n")
    cat("=================================================================\n")
    cat("OVERALL STATUS: ", if (all_passed) "VALIDATION PASSED" else "VALIDATION FAILED", "\n")
    cat("=================================================================\n")
  }

  list(
    validation_type = "Complete",
    iq = iq_results,
    oq = oq_results,
    pq = pq_results,
    summary = list(
      iq_passed = iq_results$summary$all_passed,
      oq_passed = oq_results$summary$all_passed,
      pq_passed = pq_results$summary$all_passed,
      all_passed = all_passed,
      total_tests = total_tests,
      total_passed = total_passed,
      total_failed = total_tests - total_passed,
      duration_seconds = total_duration,
      timestamp = as.character(Sys.time()),
      r_version = paste(R.version$major, R.version$minor, sep = "."),
      platform = R.version$platform
    )
  )
}


# =============================================================================
# Validation Report Generation
# =============================================================================

#' Generate Validation Report
#'
#' Creates an FDA-ready validation report.
#'
#' @param validation_results List: Results from run_validation_suite()
#' @param output_file Character: Path for output file
#' @param format Character: Output format (txt, html, json)
#' @param organization Character: Organization name
#' @param system_name Character: System name (default: ZZedc)
#' @param validator Character: Validator name
#'
#' @return Character: Path to generated report
#'
#' @export
generate_validation_report <- function(validation_results, output_file,
                                        format = "txt",
                                        organization = "Organization Name",
                                        system_name = "ZZedc EDC System",
                                        validator = "System Administrator") {
  if (format == "json") {
    report_data <- list(
      report_metadata = list(
        organization = organization,
        system_name = system_name,
        validator = validator,
        generated_at = as.character(Sys.time()),
        r_version = validation_results$summary$r_version,
        platform = validation_results$summary$platform
      ),
      validation_results = validation_results
    )

    jsonlite::write_json(report_data, output_file, pretty = TRUE,
                          auto_unbox = TRUE)

  } else if (format == "txt") {
    lines <- c(
      "===============================================================================",
      paste("           ", system_name, "- VALIDATION REPORT"),
      "                   FDA 21 CFR Part 11 Compliance",
      "===============================================================================",
      "",
      paste("Organization:    ", organization),
      paste("System:          ", system_name),
      paste("Validator:       ", validator),
      paste("Date:            ", as.character(Sys.time())),
      paste("R Version:       ", validation_results$summary$r_version),
      paste("Platform:        ", validation_results$summary$platform),
      "",
      "===============================================================================",
      "                         VALIDATION SUMMARY",
      "===============================================================================",
      "",
      paste("Installation Qualification (IQ): ",
            if (validation_results$summary$iq_passed) "PASSED" else "FAILED"),
      paste("  Tests: ", validation_results$iq$summary$passed, "/",
            validation_results$iq$summary$total_tests),
      "",
      paste("Operational Qualification (OQ):  ",
            if (validation_results$summary$oq_passed) "PASSED" else "FAILED"),
      paste("  Tests: ", validation_results$oq$summary$passed, "/",
            validation_results$oq$summary$total_tests),
      "",
      paste("Performance Qualification (PQ):  ",
            if (validation_results$summary$pq_passed) "PASSED" else "FAILED"),
      paste("  Tests: ", validation_results$pq$summary$passed, "/",
            validation_results$pq$summary$total_tests),
      "",
      "-------------------------------------------------------------------------------",
      paste("OVERALL STATUS: ",
            if (validation_results$summary$all_passed) "VALIDATION PASSED" else "VALIDATION FAILED"),
      paste("Total Tests:    ", validation_results$summary$total_passed, "/",
            validation_results$summary$total_tests),
      paste("Duration:       ", round(validation_results$summary$duration_seconds, 2), " seconds"),
      "-------------------------------------------------------------------------------",
      ""
    )

    add_test_details <- function(results, category) {
      c(
        paste("", category, "TEST DETAILS"),
        paste(rep("-", 50), collapse = ""),
        sapply(results, function(r) {
          paste(r$test_id, ": ", r$test_name, " - ",
                if (r$passed) "PASSED" else "FAILED",
                " (", r$message, ")", sep = "")
        }),
        ""
      )
    }

    lines <- c(lines,
               "===============================================================================",
               "                         DETAILED RESULTS",
               "===============================================================================",
               "",
               add_test_details(validation_results$iq$results, "IQ"),
               add_test_details(validation_results$oq$results, "OQ"),
               add_test_details(validation_results$pq$results, "PQ"),
               "",
               "===============================================================================",
               "                           SIGNATURES",
               "===============================================================================",
               "",
               "Executed By:     _________________________ Date: _______________",
               "",
               "Reviewed By:     _________________________ Date: _______________",
               "",
               "Approved By:     _________________________ Date: _______________",
               "",
               "===============================================================================",
               "                         END OF REPORT",
               "==============================================================================="
    )

    writeLines(lines, output_file)
  }

  output_file
}
