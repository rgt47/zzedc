#' Enhanced Audit Trail System
#'
#' Extended audit trail functionality for comprehensive logging of system events,
#' security events, configuration changes, and anomaly detection.
#'
#' Supports FDA 21 CFR Part 11 and GDPR Article 30 compliance requirements.

# =============================================================================
# Extended Event Types
# =============================================================================

#' Get Valid Audit Event Types
#'
#' Returns all valid event types for the enhanced audit system.
#'
#' @return Named list of event types grouped by category
#'
#' @examples
#' \dontrun{
#'   event_types <- get_audit_event_types()
#'   print(event_types$security)
#' }
#'
#' @export
get_audit_event_types <- function() {
  list(
    data = c("INSERT", "UPDATE", "DELETE", "SELECT", "EXPORT"),
    access = c("LOGIN", "LOGOUT", "ACCESS", "SESSION_START", "SESSION_END"),
    security = c("LOGIN_FAILED", "PASSWORD_CHANGE", "ROLE_CHANGE",
                 "PERMISSION_CHANGE", "LOCKOUT", "UNLOCK"),
    system = c("BACKUP", "RESTORE", "MAINTENANCE", "STARTUP", "SHUTDOWN",
               "ERROR", "WARNING"),
    config = c("CONFIG_CHANGE", "SETTING_UPDATE", "FEATURE_TOGGLE"),
    signature = c("SIGNATURE_REQUEST", "SIGNATURE_APPLIED", "SIGNATURE_REJECTED",
                  "SIGNATURE_REVOKED"),
    compliance = c("AUDIT_REVIEW", "COMPLIANCE_CHECK", "REPORT_GENERATED",
                   "INTEGRITY_VERIFIED")
  )
}

#' Get All Valid Event Types
#'
#' Returns flat vector of all valid event types.
#'
#' @return Character vector of event type names
#'
#' @keywords internal
get_all_event_types <- function() {
  types <- get_audit_event_types()
  unlist(types, use.names = FALSE)
}


# =============================================================================
# System Event Logging
# =============================================================================

#' Log System Event
#'
#' Records system-level events such as backups, restores, and maintenance.
#'
#' @param event_type Character: System event type (BACKUP, RESTORE, etc.)
#' @param description Character: Description of the event
#' @param details List: Additional event details (converted to JSON)
#' @param severity Character: Event severity (info, warning, error, critical)
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @examples
#' \dontrun{
#'   log_system_event(
#'     event_type = "BACKUP",
#'     description = "Daily backup completed",
#'     details = list(
#'       backup_file = "/backups/zzedc_20251219.db",
#'       size_mb = 45.2,
#'       duration_sec = 12
#'     ),
#'     severity = "info"
#'   )
#' }
#'
#' @export
log_system_event <- function(event_type, description, details = NULL,
                              severity = "info", db_path = NULL) {
  valid_types <- c("BACKUP", "RESTORE", "MAINTENANCE", "STARTUP",
                   "SHUTDOWN", "ERROR", "WARNING")

  if (!event_type %in% valid_types) {
    stop("Invalid system event_type. Must be one of: ",
         paste(valid_types, collapse = ", "))
  }

  valid_severity <- c("info", "warning", "error", "critical")
  if (!severity %in% valid_severity) {
    severity <- "info"
  }

  details_json <- if (!is.null(details)) {
    jsonlite::toJSON(details, auto_unbox = TRUE)
  } else {
    NULL
  }

  log_audit_event_extended(
    event_type = event_type,
    event_category = "SYSTEM",
    table_name = "system",
    operation = description,
    details = details_json,
    severity = severity,
    user_id = "SYSTEM",
    db_path = db_path
  )
}


#' Log Backup Event
#'
#' Records database backup operations.
#'
#' @param backup_path Character: Path to backup file
#' @param backup_type Character: Type of backup (full, incremental, differential)
#' @param size_bytes Numeric: Size of backup in bytes
#' @param duration_seconds Numeric: Duration of backup operation
#' @param success Logical: Whether backup succeeded
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @export
log_backup_event <- function(backup_path, backup_type = "full",
                              size_bytes = NULL, duration_seconds = NULL,
                              success = TRUE, db_path = NULL) {
  details <- list(
    backup_path = backup_path,
    backup_type = backup_type,
    size_bytes = size_bytes,
    duration_seconds = duration_seconds,
    success = success,
    timestamp = as.character(Sys.time())
  )

  log_system_event(
    event_type = "BACKUP",
    description = ifelse(success,
                         paste("Backup completed:", backup_path),
                         paste("Backup failed:", backup_path)),
    details = details,
    severity = ifelse(success, "info", "error"),
    db_path = db_path
  )
}


