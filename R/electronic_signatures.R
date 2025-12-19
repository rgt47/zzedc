#' Electronic Signatures System
#'
#' FDA 21 CFR Part 11 compliant electronic signature system.
#' Implements signature capture, validation, binding, and non-repudiation.

# =============================================================================
# Helper Functions
# =============================================================================

#' Safe Scalar Conversion for Signatures
#'
#' @param x Value to convert
#' @param default Default value if NULL
#' @return Character scalar
#' @keywords internal
safe_scalar_sig <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

# =============================================================================
# Database Schema
# =============================================================================

#' Initialize Electronic Signatures System
#'
#' Creates database tables for FDA-compliant electronic signatures.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with initialization results
#'
#' @export
init_electronic_signatures <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS electronic_signatures (
        signature_id INTEGER PRIMARY KEY AUTOINCREMENT,
        signature_code TEXT NOT NULL UNIQUE,
        signer_user_id TEXT NOT NULL,
        signer_full_name TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        signature_meaning TEXT NOT NULL CHECK(signature_meaning IN
          ('CREATED_BY', 'REVIEWED_BY', 'APPROVED_BY', 'VERIFIED_BY',
           'MONITORED_BY', 'LOCKED_BY', 'CORRECTED_BY', 'CERTIFIED_BY')),
        signature_statement TEXT NOT NULL,
        record_hash TEXT NOT NULL,
        signature_hash TEXT NOT NULL,
        previous_signature_hash TEXT,
        signed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        ip_address TEXT,
        session_id TEXT,
        is_valid BOOLEAN DEFAULT 1,
        invalidated_at TIMESTAMP,
        invalidated_by TEXT,
        invalidation_reason TEXT,
        superseded_by INTEGER REFERENCES electronic_signatures(signature_id),
        metadata TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS signature_attempts (
        attempt_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        signature_meaning TEXT NOT NULL,
        attempt_result TEXT NOT NULL CHECK(attempt_result IN
          ('SUCCESS', 'FAILED_PASSWORD', 'FAILED_PERMISSION',
           'FAILED_LOCKED', 'FAILED_VALIDATION', 'CANCELLED')),
        failure_reason TEXT,
        attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        ip_address TEXT,
        session_id TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS signature_requirements (
        requirement_id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        form_type TEXT,
        required_meanings TEXT NOT NULL,
        required_roles TEXT,
        minimum_signatures INTEGER DEFAULT 1,
        allow_self_sign BOOLEAN DEFAULT 0,
        require_different_signers BOOLEAN DEFAULT 1,
        effective_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        effective_to TIMESTAMP,
        created_by TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(table_name, form_type, effective_from)
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS signature_delegations (
        delegation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        delegator_user_id TEXT NOT NULL,
        delegate_user_id TEXT NOT NULL,
        signature_meanings TEXT NOT NULL,
        table_names TEXT,
        effective_from TIMESTAMP NOT NULL,
        effective_to TIMESTAMP NOT NULL,
        delegation_reason TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_by TEXT NOT NULL,
        revoked_at TIMESTAMP,
        revoked_by TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_signatures_record
      ON electronic_signatures(table_name, record_id)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_signatures_signer
      ON electronic_signatures(signer_user_id)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_signatures_valid
      ON electronic_signatures(is_valid)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_attempts_user
      ON signature_attempts(user_id)
    ")

    list(
      success = TRUE,
      tables_created = 4,
      message = "Electronic signatures system initialized successfully"
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    )
  })
}


# =============================================================================
# Signature Meanings
# =============================================================================

#' Get Signature Meanings
#'
#' Returns valid signature meaning codes with descriptions.
#'
#' @return Named list of signature meanings
#'
#' @export
get_signature_meanings <- function() {
  list(
    CREATED_BY = "I created this record and certify the data is accurate",
    REVIEWED_BY = "I have reviewed this record and found it complete",
    APPROVED_BY = "I approve this record for the intended purpose",
    VERIFIED_BY = "I have verified the accuracy of this record",
    MONITORED_BY = "I have monitored this record as part of oversight",
    LOCKED_BY = "I am locking this record to prevent further changes",
    CORRECTED_BY = "I have made corrections to this record",
    CERTIFIED_BY = "I certify this record meets all requirements"
  )
}


#' Get Signature Statement
#'
#' Returns the legal statement for a signature meaning.
#'
#' @param meaning Character: Signature meaning code
#'
#' @return Character: Signature statement
#'
#' @export
get_signature_statement <- function(meaning) {
  statements <- get_signature_meanings()
  if (meaning %in% names(statements)) {
    statements[[meaning]]
  } else {
    stop("Invalid signature meaning: ", meaning)
  }
}


# =============================================================================
# Signature Creation
# =============================================================================

#' Apply Electronic Signature
#'
#' Applies an FDA-compliant electronic signature to a record.
#'
#' @param table_name Character: Table containing the record
#' @param record_id Character: Record identifier
#' @param signer_user_id Character: User ID of signer
#' @param signer_full_name Character: Full name of signer
#' @param signature_meaning Character: Meaning code from get_signature_meanings()
#' @param password Character: User's password for verification
#' @param password_hash Character: Stored password hash for verification
#' @param ip_address Character: IP address (optional)
#' @param session_id Character: Session ID (optional)
#' @param custom_statement Character: Custom signature statement (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with signature result
#'
#' @export
apply_electronic_signature <- function(table_name,
                                        record_id,
                                        signer_user_id,
                                        signer_full_name,
                                        signature_meaning,
                                        password,
                                        password_hash,
                                        ip_address = NULL,
                                        session_id = NULL,
                                        custom_statement = NULL,
                                        db_path = NULL) {

  valid_meanings <- names(get_signature_meanings())
  if (!signature_meaning %in% valid_meanings) {
    log_signature_attempt(
      user_id = signer_user_id,
      table_name = table_name,
      record_id = record_id,
      signature_meaning = signature_meaning,
      result = "FAILED_VALIDATION",
      reason = "Invalid signature meaning",
      ip_address = ip_address,
      session_id = session_id,
      db_path = db_path
    )
    return(list(
      success = FALSE,
      error = paste("Invalid signature meaning. Must be one of:",
                    paste(valid_meanings, collapse = ", "))
    ))
  }

  if (!verify_password_for_signature(password, password_hash)) {
    log_signature_attempt(
      user_id = signer_user_id,
      table_name = table_name,
      record_id = record_id,
      signature_meaning = signature_meaning,
      result = "FAILED_PASSWORD",
      reason = "Password verification failed",
      ip_address = ip_address,
      session_id = session_id,
      db_path = db_path
    )
    return(list(
      success = FALSE,
      error = "Password verification failed"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    record_hash <- compute_record_hash(conn, table_name, record_id)

    last_sig <- DBI::dbGetQuery(conn, "
      SELECT signature_hash FROM electronic_signatures
      ORDER BY signature_id DESC LIMIT 1
    ")

    previous_hash <- if (nrow(last_sig) == 0) "GENESIS" else last_sig$signature_hash[1]

    signature_code <- generate_signature_code()
    timestamp <- as.character(Sys.time())

    statement <- if (!is.null(custom_statement) && nchar(custom_statement) > 10) {
      custom_statement
    } else {
      get_signature_statement(signature_meaning)
    }

    sig_content <- paste(
      signature_code,
      signer_user_id,
      signer_full_name,
      table_name,
      record_id,
      signature_meaning,
      statement,
      record_hash,
      timestamp,
      previous_hash,
      sep = "|"
    )
    signature_hash <- digest::digest(sig_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO electronic_signatures (
        signature_code, signer_user_id, signer_full_name,
        table_name, record_id, signature_meaning, signature_statement,
        record_hash, signature_hash, previous_signature_hash,
        signed_at, ip_address, session_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      signature_code,
      safe_scalar_sig(signer_user_id),
      safe_scalar_sig(signer_full_name),
      safe_scalar_sig(table_name),
      safe_scalar_sig(record_id),
      safe_scalar_sig(signature_meaning),
      safe_scalar_sig(statement),
      record_hash,
      signature_hash,
      previous_hash,
      timestamp,
      safe_scalar_sig(ip_address),
      safe_scalar_sig(session_id)
    ))

    signature_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_signature_attempt(
      user_id = signer_user_id,
      table_name = table_name,
      record_id = record_id,
      signature_meaning = signature_meaning,
      result = "SUCCESS",
      ip_address = ip_address,
      session_id = session_id,
      db_path = db_path
    )

    tryCatch({
      log_audit_event(
        event_type = "SIGNATURE_APPLIED",
        user_id = signer_user_id,
        table_name = table_name,
        record_id = record_id,
        details = paste("Electronic signature applied:",
                        signature_meaning, "by", signer_full_name)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      signature_id = signature_id,
      signature_code = signature_code,
      signature_hash = signature_hash,
      signed_at = timestamp,
      message = "Electronic signature applied successfully"
    )

  }, error = function(e) {
    log_signature_attempt(
      user_id = signer_user_id,
      table_name = table_name,
      record_id = record_id,
      signature_meaning = signature_meaning,
      result = "FAILED_VALIDATION",
      reason = e$message,
      ip_address = ip_address,
      session_id = session_id,
      db_path = db_path
    )

    list(success = FALSE, error = e$message)
  })
}


#' Generate Signature Code
#'
#' Generates a unique signature code.
#'
#' @return Character: Unique signature code
#'
#' @keywords internal
generate_signature_code <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(c(0:9, LETTERS), 6, replace = TRUE), collapse = "")
  paste0("SIG", timestamp, random)
}


#' Compute Record Hash
#'
#' Computes a hash of the record being signed.
#'
#' @param conn Database connection
#' @param table_name Character: Table name
#' @param record_id Character: Record ID
#'
#' @return Character: SHA-256 hash of record
#'
#' @keywords internal
compute_record_hash <- function(conn, table_name, record_id) {
  tryCatch({
    if (!DBI::dbExistsTable(conn, table_name)) {
      return(digest::digest(paste(table_name, record_id, sep = "|"), algo = "sha256"))
    }

    record <- DBI::dbGetQuery(conn, sprintf(
      "SELECT * FROM %s WHERE rowid = ? OR id = ? LIMIT 1",
      DBI::dbQuoteIdentifier(conn, table_name)
    ), list(record_id, record_id))

    if (nrow(record) == 0) {
      return(digest::digest(paste(table_name, record_id, "NOT_FOUND", sep = "|"),
                            algo = "sha256"))
    }

    record_json <- jsonlite::toJSON(record, auto_unbox = TRUE)
    digest::digest(record_json, algo = "sha256")

  }, error = function(e) {
    digest::digest(paste(table_name, record_id, e$message, sep = "|"),
                   algo = "sha256")
  })
}


#' Verify Password for Signature
#'
#' Verifies password before allowing signature.
#'
#' @param password Character: Plain text password
#' @param stored_hash Character: Stored password hash
#'
#' @return Logical: TRUE if password matches
#'
#' @keywords internal
verify_password_for_signature <- function(password, stored_hash) {
  if (is.null(password) || is.null(stored_hash)) {
    return(FALSE)
  }

  if (nchar(password) == 0 || nchar(stored_hash) == 0) {
    return(FALSE)
  }

  computed_hash <- digest::digest(password, algo = "sha256")
  identical(computed_hash, stored_hash)
}


#' Log Signature Attempt
#'
#' Logs a signature attempt (success or failure).
#'
#' @param user_id Character: User ID
#' @param table_name Character: Table name
#' @param record_id Character: Record ID
#' @param signature_meaning Character: Signature meaning
#' @param result Character: Result code
#' @param reason Character: Failure reason (optional)
#' @param ip_address Character: IP address (optional)
#' @param session_id Character: Session ID (optional)
#' @param db_path Character: Database path (optional)
#'
#' @keywords internal
log_signature_attempt <- function(user_id,
                                   table_name,
                                   record_id,
                                   signature_meaning,
                                   result,
                                   reason = NULL,
                                   ip_address = NULL,
                                   session_id = NULL,
                                   db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      INSERT INTO signature_attempts (
        user_id, table_name, record_id, signature_meaning,
        attempt_result, failure_reason, attempted_at,
        ip_address, session_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      safe_scalar_sig(user_id),
      safe_scalar_sig(table_name),
      safe_scalar_sig(record_id),
      safe_scalar_sig(signature_meaning),
      safe_scalar_sig(result),
      safe_scalar_sig(reason),
      as.character(Sys.time()),
      safe_scalar_sig(ip_address),
      safe_scalar_sig(session_id)
    ))

  }, error = function(e) NULL)
}


