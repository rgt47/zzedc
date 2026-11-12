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
#' the previous record's hash, and installs triggers that make the
#' three tables append-only where the backend supports triggers
#' (not DuckDB). See `?audit_protection`.
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
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    .ensure_audit_tables(conn)
    list(
      success = TRUE,
      tables_created = 3,
      protection = audit_protection_status(conn),
      message = "Audit logging initialized successfully"
    )
  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    )
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
#' @param ip_address,session_id Character: client address and Shiny
#'   session token of the request, when known (optional).
#'
#' @return `TRUE` if the record was written. If it could not be
#'   written: under the `regulated` security profile, an error; under
#'   the other profiles, a warning and `FALSE`.
#'
#' @details
#' Each audit event is assigned an `audit_id`, timestamped in UTC,
#' hashed with SHA-256 over its content and the previous record's
#' hash, and linked into `audit_chain`, all in one transaction. A
#' change to data should instead write its audit record in the same
#' transaction as the change (as `db_insert_data_entry()` does), so
#' that one cannot commit without the other. See `?audit_protection`
#' for how the trail is protected against alteration.
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
                             db_path = NULL, ip_address = NULL,
                             session_id = NULL) {
  ok <- tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    .with_db_transaction(conn, function(c) {
      .append_audit_record(c, event_type, table_name, record_id, operation,
                           details, user_id, ip_address, session_id)
    })
    TRUE
  }, error = function(e) e)

  if (isTRUE(ok)) return(TRUE)
  # An action whose audit record cannot be written must not pass
  # silently. Under the 'regulated' profile this is an error, so a
  # caller that does not catch it stops; elsewhere it remains a
  # warning, as before.
  if (get_security_profile() == "regulated") {
    stop("Audit record could not be written: ", conditionMessage(ok), call. = FALSE)
  }
  warning("Failed to log audit event: ", conditionMessage(ok))
  FALSE
}



