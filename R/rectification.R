#' Right to Rectification System
#'
#' GDPR Article 16 compliant system for managing data subject rectification
#' requests, including correction tracking, third-party notification, and
#' completion of incomplete data.

# =============================================================================
# Helper Functions
# =============================================================================

#' Safe Scalar Conversion for Rectification
#'
#' @param x Value to convert
#' @param default Default value if NULL
#' @return Character scalar
#' @keywords internal
safe_scalar_rect <- function(x, default = NA_character_) {
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

#' Initialize Rectification System
#'
#' Creates database tables for rectification request management.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with initialization results
#'
#' @export
init_rectification <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS rectification_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT NOT NULL UNIQUE,
        dsar_request_id INTEGER REFERENCES dsar_requests(request_id),
        subject_id TEXT,
        subject_email TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        request_type TEXT NOT NULL CHECK(request_type IN
          ('CORRECTION', 'COMPLETION', 'BOTH')),
        status TEXT NOT NULL DEFAULT 'RECEIVED' CHECK(status IN
          ('RECEIVED', 'UNDER_REVIEW', 'APPROVED', 'PARTIALLY_APPROVED',
           'REJECTED', 'COMPLETED', 'CLOSED')),
        received_date DATE NOT NULL,
        due_date DATE NOT NULL,
        completed_date DATE,
        requested_by TEXT NOT NULL,
        reviewed_by TEXT,
        reviewed_at TIMESTAMP,
        review_notes TEXT,
        rejection_reason TEXT,
        request_hash TEXT NOT NULL,
        previous_hash TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS rectification_items (
        item_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES rectification_requests(request_id),
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        current_value TEXT,
        requested_value TEXT NOT NULL,
        rectification_type TEXT NOT NULL CHECK(rectification_type IN
          ('CORRECTION', 'COMPLETION')),
        justification TEXT,
        supporting_evidence TEXT,
        status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN
          ('PENDING', 'APPROVED', 'REJECTED', 'APPLIED')),
        rejection_reason TEXT,
        applied_at TIMESTAMP,
        applied_by TEXT,
        item_hash TEXT NOT NULL
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS rectification_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES rectification_requests(request_id),
        item_id INTEGER REFERENCES rectification_items(item_id),
        action TEXT NOT NULL,
        action_details TEXT,
        previous_value TEXT,
        new_value TEXT,
        performed_by TEXT NOT NULL,
        performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        history_hash TEXT NOT NULL,
        previous_history_hash TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS third_party_recipients (
        recipient_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES rectification_requests(request_id),
        recipient_name TEXT NOT NULL,
        recipient_type TEXT NOT NULL CHECK(recipient_type IN
          ('PROCESSOR', 'CONTROLLER', 'THIRD_PARTY', 'REGULATOR')),
        contact_email TEXT,
        contact_name TEXT,
        data_shared TEXT,
        notification_required BOOLEAN DEFAULT 1,
        notification_sent BOOLEAN DEFAULT 0,
        notification_sent_date DATE,
        notification_sent_by TEXT,
        notification_method TEXT CHECK(notification_method IN
          ('EMAIL', 'API', 'POSTAL', 'MANUAL')),
        acknowledgment_received BOOLEAN DEFAULT 0,
        acknowledgment_date DATE,
        notes TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS rectification_notifications (
        notification_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES rectification_requests(request_id),
        recipient_id INTEGER REFERENCES third_party_recipients(recipient_id),
        notification_type TEXT NOT NULL CHECK(notification_type IN
          ('SUBJECT_ACKNOWLEDGMENT', 'SUBJECT_COMPLETION', 'SUBJECT_REJECTION',
           'THIRD_PARTY_NOTIFICATION', 'INTERNAL_NOTIFICATION')),
        recipient_email TEXT,
        subject_line TEXT,
        notification_content TEXT,
        sent_at TIMESTAMP,
        sent_by TEXT,
        delivery_status TEXT CHECK(delivery_status IN
          ('PENDING', 'SENT', 'DELIVERED', 'FAILED', 'BOUNCED')),
        notification_hash TEXT NOT NULL
      )
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_rect_status
      ON rectification_requests(status)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_rect_subject
      ON rectification_requests(subject_email)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_rect_items_request
      ON rectification_items(request_id)
    ")

    list(
      success = TRUE,
      tables_created = 5,
      message = "Rectification system initialized successfully"
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

#' Get Rectification Types
#'
#' Returns valid rectification request types.
#'
#' @return Named list of rectification types
#'
#' @export
get_rectification_types <- function() {
  list(
    CORRECTION = "Correction of inaccurate data (GDPR Article 16)",
    COMPLETION = "Completion of incomplete data (GDPR Article 16)",
    BOTH = "Both correction and completion"
  )
}


#' Get Rectification Statuses
#'
#' Returns valid rectification request statuses.
#'
#' @return Named list of status values
#'
#' @export
get_rectification_statuses <- function() {
  list(
    RECEIVED = "Request received and logged",
    UNDER_REVIEW = "Request under review",
    APPROVED = "All items approved for rectification",
    PARTIALLY_APPROVED = "Some items approved, others rejected",
    REJECTED = "Request rejected",
    COMPLETED = "All approved rectifications applied",
    CLOSED = "Request closed"
  )
}


# =============================================================================
# Request Management
# =============================================================================

#' Generate Rectification Request Number
#'
#' Generates a unique rectification request number.
#'
#' @return Character: Request number
#'
#' @keywords internal
generate_rect_number <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(0:9, 4, replace = TRUE), collapse = "")
  paste0("RECT-", timestamp, "-", random)
}


#' Create Rectification Request
#'
#' Creates a new rectification request under GDPR Article 16.
#'
#' @param subject_email Character: Data subject's email
#' @param subject_name Character: Data subject's name
#' @param request_type Character: CORRECTION, COMPLETION, or BOTH
#' @param requested_by Character: User creating request
#' @param subject_id Character: Subject ID if known (optional)
#' @param dsar_request_id Integer: Link to DSAR request (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
create_rectification_request <- function(subject_email,
                                          subject_name,
                                          request_type,
                                          requested_by,
                                          subject_id = NULL,
                                          dsar_request_id = NULL,
                                          db_path = NULL) {

  valid_types <- names(get_rectification_types())
  if (!request_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid request type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    request_number <- generate_rect_number()
    received_date <- Sys.Date()
    due_date <- received_date + 30

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT request_hash FROM rectification_requests
      ORDER BY request_id DESC LIMIT 1
    ")
    previous_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$request_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      request_number, subject_email, subject_name, request_type,
      requested_by, timestamp, previous_hash,
      sep = "|"
    )
    request_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO rectification_requests (
        request_number, dsar_request_id, subject_id, subject_email,
        subject_name, request_type, status, received_date, due_date,
        requested_by, request_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, 'RECEIVED', ?, ?, ?, ?, ?)
    ", list(
      request_number,
      dsar_request_id,
      safe_scalar_rect(subject_id),
      safe_scalar_rect(subject_email),
      safe_scalar_rect(subject_name),
      safe_scalar_rect(request_type),
      as.character(received_date),
      as.character(due_date),
      safe_scalar_rect(requested_by),
      request_hash,
      previous_hash
    ))

    request_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_rectification_action(
      request_id = request_id,
      action = "REQUEST_CREATED",
      action_details = paste("Rectification request created:", request_type),
      performed_by = requested_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      request_id = request_id,
      request_number = request_number,
      due_date = as.character(due_date),
      message = "Rectification request created successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Log Rectification Action
#'
#' Logs an action in the rectification history.
#'
#' @param request_id Integer: Request ID
#' @param action Character: Action performed
#' @param action_details Character: Action details
#' @param performed_by Character: User performing action
#' @param item_id Integer: Item ID if applicable (optional)
#' @param previous_value Character: Previous value (optional)
#' @param new_value Character: New value (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with logging result
#'
#' @keywords internal
log_rectification_action <- function(request_id,
                                      action,
                                      action_details,
                                      performed_by,
                                      item_id = NULL,
                                      previous_value = NULL,
                                      new_value = NULL,
                                      db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT history_hash FROM rectification_history
      WHERE request_id = ?
      ORDER BY history_id DESC LIMIT 1
    ", list(request_id))

    previous_history_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$history_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      request_id, action, action_details, performed_by, timestamp, previous_history_hash,
      sep = "|"
    )
    history_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO rectification_history (
        request_id, item_id, action, action_details,
        previous_value, new_value, performed_by,
        history_hash, previous_history_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      item_id,
      safe_scalar_rect(action),
      safe_scalar_rect(action_details),
      safe_scalar_rect(previous_value),
      safe_scalar_rect(new_value),
      safe_scalar_rect(performed_by),
      history_hash,
      previous_history_hash
    ))

    list(success = TRUE)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Rectification Items
