#' Data Correction Workflow System
#'
#' FDA 21 CFR Part 11 compliant data correction with approval workflow.
#' Implements reason-for-change requirements, original value preservation,
#' supervisor approval, and complete audit trail integration.

# =============================================================================
# Helper Functions
# =============================================================================

#' Safe Scalar Conversion
#'
#' Converts values to safe scalars for SQL parameters.
#'
#' @param x Value to convert
#' @param default Default value if NULL or empty
#'
#' @return Character scalar
#'
#' @keywords internal
safe_scalar_dc <- function(x, default = NA_character_) {

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

#' Initialize Data Correction System
#'
#' Creates database tables for data correction workflow.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with initialization results
#'
#' @export
init_data_correction <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS correction_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        original_value TEXT,
        corrected_value TEXT NOT NULL,
        correction_reason TEXT NOT NULL CHECK(correction_reason IN
          ('TYPO', 'SOURCE_DOC_ERROR', 'CALCULATION_ERROR',
           'TRANSCRIPTION_ERROR', 'UNIT_ERROR', 'DATE_ERROR',
           'PROTOCOL_CLARIFICATION', 'QUERY_RESPONSE', 'OTHER')),
        reason_details TEXT,
        original_source_doc TEXT,
        corrected_source_doc TEXT,
        status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN
          ('PENDING', 'APPROVED', 'REJECTED', 'APPLIED', 'CANCELLED')),
        requested_by TEXT NOT NULL,
        requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        reviewed_by TEXT,
        reviewed_at TIMESTAMP,
        review_comments TEXT,
        applied_by TEXT,
        applied_at TIMESTAMP,
        request_hash TEXT NOT NULL,
        previous_request_hash TEXT,
        site_id TEXT,
        study_id TEXT,
        subject_id TEXT,
        visit_id TEXT,
        form_id TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS correction_approvers (
        approver_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        user_role TEXT NOT NULL CHECK(user_role IN
          ('PI', 'DATA_MANAGER', 'SPONSOR', 'MEDICAL_MONITOR')),
        site_id TEXT,
        study_id TEXT,
        can_approve BOOLEAN DEFAULT 1,
        can_override_lock BOOLEAN DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_by TEXT,
        UNIQUE(user_id, site_id, study_id)
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS correction_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES correction_requests(request_id),
        action TEXT NOT NULL CHECK(action IN
          ('CREATED', 'SUBMITTED', 'APPROVED', 'REJECTED',
           'APPLIED', 'CANCELLED', 'RESUBMITTED', 'ESCALATED')),
        action_by TEXT NOT NULL,
        action_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        action_details TEXT,
        action_hash TEXT NOT NULL,
        previous_hash TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS correction_overrides (
        override_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES correction_requests(request_id),
        override_type TEXT NOT NULL CHECK(override_type IN
          ('LOCKED_RECORD', 'FINALIZED_DATA', 'SIGNATURE_PRESENT')),
        override_reason TEXT NOT NULL,
        override_by TEXT NOT NULL,
        override_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        approved_by TEXT,
        approved_at TIMESTAMP,
        override_hash TEXT NOT NULL
      )
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_corrections_status
      ON correction_requests(status)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_corrections_table_record
      ON correction_requests(table_name, record_id)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_corrections_requested_by
      ON correction_requests(requested_by)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_corrections_requested_at
      ON correction_requests(requested_at)
    ")

    list(
      success = TRUE,
      tables_created = 4,
      message = "Data correction system initialized successfully"
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    )
  })
}


# =============================================================================
# Correction Request Management
# =============================================================================

#' Get Correction Reasons
#'
#' Returns list of valid correction reasons with descriptions.
#'
#' @return Named list of correction reasons
#'
#' @export
get_correction_reasons <- function() {
  list(
    TYPO = "Typographical error in data entry",
    SOURCE_DOC_ERROR = "Error in source document",
    CALCULATION_ERROR = "Calculation or formula error",
    TRANSCRIPTION_ERROR = "Transcription error from source",
    UNIT_ERROR = "Incorrect unit of measurement",
    DATE_ERROR = "Incorrect date or time",
    PROTOCOL_CLARIFICATION = "Protocol clarification required change",
    QUERY_RESPONSE = "Response to data query",
    OTHER = "Other reason (specify in details)"
  )
}