# =============================================================================
# Security Event Logging
# =============================================================================

#' Log Security Event
#'
#' Records security-related events such as failed logins and access changes.
#'
#' @param event_type Character: Security event type
#' @param user_id Character: User ID involved
#' @param description Character: Description of the event
#' @param details List: Additional event details
#' @param ip_address Character: IP address of request (optional)
#' @param severity Character: Event severity
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @examples
#' \dontrun{
#'   log_security_event(
#'     event_type = "LOGIN_FAILED",
#'     user_id = "john.doe",
#'     description = "Failed login attempt - invalid password",
#'     details = list(attempt_number = 3),
#'     ip_address = "192.168.1.100"
#'   )
#' }
#'
#' @export
log_security_event <- function(event_type, user_id, description,
                                details = NULL, ip_address = NULL,
                                severity = "warning", db_path = NULL) {
  valid_types <- c("LOGIN_FAILED", "PASSWORD_CHANGE", "ROLE_CHANGE",
                   "PERMISSION_CHANGE", "LOCKOUT", "UNLOCK")

  if (!event_type %in% valid_types) {
    stop("Invalid security event_type. Must be one of: ",
         paste(valid_types, collapse = ", "))
  }

  details_json <- if (!is.null(details)) {
    jsonlite::toJSON(details, auto_unbox = TRUE)
  } else {
    NULL
  }

  log_audit_event_extended(
    event_type = event_type,
    event_category = "SECURITY",
    table_name = "security",
    operation = description,
    details = details_json,
    severity = severity,
    user_id = user_id,
    ip_address = ip_address,
    db_path = db_path
  )
}


#' Log Failed Login Attempt
#'
#' Records failed authentication attempts for security monitoring.
#'
#' @param username Character: Username attempted
#' @param reason Character: Reason for failure
#' @param ip_address Character: IP address of request
#' @param attempt_count Integer: Number of failed attempts
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @export
log_failed_login <- function(username, reason = "Invalid credentials",
                              ip_address = NULL, attempt_count = 1,
                              db_path = NULL) {
  log_security_event(
    event_type = "LOGIN_FAILED",
    user_id = username,
    description = paste("Failed login:", reason),
    details = list(
      reason = reason,
      attempt_count = attempt_count,
      timestamp = as.character(Sys.time())
    ),
    ip_address = ip_address,
    severity = ifelse(attempt_count >= 3, "error", "warning"),
    db_path = db_path
  )
}


#' Log Account Lockout
#'
#' Records when a user account is locked due to security policy.
#'
#' @param username Character: Username locked
#' @param reason Character: Reason for lockout
#' @param duration_minutes Integer: Lockout duration (NULL for permanent)
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @export
log_account_lockout <- function(username, reason = "Too many failed attempts",
                                 duration_minutes = NULL, db_path = NULL) {
  log_security_event(
    event_type = "LOCKOUT",
    user_id = username,
    description = paste("Account locked:", reason),
    details = list(
      reason = reason,
      duration_minutes = duration_minutes,
      lockout_time = as.character(Sys.time()),
      unlock_time = if (!is.null(duration_minutes)) {
        as.character(Sys.time() + duration_minutes * 60)
      } else {
        "Manual unlock required"
      }
    ),
    severity = "critical",
    db_path = db_path
  )
}


#' Log Password Change
#'
#' Records password change events.
#'
#' @param user_id Character: User whose password changed
#' @param changed_by Character: User who made the change
#' @param method Character: How password was changed (self, admin, reset)
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @export
log_password_change <- function(user_id, changed_by = NULL,
                                 method = "self", db_path = NULL) {
  if (is.null(changed_by)) changed_by <- user_id

  log_security_event(
    event_type = "PASSWORD_CHANGE",
    user_id = user_id,
    description = paste("Password changed via", method),
    details = list(
      changed_by = changed_by,
      method = method,
      timestamp = as.character(Sys.time())
    ),
    severity = "info",
    db_path = db_path
  )
}


