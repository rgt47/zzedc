#' Breach Notification Workflow (Feature #29)
#'
#' GDPR Articles 33-34 compliant breach detection, assessment,
#' notification, and documentation system.
#'
#' @name breach_notification
#' @docType package
NULL

#' @keywords internal
safe_scalar_bn <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize Breach Notification System
#' @return List with success status
#' @export
init_breach_notification <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS breach_incidents (
        incident_id INTEGER PRIMARY KEY AUTOINCREMENT,
        incident_code TEXT UNIQUE NOT NULL,
        incident_title TEXT NOT NULL,
        breach_type TEXT NOT NULL,
        severity TEXT NOT NULL,
        status TEXT DEFAULT 'DETECTED',
        detected_at TEXT DEFAULT (datetime('now')),
        detected_by TEXT NOT NULL,
        breach_start TEXT,
        breach_end TEXT,
        description TEXT NOT NULL,
        data_categories_affected TEXT,
        subjects_affected INTEGER DEFAULT 0,
        records_affected INTEGER DEFAULT 0,
        root_cause TEXT,
        containment_measures TEXT,
        remediation_actions TEXT,
        dpo_notified INTEGER DEFAULT 0,
        dpo_notified_at TEXT,
        authority_notification_required INTEGER,
        authority_notified INTEGER DEFAULT 0,
        authority_notified_at TEXT,
        authority_reference TEXT,
        subject_notification_required INTEGER,
        subjects_notified INTEGER DEFAULT 0,
        subjects_notified_at TEXT,
        closed_at TEXT,
        closed_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS breach_timeline (
        timeline_id INTEGER PRIMARY KEY AUTOINCREMENT,
        incident_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        event_description TEXT NOT NULL,
        event_timestamp TEXT DEFAULT (datetime('now')),
        recorded_by TEXT NOT NULL,
        FOREIGN KEY (incident_id) REFERENCES breach_incidents(incident_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS breach_notifications (
        notification_id INTEGER PRIMARY KEY AUTOINCREMENT,
        incident_id INTEGER NOT NULL,
        notification_type TEXT NOT NULL,
        recipient_type TEXT NOT NULL,
        recipient_details TEXT,
        notification_method TEXT,
        notification_content TEXT,
        sent_at TEXT DEFAULT (datetime('now')),
        sent_by TEXT NOT NULL,
        acknowledgement_received INTEGER DEFAULT 0,
        acknowledgement_at TEXT,
        FOREIGN KEY (incident_id) REFERENCES breach_incidents(incident_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS breach_risk_assessment (
        assessment_id INTEGER PRIMARY KEY AUTOINCREMENT,
        incident_id INTEGER NOT NULL,
        risk_factor TEXT NOT NULL,
        risk_level TEXT NOT NULL,
        risk_description TEXT,
        assessed_by TEXT NOT NULL,
        assessed_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (incident_id) REFERENCES breach_incidents(incident_id)
      )
    ")

    list(success = TRUE, message = "Breach notification system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Breach Types
#' @return Named character vector
#' @export
get_breach_types <- function() {
  c(
    CONFIDENTIALITY = "Unauthorized disclosure or access",
    INTEGRITY = "Unauthorized alteration of data",
    AVAILABILITY = "Loss of access to data",
    COMBINED = "Multiple breach types"
  )
}

#' Get Breach Severities
#' @return Named character vector
#' @export
get_breach_severities <- function() {
  c(
    CRITICAL = "Immediate high risk to individuals",
    HIGH = "Significant risk requiring urgent action",
    MEDIUM = "Moderate risk requiring assessment",
    LOW = "Limited risk with minimal impact"
  )
}

#' Get Breach Statuses
#' @return Named character vector
#' @export
get_breach_statuses <- function() {
  c(
    DETECTED = "Breach detected",
    INVESTIGATING = "Investigation in progress",
    CONTAINED = "Breach contained",
    ASSESSING_RISK = "Risk assessment in progress",
    NOTIFYING = "Notifications in progress",
    REMEDIATING = "Remediation in progress",
    CLOSED = "Incident closed"
  )
}

#' Report Breach Incident
#' @param incident_title Title
#' @param breach_type Type
#' @param severity Severity
#' @param description Description
#' @param detected_by User detecting
#' @param breach_start When breach started
#' @param data_categories_affected Categories affected
#' @param subjects_affected Number of subjects
#' @param records_affected Number of records
#' @return List with success status
#' @export
report_breach_incident <- function(incident_title, breach_type, severity,
                                    description, detected_by,
                                    breach_start = NULL,
                                    data_categories_affected = NULL,
                                    subjects_affected = 0,
                                    records_affected = 0) {
  tryCatch({
    if (missing(incident_title) || incident_title == "") {
      return(list(success = FALSE, error = "incident_title is required"))
    }

    valid_types <- names(get_breach_types())
    if (!breach_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid breach_type:", breach_type)))
    }

    valid_severities <- names(get_breach_severities())
    if (!severity %in% valid_severities) {
      return(list(success = FALSE,
                  error = paste("Invalid severity:", severity)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    incident_code <- paste0("BRE-", format(Sys.time(), "%Y%m%d-%H%M%S"))

    DBI::dbExecute(con, "
      INSERT INTO breach_incidents (
        incident_code, incident_title, breach_type, severity, description,
        detected_by, breach_start, data_categories_affected,
        subjects_affected, records_affected
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      incident_code, incident_title, breach_type, severity, description,
      detected_by, safe_scalar_bn(breach_start),
      safe_scalar_bn(data_categories_affected),
      as.integer(subjects_affected), as.integer(records_affected)
    ))

    incident_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    DBI::dbExecute(con, "
      INSERT INTO breach_timeline (
        incident_id, event_type, event_description, recorded_by
      ) VALUES (?, 'DETECTION', 'Breach incident reported', ?)
    ", params = list(incident_id, detected_by))

    list(success = TRUE, incident_id = incident_id,
         incident_code = incident_code)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update Breach Status
#' @param incident_id Incident ID
#' @param new_status New status
#' @param updated_by User updating
#' @param notes Optional notes
#' @return List with success status
#' @export
update_breach_status <- function(incident_id, new_status, updated_by,
                                  notes = NULL) {
  tryCatch({
    valid_statuses <- names(get_breach_statuses())
    if (!new_status %in% valid_statuses) {
      return(list(success = FALSE, error = "Invalid status"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE breach_incidents SET status = ?
      WHERE incident_id = ?
    ", params = list(new_status, incident_id))

    event_desc <- paste("Status changed to", new_status)
    if (!is.null(notes)) event_desc <- paste(event_desc, "-", notes)

    DBI::dbExecute(con, "
      INSERT INTO breach_timeline (
        incident_id, event_type, event_description, recorded_by
      ) VALUES (?, 'STATUS_CHANGE', ?, ?)
    ", params = list(incident_id, event_desc, updated_by))

    if (new_status == "CLOSED") {
      DBI::dbExecute(con, "
        UPDATE breach_incidents SET closed_at = ?, closed_by = ?
        WHERE incident_id = ?
      ", params = list(
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"), updated_by, incident_id
      ))
    }

    list(success = TRUE, message = "Status updated")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Notify DPO
#' @param incident_id Incident ID
#' @param notified_by User notifying
#' @return List with success status
#' @export
notify_dpo <- function(incident_id, notified_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE breach_incidents
      SET dpo_notified = 1, dpo_notified_at = ?
      WHERE incident_id = ?
    ", params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), incident_id))

    DBI::dbExecute(con, "
      INSERT INTO breach_timeline (
        incident_id, event_type, event_description, recorded_by
      ) VALUES (?, 'DPO_NOTIFICATION', 'DPO notified of breach', ?)
    ", params = list(incident_id, notified_by))

    list(success = TRUE, message = "DPO notified")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Assess Authority Notification Requirement
#' @param incident_id Incident ID
#' @param requires_notification Whether notification required
#' @param assessed_by User assessing
#' @param justification Justification
#' @return List with success status
#' @export
assess_authority_notification <- function(incident_id, requires_notification,
                                           assessed_by, justification = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE breach_incidents
      SET authority_notification_required = ?
      WHERE incident_id = ?
    ", params = list(as.integer(requires_notification), incident_id))

    event_desc <- if (requires_notification) {
      "Authority notification assessed as REQUIRED"
    } else {
      "Authority notification assessed as NOT REQUIRED"
    }
    if (!is.null(justification)) {
      event_desc <- paste(event_desc, "-", justification)
    }

    DBI::dbExecute(con, "
      INSERT INTO breach_timeline (
        incident_id, event_type, event_description, recorded_by
      ) VALUES (?, 'AUTHORITY_ASSESSMENT', ?, ?)
    ", params = list(incident_id, event_desc, assessed_by))

    list(success = TRUE, requires_notification = requires_notification)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Notify Supervisory Authority
#' @param incident_id Incident ID
#' @param notified_by User notifying
#' @param authority_reference Reference number
#' @param notification_content Content sent
#' @return List with success status
#' @export
notify_supervisory_authority <- function(incident_id, notified_by,
                                          authority_reference = NULL,
                                          notification_content = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE breach_incidents
      SET authority_notified = 1, authority_notified_at = ?,
          authority_reference = ?
      WHERE incident_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      safe_scalar_bn(authority_reference), incident_id
    ))

    DBI::dbExecute(con, "
      INSERT INTO breach_notifications (
        incident_id, notification_type, recipient_type, notification_content,
        sent_by
      ) VALUES (?, 'AUTHORITY', 'SUPERVISORY_AUTHORITY', ?, ?)
    ", params = list(
      incident_id, safe_scalar_bn(notification_content), notified_by
    ))

    DBI::dbExecute(con, "
      INSERT INTO breach_timeline (
        incident_id, event_type, event_description, recorded_by
      ) VALUES (?, 'AUTHORITY_NOTIFICATION', 'Supervisory authority notified', ?)
    ", params = list(incident_id, notified_by))

    list(success = TRUE, message = "Supervisory authority notified")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Assess Subject Notification Requirement
#' @param incident_id Incident ID
#' @param requires_notification Whether notification required
#' @param assessed_by User assessing
#' @param justification Justification
#' @return List with success status
#' @export
assess_subject_notification <- function(incident_id, requires_notification,
                                          assessed_by, justification = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE breach_incidents
      SET subject_notification_required = ?
      WHERE incident_id = ?
    ", params = list(as.integer(requires_notification), incident_id))

    event_desc <- if (requires_notification) {
      "Subject notification assessed as REQUIRED"
    } else {
      "Subject notification assessed as NOT REQUIRED"
    }
    if (!is.null(justification)) {
      event_desc <- paste(event_desc, "-", justification)
    }

    DBI::dbExecute(con, "
      INSERT INTO breach_timeline (
        incident_id, event_type, event_description, recorded_by
      ) VALUES (?, 'SUBJECT_ASSESSMENT', ?, ?)
    ", params = list(incident_id, event_desc, assessed_by))

    list(success = TRUE, requires_notification = requires_notification)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Notify Data Subjects
#' @param incident_id Incident ID
#' @param notified_by User notifying
#' @param subjects_notified Number notified
#' @param notification_method Method used
#' @param notification_content Content sent
#' @return List with success status
#' @export
notify_data_subjects <- function(incident_id, notified_by, subjects_notified,
                                  notification_method = NULL,
                                  notification_content = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE breach_incidents
      SET subjects_notified = ?, subjects_notified_at = ?
      WHERE incident_id = ?
    ", params = list(
      as.integer(subjects_notified),
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"), incident_id
    ))

    DBI::dbExecute(con, "
      INSERT INTO breach_notifications (
        incident_id, notification_type, recipient_type, notification_method,
        notification_content, sent_by
      ) VALUES (?, 'SUBJECT', 'DATA_SUBJECTS', ?, ?, ?)
    ", params = list(
      incident_id, safe_scalar_bn(notification_method),
      safe_scalar_bn(notification_content), notified_by
    ))

    DBI::dbExecute(con, "
      INSERT INTO breach_timeline (
        incident_id, event_type, event_description, recorded_by
      ) VALUES (?, 'SUBJECT_NOTIFICATION', ?, ?)
    ", params = list(
      incident_id, paste(subjects_notified, "data subjects notified"),
      notified_by
    ))

    list(success = TRUE, message = "Data subjects notified")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Risk Assessment
#' @param incident_id Incident ID
#' @param risk_factor Risk factor
#' @param risk_level Level
#' @param assessed_by User assessing
#' @param risk_description Description
#' @return List with success status
#' @export
add_breach_risk_assessment <- function(incident_id, risk_factor, risk_level,
                                        assessed_by, risk_description = NULL) {
  tryCatch({
    valid_levels <- names(get_breach_severities())
    if (!risk_level %in% valid_levels) {
      return(list(success = FALSE, error = "Invalid risk_level"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO breach_risk_assessment (
        incident_id, risk_factor, risk_level, risk_description, assessed_by
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(
      incident_id, risk_factor, risk_level,
      safe_scalar_bn(risk_description), assessed_by
    ))

    list(success = TRUE, message = "Risk assessment added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Timeline Event
#' @param incident_id Incident ID
#' @param event_type Event type
#' @param event_description Description
#' @param recorded_by User recording
#' @return List with success status
#' @export
add_timeline_event <- function(incident_id, event_type, event_description,
                                recorded_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO breach_timeline (
        incident_id, event_type, event_description, recorded_by
      ) VALUES (?, ?, ?, ?)
    ", params = list(incident_id, event_type, event_description, recorded_by))

    list(success = TRUE, message = "Timeline event added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Breach Timeline
#' @param incident_id Incident ID
#' @return List with timeline
#' @export
get_breach_timeline <- function(incident_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    timeline <- DBI::dbGetQuery(con, "
      SELECT * FROM breach_timeline
      WHERE incident_id = ?
      ORDER BY event_timestamp
    ", params = list(incident_id))

    list(success = TRUE, timeline = timeline, count = nrow(timeline))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Breach Incident
#' @param incident_id Incident ID
#' @return List with incident details
#' @export
get_breach_incident <- function(incident_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    incident <- DBI::dbGetQuery(con, "
      SELECT * FROM breach_incidents WHERE incident_id = ?
    ", params = list(incident_id))

    if (nrow(incident) == 0) {
      return(list(success = FALSE, error = "Incident not found"))
    }

    timeline <- DBI::dbGetQuery(con, "
      SELECT * FROM breach_timeline WHERE incident_id = ?
      ORDER BY event_timestamp
    ", params = list(incident_id))

    notifications <- DBI::dbGetQuery(con, "
      SELECT * FROM breach_notifications WHERE incident_id = ?
    ", params = list(incident_id))

    risks <- DBI::dbGetQuery(con, "
      SELECT * FROM breach_risk_assessment WHERE incident_id = ?
    ", params = list(incident_id))

    list(
      success = TRUE,
      incident = as.list(incident),
      timeline = timeline,
      notifications = notifications,
      risk_assessments = risks
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Breach Incidents List
#' @param status Optional status filter
#' @param severity Optional severity filter
#' @return List with incidents
#' @export
get_breach_incidents <- function(status = NULL, severity = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM breach_incidents WHERE 1=1"
    params <- list()

    if (!is.null(status)) {
      query <- paste(query, "AND status = ?")
      params <- append(params, list(status))
    }
    if (!is.null(severity)) {
      query <- paste(query, "AND severity = ?")
      params <- append(params, list(severity))
    }

    query <- paste(query, "ORDER BY detected_at DESC")

    if (length(params) > 0) {
      incidents <- DBI::dbGetQuery(con, query, params = params)
    } else {
      incidents <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, incidents = incidents, count = nrow(incidents))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Breach Statistics
#' @return List with statistics
#' @export
get_breach_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_incidents,
        SUM(CASE WHEN status = 'CLOSED' THEN 1 ELSE 0 END) as closed,
        SUM(CASE WHEN status != 'CLOSED' THEN 1 ELSE 0 END) as open,
        SUM(authority_notified) as authority_notifications,
        SUM(subjects_notified) as total_subjects_notified
      FROM breach_incidents
    ")

    by_severity <- DBI::dbGetQuery(con, "
      SELECT severity, COUNT(*) as count
      FROM breach_incidents
      GROUP BY severity
    ")

    by_type <- DBI::dbGetQuery(con, "
      SELECT breach_type, COUNT(*) as count
      FROM breach_incidents
      GROUP BY breach_type
    ")

    list(success = TRUE, statistics = as.list(stats),
         by_severity = by_severity, by_type = by_type)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Check 72-Hour Deadline
#' @param incident_id Incident ID
#' @return List with deadline status
#' @export
check_72_hour_deadline <- function(incident_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    incident <- DBI::dbGetQuery(con, "
      SELECT detected_at, authority_notification_required, authority_notified,
             authority_notified_at
      FROM breach_incidents WHERE incident_id = ?
    ", params = list(incident_id))

    if (nrow(incident) == 0) {
      return(list(success = FALSE, error = "Incident not found"))
    }

    detected <- as.POSIXct(incident$detected_at[1])
    deadline <- detected + 72 * 3600
    now <- Sys.time()
    hours_remaining <- as.numeric(difftime(deadline, now, units = "hours"))

    list(
      success = TRUE,
      detected_at = incident$detected_at[1],
      deadline = format(deadline, "%Y-%m-%d %H:%M:%S"),
      hours_remaining = round(hours_remaining, 1),
      is_overdue = hours_remaining < 0,
      requires_notification = incident$authority_notification_required[1] == 1,
      already_notified = incident$authority_notified[1] == 1
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