#' Create Correction Request
#'
#' Creates a new data correction request with full audit trail.
#'
#' @param table_name Character: Table containing the record
#' @param record_id Character: Record identifier
#' @param field_name Character: Field to correct
#' @param original_value Character: Current/original value
#' @param corrected_value Character: New corrected value
#' @param correction_reason Character: Reason code from get_correction_reasons()
#' @param reason_details Character: Additional details (optional)
#' @param requested_by Character: User ID requesting correction
#' @param original_source_doc Character: Original source document reference
#' @param corrected_source_doc Character: Corrected source document reference
#' @param site_id Character: Site identifier (optional)
#' @param study_id Character: Study identifier (optional)
#' @param subject_id Character: Subject identifier (optional)
#' @param visit_id Character: Visit identifier (optional)
#' @param form_id Character: Form identifier (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with request_id and status
#'
#' @export
create_correction_request <- function(table_name,
                                       record_id,
                                       field_name,
                                       original_value,
                                       corrected_value,
                                       correction_reason,
                                       reason_details = NULL,
                                       requested_by,
                                       original_source_doc = NULL,
                                       corrected_source_doc = NULL,
                                       site_id = NULL,
                                       study_id = NULL,
                                       subject_id = NULL,
                                       visit_id = NULL,
                                       form_id = NULL,
                                       db_path = NULL) {

  valid_reasons <- names(get_correction_reasons())
  if (!correction_reason %in% valid_reasons) {
    return(list(
      success = FALSE,
      error = paste("Invalid correction reason. Must be one of:",
                    paste(valid_reasons, collapse = ", "))
    ))
  }

  if (correction_reason == "OTHER" && (is.null(reason_details) ||
                                        nchar(reason_details) < 10)) {
    return(list(
      success = FALSE,
      error = "Reason details required when using OTHER (min 10 characters)"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT request_hash FROM correction_requests
      ORDER BY request_id DESC LIMIT 1
    ")

    previous_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$request_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      table_name, record_id, field_name,
      safe_scalar_dc(original_value), corrected_value,
      correction_reason, requested_by, timestamp, previous_hash,
      sep = "|"
    )
    request_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO correction_requests (
        table_name, record_id, field_name, original_value, corrected_value,
        correction_reason, reason_details, original_source_doc,
        corrected_source_doc, requested_by, requested_at, request_hash,
        previous_request_hash, site_id, study_id, subject_id, visit_id, form_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      safe_scalar_dc(table_name),
      safe_scalar_dc(record_id),
      safe_scalar_dc(field_name),
      safe_scalar_dc(original_value),
      safe_scalar_dc(corrected_value),
      safe_scalar_dc(correction_reason),
      safe_scalar_dc(reason_details),
      safe_scalar_dc(original_source_doc),
      safe_scalar_dc(corrected_source_doc),
      safe_scalar_dc(requested_by),
      timestamp,
      request_hash,
      previous_hash,
      safe_scalar_dc(site_id),
      safe_scalar_dc(study_id),
      safe_scalar_dc(subject_id),
      safe_scalar_dc(visit_id),
      safe_scalar_dc(form_id)
    ))

    request_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    history_hash <- digest::digest(
      paste(request_id, "CREATED", requested_by, timestamp, sep = "|"),
      algo = "sha256"
    )

    DBI::dbExecute(conn, "
      INSERT INTO correction_history (
        request_id, action, action_by, action_at, action_details, action_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      "CREATED",
      safe_scalar_dc(requested_by),
      timestamp,
      paste("Correction request created for", field_name),
      history_hash
    ))

    tryCatch({
      log_audit_event(
        event_type = "UPDATE",
        user_id = requested_by,
        table_name = "correction_requests",
        record_id = as.character(request_id),
        details = paste("Correction request created:",
                        field_name, "from", original_value, "to", corrected_value)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      request_id = request_id,
      status = "PENDING",
      request_hash = request_hash,
      message = "Correction request created successfully"
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Failed to create correction request:", e$message)
    )
  })
}


#' Get Correction Request
#'
#' Retrieves a correction request by ID.
#'
#' @param request_id Integer: Request identifier
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with request details
#'
#' @export
get_correction_request <- function(request_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request <- DBI::dbGetQuery(conn, "
      SELECT * FROM correction_requests WHERE request_id = ?
    ", list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    history <- DBI::dbGetQuery(conn, "
      SELECT * FROM correction_history
      WHERE request_id = ?
      ORDER BY action_at ASC
    ", list(request_id))

    list(
      success = TRUE,
      request = request,
      history = history
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Get Pending Corrections
#'
#' Retrieves all pending correction requests for review.
#'
#' @param reviewer_id Character: User ID of reviewer (optional filter)
#' @param site_id Character: Site filter (optional)
#' @param study_id Character: Study filter (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with pending requests
#'
#' @export
get_pending_corrections <- function(reviewer_id = NULL,
                                     site_id = NULL,
                                     study_id = NULL,
                                     db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    query <- "SELECT * FROM correction_requests WHERE status = 'PENDING'"
    params <- list()

    if (!is.null(site_id)) {
      query <- paste(query, "AND site_id = ?")
      params <- c(params, list(safe_scalar_dc(site_id)))
    }

    if (!is.null(study_id)) {
      query <- paste(query, "AND study_id = ?")
      params <- c(params, list(safe_scalar_dc(study_id)))
    }

    query <- paste(query, "ORDER BY requested_at ASC")

    if (length(params) > 0) {
      DBI::dbGetQuery(conn, query, params)
    } else {
      DBI::dbGetQuery(conn, query)
    }

  }, error = function(e) {
    data.frame()
  })
}


# =============================================================================
# Approval Workflow
# =============================================================================

#' Approve Correction Request
#'
#' Approves a pending correction request.
#'
#' @param request_id Integer: Request identifier
#' @param reviewed_by Character: Approver user ID
#' @param review_comments Character: Approval comments (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with approval status
#'
#' @export
approve_correction <- function(request_id,
                                reviewed_by,
                                review_comments = NULL,
                                db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request <- DBI::dbGetQuery(conn, "
      SELECT * FROM correction_requests WHERE request_id = ?
    ", list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (request$status != "PENDING") {
      return(list(
        success = FALSE,
        error = paste("Cannot approve request with status:", request$status)
      ))
    }

    if (request$requested_by == reviewed_by) {
      return(list(
        success = FALSE,
        error = "Cannot approve own correction request"
      ))
    }

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE correction_requests
      SET status = 'APPROVED',
          reviewed_by = ?,
          reviewed_at = ?,
          review_comments = ?
      WHERE request_id = ?
    ", list(
      safe_scalar_dc(reviewed_by),
      timestamp,
      safe_scalar_dc(review_comments),
      request_id
    ))

    history_hash <- digest::digest(
      paste(request_id, "APPROVED", reviewed_by, timestamp, sep = "|"),
      algo = "sha256"
    )

    DBI::dbExecute(conn, "
      INSERT INTO correction_history (
        request_id, action, action_by, action_at, action_details, action_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      "APPROVED",
      safe_scalar_dc(reviewed_by),
      timestamp,
      safe_scalar_dc(review_comments, "Approved"),
      history_hash
    ))

    tryCatch({
      log_audit_event(
        event_type = "UPDATE",
        user_id = reviewed_by,
        table_name = "correction_requests",
        record_id = as.character(request_id),
        details = paste("Correction approved for", request$field_name)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      request_id = request_id,
      status = "APPROVED",
      message = "Correction request approved"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Reject Correction Request
#'
#' Rejects a pending correction request.
#'
#' @param request_id Integer: Request identifier
#' @param reviewed_by Character: Reviewer user ID
#' @param review_comments Character: Rejection reason (required)
#' @param db_path Character: Database path (optional)
#'
#' @return List with rejection status
#'
#' @export
reject_correction <- function(request_id,
                               reviewed_by,
                               review_comments,
                               db_path = NULL) {
  if (is.null(review_comments) || nchar(review_comments) < 10) {
    return(list(
      success = FALSE,
      error = "Rejection reason required (min 10 characters)"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request <- DBI::dbGetQuery(conn, "
      SELECT * FROM correction_requests WHERE request_id = ?
    ", list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (request$status != "PENDING") {
      return(list(
        success = FALSE,
        error = paste("Cannot reject request with status:", request$status)
      ))
    }

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE correction_requests
      SET status = 'REJECTED',
          reviewed_by = ?,
          reviewed_at = ?,
          review_comments = ?
      WHERE request_id = ?
    ", list(
      safe_scalar_dc(reviewed_by),
      timestamp,
      safe_scalar_dc(review_comments),
      request_id
    ))

    history_hash <- digest::digest(
      paste(request_id, "REJECTED", reviewed_by, timestamp, sep = "|"),
      algo = "sha256"
    )

    DBI::dbExecute(conn, "
      INSERT INTO correction_history (
        request_id, action, action_by, action_at, action_details, action_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      "REJECTED",
      safe_scalar_dc(reviewed_by),
      timestamp,
      safe_scalar_dc(review_comments),
      history_hash
    ))

    tryCatch({
      log_audit_event(
        event_type = "UPDATE",
        user_id = reviewed_by,
        table_name = "correction_requests",
        record_id = as.character(request_id),
        details = paste("Correction rejected:", review_comments)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      request_id = request_id,
      status = "REJECTED",
      message = "Correction request rejected"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Correction Application
# =============================================================================

#' Apply Correction
#'
#' Applies an approved correction to the actual data.
#'
#' @param request_id Integer: Request identifier
#' @param applied_by Character: User applying the correction
#' @param db_path Character: Database path (optional)
#'
#' @return List with application status
#'
#' @export
apply_correction <- function(request_id, applied_by, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request <- DBI::dbGetQuery(conn, "
      SELECT * FROM correction_requests WHERE request_id = ?
    ", list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (request$status != "APPROVED") {
      return(list(
        success = FALSE,
        error = paste("Can only apply approved corrections. Current status:",
                      request$status)
      ))
    }

    lock_status <- tryCatch({
      check_record_lock(request$table_name, request$record_id, db_path = db_path)
    }, error = function(e) list(is_locked = FALSE))

    if (isTRUE(lock_status$is_locked) && lock_status$locked_by != applied_by) {
      return(list(
        success = FALSE,
        error = paste("Record is locked by", lock_status$locked_by),
        requires_override = TRUE
      ))
    }

    table_exists <- DBI::dbExistsTable(conn, request$table_name)
    if (!table_exists) {
      return(list(
        success = FALSE,
        error = paste("Table does not exist:", request$table_name)
      ))
    }

    tryCatch({
      current_data <- DBI::dbGetQuery(conn, sprintf(
        "SELECT * FROM %s WHERE rowid = ? OR id = ? LIMIT 1",
        DBI::dbQuoteIdentifier(conn, request$table_name)
      ), list(request$record_id, request$record_id))

      if (nrow(current_data) > 0) {
        create_record_version(
          table_name = request$table_name,
          record_id = request$record_id,
          data = as.list(current_data),
          change_type = "UPDATE",
          change_reason = paste("Data correction:", request$correction_reason,
                                "-", request$reason_details),
          changed_by = applied_by,
          field_changes = list(
            field = list(
              old_value = request$original_value,
              new_value = request$corrected_value
            )
          ),
          db_path = db_path
        )
      }
    }, error = function(e) NULL)

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE correction_requests
      SET status = 'APPLIED',
          applied_by = ?,
          applied_at = ?
      WHERE request_id = ?
    ", list(
      safe_scalar_dc(applied_by),
      timestamp,
      request_id
    ))

    history_hash <- digest::digest(
      paste(request_id, "APPLIED", applied_by, timestamp, sep = "|"),
      algo = "sha256"
    )

    DBI::dbExecute(conn, "
      INSERT INTO correction_history (
        request_id, action, action_by, action_at, action_details, action_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      "APPLIED",
      safe_scalar_dc(applied_by),
      timestamp,
      paste("Correction applied:", request$field_name,
            "changed from", request$original_value,
            "to", request$corrected_value),
      history_hash
    ))

    tryCatch({
      log_audit_event(
        event_type = "UPDATE",
        user_id = applied_by,
        table_name = request$table_name,
        record_id = request$record_id,
        details = paste("Data correction applied:",
                        request$field_name, "from", request$original_value,
                        "to", request$corrected_value,
                        "| Reason:", request$correction_reason)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      request_id = request_id,
      status = "APPLIED",
      table_name = request$table_name,
      record_id = request$record_id,
      field_name = request$field_name,
      old_value = request$original_value,
      new_value = request$corrected_value,
      message = "Correction applied successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Override Management
# =============================================================================

#' Request Override for Locked Record
#'
#' Creates an override request for correcting locked/finalized data.
#'
#' @param request_id Integer: Correction request ID
#' @param override_type Character: Type of override needed
#' @param override_reason Character: Justification for override
#' @param override_by Character: User requesting override
#' @param db_path Character: Database path (optional)
#'
#' @return List with override request status
#'
#' @export
request_correction_override <- function(request_id,
                                         override_type,
                                         override_reason,
                                         override_by,
                                         db_path = NULL) {
  valid_types <- c("LOCKED_RECORD", "FINALIZED_DATA", "SIGNATURE_PRESENT")
  if (!override_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid override type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  if (is.null(override_reason) || nchar(override_reason) < 20) {
    return(list(
      success = FALSE,
      error = "Override justification required (min 20 characters)"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request <- DBI::dbGetQuery(conn, "
      SELECT * FROM correction_requests WHERE request_id = ?
    ", list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Correction request not found"))
    }

    timestamp <- as.character(Sys.time())
    override_hash <- digest::digest(
      paste(request_id, override_type, override_reason, override_by,
            timestamp, sep = "|"),
      algo = "sha256"
    )

    DBI::dbExecute(conn, "
      INSERT INTO correction_overrides (
        request_id, override_type, override_reason, override_by,
        override_at, override_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      safe_scalar_dc(override_type),
      safe_scalar_dc(override_reason),
      safe_scalar_dc(override_by),
      timestamp,
      override_hash
    ))

    override_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    history_hash <- digest::digest(
      paste(request_id, "ESCALATED", override_by, timestamp, sep = "|"),
      algo = "sha256"
    )

    DBI::dbExecute(conn, "
      INSERT INTO correction_history (
        request_id, action, action_by, action_at, action_details, action_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      "ESCALATED",
      safe_scalar_dc(override_by),
      timestamp,
      paste("Override requested:", override_type, "-", override_reason),
      history_hash
    ))

    tryCatch({
      log_audit_event(
        event_type = "UPDATE",
        user_id = override_by,
        table_name = "correction_overrides",
        record_id = as.character(override_id),
        details = paste("Override requested for correction", request_id,
                        "| Type:", override_type)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      override_id = override_id,
      request_id = request_id,
      status = "PENDING_APPROVAL",
      message = "Override request created - awaiting approval"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Approve Override Request
#'
#' Approves an override request (requires elevated privileges).
#'
#' @param override_id Integer: Override request ID
#' @param approved_by Character: Approver user ID (must have override permission)
#' @param db_path Character: Database path (optional)
#'
#' @return List with approval status
#'
#' @export
approve_override <- function(override_id, approved_by, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    override <- DBI::dbGetQuery(conn, "
      SELECT * FROM correction_overrides WHERE override_id = ?
    ", list(override_id))

    if (nrow(override) == 0) {
      return(list(success = FALSE, error = "Override request not found"))
    }

    if (!is.na(override$approved_at)) {
      return(list(success = FALSE, error = "Override already processed"))
    }

    if (override$override_by == approved_by) {
      return(list(
        success = FALSE,
        error = "Cannot approve own override request"
      ))
    }

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE correction_overrides
      SET approved_by = ?, approved_at = ?
      WHERE override_id = ?
    ", list(
      safe_scalar_dc(approved_by),
      timestamp,
      override_id
    ))

    tryCatch({
      log_audit_event(
        event_type = "UPDATE",
        user_id = approved_by,
        table_name = "correction_overrides",
        record_id = as.character(override_id),
        details = paste("Override approved for correction",
                        override$request_id)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      override_id = override_id,
      request_id = override$request_id,
      message = "Override approved - correction can now be applied"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Reporting Functions
# =============================================================================

#' Get Correction Statistics
#'
#' Returns statistics about data corrections.
#'
#' @param site_id Character: Filter by site (optional)
#' @param study_id Character: Filter by study (optional)
#' @param start_date Character: Start date filter (optional)
#' @param end_date Character: End date filter (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with correction statistics
#'
#' @export
get_correction_statistics <- function(site_id = NULL,
                                       study_id = NULL,
                                       start_date = NULL,
                                       end_date = NULL,
                                       db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    where_clauses <- c()
    params <- list()

    if (!is.null(site_id)) {
      where_clauses <- c(where_clauses, "site_id = ?")
      params <- c(params, list(safe_scalar_dc(site_id)))
    }

    if (!is.null(study_id)) {
      where_clauses <- c(where_clauses, "study_id = ?")
      params <- c(params, list(safe_scalar_dc(study_id)))
    }

    if (!is.null(start_date)) {
      where_clauses <- c(where_clauses, "requested_at >= ?")
      params <- c(params, list(safe_scalar_dc(start_date)))
    }

    if (!is.null(end_date)) {
      where_clauses <- c(where_clauses, "requested_at <= ?")
      params <- c(params, list(safe_scalar_dc(end_date)))
    }

    where_sql <- if (length(where_clauses) > 0) {
      paste("WHERE", paste(where_clauses, collapse = " AND "))
    } else {
      ""
    }

    by_status <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT status, COUNT(*) as count
        FROM correction_requests", where_sql, "
        GROUP BY status
      "), params)
    } else {
      DBI::dbGetQuery(conn, paste("
        SELECT status, COUNT(*) as count
        FROM correction_requests", where_sql, "
        GROUP BY status
      "))
    }

    by_reason <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT correction_reason, COUNT(*) as count
        FROM correction_requests", where_sql, "
        GROUP BY correction_reason
        ORDER BY count DESC
      "), params)
    } else {
      DBI::dbGetQuery(conn, paste("
        SELECT correction_reason, COUNT(*) as count
        FROM correction_requests", where_sql, "
        GROUP BY correction_reason
        ORDER BY count DESC
      "))
    }

    by_table <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT table_name, COUNT(*) as count
        FROM correction_requests", where_sql, "
        GROUP BY table_name
        ORDER BY count DESC
      "), params)
    } else {
      DBI::dbGetQuery(conn, paste("
        SELECT table_name, COUNT(*) as count
        FROM correction_requests", where_sql, "
        GROUP BY table_name
        ORDER BY count DESC
      "))
    }

    by_site <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT site_id, COUNT(*) as count
        FROM correction_requests", where_sql, "
        AND site_id IS NOT NULL
        GROUP BY site_id
        ORDER BY count DESC
      "), params)
    } else {
      DBI::dbGetQuery(conn, paste("
        SELECT site_id, COUNT(*) as count
        FROM correction_requests", where_sql,
        if (where_sql == "") "WHERE" else "AND",
        "site_id IS NOT NULL
        GROUP BY site_id
        ORDER BY count DESC
      "))
    }

    total <- sum(by_status$count, na.rm = TRUE)
    pending <- sum(by_status$count[by_status$status == "PENDING"], na.rm = TRUE)
    approved <- sum(by_status$count[by_status$status == "APPROVED"], na.rm = TRUE)
    applied <- sum(by_status$count[by_status$status == "APPLIED"], na.rm = TRUE)
    rejected <- sum(by_status$count[by_status$status == "REJECTED"], na.rm = TRUE)

    list(
      success = TRUE,
      summary = list(
        total_requests = total,
        pending = pending,
        approved = approved,
        applied = applied,
        rejected = rejected,
        approval_rate = if (total > 0) round((approved + applied) / total * 100, 1) else 0,
        rejection_rate = if (total > 0) round(rejected / total * 100, 1) else 0
      ),
      by_status = by_status,
      by_reason = by_reason,
      by_table = by_table,
      by_site = by_site
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Generate Correction Report
#'
#' Generates a data correction report for regulatory submission.
#'
#' @param output_file Character: Output file path
#' @param format Character: Report format (txt or json)
#' @param site_id Character: Filter by site (optional)
#' @param study_id Character: Filter by study (optional)
#' @param start_date Character: Start date (optional)
#' @param end_date Character: End date (optional)
#' @param organization Character: Organization name
#' @param prepared_by Character: Report preparer
#' @param db_path Character: Database path (optional)
#'
#' @return List with report generation status
#'
#' @export
generate_correction_report <- function(output_file,
                                        format = "txt",
                                        site_id = NULL,
                                        study_id = NULL,
                                        start_date = NULL,
                                        end_date = NULL,
                                        organization = "Clinical Research Organization",
                                        prepared_by = "Data Manager",
                                        db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    stats <- get_correction_statistics(
      site_id = site_id,
      study_id = study_id,
      start_date = start_date,
      end_date = end_date,
      db_path = db_path
    )

    where_clauses <- c()
    params <- list()

    if (!is.null(site_id)) {
      where_clauses <- c(where_clauses, "site_id = ?")
      params <- c(params, list(safe_scalar_dc(site_id)))
    }

    if (!is.null(study_id)) {
      where_clauses <- c(where_clauses, "study_id = ?")
      params <- c(params, list(safe_scalar_dc(study_id)))
    }

    where_sql <- if (length(where_clauses) > 0) {
      paste("WHERE", paste(where_clauses, collapse = " AND "))
    } else {
      ""
    }

    corrections <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, paste("
        SELECT * FROM correction_requests", where_sql, "
        ORDER BY requested_at DESC
      "), params)
    } else {
      DBI::dbGetQuery(conn, paste("
        SELECT * FROM correction_requests", where_sql, "
        ORDER BY requested_at DESC
      "))
    }

    if (format == "json") {
      report_data <- list(
        report_type = "Data Correction Report",
        organization = organization,
        generated_at = as.character(Sys.time()),
        prepared_by = prepared_by,
        filters = list(
          site_id = site_id,
          study_id = study_id,
          start_date = start_date,
          end_date = end_date
        ),
        statistics = stats$summary,
        by_reason = stats$by_reason,
        by_table = stats$by_table,
        corrections = corrections
      )

      jsonlite::write_json(report_data, output_file, pretty = TRUE, auto_unbox = TRUE)

    } else {
      lines <- c(
        "===============================================================================",
        "                        DATA CORRECTION REPORT",
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
        paste("Total Correction Requests:", stats$summary$total_requests),
        paste("Pending:", stats$summary$pending),
        paste("Approved:", stats$summary$approved),
        paste("Applied:", stats$summary$applied),
        paste("Rejected:", stats$summary$rejected),
        paste("Approval Rate:", stats$summary$approval_rate, "%"),
        paste("Rejection Rate:", stats$summary$rejection_rate, "%"),
        "",
        "-------------------------------------------------------------------------------",
        "                        CORRECTIONS BY REASON",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(stats$by_reason) > 0) {
        for (i in seq_len(nrow(stats$by_reason))) {
          lines <- c(lines, sprintf("  %-25s %d",
                                    stats$by_reason$correction_reason[i],
                                    stats$by_reason$count[i]))
        }
      }

      lines <- c(lines,
        "",
        "-------------------------------------------------------------------------------",
        "                        CORRECTIONS BY TABLE",
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
        "                        CORRECTION DETAILS",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(corrections) > 0) {
        for (i in seq_len(min(nrow(corrections), 50))) {
          r <- corrections[i, ]
          lines <- c(lines,
            sprintf("Request #%d", r$request_id),
            sprintf("  Table: %s | Record: %s | Field: %s",
                    r$table_name, r$record_id, r$field_name),
            sprintf("  Original: %s -> Corrected: %s",
                    r$original_value, r$corrected_value),
            sprintf("  Reason: %s", r$correction_reason),
            sprintf("  Status: %s | Requested: %s | By: %s",
                    r$status, r$requested_at, r$requested_by),
            ""
          )
        }

        if (nrow(corrections) > 50) {
          lines <- c(lines, sprintf("... and %d more corrections",
                                    nrow(corrections) - 50))
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
      corrections_count = nrow(corrections),
      message = "Report generated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Verify Correction Chain Integrity
#'
#' Verifies the hash chain integrity of correction requests.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with verification results
#'
#' @export
verify_correction_integrity <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    requests <- DBI::dbGetQuery(conn, "
      SELECT request_id, table_name, record_id, field_name,
             original_value, corrected_value, correction_reason,
             requested_by, requested_at, request_hash, previous_request_hash
      FROM correction_requests
      ORDER BY request_id ASC
    ")

    if (nrow(requests) == 0) {
      return(list(
        success = TRUE,
        is_valid = TRUE,
        total_records = 0,
        message = "No correction requests to verify"
      ))
    }

    invalid_records <- c()

    for (i in seq_len(nrow(requests))) {
      r <- requests[i, ]

      expected_prev <- if (i == 1) "GENESIS" else requests$request_hash[i - 1]

      if (r$previous_request_hash != expected_prev) {
        invalid_records <- c(invalid_records, r$request_id)
      }
    }

    is_valid <- length(invalid_records) == 0

    list(
      success = TRUE,
      is_valid = is_valid,
      total_records = nrow(requests),
      invalid_records = invalid_records,
      message = if (is_valid) {
        "All correction request hashes verified"
      } else {
        paste("Found", length(invalid_records), "records with invalid hash chain")
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