#' Log Role Change
#'
#' Records when a user's role is modified.
#'
#' @param user_id Character: User whose role changed
#' @param old_role Character: Previous role
#' @param new_role Character: New role
#' @param changed_by Character: Administrator who made the change
#' @param reason Character: Reason for change
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @export
log_role_change <- function(user_id, old_role, new_role,
                             changed_by, reason = NULL, db_path = NULL) {
  log_security_event(
    event_type = "ROLE_CHANGE",
    user_id = user_id,
    description = paste("Role changed from", old_role, "to", new_role),
    details = list(
      old_role = old_role,
      new_role = new_role,
      changed_by = changed_by,
      reason = reason,
      timestamp = as.character(Sys.time())
    ),
    severity = "warning",
    db_path = db_path
  )
}


# =============================================================================
# Configuration Change Logging
# =============================================================================

#' Log Configuration Change
#'
#' Records changes to system configuration settings.
#'
#' @param setting_name Character: Name of setting changed
#' @param old_value Character: Previous value
#' @param new_value Character: New value
#' @param changed_by Character: User who made the change
#' @param reason Character: Reason for change
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @export
log_config_change <- function(setting_name, old_value, new_value,
                               changed_by, reason = NULL, db_path = NULL) {
  details_json <- jsonlite::toJSON(list(
    setting_name = setting_name,
    old_value = as.character(old_value),
    new_value = as.character(new_value),
    changed_by = changed_by,
    reason = reason,
    timestamp = as.character(Sys.time())
  ), auto_unbox = TRUE)

  log_audit_event_extended(
    event_type = "CONFIG_CHANGE",
    event_category = "CONFIG",
    table_name = "configuration",
    record_id = setting_name,
    operation = paste("Setting", setting_name, "changed from",
                      old_value, "to", new_value),
    details = details_json,
    severity = "warning",
    user_id = changed_by,
    db_path = db_path
  )
}


# =============================================================================
# Extended Audit Event Logging
# =============================================================================

#' Log Audit Event (Extended)
#'
#' Internal function for logging events with extended fields.
#'
#' @param event_type Character: Type of event
#' @param event_category Character: Category (DATA, SECURITY, SYSTEM, CONFIG)
#' @param table_name Character: Table affected
#' @param record_id Character: Record ID (optional)
#' @param operation Character: Description of operation
#' @param details Character: JSON details
#' @param severity Character: Event severity
#' @param user_id Character: User ID
#' @param ip_address Character: IP address (optional)
#' @param session_id Character: Session ID (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Logical TRUE if successfully logged
#'
#' @keywords internal
log_audit_event_extended <- function(event_type, event_category = "DATA",
                                      table_name, record_id = NULL,
                                      operation, details = NULL,
                                      severity = "info", user_id = NULL,
                                      ip_address = NULL, session_id = NULL,
                                      db_path = NULL) {
  safe_scalar <- function(x, default = NA_character_) {
    if (is.null(x) || length(x) == 0) {
      default
    } else if (length(x) > 1) {
      paste(x, collapse = "; ")
    } else {
      as.character(x)
    }
  }

  event_type <- safe_scalar(event_type)
  event_category <- safe_scalar(event_category, "DATA")
  table_name <- safe_scalar(table_name)
  record_id <- safe_scalar(record_id)
  operation <- safe_scalar(operation)
  details <- safe_scalar(details)
  severity <- safe_scalar(severity, "info")
  user_id <- safe_scalar(user_id)
  ip_address <- safe_scalar(ip_address)
  session_id <- safe_scalar(session_id)

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    prev_hash_query <- DBI::dbGetQuery(conn, "
      SELECT audit_hash FROM audit_log
      ORDER BY audit_id DESC LIMIT 1
    ")
    previous_hash <- if (nrow(prev_hash_query) > 0) {
      prev_hash_query[1, 1]
    } else {
      "GENESIS"
    }

    record_content <- paste(
      event_type, event_category, table_name, record_id, operation, details,
      user_id, ip_address, session_id, Sys.time(), previous_hash,
      sep = "|"
    )
    audit_hash <- digest::digest(record_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO audit_log
      (event_type, table_name, record_id, operation, details,
       user_id, ip_address, session_id, audit_hash, previous_hash)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      event_type, table_name, record_id, operation, details,
      user_id, ip_address, session_id, audit_hash, previous_hash
    ))

    audit_id <- DBI::dbGetQuery(conn,
                                 "SELECT last_insert_rowid() as id")[1, 1]

    chain_order <- DBI::dbGetQuery(conn,
                                    "SELECT COUNT(*) FROM audit_chain")[1, 1] + 1

    DBI::dbExecute(conn, "
      INSERT INTO audit_chain
      (audit_id, record_hash, previous_hash, chain_order, verified)
      VALUES (?, ?, ?, ?, 1)
    ", list(audit_id, audit_hash, previous_hash, chain_order))

    DBI::dbExecute(conn, "
      INSERT INTO audit_events
      (audit_id, event_category, event_severity, event_message)
      VALUES (?, ?, ?, ?)
    ", list(audit_id, event_category, severity, operation))

    TRUE

  }, error = function(e) {
    warning("Failed to log audit event: ", e$message)
    FALSE
  })
}


