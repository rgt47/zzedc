#' Consent Management System
#'
#' GDPR Article 7 compliant consent management system.
#' Manages consent collection, storage, withdrawal, and audit trails.
#' Supports granular consent for multiple purposes and processing activities.
#'
#' @name consent
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' @keywords internal
safe_scalar_consent <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' @keywords internal
safe_int_consent <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

#' @keywords internal
generate_consent_id <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(c(0:9, LETTERS), 6, replace = TRUE), collapse = "")
  paste0("CONS-", timestamp, "-", random)
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize Consent Management Tables
#'
#' Creates the database tables required for GDPR Article 7
#' consent management compliance.
#'
#' @return List with success status and message
#' @export
init_consent <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS consent_purposes (
        purpose_id INTEGER PRIMARY KEY AUTOINCREMENT,
        purpose_code TEXT UNIQUE NOT NULL,
        purpose_name TEXT NOT NULL,
        purpose_description TEXT NOT NULL,
        legal_basis TEXT NOT NULL,
        data_categories TEXT,
        retention_period TEXT,
        is_active INTEGER DEFAULT 1,
        requires_explicit INTEGER DEFAULT 0,
        is_mandatory INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS consent_records (
        consent_id INTEGER PRIMARY KEY AUTOINCREMENT,
        consent_code TEXT UNIQUE NOT NULL,
        subject_id TEXT NOT NULL,
        subject_email TEXT NOT NULL,
        subject_name TEXT,
        purpose_id INTEGER NOT NULL,
        consent_given INTEGER DEFAULT 0,
        consent_date TEXT,
        consent_method TEXT,
        consent_version TEXT,
        consent_text TEXT,
        ip_address TEXT,
        user_agent TEXT,
        withdrawn INTEGER DEFAULT 0,
        withdrawn_date TEXT,
        withdrawn_by TEXT,
        withdrawn_reason TEXT,
        expires_at TEXT,
        is_active INTEGER DEFAULT 1,
        consent_hash TEXT NOT NULL,
        previous_hash TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (purpose_id) REFERENCES consent_purposes(purpose_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS consent_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        consent_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        action_details TEXT,
        previous_state INTEGER,
        new_state INTEGER,
        performed_by TEXT NOT NULL,
        performed_at TEXT DEFAULT (datetime('now')),
        history_hash TEXT NOT NULL,
        previous_history_hash TEXT,
        FOREIGN KEY (consent_id) REFERENCES consent_records(consent_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS consent_withdrawal_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT UNIQUE NOT NULL,
        subject_id TEXT NOT NULL,
        subject_email TEXT NOT NULL,
        withdrawal_scope TEXT NOT NULL,
        purpose_ids TEXT,
        withdrawal_reason TEXT,
        status TEXT DEFAULT 'RECEIVED',
        received_date TEXT NOT NULL,
        completed_date TEXT,
        requested_by TEXT NOT NULL,
        processed_by TEXT,
        request_hash TEXT NOT NULL,
        previous_hash TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS consent_preferences (
        preference_id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id TEXT NOT NULL,
        subject_email TEXT NOT NULL,
        preference_type TEXT NOT NULL,
        preference_value TEXT NOT NULL,
        updated_at TEXT DEFAULT (datetime('now')),
        updated_by TEXT
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_consent_records_subject
                         ON consent_records(subject_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_consent_records_email
                         ON consent_records(subject_email)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_consent_records_purpose
                         ON consent_records(purpose_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_consent_purposes_code
                         ON consent_purposes(purpose_code)")

    list(success = TRUE, message = "Consent management system initialized")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Consent Methods
#' @return Named character vector of consent methods
#' @export
get_consent_methods <- function() {
  c(
    CHECKBOX = "Online checkbox/tick box",
    SIGNATURE = "Physical or electronic signature",
    VERBAL = "Verbal consent (recorded)",
    WRITTEN = "Written consent form",
    DOUBLE_OPT_IN = "Double opt-in (email confirmation)",
    API = "API/programmatic consent"
  )
}

#' Get Consent Legal Bases
#' @return Named character vector of legal bases
#' @export
get_consent_legal_bases <- function() {
  c(
    CONSENT = "Article 6(1)(a) - Consent",
    EXPLICIT_CONSENT = "Article 9(2)(a) - Explicit consent for special categories"
  )
}

#' Get Withdrawal Scopes
#' @return Named character vector of withdrawal scopes
#' @export
get_withdrawal_scopes <- function() {
  c(
    ALL = "Withdraw all consents",
    SPECIFIC = "Withdraw specific purpose(s)",
    CATEGORY = "Withdraw by data category"
  )
}

#' Get Consent Statuses
#' @return Named character vector of consent statuses
#' @export
get_consent_statuses <- function() {
  c(
    PENDING = "Consent pending",
    GIVEN = "Consent given",
    WITHDRAWN = "Consent withdrawn",
    EXPIRED = "Consent expired",
    REFRESHED = "Consent refreshed"
  )
}

# ============================================================================
# PURPOSE MANAGEMENT
# ============================================================================

#' Create Consent Purpose
#'
#' Creates a new consent purpose for data processing.
#'
#' @param purpose_code Unique code for the purpose
#' @param purpose_name Human-readable name
#' @param purpose_description Detailed description
#' @param legal_basis Legal basis from get_consent_legal_bases()
#' @param created_by User creating the purpose
#' @param data_categories Optional data categories involved
#' @param retention_period Optional retention period
#' @param requires_explicit Whether explicit consent is required
#' @param is_mandatory Whether consent is mandatory for service
#'
#' @return List with success status and purpose details
#' @export
create_consent_purpose <- function(purpose_code,
                                    purpose_name,
                                    purpose_description,
                                    legal_basis,
                                    created_by,
                                    data_categories = NULL,
                                    retention_period = NULL,
                                    requires_explicit = FALSE,
                                    is_mandatory = FALSE) {
  tryCatch({
    if (missing(purpose_code) || is.null(purpose_code) || purpose_code == "") {
      return(list(success = FALSE, error = "purpose_code is required"))
    }
    if (missing(purpose_name) || is.null(purpose_name) || purpose_name == "") {
      return(list(success = FALSE, error = "purpose_name is required"))
    }
    if (missing(purpose_description) || is.null(purpose_description) ||
        nchar(purpose_description) < 20) {
      return(list(success = FALSE,
                  error = "purpose_description must be at least 20 characters"))
    }

    valid_bases <- names(get_consent_legal_bases())
    if (!legal_basis %in% valid_bases) {
      return(list(
        success = FALSE,
        error = paste("Invalid legal_basis. Must be one of:",
                     paste(valid_bases, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    existing <- DBI::dbGetQuery(con, "
      SELECT purpose_id FROM consent_purposes WHERE purpose_code = ?
    ", params = list(purpose_code))

    if (nrow(existing) > 0) {
      return(list(success = FALSE, error = "purpose_code already exists"))
    }

    DBI::dbExecute(con, "
      INSERT INTO consent_purposes (
        purpose_code, purpose_name, purpose_description, legal_basis,
        data_categories, retention_period, requires_explicit,
        is_mandatory, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      purpose_code,
      purpose_name,
      purpose_description,
      legal_basis,
      safe_scalar_consent(data_categories),
      safe_scalar_consent(retention_period),
      as.integer(requires_explicit),
      as.integer(is_mandatory),
      created_by
    ))

    purpose_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      purpose_id = purpose_id,
      purpose_code = purpose_code,
      message = "Consent purpose created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Consent Purposes
#'
#' Retrieves all active consent purposes.
#'
#' @param include_inactive Include inactive purposes
#'
#' @return List with success status and purposes
#' @export
get_consent_purposes <- function(include_inactive = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (include_inactive) {
      purposes <- DBI::dbGetQuery(con, "SELECT * FROM consent_purposes")
    } else {
      purposes <- DBI::dbGetQuery(con, "
        SELECT * FROM consent_purposes WHERE is_active = 1
      ")
    }

    list(success = TRUE, purposes = purposes, count = nrow(purposes))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Deactivate Consent Purpose
#'
#' Deactivates a consent purpose (does not delete for audit).
#'
#' @param purpose_id Purpose ID
#' @param deactivated_by User deactivating
#'
#' @return List with success status
#' @export
deactivate_consent_purpose <- function(purpose_id, deactivated_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE consent_purposes
      SET is_active = 0, updated_at = ?, updated_by = ?
      WHERE purpose_id = ?
    ", params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                     deactivated_by, purpose_id))

    list(success = TRUE, message = "Purpose deactivated")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# CONSENT RECORDING
# ============================================================================

#' Record Consent
#'
#' Records a consent given by a data subject.
#'
#' @param subject_id Subject identifier
#' @param subject_email Subject email
#' @param purpose_id Purpose ID to consent to
#' @param consent_method Method from get_consent_methods()
#' @param recorded_by User recording the consent
#' @param subject_name Optional subject name
#' @param consent_version Optional version of consent text
#' @param consent_text Optional consent text shown to subject
#' @param ip_address Optional IP address
#' @param user_agent Optional user agent
#' @param expires_at Optional expiration date
#'
#' @return List with success status and consent details
#' @export
record_consent <- function(subject_id,
                            subject_email,
                            purpose_id,
                            consent_method,
                            recorded_by,
                            subject_name = NULL,
                            consent_version = NULL,
                            consent_text = NULL,
                            ip_address = NULL,
                            user_agent = NULL,
                            expires_at = NULL) {
  tryCatch({
    if (missing(subject_id) || is.null(subject_id) || subject_id == "") {
      return(list(success = FALSE, error = "subject_id is required"))
    }
    if (missing(subject_email) || is.null(subject_email) || subject_email == "") {
      return(list(success = FALSE, error = "subject_email is required"))
    }
    if (missing(purpose_id) || is.null(purpose_id)) {
      return(list(success = FALSE, error = "purpose_id is required"))
    }

    valid_methods <- names(get_consent_methods())
    if (!consent_method %in% valid_methods) {
      return(list(
        success = FALSE,
        error = paste("Invalid consent_method. Must be one of:",
                     paste(valid_methods, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    purpose <- DBI::dbGetQuery(con, "
      SELECT purpose_id, is_active FROM consent_purposes WHERE purpose_id = ?
    ", params = list(purpose_id))

    if (nrow(purpose) == 0) {
      return(list(success = FALSE, error = "Purpose not found"))
    }

    if (purpose$is_active[1] == 0) {
      return(list(success = FALSE, error = "Purpose is not active"))
    }

    consent_code <- generate_consent_id()
    consent_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    previous_hash <- NA_character_
    last_consent <- DBI::dbGetQuery(con, "
      SELECT consent_hash FROM consent_records
      WHERE subject_id = ?
      ORDER BY consent_id DESC LIMIT 1
    ", params = list(subject_id))

    if (nrow(last_consent) > 0) {
      previous_hash <- last_consent$consent_hash[1]
    }

    hash_content <- paste(
      consent_code,
      subject_id,
      subject_email,
      purpose_id,
      consent_date,
      consent_method,
      safe_scalar_consent(previous_hash),
      sep = "|"
    )
    consent_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO consent_records (
        consent_code, subject_id, subject_email, subject_name, purpose_id,
        consent_given, consent_date, consent_method, consent_version,
        consent_text, ip_address, user_agent, expires_at, consent_hash,
        previous_hash
      ) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      consent_code,
      subject_id,
      subject_email,
      safe_scalar_consent(subject_name),
      purpose_id,
      consent_date,
      consent_method,
      safe_scalar_consent(consent_version),
      safe_scalar_consent(consent_text),
      safe_scalar_consent(ip_address),
      safe_scalar_consent(user_agent),
      safe_scalar_consent(expires_at),
      consent_hash,
      safe_scalar_consent(previous_hash)
    ))

    consent_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_consent_action(
      consent_id = consent_id,
      action = "CONSENT_GIVEN",
      action_details = paste("Consent recorded via", consent_method),
      previous_state = 0,
      new_state = 1,
      performed_by = recorded_by
    )

    list(
      success = TRUE,
      consent_id = consent_id,
      consent_code = consent_code,
      consent_date = consent_date,
      message = "Consent recorded successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Log Consent Action
#' @keywords internal
log_consent_action <- function(consent_id, action, action_details,
                                previous_state, new_state, performed_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    previous_hash <- NA_character_
    last_history <- DBI::dbGetQuery(con, "
      SELECT history_hash FROM consent_history
      WHERE consent_id = ?
      ORDER BY history_id DESC LIMIT 1
    ", params = list(consent_id))

    if (nrow(last_history) > 0) {
      previous_hash <- last_history$history_hash[1]
    }

    performed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    hash_content <- paste(
      consent_id,
      action,
      previous_state,
      new_state,
      performed_by,
      performed_at,
      safe_scalar_consent(previous_hash),
      sep = "|"
    )
    history_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO consent_history (
        consent_id, action, action_details, previous_state, new_state,
        performed_by, performed_at, history_hash, previous_history_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      consent_id,
      action,
      action_details,
      previous_state,
      new_state,
      performed_by,
      performed_at,
      history_hash,
      safe_scalar_consent(previous_hash)
    ))

    list(success = TRUE)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# CONSENT WITHDRAWAL
# ============================================================================

#' Withdraw Consent
#'
#' Withdraws consent for a specific consent record.
#'
#' @param consent_id Consent ID to withdraw
#' @param withdrawn_by User recording the withdrawal
#' @param withdrawn_reason Reason for withdrawal
#'
#' @return List with success status
#' @export
withdraw_consent <- function(consent_id, withdrawn_by, withdrawn_reason = NULL) {
  tryCatch({
    if (missing(consent_id) || is.null(consent_id)) {
      return(list(success = FALSE, error = "consent_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    consent <- DBI::dbGetQuery(con, "
      SELECT consent_id, consent_given, withdrawn FROM consent_records
      WHERE consent_id = ?
    ", params = list(consent_id))

    if (nrow(consent) == 0) {
      return(list(success = FALSE, error = "Consent not found"))
    }

    if (consent$withdrawn[1] == 1) {
      return(list(success = FALSE, error = "Consent already withdrawn"))
    }

    withdrawn_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE consent_records
      SET withdrawn = 1, withdrawn_date = ?, withdrawn_by = ?,
          withdrawn_reason = ?, is_active = 0, consent_given = 0
      WHERE consent_id = ?
    ", params = list(
      withdrawn_date,
      withdrawn_by,
      safe_scalar_consent(withdrawn_reason),
      consent_id
    ))

    log_consent_action(
      consent_id = consent_id,
      action = "CONSENT_WITHDRAWN",
      action_details = paste("Consent withdrawn.",
                            if (!is.null(withdrawn_reason))
                              paste("Reason:", withdrawn_reason) else ""),
      previous_state = 1,
      new_state = 0,
      performed_by = withdrawn_by
    )

    list(
      success = TRUE,
      withdrawn_date = withdrawn_date,
      message = "Consent withdrawn successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Withdraw All Consents
#'
#' Withdraws all consents for a subject.
#'
#' @param subject_id Subject identifier
#' @param withdrawn_by User recording the withdrawal
#' @param withdrawn_reason Reason for withdrawal
#'
#' @return List with success status and count
#' @export
withdraw_all_consents <- function(subject_id, withdrawn_by, withdrawn_reason = NULL) {
  tryCatch({
    if (missing(subject_id) || is.null(subject_id) || subject_id == "") {
      return(list(success = FALSE, error = "subject_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    consents <- DBI::dbGetQuery(con, "
      SELECT consent_id FROM consent_records
      WHERE subject_id = ? AND withdrawn = 0 AND consent_given = 1
    ", params = list(subject_id))

    if (nrow(consents) == 0) {
      return(list(success = TRUE, withdrawn_count = 0,
                  message = "No active consents to withdraw"))
    }

    withdrawn_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE consent_records
      SET withdrawn = 1, withdrawn_date = ?, withdrawn_by = ?,
          withdrawn_reason = ?, is_active = 0, consent_given = 0
      WHERE subject_id = ? AND withdrawn = 0 AND consent_given = 1
    ", params = list(
      withdrawn_date,
      withdrawn_by,
      safe_scalar_consent(withdrawn_reason),
      subject_id
    ))

    for (i in seq_len(nrow(consents))) {
      log_consent_action(
        consent_id = consents$consent_id[i],
        action = "CONSENT_WITHDRAWN",
        action_details = "Bulk withdrawal - all consents",
        previous_state = 1,
        new_state = 0,
        performed_by = withdrawn_by
      )
    }

    list(
      success = TRUE,
      withdrawn_count = nrow(consents),
      withdrawn_date = withdrawn_date,
      message = paste(nrow(consents), "consent(s) withdrawn")
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Create Withdrawal Request
#'
#' Creates a formal consent withdrawal request.
#'
#' @param subject_id Subject identifier
#' @param subject_email Subject email
#' @param withdrawal_scope Scope from get_withdrawal_scopes()
#' @param requested_by User creating the request
#' @param purpose_ids Optional specific purpose IDs (for SPECIFIC scope)
#' @param withdrawal_reason Optional reason
#'
#' @return List with success status and request details
#' @export
create_withdrawal_request <- function(subject_id,
                                       subject_email,
                                       withdrawal_scope,
                                       requested_by,
                                       purpose_ids = NULL,
                                       withdrawal_reason = NULL) {
  tryCatch({
    if (missing(subject_id) || is.null(subject_id) || subject_id == "") {
      return(list(success = FALSE, error = "subject_id is required"))
    }
    if (missing(subject_email) || is.null(subject_email) || subject_email == "") {
      return(list(success = FALSE, error = "subject_email is required"))
    }

    valid_scopes <- names(get_withdrawal_scopes())
    if (!withdrawal_scope %in% valid_scopes) {
      return(list(
        success = FALSE,
        error = paste("Invalid withdrawal_scope. Must be one of:",
                     paste(valid_scopes, collapse = ", "))
      ))
    }

    if (withdrawal_scope == "SPECIFIC" &&
        (is.null(purpose_ids) || length(purpose_ids) == 0)) {
      return(list(success = FALSE,
                  error = "purpose_ids required for SPECIFIC scope"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request_number <- paste0("WDRL-",
                            format(Sys.time(), "%Y%m%d%H%M%S"), "-",
                            paste0(sample(c(0:9, LETTERS), 4, replace = TRUE),
                                   collapse = ""))

    received_date <- format(Sys.Date(), "%Y-%m-%d")

    previous_hash <- NA_character_
    last_request <- DBI::dbGetQuery(con, "
      SELECT request_hash FROM consent_withdrawal_requests
      ORDER BY request_id DESC LIMIT 1
    ")
    if (nrow(last_request) > 0) {
      previous_hash <- last_request$request_hash[1]
    }

    hash_content <- paste(
      request_number,
      subject_id,
      subject_email,
      withdrawal_scope,
      received_date,
      safe_scalar_consent(previous_hash),
      sep = "|"
    )
    request_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO consent_withdrawal_requests (
        request_number, subject_id, subject_email, withdrawal_scope,
        purpose_ids, withdrawal_reason, received_date, requested_by,
        request_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_number,
      subject_id,
      subject_email,
      withdrawal_scope,
      safe_scalar_consent(purpose_ids),
      safe_scalar_consent(withdrawal_reason),
      received_date,
      requested_by,
      request_hash,
      safe_scalar_consent(previous_hash)
    ))

    request_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      request_id = request_id,
      request_number = request_number,
      status = "RECEIVED",
      message = "Withdrawal request created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Process Withdrawal Request
#'
#' Processes a consent withdrawal request.
#'
#' @param request_id Request ID
#' @param processed_by User processing the request
#'
#' @return List with success status and count
#' @export
process_withdrawal_request <- function(request_id, processed_by) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT * FROM consent_withdrawal_requests WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (request$status[1] == "COMPLETED") {
      return(list(success = FALSE, error = "Request already processed"))
    }

    withdrawn_count <- 0

    if (request$withdrawal_scope[1] == "ALL") {
      result <- withdraw_all_consents(
        subject_id = request$subject_id[1],
        withdrawn_by = processed_by,
        withdrawn_reason = request$withdrawal_reason[1]
      )
      withdrawn_count <- result$withdrawn_count
    } else if (request$withdrawal_scope[1] == "SPECIFIC") {
      purpose_ids <- strsplit(request$purpose_ids[1], ";")[[1]]
      consents <- DBI::dbGetQuery(con, paste0("
        SELECT consent_id FROM consent_records
        WHERE subject_id = ? AND purpose_id IN (",
        paste(rep("?", length(purpose_ids)), collapse = ","),
        ") AND withdrawn = 0 AND consent_given = 1
      "), params = c(list(request$subject_id[1]), as.list(purpose_ids)))

      for (i in seq_len(nrow(consents))) {
        withdraw_consent(
          consent_id = consents$consent_id[i],
          withdrawn_by = processed_by,
          withdrawn_reason = request$withdrawal_reason[1]
        )
        withdrawn_count <- withdrawn_count + 1
      }
    }

    completed_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE consent_withdrawal_requests
      SET status = 'COMPLETED', completed_date = ?, processed_by = ?
      WHERE request_id = ?
    ", params = list(completed_date, processed_by, request_id))

    list(
      success = TRUE,
      status = "COMPLETED",
      withdrawn_count = withdrawn_count,
      completed_date = completed_date,
      message = paste("Processed -", withdrawn_count, "consent(s) withdrawn")
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# CONSENT CHECKING
# ============================================================================

#' Check Consent
#'
#' Checks if a subject has given consent for a purpose.
#'
#' @param subject_id Subject identifier
#' @param purpose_id Purpose ID to check
#'
#' @return List with consent status
#' @export
check_consent <- function(subject_id, purpose_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    consent <- DBI::dbGetQuery(con, "
      SELECT consent_id, consent_given, withdrawn, expires_at
      FROM consent_records
      WHERE subject_id = ? AND purpose_id = ? AND is_active = 1
      ORDER BY consent_id DESC LIMIT 1
    ", params = list(subject_id, purpose_id))

    if (nrow(consent) == 0) {
      return(list(
        success = TRUE,
        has_consent = FALSE,
        reason = "No consent record found"
      ))
    }

    if (consent$withdrawn[1] == 1) {
      return(list(
        success = TRUE,
        has_consent = FALSE,
        reason = "Consent withdrawn"
      ))
    }

    if (!is.na(consent$expires_at[1])) {
      if (as.Date(consent$expires_at[1]) < Sys.Date()) {
        return(list(
          success = TRUE,
          has_consent = FALSE,
          reason = "Consent expired"
        ))
      }
    }

    if (consent$consent_given[1] == 1) {
      list(
        success = TRUE,
        has_consent = TRUE,
        consent_id = consent$consent_id[1]
      )
    } else {
      list(
        success = TRUE,
        has_consent = FALSE,
        reason = "Consent not given"
      )
    }

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Subject Consents
#'
#' Gets all consents for a subject.
#'
#' @param subject_id Subject identifier
#' @param include_withdrawn Include withdrawn consents
#'
#' @return List with success status and consents
#' @export
get_subject_consents <- function(subject_id, include_withdrawn = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (include_withdrawn) {
      consents <- DBI::dbGetQuery(con, "
        SELECT c.*, p.purpose_code, p.purpose_name
        FROM consent_records c
        JOIN consent_purposes p ON c.purpose_id = p.purpose_id
        WHERE c.subject_id = ?
        ORDER BY c.consent_id DESC
      ", params = list(subject_id))
    } else {
      consents <- DBI::dbGetQuery(con, "
        SELECT c.*, p.purpose_code, p.purpose_name
        FROM consent_records c
        JOIN consent_purposes p ON c.purpose_id = p.purpose_id
        WHERE c.subject_id = ? AND c.withdrawn = 0 AND c.consent_given = 1
        ORDER BY c.consent_id DESC
      ", params = list(subject_id))
    }

    list(success = TRUE, consents = consents, count = nrow(consents))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Consent History
#'
#' Gets audit history for a consent record.
#'
#' @param consent_id Consent ID
#'
#' @return List with success status and history
#' @export
get_consent_history <- function(consent_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    history <- DBI::dbGetQuery(con, "
      SELECT * FROM consent_history
      WHERE consent_id = ?
      ORDER BY history_id ASC
    ", params = list(consent_id))

    list(success = TRUE, history = history, count = nrow(history))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Pending Withdrawal Requests
#'
#' Gets all pending withdrawal requests.
#'
#' @return List with success status and requests
#' @export
get_pending_withdrawal_requests <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    requests <- DBI::dbGetQuery(con, "
      SELECT * FROM consent_withdrawal_requests
      WHERE status = 'RECEIVED'
      ORDER BY received_date ASC
    ")

    list(success = TRUE, requests = requests, count = nrow(requests))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# CONSENT REFRESH
# ============================================================================

#' Refresh Consent
#'
#' Refreshes an existing consent (re-consent).
#'
#' @param consent_id Existing consent ID
#' @param consent_method Method used for refresh
#' @param refreshed_by User recording the refresh
#' @param new_consent_text Optional new consent text
#' @param new_version Optional new version
#'
#' @return List with success status
#' @export
refresh_consent <- function(consent_id,
                             consent_method,
                             refreshed_by,
                             new_consent_text = NULL,
                             new_version = NULL) {
  tryCatch({
    if (missing(consent_id) || is.null(consent_id)) {
      return(list(success = FALSE, error = "consent_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    consent <- DBI::dbGetQuery(con, "
      SELECT * FROM consent_records WHERE consent_id = ?
    ", params = list(consent_id))

    if (nrow(consent) == 0) {
      return(list(success = FALSE, error = "Consent not found"))
    }

    refreshed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE consent_records
      SET consent_given = 1, consent_date = ?, consent_method = ?,
          consent_text = COALESCE(?, consent_text),
          consent_version = COALESCE(?, consent_version),
          withdrawn = 0, is_active = 1
      WHERE consent_id = ?
    ", params = list(
      refreshed_at,
      consent_method,
      safe_scalar_consent(new_consent_text),
      safe_scalar_consent(new_version),
      consent_id
    ))

    log_consent_action(
      consent_id = consent_id,
      action = "CONSENT_REFRESHED",
      action_details = paste("Consent refreshed via", consent_method),
      previous_state = consent$consent_given[1],
      new_state = 1,
      performed_by = refreshed_by
    )

    list(
      success = TRUE,
      refreshed_at = refreshed_at,
      message = "Consent refreshed successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# STATISTICS AND REPORTING
# ============================================================================

#' Get Consent Statistics
#'
#' Returns comprehensive consent statistics.
#'
#' @return List with statistics
#' @export
get_consent_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    consent_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(consent_given) as given,
        SUM(withdrawn) as withdrawn,
        SUM(CASE WHEN is_active = 1 AND consent_given = 1 THEN 1 ELSE 0 END)
          as active
      FROM consent_records
    ")

    purpose_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(is_active) as active,
        SUM(is_mandatory) as mandatory
      FROM consent_purposes
    ")

    withdrawal_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'RECEIVED' THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) as completed
      FROM consent_withdrawal_requests
    ")

    by_purpose <- DBI::dbGetQuery(con, "
      SELECT p.purpose_name, COUNT(c.consent_id) as count,
             SUM(c.consent_given) as given
      FROM consent_purposes p
      LEFT JOIN consent_records c ON p.purpose_id = c.purpose_id
      GROUP BY p.purpose_id
    ")

    list(
      success = TRUE,
      consents = as.list(consent_stats),
      purposes = as.list(purpose_stats),
      withdrawals = as.list(withdrawal_stats),
      by_purpose = by_purpose
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Generate Consent Report
#'
#' Generates a consent management report.
#'
#' @param output_file Output file path
#' @param format Report format: "txt" or "json"
#' @param organization Organization name
#' @param prepared_by Name of person preparing report
#'
#' @return List with success status
#' @export
generate_consent_report <- function(output_file,
                                     format = "txt",
                                     organization = "Organization",
                                     prepared_by = "DPO") {
  tryCatch({
    stats <- get_consent_statistics()
    if (!stats$success) {
      return(list(success = FALSE, error = "Failed to get statistics"))
    }

    if (format == "json") {
      report_data <- list(
        report_type = "GDPR Article 7 Consent Management Report",
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
        "         GDPR ARTICLE 7 - CONSENT MANAGEMENT REPORT",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Prepared by:", prepared_by),
        paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        "",
        "-------------------------------------------------------------------------------",
        "CONSENT RECORDS",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Records:", stats$consents$total),
        paste("  - Given:", stats$consents$given),
        paste("  - Active:", stats$consents$active),
        paste("  - Withdrawn:", stats$consents$withdrawn),
        "",
        "-------------------------------------------------------------------------------",
        "CONSENT PURPOSES",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Purposes:", stats$purposes$total),
        paste("  - Active:", stats$purposes$active),
        paste("  - Mandatory:", stats$purposes$mandatory),
        "",
        "-------------------------------------------------------------------------------",
        "WITHDRAWAL REQUESTS",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Requests:", stats$withdrawals$total),
        paste("  - Pending:", stats$withdrawals$pending),
        paste("  - Completed:", stats$withdrawals$completed),
        "",
        "-------------------------------------------------------------------------------",
        "GDPR ARTICLE 7 COMPLIANCE NOTES",
        "-------------------------------------------------------------------------------",
        "",
        "Article 7(1): Demonstrable Consent",
        "  - Controller must demonstrate consent was given",
        "  - Consent records include method, date, and version",
        "",
        "Article 7(2): Distinguishable Request",
        "  - Consent request clearly distinguishable from other matters",
        "  - Intelligible, easily accessible, clear and plain language",
        "",
        "Article 7(3): Right to Withdraw",
        "  - Withdrawal shall be as easy as giving consent",
        "  - Data subject informed of right before consent given",
        "",
        "Article 7(4): Freely Given",
        "  - Performance not conditional on consent not necessary",
        "  - Separate consent for separate purposes",
        "",
        "===============================================================================",
        ""
      )
      writeLines(lines, output_file)
    }

    list(success = TRUE, output_file = output_file,
         message = paste("Report generated:", output_file))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
