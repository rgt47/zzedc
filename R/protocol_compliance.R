#' Protocol Compliance Monitoring System
#'
#' FDA-compliant protocol adherence tracking including visit windows,
#' assessment completion, deviation detection, and eligibility enforcement.

# =============================================================================
# Helper Functions
# =============================================================================

#' Safe Scalar Conversion for Protocol
#'
#' @param x Value to convert
#' @param default Default value if NULL
#' @return Character scalar
#' @keywords internal
safe_scalar_proto <- function(x, default = NA_character_) {
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

#' Initialize Protocol Compliance System
#'
#' Creates database tables for protocol compliance monitoring.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with initialization results
#'
#' @export
init_protocol_compliance <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS protocol_definitions (
        protocol_id INTEGER PRIMARY KEY AUTOINCREMENT,
        protocol_code TEXT NOT NULL UNIQUE,
        protocol_title TEXT NOT NULL,
        protocol_version TEXT NOT NULL,
        effective_date DATE NOT NULL,
        expiration_date DATE,
        status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN
          ('DRAFT', 'ACTIVE', 'AMENDED', 'CLOSED')),
        sponsor TEXT,
        principal_investigator TEXT,
        description TEXT,
        created_by TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP,
        metadata TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS protocol_visits (
        visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
        protocol_id INTEGER NOT NULL REFERENCES protocol_definitions(protocol_id),
        visit_code TEXT NOT NULL,
        visit_name TEXT NOT NULL,
        visit_order INTEGER NOT NULL,
        target_day INTEGER NOT NULL,
        window_before INTEGER DEFAULT 0,
        window_after INTEGER DEFAULT 0,
        is_required BOOLEAN DEFAULT 1,
        visit_type TEXT DEFAULT 'SCHEDULED' CHECK(visit_type IN
          ('SCREENING', 'BASELINE', 'SCHEDULED', 'UNSCHEDULED', 'CLOSEOUT', 'FOLLOW_UP')),
        description TEXT,
        UNIQUE(protocol_id, visit_code)
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS protocol_assessments (
        assessment_id INTEGER PRIMARY KEY AUTOINCREMENT,
        protocol_id INTEGER NOT NULL REFERENCES protocol_definitions(protocol_id),
        visit_id INTEGER REFERENCES protocol_visits(visit_id),
        assessment_code TEXT NOT NULL,
        assessment_name TEXT NOT NULL,
        form_type TEXT,
        is_required BOOLEAN DEFAULT 1,
        completion_window_days INTEGER DEFAULT 0,
        description TEXT,
        UNIQUE(protocol_id, visit_id, assessment_code)
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS subject_visits (
        subject_visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id TEXT NOT NULL,
        protocol_id INTEGER NOT NULL REFERENCES protocol_definitions(protocol_id),
        visit_id INTEGER NOT NULL REFERENCES protocol_visits(visit_id),
        scheduled_date DATE,
        actual_date DATE,
        status TEXT NOT NULL DEFAULT 'SCHEDULED' CHECK(status IN
          ('SCHEDULED', 'COMPLETED', 'MISSED', 'CANCELLED', 'PARTIAL')),
        days_from_baseline INTEGER,
        window_status TEXT CHECK(window_status IN
          ('WITHIN_WINDOW', 'EARLY', 'LATE', 'OUTSIDE_WINDOW')),
        deviation_id INTEGER REFERENCES protocol_deviations(deviation_id),
        completed_by TEXT,
        completed_at TIMESTAMP,
        notes TEXT,
        UNIQUE(subject_id, protocol_id, visit_id)
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS protocol_deviations (
        deviation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        protocol_id INTEGER NOT NULL REFERENCES protocol_definitions(protocol_id),
        subject_id TEXT NOT NULL,
        deviation_type TEXT NOT NULL CHECK(deviation_type IN
          ('VISIT_TIMING', 'MISSED_VISIT', 'MISSED_ASSESSMENT',
           'ELIGIBILITY', 'DOSING', 'PROCEDURE', 'DOCUMENTATION', 'OTHER')),
        severity TEXT NOT NULL CHECK(severity IN
          ('MINOR', 'MAJOR', 'CRITICAL')),
        deviation_date DATE NOT NULL,
        description TEXT NOT NULL,
        root_cause TEXT,
        corrective_action TEXT,
        preventive_action TEXT,
        reported_by TEXT NOT NULL,
        reported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        reviewed_by TEXT,
        reviewed_at TIMESTAMP,
        review_status TEXT DEFAULT 'PENDING' CHECK(review_status IN
          ('PENDING', 'REVIEWED', 'APPROVED', 'REQUIRES_ACTION')),
        resolution_date DATE,
        resolution_notes TEXT,
        irb_reportable BOOLEAN DEFAULT 0,
        sponsor_reportable BOOLEAN DEFAULT 0,
        deviation_hash TEXT NOT NULL,
        previous_hash TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS eligibility_criteria (
        criterion_id INTEGER PRIMARY KEY AUTOINCREMENT,
        protocol_id INTEGER NOT NULL REFERENCES protocol_definitions(protocol_id),
        criterion_type TEXT NOT NULL CHECK(criterion_type IN
          ('INCLUSION', 'EXCLUSION')),
        criterion_code TEXT NOT NULL,
        criterion_text TEXT NOT NULL,
        field_name TEXT,
        operator TEXT CHECK(operator IN
          ('EQ', 'NE', 'GT', 'GE', 'LT', 'LE', 'IN', 'NOT_IN', 'BETWEEN', 'REGEX')),
        value TEXT,
        is_active BOOLEAN DEFAULT 1,
        UNIQUE(protocol_id, criterion_code)
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS eligibility_checks (
        check_id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id TEXT NOT NULL,
        protocol_id INTEGER NOT NULL REFERENCES protocol_definitions(protocol_id),
        check_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        overall_eligible BOOLEAN NOT NULL,
        criteria_results TEXT NOT NULL,
        waiver_granted BOOLEAN DEFAULT 0,
        waiver_reason TEXT,
        waiver_approved_by TEXT,
        waiver_approved_at TIMESTAMP,
        checked_by TEXT NOT NULL,
        notes TEXT
      )
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_deviations_subject
      ON protocol_deviations(subject_id)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_deviations_protocol
      ON protocol_deviations(protocol_id)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_deviations_status
      ON protocol_deviations(review_status)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_subject_visits
      ON subject_visits(subject_id, protocol_id)
    ")

    list(
      success = TRUE,
      tables_created = 7,
      message = "Protocol compliance system initialized successfully"
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    )
  })
}


# =============================================================================
# Protocol Definition Management
# =============================================================================

#' Create Protocol Definition
#'
#' Creates a new study protocol definition.
#'
#' @param protocol_code Character: Unique protocol code
#' @param protocol_title Character: Protocol title
#' @param protocol_version Character: Version number
#' @param effective_date Date: Effective date
#' @param sponsor Character: Sponsor name (optional)
#' @param principal_investigator Character: PI name (optional)
#' @param description Character: Description (optional)
#' @param created_by Character: Creator user ID
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
create_protocol <- function(protocol_code,
                             protocol_title,
                             protocol_version,
                             effective_date,
                             sponsor = NULL,
                             principal_investigator = NULL,
                             description = NULL,
                             created_by,
                             db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      INSERT INTO protocol_definitions (
        protocol_code, protocol_title, protocol_version,
        effective_date, sponsor, principal_investigator,
        description, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      safe_scalar_proto(protocol_code),
      safe_scalar_proto(protocol_title),
      safe_scalar_proto(protocol_version),
      safe_scalar_proto(as.character(effective_date)),
      safe_scalar_proto(sponsor),
      safe_scalar_proto(principal_investigator),
      safe_scalar_proto(description),
      safe_scalar_proto(created_by)
    ))

    protocol_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    list(
      success = TRUE,
      protocol_id = protocol_id,
      protocol_code = protocol_code,
      message = "Protocol created successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Get Protocol Definition
#'
#' Retrieves a protocol definition.
#'
#' @param protocol_id Integer: Protocol ID (optional)
#' @param protocol_code Character: Protocol code (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with protocol definition
#'
#' @export
get_protocol <- function(protocol_id = NULL,
                          protocol_code = NULL,
                          db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (!is.null(protocol_id)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM protocol_definitions WHERE protocol_id = ?
      ", list(protocol_id))
    } else if (!is.null(protocol_code)) {
      DBI::dbGetQuery(conn, "
        SELECT * FROM protocol_definitions WHERE protocol_code = ?
      ", list(safe_scalar_proto(protocol_code)))
    } else {
      DBI::dbGetQuery(conn, "
        SELECT * FROM protocol_definitions WHERE status = 'ACTIVE'
        ORDER BY created_at DESC
      ")
    }

  }, error = function(e) data.frame())
}


# =============================================================================
# Visit Schedule Management
# =============================================================================

#' Add Protocol Visit
#'
#' Adds a visit to the protocol schedule.
#'
#' @param protocol_id Integer: Protocol ID
#' @param visit_code Character: Unique visit code
#' @param visit_name Character: Visit display name
#' @param visit_order Integer: Visit sequence order
#' @param target_day Integer: Target study day
#' @param window_before Integer: Days allowed before target
#' @param window_after Integer: Days allowed after target
#' @param is_required Logical: Whether visit is required
#' @param visit_type Character: Visit type
#' @param description Character: Description (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
add_protocol_visit <- function(protocol_id,
                                visit_code,
                                visit_name,
                                visit_order,
                                target_day,
                                window_before = 0,
                                window_after = 0,
                                is_required = TRUE,
                                visit_type = "SCHEDULED",
                                description = NULL,
                                db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      INSERT INTO protocol_visits (
        protocol_id, visit_code, visit_name, visit_order,
        target_day, window_before, window_after,
        is_required, visit_type, description
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      protocol_id,
      safe_scalar_proto(visit_code),
      safe_scalar_proto(visit_name),
      visit_order,
      target_day,
      window_before,
      window_after,
      as.integer(is_required),
      safe_scalar_proto(visit_type),
      safe_scalar_proto(description)
    ))

    visit_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    list(
      success = TRUE,
      visit_id = visit_id,
      message = "Visit added successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Get Protocol Visits
#'
#' Retrieves all visits for a protocol.
#'
#' @param protocol_id Integer: Protocol ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with visits
#'
#' @export
get_protocol_visits <- function(protocol_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT * FROM protocol_visits
      WHERE protocol_id = ?
      ORDER BY visit_order ASC
    ", list(protocol_id))

  }, error = function(e) data.frame())
}


# =============================================================================
# Subject Visit Tracking
# =============================================================================

#' Schedule Subject Visit
#'
#' Schedules a visit for a subject.
#'
#' @param subject_id Character: Subject ID
#' @param protocol_id Integer: Protocol ID
#' @param visit_id Integer: Visit ID
#' @param scheduled_date Date: Scheduled date
#' @param baseline_date Date: Baseline date for window calculation
#' @param db_path Character: Database path (optional)
#'
#' @return List with scheduling result
#'
#' @export
schedule_subject_visit <- function(subject_id,
                                    protocol_id,
                                    visit_id,
                                    scheduled_date,
                                    baseline_date = NULL,
                                    db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    days_from_baseline <- if (!is.null(baseline_date)) {
      as.integer(as.Date(scheduled_date) - as.Date(baseline_date))
    } else {
      NA_integer_
    }

    DBI::dbExecute(conn, "
      INSERT INTO subject_visits (
        subject_id, protocol_id, visit_id,
        scheduled_date, days_from_baseline, status
      ) VALUES (?, ?, ?, ?, ?, 'SCHEDULED')
    ", list(
      safe_scalar_proto(subject_id),
      protocol_id,
      visit_id,
      safe_scalar_proto(as.character(scheduled_date)),
      days_from_baseline
    ))

    subject_visit_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    list(
      success = TRUE,
      subject_visit_id = subject_visit_id,
      message = "Visit scheduled successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Complete Subject Visit
#'
#' Records completion of a subject visit with window validation.
#'
#' @param subject_id Character: Subject ID
#' @param protocol_id Integer: Protocol ID
#' @param visit_id Integer: Visit ID
#' @param actual_date Date: Actual visit date
#' @param baseline_date Date: Baseline date for window calculation
#' @param completed_by Character: User completing visit
#' @param notes Character: Notes (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with completion result including window status
#'
#' @export
complete_subject_visit <- function(subject_id,
                                    protocol_id,
                                    visit_id,
                                    actual_date,
                                    baseline_date,
                                    completed_by,
                                    notes = NULL,
                                    db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    visit <- DBI::dbGetQuery(conn, "
      SELECT * FROM protocol_visits WHERE visit_id = ?
    ", list(visit_id))

    if (nrow(visit) == 0) {
      return(list(success = FALSE, error = "Visit not found"))
    }

    days_from_baseline <- as.integer(as.Date(actual_date) - as.Date(baseline_date))

    target_day <- visit$target_day
    window_start <- target_day - visit$window_before
    window_end <- target_day + visit$window_after

    window_status <- if (days_from_baseline >= window_start &&
                         days_from_baseline <= window_end) {
      "WITHIN_WINDOW"
    } else if (days_from_baseline < window_start) {
      "EARLY"
    } else {
      "LATE"
    }

    outside_window <- window_status != "WITHIN_WINDOW"

    timestamp <- as.character(Sys.time())

    existing <- DBI::dbGetQuery(conn, "
      SELECT subject_visit_id FROM subject_visits
      WHERE subject_id = ? AND protocol_id = ? AND visit_id = ?
    ", list(safe_scalar_proto(subject_id), protocol_id, visit_id))

    if (nrow(existing) > 0) {
      DBI::dbExecute(conn, "
        UPDATE subject_visits
        SET actual_date = ?,
            status = 'COMPLETED',
            days_from_baseline = ?,
            window_status = ?,
            completed_by = ?,
            completed_at = ?,
            notes = ?
        WHERE subject_id = ? AND protocol_id = ? AND visit_id = ?
      ", list(
        safe_scalar_proto(as.character(actual_date)),
        days_from_baseline,
        window_status,
        safe_scalar_proto(completed_by),
        timestamp,
        safe_scalar_proto(notes),
        safe_scalar_proto(subject_id),
        protocol_id,
        visit_id
      ))
      subject_visit_id <- existing$subject_visit_id
    } else {
      DBI::dbExecute(conn, "
        INSERT INTO subject_visits (
          subject_id, protocol_id, visit_id,
          actual_date, status, days_from_baseline, window_status,
          completed_by, completed_at, notes
        ) VALUES (?, ?, ?, ?, 'COMPLETED', ?, ?, ?, ?, ?)
      ", list(
        safe_scalar_proto(subject_id),
        protocol_id,
        visit_id,
        safe_scalar_proto(as.character(actual_date)),
        days_from_baseline,
        window_status,
        safe_scalar_proto(completed_by),
        timestamp,
        safe_scalar_proto(notes)
      ))
      subject_visit_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id
    }

    deviation_id <- NULL
    if (outside_window) {
      deviation_result <- create_protocol_deviation(
        protocol_id = protocol_id,
        subject_id = subject_id,
        deviation_type = "VISIT_TIMING",
        severity = if (abs(days_from_baseline - target_day) > visit$window_after * 2) "MAJOR" else "MINOR",
        deviation_date = actual_date,
        description = sprintf(
          "Visit %s completed %s window. Target: Day %d, Actual: Day %d. %s by %d days.",
          visit$visit_name,
          if (window_status == "EARLY") "before" else "after",
          target_day,
          days_from_baseline,
          if (window_status == "EARLY") "Early" else "Late",
          abs(days_from_baseline - target_day) - if (window_status == "EARLY") visit$window_before else visit$window_after
        ),
        reported_by = completed_by,
        db_path = db_path
      )

      if (deviation_result$success) {
        deviation_id <- deviation_result$deviation_id

        DBI::dbExecute(conn, "
          UPDATE subject_visits SET deviation_id = ? WHERE subject_visit_id = ?
        ", list(deviation_id, subject_visit_id))
      }
    }

    list(
      success = TRUE,
      subject_visit_id = subject_visit_id,
      window_status = window_status,
      days_from_baseline = days_from_baseline,
      target_day = target_day,
      deviation_created = outside_window,
      deviation_id = deviation_id,
      message = if (outside_window) {
        paste("Visit completed but outside window -", window_status)
      } else {
        "Visit completed within window"
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Get Subject Visit Status
#'
#' Gets visit completion status for a subject.
#'
#' @param subject_id Character: Subject ID
#' @param protocol_id Integer: Protocol ID
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with visit status
#'
#' @export
get_subject_visit_status <- function(subject_id, protocol_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbGetQuery(conn, "
      SELECT pv.*, sv.scheduled_date, sv.actual_date, sv.status,
             sv.days_from_baseline, sv.window_status, sv.deviation_id
      FROM protocol_visits pv
      LEFT JOIN subject_visits sv ON pv.visit_id = sv.visit_id
        AND sv.subject_id = ? AND sv.protocol_id = pv.protocol_id
      WHERE pv.protocol_id = ?
      ORDER BY pv.visit_order ASC
    ", list(safe_scalar_proto(subject_id), protocol_id))

  }, error = function(e) data.frame())
}


# =============================================================================
# Protocol Deviation Management
# =============================================================================

#' Get Deviation Types
#'
#' Returns valid deviation types with descriptions.
#'
#' @return Named list of deviation types
#'
#' @export
get_deviation_types <- function() {
  list(
    VISIT_TIMING = "Visit occurred outside allowed window",
    MISSED_VISIT = "Required visit was not completed",
    MISSED_ASSESSMENT = "Required assessment was not completed",
    ELIGIBILITY = "Subject eligibility criteria violation",
    DOSING = "Study drug dosing deviation",
    PROCEDURE = "Required procedure not performed correctly",
    DOCUMENTATION = "Documentation requirement not met",
    OTHER = "Other protocol deviation"
  )
}


#' Create Protocol Deviation
#'
#' Records a protocol deviation with audit trail.
#'
#' @param protocol_id Integer: Protocol ID
#' @param subject_id Character: Subject ID
#' @param deviation_type Character: Type from get_deviation_types()
#' @param severity Character: MINOR, MAJOR, or CRITICAL
#' @param deviation_date Date: Date of deviation
#' @param description Character: Description of deviation
#' @param root_cause Character: Root cause (optional)
#' @param corrective_action Character: Corrective action (optional)
#' @param preventive_action Character: Preventive action (optional)
#' @param reported_by Character: Reporter user ID
#' @param irb_reportable Logical: IRB reportable (default FALSE)
#' @param sponsor_reportable Logical: Sponsor reportable (default FALSE)
#' @param db_path Character: Database path (optional)
#'
#' @return List with deviation result
#'
#' @export
create_protocol_deviation <- function(protocol_id,
                                       subject_id,
                                       deviation_type,
                                       severity,
                                       deviation_date,
                                       description,
                                       root_cause = NULL,
                                       corrective_action = NULL,
                                       preventive_action = NULL,
                                       reported_by,
                                       irb_reportable = FALSE,
                                       sponsor_reportable = FALSE,
                                       db_path = NULL) {

  valid_types <- names(get_deviation_types())
  if (!deviation_type %in% valid_types) {
    return(list(
      success = FALSE,
      error = paste("Invalid deviation type. Must be one of:",
                    paste(valid_types, collapse = ", "))
    ))
  }

  if (!severity %in% c("MINOR", "MAJOR", "CRITICAL")) {
    return(list(
      success = FALSE,
      error = "Severity must be MINOR, MAJOR, or CRITICAL"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    last_hash <- DBI::dbGetQuery(conn, "
      SELECT deviation_hash FROM protocol_deviations
      ORDER BY deviation_id DESC LIMIT 1
    ")

    previous_hash <- if (nrow(last_hash) == 0) "GENESIS" else last_hash$deviation_hash[1]

    timestamp <- as.character(Sys.time())
    hash_content <- paste(
      protocol_id, subject_id, deviation_type, severity,
      deviation_date, description, reported_by, timestamp, previous_hash,
      sep = "|"
    )
    deviation_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      INSERT INTO protocol_deviations (
        protocol_id, subject_id, deviation_type, severity,
        deviation_date, description, root_cause, corrective_action,
        preventive_action, reported_by, irb_reportable, sponsor_reportable,
        deviation_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      protocol_id,
      safe_scalar_proto(subject_id),
      safe_scalar_proto(deviation_type),
      safe_scalar_proto(severity),
      safe_scalar_proto(as.character(deviation_date)),
      safe_scalar_proto(description),
      safe_scalar_proto(root_cause),
      safe_scalar_proto(corrective_action),
      safe_scalar_proto(preventive_action),
      safe_scalar_proto(reported_by),
      as.integer(irb_reportable),
      as.integer(sponsor_reportable),
      deviation_hash,
      previous_hash
    ))

    deviation_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    tryCatch({
      log_audit_event(
        event_type = "INSERT",
        user_id = reported_by,
        table_name = "protocol_deviations",
        record_id = as.character(deviation_id),
        details = paste("Protocol deviation created:", deviation_type,
                        "| Severity:", severity,
                        "| Subject:", subject_id)
      )
    }, error = function(e) NULL)

    list(
      success = TRUE,
      deviation_id = deviation_id,
      deviation_hash = deviation_hash,
      message = "Protocol deviation recorded successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Review Protocol Deviation
#'
#' Reviews and updates a protocol deviation.
#'
#' @param deviation_id Integer: Deviation ID
#' @param reviewed_by Character: Reviewer user ID
#' @param review_status Character: REVIEWED, APPROVED, or REQUIRES_ACTION
#' @param resolution_notes Character: Resolution notes (optional)
#' @param resolution_date Date: Resolution date (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with review result
#'
#' @export
review_protocol_deviation <- function(deviation_id,
                                       reviewed_by,
                                       review_status,
                                       resolution_notes = NULL,
                                       resolution_date = NULL,
                                       db_path = NULL) {

  if (!review_status %in% c("REVIEWED", "APPROVED", "REQUIRES_ACTION")) {
    return(list(
      success = FALSE,
      error = "Review status must be REVIEWED, APPROVED, or REQUIRES_ACTION"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    timestamp <- as.character(Sys.time())

    DBI::dbExecute(conn, "
      UPDATE protocol_deviations
      SET reviewed_by = ?,
          reviewed_at = ?,
          review_status = ?,
          resolution_notes = ?,
          resolution_date = ?
      WHERE deviation_id = ?
    ", list(
      safe_scalar_proto(reviewed_by),
      timestamp,
      safe_scalar_proto(review_status),
      safe_scalar_proto(resolution_notes),
      safe_scalar_proto(as.character(resolution_date)),
      deviation_id
    ))

    list(
      success = TRUE,
      deviation_id = deviation_id,
      review_status = review_status,
      message = "Deviation reviewed successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Get Protocol Deviations
#'
#' Retrieves protocol deviations with optional filters.
#'
#' @param protocol_id Integer: Protocol ID (optional)
#' @param subject_id Character: Subject ID (optional)
#' @param review_status Character: Filter by status (optional)
#' @param severity Character: Filter by severity (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with deviations
#'
#' @export
get_protocol_deviations <- function(protocol_id = NULL,
                                     subject_id = NULL,
                                     review_status = NULL,
                                     severity = NULL,
                                     db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    query <- "SELECT * FROM protocol_deviations WHERE 1=1"
    params <- list()

    if (!is.null(protocol_id)) {
      query <- paste(query, "AND protocol_id = ?")
      params <- c(params, list(protocol_id))
    }

    if (!is.null(subject_id)) {
      query <- paste(query, "AND subject_id = ?")
      params <- c(params, list(safe_scalar_proto(subject_id)))
    }

    if (!is.null(review_status)) {
      query <- paste(query, "AND review_status = ?")
      params <- c(params, list(safe_scalar_proto(review_status)))
    }

    if (!is.null(severity)) {
      query <- paste(query, "AND severity = ?")
      params <- c(params, list(safe_scalar_proto(severity)))
    }

    query <- paste(query, "ORDER BY deviation_date DESC")

    if (length(params) > 0) {
      DBI::dbGetQuery(conn, query, params)
    } else {
      DBI::dbGetQuery(conn, query)
    }

  }, error = function(e) data.frame())
}


# =============================================================================
# Eligibility Management
# =============================================================================

#' Add Eligibility Criterion
#'
#' Adds an inclusion or exclusion criterion to the protocol.
#'
#' @param protocol_id Integer: Protocol ID
#' @param criterion_type Character: INCLUSION or EXCLUSION
#' @param criterion_code Character: Unique criterion code
#' @param criterion_text Character: Criterion description
#' @param field_name Character: Data field to check (optional)
#' @param operator Character: Comparison operator (optional)
#' @param value Character: Comparison value (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with creation result
#'
#' @export
add_eligibility_criterion <- function(protocol_id,
                                       criterion_type,
                                       criterion_code,
                                       criterion_text,
                                       field_name = NULL,
                                       operator = NULL,
                                       value = NULL,
                                       db_path = NULL) {

  if (!criterion_type %in% c("INCLUSION", "EXCLUSION")) {
    return(list(
      success = FALSE,
      error = "Criterion type must be INCLUSION or EXCLUSION"
    ))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      INSERT INTO eligibility_criteria (
        protocol_id, criterion_type, criterion_code,
        criterion_text, field_name, operator, value
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", list(
      protocol_id,
      safe_scalar_proto(criterion_type),
      safe_scalar_proto(criterion_code),
      safe_scalar_proto(criterion_text),
      safe_scalar_proto(field_name),
      safe_scalar_proto(operator),
      safe_scalar_proto(value)
    ))

    criterion_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    list(
      success = TRUE,
      criterion_id = criterion_id,
      message = "Criterion added successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Check Subject Eligibility
#'
#' Checks a subject against protocol eligibility criteria.
#'
#' @param subject_id Character: Subject ID
#' @param protocol_id Integer: Protocol ID
#' @param subject_data List: Subject data to check against criteria
#' @param checked_by Character: User performing check
#' @param db_path Character: Database path (optional)
#'
#' @return List with eligibility result
#'
#' @export
check_subject_eligibility <- function(subject_id,
                                       protocol_id,
                                       subject_data,
                                       checked_by,
                                       db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    criteria <- DBI::dbGetQuery(conn, "
      SELECT * FROM eligibility_criteria
      WHERE protocol_id = ? AND is_active = 1
    ", list(protocol_id))

    if (nrow(criteria) == 0) {
      return(list(
        success = TRUE,
        eligible = TRUE,
        message = "No eligibility criteria defined"
      ))
    }

    results <- list()
    all_inclusion_met <- TRUE
    any_exclusion_met <- FALSE

    for (i in seq_len(nrow(criteria))) {
      crit <- criteria[i, ]
      crit_result <- list(
        criterion_code = crit$criterion_code,
        criterion_type = crit$criterion_type,
        criterion_text = crit$criterion_text,
        met = NA,
        value_checked = NA
      )

      if (!is.null(crit$field_name) && !is.na(crit$field_name) &&
          crit$field_name %in% names(subject_data)) {

        field_value <- subject_data[[crit$field_name]]
        crit_result$value_checked <- as.character(field_value)

        criterion_met <- evaluate_criterion(field_value, crit$operator, crit$value)
        crit_result$met <- criterion_met

        if (crit$criterion_type == "INCLUSION" && !criterion_met) {
          all_inclusion_met <- FALSE
        }
        if (crit$criterion_type == "EXCLUSION" && criterion_met) {
          any_exclusion_met <- TRUE
        }
      } else {
        crit_result$met <- NA
      }

      results[[crit$criterion_code]] <- crit_result
    }

    overall_eligible <- all_inclusion_met && !any_exclusion_met

    DBI::dbExecute(conn, "
      INSERT INTO eligibility_checks (
        subject_id, protocol_id, overall_eligible,
        criteria_results, checked_by
      ) VALUES (?, ?, ?, ?, ?)
    ", list(
      safe_scalar_proto(subject_id),
      protocol_id,
      as.integer(overall_eligible),
      jsonlite::toJSON(results, auto_unbox = TRUE),
      safe_scalar_proto(checked_by)
    ))

    check_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id

    list(
      success = TRUE,
      check_id = check_id,
      eligible = overall_eligible,
      all_inclusion_met = all_inclusion_met,
      any_exclusion_met = any_exclusion_met,
      criteria_results = results,
      message = if (overall_eligible) "Subject is eligible" else "Subject is not eligible"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Evaluate Criterion
#'
#' Evaluates a single criterion against a value.
#'
#' @param value Value to check
#' @param operator Comparison operator
#' @param criterion_value Criterion value to compare against
#'
#' @return Logical: TRUE if criterion is met
#'
#' @keywords internal
evaluate_criterion <- function(value, operator, criterion_value) {
  if (is.null(operator) || is.na(operator)) {
    return(NA)
  }

  tryCatch({
    num_value <- suppressWarnings(as.numeric(value))
    num_criterion <- suppressWarnings(as.numeric(criterion_value))

    result <- switch(operator,
      "EQ" = value == criterion_value,
      "NE" = value != criterion_value,
      "GT" = !is.na(num_value) && !is.na(num_criterion) && num_value > num_criterion,
      "GE" = !is.na(num_value) && !is.na(num_criterion) && num_value >= num_criterion,
      "LT" = !is.na(num_value) && !is.na(num_criterion) && num_value < num_criterion,
      "LE" = !is.na(num_value) && !is.na(num_criterion) && num_value <= num_criterion,
      "IN" = value %in% strsplit(criterion_value, ",")[[1]],
      "NOT_IN" = !(value %in% strsplit(criterion_value, ",")[[1]]),
      "REGEX" = grepl(criterion_value, value),
      NA
    )

    if (is.null(result)) NA else result

  }, error = function(e) NA)
}


# =============================================================================
# Compliance Statistics
# =============================================================================

#' Get Compliance Statistics
#'
#' Returns protocol compliance statistics.
#'
#' @param protocol_id Integer: Protocol ID
#' @param db_path Character: Database path (optional)
#'
#' @return List with compliance statistics
#'
#' @export
get_compliance_statistics <- function(protocol_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    visit_stats <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_visits,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'MISSED' THEN 1 ELSE 0 END) as missed,
        SUM(CASE WHEN window_status = 'WITHIN_WINDOW' THEN 1 ELSE 0 END) as within_window,
        SUM(CASE WHEN window_status IN ('EARLY', 'LATE') THEN 1 ELSE 0 END) as outside_window
      FROM subject_visits
      WHERE protocol_id = ?
    ", list(protocol_id))

    deviation_stats <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_deviations,
        SUM(CASE WHEN severity = 'MINOR' THEN 1 ELSE 0 END) as minor,
        SUM(CASE WHEN severity = 'MAJOR' THEN 1 ELSE 0 END) as major,
        SUM(CASE WHEN severity = 'CRITICAL' THEN 1 ELSE 0 END) as critical,
        SUM(CASE WHEN review_status = 'PENDING' THEN 1 ELSE 0 END) as pending_review
      FROM protocol_deviations
      WHERE protocol_id = ?
    ", list(protocol_id))

    by_type <- DBI::dbGetQuery(conn, "
      SELECT deviation_type, COUNT(*) as count
      FROM protocol_deviations
      WHERE protocol_id = ?
      GROUP BY deviation_type
      ORDER BY count DESC
    ", list(protocol_id))

    by_subject <- DBI::dbGetQuery(conn, "
      SELECT subject_id, COUNT(*) as deviation_count
      FROM protocol_deviations
      WHERE protocol_id = ?
      GROUP BY subject_id
      ORDER BY deviation_count DESC
      LIMIT 10
    ", list(protocol_id))

    eligibility_stats <- DBI::dbGetQuery(conn, "
      SELECT
        COUNT(*) as total_checks,
        SUM(CASE WHEN overall_eligible = 1 THEN 1 ELSE 0 END) as eligible,
        SUM(CASE WHEN overall_eligible = 0 THEN 1 ELSE 0 END) as ineligible,
        SUM(CASE WHEN waiver_granted = 1 THEN 1 ELSE 0 END) as waivers
      FROM eligibility_checks
      WHERE protocol_id = ?
    ", list(protocol_id))

    completion_rate <- if (visit_stats$total_visits > 0) {
      round(visit_stats$completed / visit_stats$total_visits * 100, 1)
    } else {
      0
    }

    window_compliance <- if (visit_stats$completed > 0) {
      round(visit_stats$within_window / visit_stats$completed * 100, 1)
    } else {
      0
    }

    list(
      success = TRUE,
      visits = list(
        total = visit_stats$total_visits,
        completed = visit_stats$completed,
        missed = visit_stats$missed,
        within_window = visit_stats$within_window,
        outside_window = visit_stats$outside_window,
        completion_rate = completion_rate,
        window_compliance = window_compliance
      ),
      deviations = list(
        total = deviation_stats$total_deviations,
        minor = deviation_stats$minor,
        major = deviation_stats$major,
        critical = deviation_stats$critical,
        pending_review = deviation_stats$pending_review
      ),
      by_type = by_type,
      by_subject = by_subject,
      eligibility = list(
        total_checks = eligibility_stats$total_checks,
        eligible = eligibility_stats$eligible,
        ineligible = eligibility_stats$ineligible,
        waivers = eligibility_stats$waivers
      )
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Generate Compliance Report
#'
#' Generates a protocol compliance report.
#'
#' @param protocol_id Integer: Protocol ID
#' @param output_file Character: Output file path
#' @param format Character: Report format (txt or json)
#' @param organization Character: Organization name
#' @param prepared_by Character: Report preparer
#' @param db_path Character: Database path (optional)
#'
#' @return List with report generation status
#'
#' @export
generate_compliance_report <- function(protocol_id,
                                        output_file,
                                        format = "txt",
                                        organization = "Clinical Research Organization",
                                        prepared_by = "Compliance Officer",
                                        db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    protocol <- get_protocol(protocol_id = protocol_id, db_path = db_path)
    stats <- get_compliance_statistics(protocol_id, db_path = db_path)
    deviations <- get_protocol_deviations(protocol_id = protocol_id, db_path = db_path)

    if (format == "json") {
      report_data <- list(
        report_type = "Protocol Compliance Report",
        organization = organization,
        generated_at = as.character(Sys.time()),
        prepared_by = prepared_by,
        protocol = protocol,
        statistics = stats,
        deviations = deviations
      )

      jsonlite::write_json(report_data, output_file, pretty = TRUE, auto_unbox = TRUE)

    } else {
      lines <- c(
        "===============================================================================",
        "                    PROTOCOL COMPLIANCE REPORT",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Generated:", Sys.time()),
        paste("Prepared By:", prepared_by),
        ""
      )

      if (nrow(protocol) > 0) {
        lines <- c(lines,
          paste("Protocol:", protocol$protocol_code[1]),
          paste("Title:", protocol$protocol_title[1]),
          paste("Version:", protocol$protocol_version[1]),
          paste("Status:", protocol$status[1]),
          ""
        )
      }

      lines <- c(lines,
        "-------------------------------------------------------------------------------",
        "                           VISIT COMPLIANCE",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Visits:", stats$visits$total),
        paste("Completed:", stats$visits$completed),
        paste("Missed:", stats$visits$missed),
        paste("Completion Rate:", stats$visits$completion_rate, "%"),
        paste("Within Window:", stats$visits$within_window),
        paste("Outside Window:", stats$visits$outside_window),
        paste("Window Compliance:", stats$visits$window_compliance, "%"),
        "",
        "-------------------------------------------------------------------------------",
        "                        PROTOCOL DEVIATIONS",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Deviations:", stats$deviations$total),
        paste("  Minor:", stats$deviations$minor),
        paste("  Major:", stats$deviations$major),
        paste("  Critical:", stats$deviations$critical),
        paste("Pending Review:", stats$deviations$pending_review),
        ""
      )

      if (nrow(stats$by_type) > 0) {
        lines <- c(lines, "Deviations by Type:")
        for (i in seq_len(nrow(stats$by_type))) {
          lines <- c(lines, sprintf("  %-20s %d",
                                    stats$by_type$deviation_type[i],
                                    stats$by_type$count[i]))
        }
        lines <- c(lines, "")
      }

      lines <- c(lines,
        "-------------------------------------------------------------------------------",
        "                        ELIGIBILITY SUMMARY",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Checks:", stats$eligibility$total_checks),
        paste("Eligible:", stats$eligibility$eligible),
        paste("Ineligible:", stats$eligibility$ineligible),
        paste("Waivers Granted:", stats$eligibility$waivers),
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
      message = "Report generated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