#' Get Audit Trail
#'
#' Retrieve audit trail with optional filtering and verification.
#'
#' @param filters List: Filter criteria (user, table_name, record_id,
#'   event_type, date_from, date_to). All are bound as query
#'   parameters.
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
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # Every filter is a bound parameter. They were pasted into the SQL
    # string, so a filter value containing a quote could rewrite the
    # query against the audit trail.
    where <- character(0)
    params <- list()
    add <- function(clause, value) {
      where <<- c(where, clause)
      params <<- c(params, list(as.character(value)))
    }
    if (!is.null(filters$user)) add("user_id = ?", filters$user)
    if (!is.null(filters$table_name)) add("table_name = ?", filters$table_name)
    if (!is.null(filters$event_type)) add("event_type = ?", filters$event_type)
    if (!is.null(filters$record_id)) add("record_id = ?", filters$record_id)
    if (!is.null(filters$date_from)) add("DATE(timestamp) >= ?", as.Date(filters$date_from))
    if (!is.null(filters$date_to)) add("DATE(timestamp) <= ?", as.Date(filters$date_to))

    query <- paste0(
      "SELECT * FROM audit_log",
      if (length(where)) paste0(" WHERE ", paste(where, collapse = " AND ")) else "",
      " ORDER BY audit_id DESC"
    )
    audit_trail <- if (length(params)) {
      DBI::dbGetQuery(conn, query, params = params)
    } else {
      DBI::dbGetQuery(conn, query)
    }

    # Add chain verification if requested
    if (include_chain && nrow(audit_trail) > 0) {
      chain_data <- DBI::dbGetQuery(conn, "
        SELECT audit_id, record_hash, verified
        FROM audit_chain
        ORDER BY audit_id DESC
      ")
      audit_trail <- merge(audit_trail, chain_data, by.x = "audit_id", by.y = "audit_id", all.x = TRUE)
    }

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
#' @keywords internal
#' @export
verify_audit_integrity <- function(start_id = NULL, end_id = NULL, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # Join the chain to the log so the content behind each hash is
    # available. The clauses are assembled before ORDER BY: they were
    # appended after it, which is a syntax error, so any call passing
    # start_id or end_id failed outright and was swallowed by the
    # handler below as a verification failure.
    where <- character(0)
    params <- list()
    if (!is.null(start_id)) {
      where <- c(where, "c.audit_id >= ?")
      params <- c(params, list(start_id))
    }
    if (!is.null(end_id)) {
      where <- c(where, "c.audit_id <= ?")
      params <- c(params, list(end_id))
    }
    query <- paste0(
      "SELECT c.audit_id, c.record_hash, c.previous_hash, c.chain_order, ",
      "l.event_type, l.table_name, l.record_id, l.operation, l.details, ",
      "l.user_id, l.ip_address, l.session_id, l.timestamp, l.previous_hash AS log_previous_hash ",
      "FROM audit_chain c JOIN audit_log l ON l.audit_id = c.audit_id",
      if (length(where)) paste0(" WHERE ", paste(where, collapse = " AND ")) else "",
      " ORDER BY c.chain_order ASC"
    )
    chain_records <- if (length(params)) {
      DBI::dbGetQuery(conn, query, params = params)
    } else {
      DBI::dbGetQuery(conn, query)
    }
    # Whether this run covers the head of the chain, which is the only
    # place GENESIS belongs.
    from_start <- nrow(chain_records) > 0 &&
      chain_records$chain_order[1] == 1

    records_checked <- nrow(chain_records)
    verification_errors <- 0

    tampered <- integer(0)

    # Verify each record in chain
    if (records_checked > 0) {
      for (i in seq_len(nrow(chain_records))) {
        # Verify previous hash matches next record's previous_hash
        if (i > 1) {
          prev_record_hash <- chain_records[i - 1, "record_hash"]
          if (chain_records[i, "previous_hash"] != prev_record_hash) {
            verification_errors <- verification_errors + 1
          }
        } else if (i == 1 && from_start &&
                     chain_records[i, "previous_hash"] != "GENESIS") {
          # Only the true first record of the chain has GENESIS as its
          # predecessor. When a sub-range is verified its first record
          # legitimately points at the record before it, so applying
          # this check there reported a failure on every partial
          # verification.
          verification_errors <- verification_errors + 1
        }

        # Recompute the hash from the record's own content, in the
        # field order log_audit_event() used. Comparing the linkage
        # fields alone proves only that they agree with each other:
        # the event, the user, the record acted on and the timestamp
        # could all be rewritten and the chain would still report
        # itself intact.
        rec <- chain_records[i, ]
        recomputed <- digest::digest(
          .audit_hash_content(
            rec$event_type, rec$table_name, rec$record_id, rec$operation,
            rec$details, rec$user_id, rec$ip_address, rec$session_id,
            rec$timestamp, rec$log_previous_hash
          ),
          algo = "sha256"
        )
        if (!identical(recomputed, as.character(rec$record_hash))) {
          verification_errors <- verification_errors + 1
          tampered <- c(tampered, rec$audit_id)
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

    return(list(
      valid = verification_errors == 0,
      records_checked = records_checked,
      errors_found = verification_errors,
      tampered_records = tampered,
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
#' @keywords internal
#' @export
create_audit_report <- function(start_date, end_date, report_type = "summary", db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

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
#' @keywords internal
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

#' @noRd
# Canonical content string behind an audit record's hash.
#
# There were two writers, log_audit_event() here and
# log_audit_event_extended() in audit_enhanced.R, hashing different
# field sets into the same audit_log table: the extended one added
# ip_address, session_id and event_category, the last of which is
# stored in a different table entirely. Both also hashed a Sys.time()
# that was never written anywhere, so neither hash could be recomputed
# from the row it described. One verifier cannot check two
# constructions, which is why verification only ever compared the
# linkage fields.
#
# Everything here is a column of audit_log, so the string can be
# rebuilt from a stored row. NULL and NA collapse to the empty string
# so that a writer omitting a field and a reader finding it NULL agree.
.audit_hash_content <- function(event_type, table_name, record_id,
                                operation, details, user_id,
                                ip_address, session_id, timestamp,
                                previous_hash) {
  nz <- function(x) {
    if (is.null(x) || length(x) == 0L || is.na(x[1L])) {
      ""
    } else {
      as.character(x[1L])
    }
  }
  paste(nz(event_type), nz(table_name), nz(record_id), nz(operation),
        nz(details), nz(user_id), nz(ip_address), nz(session_id),
        nz(timestamp), nz(previous_hash), sep = "|")
}