# =============================================================================

#' Add Rectification Item
#'
#' Adds an item to be rectified in a request.
#'
#' @param request_id Integer: Request ID
#' @param table_name Character: Table containing data
#' @param record_id Character: Record identifier
#' @param field_name Character: Field to rectify
#' @param current_value Character: Current value
#' @param requested_value Character: Requested new value
#' @param rectification_type Character: CORRECTION or COMPLETION
#' @param added_by Character: User adding item
#' @param justification Character: Justification (optional)
#' @param supporting_evidence Character: Evidence reference (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with addition result
#'
#' @export
add_rectification_item <- function(request_id,
                                    table_name,
                                    record_id,
                                    field_name,
                                    current_value,
                                    requested_value,
                                    rectification_type,
                                    added_by,
                                    justification = NULL,
                                    supporting_evidence = NULL,
                                    db_path = NULL) {

  if (!rectification_type %in% c("CORRECTION", "COMPLETION")) {
    return(list(
      success = FALSE,
      error = "Rectification type must be CORRECTION or COMPLETION"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      request_id, table_name, record_id, field_name,
      current_value, requested_value, rectification_type, timestamp,
      sep = "|"
    )
    item_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO rectification_items (
        request_id, table_name, record_id, field_name,
        current_value, requested_value, rectification_type,
        justification, supporting_evidence, status, item_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', ?)
    ", list(
      request_id,
      safe_scalar_rect(table_name),
      safe_scalar_rect(record_id),
      safe_scalar_rect(field_name),
      safe_scalar_rect(current_value),
      safe_scalar_rect(requested_value),
      safe_scalar_rect(rectification_type),
      safe_scalar_rect(justification),
      safe_scalar_rect(supporting_evidence),
      item_hash
    ))

    item_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_rectification_action(
      request_id = request_id,
      item_id = item_id,
      action = "ITEM_ADDED",
      action_details = paste("Item added:", table_name, ".", field_name),
      performed_by = added_by,
      previous_value = current_value,
      new_value = requested_value,
      db_path = db_path
    )

    list(
      success = TRUE,
      item_id = item_id,
      message = "Rectification item added successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Review Rectification Item
#'
#' Reviews and approves or rejects a rectification item.
#'
#' @param item_id Integer: Item ID
#' @param decision Character: APPROVED or REJECTED
#' @param reviewed_by Character: Reviewer user ID
#' @param rejection_reason Character: Reason if rejected (required for rejection)
#' @param db_path Character: Database path (optional)
#'
#' @return List with review result
#'
#' @export
review_rectification_item <- function(item_id,
                                       decision,
                                       reviewed_by,
                                       rejection_reason = NULL,
                                       db_path = NULL) {

  if (!decision %in% c("APPROVED", "REJECTED")) {
    return(list(
      success = FALSE,
      error = "Decision must be APPROVED or REJECTED"
    ))
  }

  if (decision == "REJECTED" && (is.null(rejection_reason) || nchar(rejection_reason) < 10)) {
    return(list(
      success = FALSE,
      error = "Rejection reason must be at least 10 characters"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    item <- DBI::dbGetQuery(conn, "
      SELECT request_id, field_name FROM rectification_items WHERE item_id = ?
    ", list(item_id))

    if (nrow(item) == 0) {
      return(list(success = FALSE, error = "Item not found"))
    }

    DBI::dbExecute(conn, "
      UPDATE rectification_items
      SET status = ?,
          rejection_reason = ?
      WHERE item_id = ?
    ", list(
      decision,
      safe_scalar_rect(rejection_reason),
      item_id
    ))

    log_rectification_action(
      request_id = item$request_id,
      item_id = item_id,
      action = paste("ITEM", decision),
      action_details = paste("Item", item$field_name, decision),
      performed_by = reviewed_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      item_id = item_id,
      decision = decision,
      message = paste("Item", tolower(decision), "successfully")
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Apply Rectification Item
#'
#' Applies an approved rectification to the actual data.
#'
#' @param item_id Integer: Item ID
#' @param applied_by Character: User applying change
#' @param db_path Character: Database path (optional)
#'
#' @return List with application result
#'
#' @export
apply_rectification_item <- function(item_id,
                                      applied_by,
                                      db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    item <- DBI::dbGetQuery(conn, "
      SELECT * FROM rectification_items WHERE item_id = ?
    ", list(item_id))

    if (nrow(item) == 0) {
      return(list(success = FALSE, error = "Item not found"))
    }

    if (item$status != "APPROVED") {
      return(list(success = FALSE, error = "Item must be approved before applying"))
    }

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE rectification_items
      SET status = 'APPLIED',
          applied_at = ?,
          applied_by = ?
      WHERE item_id = ?
    ", list(
      timestamp,
      safe_scalar_rect(applied_by),
      item_id
    ))

    log_rectification_action(
      request_id = item$request_id,
      item_id = item_id,
      action = "ITEM_APPLIED",
      action_details = paste("Rectification applied to", item$table_name, ".",
                             item$field_name),
      performed_by = applied_by,
      previous_value = item$current_value,
      new_value = item$requested_value,
      db_path = db_path
    )

    list(
      success = TRUE,
      item_id = item_id,
      table_name = item$table_name,
      record_id = item$record_id,
      field_name = item$field_name,
      old_value = item$current_value,
      new_value = item$requested_value,
      message = "Rectification applied successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Third-Party Notifications
# =============================================================================

#' Add Third-Party Recipient
#'
#' Adds a third party who received the data and needs notification.
#'
#' @param request_id Integer: Request ID
#' @param recipient_name Character: Recipient organization name
#' @param recipient_type Character: PROCESSOR, CONTROLLER, THIRD_PARTY, REGULATOR
#' @param data_shared Character: Description of data shared
#' @param added_by Character: User adding recipient
#' @param contact_email Character: Contact email (optional)
#' @param contact_name Character: Contact name (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with addition result
#'
#' @export
add_third_party_recipient <- function(request_id,
                                       recipient_name,
                                       recipient_type,
                                       data_shared,
                                       added_by,
                                       contact_email = NULL,
                                       contact_name = NULL,
                                       db_path = NULL) {

  valid_types <- c("PROCESSOR", "CONTROLLER", "THIRD_PARTY", "REGULATOR")
  if (!recipient_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid recipient type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      INSERT INTO third_party_recipients (
        request_id, recipient_name, recipient_type, contact_email,
        contact_name, data_shared, notification_required
      ) VALUES (?, ?, ?, ?, ?, ?, 1)
    ", list(
      request_id,
      safe_scalar_rect(recipient_name),
      safe_scalar_rect(recipient_type),
      safe_scalar_rect(contact_email),
      safe_scalar_rect(contact_name),
      safe_scalar_rect(data_shared)
    ))

    recipient_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_rectification_action(
      request_id = request_id,
      action = "RECIPIENT_ADDED",
      action_details = paste("Third party added:", recipient_name),
      performed_by = added_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      recipient_id = recipient_id,
      message = "Third party recipient added successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Send Third-Party Notification
#'
#' Records that notification was sent to a third party.
#'
#' @param recipient_id Integer: Recipient ID
#' @param notification_method Character: EMAIL, API, POSTAL, MANUAL
#' @param sent_by Character: User sending notification
#' @param notification_content Character: Content of notification (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with notification result
#'
#' @export
send_third_party_notification <- function(recipient_id,
                                           notification_method,
                                           sent_by,
                                           notification_content = NULL,
                                           db_path = NULL) {

  valid_methods <- c("EMAIL", "API", "POSTAL", "MANUAL")
  if (!notification_method %in% valid_methods) {
    return(list(
      success = FALSE,
      error = paste("Invalid method. Must be one of:",
                    paste(valid_methods, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    recipient <- DBI::dbGetQuery(conn, "
      SELECT request_id, recipient_name, contact_email
      FROM third_party_recipients
      WHERE recipient_id = ?
    ", list(recipient_id))

    if (nrow(recipient) == 0) {
      return(list(success = FALSE, error = "Recipient not found"))
    }

    notification_date <- Sys.Date()
    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE third_party_recipients
      SET notification_sent = 1,
          notification_sent_date = ?,
          notification_sent_by = ?,
          notification_method = ?
      WHERE recipient_id = ?
    ", list(
      as.character(notification_date),
      safe_scalar_rect(sent_by),
      safe_scalar_rect(notification_method),
      recipient_id
    ))

    hash_content <- paste(
      recipient$request_id, recipient_id, "THIRD_PARTY_NOTIFICATION",
      notification_content, timestamp,
      sep = "|"
    )
    notification_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO rectification_notifications (
        request_id, recipient_id, notification_type,
        recipient_email, notification_content, sent_at, sent_by,
        delivery_status, notification_hash
      ) VALUES (?, ?, 'THIRD_PARTY_NOTIFICATION', ?, ?, ?, ?, 'SENT', ?)
    ", list(
      recipient$request_id,
      recipient_id,
      safe_scalar_rect(recipient$contact_email),
      safe_scalar_rect(notification_content),
      timestamp,
      safe_scalar_rect(sent_by),
      notification_hash
    ))

    log_rectification_action(
      request_id = recipient$request_id,
      action = "THIRD_PARTY_NOTIFIED",
      action_details = paste("Notification sent to:", recipient$recipient_name),
      performed_by = sent_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      recipient_id = recipient_id,
      recipient_name = recipient$recipient_name,
      message = "Third party notification sent successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Record Third-Party Acknowledgment
#'
#' Records acknowledgment from a third party.
#'
#' @param recipient_id Integer: Recipient ID
#' @param recorded_by Character: User recording acknowledgment
#' @param db_path Character: Database path (optional)
#'
#' @return List with recording result
#'
#' @export
record_third_party_acknowledgment <- function(recipient_id,
                                               recorded_by,
                                               db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      UPDATE third_party_recipients
      SET acknowledgment_received = 1,
          acknowledgment_date = ?
      WHERE recipient_id = ?
    ", list(
      as.character(Sys.Date()),
      recipient_id
    ))

    list(
      success = TRUE,
      message = "Acknowledgment recorded successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Request Completion
# =============================================================================

#' Complete Rectification Request
#'
#' Completes a rectification request after all items are processed.
#'
#' @param request_id Integer: Request ID
#' @param completed_by Character: User completing request
#' @param db_path Character: Database path (optional)
#'
#' @return List with completion result
#'
#' @export
complete_rectification_request <- function(request_id,
                                            completed_by,
                                            db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    items <- DBI::dbGetQuery(conn, "
      SELECT status, COUNT(*) as count
      FROM rectification_items
      WHERE request_id = ?
      GROUP BY status
    ", list(request_id))

    pending <- sum(items$count[items$status == "PENDING"])
    approved_pending <- sum(items$count[items$status == "APPROVED"])

    if (pending > 0) {
      return(list(
        success = FALSE,
        error = paste(pending, "items still pending review")
      ))
    }

    if (approved_pending > 0) {
      return(list(
        success = FALSE,
        error = paste(approved_pending, "approved items not yet applied")
      ))
    }

    pending_notifications <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as count
      FROM third_party_recipients
      WHERE request_id = ? AND notification_required = 1 AND notification_sent = 0
    ", list(request_id))

    if (pending_notifications$count > 0) {
      return(list(
        success = FALSE,
        error = paste(pending_notifications$count,
                      "third party notifications pending")
      ))
    }

    applied <- sum(items$count[items$status == "APPLIED"])
    rejected <- sum(items$count[items$status == "REJECTED"])

    final_status <- if (rejected == 0 && applied > 0) {
      "COMPLETED"
    } else if (applied > 0 && rejected > 0) {
      "COMPLETED"
    } else {
      "COMPLETED"
    }

    timestamp <- as.character(Sys.time())
    DBI::dbExecute(conn, "
      UPDATE rectification_requests
      SET status = ?,
          completed_date = ?,
          reviewed_by = ?,
          reviewed_at = ?
      WHERE request_id = ?
    ", list(
      final_status,
      as.character(Sys.Date()),
      safe_scalar_rect(completed_by),
      timestamp,
      request_id
    ))

    log_rectification_action(
      request_id = request_id,
      action = "REQUEST_COMPLETED",
      action_details = paste("Request completed. Applied:", applied, "Rejected:", rejected),
      performed_by = completed_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      status = final_status,
      items_applied = applied,
      items_rejected = rejected,
      message = "Rectification request completed successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Reject Rectification Request
#'
#' Rejects an entire rectification request.
#'
#' @param request_id Integer: Request ID
#' @param rejection_reason Character: Reason for rejection (min 20 chars)
#' @param rejected_by Character: User rejecting request
#' @param db_path Character: Database path (optional)
#'
#' @return List with rejection result
#'
#' @export
reject_rectification_request <- function(request_id,
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
      UPDATE rectification_requests
      SET status = 'REJECTED',
          rejection_reason = ?,
          reviewed_by = ?,
          reviewed_at = ?,
          completed_date = ?
      WHERE request_id = ?
    ", list(
      safe_scalar_rect(rejection_reason),
      safe_scalar_rect(rejected_by),
      timestamp,
      as.character(Sys.Date()),
      request_id
    ))

    log_rectification_action(
      request_id = request_id,
      action = "REQUEST_REJECTED",
      action_details = paste("Request rejected:", rejection_reason),
      performed_by = rejected_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      message = "Rectification request rejected"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Retrieval Functions
# =============================================================================

#' Get Rectification Request
#'
#' Retrieves a rectification request.
#'
#' @param request_id Integer: Request ID (optional)
#' @param request_number Character: Request number (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with request details
#'
#' @export
get_rectification_request <- function(request_id = NULL,
                                       request_number = NULL,
                                       db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (!is.null(request_id)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM rectification_requests WHERE request_id = ?
      ", list(request_id))
    } else if (!is.null(request_number)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM rectification_requests WHERE request_number = ?
      ", list(safe_scalar_rect(request_number)))
    } else {
      data.frame()
    }

  }, error = function(e) data.frame())
}


#' Get Rectification Items
#'
#' Retrieves items for a rectification request.
#'
#' @param request_id Integer: Request ID
#' @param status Character: Filter by status (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with items
#'
#' @export
get_rectification_items <- function(request_id,
                                     status = NULL,
                                     db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (!is.null(status)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM rectification_items
        WHERE request_id = ? AND status = ?
        ORDER BY item_id
      ", list(request_id, safe_scalar_rect(status)))
    } else {
      DBI::dbGetQuery(conn, "
        SELECT * FROM rectification_items
        WHERE request_id = ?
        ORDER BY item_id
      ", list(request_id))
    }

  }, error = function(e) data.frame())
}


#' Get Third-Party Recipients
#'
#' Retrieves third-party recipients for a request.
#'
#' @param request_id Integer: Request ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with recipients
#'
#' @export
get_third_party_recipients <- function(request_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM third_party_recipients
      WHERE request_id = ?
      ORDER BY recipient_id
    ", list(request_id))

  }, error = function(e) data.frame())
}


#' Get Rectification History
#'
#' Retrieves history for a rectification request.
#'
#' @param request_id Integer: Request ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with history entries
#'
#' @export
get_rectification_history <- function(request_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM rectification_history
      WHERE request_id = ?
      ORDER BY performed_at ASC
    ", list(request_id))

  }, error = function(e) data.frame())
}


#' Get Pending Rectification Requests
#'
#' Retrieves pending rectification requests.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with pending requests
#'
#' @export
get_pending_rectification_requests <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM rectification_requests
      WHERE status NOT IN ('COMPLETED', 'REJECTED', 'CLOSED')
      ORDER BY due_date ASC
    ")

  }, error = function(e) data.frame())
}


# =============================================================================
# Statistics and Reporting
# =============================================================================

#' Get Rectification Statistics
#'
#' Returns rectification statistics.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with statistics
#'
#' @export
get_rectification_statistics <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    overall <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_requests,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status NOT IN ('COMPLETED', 'REJECTED', 'CLOSED') THEN 1 ELSE 0 END) as pending
      FROM rectification_requests
    ")

    items <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_items,
        SUM(CASE WHEN status = 'APPLIED' THEN 1 ELSE 0 END) as applied,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) as pending
      FROM rectification_items
    ")

    by_type <- DBI::dbGetQuery(conn, "
      SELECT request_type, COUNT(*) as count
      FROM rectification_requests
      GROUP BY request_type
    ")

    third_party <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_recipients,
        SUM(CASE WHEN notification_sent = 1 THEN 1 ELSE 0 END) as notified,
        SUM(CASE WHEN acknowledgment_received = 1 THEN 1 ELSE 0 END) as acknowledged
      FROM third_party_recipients
    ")

    list(
      success = TRUE,
      requests = list(
        total = overall$total_requests,
        completed = overall$completed,
        rejected = overall$rejected,
        pending = overall$pending
      ),
      items = list(
        total = items$total_items,
        applied = items$applied,
        rejected = items$rejected,
        pending = items$pending
      ),
      by_type = by_type,
      third_party = list(
        total_recipients = third_party$total_recipients,
        notified = third_party$notified,
        acknowledged = third_party$acknowledged
      )
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Generate Rectification Report
#'
#' Generates a rectification compliance report.
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
generate_rectification_report <- function(output_file,
                                           format = "txt",
                                           organization = "Organization",
                                           prepared_by = "DPO",
                                           db_path = NULL) {
  tryCatch({
    stats <- get_rectification_statistics(db_path = db_path)

    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    requests <- DBI::dbGetQuery(conn, "
      SELECT request_number, request_type, subject_name, status,
             received_date, due_date, completed_date
      FROM rectification_requests
      ORDER BY received_date DESC
      LIMIT 50
    ")

    if (format == "json") {
      report_data <- list(
        report_type = "Rectification Compliance Report",
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
        "                    RECTIFICATION COMPLIANCE REPORT",
        "                         (GDPR Article 16)",
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
        paste("Total Requests:", stats$requests$total),
        paste("Completed:", stats$requests$completed),
        paste("Rejected:", stats$requests$rejected),
        paste("Pending:", stats$requests$pending),
        "",
        paste("Total Items:", stats$items$total),
        paste("Items Applied:", stats$items$applied),
        paste("Items Rejected:", stats$items$rejected),
        paste("Items Pending:", stats$items$pending),
        "",
        paste("Third Parties Notified:", stats$third_party$notified, "/",
              stats$third_party$total_recipients),
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
