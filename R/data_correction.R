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
#' @keywords internal
#' @export
init_data_correction <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    prepare_auto_increment(conn, "correction_requests", "request_id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS correction_requests (
        request_id %s,
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
    ", auto_increment_ddl("correction_requests", "request_id")))

    prepare_auto_increment(conn, "correction_approvers", "approver_id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS correction_approvers (
        approver_id %s,
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
    ", auto_increment_ddl("correction_approvers", "approver_id")))

    prepare_auto_increment(conn, "correction_history", "history_id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS correction_history (
        history_id %s,
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
    ", auto_increment_ddl("correction_history", "history_id")))

    prepare_auto_increment(conn, "correction_overrides", "override_id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS correction_overrides (
        override_id %s,
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
    ", auto_increment_ddl("correction_overrides", "override_id")))

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
#' @keywords internal
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
#'
#' @examples
#' \dontrun{
#' # Open a data-correction request: the change goes into a queue
#' # requiring approval before the database is updated.
#' create_correction_request(
#'   record_id  = "SUBJ-001:VISIT-1:CRF-VITAL",
#'   field_name = "sbp",
#'   old_value  = "220",
#'   new_value  = "120",
#'   reason     = "Transcription error from source document",
#'   requested_by = "data_entry_clerk"
#' )
#' }
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

    request_id <- DBI::dbGetQuery(conn, "
      INSERT INTO correction_requests (
        table_name, record_id, field_name, original_value, corrected_value,
        correction_reason, reason_details, original_source_doc,
        corrected_source_doc, requested_by, requested_at, request_hash,
        previous_request_hash, site_id, study_id, subject_id, visit_id, form_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING request_id AS id
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
    ))$id[1]

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
        operation = paste("Correction request created:", field_name),
        details = paste("Correction request created:",
                        field_name, "from", original_value, "to", corrected_value),
        db_path = db_path
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
#' @keywords internal
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
#' @keywords internal
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
#' @keywords internal
#' @param reviewer_role Optional: the reviewer's role, checked via
#'   [require_role()] against `c("Admin", "PI", "StudyManager",
#'   "Data Manager")` (§11.10(g)). `NULL` skips the check -- existing
#'   callers that do not yet pass a role are unaffected; new callers
#'   should supply one.
#' @export
approve_correction <- function(request_id,
                                reviewed_by,
                                review_comments = NULL,
                                db_path = NULL,
                                reviewer_role = NULL) {
  tryCatch({
    if (!is.null(reviewer_role)) {
      denied <- require_role(reviewer_role,
                              c("Admin", "PI", "StudyManager", "Data Manager"),
                              "approve a data correction")
      if (!is.null(denied)) return(denied)
    }

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
        operation = paste("Correction approved for", request$field_name),
        details = paste("Correction approved for", request$field_name),
        db_path = db_path
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
#' @param reviewer_role Optional: the reviewer's role (see
#'   [approve_correction()]'s matching parameter for the check and
#'   allowed-role list).
#'
#' @return List with rejection status
#'
#' @keywords internal
#' @export
reject_correction <- function(request_id,
                               reviewed_by,
                               review_comments,
                               db_path = NULL,
                               reviewer_role = NULL) {
  if (is.null(review_comments) || nchar(review_comments) < 10) {
    return(list(
      success = FALSE,
      error = "Rejection reason required (min 10 characters)"
    ))
  }

  if (!is.null(reviewer_role)) {
    denied <- require_role(reviewer_role,
                            c("Admin", "PI", "StudyManager", "Data Manager"),
                            "reject a data correction")
    if (!is.null(denied)) return(denied)
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
        operation = "Correction request rejected",
        details = paste("Correction rejected:", review_comments),
        db_path = db_path
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
#' Applies an approved correction to the stored data.
#'
#' @param request_id Integer: Request identifier
#' @param applied_by Character: User applying the correction
#' @param db_path Character: Database path (optional)
#'
#' @return List with `success`; on success `status = "APPLIED"`,
#'   `table_name`, `record_id`, `field_name`, `old_value`, `new_value`,
#'   `version_recorded`, and `message`; otherwise `error` (and
#'   `requires_override = TRUE` when the record is locked).
#'
#' @details
#' Until 2026-11-11 this function marked the request applied, wrote an
#' audit record saying the value had changed, and returned success,
#' without changing the stored value. It also never honored record
#' locks: it tested a field (`is_locked`) that `check_record_lock()`
#' does not return. Now, in one transaction:
#'
#' 1. The record is read and the field's current value compared with
#'    the request's `original_value`. If they differ (the record changed
#'    after the request was made), nothing is applied.
#' 2. The field is updated: a column of the table, or, for a table that
#'    stores its fields as JSON (`data_entries.data_json`), the named
#'    field inside the JSON. Numeric and logical fields keep their type;
#'    a corrected value that is not of the field's type is refused.
#'    `modified_by` and `modified_date` are set where the table has them.
#' 3. The request is marked `APPLIED` (only if it is still `APPROVED`, so
#'    it cannot be applied twice), a history entry is added, and an
#'    `UPDATE` audit record is written with the old value, new value,
#'    reason, and approver.
#'
#' If any step fails, none of them takes effect. A record locked by
#' someone else (`version_locks`), or a `data_entries` row marked
#' `locked`, is corrected only when an override for this request has
#' been approved (`request_correction_override()`, `approve_override()`).
#' Audit, signature, version, user, and correction tables cannot be
#' corrected through this workflow, nor can a table's primary key or
#' `data_json` column as a whole.
#'
#' After the transaction, the record's state is stored as a version
#' (`create_record_version()`): a baseline of the state before the
#' correction if the record had no versions, then the corrected state.
#' A failure there does not undo the correction, which is already
#' recorded in the audit trail; it is reported as
#' `version_recorded = FALSE`.
#'
#' @keywords internal
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

    tbl <- request$table_name
    field <- request$field_name
    if (tbl %in% .correction_protected_tables ||
        grepl("^(audit_|correction_|signature|version_)", tbl)) {
      return(list(success = FALSE, error = paste(
        "Table", tbl, "cannot be changed through the data-correction workflow.")))
    }
    if (!DBI::dbExistsTable(conn, tbl)) {
      return(list(success = FALSE, error = paste("Table does not exist:", tbl)))
    }
    cols <- DBI::dbListFields(conn, tbl)
    pk_col <- resolve_table_pk_column(conn, tbl)
    target <- if (field %in% cols) {
      if (field %in% c(pk_col, "data_json")) {
        return(list(success = FALSE, error = paste(
          "Field", field, "cannot be changed through the data-correction workflow.")))
      }
      "column"
    } else if ("data_json" %in% cols) {
      "json"
    } else {
      return(list(success = FALSE, error = paste("Table", tbl, "has no field", field)))
    }

    select_row <- sprintf("SELECT * FROM %s WHERE %s = ?",
                          DBI::dbQuoteIdentifier(conn, tbl),
                          DBI::dbQuoteIdentifier(conn, pk_col))
    before <- DBI::dbGetQuery(conn, select_row, list(request$record_id))
    if (nrow(before) == 0) {
      return(list(success = FALSE, error = paste("Record", request$record_id, "not found in", tbl)))
    }

    # Locks: a version lock held by someone else, or a locked
    # data_entries row, needs an approved override for this request.
    lock_status <- check_record_lock(tbl, request$record_id, db_path = db_path)
    if (!is.null(lock_status$error) && DBI::dbExistsTable(conn, "version_locks")) {
      return(list(success = FALSE, error = paste(
        "Could not check whether the record is locked:", lock_status$error)))
    }
    locked_by_other <- isTRUE(lock_status$locked) && !identical(lock_status$locked_by, applied_by)
    row_locked <- "locked" %in% cols && isTRUE(as.logical(as.integer(before$locked[1])))
    if (locked_by_other || row_locked) {
      override <- DBI::dbGetQuery(conn, "
        SELECT COUNT(*) AS n FROM correction_overrides
        WHERE request_id = ? AND approved_by IS NOT NULL
      ", list(request_id))$n
      if (override == 0) {
        return(list(
          success = FALSE,
          error = if (locked_by_other) paste("Record is locked by", lock_status$locked_by)
                  else "Record is locked",
          requires_override = TRUE
        ))
      }
    }

    timestamp <- as.character(Sys.time())

    .with_db_transaction(conn, function(c) {
      row <- DBI::dbGetQuery(c, select_row, list(request$record_id))
      if (nrow(row) == 0) stop("Record ", request$record_id, " not found in ", tbl)

      if (target == "column") {
        current <- row[[field]][1]
        if (!.correction_value_matches(current, request$original_value)) {
          stop("The record has changed since the correction was requested: ", field,
               " is now '", .correction_display(current), "', not '",
               .correction_display(request$original_value), "'. Nothing was applied.")
        }
        new_value <- .correction_coerce(request$corrected_value, current)
        sets <- sprintf("%s = ?", DBI::dbQuoteIdentifier(c, field))
        values <- list(new_value)
      } else {
        fields <- jsonlite::fromJSON(row$data_json[1] %||% "{}", simplifyVector = FALSE)
        current <- fields[[field]]
        if (!.correction_value_matches(current, request$original_value)) {
          stop("The entry has changed since the correction was requested: ", field,
               " is now '", .correction_display(current), "', not '",
               .correction_display(request$original_value), "'. Nothing was applied.")
        }
        fields[[field]] <- .correction_coerce(request$corrected_value, current)
        sets <- "data_json = ?"
        values <- list(as.character(jsonlite::toJSON(fields, auto_unbox = TRUE, null = "null")))
      }
      if ("modified_by" %in% cols) {
        sets <- c(sets, "modified_by = ?")
        values <- c(values, list(safe_scalar_dc(applied_by)))
      }
      if ("modified_date" %in% cols) {
        sets <- c(sets, "modified_date = ?")
        values <- c(values, list(format(Sys.time(), tz = "UTC", "%Y-%m-%d %H:%M:%S")))
      }
      n <- DBI::dbExecute(c, sprintf("UPDATE %s SET %s WHERE %s = ?",
                                     DBI::dbQuoteIdentifier(c, tbl),
                                     paste(sets, collapse = ", "),
                                     DBI::dbQuoteIdentifier(c, pk_col)),
                          params = c(values, list(request$record_id)))
      if (n != 1) stop("Expected to update one record, updated ", n)

      n <- DBI::dbExecute(c, "
        UPDATE correction_requests
        SET status = 'APPLIED', applied_by = ?, applied_at = ?
        WHERE request_id = ? AND status = 'APPROVED'
      ", params = list(safe_scalar_dc(applied_by), timestamp, request_id))
      if (n != 1) stop("The request is no longer approved; nothing was applied.")

      DBI::dbExecute(c, "
        INSERT INTO correction_history (
          request_id, action, action_by, action_at, action_details, action_hash
        ) VALUES (?, ?, ?, ?, ?, ?)
      ", params = list(
        request_id, "APPLIED", safe_scalar_dc(applied_by), timestamp,
        paste("Correction applied:", field, "changed from",
              .correction_display(current), "to", request$corrected_value),
        digest::digest(paste(request_id, "APPLIED", applied_by, timestamp, sep = "|"),
                       algo = "sha256")
      ))

      .append_audit_record(
        c, event_type = "UPDATE", table_name = tbl, record_id = request$record_id,
        operation = paste("Data correction applied:", field),
        details = as.character(jsonlite::toJSON(list(
          field = field,
          old_value = .correction_display(current),
          new_value = request$corrected_value,
          reason = request$correction_reason,
          reason_details = request$reason_details,
          correction_request_id = request_id,
          requested_by = request$requested_by,
          approved_by = request$reviewed_by
        ), auto_unbox = TRUE, null = "null")),
        user_id = applied_by
      )
    })

    after <- DBI::dbGetQuery(conn, select_row, list(request$record_id))
    version_recorded <- tryCatch({
      reason <- paste("Data correction:", request$correction_reason,
                      if (!is.na(request$reason_details)) paste("-", request$reason_details) else "")
      had_versions <- tryCatch(
        DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM record_versions WHERE table_name = ? AND record_id = ?",
                        list(tbl, request$record_id))$n > 0,
        error = function(e) FALSE)
      if (!had_versions) {
        create_record_version(tbl, request$record_id, as.list(before),
                              change_type = "CREATE",
                              change_reason = "State before the first correction",
                              changed_by = applied_by, db_path = db_path)
      }
      v <- create_record_version(
        tbl, request$record_id, as.list(after), change_type = "UPDATE",
        change_reason = reason, changed_by = applied_by,
        field_changes = stats::setNames(list(list(
          old_value = request$original_value, new_value = request$corrected_value)), field),
        db_path = db_path)
      isTRUE(v$success)
    }, error = function(e) FALSE)

    list(
      success = TRUE,
      request_id = request_id,
      status = "APPLIED",
      table_name = tbl,
      record_id = request$record_id,
      field_name = field,
      old_value = request$original_value,
      new_value = request$corrected_value,
      version_recorded = version_recorded,
      message = "Correction applied successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}


.correction_protected_tables <- c(
  "audit_log", "audit_chain", "audit_events", "record_versions",
  "version_locks", "edc_users", "electronic_signatures", "data_entries_audit"
)


#' Display Form of a Stored Value (internal)
#' @keywords internal
.correction_display <- function(x) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) "" else as.character(x[[1]])
}


#' Whether a Stored Value Equals a Request's Original Value (internal)
#'
#' Compares as text after trimming, and numerically when both parse as
#' numbers (so `70.5` stored as a double equals the request's `"70.50"`).
#' A missing stored value equals an empty or missing original value.
#' @keywords internal
.correction_value_matches <- function(current, original) {
  cur <- trimws(.correction_display(current))
  orig <- trimws(.correction_display(original))
  if (identical(cur, orig)) return(TRUE)
  cn <- suppressWarnings(as.numeric(cur))
  on <- suppressWarnings(as.numeric(orig))
  !is.na(cn) && !is.na(on) && isTRUE(all.equal(cn, on, tolerance = 1e-9))
}


#' Convert a Corrected Value to the Stored Field's Type (internal)
#'
#' @param value The corrected value (text, as stored on the request).
#' @param template The field's current value.
#' @return `value` as a number or logical when the field is one (an
#'   error if it does not convert), otherwise as text. An empty value
#'   becomes `NA`.
#' @keywords internal
.correction_coerce <- function(value, template) {
  value <- trimws(as.character(value))
  if (!nzchar(value)) return(NA)
  if (is.null(template) || length(template) == 0 || (length(template) == 1 && is.na(template) && is.logical(template))) {
    return(value)
  }
  if (is.numeric(template)) {
    v <- suppressWarnings(as.numeric(value))
    if (is.na(v)) stop("The corrected value '", value, "' is not a number, but the field is numeric.")
    if (is.integer(template) && v == round(v)) return(as.integer(v))
    return(v)
  }
  if (is.logical(template)) {
    v <- switch(toupper(value), "TRUE" = TRUE, "T" = TRUE, "1" = TRUE, "YES" = TRUE,
                "FALSE" = FALSE, "F" = FALSE, "0" = FALSE, "NO" = FALSE, NA)
    if (is.na(v)) stop("The corrected value '", value, "' is not true/false, but the field is.")
    return(v)
  }
  value
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
#' @keywords internal
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

    override_id <- DBI::dbGetQuery(conn, "
      INSERT INTO correction_overrides (
        request_id, override_type, override_reason, override_by,
        override_at, override_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
      RETURNING override_id AS id
    ", list(
      request_id,
      safe_scalar_dc(override_type),
      safe_scalar_dc(override_reason),
      safe_scalar_dc(override_by),
      timestamp,
      override_hash
    ))$id[1]

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
        operation = paste("Override requested for correction", request_id),
        details = paste("Override requested for correction", request_id,
                        "| Type:", override_type),
        db_path = db_path
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
#' @keywords internal
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
        operation = paste("Override approved for correction",
                          override$request_id),
        details = paste("Override approved for correction",
                        override$request_id),
        db_path = db_path
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
#' @keywords internal
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
#' @keywords internal
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
        # §11.10(b) requires this report to be a complete copy, not a
        # bounded preview -- see the matching fix and comment in
        # generate_signature_report() (R/electronic_signatures.R).
        for (i in seq_len(nrow(corrections))) {
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
#'
#' @examples
#' \dontrun{
#' # CFR-Part-11 features require an initialized database with the
#' # data-correction tables created at study-init time.
#' # Verify the hash chain on a data-correction record.
#' verify_correction_integrity(correction_id = 42)
#' }
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

    tampered_records <- c()

    for (i in seq_len(nrow(requests))) {
      r <- requests[i, ]

      expected_prev <- if (i == 1) "GENESIS" else requests$request_hash[i - 1]

      if (r$previous_request_hash != expected_prev) {
        invalid_records <- c(invalid_records, r$request_id)
      }

      # Recompute from the stored content, in the order the request was
      # hashed with. Comparing the linkage fields alone establishes that
      # they agree with one another and nothing about what was
      # corrected: the field, the original value, the value it was
      # changed to and who asked for it could all be rewritten, and the
      # function still reported "All correction request hashes
      # verified". These records exist to document a change to a
      # recorded clinical value, so the content is the whole point.
      nz <- function(x) {
        if (is.null(x) || length(x) == 0L || is.na(x[1L])) {
          ""
        } else {
          as.character(x[1L])
        }
      }
      recomputed <- digest::digest(
        paste(nz(r$table_name), nz(r$record_id), nz(r$field_name),
              nz(r$original_value), nz(r$corrected_value),
              nz(r$correction_reason), nz(r$requested_by),
              nz(r$requested_at), nz(r$previous_request_hash),
              sep = "|"),
        algo = "sha256"
      )
      if (!identical(recomputed, as.character(r$request_hash))) {
        tampered_records <- c(tampered_records, r$request_id)
      }
    }

    is_valid <- length(invalid_records) == 0 &&
      length(tampered_records) == 0

    list(
      success = TRUE,
      is_valid = is_valid,
      total_records = nrow(requests),
      invalid_records = invalid_records,
      tampered_records = tampered_records,
      message = if (is_valid) {
        "All correction request hashes verified"
      } else {
        paste0("Found ", length(invalid_records),
               " records with a broken hash chain and ",
               length(tampered_records),
               " whose content does not match its recorded hash")
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
