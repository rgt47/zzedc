#' Right to Restrict Processing System
#'
#' GDPR Article 18 compliant restriction of processing system.
#' Allows data subjects to request that their data not be processed
#' while still being retained. Integrates with legal holds and
#' provides third-party notification per Article 19.
#'
#' @name restriction
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' Safe Scalar Conversion for Restriction System
#'
#' Converts values to scalar character, handling NULL and vectors.
#'
#' @param x Value to convert
#' @param default Default value if NULL or empty
#' @return Character scalar
#' @keywords internal
safe_scalar_restriction <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' Safe Integer Conversion for Restriction System
#'
#' Converts values to integer scalar, handling NULL.
#'
#' @param x Value to convert
#' @param default Default value if NULL or empty
#' @return Integer scalar
#' @keywords internal
safe_int_restriction <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

#' Generate Restriction Request Number
#'
#' Generates a unique restriction request number.
#'
#' @return Character string in format RESTR-TIMESTAMP-RANDOM
#' @keywords internal
generate_restriction_number <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(c(0:9, LETTERS), 6, replace = TRUE), collapse = "")
  paste0("RESTR-", timestamp, "-", random)
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize Restriction System Tables
#'
#' Creates the database tables required for GDPR Article 18
#' Right to Restrict Processing compliance.
#'
#' Tables created:
#' - restriction_requests: Main restriction request tracking
#' - restriction_items: Individual data items under restriction
#' - restriction_history: Audit trail for all actions
#' - restriction_third_parties: Third-party notification tracking
#' - processing_attempts: Log of blocked processing attempts
#'
#' @return List with success status and message
#' @export
#'
#' @examples
#' \dontrun{
#' init_restriction()
#' }
init_restriction <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS restriction_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT UNIQUE NOT NULL,
        dsar_request_id INTEGER,
        subject_id TEXT,
        subject_email TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        restriction_grounds TEXT NOT NULL,
        status TEXT DEFAULT 'RECEIVED',
        received_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        completed_date TEXT,
        requested_by TEXT NOT NULL,
        reviewed_by TEXT,
        reviewed_at TEXT,
        review_notes TEXT,
        rejection_reason TEXT,
        lifted_date TEXT,
        lifted_by TEXT,
        lift_reason TEXT,
        legal_hold_id INTEGER,
        request_hash TEXT NOT NULL,
        previous_hash TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (dsar_request_id) REFERENCES dsar_requests(request_id),
        FOREIGN KEY (legal_hold_id) REFERENCES legal_holds(hold_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS restriction_items (
        item_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        data_category TEXT NOT NULL,
        field_name TEXT,
        restriction_scope TEXT DEFAULT 'FULL',
        status TEXT DEFAULT 'PENDING',
        rejection_reason TEXT,
        applied_at TEXT,
        applied_by TEXT,
        lifted_at TEXT,
        lifted_by TEXT,
        lift_reason TEXT,
        item_hash TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (request_id) REFERENCES restriction_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS restriction_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        item_id INTEGER,
        action TEXT NOT NULL,
        action_details TEXT,
        performed_by TEXT NOT NULL,
        performed_at TEXT DEFAULT (datetime('now')),
        history_hash TEXT NOT NULL,
        previous_history_hash TEXT,
        FOREIGN KEY (request_id) REFERENCES restriction_requests(request_id),
        FOREIGN KEY (item_id) REFERENCES restriction_items(item_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS restriction_third_parties (
        recipient_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        recipient_name TEXT NOT NULL,
        recipient_type TEXT NOT NULL,
        contact_email TEXT,
        contact_name TEXT,
        data_shared TEXT,
        notification_required INTEGER DEFAULT 1,
        notification_sent INTEGER DEFAULT 0,
        notification_sent_date TEXT,
        notification_sent_by TEXT,
        restriction_confirmed INTEGER DEFAULT 0,
        restriction_confirmed_date TEXT,
        lift_notification_sent INTEGER DEFAULT 0,
        lift_notification_sent_date TEXT,
        notes TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (request_id) REFERENCES restriction_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS processing_attempts (
        attempt_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER,
        item_id INTEGER,
        subject_id TEXT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        operation_details TEXT,
        attempted_by TEXT NOT NULL,
        attempted_at TEXT DEFAULT (datetime('now')),
        was_blocked INTEGER DEFAULT 1,
        override_reason TEXT,
        override_authorized_by TEXT,
        attempt_hash TEXT NOT NULL,
        FOREIGN KEY (request_id) REFERENCES restriction_requests(request_id),
        FOREIGN KEY (item_id) REFERENCES restriction_items(item_id)
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_restriction_requests_status
                         ON restriction_requests(status)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_restriction_requests_subject
                         ON restriction_requests(subject_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_restriction_items_status
                         ON restriction_items(status)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_restriction_items_table_record
                         ON restriction_items(table_name, record_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_processing_attempts_subject
                         ON processing_attempts(subject_id)")

    list(success = TRUE, message = "Restriction system initialized successfully")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Restriction Grounds
#'
#' Returns valid GDPR Article 18(1) grounds for restriction.
#'
#' @return Named character vector of restriction grounds
#' @export
#'
#' @examples
#' grounds <- get_restriction_grounds()
get_restriction_grounds <- function() {
  c(
    ACCURACY_CONTESTED = "Accuracy of data contested by subject",
    UNLAWFUL_PROCESSING = "Processing is unlawful but subject opposes erasure",
    LEGAL_CLAIMS = "Controller no longer needs data but subject needs for legal claims",
    OBJECTION_PENDING = "Subject objected under Article 21, pending verification"
  )
}

#' Get Restriction Statuses
#'
#' Returns valid status values for restriction requests.
#'
#' @return Named character vector of status values
#' @export
#'
#' @examples
#' statuses <- get_restriction_statuses()
get_restriction_statuses <- function() {
  c(
    RECEIVED = "Request received",
    UNDER_REVIEW = "Under review",
    APPROVED = "Restriction approved",
    PARTIALLY_APPROVED = "Partially approved",
    REJECTED = "Request rejected",
    ACTIVE = "Restriction active",
    LIFTED = "Restriction lifted",
    COMPLETED = "Request completed"
  )
}

#' Get Restriction Scopes
#'
#' Returns valid scope values for restriction items.
#'
#' @return Named character vector of scope values
#' @export
#'
#' @examples
#' scopes <- get_restriction_scopes()
get_restriction_scopes <- function() {
  c(
    FULL = "Full restriction on all processing",
    STORAGE_ONLY = "Storage only - no other processing",
    CONSENT_ONLY = "Processing only with explicit consent",
    LEGAL_CLAIMS = "Processing only for legal claims",
    RIGHTS_PROTECTION = "Processing only to protect rights of others",
    PUBLIC_INTEREST = "Processing only for important public interest"
  )
}

#' Get Allowed Processing Types
#'
#' Returns processing types allowed during restriction per GDPR Article 18(2).
#'
#' @return Named character vector of allowed processing types
#' @export
#'
#' @examples
#' allowed <- get_allowed_processing_during_restriction()
get_allowed_processing_during_restriction <- function() {
  c(
    STORAGE = "Storage of data",
    CONSENT_PROCESSING = "Processing with data subject consent",
    LEGAL_CLAIMS = "Processing for legal claims",
    RIGHTS_PROTECTION = "Processing to protect rights of others",
    PUBLIC_INTEREST = "Processing for important public interest",
    BACKUP = "Backup and disaster recovery"
  )
}

# ============================================================================
# REQUEST MANAGEMENT
# ============================================================================

#' Create Restriction Request
#'
#' Creates a new GDPR Article 18 restriction request with hash-chain integrity.
#'
#' @param subject_email Email address of the data subject
#' @param subject_name Name of the data subject
#' @param restriction_grounds Grounds for restriction from get_restriction_grounds()
#' @param requested_by User ID creating the request
#' @param subject_id Optional subject identifier
#' @param dsar_request_id Optional link to related DSAR request
#'
#' @return List with success status, request details or error message
#' @export
#'
#' @examples
#' \dontrun{
#' request <- create_restriction_request(
#'   subject_email = "john@example.com",
#'   subject_name = "John Doe",
#'   restriction_grounds = "ACCURACY_CONTESTED",
#'   requested_by = "dpo"
#' )
#' }
create_restriction_request <- function(subject_email,
                                        subject_name,
                                        restriction_grounds,
                                        requested_by,
                                        subject_id = NULL,
                                        dsar_request_id = NULL) {
  tryCatch({
    if (missing(subject_email) || is.null(subject_email) || subject_email == "") {
      return(list(success = FALSE, error = "subject_email is required"))
    }
    if (missing(subject_name) || is.null(subject_name) || subject_name == "") {
      return(list(success = FALSE, error = "subject_name is required"))
    }
    if (missing(restriction_grounds) || is.null(restriction_grounds) ||
        restriction_grounds == "") {
      return(list(success = FALSE, error = "restriction_grounds is required"))
    }

    valid_grounds <- names(get_restriction_grounds())
    if (!restriction_grounds %in% valid_grounds) {
      return(list(
        success = FALSE,
        error = paste("Invalid restriction_grounds. Must be one of:",
                     paste(valid_grounds, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request_number <- generate_restriction_number()
    received_date <- format(Sys.Date(), "%Y-%m-%d")
    due_date <- format(Sys.Date() + 30, "%Y-%m-%d")

    previous_hash <- NA_character_
    last_request <- DBI::dbGetQuery(con, "
      SELECT request_hash FROM restriction_requests
      ORDER BY request_id DESC LIMIT 1
    ")
    if (nrow(last_request) > 0) {
      previous_hash <- last_request$request_hash[1]
    }

    hash_content <- paste(
      request_number,
      safe_scalar_restriction(subject_id),
      subject_email,
      subject_name,
      restriction_grounds,
      received_date,
      requested_by,
      safe_scalar_restriction(previous_hash),
      sep = "|"
    )
    request_hash <- digest::digest(hash_content, algo = "sha256")

    is_held <- FALSE
    hold_id <- NA_integer_
    status <- "RECEIVED"

    if (!is.null(subject_id)) {
      hold_check <- tryCatch({
        check_legal_hold(subject_id = subject_id)
      }, error = function(e) {
        list(is_held = FALSE)
      })

      if (isTRUE(hold_check$is_held)) {
        is_held <- TRUE
        hold_id <- hold_check$hold_id
        status <- "LEGAL_HOLD"
      }
    }

    DBI::dbExecute(con, "
      INSERT INTO restriction_requests (
        request_number, dsar_request_id, subject_id, subject_email,
        subject_name, restriction_grounds, status, received_date,
        due_date, requested_by, legal_hold_id, request_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_number,
      safe_int_restriction(dsar_request_id),
      safe_scalar_restriction(subject_id),
      subject_email,
      subject_name,
      restriction_grounds,
      status,
      received_date,
      due_date,
      requested_by,
      safe_int_restriction(hold_id),
      request_hash,
      safe_scalar_restriction(previous_hash)
    ))

    request_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_restriction_action(
      request_id = request_id,
      action = "REQUEST_CREATED",
      action_details = paste("Restriction request created. Grounds:",
                            restriction_grounds),
      performed_by = requested_by
    )

    if (is_held) {
      log_restriction_action(
        request_id = request_id,
        action = "LEGAL_HOLD_DETECTED",
        action_details = paste("Request blocked by legal hold ID:", hold_id),
        performed_by = "SYSTEM"
      )
    }

    list(
      success = TRUE,
      request_id = request_id,
      request_number = request_number,
      status = status,
      is_held = is_held,
      legal_hold_id = if (is_held) hold_id else NULL,
      due_date = due_date,
      message = if (is_held) {
        "Restriction request created but blocked by legal hold"
      } else {
        "Restriction request created successfully"
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Log Restriction Action
#'
#' Logs an action to the restriction audit history with hash-chain.
#'
#' @param request_id Request ID
#' @param action Action performed
#' @param action_details Details of the action
#' @param performed_by User who performed the action
#' @param item_id Optional item ID
#'
#' @return List with success status
#' @keywords internal
log_restriction_action <- function(request_id,
                                    action,
                                    action_details,
                                    performed_by,
                                    item_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    previous_hash <- NA_character_
    last_history <- DBI::dbGetQuery(con, "
      SELECT history_hash FROM restriction_history
      WHERE request_id = ?
      ORDER BY history_id DESC LIMIT 1
    ", params = list(request_id))

    if (nrow(last_history) > 0) {
      previous_hash <- last_history$history_hash[1]
    }

    performed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    hash_content <- paste(
      request_id,
      safe_int_restriction(item_id),
      action,
      action_details,
      performed_by,
      performed_at,
      safe_scalar_restriction(previous_hash),
      sep = "|"
    )
    history_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO restriction_history (
        request_id, item_id, action, action_details,
        performed_by, performed_at, history_hash, previous_history_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      safe_int_restriction(item_id),
      action,
      action_details,
      performed_by,
      performed_at,
      history_hash,
      safe_scalar_restriction(previous_hash)
    ))

    list(success = TRUE)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# ITEM MANAGEMENT
# ============================================================================

#' Add Restriction Item
#'
#' Adds a data item to be restricted under a request.
#'
#' @param request_id Request ID
#' @param table_name Table containing the data
#' @param record_id Record identifier
#' @param data_category Category of data
#' @param added_by User adding the item
#' @param field_name Optional specific field to restrict
#' @param restriction_scope Scope of restriction from get_restriction_scopes()
#'
#' @return List with success status and item details
#' @export
#'
#' @examples
#' \dontrun{
#' item <- add_restriction_item(
#'   request_id = 1,
#'   table_name = "subjects",
#'   record_id = "SUBJ-001",
#'   data_category = "CONTACT",
#'   added_by = "dpo"
#' )
#' }
add_restriction_item <- function(request_id,
                                  table_name,
                                  record_id,
                                  data_category,
                                  added_by,
                                  field_name = NULL,
                                  restriction_scope = "FULL") {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(table_name) || is.null(table_name) || table_name == "") {
      return(list(success = FALSE, error = "table_name is required"))
    }
    if (missing(record_id) || is.null(record_id) || record_id == "") {
      return(list(success = FALSE, error = "record_id is required"))
    }
    if (missing(data_category) || is.null(data_category) || data_category == "") {
      return(list(success = FALSE, error = "data_category is required"))
    }

    valid_scopes <- names(get_restriction_scopes())
    if (!restriction_scope %in% valid_scopes) {
      return(list(
        success = FALSE,
        error = paste("Invalid restriction_scope. Must be one of:",
                     paste(valid_scopes, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status, subject_id FROM restriction_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    is_on_hold <- FALSE
    hold_reason <- NULL

    hold_check <- tryCatch({
      check_legal_hold(data_category = data_category)
    }, error = function(e) {
      list(is_held = FALSE)
    })

    if (isTRUE(hold_check$is_held)) {
      is_on_hold <- TRUE
      hold_reason <- paste("Data category under legal hold:",
                          hold_check$hold_type)
    }

    status <- if (is_on_hold) "ON_HOLD" else "PENDING"

    hash_content <- paste(
      request_id,
      table_name,
      record_id,
      data_category,
      safe_scalar_restriction(field_name),
      restriction_scope,
      status,
      added_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    item_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO restriction_items (
        request_id, table_name, record_id, data_category,
        field_name, restriction_scope, status, item_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      table_name,
      record_id,
      data_category,
      safe_scalar_restriction(field_name),
      restriction_scope,
      status,
      item_hash
    ))

    item_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_restriction_action(
      request_id = request_id,
      item_id = item_id,
      action = "ITEM_ADDED",
      action_details = paste("Restriction item added:", table_name, "-",
                            record_id, "- Category:", data_category),
      performed_by = added_by
    )

    if (is_on_hold) {
      log_restriction_action(
        request_id = request_id,
        item_id = item_id,
        action = "ITEM_ON_HOLD",
        action_details = hold_reason,
        performed_by = "SYSTEM"
      )
    }

    list(
      success = TRUE,
      item_id = item_id,
      status = status,
      is_on_hold = is_on_hold,
      hold_reason = hold_reason,
      message = if (is_on_hold) {
        "Item added but on hold due to legal hold"
      } else {
        "Restriction item added successfully"
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Review Restriction Item
#'
#' Approves or rejects a restriction item.
#'
#' @param item_id Item ID to review
#' @param decision Decision: "APPROVED" or "REJECTED"
#' @param reviewed_by User reviewing the item
#' @param rejection_reason Required if rejecting
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' review_restriction_item(
#'   item_id = 1,
#'   decision = "APPROVED",
#'   reviewed_by = "admin"
#' )
#' }
review_restriction_item <- function(item_id,
                                     decision,
                                     reviewed_by,
                                     rejection_reason = NULL) {
  tryCatch({
    if (missing(item_id) || is.null(item_id)) {
      return(list(success = FALSE, error = "item_id is required"))
    }
    if (!decision %in% c("APPROVED", "REJECTED")) {
      return(list(success = FALSE, error = "decision must be APPROVED or REJECTED"))
    }
    if (decision == "REJECTED" &&
        (is.null(rejection_reason) || rejection_reason == "")) {
      return(list(success = FALSE, error = "rejection_reason required when rejecting"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    item <- DBI::dbGetQuery(con, "
      SELECT item_id, request_id, status FROM restriction_items
      WHERE item_id = ?
    ", params = list(item_id))

    if (nrow(item) == 0) {
      return(list(success = FALSE, error = "Item not found"))
    }

    if (item$status[1] == "ON_HOLD") {
      return(list(success = FALSE, error = "Cannot review item that is on hold"))
    }

    if (item$status[1] != "PENDING") {
      return(list(success = FALSE,
                  error = paste("Item is not pending. Current status:",
                               item$status[1])))
    }

    if (decision == "APPROVED") {
      DBI::dbExecute(con, "
        UPDATE restriction_items
        SET status = 'APPROVED'
        WHERE item_id = ?
      ", params = list(item_id))
    } else {
      DBI::dbExecute(con, "
        UPDATE restriction_items
        SET status = 'REJECTED', rejection_reason = ?
        WHERE item_id = ?
      ", params = list(rejection_reason, item_id))
    }

    log_restriction_action(
      request_id = item$request_id[1],
      item_id = item_id,
      action = paste0("ITEM_", decision),
      action_details = if (decision == "REJECTED") {
        paste("Item rejected:", rejection_reason)
      } else {
        "Item approved for restriction"
      },
      performed_by = reviewed_by
    )

    list(
      success = TRUE,
      status = decision,
      message = paste("Item", tolower(decision), "successfully")
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Apply Restriction Item
#'
#' Applies the approved restriction to a data item.
#'
#' @param item_id Item ID to apply
#' @param applied_by User applying the restriction
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' apply_restriction_item(
#'   item_id = 1,
#'   applied_by = "data_manager"
#' )
#' }
apply_restriction_item <- function(item_id, applied_by) {
  tryCatch({
    if (missing(item_id) || is.null(item_id)) {
      return(list(success = FALSE, error = "item_id is required"))
    }
    if (missing(applied_by) || is.null(applied_by) || applied_by == "") {
      return(list(success = FALSE, error = "applied_by is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    item <- DBI::dbGetQuery(con, "
      SELECT item_id, request_id, status, table_name, record_id
      FROM restriction_items
      WHERE item_id = ?
    ", params = list(item_id))

    if (nrow(item) == 0) {
      return(list(success = FALSE, error = "Item not found"))
    }

    if (item$status[1] != "APPROVED") {
      return(list(success = FALSE,
                  error = paste("Item must be approved before applying.",
                               "Current status:", item$status[1])))
    }

    applied_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE restriction_items
      SET status = 'ACTIVE', applied_at = ?, applied_by = ?
      WHERE item_id = ?
    ", params = list(applied_at, applied_by, item_id))

    log_restriction_action(
      request_id = item$request_id[1],
      item_id = item_id,
      action = "RESTRICTION_APPLIED",
      action_details = paste("Restriction applied to", item$table_name[1],
                            "-", item$record_id[1]),
      performed_by = applied_by
    )

    list(
      success = TRUE,
      status = "ACTIVE",
      applied_at = applied_at,
      message = "Restriction applied successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Lift Restriction Item
#'
#' Lifts the restriction on a data item.
#'
#' @param item_id Item ID
#' @param lifted_by User lifting the restriction
#' @param lift_reason Reason for lifting (minimum 20 characters)
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' lift_restriction_item(
#'   item_id = 1,
#'   lifted_by = "dpo",
#'   lift_reason = "Accuracy dispute resolved in favor of data subject"
#' )
#' }
lift_restriction_item <- function(item_id, lifted_by, lift_reason) {
  tryCatch({
    if (missing(item_id) || is.null(item_id)) {
      return(list(success = FALSE, error = "item_id is required"))
    }
    if (missing(lifted_by) || is.null(lifted_by) || lifted_by == "") {
      return(list(success = FALSE, error = "lifted_by is required"))
    }
    if (missing(lift_reason) || is.null(lift_reason) || nchar(lift_reason) < 20) {
      return(list(success = FALSE,
                  error = "lift_reason must be at least 20 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    item <- DBI::dbGetQuery(con, "
      SELECT item_id, request_id, status, table_name, record_id
      FROM restriction_items
      WHERE item_id = ?
    ", params = list(item_id))

    if (nrow(item) == 0) {
      return(list(success = FALSE, error = "Item not found"))
    }

    if (item$status[1] != "ACTIVE") {
      return(list(success = FALSE,
                  error = paste("Only active restrictions can be lifted.",
                               "Current status:", item$status[1])))
    }

    lifted_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE restriction_items
      SET status = 'LIFTED', lifted_at = ?, lifted_by = ?, lift_reason = ?
      WHERE item_id = ?
    ", params = list(lifted_at, lifted_by, lift_reason, item_id))

    log_restriction_action(
      request_id = item$request_id[1],
      item_id = item_id,
      action = "RESTRICTION_LIFTED",
      action_details = paste("Restriction lifted:", lift_reason),
      performed_by = lifted_by
    )

    list(
      success = TRUE,
      status = "LIFTED",
      lifted_at = lifted_at,
      message = "Restriction lifted successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# PROCESSING CONTROL
# ============================================================================
#' Check Restriction Status
#'
#' Checks if a data record is currently under restriction.
#'
#' @param table_name Table containing the data
#' @param record_id Record identifier
#' @param subject_id Optional subject identifier
#'
#' @return List with restriction status and details
#' @export
#'
#' @examples
#' \dontrun{
#' status <- check_restriction_status(
#'   table_name = "subjects",
#'   record_id = "SUBJ-001"
#' )
#' print(status$is_restricted)
#' }
check_restriction_status <- function(table_name, record_id, subject_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "
      SELECT ri.item_id, ri.request_id, ri.restriction_scope,
             rr.restriction_grounds, rr.subject_id, rr.subject_name
      FROM restriction_items ri
      JOIN restriction_requests rr ON ri.request_id = rr.request_id
      WHERE ri.table_name = ? AND ri.record_id = ? AND ri.status = 'ACTIVE'
    "
    params <- list(table_name, record_id)

    if (!is.null(subject_id)) {
      query <- gsub("AND ri.status = 'ACTIVE'",
                    "AND ri.status = 'ACTIVE' AND rr.subject_id = ?", query)
      params <- append(params, subject_id)
    }

    restrictions <- DBI::dbGetQuery(con, query, params = params)

    if (nrow(restrictions) == 0) {
      list(
        success = TRUE,
        is_restricted = FALSE,
        message = "No active restrictions on this record"
      )
    } else {
      list(
        success = TRUE,
        is_restricted = TRUE,
        restriction_count = nrow(restrictions),
        restrictions = restrictions,
        allowed_processing = get_allowed_processing_during_restriction(),
        message = paste("Record has", nrow(restrictions), "active restriction(s)")
      )
    }

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Log Processing Attempt
#'
#' Logs an attempt to process restricted data (for audit purposes).
#'
#' @param table_name Table containing the data
#' @param record_id Record identifier
#' @param operation_type Type of operation attempted
#' @param attempted_by User attempting the operation
#' @param subject_id Optional subject identifier
#' @param operation_details Optional details about the operation
#' @param was_blocked Whether the operation was blocked
#' @param override_reason Reason if operation was allowed
#' @param override_authorized_by User who authorized override
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' log_processing_attempt(
#'   table_name = "subjects",
#'   record_id = "SUBJ-001",
#'   operation_type = "UPDATE",
#'   attempted_by = "user123"
#' )
#' }
log_processing_attempt <- function(table_name,
                                    record_id,
                                    operation_type,
                                    attempted_by,
                                    subject_id = NULL,
                                    operation_details = NULL,
                                    was_blocked = TRUE,
                                    override_reason = NULL,
                                    override_authorized_by = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    restriction <- DBI::dbGetQuery(con, "
      SELECT ri.item_id, ri.request_id
      FROM restriction_items ri
      WHERE ri.table_name = ? AND ri.record_id = ? AND ri.status = 'ACTIVE'
      LIMIT 1
    ", params = list(table_name, record_id))

    request_id <- if (nrow(restriction) > 0) restriction$request_id[1] else NA
    item_id <- if (nrow(restriction) > 0) restriction$item_id[1] else NA

    hash_content <- paste(
      safe_int_restriction(request_id),
      safe_int_restriction(item_id),
      safe_scalar_restriction(subject_id),
      table_name,
      record_id,
      operation_type,
      attempted_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    attempt_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO processing_attempts (
        request_id, item_id, subject_id, table_name, record_id,
        operation_type, operation_details, attempted_by, was_blocked,
        override_reason, override_authorized_by, attempt_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      safe_int_restriction(request_id),
      safe_int_restriction(item_id),
      safe_scalar_restriction(subject_id),
      table_name,
      record_id,
      operation_type,
      safe_scalar_restriction(operation_details),
      attempted_by,
      as.integer(was_blocked),
      safe_scalar_restriction(override_reason),
      safe_scalar_restriction(override_authorized_by),
      attempt_hash
    ))

    if (!is.na(request_id)) {
      log_restriction_action(
        request_id = request_id,
        item_id = item_id,
        action = if (was_blocked) "PROCESSING_BLOCKED" else "PROCESSING_ALLOWED",
        action_details = paste(
          "Operation:", operation_type,
          if (!was_blocked) paste("- Override:", override_reason) else ""
        ),
        performed_by = attempted_by
      )
    }

    list(
      success = TRUE,
      was_blocked = was_blocked,
      message = if (was_blocked) "Processing attempt logged and blocked" else
        "Processing attempt logged and allowed"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# THIRD-PARTY NOTIFICATIONS
# ============================================================================

#' Add Restriction Third Party
#'
#' Registers a third-party recipient for notification per GDPR Article 19.
#'
#' @param request_id Request ID
#' @param recipient_name Name of recipient organization
#' @param recipient_type Type: PROCESSOR, CONTROLLER, THIRD_PARTY, REGULATOR
#' @param added_by User adding the recipient
#' @param contact_email Optional contact email
#' @param contact_name Optional contact name
#' @param data_shared Optional description of data shared
#' @param notification_required Whether notification is required (default TRUE)
#'
#' @return List with success status and recipient details
#' @export
#'
#' @examples
#' \dontrun{
#' recipient <- add_restriction_third_party(
#'   request_id = 1,
#'   recipient_name = "Analytics Partner",
#'   recipient_type = "PROCESSOR",
#'   added_by = "dpo"
#' )
#' }
add_restriction_third_party <- function(request_id,
                                         recipient_name,
                                         recipient_type,
                                         added_by,
                                         contact_email = NULL,
                                         contact_name = NULL,
                                         data_shared = NULL,
                                         notification_required = TRUE) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(recipient_name) || is.null(recipient_name) ||
        recipient_name == "") {
      return(list(success = FALSE, error = "recipient_name is required"))
    }

    valid_types <- c("PROCESSOR", "CONTROLLER", "THIRD_PARTY", "REGULATOR")
    if (!recipient_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid recipient_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id FROM restriction_requests WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    DBI::dbExecute(con, "
      INSERT INTO restriction_third_parties (
        request_id, recipient_name, recipient_type, contact_email,
        contact_name, data_shared, notification_required
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      recipient_name,
      recipient_type,
      safe_scalar_restriction(contact_email),
      safe_scalar_restriction(contact_name),
      safe_scalar_restriction(data_shared),
      as.integer(notification_required)
    ))

    recipient_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_restriction_action(
      request_id = request_id,
      action = "THIRD_PARTY_ADDED",
      action_details = paste("Third party added:", recipient_name,
                            "(", recipient_type, ")"),
      performed_by = added_by
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

#' Notify Restriction Third Party
#'
#' Records notification sent to third party about restriction.
#'
#' @param recipient_id Recipient ID
#' @param sent_by User who sent the notification
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' notify_restriction_third_party(
#'   recipient_id = 1,
#'   sent_by = "dpo"
#' )
#' }
notify_restriction_third_party <- function(recipient_id, sent_by) {
  tryCatch({
    if (missing(recipient_id) || is.null(recipient_id)) {
      return(list(success = FALSE, error = "recipient_id is required"))
    }
    if (missing(sent_by) || is.null(sent_by) || sent_by == "") {
      return(list(success = FALSE, error = "sent_by is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    recipient <- DBI::dbGetQuery(con, "
      SELECT recipient_id, request_id, recipient_name, notification_sent
      FROM restriction_third_parties
      WHERE recipient_id = ?
    ", params = list(recipient_id))

    if (nrow(recipient) == 0) {
      return(list(success = FALSE, error = "Recipient not found"))
    }

    if (recipient$notification_sent[1] == 1) {
      return(list(success = FALSE, error = "Notification already sent"))
    }

    sent_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE restriction_third_parties
      SET notification_sent = 1, notification_sent_date = ?,
          notification_sent_by = ?
      WHERE recipient_id = ?
    ", params = list(sent_date, sent_by, recipient_id))

    log_restriction_action(
      request_id = recipient$request_id[1],
      action = "THIRD_PARTY_NOTIFIED",
      action_details = paste("Notification sent to:", recipient$recipient_name[1]),
      performed_by = sent_by
    )

    list(
      success = TRUE,
      notification_sent_date = sent_date,
      message = "Third party notification recorded"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Confirm Third Party Restriction
#'
#' Records confirmation that third party has applied restriction.
#'
#' @param recipient_id Recipient ID
#' @param confirmed_by User recording the confirmation
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' confirm_restriction_third_party(
#'   recipient_id = 1,
#'   confirmed_by = "dpo"
#' )
#' }
confirm_restriction_third_party <- function(recipient_id, confirmed_by) {
  tryCatch({
    if (missing(recipient_id) || is.null(recipient_id)) {
      return(list(success = FALSE, error = "recipient_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    recipient <- DBI::dbGetQuery(con, "
      SELECT recipient_id, request_id, recipient_name, notification_sent,
             restriction_confirmed
      FROM restriction_third_parties
      WHERE recipient_id = ?
    ", params = list(recipient_id))

    if (nrow(recipient) == 0) {
      return(list(success = FALSE, error = "Recipient not found"))
    }

    if (recipient$notification_sent[1] == 0) {
      return(list(success = FALSE, error = "Must send notification first"))
    }

    if (recipient$restriction_confirmed[1] == 1) {
      return(list(success = FALSE, error = "Restriction already confirmed"))
    }

    confirmed_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE restriction_third_parties
      SET restriction_confirmed = 1, restriction_confirmed_date = ?
      WHERE recipient_id = ?
    ", params = list(confirmed_date, recipient_id))

    log_restriction_action(
      request_id = recipient$request_id[1],
      action = "THIRD_PARTY_CONFIRMED",
      action_details = paste("Restriction confirmed by:",
                            recipient$recipient_name[1]),
      performed_by = confirmed_by
    )

    list(
      success = TRUE,
      restriction_confirmed_date = confirmed_date,
      message = "Third party restriction confirmation recorded"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Notify Third Party of Lift
#'
#' Records notification sent to third party about restriction being lifted.
#'
#' @param recipient_id Recipient ID
#' @param sent_by User who sent the notification
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' notify_lift_third_party(
#'   recipient_id = 1,
#'   sent_by = "dpo"
#' )
#' }
notify_lift_third_party <- function(recipient_id, sent_by) {
  tryCatch({
    if (missing(recipient_id) || is.null(recipient_id)) {
      return(list(success = FALSE, error = "recipient_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    recipient <- DBI::dbGetQuery(con, "
      SELECT recipient_id, request_id, recipient_name, lift_notification_sent
      FROM restriction_third_parties
      WHERE recipient_id = ?
    ", params = list(recipient_id))

    if (nrow(recipient) == 0) {
      return(list(success = FALSE, error = "Recipient not found"))
    }

    if (recipient$lift_notification_sent[1] == 1) {
      return(list(success = FALSE, error = "Lift notification already sent"))
    }

    sent_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE restriction_third_parties
      SET lift_notification_sent = 1, lift_notification_sent_date = ?
      WHERE recipient_id = ?
    ", params = list(sent_date, recipient_id))

    log_restriction_action(
      request_id = recipient$request_id[1],
      action = "LIFT_NOTIFICATION_SENT",
      action_details = paste("Lift notification sent to:",
                            recipient$recipient_name[1]),
      performed_by = sent_by
    )

    list(
      success = TRUE,
      lift_notification_sent_date = sent_date,
      message = "Lift notification recorded"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REQUEST COMPLETION
# ============================================================================

#' Approve Restriction Request
#'
#' Approves a restriction request and updates status.
#'
#' @param request_id Request ID
#' @param approved_by User approving the request
#' @param review_notes Optional review notes
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' approve_restriction_request(
#'   request_id = 1,
#'   approved_by = "admin"
#' )
#' }
approve_restriction_request <- function(request_id,
                                         approved_by,
                                         review_notes = NULL) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(approved_by) || is.null(approved_by) || approved_by == "") {
      return(list(success = FALSE, error = "approved_by is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status FROM restriction_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (!request$status[1] %in% c("RECEIVED", "UNDER_REVIEW")) {
      return(list(success = FALSE,
                  error = paste("Cannot approve request with status:",
                               request$status[1])))
    }

    reviewed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE restriction_requests
      SET status = 'APPROVED', reviewed_by = ?, reviewed_at = ?,
          review_notes = ?
      WHERE request_id = ?
    ", params = list(approved_by, reviewed_at,
                     safe_scalar_restriction(review_notes), request_id))

    log_restriction_action(
      request_id = request_id,
      action = "REQUEST_APPROVED",
      action_details = paste("Request approved.",
                            if (!is.null(review_notes))
                              paste("Notes:", review_notes) else ""),
      performed_by = approved_by
    )

    list(
      success = TRUE,
      status = "APPROVED",
      reviewed_at = reviewed_at,
      message = "Restriction request approved"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Activate Restriction Request
#'
#' Activates a restriction request after all items have been applied.
#'
#' @param request_id Request ID
#' @param activated_by User activating the request
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' activate_restriction_request(
#'   request_id = 1,
#'   activated_by = "dpo"
#' )
#' }
activate_restriction_request <- function(request_id, activated_by) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status FROM restriction_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (request$status[1] != "APPROVED") {
      return(list(success = FALSE,
                  error = paste("Request must be approved before activation.",
                               "Current status:", request$status[1])))
    }

    items <- DBI::dbGetQuery(con, "
      SELECT status, COUNT(*) as count
      FROM restriction_items
      WHERE request_id = ?
      GROUP BY status
    ", params = list(request_id))

    if (nrow(items) == 0) {
      return(list(success = FALSE, error = "No items in request"))
    }

    active_count <- sum(items$count[items$status == "ACTIVE"], na.rm = TRUE)
    pending_count <- sum(items$count[items$status %in%
                                      c("PENDING", "APPROVED")], na.rm = TRUE)

    if (active_count == 0) {
      return(list(success = FALSE,
                  error = "At least one item must be active to activate request"))
    }

    DBI::dbExecute(con, "
      UPDATE restriction_requests
      SET status = 'ACTIVE'
      WHERE request_id = ?
    ", params = list(request_id))

    log_restriction_action(
      request_id = request_id,
      action = "REQUEST_ACTIVATED",
      action_details = paste("Restriction activated with", active_count,
                            "active item(s)"),
      performed_by = activated_by
    )

    list(
      success = TRUE,
      status = "ACTIVE",
      active_items = active_count,
      pending_items = pending_count,
      message = "Restriction request activated"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Lift Restriction Request
#'
#' Lifts all restrictions and completes the request.
#' Per GDPR Article 18(3), must inform data subject before lifting.
#'
#' @param request_id Request ID
#' @param lifted_by User lifting the restriction
#' @param lift_reason Reason for lifting (minimum 20 characters)
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' lift_restriction_request(
#'   request_id = 1,
#'   lifted_by = "dpo",
#'   lift_reason = "Accuracy verification completed - data confirmed accurate"
#' )
#' }
lift_restriction_request <- function(request_id, lifted_by, lift_reason) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(lift_reason) || is.null(lift_reason) || nchar(lift_reason) < 20) {
      return(list(success = FALSE,
                  error = "lift_reason must be at least 20 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status FROM restriction_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (request$status[1] != "ACTIVE") {
      return(list(success = FALSE,
                  error = paste("Only active restrictions can be lifted.",
                               "Current status:", request$status[1])))
    }

    lifted_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE restriction_items
      SET status = 'LIFTED', lifted_at = ?, lifted_by = ?, lift_reason = ?
      WHERE request_id = ? AND status = 'ACTIVE'
    ", params = list(lifted_date, lifted_by, lift_reason, request_id))

    DBI::dbExecute(con, "
      UPDATE restriction_requests
      SET status = 'LIFTED', lifted_date = ?, lifted_by = ?, lift_reason = ?,
          completed_date = ?
      WHERE request_id = ?
    ", params = list(lifted_date, lifted_by, lift_reason, lifted_date, request_id))

    log_restriction_action(
      request_id = request_id,
      action = "REQUEST_LIFTED",
      action_details = paste("All restrictions lifted:", lift_reason),
      performed_by = lifted_by
    )

    list(
      success = TRUE,
      status = "LIFTED",
      lifted_date = lifted_date,
      message = paste("Restriction lifted. Note: Per GDPR Article 18(3),",
                     "data subject should be informed before lifting restriction.")
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Reject Restriction Request
#'
#' Rejects a restriction request with documented reason.
#'
#' @param request_id Request ID
#' @param rejection_reason Reason for rejection (minimum 20 characters)
#' @param rejected_by User rejecting the request
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' reject_restriction_request(
#'   request_id = 1,
#'   rejection_reason = "Request does not meet GDPR Article 18(1) grounds",
#'   rejected_by = "dpo"
#' )
#' }
reject_restriction_request <- function(request_id,
                                        rejection_reason,
                                        rejected_by) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(rejection_reason) || is.null(rejection_reason) ||
        nchar(rejection_reason) < 20) {
      return(list(success = FALSE,
                  error = "rejection_reason must be at least 20 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status FROM restriction_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (!request$status[1] %in% c("RECEIVED", "UNDER_REVIEW")) {
      return(list(success = FALSE,
                  error = paste("Cannot reject request with status:",
                               request$status[1])))
    }

    reviewed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE restriction_requests
      SET status = 'REJECTED', reviewed_by = ?, reviewed_at = ?,
          rejection_reason = ?, completed_date = ?
      WHERE request_id = ?
    ", params = list(rejected_by, reviewed_at, rejection_reason,
                     reviewed_at, request_id))

    log_restriction_action(
      request_id = request_id,
      action = "REQUEST_REJECTED",
      action_details = paste("Request rejected:", rejection_reason),
      performed_by = rejected_by
    )

    list(
      success = TRUE,
      status = "REJECTED",
      completed_date = reviewed_at,
      message = "Restriction request rejected"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# RETRIEVAL FUNCTIONS
# ============================================================================

#' Get Restriction Request
#'
#' Retrieves a restriction request by ID or request number.
#'
#' @param request_id Optional request ID
#' @param request_number Optional request number
#'
#' @return List with success status and request data
#' @export
#'
#' @examples
#' \dontrun{
#' request <- get_restriction_request(request_id = 1)
#' }
get_restriction_request <- function(request_id = NULL, request_number = NULL) {
  tryCatch({
    if (is.null(request_id) && is.null(request_number)) {
      return(list(success = FALSE,
                  error = "Either request_id or request_number required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (!is.null(request_id)) {
      request <- DBI::dbGetQuery(con, "
        SELECT * FROM restriction_requests WHERE request_id = ?
      ", params = list(request_id))
    } else {
      request <- DBI::dbGetQuery(con, "
        SELECT * FROM restriction_requests WHERE request_number = ?
      ", params = list(request_number))
    }

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    list(
      success = TRUE,
      request = request
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Restriction Items
#'
#' Retrieves items for a restriction request.
#'
#' @param request_id Request ID
#' @param status Optional filter by status
#'
#' @return List with success status and items
#' @export
#'
#' @examples
#' \dontrun{
#' items <- get_restriction_items(request_id = 1, status = "ACTIVE")
#' }
get_restriction_items <- function(request_id, status = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(status)) {
      items <- DBI::dbGetQuery(con, "
        SELECT * FROM restriction_items WHERE request_id = ?
      ", params = list(request_id))
    } else {
      items <- DBI::dbGetQuery(con, "
        SELECT * FROM restriction_items
        WHERE request_id = ? AND status = ?
      ", params = list(request_id, status))
    }

    list(
      success = TRUE,
      items = items,
      count = nrow(items)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Restriction Third Parties
#'
#' Retrieves third-party recipients for a restriction request.
#'
#' @param request_id Request ID
#'
#' @return List with success status and recipients
#' @export
#'
#' @examples
#' \dontrun{
#' recipients <- get_restriction_third_parties(request_id = 1)
#' }
get_restriction_third_parties <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    recipients <- DBI::dbGetQuery(con, "
      SELECT * FROM restriction_third_parties WHERE request_id = ?
    ", params = list(request_id))

    list(
      success = TRUE,
      recipients = recipients,
      count = nrow(recipients)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Restriction History
#'
#' Retrieves audit history for a restriction request.
#'
#' @param request_id Request ID
#'
#' @return List with success status and history
#' @export
#'
#' @examples
#' \dontrun{
#' history <- get_restriction_history(request_id = 1)
#' }
get_restriction_history <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    history <- DBI::dbGetQuery(con, "
      SELECT * FROM restriction_history
      WHERE request_id = ?
      ORDER BY history_id ASC
    ", params = list(request_id))

    list(
      success = TRUE,
      history = history,
      count = nrow(history)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Processing Attempts
#'
#' Retrieves processing attempts for a subject or record.
#'
#' @param subject_id Optional subject ID
#' @param table_name Optional table name
#' @param record_id Optional record ID
#' @param blocked_only Only return blocked attempts (default TRUE)
#'
#' @return List with success status and attempts
#' @export
#'
#' @examples
#' \dontrun{
#' attempts <- get_processing_attempts(subject_id = "SUBJ-001")
#' }
get_processing_attempts <- function(subject_id = NULL,
                                     table_name = NULL,
                                     record_id = NULL,
                                     blocked_only = TRUE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM processing_attempts WHERE 1=1"
    params <- list()

    if (!is.null(subject_id)) {
      query <- paste(query, "AND subject_id = ?")
      params <- append(params, subject_id)
    }

    if (!is.null(table_name)) {
      query <- paste(query, "AND table_name = ?")
      params <- append(params, table_name)
    }

    if (!is.null(record_id)) {
      query <- paste(query, "AND record_id = ?")
      params <- append(params, record_id)
    }

    if (blocked_only) {
      query <- paste(query, "AND was_blocked = 1")
    }

    query <- paste(query, "ORDER BY attempted_at DESC")

    attempts <- DBI::dbGetQuery(con, query, params = params)

    list(
      success = TRUE,
      attempts = attempts,
      count = nrow(attempts)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Pending Restriction Requests
#'
#' Retrieves all pending restriction requests.
#'
#' @param include_held Include requests blocked by legal hold (default FALSE)
#'
#' @return List with success status and requests
#' @export
#'
#' @examples
#' \dontrun{
#' pending <- get_pending_restriction_requests()
#' }
get_pending_restriction_requests <- function(include_held = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (include_held) {
      requests <- DBI::dbGetQuery(con, "
        SELECT * FROM restriction_requests
        WHERE status IN ('RECEIVED', 'UNDER_REVIEW', 'LEGAL_HOLD')
        ORDER BY due_date ASC
      ")
    } else {
      requests <- DBI::dbGetQuery(con, "
        SELECT * FROM restriction_requests
        WHERE status IN ('RECEIVED', 'UNDER_REVIEW')
        ORDER BY due_date ASC
      ")
    }

    list(
      success = TRUE,
      requests = requests,
      count = nrow(requests)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Active Restrictions
#'
#' Retrieves all currently active restrictions.
#'
#' @return List with success status and active restrictions
#' @export
#'
#' @examples
#' \dontrun{
#' active <- get_active_restrictions()
#' }
get_active_restrictions <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    restrictions <- DBI::dbGetQuery(con, "
      SELECT rr.request_id, rr.request_number, rr.subject_id,
             rr.subject_email, rr.subject_name, rr.restriction_grounds,
             ri.item_id, ri.table_name, ri.record_id, ri.data_category,
             ri.restriction_scope, ri.applied_at
      FROM restriction_requests rr
      JOIN restriction_items ri ON rr.request_id = ri.request_id
      WHERE rr.status = 'ACTIVE' AND ri.status = 'ACTIVE'
      ORDER BY ri.applied_at DESC
    ")

    list(
      success = TRUE,
      restrictions = restrictions,
      count = nrow(restrictions)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# STATISTICS AND REPORTING
# ============================================================================

#' Get Restriction Statistics
#'
#' Returns comprehensive statistics for restriction requests.
#'
#' @return List with statistics
#' @export
#'
#' @examples
#' \dontrun{
#' stats <- get_restriction_statistics()
#' }
get_restriction_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'RECEIVED' THEN 1 ELSE 0 END) as received,
        SUM(CASE WHEN status = 'UNDER_REVIEW' THEN 1 ELSE 0 END) as under_review,
        SUM(CASE WHEN status = 'APPROVED' THEN 1 ELSE 0 END) as approved,
        SUM(CASE WHEN status = 'ACTIVE' THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN status = 'LIFTED' THEN 1 ELSE 0 END) as lifted,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status = 'LEGAL_HOLD' THEN 1 ELSE 0 END) as on_hold
      FROM restriction_requests
    ")

    item_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 'APPROVED' THEN 1 ELSE 0 END) as approved,
        SUM(CASE WHEN status = 'ACTIVE' THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN status = 'LIFTED' THEN 1 ELSE 0 END) as lifted,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status = 'ON_HOLD' THEN 1 ELSE 0 END) as on_hold
      FROM restriction_items
    ")

    third_party_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(notification_required) as requiring_notification,
        SUM(notification_sent) as notified,
        SUM(restriction_confirmed) as confirmed
      FROM restriction_third_parties
    ")

    attempt_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(was_blocked) as blocked,
        SUM(CASE WHEN was_blocked = 0 THEN 1 ELSE 0 END) as allowed
      FROM processing_attempts
    ")

    grounds_stats <- DBI::dbGetQuery(con, "
      SELECT restriction_grounds, COUNT(*) as count
      FROM restriction_requests
      GROUP BY restriction_grounds
      ORDER BY count DESC
    ")

    list(
      success = TRUE,
      requests = as.list(request_stats),
      items = as.list(item_stats),
      third_party = as.list(third_party_stats),
      processing_attempts = as.list(attempt_stats),
      by_grounds = grounds_stats
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Generate Restriction Report
#'
#' Generates a compliance report for restriction requests.
#'
#' @param output_file Output file path
#' @param format Report format: "txt" or "json"
#' @param organization Organization name
#' @param prepared_by Name of person preparing report
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' generate_restriction_report(
#'   output_file = "restriction_report.txt",
#'   format = "txt",
#'   organization = "Healthcare Org",
#'   prepared_by = "DPO"
#' )
#' }
generate_restriction_report <- function(output_file,
                                         format = "txt",
                                         organization = "Organization",
                                         prepared_by = "DPO") {
  tryCatch({
    stats <- get_restriction_statistics()
    if (!stats$success) {
      return(list(success = FALSE, error = "Failed to get statistics"))
    }

    if (format == "json") {
      report_data <- list(
        report_type = "GDPR Article 18 Right to Restrict Processing Report",
        organization = organization,
        prepared_by = prepared_by,
        generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        statistics = stats
      )
      writeLines(
        jsonlite::toJSON(report_data, pretty = TRUE, auto_unbox = TRUE),
        output_file
      )
    } else {
      lines <- c(
        "===============================================================================",
        "       GDPR ARTICLE 18 - RIGHT TO RESTRICT PROCESSING REPORT",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Prepared by:", prepared_by),
        paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        "",
        "-------------------------------------------------------------------------------",
        "REQUEST SUMMARY",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Requests:", stats$requests$total),
        paste("  - Received:", stats$requests$received),
        paste("  - Under Review:", stats$requests$under_review),
        paste("  - Approved:", stats$requests$approved),
        paste("  - Active:", stats$requests$active),
        paste("  - Lifted:", stats$requests$lifted),
        paste("  - Rejected:", stats$requests$rejected),
        paste("  - On Legal Hold:", stats$requests$on_hold),
        "",
        "-------------------------------------------------------------------------------",
        "RESTRICTION ITEMS",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Items:", stats$items$total),
        paste("  - Pending:", stats$items$pending),
        paste("  - Approved:", stats$items$approved),
        paste("  - Active:", stats$items$active),
        paste("  - Lifted:", stats$items$lifted),
        paste("  - Rejected:", stats$items$rejected),
        paste("  - On Hold:", stats$items$on_hold),
        "",
        "-------------------------------------------------------------------------------",
        "PROCESSING ATTEMPTS (AUDIT)",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Attempts:", stats$processing_attempts$total),
        paste("  - Blocked:", stats$processing_attempts$blocked),
        paste("  - Allowed (override):", stats$processing_attempts$allowed),
        "",
        "-------------------------------------------------------------------------------",
        "THIRD-PARTY NOTIFICATIONS (GDPR Article 19)",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Recipients:", stats$third_party$total),
        paste("  - Requiring Notification:", stats$third_party$requiring_notification),
        paste("  - Notified:", stats$third_party$notified),
        paste("  - Confirmed:", stats$third_party$confirmed),
        "",
        "-------------------------------------------------------------------------------",
        "REQUESTS BY GROUNDS (Article 18(1))",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(stats$by_grounds) > 0) {
        for (i in seq_len(nrow(stats$by_grounds))) {
          lines <- c(lines, paste(" ",
            stats$by_grounds$restriction_grounds[i], ":",
            stats$by_grounds$count[i]))
        }
      } else {
        lines <- c(lines, "  No requests recorded")
      }

      lines <- c(lines,
        "",
        "-------------------------------------------------------------------------------",
        "COMPLIANCE NOTES",
        "-------------------------------------------------------------------------------",
        "",
        "GDPR Article 18 - Right to Restriction of Processing:",
        "  - Data subject can request restriction when accuracy contested",
        "  - Restriction applies when processing unlawful but erasure opposed",
        "  - Restriction when controller no longer needs data for legal claims",
        "  - Restriction pending verification of objection grounds",
        "",
        "GDPR Article 18(2) - Allowed Processing During Restriction:",
        "  - Storage is always allowed",
        "  - Processing with data subject consent",
        "  - Processing for legal claims",
        "  - Processing to protect rights of others",
        "  - Processing for important public interest",
        "",
        "GDPR Article 18(3) - Lifting Notification:",
        "  - Controller must inform data subject before lifting restriction",
        "",
        "===============================================================================",
        ""
      )

      writeLines(lines, output_file)
    }

    list(
      success = TRUE,
      output_file = output_file,
      message = paste("Report generated:", output_file)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