# =============================================================================
# Signature Verification
# =============================================================================

#' Verify Electronic Signature
#'
#' Verifies an electronic signature is valid and intact.
#'
#' @param signature_code Character: Signature code to verify
#' @param db_path Character: Database path (optional)
#'
#' @return List with verification results
#'
#' @export
verify_electronic_signature <- function(signature_code, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    sig <- DBI::dbGetQuery(conn, "
      SELECT * FROM electronic_signatures WHERE signature_code = ?
    ", list(signature_code))

    if (nrow(sig) == 0) {
      return(list(
        success = TRUE,
        is_valid = FALSE,
        error = "Signature not found"
      ))
    }

    if (!sig$is_valid) {
      return(list(
        success = TRUE,
        is_valid = FALSE,
        signature = sig,
        error = paste("Signature was invalidated on", sig$invalidated_at,
                      "by", sig$invalidated_by,
                      "Reason:", sig$invalidation_reason)
      ))
    }

    current_record_hash <- compute_record_hash(conn, sig$table_name, sig$record_id)

    record_unchanged <- identical(current_record_hash, sig$record_hash)

    list(
      success = TRUE,
      is_valid = TRUE,
      record_unchanged = record_unchanged,
      signature = sig,
      verification_time = Sys.time(),
      message = if (record_unchanged) {
        "Signature valid and record unchanged"
      } else {
        "Signature valid but record has been modified since signing"
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Get Record Signatures
#'
#' Retrieves all signatures for a record.
#'
#' @param table_name Character: Table name
#' @param record_id Character: Record ID
#' @param include_invalid Logical: Include invalidated signatures
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame of signatures
#'
#' @export
get_record_signatures <- function(table_name,
                                   record_id,
                                   include_invalid = FALSE,
                                   db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    query <- "
      SELECT * FROM electronic_signatures
      WHERE table_name = ? AND record_id = ?
    "

    if (!include_invalid) {
      query <- paste(query, "AND is_valid = 1")
    }

    query <- paste(query, "ORDER BY signed_at DESC")

    DBI::dbGetQuery(conn, query, list(
      safe_scalar_sig(table_name),
      safe_scalar_sig(record_id)
    ))

  }, error = function(e) data.frame())
}


#' Check Signature Requirements
#'
#' Checks if a record meets its signature requirements.
#'
#' @param table_name Character: Table name
#' @param record_id Character: Record ID
#' @param form_type Character: Form type (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with requirement check results
#'
#' @export
check_signature_requirements <- function(table_name,
                                          record_id,
                                          form_type = NULL,
                                          db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    current_time <- as.character(Sys.time())

    req_query <- "
      SELECT * FROM signature_requirements
      WHERE table_name = ?
      AND (form_type IS NULL OR form_type = ?)
      AND effective_from <= ?
      AND (effective_to IS NULL OR effective_to > ?)
      ORDER BY effective_from DESC
      LIMIT 1
    "

    req <- DBI::dbGetQuery(conn, req_query, list(
      safe_scalar_sig(table_name),
      safe_scalar_sig(form_type),
      current_time,
      current_time
    ))

    if (nrow(req) == 0) {
      return(list(
        success = TRUE,
        has_requirements = FALSE,
        is_complete = TRUE,
        message = "No signature requirements defined for this record"
      ))
    }

    signatures <- get_record_signatures(table_name, record_id, db_path = db_path)

    required_meanings <- strsplit(req$required_meanings, ",")[[1]]
    obtained_meanings <- unique(signatures$signature_meaning)

    missing_meanings <- setdiff(required_meanings, obtained_meanings)

    is_complete <- length(missing_meanings) == 0 &&
                   nrow(signatures) >= req$minimum_signatures

    if (req$require_different_signers && nrow(signatures) > 1) {
      unique_signers <- length(unique(signatures$signer_user_id))
      if (unique_signers < nrow(signatures)) {
        is_complete <- FALSE
      }
    }

    list(
      success = TRUE,
      has_requirements = TRUE,
      is_complete = is_complete,
      required_meanings = required_meanings,
      obtained_meanings = obtained_meanings,
      missing_meanings = missing_meanings,
      signature_count = nrow(signatures),
      minimum_required = req$minimum_signatures,
      requirements = req
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Signature Invalidation
# =============================================================================

#' Invalidate Electronic Signature
#'
#' Invalidates an electronic signature (cannot be deleted per FDA).
#'
#' @param signature_code Character: Signature code to invalidate
#' @param invalidated_by Character: User ID performing invalidation
#' @param reason Character: Reason for invalidation (required)
#' @param db_path Character: Database path (optional)
#'
#' @return List with invalidation result
#'
#' @export
invalidate_signature <- function(signature_code,
                                  invalidated_by,
                                  reason,
                                  db_path = NULL) {
  if (is.null(reason) || nchar(reason) < 10) {
    return(list(
      success = FALSE,
      error = "Invalidation reason required (min 10 characters)"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    sig <- DBI::dbGetQuery(conn, "
      SELECT * FROM electronic_signatures WHERE signature_code = ?
    ", list(signature_code))

    if (nrow(sig) == 0) {
      return(list(success = FALSE, error = "Signature not found"))
    }

    if (!sig$is_valid) {
      return(list(success = FALSE, error = "Signature already invalidated"))
    }

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE electronic_signatures
      SET is_valid = 0,
          invalidated_at = ?,
          invalidated_by = ?,
          invalidation_reason = ?
      WHERE signature_code = ?
    ", list(
      timestamp,
      safe_scalar_sig(invalidated_by),
      safe_scalar_sig(reason),
      signature_code
    ))

    tryCatch({
      log_audit_event(
        event_type = "SIGNATURE_REVOKED",
        user_id = invalidated_by,
        table_name = sig$table_name,
        record_id = sig$record_id,
        details = paste("Signature invalidated:", signature_code,
                        "| Reason:", reason)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      signature_code = signature_code,
      invalidated_at = timestamp,
      message = "Signature invalidated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Statistics and Reporting
# =============================================================================

#' Get Signature Statistics
#'
#' Returns statistics about electronic signatures.
#'
#' @param start_date Character: Start date filter (optional)
#' @param end_date Character: End date filter (optional)
#' @param user_id Character: Filter by signer (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with signature statistics
#'
#' @export
get_signature_statistics <- function(start_date = NULL,
                                      end_date = NULL,
                                      user_id = NULL,
                                      db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    where_clauses <- c()
    params <- list()

    if (!is.null(start_date)) {
      where_clauses <- c(where_clauses, "signed_at >= ?")
      params <- c(params, list(safe_scalar_sig(start_date)))
    }

    if (!is.null(end_date)) {
      where_clauses <- c(where_clauses, "signed_at <= ?")
      params <- c(params, list(safe_scalar_sig(end_date)))
    }

    if (!is.null(user_id)) {
      where_clauses <- c(where_clauses, "signer_user_id = ?")
      params <- c(params, list(safe_scalar_sig(user_id)))
    }

    where_sql <- if (length(where_clauses) > 0) {
      paste("WHERE", paste(where_clauses, collapse = " AND "))
    } else {
      ""
    }

    total_query <- paste("SELECT COUNT(*) as count FROM electronic_signatures", where_sql)
    total <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, total_query, params)$count
    } else {
      DBI::dbGetQuery(conn, total_query)$count
    }

    valid_query <- paste(total_query, if (where_sql == "") "WHERE" else "AND", "is_valid = 1")
    valid <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, valid_query, params)$count
    } else {
      DBI::dbGetQuery(conn, valid_query)$count
    }

    by_meaning <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT signature_meaning, COUNT(*) as count
        FROM electronic_signatures", where_sql, "
        GROUP BY signature_meaning
        ORDER BY count DESC
      "), params)
    } else {
      DBI::dbGetQuery(conn, paste("
        SELECT signature_meaning, COUNT(*) as count
        FROM electronic_signatures", where_sql, "
        GROUP BY signature_meaning
        ORDER BY count DESC
      "))
    }

    by_table <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT table_name, COUNT(*) as count
        FROM electronic_signatures", where_sql, "
        GROUP BY table_name
        ORDER BY count DESC
      "), params)
    } else {
      DBI::dbGetQuery(conn, paste("
        SELECT table_name, COUNT(*) as count
        FROM electronic_signatures", where_sql, "
        GROUP BY table_name
        ORDER BY count DESC
      "))
    }

    by_signer <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT signer_user_id, signer_full_name, COUNT(*) as count
        FROM electronic_signatures", where_sql, "
        GROUP BY signer_user_id
        ORDER BY count DESC
        LIMIT 20
      "), params)
    } else {
      DBI::dbGetQuery(conn, paste("
        SELECT signer_user_id, signer_full_name, COUNT(*) as count
        FROM electronic_signatures", where_sql, "
        GROUP BY signer_user_id
        ORDER BY count DESC
        LIMIT 20
      "))
    }

    failed_attempts <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as count FROM signature_attempts
      WHERE attempt_result != 'SUCCESS'
    ")$count

    list(
      success = TRUE,
      summary = list(
        total_signatures = total,
        valid_signatures = valid,
        invalidated_signatures = total - valid,
        failed_attempts = failed_attempts
      ),
      by_meaning = by_meaning,
      by_table = by_table,
      by_signer = by_signer
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Generate Signature Report
#'
#' Generates an FDA-compliant electronic signature report.
#'
#' @param output_file Character: Output file path
#' @param format Character: Report format (txt or json)
#' @param start_date Character: Start date (optional)
#' @param end_date Character: End date (optional)
#' @param organization Character: Organization name
#' @param prepared_by Character: Report preparer
#' @param db_path Character: Database path (optional)
#'
#' @return List with report generation status
#'
#' @export
generate_signature_report <- function(output_file,
                                       format = "txt",
                                       start_date = NULL,
                                       end_date = NULL,
                                       organization = "Clinical Research Organization",
                                       prepared_by = "Compliance Officer",
                                       db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    stats <- get_signature_statistics(
      start_date = start_date,
      end_date = end_date,
      db_path = db_path
    )

    where_sql <- ""
    params <- list()

    if (!is.null(start_date)) {
      where_sql <- "WHERE signed_at >= ?"
      params <- c(params, list(safe_scalar_sig(start_date)))
    }

    if (!is.null(end_date)) {
      where_sql <- paste(where_sql, if (where_sql == "") "WHERE" else "AND", "signed_at <= ?")
      params <- c(params, list(safe_scalar_sig(end_date)))
    }

    signatures <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT * FROM electronic_signatures", where_sql, "
        ORDER BY signed_at DESC
      "), params)
    } else {
      DBI::dbGetQuery(conn, "
        SELECT * FROM electronic_signatures
        ORDER BY signed_at DESC
      ")
    }

    if (format == "json") {
      report_data <- list(
        report_type = "Electronic Signature Report",
        organization = organization,
        generated_at = as.character(Sys.time()),
        prepared_by = prepared_by,
        date_range = list(start = start_date, end = end_date),
        statistics = stats$summary,
        by_meaning = stats$by_meaning,
        by_table = stats$by_table,
        signatures = signatures
      )

      jsonlite::write_json(report_data, output_file, pretty = TRUE, auto_unbox = TRUE)

    } else {
      lines <- c(
        "===============================================================================",
        "                    ELECTRONIC SIGNATURE REPORT",
        "                      21 CFR Part 11 Compliant",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Generated:", Sys.time()),
        paste("Prepared By:", prepared_by),
        if (!is.null(start_date)) paste("Date Range:", start_date, "to", end_date) else "",
        "",
        "-------------------------------------------------------------------------------",
        "                              SUMMARY",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Signatures:", stats$summary$total_signatures),
        paste("Valid Signatures:", stats$summary$valid_signatures),
        paste("Invalidated:", stats$summary$invalidated_signatures),
        paste("Failed Attempts:", stats$summary$failed_attempts),
        "",
        "-------------------------------------------------------------------------------",
        "                       SIGNATURES BY MEANING",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(stats$by_meaning) > 0) {
        for (i in seq_len(nrow(stats$by_meaning))) {
          lines <- c(lines, sprintf("  %-20s %d",
                                    stats$by_meaning$signature_meaning[i],
                                    stats$by_meaning$count[i]))
        }
      }

      lines <- c(lines,
        "",
        "-------------------------------------------------------------------------------",
        "                        SIGNATURES BY TABLE",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(stats$by_table) > 0) {
        for (i in seq_len(nrow(stats$by_table))) {
          lines <- c(lines, sprintf("  %-25s %d",
                                    stats$by_table$table_name[i],
                                    stats$by_table$count[i]))
        }
      }

      lines <- c(lines,
        "",
        "-------------------------------------------------------------------------------",
        "                       SIGNATURE DETAILS",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(signatures) > 0) {
        for (i in seq_len(min(nrow(signatures), 50))) {
          s <- signatures[i, ]
          lines <- c(lines,
            sprintf("Signature: %s", s$signature_code),
            sprintf("  Signer: %s (%s)", s$signer_full_name, s$signer_user_id),
            sprintf("  Record: %s.%s", s$table_name, s$record_id),
            sprintf("  Meaning: %s", s$signature_meaning),
            sprintf("  Signed: %s | Valid: %s", s$signed_at, ifelse(s$is_valid, "Yes", "No")),
            ""
          )
        }

        if (nrow(signatures) > 50) {
          lines <- c(lines, sprintf("... and %d more signatures", nrow(signatures) - 50))
        }
      }

      lines <- c(lines,
        "",
        "===============================================================================",
        "                              END OF REPORT",
        "==============================================================================="
      )

      writeLines(lines, output_file)
    }

    list(
      success = TRUE,
      output_file = output_file,
      format = format,
      signature_count = nrow(signatures),
      message = "Report generated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Verify Signature Chain Integrity
#'
#' Verifies the hash chain integrity of all signatures.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with verification results
#'
#' @export
verify_signature_chain <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    signatures <- DBI::dbGetQuery(conn, "
      SELECT signature_id, signature_hash, previous_signature_hash
      FROM electronic_signatures
      ORDER BY signature_id ASC
    ")

    if (nrow(signatures) == 0) {
      return(list(
        success = TRUE,
        is_valid = TRUE,
        total_signatures = 0,
        message = "No signatures to verify"
      ))
    }

    invalid_records <- c()

    for (i in seq_len(nrow(signatures))) {
      s <- signatures[i, ]

      expected_prev <- if (i == 1) "GENESIS" else signatures$signature_hash[i - 1]

      if (s$previous_signature_hash != expected_prev) {
        invalid_records <- c(invalid_records, s$signature_id)
      }
    }

    is_valid <- length(invalid_records) == 0

    list(
      success = TRUE,
      is_valid = is_valid,
      total_signatures = nrow(signatures),
      invalid_records = invalid_records,
      message = if (is_valid) {
        "Signature chain integrity verified"
      } else {
        paste("Found", length(invalid_records), "signatures with broken chain")
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