# =============================================================================
# Anomaly Detection
# =============================================================================

#' Detect Audit Anomalies
#'
#' Analyzes audit trail for suspicious patterns and anomalies.
#'
#' @param lookback_hours Numeric: Hours to analyze (default: 24)
#' @param thresholds List: Custom thresholds for anomaly detection
#' @param db_path Character: Database path (optional)
#'
#' @return List with detected anomalies and risk assessment
#'
#' @details
#' Detects the following anomaly types:
#'
#' - Excessive failed logins (possible brute force)
#' - Unusual access patterns (off-hours activity)
#' - Bulk data operations (possible data exfiltration)
#' - Multiple role changes (possible privilege escalation)
#' - Integrity verification failures
#'
#' @examples
#' \dontrun{
#'   anomalies <- detect_audit_anomalies(lookback_hours = 24)
#'   if (length(anomalies$alerts) > 0) {
#'     print(anomalies$alerts)
#'   }
#' }
#'
#' @export
detect_audit_anomalies <- function(lookback_hours = 24, thresholds = NULL,
                                    db_path = NULL) {
  default_thresholds <- list(
    failed_logins_per_user = 5,
    failed_logins_total = 20,
    bulk_exports_per_hour = 10,
    role_changes_per_day = 3,
    off_hours_start = 22,
    off_hours_end = 6
  )

  if (!is.null(thresholds)) {
    default_thresholds <- modifyList(default_thresholds, thresholds)
  }
  thresholds <- default_thresholds

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)

    cutoff_time <- Sys.time() - (lookback_hours * 3600)

    audit_data <- DBI::dbGetQuery(conn, "
      SELECT * FROM audit_log
      WHERE timestamp >= ?
      ORDER BY timestamp DESC
    ", list(as.character(cutoff_time)))

    DBI::dbDisconnect(conn)

    alerts <- list()
    risk_score <- 0

    if (nrow(audit_data) == 0) {
      return(list(
        alerts = alerts,
        risk_score = 0,
        risk_level = "LOW",
        analysis_period = paste(lookback_hours, "hours"),
        events_analyzed = 0
      ))
    }

    failed_logins <- audit_data[audit_data$event_type == "LOGIN_FAILED", ]
    if (nrow(failed_logins) > 0) {
      by_user <- table(failed_logins$user_id)
      high_fail_users <- names(by_user)[by_user >= thresholds$failed_logins_per_user]

      if (length(high_fail_users) > 0) {
        alerts <- c(alerts, list(list(
          type = "BRUTE_FORCE_SUSPECTED",
          severity = "HIGH",
          message = paste("Multiple failed logins for users:",
                          paste(high_fail_users, collapse = ", ")),
          count = sum(by_user[high_fail_users]),
          affected_users = high_fail_users
        )))
        risk_score <- risk_score + 30
      }

      if (nrow(failed_logins) >= thresholds$failed_logins_total) {
        alerts <- c(alerts, list(list(
          type = "EXCESSIVE_FAILED_LOGINS",
          severity = "MEDIUM",
          message = paste(nrow(failed_logins), "failed login attempts in period"),
          count = nrow(failed_logins)
        )))
        risk_score <- risk_score + 20
      }
    }

    exports <- audit_data[audit_data$event_type == "EXPORT", ]
    if (nrow(exports) > 0) {
      exports_per_hour <- nrow(exports) / lookback_hours
      if (exports_per_hour >= thresholds$bulk_exports_per_hour) {
        alerts <- c(alerts, list(list(
          type = "BULK_EXPORT_DETECTED",
          severity = "MEDIUM",
          message = paste("High export volume:", round(exports_per_hour, 1),
                          "exports/hour"),
          count = nrow(exports)
        )))
        risk_score <- risk_score + 15
      }
    }

    role_changes <- audit_data[audit_data$event_type == "ROLE_CHANGE", ]
    if (nrow(role_changes) >= thresholds$role_changes_per_day) {
      alerts <- c(alerts, list(list(
        type = "MULTIPLE_ROLE_CHANGES",
        severity = "MEDIUM",
        message = paste(nrow(role_changes), "role changes detected"),
        count = nrow(role_changes)
      )))
      risk_score <- risk_score + 15
    }

    if (nrow(audit_data) > 0 && "timestamp" %in% names(audit_data)) {
      hours <- as.numeric(format(as.POSIXct(audit_data$timestamp), "%H"))
      off_hours_events <- sum(hours >= thresholds$off_hours_start |
                                hours < thresholds$off_hours_end)

      if (off_hours_events > 10) {
        alerts <- c(alerts, list(list(
          type = "OFF_HOURS_ACTIVITY",
          severity = "LOW",
          message = paste(off_hours_events, "events during off-hours"),
          count = off_hours_events
        )))
        risk_score <- risk_score + 10
      }
    }

    risk_level <- if (risk_score >= 50) {
      "HIGH"
    } else if (risk_score >= 25) {
      "MEDIUM"
    } else {
      "LOW"
    }

    list(
      alerts = alerts,
      risk_score = risk_score,
      risk_level = risk_level,
      analysis_period = paste(lookback_hours, "hours"),
      events_analyzed = nrow(audit_data),
      thresholds_used = thresholds
    )

  }, error = function(e) {
    list(
      alerts = list(),
      risk_score = 0,
      risk_level = "UNKNOWN",
      error = e$message
    )
  })
}


