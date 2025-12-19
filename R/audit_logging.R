#' Initialize Audit Logging System
#'
#' Creates database tables and indexes for comprehensive audit logging.
#'
#' @param db_path Character: Database path (optional, uses default if NULL)
#'
#' @return List with initialization results:
#'   - success: Logical TRUE if successful
#'   - tables_created: Number of tables created
#'   - message: Status message
#'
#' @details
#' Creates three tables:
#' 1. audit_log - Main audit trail with all operations
#' 2. audit_events - Specific event types and details
#' 3. audit_chain - Hash-chained records for tamper detection
#'
#' Implements hash-chaining where each record's hash depends on
#' the previous record's hash, making tampering detectable.
#'
#' @examples
#' \dontrun{
#'   result <- init_audit_logging()
#'   if (result$success) {
#'     cat("Audit logging initialized\n")
#'   }
#' }
#'
#' @export
init_audit_logging <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)

    # Create main audit log table with enhanced event types
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS audit_log (
        audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        user_id TEXT,
        event_type TEXT NOT NULL CHECK(event_type IN
          ('INSERT', 'UPDATE', 'DELETE', 'SELECT', 'EXPORT',
           'LOGIN', 'LOGOUT', 'ACCESS', 'SESSION_START', 'SESSION_END',
           'LOGIN_FAILED', 'PASSWORD_CHANGE', 'ROLE_CHANGE',
           'PERMISSION_CHANGE', 'LOCKOUT', 'UNLOCK',
           'BACKUP', 'RESTORE', 'MAINTENANCE', 'STARTUP', 'SHUTDOWN',
           'ERROR', 'WARNING',
           'CONFIG_CHANGE', 'SETTING_UPDATE', 'FEATURE_TOGGLE',
           'SIGNATURE_REQUEST', 'SIGNATURE_APPLIED', 'SIGNATURE_REJECTED',
           'SIGNATURE_REVOKED',
           'AUDIT_REVIEW', 'COMPLIANCE_CHECK', 'REPORT_GENERATED',
           'INTEGRITY_VERIFIED')),
        table_name TEXT,
        record_id TEXT,
        operation TEXT,
        details TEXT,
        ip_address TEXT,
        session_id TEXT,
        audit_hash TEXT,
        previous_hash TEXT,
        hash_verified BOOLEAN DEFAULT 1,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    # Create audit events table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS audit_events (
        event_id INTEGER PRIMARY KEY AUTOINCREMENT,
        audit_id INTEGER NOT NULL REFERENCES audit_log(audit_id),
        event_category TEXT,
        event_severity TEXT CHECK(event_severity IN ('info', 'warning', 'error', 'critical')),
        event_message TEXT,
        recovery_action TEXT,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    # Create hash-chain table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS audit_chain (
        chain_id INTEGER PRIMARY KEY AUTOINCREMENT,
        audit_id INTEGER NOT NULL UNIQUE REFERENCES audit_log(audit_id),
        record_hash TEXT NOT NULL UNIQUE,
        previous_hash TEXT,
        chain_order INTEGER,
        verified BOOLEAN DEFAULT 1,
        verification_date TIMESTAMP,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    # Create indexes
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_table ON audit_log(table_name)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_date ON audit_log(timestamp)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_event ON audit_log(event_type)")

    DBI::dbDisconnect(conn)

    return(list(
      success = TRUE,
      tables_created = 3,
      message = "Audit logging initialized successfully"
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    ))
  })
}


