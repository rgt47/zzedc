#' Data Retention Enforcement System
#'
#' GDPR Article 5(1)(e) compliant data retention management.
#' Manages retention policies, tracks data age, enforces retention
#' periods, and maintains comprehensive audit trails.
#'
#' @name retention
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' @keywords internal
safe_scalar_retention <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' @keywords internal
safe_int_retention <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

#' @keywords internal
generate_retention_id <- function(prefix = "RET") {

  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(c(0:9, LETTERS), 6, replace = TRUE), collapse = "")
  paste0(prefix, "-", timestamp, "-", random)
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize Data Retention System Tables
#'
#' Creates the database tables required for GDPR Article 5(1)(e)
#' data retention compliance.
#'
#' @return List with success status and message
#' @export
init_retention <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS retention_policies (
        policy_id INTEGER PRIMARY KEY AUTOINCREMENT,
        policy_code TEXT UNIQUE NOT NULL,
        policy_name TEXT NOT NULL,
        data_category TEXT NOT NULL,
        table_name TEXT,
        retention_period_days INTEGER NOT NULL,
        retention_basis TEXT NOT NULL,
        legal_reference TEXT,
        description TEXT,
        action_on_expiry TEXT DEFAULT 'DELETE',
        requires_review INTEGER DEFAULT 1,
        auto_enforce INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS retention_records (
        record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        policy_id INTEGER NOT NULL,
        table_name TEXT NOT NULL,
        record_key TEXT NOT NULL,
        subject_id TEXT,
        data_category TEXT NOT NULL,
        created_date TEXT NOT NULL,
        last_accessed_date TEXT,
        retention_start_date TEXT NOT NULL,
        retention_end_date TEXT NOT NULL,
        status TEXT DEFAULT 'ACTIVE',
        extended INTEGER DEFAULT 0,
        extension_count INTEGER DEFAULT 0,
        extension_reason TEXT,
        extended_until TEXT,
        legal_hold INTEGER DEFAULT 0,
        legal_hold_reason TEXT,
        legal_hold_start TEXT,
        legal_hold_end TEXT,
        reviewed INTEGER DEFAULT 0,
        reviewed_at TEXT,
        reviewed_by TEXT,
        action_taken TEXT,
        action_date TEXT,
        action_by TEXT,
        record_hash TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (policy_id) REFERENCES retention_policies(policy_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS retention_reviews (
        review_id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id INTEGER,
        policy_id INTEGER,
        review_type TEXT NOT NULL,
        review_scope TEXT NOT NULL,
        records_reviewed INTEGER DEFAULT 0,
        records_expired INTEGER DEFAULT 0,
        records_extended INTEGER DEFAULT 0,
        records_deleted INTEGER DEFAULT 0,
        records_anonymized INTEGER DEFAULT 0,
        records_on_hold INTEGER DEFAULT 0,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        performed_by TEXT NOT NULL,
        review_notes TEXT,
        review_hash TEXT NOT NULL,
        FOREIGN KEY (record_id) REFERENCES retention_records(record_id),
        FOREIGN KEY (policy_id) REFERENCES retention_policies(policy_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS retention_actions (
        action_id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id INTEGER NOT NULL,
        review_id INTEGER,
        action_type TEXT NOT NULL,
        previous_status TEXT,
        new_status TEXT,
        action_reason TEXT,
        action_details TEXT,
        performed_by TEXT NOT NULL,
        performed_at TEXT DEFAULT (datetime('now')),
        action_hash TEXT NOT NULL,
        previous_action_hash TEXT,
        FOREIGN KEY (record_id) REFERENCES retention_records(record_id),
        FOREIGN KEY (review_id) REFERENCES retention_reviews(review_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS retention_schedules (
        schedule_id INTEGER PRIMARY KEY AUTOINCREMENT,
        policy_id INTEGER NOT NULL,
        schedule_type TEXT NOT NULL,
        frequency_days INTEGER NOT NULL,
        last_run_date TEXT,
        next_run_date TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        FOREIGN KEY (policy_id) REFERENCES retention_policies(policy_id)
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_retention_records_policy
                         ON retention_records(policy_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_retention_records_status
                         ON retention_records(status)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_retention_records_end_date
                         ON retention_records(retention_end_date)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_retention_records_subject
                         ON retention_records(subject_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_retention_policies_code
                         ON retention_policies(policy_code)")

    list(success = TRUE, message = "Data retention system initialized")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Retention Bases
#' @return Named character vector of retention legal bases
#' @export
get_retention_bases <- function() {
  c(
    LEGAL_REQUIREMENT = "Legal or regulatory requirement",
    CONTRACT = "Contractual obligation",
    LEGITIMATE_INTEREST = "Legitimate interest",
    CONSENT = "Data subject consent",
    RESEARCH = "Scientific or historical research",
    PUBLIC_INTEREST = "Public interest archiving",
    LEGAL_CLAIMS = "Establishment or defense of legal claims"
  )
}

#' Get Retention Actions
#' @return Named character vector of actions on expiry
#' @export
get_retention_actions <- function() {
  c(
    DELETE = "Permanently delete data",
    ANONYMIZE = "Anonymize data (remove identifiers)",
    ARCHIVE = "Move to secure archive",
    REVIEW = "Flag for manual review",
    EXTEND = "Extend retention period"
  )
}

#' Get Retention Statuses
#' @return Named character vector of record statuses
#' @export
get_retention_statuses <- function() {
  c(
    ACTIVE = "Data is within retention period",
    EXPIRED = "Retention period has ended",
    EXTENDED = "Retention extended",
    LEGAL_HOLD = "On legal hold - cannot delete",
    DELETED = "Data has been deleted",
    ANONYMIZED = "Data has been anonymized",
    ARCHIVED = "Data has been archived"
  )
}

#' Get Review Types
#' @return Named character vector of review types
#' @export
get_review_types <- function() {
  c(
    SCHEDULED = "Scheduled periodic review",
    MANUAL = "Manual ad-hoc review",
    TRIGGERED = "Event-triggered review",
    AUDIT = "Compliance audit review"
  )
}

#' Get Data Categories
#' @return Named character vector of data categories
#' @export
get_retention_data_categories <- function() {
  c(
    IDENTITY = "Identity data (name, ID numbers)",
    CONTACT = "Contact data (address, email, phone)",
    HEALTH = "Health and medical data",
    FINANCIAL = "Financial data",
    BEHAVIORAL = "Behavioral/usage data",
    CONSENT = "Consent records",
    AUDIT = "Audit trail data",
    RESEARCH = "Research data",
    COMMUNICATIONS = "Communication records"
  )
}

# ============================================================================
# POLICY MANAGEMENT
# ============================================================================

#' Create Retention Policy
#'
#' Creates a data retention policy for a data category.
#'
#' @param policy_code Unique code for the policy
#' @param policy_name Human-readable name
#' @param data_category Data category from get_retention_data_categories()
#' @param retention_period_days Retention period in days
#' @param retention_basis Legal basis from get_retention_bases()
#' @param created_by User creating the policy
#' @param table_name Optional specific table this applies to
#' @param legal_reference Optional legal/regulatory reference
#' @param description Optional policy description
#' @param action_on_expiry Action from get_retention_actions()
#' @param requires_review Whether manual review required before action
#' @param auto_enforce Whether to auto-enforce on expiry
#'
#' @return List with success status and policy details
#' @export
create_retention_policy <- function(policy_code,
                                     policy_name,
                                     data_category,
                                     retention_period_days,
                                     retention_basis,
                                     created_by,
                                     table_name = NULL,
                                     legal_reference = NULL,
                                     description = NULL,
                                     action_on_expiry = "DELETE",
                                     requires_review = TRUE,
                                     auto_enforce = FALSE) {
  tryCatch({
    if (missing(policy_code) || is.null(policy_code) || policy_code == "") {
      return(list(success = FALSE, error = "policy_code is required"))
    }
    if (missing(policy_name) || is.null(policy_name) || policy_name == "") {
      return(list(success = FALSE, error = "policy_name is required"))
    }
    if (missing(retention_period_days) || is.null(retention_period_days) ||
        retention_period_days < 1) {
      return(list(success = FALSE,
                  error = "retention_period_days must be at least 1"))
    }

    valid_categories <- names(get_retention_data_categories())
    if (!data_category %in% valid_categories) {
      return(list(
        success = FALSE,
        error = paste("Invalid data_category. Must be one of:",
                     paste(valid_categories, collapse = ", "))
      ))
    }

    valid_bases <- names(get_retention_bases())
    if (!retention_basis %in% valid_bases) {
      return(list(
        success = FALSE,
        error = paste("Invalid retention_basis. Must be one of:",
                     paste(valid_bases, collapse = ", "))
      ))
    }

    valid_actions <- names(get_retention_actions())
    if (!action_on_expiry %in% valid_actions) {
      return(list(
        success = FALSE,
        error = paste("Invalid action_on_expiry. Must be one of:",
                     paste(valid_actions, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    existing <- DBI::dbGetQuery(con, "
      SELECT policy_id FROM retention_policies WHERE policy_code = ?
    ", params = list(policy_code))

    if (nrow(existing) > 0) {
      return(list(success = FALSE, error = "policy_code already exists"))
    }

    DBI::dbExecute(con, "
      INSERT INTO retention_policies (
        policy_code, policy_name, data_category, table_name,
        retention_period_days, retention_basis, legal_reference,
        description, action_on_expiry, requires_review, auto_enforce,
        created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      policy_code,
      policy_name,
      data_category,
      safe_scalar_retention(table_name),
      as.integer(retention_period_days),
      retention_basis,
      safe_scalar_retention(legal_reference),
      safe_scalar_retention(description),
      action_on_expiry,
      as.integer(requires_review),
      as.integer(auto_enforce),
      created_by
    ))

    policy_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      policy_id = policy_id,
      policy_code = policy_code,
      retention_period_days = retention_period_days,
      message = "Retention policy created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Retention Policies
#'
#' Retrieves retention policies.
#'
#' @param include_inactive Include inactive policies
#' @param data_category Optional filter by data category
#'
#' @return List with success status and policies
#' @export
get_retention_policies <- function(include_inactive = FALSE,
                                    data_category = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM retention_policies WHERE 1=1"
    params <- list()

    if (!include_inactive) {
      query <- paste(query, "AND is_active = 1")
    }

    if (!is.null(data_category)) {
      query <- paste(query, "AND data_category = ?")
      params <- append(params, list(data_category))
    }

    query <- paste(query, "ORDER BY data_category, policy_name")

    if (length(params) > 0) {
      policies <- DBI::dbGetQuery(con, query, params = params)
    } else {
      policies <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, policies = policies, count = nrow(policies))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update Retention Policy
#'
#' Updates an existing retention policy.
#'
#' @param policy_id Policy ID
#' @param updated_by User updating the policy
#' @param retention_period_days New retention period
#' @param action_on_expiry New action on expiry
#' @param requires_review New review requirement
#' @param auto_enforce New auto-enforce setting
#' @param is_active New active status
#'
#' @return List with success status
#' @export
update_retention_policy <- function(policy_id,
                                     updated_by,
                                     retention_period_days = NULL,
                                     action_on_expiry = NULL,
                                     requires_review = NULL,
                                     auto_enforce = NULL,
                                     is_active = NULL) {
  tryCatch({
    if (missing(policy_id) || is.null(policy_id)) {
      return(list(success = FALSE, error = "policy_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    policy <- DBI::dbGetQuery(con, "
      SELECT policy_id FROM retention_policies WHERE policy_id = ?
    ", params = list(policy_id))

    if (nrow(policy) == 0) {
      return(list(success = FALSE, error = "Policy not found"))
    }

    updates <- c()
    params <- list()

    if (!is.null(retention_period_days)) {
      updates <- c(updates, "retention_period_days = ?")
      params <- append(params, list(as.integer(retention_period_days)))
    }
    if (!is.null(action_on_expiry)) {
      updates <- c(updates, "action_on_expiry = ?")
      params <- append(params, list(action_on_expiry))
    }
    if (!is.null(requires_review)) {
      updates <- c(updates, "requires_review = ?")
      params <- append(params, list(as.integer(requires_review)))
    }
    if (!is.null(auto_enforce)) {
      updates <- c(updates, "auto_enforce = ?")
      params <- append(params, list(as.integer(auto_enforce)))
    }
    if (!is.null(is_active)) {
      updates <- c(updates, "is_active = ?")
      params <- append(params, list(as.integer(is_active)))
    }

    if (length(updates) == 0) {
      return(list(success = FALSE, error = "No updates provided"))
    }

    updates <- c(updates, "updated_at = ?", "updated_by = ?")
    params <- append(params, list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      updated_by
    ))
    params <- append(params, list(policy_id))

    query <- paste("UPDATE retention_policies SET",
                   paste(updates, collapse = ", "),
                   "WHERE policy_id = ?")

    DBI::dbExecute(con, query, params = params)

    list(success = TRUE, message = "Policy updated")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# RETENTION RECORD MANAGEMENT
# ============================================================================

#' Register Data for Retention Tracking
#'
#' Registers a data record for retention tracking.
#'
#' @param policy_id Policy ID to apply
#' @param table_name Table containing the data
#' @param record_key Unique key identifying the record
#' @param created_date Date the data was created
#' @param registered_by User registering the record
#' @param subject_id Optional subject ID
#' @param data_category Optional override of policy category
#'
#' @return List with success status and record details
#' @export
register_retention_record <- function(policy_id,
                                       table_name,
                                       record_key,
                                       created_date,
                                       registered_by,
                                       subject_id = NULL,
                                       data_category = NULL) {
  tryCatch({
    if (missing(policy_id) || is.null(policy_id)) {
      return(list(success = FALSE, error = "policy_id is required"))
    }
    if (missing(table_name) || is.null(table_name) || table_name == "") {
      return(list(success = FALSE, error = "table_name is required"))
    }
    if (missing(record_key) || is.null(record_key) || record_key == "") {
      return(list(success = FALSE, error = "record_key is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    policy <- DBI::dbGetQuery(con, "
      SELECT policy_id, data_category, retention_period_days, is_active
      FROM retention_policies WHERE policy_id = ?
    ", params = list(policy_id))

    if (nrow(policy) == 0) {
      return(list(success = FALSE, error = "Policy not found"))
    }

    if (policy$is_active[1] == 0) {
      return(list(success = FALSE, error = "Policy is not active"))
    }

    existing <- DBI::dbGetQuery(con, "
      SELECT record_id FROM retention_records
      WHERE table_name = ? AND record_key = ?
    ", params = list(table_name, record_key))

    if (nrow(existing) > 0) {
      return(list(success = FALSE, error = "Record already registered"))
    }

    if (is.null(data_category)) {
      data_category <- policy$data_category[1]
    }

    if (is.character(created_date)) {
      created_date <- as.Date(created_date)
    }

    retention_start <- created_date
    retention_end <- created_date + policy$retention_period_days[1]

    hash_content <- paste(
      policy_id,
      table_name,
      record_key,
      format(retention_start, "%Y-%m-%d"),
      format(retention_end, "%Y-%m-%d"),
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    record_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO retention_records (
        policy_id, table_name, record_key, subject_id, data_category,
        created_date, retention_start_date, retention_end_date, record_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      policy_id,
      table_name,
      record_key,
      safe_scalar_retention(subject_id),
      data_category,
      format(created_date, "%Y-%m-%d"),
      format(retention_start, "%Y-%m-%d"),
      format(retention_end, "%Y-%m-%d"),
      record_hash
    ))

    record_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_retention_action(
      record_id = record_id,
      action_type = "REGISTERED",
      new_status = "ACTIVE",
      action_reason = "Data registered for retention tracking",
      performed_by = registered_by
    )

    list(
      success = TRUE,
      record_id = record_id,
      retention_end_date = format(retention_end, "%Y-%m-%d"),
      message = "Record registered for retention tracking"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Log Retention Action
#' @keywords internal
log_retention_action <- function(record_id, action_type, new_status = NULL,
                                  previous_status = NULL, action_reason = NULL,
                                  action_details = NULL, performed_by,
                                  review_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    previous_hash <- NA_character_
    last_action <- DBI::dbGetQuery(con, "
      SELECT action_hash FROM retention_actions
      WHERE record_id = ?
      ORDER BY action_id DESC LIMIT 1
    ", params = list(record_id))

    if (nrow(last_action) > 0) {
      previous_hash <- last_action$action_hash[1]
    }

    performed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    hash_content <- paste(
      record_id,
      action_type,
      safe_scalar_retention(previous_status),
      safe_scalar_retention(new_status),
      performed_by,
      performed_at,
      safe_scalar_retention(previous_hash),
      sep = "|"
    )
    action_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO retention_actions (
        record_id, review_id, action_type, previous_status, new_status,
        action_reason, action_details, performed_by, performed_at,
        action_hash, previous_action_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      record_id,
      safe_int_retention(review_id),
      action_type,
      safe_scalar_retention(previous_status),
      safe_scalar_retention(new_status),
      safe_scalar_retention(action_reason),
      safe_scalar_retention(action_details),
      performed_by,
      performed_at,
      action_hash,
      safe_scalar_retention(previous_hash)
    ))

    list(success = TRUE)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# RETENTION REVIEW
# ============================================================================

#' Get Expired Records
#'
#' Retrieves records that have passed their retention end date.
#'
#' @param policy_id Optional filter by policy
#' @param data_category Optional filter by category
#' @param include_on_hold Include records on legal hold
#'
#' @return List with success status and expired records
#' @export
get_expired_records <- function(policy_id = NULL,
                                 data_category = NULL,
                                 include_on_hold = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    today <- format(Sys.Date(), "%Y-%m-%d")

    query <- "
      SELECT r.*, p.policy_code, p.policy_name, p.action_on_expiry,
             p.requires_review
      FROM retention_records r
      JOIN retention_policies p ON r.policy_id = p.policy_id
      WHERE r.retention_end_date < ?
        AND r.status = 'ACTIVE'
    "
    params <- list(today)

    if (!include_on_hold) {
      query <- paste(query, "AND r.legal_hold = 0")
    }

    if (!is.null(policy_id)) {
      query <- paste(query, "AND r.policy_id = ?")
      params <- append(params, list(policy_id))
    }

    if (!is.null(data_category)) {
      query <- paste(query, "AND r.data_category = ?")
      params <- append(params, list(data_category))
    }

    query <- paste(query, "ORDER BY r.retention_end_date ASC")

    records <- DBI::dbGetQuery(con, query, params = params)

    list(
      success = TRUE,
      records = records,
      count = nrow(records),
      as_of_date = today
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Records Expiring Soon
#'
#' Retrieves records expiring within specified days.
#'
#' @param days_ahead Number of days to look ahead
#' @param policy_id Optional filter by policy
#'
#' @return List with success status and records
#' @export
get_records_expiring_soon <- function(days_ahead = 30, policy_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    today <- Sys.Date()
    future_date <- format(today + days_ahead, "%Y-%m-%d")
    today_str <- format(today, "%Y-%m-%d")

    query <- "
      SELECT r.*, p.policy_code, p.policy_name, p.action_on_expiry
      FROM retention_records r
      JOIN retention_policies p ON r.policy_id = p.policy_id
      WHERE r.retention_end_date >= ?
        AND r.retention_end_date <= ?
        AND r.status = 'ACTIVE'
        AND r.legal_hold = 0
    "
    params <- list(today_str, future_date)

    if (!is.null(policy_id)) {
      query <- paste(query, "AND r.policy_id = ?")
      params <- append(params, list(policy_id))
    }

    query <- paste(query, "ORDER BY r.retention_end_date ASC")

    records <- DBI::dbGetQuery(con, query, params = params)

    list(
      success = TRUE,
      records = records,
      count = nrow(records),
      expiring_within_days = days_ahead
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Create Retention Review
#'
#' Creates a retention review session.
#'
#' @param review_type Type from get_review_types()
#' @param review_scope Description of review scope
#' @param performed_by User performing review
#' @param policy_id Optional policy ID for policy-specific review
#'
#' @return List with success status and review details
#' @export
create_retention_review <- function(review_type,
                                     review_scope,
                                     performed_by,
                                     policy_id = NULL) {
  tryCatch({
    valid_types <- names(get_review_types())
    if (!review_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid review_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    started_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    hash_content <- paste(
      review_type,
      review_scope,
      started_at,
      performed_by,
      sep = "|"
    )
    review_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO retention_reviews (
        policy_id, review_type, review_scope, started_at,
        performed_by, review_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      safe_int_retention(policy_id),
      review_type,
      review_scope,
      started_at,
      performed_by,
      review_hash
    ))

    review_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      review_id = review_id,
      review_type = review_type,
      started_at = started_at,
      message = "Retention review created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Complete Retention Review
#'
#' Completes a retention review with summary.
#'
#' @param review_id Review ID
#' @param completed_by User completing review
#' @param review_notes Optional review notes
#'
#' @return List with success status
#' @export
complete_retention_review <- function(review_id, completed_by,
                                       review_notes = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    review <- DBI::dbGetQuery(con, "
      SELECT review_id, completed_at FROM retention_reviews WHERE review_id = ?
    ", params = list(review_id))

    if (nrow(review) == 0) {
      return(list(success = FALSE, error = "Review not found"))
    }

    if (!is.na(review$completed_at[1])) {
      return(list(success = FALSE, error = "Review already completed"))
    }

    stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN action_type = 'DELETED' THEN 1 ELSE 0 END) as deleted,
        SUM(CASE WHEN action_type = 'ANONYMIZED' THEN 1 ELSE 0 END) as anonymized,
        SUM(CASE WHEN action_type = 'EXTENDED' THEN 1 ELSE 0 END) as extended
      FROM retention_actions
      WHERE review_id = ?
    ", params = list(review_id))

    completed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE retention_reviews
      SET completed_at = ?, review_notes = ?,
          records_reviewed = ?, records_deleted = ?,
          records_anonymized = ?, records_extended = ?
      WHERE review_id = ?
    ", params = list(
      completed_at,
      safe_scalar_retention(review_notes),
      stats$total[1],
      stats$deleted[1],
      stats$anonymized[1],
      stats$extended[1],
      review_id
    ))

    list(
      success = TRUE,
      completed_at = completed_at,
      records_reviewed = stats$total[1],
      records_deleted = stats$deleted[1],
      records_anonymized = stats$anonymized[1],
      records_extended = stats$extended[1],
      message = "Review completed"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# RETENTION ACTIONS
# ============================================================================

#' Delete Expired Record
#'
#' Marks a retention record as deleted.
#'
#' @param record_id Record ID
#' @param deleted_by User performing deletion
#' @param review_id Optional review ID
#' @param deletion_reason Optional reason for deletion
#'
#' @return List with success status
#' @export
delete_retention_record <- function(record_id, deleted_by,
                                     review_id = NULL,
                                     deletion_reason = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    record <- DBI::dbGetQuery(con, "
      SELECT record_id, status, legal_hold FROM retention_records
      WHERE record_id = ?
    ", params = list(record_id))

    if (nrow(record) == 0) {
      return(list(success = FALSE, error = "Record not found"))
    }

    if (record$legal_hold[1] == 1) {
      return(list(success = FALSE, error = "Record is on legal hold"))
    }

    if (record$status[1] == "DELETED") {
      return(list(success = FALSE, error = "Record already deleted"))
    }

    previous_status <- record$status[1]
    action_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE retention_records
      SET status = 'DELETED', action_taken = 'DELETED',
          action_date = ?, action_by = ?
      WHERE record_id = ?
    ", params = list(action_date, deleted_by, record_id))

    log_retention_action(
      record_id = record_id,
      action_type = "DELETED",
      previous_status = previous_status,
      new_status = "DELETED",
      action_reason = deletion_reason,
      action_details = "Record deleted per retention policy",
      performed_by = deleted_by,
      review_id = review_id
    )

    list(
      success = TRUE,
      action_date = action_date,
      message = "Record marked as deleted"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Anonymize Retention Record
#'
#' Marks a retention record as anonymized.
#'
#' @param record_id Record ID
#' @param anonymized_by User performing anonymization
#' @param review_id Optional review ID
#' @param anonymization_details Optional details
#'
#' @return List with success status
#' @export
anonymize_retention_record <- function(record_id, anonymized_by,
                                        review_id = NULL,
                                        anonymization_details = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    record <- DBI::dbGetQuery(con, "
      SELECT record_id, status, legal_hold FROM retention_records
      WHERE record_id = ?
    ", params = list(record_id))

    if (nrow(record) == 0) {
      return(list(success = FALSE, error = "Record not found"))
    }

    if (record$legal_hold[1] == 1) {
      return(list(success = FALSE, error = "Record is on legal hold"))
    }

    if (record$status[1] %in% c("DELETED", "ANONYMIZED")) {
      return(list(success = FALSE,
                  error = "Record already deleted or anonymized"))
    }

    previous_status <- record$status[1]
    action_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE retention_records
      SET status = 'ANONYMIZED', action_taken = 'ANONYMIZED',
          action_date = ?, action_by = ?, subject_id = NULL
      WHERE record_id = ?
    ", params = list(action_date, anonymized_by, record_id))

    log_retention_action(
      record_id = record_id,
      action_type = "ANONYMIZED",
      previous_status = previous_status,
      new_status = "ANONYMIZED",
      action_reason = "Data anonymized per retention policy",
      action_details = anonymization_details,
      performed_by = anonymized_by,
      review_id = review_id
    )

    list(
      success = TRUE,
      action_date = action_date,
      message = "Record marked as anonymized"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Extend Retention Period
#'
#' Extends the retention period for a record.
#'
#' @param record_id Record ID
#' @param extension_days Number of days to extend
#' @param extension_reason Reason for extension
#' @param extended_by User extending retention
#' @param review_id Optional review ID
#'
#' @return List with success status and new end date
#' @export
extend_retention <- function(record_id, extension_days, extension_reason,
                              extended_by, review_id = NULL) {
  tryCatch({
    if (missing(extension_reason) || is.null(extension_reason) ||
        extension_reason == "") {
      return(list(success = FALSE, error = "extension_reason is required"))
    }
    if (missing(extension_days) || is.null(extension_days) ||
        extension_days < 1) {
      return(list(success = FALSE,
                  error = "extension_days must be at least 1"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    record <- DBI::dbGetQuery(con, "
      SELECT record_id, status, retention_end_date, extension_count
      FROM retention_records WHERE record_id = ?
    ", params = list(record_id))

    if (nrow(record) == 0) {
      return(list(success = FALSE, error = "Record not found"))
    }

    if (record$status[1] %in% c("DELETED", "ANONYMIZED")) {
      return(list(success = FALSE, error = "Cannot extend deleted record"))
    }

    current_end <- as.Date(record$retention_end_date[1])
    new_end <- current_end + extension_days
    new_extension_count <- record$extension_count[1] + 1
    previous_status <- record$status[1]

    DBI::dbExecute(con, "
      UPDATE retention_records
      SET retention_end_date = ?, status = 'EXTENDED',
          extended = 1, extension_count = ?,
          extension_reason = ?, extended_until = ?
      WHERE record_id = ?
    ", params = list(
      format(new_end, "%Y-%m-%d"),
      new_extension_count,
      extension_reason,
      format(new_end, "%Y-%m-%d"),
      record_id
    ))

    log_retention_action(
      record_id = record_id,
      action_type = "EXTENDED",
      previous_status = previous_status,
      new_status = "EXTENDED",
      action_reason = extension_reason,
      action_details = paste("Extended by", extension_days, "days to",
                            format(new_end, "%Y-%m-%d")),
      performed_by = extended_by,
      review_id = review_id
    )

    list(
      success = TRUE,
      new_retention_end_date = format(new_end, "%Y-%m-%d"),
      extension_count = new_extension_count,
      message = paste("Retention extended to", format(new_end, "%Y-%m-%d"))
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Apply Legal Hold
#'
#' Places a record on legal hold to prevent deletion.
#'
#' @param record_id Record ID
#' @param hold_reason Reason for legal hold
#' @param held_by User applying hold
#' @param hold_end_date Optional expected end date
#'
#' @return List with success status
#' @export
apply_legal_hold <- function(record_id, hold_reason, held_by,
                              hold_end_date = NULL) {
  tryCatch({
    if (missing(hold_reason) || is.null(hold_reason) || hold_reason == "") {
      return(list(success = FALSE, error = "hold_reason is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    record <- DBI::dbGetQuery(con, "
      SELECT record_id, status, legal_hold FROM retention_records
      WHERE record_id = ?
    ", params = list(record_id))

    if (nrow(record) == 0) {
      return(list(success = FALSE, error = "Record not found"))
    }

    if (record$legal_hold[1] == 1) {
      return(list(success = FALSE, error = "Record already on legal hold"))
    }

    if (record$status[1] %in% c("DELETED", "ANONYMIZED")) {
      return(list(success = FALSE,
                  error = "Cannot hold deleted or anonymized record"))
    }

    hold_start <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    previous_status <- record$status[1]

    DBI::dbExecute(con, "
      UPDATE retention_records
      SET legal_hold = 1, legal_hold_reason = ?,
          legal_hold_start = ?, legal_hold_end = ?,
          status = 'LEGAL_HOLD'
      WHERE record_id = ?
    ", params = list(
      hold_reason,
      hold_start,
      safe_scalar_retention(hold_end_date),
      record_id
    ))

    log_retention_action(
      record_id = record_id,
      action_type = "LEGAL_HOLD_APPLIED",
      previous_status = previous_status,
      new_status = "LEGAL_HOLD",
      action_reason = hold_reason,
      performed_by = held_by
    )

    list(
      success = TRUE,
      hold_start = hold_start,
      message = "Legal hold applied"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Release Legal Hold
#'
#' Releases a legal hold from a record.
#'
#' @param record_id Record ID
#' @param released_by User releasing hold
#' @param release_reason Reason for release
#'
#' @return List with success status
#' @export
release_legal_hold <- function(record_id, released_by, release_reason = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    record <- DBI::dbGetQuery(con, "
      SELECT record_id, legal_hold, retention_end_date
      FROM retention_records WHERE record_id = ?
    ", params = list(record_id))

    if (nrow(record) == 0) {
      return(list(success = FALSE, error = "Record not found"))
    }

    if (record$legal_hold[1] == 0) {
      return(list(success = FALSE, error = "Record not on legal hold"))
    }

    today <- Sys.Date()
    end_date <- as.Date(record$retention_end_date[1])
    new_status <- if (end_date < today) "EXPIRED" else "ACTIVE"

    DBI::dbExecute(con, "
      UPDATE retention_records
      SET legal_hold = 0, legal_hold_end = ?, status = ?
      WHERE record_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      new_status,
      record_id
    ))

    log_retention_action(
      record_id = record_id,
      action_type = "LEGAL_HOLD_RELEASED",
      previous_status = "LEGAL_HOLD",
      new_status = new_status,
      action_reason = release_reason,
      performed_by = released_by
    )

    list(
      success = TRUE,
      new_status = new_status,
      message = "Legal hold released"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# RETRIEVAL FUNCTIONS
# ============================================================================

#' Get Retention Record
#'
#' Retrieves a retention record by ID.
#'
#' @param record_id Record ID
#'
#' @return List with success status and record details
#' @export
get_retention_record <- function(record_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    record <- DBI::dbGetQuery(con, "
      SELECT r.*, p.policy_code, p.policy_name, p.action_on_expiry
      FROM retention_records r
      JOIN retention_policies p ON r.policy_id = p.policy_id
      WHERE r.record_id = ?
    ", params = list(record_id))

    if (nrow(record) == 0) {
      return(list(success = FALSE, error = "Record not found"))
    }

    list(success = TRUE, record = record)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Retention Action History
#'
#' Retrieves action history for a record.
#'
#' @param record_id Record ID
#'
#' @return List with success status and history
#' @export
get_retention_action_history <- function(record_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    actions <- DBI::dbGetQuery(con, "
      SELECT * FROM retention_actions
      WHERE record_id = ?
      ORDER BY action_id ASC
    ", params = list(record_id))

    list(success = TRUE, actions = actions, count = nrow(actions))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Subject Retention Records
#'
#' Gets all retention records for a subject.
#'
#' @param subject_id Subject ID
#' @param include_deleted Include deleted records
#'
#' @return List with success status and records
#' @export
get_subject_retention_records <- function(subject_id,
                                           include_deleted = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "
      SELECT r.*, p.policy_code, p.policy_name
      FROM retention_records r
      JOIN retention_policies p ON r.policy_id = p.policy_id
      WHERE r.subject_id = ?
    "

    if (!include_deleted) {
      query <- paste(query, "AND r.status NOT IN ('DELETED', 'ANONYMIZED')")
    }

    query <- paste(query, "ORDER BY r.retention_end_date")

    records <- DBI::dbGetQuery(con, query, params = list(subject_id))

    list(success = TRUE, records = records, count = nrow(records))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# STATISTICS AND REPORTING
# ============================================================================

#' Get Retention Statistics
#'
#' Returns comprehensive retention statistics.
#'
#' @return List with statistics
#' @export
get_retention_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    today <- format(Sys.Date(), "%Y-%m-%d")

    policy_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(is_active) as active
      FROM retention_policies
    ")

    record_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'ACTIVE' THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN status = 'EXPIRED' THEN 1 ELSE 0 END) as expired,
        SUM(CASE WHEN status = 'EXTENDED' THEN 1 ELSE 0 END) as extended,
        SUM(CASE WHEN status = 'LEGAL_HOLD' THEN 1 ELSE 0 END) as on_hold,
        SUM(CASE WHEN status = 'DELETED' THEN 1 ELSE 0 END) as deleted,
        SUM(CASE WHEN status = 'ANONYMIZED' THEN 1 ELSE 0 END) as anonymized
      FROM retention_records
    ")

    expired_pending <- DBI::dbGetQuery(con, "
      SELECT COUNT(*) as count
      FROM retention_records
      WHERE retention_end_date < ?
        AND status = 'ACTIVE'
        AND legal_hold = 0
    ", params = list(today))

    by_category <- DBI::dbGetQuery(con, "
      SELECT data_category, COUNT(*) as count,
             SUM(CASE WHEN status = 'ACTIVE' THEN 1 ELSE 0 END) as active
      FROM retention_records
      GROUP BY data_category
    ")

    list(
      success = TRUE,
      policies = as.list(policy_stats),
      records = as.list(record_stats),
      expired_pending_action = expired_pending$count[1],
      by_category = by_category,
      as_of_date = today
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Generate Retention Report
#'
#' Generates a data retention compliance report.
#'
#' @param output_file Output file path
#' @param format Report format: "txt" or "json"
#' @param organization Organization name
#' @param prepared_by Name of person preparing report
#'
#' @return List with success status
#' @export
generate_retention_report <- function(output_file,
                                       format = "txt",
                                       organization = "Organization",
                                       prepared_by = "DPO") {
  tryCatch({
    stats <- get_retention_statistics()
    if (!stats$success) {
      return(list(success = FALSE, error = "Failed to get statistics"))
    }

    policies <- get_retention_policies()
    expired <- get_expired_records()

    if (format == "json") {
      report_data <- list(
        report_type = "GDPR Article 5(1)(e) Data Retention Report",
        organization = organization,
        prepared_by = prepared_by,
        generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        statistics = stats,
        policies = policies$policies,
        expired_records = expired$records
      )
      writeLines(
        jsonlite::toJSON(report_data, pretty = TRUE, auto_unbox = TRUE),
        output_file
      )
    } else {
      lines <- c(
        "===============================================================================",
        "         GDPR ARTICLE 5(1)(e) - DATA RETENTION REPORT",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Prepared by:", prepared_by),
        paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        "",
        "-------------------------------------------------------------------------------",
        "RETENTION POLICIES",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Policies:", stats$policies$total),
        paste("  - Active:", stats$policies$active),
        "",
        "-------------------------------------------------------------------------------",
        "RETENTION RECORDS",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Records:", stats$records$total),
        paste("  - Active:", stats$records$active),
        paste("  - Expired (pending action):", stats$expired_pending_action),
        paste("  - Extended:", stats$records$extended),
        paste("  - On Legal Hold:", stats$records$on_hold),
        paste("  - Deleted:", stats$records$deleted),
        paste("  - Anonymized:", stats$records$anonymized),
        "",
        "-------------------------------------------------------------------------------",
        "BY DATA CATEGORY",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(stats$by_category) > 0) {
        for (i in seq_len(nrow(stats$by_category))) {
          lines <- c(lines,
            paste0("  ", stats$by_category$data_category[i], ": ",
                   stats$by_category$count[i], " records (",
                   stats$by_category$active[i], " active)"))
        }
      }

      lines <- c(lines, "",
        "-------------------------------------------------------------------------------",
        "GDPR ARTICLE 5(1)(e) COMPLIANCE NOTES",
        "-------------------------------------------------------------------------------",
        "",
        "Storage Limitation Principle:",
        "  - Personal data kept only as long as necessary",
        "  - Purpose of processing determines retention period",
        "  - Longer periods only for archiving in public interest",
        "",
        "Implementation Requirements:",
        "  - Define retention periods for each data category",
        "  - Regularly review and enforce retention policies",
        "  - Document retention decisions and legal bases",
        "  - Maintain audit trail of retention actions",
        "",
        "Legal Hold Protocol:",
        "  - Legal hold suspends normal retention enforcement",
        "  - Required for litigation, regulatory investigation",
        "  - Document reason and expected duration",
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