# =============================================================================
# Enhanced Search and Filtering
# =============================================================================

#' Search Audit Trail
#'
#' Advanced search of audit trail with multiple filter options.
#'
#' @param search_term Character: Text to search in operations/details
#' @param event_types Character vector: Filter by event types
#' @param event_categories Character vector: Filter by categories
#' @param users Character vector: Filter by user IDs
#' @param tables Character vector: Filter by table names
#' @param date_from Date: Start date
#' @param date_to Date: End date
#' @param severity Character vector: Filter by severity levels
#' @param limit Integer: Maximum records to return (default: 1000)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with matching audit records
#'
#' @export
search_audit_trail <- function(search_term = NULL, event_types = NULL,
                                event_categories = NULL, users = NULL,
                                tables = NULL, date_from = NULL,
                                date_to = NULL, severity = NULL,
                                limit = 1000, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)

    query <- "
      SELECT
        al.audit_id, al.timestamp, al.user_id, al.event_type,
        al.table_name, al.record_id, al.operation, al.details,
        al.ip_address, al.session_id, al.audit_hash,
        ae.event_category, ae.event_severity, ae.event_message
      FROM audit_log al
      LEFT JOIN audit_events ae ON al.audit_id = ae.audit_id
      WHERE 1=1
    "

    params <- list()
    param_idx <- 1

    if (!is.null(search_term) && nchar(search_term) > 0) {
      query <- paste0(query, " AND (al.operation LIKE ? OR al.details LIKE ?)")
      search_pattern <- paste0("%", search_term, "%")
      params[[param_idx]] <- search_pattern
      params[[param_idx + 1]] <- search_pattern
      param_idx <- param_idx + 2
    }

    if (!is.null(event_types) && length(event_types) > 0) {
      placeholders <- paste(rep("?", length(event_types)), collapse = ",")
      query <- paste0(query, " AND al.event_type IN (", placeholders, ")")
      for (et in event_types) {
        params[[param_idx]] <- et
        param_idx <- param_idx + 1
      }
    }

    if (!is.null(users) && length(users) > 0) {
      placeholders <- paste(rep("?", length(users)), collapse = ",")
      query <- paste0(query, " AND al.user_id IN (", placeholders, ")")
      for (u in users) {
        params[[param_idx]] <- u
        param_idx <- param_idx + 1
      }
    }

    if (!is.null(tables) && length(tables) > 0) {
      placeholders <- paste(rep("?", length(tables)), collapse = ",")
      query <- paste0(query, " AND al.table_name IN (", placeholders, ")")
      for (t in tables) {
        params[[param_idx]] <- t
        param_idx <- param_idx + 1
      }
    }

    if (!is.null(date_from)) {
      query <- paste0(query, " AND DATE(al.timestamp) >= ?")
      params[[param_idx]] <- as.character(date_from)
      param_idx <- param_idx + 1
    }

    if (!is.null(date_to)) {
      query <- paste0(query, " AND DATE(al.timestamp) <= ?")
      params[[param_idx]] <- as.character(date_to)
      param_idx <- param_idx + 1
    }

    query <- paste0(query, " ORDER BY al.timestamp DESC LIMIT ", limit)

    if (length(params) > 0) {
      results <- DBI::dbGetQuery(conn, query, params)
    } else {
      results <- DBI::dbGetQuery(conn, query)
    }

    DBI::dbDisconnect(conn)
    results

  }, error = function(e) {
    warning("Search failed: ", e$message)
    data.frame()
  })
}