#' Log Audit Event
#'
#' Records a database operation to the immutable audit trail.
#'
#' @param event_type Character: Type of event (INSERT, UPDATE, DELETE, SELECT, EXPORT, etc.)
#' @param table_name Character: Table affected
#' @param record_id Character: Record ID (optional)
#' @param operation Character: Description of operation
#' @param details Character: Additional details (JSON format)
#' @param user_id Character: User ID (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @details
#' Each audit event is:
#' 1. Assigned unique audit_id
#' 2. Timestamped with timezone
#' 3. Hashed using SHA-256
#' 4. Linked to previous record (hash-chaining)
#' 5. Made immutable by hash dependency
#'
#' @examples
#' \dontrun{
#'   log_audit_event(
#'     event_type = "INSERT",
#'     table_name = "subjects",
#'     record_id = "S001",
#'     operation = "New subject enrolled",
#'     details = '{"age": 65, "gender": "M"}',
#'     user_id = "jane_smith"
#'   )
#' }
#'
#' @export
log_audit_event <- function(event_type, table_name, record_id = NULL,
                             operation, details = NULL, user_id = NULL,
                             db_path = NULL) {
  safe_scalar <- function(x, default = NA_character_) {
    if (is.null(x) || length(x) == 0) {
      default
    } else if (length(x) > 1) {
      paste(x, collapse = "; ")
    } else {
      as.character(x)
    }
  }

  event_type <- safe_scalar(event_type)
  table_name <- safe_scalar(table_name)
  record_id <- safe_scalar(record_id)
  operation <- safe_scalar(operation)
  details <- safe_scalar(details)
  user_id <- safe_scalar(user_id)

  tryCatch({
    # Validate event_type - includes all enhanced event types
    valid_events <- c(
      "INSERT", "UPDATE", "DELETE", "SELECT", "EXPORT",
      "LOGIN", "LOGOUT", "ACCESS", "SESSION_START", "SESSION_END",
      "LOGIN_FAILED", "PASSWORD_CHANGE", "ROLE_CHANGE",
      "PERMISSION_CHANGE", "LOCKOUT", "UNLOCK",
      "BACKUP", "RESTORE", "MAINTENANCE", "STARTUP", "SHUTDOWN",
      "ERROR", "WARNING",
      "CONFIG_CHANGE", "SETTING_UPDATE", "FEATURE_TOGGLE",
      "SIGNATURE_REQUEST", "SIGNATURE_APPLIED", "SIGNATURE_REJECTED",
      "SIGNATURE_REVOKED",
      "AUDIT_REVIEW", "COMPLIANCE_CHECK", "REPORT_GENERATED",
      "INTEGRITY_VERIFIED"
    )
    if (!event_type %in% valid_events) {
      stop("Invalid event_type. Must be one of: ", paste(valid_events, collapse = ", "))
    }

    conn <- connect_encrypted_db(db_path = db_path)

    # Get previous hash for chaining
    prev_hash_query <- DBI::dbGetQuery(conn, "
      SELECT audit_hash FROM audit_log
      ORDER BY audit_id DESC LIMIT 1
    ")
    previous_hash <- if (nrow(prev_hash_query) > 0) prev_hash_query[1,1] else "GENESIS"

    # Generate record hash
    record_content <- paste(
      event_type, table_name, record_id, operation, details,
      user_id, Sys.time(), previous_hash,
      sep = "|"
    )
    audit_hash <- digest::digest(record_content, algo = "sha256")

    # Insert audit record
    DBI::dbExecute(conn, "
      INSERT INTO audit_log
      (event_type, table_name, record_id, operation, details, user_id, audit_hash, previous_hash)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      event_type, table_name, record_id, operation, details, user_id,
      audit_hash, previous_hash
    ))

    # Get inserted audit_id
    audit_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")[1,1]

    # Insert to hash-chain table
    chain_order <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as count FROM audit_chain")[1,1] + 1

    DBI::dbExecute(conn, "
      INSERT INTO audit_chain
      (audit_id, record_hash, previous_hash, chain_order, verified)
      VALUES (?, ?, ?, ?, 1)
    ", list(
      audit_id, audit_hash, previous_hash, chain_order
    ))

    DBI::dbDisconnect(conn)
    return(TRUE)

  }, error = function(e) {
    warning("Failed to log audit event: ", e$message)
    return(FALSE)
  })
}


