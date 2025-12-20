#' Data Subject Access Request (DSAR) System
#'
#' GDPR Article 15 compliant system for managing data subject access requests,
#' including identity verification, data collection, and response tracking.

# =============================================================================
# Helper Functions
# =============================================================================

#' Safe Scalar Conversion for DSAR
#'
#' @param x Value to convert
#' @param default Default value if NULL
#' @return Character scalar
#' @keywords internal
safe_scalar_dsar <- function(x, default = NA_character_) {
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

#' Initialize DSAR System
#'
#' Creates database tables for data subject access request management.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with initialization results
#'
#' @export
init_dsar <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS dsar_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT NOT NULL UNIQUE,
        request_type TEXT NOT NULL CHECK(request_type IN
          ('ACCESS', 'RECTIFICATION', 'ERASURE', 'RESTRICTION',
           'PORTABILITY', 'OBJECTION')),
        subject_id TEXT,
        subject_email TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        subject_phone TEXT,
        subject_address TEXT,
        identity_verified BOOLEAN DEFAULT 0,
        identity_verification_method TEXT,
        identity_verified_by TEXT,
        identity_verified_at TIMESTAMP,
        request_details TEXT,
        data_categories TEXT,
        status TEXT NOT NULL DEFAULT 'RECEIVED' CHECK(status IN
          ('RECEIVED', 'IDENTITY_PENDING', 'IDENTITY_VERIFIED', 'IN_PROGRESS',
           'DATA_COLLECTED', 'REVIEW_PENDING', 'COMPLETED', 'REJECTED',
           'EXTENDED', 'CLOSED')),
        received_date DATE NOT NULL,
        due_date DATE NOT NULL,
        extended_due_date DATE,
        extension_reason TEXT,
        completed_date DATE,
        response_method TEXT CHECK(response_method IN
          ('EMAIL', 'POSTAL', 'SECURE_PORTAL', 'IN_PERSON')),
        response_sent_date DATE,
        rejection_reason TEXT,
        assigned_to TEXT,
        priority TEXT DEFAULT 'NORMAL' CHECK(priority IN
          ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
        notes TEXT,
        created_by TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_by TEXT,
        updated_at TIMESTAMP,
        request_hash TEXT NOT NULL,
        previous_hash TEXT,
        metadata TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS dsar_identity_documents (
        document_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES dsar_requests(request_id),
        document_type TEXT NOT NULL CHECK(document_type IN
          ('PASSPORT', 'DRIVERS_LICENSE', 'NATIONAL_ID', 'OTHER')),
        document_reference TEXT,
        verified BOOLEAN DEFAULT 0,
        verification_notes TEXT,
        uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        verified_by TEXT,
        verified_at TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS dsar_data_sources (
        source_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES dsar_requests(request_id),
        source_name TEXT NOT NULL,
        source_type TEXT NOT NULL CHECK(source_type IN
          ('DATABASE', 'FILE_SYSTEM', 'THIRD_PARTY', 'BACKUP', 'ARCHIVE')),
        table_name TEXT,
        records_found INTEGER DEFAULT 0,
        data_collected BOOLEAN DEFAULT 0,
        collection_date TIMESTAMP,
        collected_by TEXT,
        notes TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS dsar_collected_data (
        collection_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES dsar_requests(request_id),
        source_id INTEGER REFERENCES dsar_data_sources(source_id),
        data_category TEXT NOT NULL,
        data_description TEXT,
        record_count INTEGER DEFAULT 0,
        data_format TEXT,
        file_path TEXT,
        file_hash TEXT,
        collected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        collected_by TEXT NOT NULL,
        reviewed BOOLEAN DEFAULT 0,
        reviewed_by TEXT,
        reviewed_at TIMESTAMP,
        redacted BOOLEAN DEFAULT 0,
        redaction_reason TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS dsar_responses (
        response_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES dsar_requests(request_id),
        response_type TEXT NOT NULL CHECK(response_type IN
          ('FULL_DISCLOSURE', 'PARTIAL_DISCLOSURE', 'NO_DATA_FOUND',
           'REJECTION', 'EXTENSION_NOTICE', 'ACKNOWLEDGMENT')),
        response_date DATE NOT NULL,
        response_content TEXT,
        attachments TEXT,
        delivery_method TEXT CHECK(delivery_method IN
          ('EMAIL', 'POSTAL', 'SECURE_PORTAL', 'IN_PERSON')),
        delivery_confirmed BOOLEAN DEFAULT 0,
        delivery_confirmed_date DATE,
        prepared_by TEXT NOT NULL,
        approved_by TEXT,
        approved_at TIMESTAMP,
        response_hash TEXT NOT NULL
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS dsar_audit_log (
        log_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES dsar_requests(request_id),
        action TEXT NOT NULL,
        action_details TEXT,
        performed_by TEXT NOT NULL,
        performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        ip_address TEXT,
        log_hash TEXT NOT NULL,
        previous_log_hash TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_dsar_status
      ON dsar_requests(status)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_dsar_due_date
      ON dsar_requests(due_date)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_dsar_subject_email
      ON dsar_requests(subject_email)
    ")

    list(
      success = TRUE,
      tables_created = 6,
      message = "DSAR system initialized successfully"
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    )
  })
}


# =============================================================================
# Reference Data
# =============================================================================

#' Get DSAR Request Types
#'
#' Returns valid DSAR request types per GDPR Articles 15-22.
#'
#' @return Named list of request types
#'
#' @export
get_dsar_request_types <- function() {
  list(
    ACCESS = "Right of access (Article 15) - Request copy of personal data",
    RECTIFICATION = "Right to rectification (Article 16) - Correct inaccurate data",
    ERASURE = "Right to erasure (Article 17) - Delete personal data",
    RESTRICTION = "Right to restriction (Article 18) - Limit processing",
    PORTABILITY = "Right to data portability (Article 20) - Export data",
    OBJECTION = "Right to object (Article 21) - Object to processing"
  )
}


#' Get DSAR Status Values
#'
#' Returns valid DSAR status values with descriptions.
#'
#' @return Named list of status values
#'
#' @export
get_dsar_statuses <- function() {
  list(
    RECEIVED = "Request received and logged",
    IDENTITY_PENDING = "Awaiting identity verification",
    IDENTITY_VERIFIED = "Identity verified, ready to process",
    IN_PROGRESS = "Data collection in progress",
    DATA_COLLECTED = "All data collected, pending review",
    REVIEW_PENDING = "Data under review before disclosure",
    COMPLETED = "Request fulfilled and response sent",
    REJECTED = "Request rejected with documented reason",
    EXTENDED = "Response deadline extended (max 60 additional days)",
    CLOSED = "Request closed (completed or rejected)"
  )
}


#' Get Data Categories
#'
#' Returns standard personal data categories per GDPR.
#'
#' @return Named list of data categories
#'
#' @export
get_data_categories <- function() {
  list(
    IDENTITY = "Identity data (name, ID numbers, date of birth)",
    CONTACT = "Contact data (address, email, phone)",
    HEALTH = "Health data (medical records, diagnoses, treatments)",
    BIOMETRIC = "Biometric data (fingerprints, facial recognition)",
    GENETIC = "Genetic data (DNA, genetic test results)",
    DEMOGRAPHIC = "Demographic data (age, gender, ethnicity)",
    FINANCIAL = "Financial data (payment information)",
    EMPLOYMENT = "Employment data (job history, qualifications)",
    LOCATION = "Location data (GPS, travel history)",
    BEHAVIORAL = "Behavioral data (preferences, habits)",
    CONSENT = "Consent records",
    COMMUNICATIONS = "Communication records (emails, messages)"
  )
}


# =============================================================================
# Request Management
# =============================================================================

#' Generate Request Number
#'
#' Generates a unique DSAR request number.
#'
#' @param request_type Character: Request type
#'
#' @return Character: Request number
#'
#' @keywords internal
generate_request_number <- function(request_type) {
  prefix <- switch(request_type,
    "ACCESS" = "DSAR-ACC",
    "RECTIFICATION" = "DSAR-REC",
    "ERASURE" = "DSAR-ERA",
    "RESTRICTION" = "DSAR-RES",
    "PORTABILITY" = "DSAR-POR",
    "OBJECTION" = "DSAR-OBJ",
    "DSAR"
  )
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(0:9, 4, replace = TRUE), collapse = "")
  paste0(prefix, "-", timestamp, "-", random)
}


#' Create DSAR Request
#'
#' Creates a new data subject access request.
#'
#' @param request_type Character: Type of request (ACCESS, RECTIFICATION, etc.)
#' @param subject_email Character: Data subject's email
#' @param subject_name Character: Data subject's full name
#' @param created_by Character: User creating the request
#' @param subject_id Character: Subject ID if known (optional)
#' @param subject_phone Character: Subject phone (optional)
#' @param subject_address Character: Subject address (optional)
#' @param request_details Character: Additional details (optional)
#' @param data_categories Character vector: Requested data categories (optional)
#' @param priority Character: Priority level (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
create_dsar_request <- function(request_type,
                                 subject_email,
                                 subject_name,
                                 created_by,
                                 subject_id = NULL,
                                 subject_phone = NULL,
                                 subject_address = NULL,
                                 request_details = NULL,
                                 data_categories = NULL,
                                 priority = "NORMAL",
                                 db_path = NULL) {

  valid_types <- names(get_dsar_request_types())
  if (!request_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid request type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  if (!priority %in% c("LOW", "NORMAL", "HIGH", "URGENT")) {
    return(list(
      success = FALSE,
      error = "Priority must be LOW, NORMAL, HIGH, or URGENT"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request_number <- generate_request_number(request_type)
    received_date <- Sys.Date()
    due_date <- received_date + 30

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT request_hash FROM dsar_requests
      ORDER BY request_id DESC LIMIT 1
    ")
    previous_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$request_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      request_number, request_type, subject_email, subject_name,
      created_by, timestamp, previous_hash,
      sep = "|"
    )
    request_hash <- digest::digest(hash_content, algo = "sha256")

    categories_str <- if (!is.null(data_categories)) {
      paste(data_categories, collapse = ";")
    } else {
      NA_character_
    }

    DBI::dbExecute(conn, "
      INSERT INTO dsar_requests (
        request_number, request_type, subject_id, subject_email, subject_name,
        subject_phone, subject_address, request_details, data_categories,
        status, received_date, due_date, priority, created_by,
        request_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'RECEIVED', ?, ?, ?, ?, ?, ?)
    ", list(
      request_number,
      safe_scalar_dsar(request_type),
      safe_scalar_dsar(subject_id),
      safe_scalar_dsar(subject_email),
      safe_scalar_dsar(subject_name),
      safe_scalar_dsar(subject_phone),
      safe_scalar_dsar(subject_address),
      safe_scalar_dsar(request_details),
      safe_scalar_dsar(categories_str),
      as.character(received_date),
      as.character(due_date),
      safe_scalar_dsar(priority),
      safe_scalar_dsar(created_by),
      request_hash,
      previous_hash
    ))

    request_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_dsar_action(
      request_id = request_id,
      action = "REQUEST_CREATED",
      action_details = paste("DSAR request created:", request_type),
      performed_by = created_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      request_id = request_id,
      request_number = request_number,
      due_date = as.character(due_date),
      message = "DSAR request created successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Log DSAR Action
#'
#' Logs an action in the DSAR audit trail.
#'
#' @param request_id Integer: Request ID
#' @param action Character: Action performed
#' @param action_details Character: Action details
#' @param performed_by Character: User performing action
#' @param ip_address Character: IP address (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with logging result
#'
#' @keywords internal
log_dsar_action <- function(request_id,
                             action,
                             action_details,
                             performed_by,
                             ip_address = NULL,
                             db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT log_hash FROM dsar_audit_log
      WHERE request_id = ?
      ORDER BY log_id DESC LIMIT 1
    ", list(request_id))

    previous_log_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$log_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      request_id, action, action_details, performed_by, timestamp, previous_log_hash,
      sep = "|"
    )
    log_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO dsar_audit_log (
        request_id, action, action_details, performed_by, ip_address,
        log_hash, previous_log_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      safe_scalar_dsar(action),
      safe_scalar_dsar(action_details),
      safe_scalar_dsar(performed_by),
      safe_scalar_dsar(ip_address),
      log_hash,
      previous_log_hash
    ))

    list(success = TRUE)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Identity Verification
# =============================================================================

#' Verify Subject Identity
#'
#' Records identity verification for a DSAR request.
#'
#' @param request_id Integer: Request ID
#' @param verification_method Character: Method used for verification
#' @param verified_by Character: User verifying identity
#' @param document_type Character: Document type used (optional)
#' @param document_reference Character: Document reference (optional)
#' @param verification_notes Character: Notes (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with verification result
#'
#' @export
verify_subject_identity <- function(request_id,
                                     verification_method,
                                     verified_by,
                                     document_type = NULL,
                                     document_reference = NULL,
                                     verification_notes = NULL,
                                     db_path = NULL) {

  valid_methods <- c("DOCUMENT_CHECK", "KNOWLEDGE_BASED", "EMAIL_CONFIRMATION",
                     "PHONE_CONFIRMATION", "IN_PERSON", "TWO_FACTOR")

  if (!verification_method %in% valid_methods) {
    return(list(
      success = FALSE,
      error = paste("Invalid verification method. Must be one of:",
                    paste(valid_methods, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request <- DBI::dbGetQuery(conn, "
      SELECT status FROM dsar_requests WHERE request_id = ?
    ", list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE dsar_requests
      SET identity_verified = 1,
          identity_verification_method = ?,
          identity_verified_by = ?,
          identity_verified_at = ?,
          status = 'IDENTITY_VERIFIED',
          updated_by = ?,
          updated_at = ?
      WHERE request_id = ?
    ", list(
      safe_scalar_dsar(verification_method),
      safe_scalar_dsar(verified_by),
      timestamp,
      safe_scalar_dsar(verified_by),
      timestamp,
      request_id
    ))

    if (!is.null(document_type)) {
      DBI::dbExecute(conn, "
        INSERT INTO dsar_identity_documents (
          request_id, document_type, document_reference, verified,
          verification_notes, verified_by, verified_at
        ) VALUES (?, ?, ?, 1, ?, ?, ?)
      ", list(
        request_id,
        safe_scalar_dsar(document_type),
        safe_scalar_dsar(document_reference),
        safe_scalar_dsar(verification_notes),
        safe_scalar_dsar(verified_by),
        timestamp
      ))
    }

    log_dsar_action(
      request_id = request_id,
      action = "IDENTITY_VERIFIED",
      action_details = paste("Identity verified using:", verification_method),
      performed_by = verified_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      request_id = request_id,
      message = "Identity verified successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Data Collection
# =============================================================================

#' Add Data Source
#'
#' Registers a data source to be searched for a DSAR request.
#'
#' @param request_id Integer: Request ID
#' @param source_name Character: Source name
#' @param source_type Character: Source type (DATABASE, FILE_SYSTEM, etc.)
#' @param table_name Character: Table name if database (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with source addition result
#'
#' @export
add_dsar_data_source <- function(request_id,
                                  source_name,
                                  source_type,
                                  table_name = NULL,
                                  db_path = NULL) {

  valid_types <- c("DATABASE", "FILE_SYSTEM", "THIRD_PARTY", "BACKUP", "ARCHIVE")
  if (!source_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid source type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      INSERT INTO dsar_data_sources (
        request_id, source_name, source_type, table_name
      ) VALUES (?, ?, ?, ?)
    ", list(
      request_id,
      safe_scalar_dsar(source_name),
      safe_scalar_dsar(source_type),
      safe_scalar_dsar(table_name)
    ))

    source_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    list(
      success = TRUE,
      source_id = source_id,
      message = "Data source added successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Record Data Collection
#'
#' Records data collected from a source for a DSAR request.
#'
#' @param request_id Integer: Request ID
#' @param data_category Character: Data category collected
#' @param record_count Integer: Number of records collected
#' @param collected_by Character: User collecting data
#' @param source_id Integer: Source ID (optional)
#' @param data_description Character: Description (optional)
#' @param data_format Character: Format (CSV, JSON, etc.) (optional)
#' @param file_path Character: Path to exported file (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with collection result
#'
#' @export
record_data_collection <- function(request_id,
                                    data_category,
                                    record_count,
                                    collected_by,
                                    source_id = NULL,
                                    data_description = NULL,
                                    data_format = NULL,
                                    file_path = NULL,
                                    db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    file_hash <- if (!is.null(file_path) && file.exists(file_path)) {
      digest::digest(file = file_path, algo = "sha256")
    } else {
      NA_character_
    }

    DBI::dbExecute(conn, "
      INSERT INTO dsar_collected_data (
        request_id, source_id, data_category, data_description,
        record_count, data_format, file_path, file_hash, collected_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      source_id,
      safe_scalar_dsar(data_category),
      safe_scalar_dsar(data_description),
      record_count,
      safe_scalar_dsar(data_format),
      safe_scalar_dsar(file_path),
      safe_scalar_dsar(file_hash),
      safe_scalar_dsar(collected_by)
    ))

    collection_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    if (!is.null(source_id)) {
      DBI::dbExecute(conn, "
        UPDATE dsar_data_sources
        SET records_found = records_found + ?,
            data_collected = 1,
            collection_date = ?,
            collected_by = ?
        WHERE source_id = ?
      ", list(
        record_count,
        as.character(Sys.time()),
        safe_scalar_dsar(collected_by),
        source_id
      ))
    }

    log_dsar_action(
      request_id = request_id,
      action = "DATA_COLLECTED",
      action_details = paste("Collected", record_count, "records from", data_category),
      performed_by = collected_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      collection_id = collection_id,
      message = "Data collection recorded successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Mark Data Collection Complete
#'
#' Marks data collection as complete and updates request status.
#'
#' @param request_id Integer: Request ID
#' @param completed_by Character: User completing collection
#' @param db_path Character: Database path (optional)
#'
#' @return List with completion result
#'
#' @export
complete_data_collection <- function(request_id, completed_by, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      UPDATE dsar_requests
      SET status = 'DATA_COLLECTED',
          updated_by = ?,
          updated_at = ?
      WHERE request_id = ?
    ", list(
      safe_scalar_dsar(completed_by),
      as.character(Sys.time()),
      request_id
    ))

    log_dsar_action(
      request_id = request_id,
      action = "DATA_COLLECTION_COMPLETE",
      action_details = "All data collection completed",
      performed_by = completed_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      message = "Data collection marked as complete"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Response Management
# =============================================================================

#' Create DSAR Response
#'
#' Creates and records a response to a DSAR request.
#'
#' @param request_id Integer: Request ID
#' @param response_type Character: Response type
#' @param response_content Character: Response content
#' @param prepared_by Character: User preparing response
#' @param delivery_method Character: Delivery method
#' @param attachments Character: Attachment descriptions (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with response result
#'
#' @export
create_dsar_response <- function(request_id,
                                  response_type,
                                  response_content,
                                  prepared_by,
                                  delivery_method,
                                  attachments = NULL,
                                  db_path = NULL) {

  valid_types <- c("FULL_DISCLOSURE", "PARTIAL_DISCLOSURE", "NO_DATA_FOUND",
                   "REJECTION", "EXTENSION_NOTICE", "ACKNOWLEDGMENT")
  if (!response_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid response type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  valid_methods <- c("EMAIL", "POSTAL", "SECURE_PORTAL", "IN_PERSON")
  if (!delivery_method %in% valid_methods) {
    return(list(
      success = FALSE,
      error = paste("Invalid delivery method. Must be one of:",
                    paste(valid_methods, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    response_date <- Sys.Date()

    hash_content <- paste(
      request_id, response_type, response_content, prepared_by,
      as.character(Sys.time()),
      sep = "|"
    )
    response_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO dsar_responses (
        request_id, response_type, response_date, response_content,
        attachments, delivery_method, prepared_by, response_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      safe_scalar_dsar(response_type),
      as.character(response_date),
      safe_scalar_dsar(response_content),
      safe_scalar_dsar(attachments),
      safe_scalar_dsar(delivery_method),
      safe_scalar_dsar(prepared_by),
      response_hash
    ))

    response_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_dsar_action(
      request_id = request_id,
      action = "RESPONSE_CREATED",
      action_details = paste("Response created:", response_type),
      performed_by = prepared_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      response_id = response_id,
      message = "Response created successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Complete DSAR Request
#'
#' Marks a DSAR request as completed.
#'
#' @param request_id Integer: Request ID
#' @param completed_by Character: User completing request
#' @param response_method Character: How response was delivered
#' @param db_path Character: Database path (optional)
#'
#' @return List with completion result
#'
#' @export
complete_dsar_request <- function(request_id,
                                   completed_by,
                                   response_method,
                                   db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    timestamp <- as.character(Sys.time())
    completed_date <- Sys.Date()

    DBI::dbExecute(conn, "
      UPDATE dsar_requests
      SET status = 'COMPLETED',
          completed_date = ?,
          response_method = ?,
          response_sent_date = ?,
          updated_by = ?,
          updated_at = ?
      WHERE request_id = ?
    ", list(
      as.character(completed_date),
      safe_scalar_dsar(response_method),
      as.character(completed_date),
      safe_scalar_dsar(completed_by),
      timestamp,
      request_id
    ))

    log_dsar_action(
      request_id = request_id,
      action = "REQUEST_COMPLETED",
      action_details = paste("Request completed via", response_method),
      performed_by = completed_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      completed_date = as.character(completed_date),
      message = "DSAR request completed successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Extend DSAR Deadline
#'
#' Extends the deadline for a DSAR request (max 60 additional days per GDPR).
#'
#' @param request_id Integer: Request ID
#' @param extension_days Integer: Days to extend (max 60)
#' @param extension_reason Character: Reason for extension
#' @param extended_by Character: User extending deadline
#' @param db_path Character: Database path (optional)
#'
#' @return List with extension result
#'
#' @export
extend_dsar_deadline <- function(request_id,
                                  extension_days,
                                  extension_reason,
                                  extended_by,
                                  db_path = NULL) {

  if (extension_days < 1 || extension_days > 60) {
    return(list(
      success = FALSE,
      error = "Extension must be between 1 and 60 days per GDPR Article 12(3)"
    ))
  }

  if (nchar(extension_reason) < 10) {
    return(list(
      success = FALSE,
      error = "Extension reason must be at least 10 characters"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request <- DBI::dbGetQuery(conn, "
      SELECT due_date, extended_due_date FROM dsar_requests
      WHERE request_id = ?
    ", list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (!is.na(request$extended_due_date)) {
      return(list(success = FALSE, error = "Request has already been extended"))
    }

    new_due_date <- as.Date(request$due_date) + extension_days
    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE dsar_requests
      SET status = 'EXTENDED',
          extended_due_date = ?,
          extension_reason = ?,
          updated_by = ?,
          updated_at = ?
      WHERE request_id = ?
    ", list(
      as.character(new_due_date),
      safe_scalar_dsar(extension_reason),
      safe_scalar_dsar(extended_by),
      timestamp,
      request_id
    ))

    log_dsar_action(
      request_id = request_id,
      action = "DEADLINE_EXTENDED",
      action_details = paste("Extended by", extension_days, "days. New deadline:",
                             as.character(new_due_date)),
      performed_by = extended_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      original_due_date = as.character(request$due_date),
      extended_due_date = as.character(new_due_date),
      message = "Deadline extended successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Reject DSAR Request
#'
#' Rejects a DSAR request with documented reason.
#'
#' @param request_id Integer: Request ID
#' @param rejection_reason Character: Reason for rejection (min 20 chars)
#' @param rejected_by Character: User rejecting request
#' @param db_path Character: Database path (optional)
#'
#' @return List with rejection result
#'
#' @export
reject_dsar_request <- function(request_id,
                                 rejection_reason,
                                 rejected_by,
                                 db_path = NULL) {

  if (nchar(rejection_reason) < 20) {
    return(list(
      success = FALSE,
      error = "Rejection reason must be at least 20 characters"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE dsar_requests
      SET status = 'REJECTED',
          rejection_reason = ?,
          completed_date = ?,
          updated_by = ?,
          updated_at = ?
      WHERE request_id = ?
    ", list(
      safe_scalar_dsar(rejection_reason),
      as.character(Sys.Date()),
      safe_scalar_dsar(rejected_by),
      timestamp,
      request_id
    ))

    log_dsar_action(
      request_id = request_id,
      action = "REQUEST_REJECTED",
      action_details = paste("Rejected:", rejection_reason),
      performed_by = rejected_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      message = "Request rejected successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Retrieval Functions
# =============================================================================

#' Get DSAR Request
#'
#' Retrieves a DSAR request with full details.
#'
#' @param request_id Integer: Request ID (optional)
#' @param request_number Character: Request number (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with request details
#'
#' @export
get_dsar_request <- function(request_id = NULL,
                              request_number = NULL,
                              db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (!is.null(request_id)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM dsar_requests WHERE request_id = ?
      ", list(request_id))
    } else if (!is.null(request_number)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM dsar_requests WHERE request_number = ?
      ", list(safe_scalar_dsar(request_number)))
    } else {
      data.frame()
    }

  }, error = function(e) data.frame())
}


#' Get Pending DSAR Requests
#'
#' Retrieves DSAR requests that are pending or overdue.
#'
#' @param include_overdue Logical: Include only overdue requests
#' @param assigned_to Character: Filter by assigned user (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with pending requests
#'
#' @export
get_pending_dsar_requests <- function(include_overdue = FALSE,
                                       assigned_to = NULL,
                                       db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    query <- "
      SELECT *,
        CASE
          WHEN extended_due_date IS NOT NULL THEN extended_due_date
          ELSE due_date
        END as effective_due_date
      FROM dsar_requests
      WHERE status NOT IN ('COMPLETED', 'REJECTED', 'CLOSED')
    "
    params <- list()

    if (include_overdue) {
      query <- paste(query, "AND (
        (extended_due_date IS NOT NULL AND extended_due_date < date('now'))
        OR (extended_due_date IS NULL AND due_date < date('now'))
      )")
    }

    if (!is.null(assigned_to)) {
      query <- paste(query, "AND assigned_to = ?")
      params <- c(params, list(safe_scalar_dsar(assigned_to)))
    }

    query <- paste(query, "ORDER BY due_date ASC")

    if (length(params) > 0) {
      DBI::dbGetQuery(conn, query, params)
    } else {
      DBI::dbGetQuery(conn, query)
    }

  }, error = function(e) data.frame())
}


#' Get DSAR Audit Log
#'
#' Retrieves the audit log for a DSAR request.
#'
#' @param request_id Integer: Request ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with audit log entries
#'
#' @export
get_dsar_audit_log <- function(request_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM dsar_audit_log
      WHERE request_id = ?
      ORDER BY performed_at ASC
    ", list(request_id))

  }, error = function(e) data.frame())
}


#' Get Collected Data
#'
#' Retrieves collected data records for a DSAR request.
#'
#' @param request_id Integer: Request ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with collected data
#'
#' @export
get_dsar_collected_data <- function(request_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT cd.*, ds.source_name, ds.source_type
      FROM dsar_collected_data cd
      LEFT JOIN dsar_data_sources ds ON cd.source_id = ds.source_id
      WHERE cd.request_id = ?
      ORDER BY cd.collected_at ASC
    ", list(request_id))

  }, error = function(e) data.frame())
}


# =============================================================================
# Statistics and Reporting
# =============================================================================

#' Get DSAR Statistics
#'
#' Returns DSAR statistics.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with DSAR statistics
#'
#' @export
get_dsar_statistics <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    overall <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_requests,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status NOT IN ('COMPLETED', 'REJECTED', 'CLOSED') THEN 1 ELSE 0 END) as pending
      FROM dsar_requests
    ")

    by_type <- DBI::dbGetQuery(conn, "
      SELECT request_type, COUNT(*) as count
      FROM dsar_requests
      GROUP BY request_type
      ORDER BY count DESC
    ")

    by_status <- DBI::dbGetQuery(conn, "
      SELECT status, COUNT(*) as count
      FROM dsar_requests
      GROUP BY status
      ORDER BY count DESC
    ")

    overdue <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as count
      FROM dsar_requests
      WHERE status NOT IN ('COMPLETED', 'REJECTED', 'CLOSED')
        AND (
          (extended_due_date IS NOT NULL AND extended_due_date < date('now'))
          OR (extended_due_date IS NULL AND due_date < date('now'))
        )
    ")

    avg_response <- DBI::dbGetQuery(conn, "
      SELECT AVG(julianday(completed_date) - julianday(received_date)) as avg_days
      FROM dsar_requests
      WHERE status = 'COMPLETED' AND completed_date IS NOT NULL
    ")

    list(
      success = TRUE,
      overall = list(
        total_requests = overall$total_requests,
        completed = overall$completed,
        rejected = overall$rejected,
        pending = overall$pending
      ),
      by_type = by_type,
      by_status = by_status,
      overdue_count = overdue$count,
      average_response_days = round(avg_response$avg_days, 1)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Generate DSAR Report
#'
#' Generates a DSAR compliance report.
#'
#' @param output_file Character: Output file path
#' @param format Character: Report format (txt or json)
#' @param organization Character: Organization name
#' @param prepared_by Character: Report preparer
#' @param db_path Character: Database path (optional)
#'
#' @return List with report generation status
#'
#' @export
generate_dsar_report <- function(output_file,
                                  format = "txt",
                                  organization = "Organization",
                                  prepared_by = "DPO",
                                  db_path = NULL) {
  tryCatch({
    stats <- get_dsar_statistics(db_path = db_path)

    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    requests <- DBI::dbGetQuery(conn, "
      SELECT request_number, request_type, subject_name, status,
             received_date, due_date, extended_due_date, completed_date
      FROM dsar_requests
      ORDER BY received_date DESC
      LIMIT 100
    ")

    if (format == "json") {
      report_data <- list(
        report_type = "DSAR Compliance Report",
        organization = organization,
        generated_at = as.character(Sys.time()),
        prepared_by = prepared_by,
        statistics = stats,
        recent_requests = requests
      )

      jsonlite::write_json(report_data, output_file, pretty = TRUE, auto_unbox = TRUE)

    } else {
      lines <- c(
        "===============================================================================",
        "                    DSAR COMPLIANCE REPORT",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Generated:", Sys.time()),
        paste("Prepared By:", prepared_by),
        "",
        "-------------------------------------------------------------------------------",
        "                              SUMMARY",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Requests:", stats$overall$total_requests),
        paste("Completed:", stats$overall$completed),
        paste("Rejected:", stats$overall$rejected),
        paste("Pending:", stats$overall$pending),
        paste("Overdue:", stats$overdue_count),
        paste("Average Response Time:", stats$average_response_days, "days"),
        ""
      )

      if (nrow(stats$by_type) > 0) {
        lines <- c(lines, "By Request Type:")
        for (i in seq_len(nrow(stats$by_type))) {
          lines <- c(lines, sprintf("  %-15s %d",
                                    stats$by_type$request_type[i],
                                    stats$by_type$count[i]))
        }
        lines <- c(lines, "")
      }

      lines <- c(lines,
        "-------------------------------------------------------------------------------",
        "                          RECENT REQUESTS",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(requests) > 0) {
        for (i in seq_len(min(20, nrow(requests)))) {
          req <- requests[i, ]
          lines <- c(lines,
            paste(req$request_number, "-", req$request_type),
            paste("  Subject:", req$subject_name),
            paste("  Status:", req$status),
            paste("  Received:", req$received_date),
            paste("  Due:", req$due_date),
            ""
          )
        }
      } else {
        lines <- c(lines, "No requests recorded.", "")
      }

      lines <- c(lines,
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
      message = "Report generated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