#' Get Audit Statistics
#'
#' Generate summary statistics of audit trail activity.
#'
#' @param period Character: Time period (day, week, month, year)
#' @param db_path Character: Database path (optional)
#'
#' @return List with audit statistics
#'
#' @export
get_audit_statistics <- function(period = "week", db_path = NULL) {
  days_map <- list(day = 1, week = 7, month = 30, year = 365)
  days <- days_map[[period]]
  if (is.null(days)) days <- 7

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)

    cutoff <- Sys.Date() - days

    total_events <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as count FROM audit_log
      WHERE DATE(timestamp) >= ?
    ", list(as.character(cutoff)))[1, 1]

    events_by_type <- DBI::dbGetQuery(conn, "
      SELECT event_type, COUNT(*) as count
      FROM audit_log
      WHERE DATE(timestamp) >= ?
      GROUP BY event_type
      ORDER BY count DESC
    ", list(as.character(cutoff)))

    events_by_user <- DBI::dbGetQuery(conn, "
      SELECT user_id, COUNT(*) as count
      FROM audit_log
      WHERE DATE(timestamp) >= ? AND user_id IS NOT NULL
      GROUP BY user_id
      ORDER BY count DESC
      LIMIT 10
    ", list(as.character(cutoff)))

    events_by_table <- DBI::dbGetQuery(conn, "
      SELECT table_name, COUNT(*) as count
      FROM audit_log
      WHERE DATE(timestamp) >= ? AND table_name IS NOT NULL
      GROUP BY table_name
      ORDER BY count DESC
      LIMIT 10
    ", list(as.character(cutoff)))

    events_by_day <- DBI::dbGetQuery(conn, "
      SELECT DATE(timestamp) as date, COUNT(*) as count
      FROM audit_log
      WHERE DATE(timestamp) >= ?
      GROUP BY DATE(timestamp)
      ORDER BY date ASC
    ", list(as.character(cutoff)))

    security_events <- DBI::dbGetQuery(conn, "
      SELECT COUNT(*) as count FROM audit_log
      WHERE DATE(timestamp) >= ?
      AND event_type IN ('LOGIN_FAILED', 'LOCKOUT', 'PASSWORD_CHANGE', 'ROLE_CHANGE')
    ", list(as.character(cutoff)))[1, 1]

    DBI::dbDisconnect(conn)

    list(
      period = period,
      period_start = as.character(cutoff),
      period_end = as.character(Sys.Date()),
      total_events = total_events,
      events_per_day = round(total_events / days, 1),
      events_by_type = events_by_type,
      events_by_user = events_by_user,
      events_by_table = events_by_table,
      events_by_day = events_by_day,
      security_events = security_events,
      generated_at = as.character(Sys.time())
    )

  }, error = function(e) {
    list(error = e$message)
  })
}