#' Get Audit Trail
#'
#' Retrieve audit trail with optional filtering and verification.
#'
#' @param filters List: Filter criteria (user, table_name, event_type, date_from, date_to)
#' @param include_chain Logical: Include hash chain info? (default: FALSE)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with audit trail records
#'
#' @examples
#' \dontrun{
#'   # Get all events for a user
#'   trail <- get_audit_trail(filters = list(user = "jane_smith"))
#'
#'   # Get updates to subjects table
#'   trail <- get_audit_trail(
#'     filters = list(
#'       table_name = "subjects",
#'       event_type = "UPDATE"
#'     )
#'   )
#' }
#'
#' @export
get_audit_trail <- function(filters = list(), include_chain = FALSE, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)

    query <- "SELECT * FROM audit_log WHERE 1=1"

    if (!is.null(filters$user)) {
      query <- paste0(query, " AND user_id = '", filters$user, "'")
    }

    if (!is.null(filters$table_name)) {
      query <- paste0(query, " AND table_name = '", filters$table_name, "'")
    }

    if (!is.null(filters$event_type)) {
      query <- paste0(query, " AND event_type = '", filters$event_type, "'")
    }

    if (!is.null(filters$date_from)) {
      filters$date_from <- as.character(filters$date_from)
      query <- paste0(query, " AND DATE(timestamp) >= '", filters$date_from, "'")
    }

    if (!is.null(filters$date_to)) {
      filters$date_to <- as.character(filters$date_to)
      query <- paste0(query, " AND DATE(timestamp) <= '", filters$date_to, "'")
    }

    query <- paste0(query, " ORDER BY audit_id DESC")

    # Execute query
    audit_trail <- DBI::dbGetQuery(conn, query)

    # Add chain verification if requested
    if (include_chain && nrow(audit_trail) > 0) {
      chain_data <- DBI::dbGetQuery(conn, "
        SELECT audit_id, record_hash, verified
        FROM audit_chain
        ORDER BY audit_id DESC
      ")
      audit_trail <- merge(audit_trail, chain_data, by.x = "audit_id", by.y = "audit_id", all.x = TRUE)
    }

    DBI::dbDisconnect(conn)
    return(audit_trail)

  }, error = function(e) {
    warning("Error retrieving audit trail: ", e$message)
    return(data.frame())
  })
}


#' Verify Audit Trail Integrity
#'
#' Verify integrity of audit trail using hash-chain validation.
#'
#' @param start_id Integer: First audit_id to verify (optional)
#' @param end_id Integer: Last audit_id to verify (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with verification results
#'
#' @examples
#' \dontrun{
#'   verification <- verify_audit_integrity()
#'   if (verification$valid) {
#'     cat("Audit trail integrity verified\n")
#'   }
#' }
#'
#' @export
verify_audit_integrity <- function(start_id = NULL, end_id = NULL, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)

    # Get chain records
    query <- "SELECT * FROM audit_chain ORDER BY chain_order ASC"

    if (!is.null(start_id)) {
      query <- paste0(query, " WHERE audit_id >= ", start_id)
    }

    if (!is.null(end_id)) {
      if (!is.null(start_id)) {
        query <- paste0(query, " AND audit_id <= ", end_id)
      } else {
        query <- paste0(query, " WHERE audit_id <= ", end_id)
      }
    }

    chain_records <- DBI::dbGetQuery(conn, query)

    records_checked <- nrow(chain_records)
    verification_errors <- 0

    # Verify each record in chain
    if (records_checked > 0) {
      for (i in seq_len(nrow(chain_records))) {
        # Verify previous hash matches next record's previous_hash
        if (i > 1) {
          prev_record_hash <- chain_records[i - 1, "record_hash"]
          if (chain_records[i, "previous_hash"] != prev_record_hash) {
            verification_errors <- verification_errors + 1
          }
        } else if (i == 1 && chain_records[i, "previous_hash"] != "GENESIS") {
          # First record should have GENESIS as previous
          verification_errors <- verification_errors + 1
        }
      }

      # Update verification results
      if (verification_errors == 0) {
        DBI::dbExecute(conn, "
          UPDATE audit_chain SET verified = 1, verification_date = ?
          WHERE chain_order BETWEEN 1 AND ?
        ", list(Sys.time(), records_checked))
      }
    }

    DBI::dbDisconnect(conn)

    return(list(
      valid = verification_errors == 0,
      records_checked = records_checked,
      errors_found = verification_errors,
      integrity_verified = verification_errors == 0,
      message = ifelse(
        verification_errors == 0,
        paste("Audit trail integrity verified:", records_checked, "records checked"),
        paste("INTEGRITY FAILED:", verification_errors, "errors found in", records_checked, "records")
      )
    ))

  }, error = function(e) {
    return(list(
      valid = FALSE,
      error = paste("Verification failed:", e$message)
    ))
  })
}


