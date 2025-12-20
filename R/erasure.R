#' Right to Erasure System with Legal Hold
#'
#' GDPR Article 17 compliant system for managing data subject erasure
#' requests, including legal hold management for regulatory compliance.

# =============================================================================
# Helper Functions
# =============================================================================

#' Safe Scalar Conversion for Erasure
#'
#' @param x Value to convert
#' @param default Default value if NULL
#' @return Character scalar
#' @keywords internal
safe_scalar_erasure <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' Safe Integer Scalar Conversion for Erasure
#'
#' @param x Value to convert
#' @param default Default value if NULL
#' @return Integer scalar or NA
#' @keywords internal
safe_int_erasure <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

# =============================================================================
# Database Schema
# =============================================================================

#' Initialize Erasure System
#'
#' Creates database tables for erasure request and legal hold management.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with initialization results
#'
#' @export
init_erasure <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS erasure_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT NOT NULL UNIQUE,
        dsar_request_id INTEGER REFERENCES dsar_requests(request_id),
        subject_id TEXT,
        subject_email TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        erasure_grounds TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'RECEIVED' CHECK(status IN
          ('RECEIVED', 'UNDER_REVIEW', 'LEGAL_HOLD', 'APPROVED',
           'PARTIALLY_APPROVED', 'REJECTED', 'COMPLETED', 'CLOSED')),
        received_date DATE NOT NULL,
        due_date DATE NOT NULL,
        completed_date DATE,
        requested_by TEXT NOT NULL,
        reviewed_by TEXT,
        reviewed_at TIMESTAMP,
        review_notes TEXT,
        rejection_reason TEXT,
        legal_hold_id INTEGER REFERENCES legal_holds(hold_id),
        request_hash TEXT NOT NULL,
        previous_hash TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS erasure_items (
        item_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES erasure_requests(request_id),
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        data_category TEXT NOT NULL,
        erasure_method TEXT NOT NULL CHECK(erasure_method IN
          ('DELETE', 'ANONYMIZE', 'PSEUDONYMIZE')),
        status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN
          ('PENDING', 'APPROVED', 'REJECTED', 'ON_HOLD', 'EXECUTED')),
        rejection_reason TEXT,
        hold_reason TEXT,
        executed_at TIMESTAMP,
        executed_by TEXT,
        verification_hash TEXT,
        item_hash TEXT NOT NULL
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS legal_holds (
        hold_id INTEGER PRIMARY KEY AUTOINCREMENT,
        hold_number TEXT NOT NULL UNIQUE,
        hold_type TEXT NOT NULL CHECK(hold_type IN
          ('REGULATORY', 'LITIGATION', 'AUDIT', 'INVESTIGATION', 'OTHER')),
        hold_reason TEXT NOT NULL,
        legal_basis TEXT NOT NULL,
        affected_subjects TEXT,
        affected_data_categories TEXT,
        start_date DATE NOT NULL,
        end_date DATE,
        is_active INTEGER DEFAULT 1,
        created_by TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        released_by TEXT,
        released_at TIMESTAMP,
        release_reason TEXT,
        hold_hash TEXT NOT NULL,
        previous_hash TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS erasure_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES erasure_requests(request_id),
        item_id INTEGER REFERENCES erasure_items(item_id),
        hold_id INTEGER REFERENCES legal_holds(hold_id),
        action TEXT NOT NULL,
        action_details TEXT,
        performed_by TEXT NOT NULL,
        performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        history_hash TEXT NOT NULL,
        previous_history_hash TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS erasure_third_parties (
        recipient_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES erasure_requests(request_id),
        recipient_name TEXT NOT NULL,
        recipient_type TEXT NOT NULL CHECK(recipient_type IN
          ('PROCESSOR', 'CONTROLLER', 'THIRD_PARTY', 'REGULATOR')),
        contact_email TEXT,
        contact_name TEXT,
        data_shared TEXT,
        notification_required INTEGER DEFAULT 1,
        notification_sent INTEGER DEFAULT 0,
        notification_sent_date DATE,
        notification_sent_by TEXT,
        erasure_confirmed INTEGER DEFAULT 0,
        erasure_confirmed_date DATE,
        notes TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_erasure_status
      ON erasure_requests(status)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_erasure_subject
      ON erasure_requests(subject_email)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_legal_holds_active
      ON legal_holds(is_active)
    ")

    list(
      success = TRUE,
      tables_created = 5,
      message = "Erasure system initialized successfully"
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

#' Get Erasure Grounds
#'
#' Returns valid grounds for erasure under GDPR Article 17.
#'
#' @return Named list of erasure grounds
#'
#' @export
get_erasure_grounds <- function() {
  list(
    NO_LONGER_NECESSARY = "Data no longer necessary for original purpose (Art. 17(1)(a))",
    CONSENT_WITHDRAWN = "Consent withdrawn and no other legal basis (Art. 17(1)(b))",
    OBJECTION = "Data subject objects and no overriding legitimate grounds (Art. 17(1)(c))",
    UNLAWFUL_PROCESSING = "Data processed unlawfully (Art. 17(1)(d))",
    LEGAL_OBLIGATION = "Erasure required for legal compliance (Art. 17(1)(e))",
    CHILD_DATA = "Data collected from child for information society services (Art. 17(1)(f))"
  )
}


#' Get Erasure Statuses
#'
#' Returns valid erasure request statuses.
#'
#' @return Named list of status values
#'
#' @export
get_erasure_statuses <- function() {
  list(
    RECEIVED = "Request received and logged",
    UNDER_REVIEW = "Request under review",
    LEGAL_HOLD = "Request blocked by legal hold",
    APPROVED = "All items approved for erasure",
    PARTIALLY_APPROVED = "Some items approved, others blocked",
    REJECTED = "Request rejected",
    COMPLETED = "All approved erasures executed",
    CLOSED = "Request closed"
  )
}


#' Get Legal Hold Types
#'
#' Returns valid legal hold types.
#'
#' @return Named list of hold types
#'
#' @export
get_legal_hold_types <- function() {
  list(
    REGULATORY = "Regulatory retention requirement (FDA, SEC, etc.)",
    LITIGATION = "Litigation hold for legal proceedings",
    AUDIT = "Audit retention requirement",
    INVESTIGATION = "Investigation hold",
    OTHER = "Other legal requirement"
  )
}


#' Get Erasure Methods
#'
#' Returns valid erasure methods.
#'
#' @return Named list of erasure methods
#'
#' @export
get_erasure_methods <- function() {
  list(
    DELETE = "Complete deletion of data",
    ANONYMIZE = "Irreversible anonymization",
    PSEUDONYMIZE = "Pseudonymization with key deletion"
  )
}


#' Get Erasure Exceptions
#'
#' Returns grounds for refusing erasure under GDPR Article 17(3).
#'
#' @return Named list of exception grounds
#'
#' @export
get_erasure_exceptions <- function() {
  list(
    FREE_EXPRESSION = "Freedom of expression and information (Art. 17(3)(a))",
    LEGAL_OBLIGATION = "Compliance with legal obligation (Art. 17(3)(b))",
    PUBLIC_HEALTH = "Public health purposes (Art. 17(3)(c))",
    ARCHIVING = "Archiving in public interest, research, statistics (Art. 17(3)(d))",
    LEGAL_CLAIMS = "Establishment, exercise or defense of legal claims (Art. 17(3)(e))"
  )
}


# =============================================================================
# Legal Hold Management
# =============================================================================

#' Generate Legal Hold Number
#'
#' @return Character: Hold number
#' @keywords internal
generate_hold_number <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(0:9, 4, replace = TRUE), collapse = "")
  paste0("HOLD-", timestamp, "-", random)
}


#' Create Legal Hold
#'
#' Creates a legal hold that prevents data erasure.
#'
#' @param hold_type Character: REGULATORY, LITIGATION, AUDIT, INVESTIGATION, OTHER
#' @param hold_reason Character: Reason for hold
#' @param legal_basis Character: Legal basis for hold
#' @param created_by Character: User creating hold
#' @param start_date Date: Start date (default: today)
#' @param end_date Date: End date (optional)
#' @param affected_subjects Character: Affected subject IDs (optional)
#' @param affected_data_categories Character: Affected categories (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
create_legal_hold <- function(hold_type,
                               hold_reason,
                               legal_basis,
                               created_by,
                               start_date = Sys.Date(),
                               end_date = NULL,
                               affected_subjects = NULL,
                               affected_data_categories = NULL,
                               db_path = NULL) {

  valid_types <- names(get_legal_hold_types())
  if (!hold_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid hold type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  if (nchar(hold_reason) < 20) {
    return(list(
      success = FALSE,
      error = "Hold reason must be at least 20 characters"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    hold_number <- generate_hold_number()

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT hold_hash FROM legal_holds
      ORDER BY hold_id DESC LIMIT 1
    ")
    previous_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$hold_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      hold_number, hold_type, hold_reason, legal_basis,
      created_by, timestamp, previous_hash,
      sep = "|"
    )
    hold_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO legal_holds (
        hold_number, hold_type, hold_reason, legal_basis,
        affected_subjects, affected_data_categories,
        start_date, end_date, is_active, created_by, hold_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
    ", list(
      hold_number,
      safe_scalar_erasure(hold_type),
      safe_scalar_erasure(hold_reason),
      safe_scalar_erasure(legal_basis),
      safe_scalar_erasure(affected_subjects),
      safe_scalar_erasure(affected_data_categories),
      as.character(start_date),
      if (is.null(end_date)) NA_character_ else as.character(end_date),
      safe_scalar_erasure(created_by),
      hold_hash,
      previous_hash
    ))

    hold_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    list(
      success = TRUE,
      hold_id = hold_id,
      hold_number = hold_number,
      message = "Legal hold created successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Release Legal Hold
#'
#' Releases a legal hold, allowing erasure to proceed.
#'
#' @param hold_id Integer: Hold ID
#' @param release_reason Character: Reason for release
#' @param released_by Character: User releasing hold
#' @param db_path Character: Database path (optional)
#'
#' @return List with release result
#'
#' @export
release_legal_hold <- function(hold_id,
                                release_reason,
                                released_by,
                                db_path = NULL) {

  if (nchar(release_reason) < 20) {
    return(list(
      success = FALSE,
      error = "Release reason must be at least 20 characters"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    hold <- DBI::dbGetQuery(conn, "
      SELECT * FROM legal_holds WHERE hold_id = ?
    ", list(hold_id))

    if (nrow(hold) == 0) {
      return(list(success = FALSE, error = "Hold not found"))
    }

    if (hold$is_active == 0) {
      return(list(success = FALSE, error = "Hold is already released"))
    }

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE legal_holds
      SET is_active = 0,
          released_by = ?,
          released_at = ?,
          release_reason = ?
      WHERE hold_id = ?
    ", list(
      safe_scalar_erasure(released_by),
      timestamp,
      safe_scalar_erasure(release_reason),
      hold_id
    ))

    list(
      success = TRUE,
      hold_id = hold_id,
      message = "Legal hold released successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Check Legal Hold
#'
#' Checks if a subject or data category is under legal hold.
#'
#' @param subject_id Character: Subject ID (optional)
#' @param data_category Character: Data category (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with hold status
#'
#' @export
check_legal_hold <- function(subject_id = NULL,
                              data_category = NULL,
                              db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    active_holds <- DBI::dbGetQuery(conn, "
      SELECT * FROM legal_holds WHERE is_active = 1
    ")

    if (nrow(active_holds) == 0) {
      return(list(
        success = TRUE,
        is_held = FALSE,
        holds = list(),
        message = "No active legal holds"
      ))
    }

    matching_holds <- list()

    for (i in seq_len(nrow(active_holds))) {
      hold <- active_holds[i, ]
      matches <- FALSE

      if (!is.null(subject_id) && !is.na(hold$affected_subjects)) {
        subjects <- strsplit(hold$affected_subjects, ";")[[1]]
        subjects <- trimws(subjects)
        if (subject_id %in% subjects || "ALL" %in% subjects) {
          matches <- TRUE
        }
      }

      if (!is.null(data_category) && !is.na(hold$affected_data_categories)) {
        categories <- strsplit(hold$affected_data_categories, ";")[[1]]
        categories <- trimws(categories)
        if (data_category %in% categories || "ALL" %in% categories) {
          matches <- TRUE
        }
      }

      if (is.na(hold$affected_subjects) && is.na(hold$affected_data_categories)) {
        matches <- TRUE
      }

      if (matches) {
        matching_holds <- c(matching_holds, list(hold))
      }
    }

    list(
      success = TRUE,
      is_held = length(matching_holds) > 0,
      holds = matching_holds,
      message = if (length(matching_holds) > 0) {
        paste(length(matching_holds), "active hold(s) apply")
      } else {
        "No matching holds"
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Get Active Legal Holds
#'
#' Retrieves all active legal holds.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with active holds
#'
#' @export
get_active_legal_holds <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM legal_holds
      WHERE is_active = 1
      ORDER BY start_date DESC
    ")

  }, error = function(e) data.frame())
}


# =============================================================================
# Erasure Request Management
# =============================================================================

#' Generate Erasure Request Number
#'
#' @return Character: Request number
#' @keywords internal
generate_erasure_number <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(0:9, 4, replace = TRUE), collapse = "")
  paste0("ERASE-", timestamp, "-", random)
}


#' Create Erasure Request
#'
#' Creates a new erasure request under GDPR Article 17.
#'
#' @param subject_email Character: Data subject's email
#' @param subject_name Character: Data subject's name
#' @param erasure_grounds Character: Legal grounds for erasure
#' @param requested_by Character: User creating request
#' @param subject_id Character: Subject ID if known (optional)
#' @param dsar_request_id Integer: Link to DSAR request (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
create_erasure_request <- function(subject_email,
                                    subject_name,
                                    erasure_grounds,
                                    requested_by,
                                    subject_id = NULL,
                                    dsar_request_id = NULL,
                                    db_path = NULL) {

  valid_grounds <- names(get_erasure_grounds())
  if (!erasure_grounds %in% valid_grounds) {
    return(list(
      success = FALSE,
      error = paste("Invalid erasure grounds. Must be one of:",
                    paste(valid_grounds, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    hold_check <- check_legal_hold(
      subject_id = subject_id,
      db_path = db_path
    )

    request_number <- generate_erasure_number()
    received_date <- Sys.Date()
    due_date <- received_date + 30

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT request_hash FROM erasure_requests
      ORDER BY request_id DESC LIMIT 1
    ")
    previous_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$request_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      request_number, subject_email, subject_name, erasure_grounds,
      requested_by, timestamp, previous_hash,
      sep = "|"
    )
    request_hash <- digest::digest(hash_content, algo = "sha256")

    initial_status <- if (hold_check$is_held) "LEGAL_HOLD" else "RECEIVED"

    hold_id <- if (hold_check$is_held && length(hold_check$holds) > 0) {
      hold_check$holds[[1]]$hold_id
    } else {
      NA_integer_
    }

    DBI::dbExecute(conn, "
      INSERT INTO erasure_requests (
        request_number, dsar_request_id, subject_id, subject_email,
        subject_name, erasure_grounds, status, received_date, due_date,
        requested_by, legal_hold_id, request_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      request_number,
      safe_int_erasure(dsar_request_id),
      safe_scalar_erasure(subject_id),
      safe_scalar_erasure(subject_email),
      safe_scalar_erasure(subject_name),
      safe_scalar_erasure(erasure_grounds),
      initial_status,
      as.character(received_date),
      as.character(due_date),
      safe_scalar_erasure(requested_by),
      safe_int_erasure(hold_id),
      request_hash,
      previous_hash
    ))

    request_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_erasure_action(
      request_id = request_id,
      action = "REQUEST_CREATED",
      action_details = paste("Erasure request created:", erasure_grounds,
                             if (hold_check$is_held) "(LEGAL HOLD ACTIVE)" else ""),
      performed_by = requested_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      request_id = request_id,
      request_number = request_number,
      status = initial_status,
      due_date = as.character(due_date),
      is_held = hold_check$is_held,
      message = if (hold_check$is_held) {
        "Erasure request created but blocked by legal hold"
      } else {
        "Erasure request created successfully"
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Log Erasure Action
#'
#' Logs an action in the erasure history.
#'
#' @param request_id Integer: Request ID
#' @param action Character: Action performed
#' @param action_details Character: Action details
#' @param performed_by Character: User performing action
#' @param item_id Integer: Item ID if applicable (optional)
#' @param hold_id Integer: Hold ID if applicable (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with logging result
#'
#' @keywords internal
log_erasure_action <- function(request_id,
                                action,
                                action_details,
                                performed_by,
                                item_id = NULL,
                                hold_id = NULL,
                                db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT history_hash FROM erasure_history
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
      INSERT INTO erasure_history (
        request_id, item_id, hold_id, action, action_details,
        performed_by, history_hash, previous_history_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      safe_int_erasure(item_id),
      safe_int_erasure(hold_id),
      safe_scalar_erasure(action),
      safe_scalar_erasure(action_details),
      safe_scalar_erasure(performed_by),
      history_hash,
      previous_history_hash
    ))

    list(success = TRUE)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Erasure Items
# =============================================================================

#' Add Erasure Item
#'
#' Adds an item to be erased in a request.
#'
#' @param request_id Integer: Request ID
#' @param table_name Character: Table containing data
#' @param record_id Character: Record identifier
#' @param data_category Character: Category of data
#' @param erasure_method Character: DELETE, ANONYMIZE, PSEUDONYMIZE
#' @param added_by Character: User adding item
#' @param db_path Character: Database path (optional)
#'
#' @return List with addition result
#'
#' @export
add_erasure_item <- function(request_id,
                              table_name,
                              record_id,
                              data_category,
                              erasure_method,
                              added_by,
                              db_path = NULL) {

  valid_methods <- names(get_erasure_methods())
  if (!erasure_method %in% valid_methods) {
    return(list(
      success = FALSE,
      error = paste("Invalid erasure method. Must be one of:",
                    paste(valid_methods, collapse = ", "))
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    hold_check <- check_legal_hold(
      data_category = data_category,
      db_path = db_path
    )

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      request_id, table_name, record_id, data_category,
      erasure_method, timestamp,
      sep = "|"
    )
    item_hash <- digest::digest(hash_content, algo = "sha256")

    initial_status <- if (hold_check$is_held) "ON_HOLD" else "PENDING"
    hold_reason <- if (hold_check$is_held && length(hold_check$holds) > 0) {
      hold_check$holds[[1]]$hold_reason
    } else {
      NA_character_
    }

    DBI::dbExecute(conn, "
      INSERT INTO erasure_items (
        request_id, table_name, record_id, data_category,
        erasure_method, status, hold_reason, item_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      request_id,
      safe_scalar_erasure(table_name),
      safe_scalar_erasure(record_id),
      safe_scalar_erasure(data_category),
      safe_scalar_erasure(erasure_method),
      initial_status,
      safe_scalar_erasure(hold_reason),
      item_hash
    ))

    item_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_erasure_action(
      request_id = request_id,
      item_id = item_id,
      action = "ITEM_ADDED",
      action_details = paste("Erasure item added:", table_name, ".", data_category,
                             if (hold_check$is_held) "(ON HOLD)" else ""),
      performed_by = added_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      item_id = item_id,
      status = initial_status,
      is_held = hold_check$is_held,
      message = if (hold_check$is_held) {
        "Item added but on legal hold"
      } else {
        "Erasure item added successfully"
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Review Erasure Item
#'
#' Reviews and approves or rejects an erasure item.
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
review_erasure_item <- function(item_id,
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
      SELECT request_id, status, data_category FROM erasure_items WHERE item_id = ?
    ", list(item_id))

    if (nrow(item) == 0) {
      return(list(success = FALSE, error = "Item not found"))
    }

    if (item$status == "ON_HOLD") {
      return(list(success = FALSE, error = "Item is on legal hold and cannot be reviewed"))
    }

    DBI::dbExecute(conn, "
      UPDATE erasure_items
      SET status = ?,
          rejection_reason = ?
      WHERE item_id = ?
    ", list(
      decision,
      safe_scalar_erasure(rejection_reason),
      item_id
    ))

    log_erasure_action(
      request_id = item$request_id,
      item_id = item_id,
      action = paste("ITEM", decision),
      action_details = paste("Item", item$data_category, decision),
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


#' Execute Erasure Item
#'
#' Executes an approved erasure.
#'
#' @param item_id Integer: Item ID
#' @param executed_by Character: User executing erasure
#' @param db_path Character: Database path (optional)
#'
#' @return List with execution result
#'
#' @export
execute_erasure_item <- function(item_id,
                                  executed_by,
                                  db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    item <- DBI::dbGetQuery(conn, "
      SELECT * FROM erasure_items WHERE item_id = ?
    ", list(item_id))

    if (nrow(item) == 0) {
      return(list(success = FALSE, error = "Item not found"))
    }

    if (item$status != "APPROVED") {
      return(list(success = FALSE, error = "Item must be approved before execution"))
    }

    timestamp <- as.character(Sys.time())
    verification_content <- paste(
      item_id, item$table_name, item$record_id, item$erasure_method,
      executed_by, timestamp,
      sep = "|"
    )
    verification_hash <- digest::digest(verification_content, algo = "sha256")

    DBI::dbExecute(conn, "
      UPDATE erasure_items
      SET status = 'EXECUTED',
          executed_at = ?,
          executed_by = ?,
          verification_hash = ?
      WHERE item_id = ?
    ", list(
      timestamp,
      safe_scalar_erasure(executed_by),
      verification_hash,
      item_id
    ))

    log_erasure_action(
      request_id = item$request_id,
      item_id = item_id,
      action = "ITEM_EXECUTED",
      action_details = paste("Erasure executed:", item$erasure_method, "on",
                             item$table_name, ".", item$data_category),
      performed_by = executed_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      item_id = item_id,
      table_name = item$table_name,
      record_id = item$record_id,
      erasure_method = item$erasure_method,
      verification_hash = verification_hash,
      message = "Erasure executed successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Third-Party Notifications
# =============================================================================

#' Add Erasure Third Party
#'
#' Adds a third party who received the data and needs erasure notification.
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
add_erasure_third_party <- function(request_id,
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
      INSERT INTO erasure_third_parties (
        request_id, recipient_name, recipient_type, contact_email,
        contact_name, data_shared, notification_required
      ) VALUES (?, ?, ?, ?, ?, ?, 1)
    ", list(
      request_id,
      safe_scalar_erasure(recipient_name),
      safe_scalar_erasure(recipient_type),
      safe_scalar_erasure(contact_email),
      safe_scalar_erasure(contact_name),
      safe_scalar_erasure(data_shared)
    ))

    recipient_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    log_erasure_action(
      request_id = request_id,
      action = "THIRD_PARTY_ADDED",
      action_details = paste("Third party added:", recipient_name),
      performed_by = added_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      recipient_id = recipient_id,
      message = "Third party added successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Notify Erasure Third Party
#'
#' Records that erasure notification was sent to a third party.
#'
#' @param recipient_id Integer: Recipient ID
#' @param sent_by Character: User sending notification
#' @param db_path Character: Database path (optional)
#'
#' @return List with notification result
#'
#' @export
notify_erasure_third_party <- function(recipient_id,
                                        sent_by,
                                        db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    recipient <- DBI::dbGetQuery(conn, "
      SELECT request_id, recipient_name
      FROM erasure_third_parties
      WHERE recipient_id = ?
    ", list(recipient_id))

    if (nrow(recipient) == 0) {
      return(list(success = FALSE, error = "Recipient not found"))
    }

    DBI::dbExecute(conn, "
      UPDATE erasure_third_parties
      SET notification_sent = 1,
          notification_sent_date = ?,
          notification_sent_by = ?
      WHERE recipient_id = ?
    ", list(
      as.character(Sys.Date()),
      safe_scalar_erasure(sent_by),
      recipient_id
    ))

    log_erasure_action(
      request_id = recipient$request_id,
      action = "THIRD_PARTY_NOTIFIED",
      action_details = paste("Erasure notification sent to:", recipient$recipient_name),
      performed_by = sent_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      recipient_id = recipient_id,
      message = "Third party notified successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Confirm Erasure Third Party
#'
#' Records that a third party confirmed erasure.
#'
#' @param recipient_id Integer: Recipient ID
#' @param confirmed_by Character: User recording confirmation
#' @param db_path Character: Database path (optional)
#'
#' @return List with confirmation result
#'
#' @export
confirm_erasure_third_party <- function(recipient_id,
                                         confirmed_by,
                                         db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      UPDATE erasure_third_parties
      SET erasure_confirmed = 1,
          erasure_confirmed_date = ?
      WHERE recipient_id = ?
    ", list(
      as.character(Sys.Date()),
      recipient_id
    ))

    list(
      success = TRUE,
      message = "Erasure confirmation recorded"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Request Completion
# =============================================================================

#' Complete Erasure Request
#'
#' Completes an erasure request after all items are processed.
#'
#' @param request_id Integer: Request ID
#' @param completed_by Character: User completing request
#' @param db_path Character: Database path (optional)
#'
#' @return List with completion result
#'
#' @export
complete_erasure_request <- function(request_id,
                                      completed_by,
                                      db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    items <- DBI::dbGetQuery(conn, "
      SELECT status, COUNT(*) as count
      FROM erasure_items
      WHERE request_id = ?
      GROUP BY status
    ", list(request_id))

    pending <- sum(items$count[items$status == "PENDING"])
    approved_pending <- sum(items$count[items$status == "APPROVED"])
    on_hold <- sum(items$count[items$status == "ON_HOLD"])

    if (pending > 0) {
      return(list(
        success = FALSE,
        error = paste(pending, "items still pending review")
      ))
    }

    if (approved_pending > 0) {
      return(list(
        success = FALSE,
        error = paste(approved_pending, "approved items not yet executed")
      ))
    }

    pending_notifications <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as count
      FROM erasure_third_parties
      WHERE request_id = ? AND notification_required = 1 AND notification_sent = 0
    ", list(request_id))

    if (pending_notifications$count > 0) {
      return(list(
        success = FALSE,
        error = paste(pending_notifications$count,
                      "third party notifications pending")
      ))
    }

    executed <- sum(items$count[items$status == "EXECUTED"])
    rejected <- sum(items$count[items$status == "REJECTED"])

    final_status <- if (on_hold > 0 && executed == 0) {
      "LEGAL_HOLD"
    } else if (on_hold > 0 || rejected > 0) {
      "PARTIALLY_APPROVED"
    } else {
      "COMPLETED"
    }

    timestamp <- as.character(Sys.time())
    DBI::dbExecute(conn, "
      UPDATE erasure_requests
      SET status = ?,
          completed_date = ?,
          reviewed_by = ?,
          reviewed_at = ?
      WHERE request_id = ?
    ", list(
      final_status,
      as.character(Sys.Date()),
      safe_scalar_erasure(completed_by),
      timestamp,
      request_id
    ))

    log_erasure_action(
      request_id = request_id,
      action = "REQUEST_COMPLETED",
      action_details = paste("Request completed. Executed:", executed,
                             "Rejected:", rejected, "On hold:", on_hold),
      performed_by = completed_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      status = final_status,
      items_executed = executed,
      items_rejected = rejected,
      items_on_hold = on_hold,
      message = "Erasure request completed"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Reject Erasure Request
#'
#' Rejects an entire erasure request.
#'
#' @param request_id Integer: Request ID
#' @param rejection_reason Character: Reason for rejection (min 20 chars)
#' @param rejected_by Character: User rejecting request
#' @param exception_ground Character: GDPR Article 17(3) exception (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with rejection result
#'
#' @export
reject_erasure_request <- function(request_id,
                                    rejection_reason,
                                    rejected_by,
                                    exception_ground = NULL,
                                    db_path = NULL) {

  if (nchar(rejection_reason) < 20) {
    return(list(
      success = FALSE,
      error = "Rejection reason must be at least 20 characters"
    ))
  }

  if (!is.null(exception_ground)) {
    valid_exceptions <- names(get_erasure_exceptions())
    if (!exception_ground %in% valid_exceptions) {
      return(list(
        success = FALSE,
        error = paste("Invalid exception ground. Must be one of:",
                      paste(valid_exceptions, collapse = ", "))
      ))
    }
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    full_reason <- if (!is.null(exception_ground)) {
      paste(rejection_reason, "[Exception:", exception_ground, "]")
    } else {
      rejection_reason
    }

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE erasure_requests
      SET status = 'REJECTED',
          rejection_reason = ?,
          reviewed_by = ?,
          reviewed_at = ?,
          completed_date = ?
      WHERE request_id = ?
    ", list(
      safe_scalar_erasure(full_reason),
      safe_scalar_erasure(rejected_by),
      timestamp,
      as.character(Sys.Date()),
      request_id
    ))

    log_erasure_action(
      request_id = request_id,
      action = "REQUEST_REJECTED",
      action_details = paste("Request rejected:", full_reason),
      performed_by = rejected_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      message = "Erasure request rejected"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


# =============================================================================
# Retrieval Functions
# =============================================================================

#' Get Erasure Request
#'
#' Retrieves an erasure request.
#'
#' @param request_id Integer: Request ID (optional)
#' @param request_number Character: Request number (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with request details
#'
#' @export
get_erasure_request <- function(request_id = NULL,
                                 request_number = NULL,
                                 db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (!is.null(request_id)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM erasure_requests WHERE request_id = ?
      ", list(request_id))
    } else if (!is.null(request_number)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM erasure_requests WHERE request_number = ?
      ", list(safe_scalar_erasure(request_number)))
    } else {
      data.frame()
    }

  }, error = function(e) data.frame())
}


#' Get Erasure Items
#'
#' Retrieves items for an erasure request.
#'
#' @param request_id Integer: Request ID
#' @param status Character: Filter by status (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with items
#'
#' @export
get_erasure_items <- function(request_id,
                               status = NULL,
                               db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (!is.null(status)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM erasure_items
        WHERE request_id = ? AND status = ?
        ORDER BY item_id
      ", list(request_id, safe_scalar_erasure(status)))
    } else {
      DBI::dbGetQuery(conn, "
        SELECT * FROM erasure_items
        WHERE request_id = ?
        ORDER BY item_id
      ", list(request_id))
    }

  }, error = function(e) data.frame())
}


#' Get Erasure Third Parties
#'
#' Retrieves third-party recipients for an erasure request.
#'
#' @param request_id Integer: Request ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with recipients
#'
#' @export
get_erasure_third_parties <- function(request_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM erasure_third_parties
      WHERE request_id = ?
      ORDER BY recipient_id
    ", list(request_id))

  }, error = function(e) data.frame())
}


#' Get Erasure History
#'
#' Retrieves history for an erasure request.
#'
#' @param request_id Integer: Request ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with history entries
#'
#' @export
get_erasure_history <- function(request_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM erasure_history
      WHERE request_id = ?
      ORDER BY performed_at ASC
    ", list(request_id))

  }, error = function(e) data.frame())
}


#' Get Pending Erasure Requests
#'
#' Retrieves pending erasure requests.
#'
#' @param include_held Logical: Include requests on legal hold (default: FALSE)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with pending requests
#'
#' @export
get_pending_erasure_requests <- function(include_held = FALSE, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (include_held) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM erasure_requests
        WHERE status NOT IN ('COMPLETED', 'REJECTED', 'CLOSED')
        ORDER BY due_date ASC
      ")
    } else {
      DBI::dbGetQuery(conn, "
        SELECT * FROM erasure_requests
        WHERE status NOT IN ('COMPLETED', 'REJECTED', 'CLOSED', 'LEGAL_HOLD')
        ORDER BY due_date ASC
      ")
    }

  }, error = function(e) data.frame())
}


# =============================================================================
# Statistics and Reporting
# =============================================================================

#' Get Erasure Statistics
#'
#' Returns erasure and legal hold statistics.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with statistics
#'
#' @export
get_erasure_statistics <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    requests <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_requests,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status = 'LEGAL_HOLD' THEN 1 ELSE 0 END) as on_hold,
        SUM(CASE WHEN status NOT IN ('COMPLETED', 'REJECTED', 'CLOSED', 'LEGAL_HOLD') THEN 1 ELSE 0 END) as pending
      FROM erasure_requests
    ")

    items <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_items,
        SUM(CASE WHEN status = 'EXECUTED' THEN 1 ELSE 0 END) as executed,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status = 'ON_HOLD' THEN 1 ELSE 0 END) as on_hold,
        SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) as pending
      FROM erasure_items
    ")

    by_grounds <- DBI::dbGetQuery(conn, "
      SELECT erasure_grounds, COUNT(*) as count
      FROM erasure_requests
      GROUP BY erasure_grounds
    ")

    holds <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_holds,
        SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END) as active_holds
      FROM legal_holds
    ")

    third_parties <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_recipients,
        SUM(CASE WHEN notification_sent = 1 THEN 1 ELSE 0 END) as notified,
        SUM(CASE WHEN erasure_confirmed = 1 THEN 1 ELSE 0 END) as confirmed
      FROM erasure_third_parties
    ")

    list(
      success = TRUE,
      requests = list(
        total = requests$total_requests,
        completed = requests$completed,
        rejected = requests$rejected,
        on_hold = requests$on_hold,
        pending = requests$pending
      ),
      items = list(
        total = items$total_items,
        executed = items$executed,
        rejected = items$rejected,
        on_hold = items$on_hold,
        pending = items$pending
      ),
      by_grounds = by_grounds,
      legal_holds = list(
        total = holds$total_holds,
        active = holds$active_holds
      ),
      third_parties = list(
        total = third_parties$total_recipients,
        notified = third_parties$notified,
        confirmed = third_parties$confirmed
      )
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Generate Erasure Report
#'
#' Generates an erasure compliance report.
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
generate_erasure_report <- function(output_file,
                                     format = "txt",
                                     organization = "Organization",
                                     prepared_by = "DPO",
                                     db_path = NULL) {
  tryCatch({
    stats <- get_erasure_statistics(db_path = db_path)

    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    requests <- DBI::dbGetQuery(conn, "
      SELECT request_number, erasure_grounds, subject_name, status,
             received_date, due_date, completed_date
      FROM erasure_requests
      ORDER BY received_date DESC
      LIMIT 50
    ")

    active_holds <- get_active_legal_holds(db_path = db_path)

    if (format == "json") {
      report_data <- list(
        report_type = "Erasure Compliance Report",
        organization = organization,
        generated_at = as.character(Sys.time()),
        prepared_by = prepared_by,
        statistics = stats,
        active_legal_holds = active_holds,
        recent_requests = requests
      )

      jsonlite::write_json(report_data, output_file, pretty = TRUE, auto_unbox = TRUE)

    } else {
      lines <- c(
        "===============================================================================",
        "                       ERASURE COMPLIANCE REPORT",
        "                         (GDPR Article 17)",
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
        paste("On Legal Hold:", stats$requests$on_hold),
        paste("Pending:", stats$requests$pending),
        "",
        paste("Total Items:", stats$items$total),
        paste("Items Executed:", stats$items$executed),
        paste("Items Rejected:", stats$items$rejected),
        paste("Items On Hold:", stats$items$on_hold),
        "",
        paste("Active Legal Holds:", stats$legal_holds$active),
        paste("Third Parties Notified:", stats$third_parties$notified, "/",
              stats$third_parties$total),
        ""
      )

      if (nrow(stats$by_grounds) > 0) {
        lines <- c(lines, "By Erasure Grounds:")
        for (i in seq_len(nrow(stats$by_grounds))) {
          lines <- c(lines, sprintf("  %-25s %d",
                                    stats$by_grounds$erasure_grounds[i],
                                    stats$by_grounds$count[i]))
        }
        lines <- c(lines, "")
      }

      if (nrow(active_holds) > 0) {
        lines <- c(lines,
          "-------------------------------------------------------------------------------",
          "                          ACTIVE LEGAL HOLDS",
          "-------------------------------------------------------------------------------",
          ""
        )
        for (i in seq_len(nrow(active_holds))) {
          lines <- c(lines,
            paste("Hold:", active_holds$hold_number[i]),
            paste("  Type:", active_holds$hold_type[i]),
            paste("  Reason:", active_holds$hold_reason[i]),
            paste("  Start:", active_holds$start_date[i]),
            ""
          )
        }
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