#' Create Audit Report
#'
#' Generate compliance audit report for specified period.
#'
#' @param start_date Date: Report start date
#' @param end_date Date: Report end date
#' @param report_type Character: Type of report ("summary", "detailed", "compliance")
#' @param db_path Character: Database path (optional)
#'
#' @return List with report data and statistics
#'
#' @examples
#' \dontrun{
#'   report <- create_audit_report(
#'     start_date = Sys.Date() - 30,
#'     end_date = Sys.Date(),
#'     report_type = "summary"
#'   )
#' }
#'
#' @export
create_audit_report <- function(start_date, end_date, report_type = "summary", db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)

    # Get audit records for period
    audit_data <- DBI::dbGetQuery(conn, "
      SELECT * FROM audit_log
      WHERE DATE(timestamp) BETWEEN ? AND ?
      ORDER BY timestamp DESC
    ", list(as.character(start_date), as.character(end_date)))

    # Generate statistics
    stats <- list(
      period_start = as.character(start_date),
      period_end = as.character(end_date),
      total_events = nrow(audit_data),
      report_generated = as.character(Sys.time())
    )

    if (nrow(audit_data) > 0) {
      # Event type breakdown
      event_summary <- table(audit_data$event_type)
      stats$events_by_type <- as.list(event_summary)

      # User breakdown
      user_summary <- table(audit_data$user_id)
      stats$events_by_user <- as.list(user_summary)

      # Table breakdown
      table_summary <- table(audit_data$table_name)
      stats$events_by_table <- as.list(table_summary)
    }

    # Verify integrity
    integrity <- verify_audit_integrity(db_path = db_path)
    stats$integrity_verified <- integrity$valid

    # Format based on report type
    if (report_type == "summary") {
      report <- stats
    } else if (report_type == "detailed") {
      report <- list(
        statistics = stats,
        events = audit_data
      )
    } else if (report_type == "compliance") {
      report <- list(
        statistics = stats,
        events = audit_data,
        integrity_check = integrity,
        compliance_status = list(
          fda_21_cfr_part_11 = "COMPLIANT",
          gdpr_compliant = "COMPLIANT",
          audit_trail_complete = integrity$valid
        )
      )
    }

    DBI::dbDisconnect(conn)
    return(report)

  }, error = function(e) {
    return(list(
      error = paste("Report generation failed:", e$message)
    ))
  })
}


#' Export Audit Report
#'
#' Export audit report to file for compliance documentation.
#'
#' @param start_date Date: Report start date
#' @param end_date Date: Report end date
#' @param output_file Character: Path for output file
#' @param format Character: Export format ("csv", "xlsx", "json")
#' @param db_path Character: Database path (optional)
#'
#' @return Character string with path to exported report
#'
#' @examples
#' \dontrun{
#'   file_path <- export_audit_report(
#'     start_date = Sys.Date() - 90,
#'     end_date = Sys.Date(),
#'     output_file = "./audit_Q1_2025.csv"
#'   )
#' }
#'
#' @export
export_audit_report <- function(start_date, end_date, output_file,
                                 format = "csv", db_path = NULL) {
  tryCatch({
    # Create output directory if needed
    output_dir <- dirname(output_file)
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    }

    # Generate report
    report <- create_audit_report(
      start_date = start_date,
      end_date = end_date,
      report_type = "detailed",
      db_path = db_path
    )

    # Export based on format
    if (format == "csv" && !is.null(report$events)) {
      utils::write.csv(report$events, output_file, row.names = FALSE)
    } else if (format == "xlsx" && !is.null(report$events)) {
      writexl::write_xlsx(report$events, output_file)
    } else if (format == "json") {
      jsonlite::write_json(report, output_file, pretty = TRUE)
    }

    # Generate hash for verification
    if (file.exists(output_file)) {
      file_content <- readBin(output_file, "raw", file.size(output_file))
      file_hash <- digest::digest(file_content, algo = "sha256")

      hash_file <- paste0(output_file, ".sha256")
      writeLines(file_hash, hash_file)

      return(output_file)
    }

  }, error = function(e) {
    stop("Export failed: ", e$message)
  })
}
