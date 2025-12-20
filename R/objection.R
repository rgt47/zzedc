#' Right to Object System
#'
#' GDPR Article 21 compliant objection to processing system.
#' Enables data subjects to object to processing based on legitimate
#' interest, direct marketing, or research purposes.
#'
#' @name objection
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' Safe Scalar Conversion for Objection System
#' @param x Value to convert
#' @param default Default value if NULL or empty
#' @return Character scalar
#' @keywords internal
safe_scalar_objection <- function(x, default = NA_character_) {
 if (is.null(x) || length(x) == 0) {

    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' Safe Integer Conversion for Objection System
#' @param x Value to convert
#' @param default Default value if NULL or empty
#' @return Integer scalar
#' @keywords internal
safe_int_objection <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

#' Generate Objection Request Number
#' @return Character string in format OBJ-TIMESTAMP-RANDOM
#' @keywords internal
generate_objection_number <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(c(0:9, LETTERS), 6, replace = TRUE), collapse = "")
  paste0("OBJ-", timestamp, "-", random)
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize Objection System Tables
#'
#' Creates the database tables required for GDPR Article 21
#' Right to Object compliance.
#'
#' @return List with success status and message
#' @export
#'
#' @examples
#' \dontrun{
#' init_objection()
#' }
init_objection <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS objection_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT UNIQUE NOT NULL,
        dsar_request_id INTEGER,
        subject_id TEXT,
        subject_email TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        objection_type TEXT NOT NULL,
        processing_purpose TEXT NOT NULL,
        objection_grounds TEXT NOT NULL,
        situation_details TEXT,
        status TEXT DEFAULT 'RECEIVED',
        is_direct_marketing INTEGER DEFAULT 0,
        received_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        completed_date TEXT,
        requested_by TEXT NOT NULL,
        reviewed_by TEXT,
        reviewed_at TEXT,
        review_notes TEXT,
        decision TEXT,
        decision_reason TEXT,
        compelling_grounds TEXT,
        request_hash TEXT NOT NULL,
        previous_hash TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (dsar_request_id) REFERENCES dsar_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS objection_processing_activities (
        activity_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        activity_name TEXT NOT NULL,
        activity_description TEXT,
        legal_basis TEXT NOT NULL,
        data_categories TEXT,
        status TEXT DEFAULT 'ACTIVE',
        objection_applies INTEGER DEFAULT 1,
        processing_stopped INTEGER DEFAULT 0,
        stopped_at TEXT,
        stopped_by TEXT,
        resumed_at TEXT,
        resumed_by TEXT,
        resume_reason TEXT,
        activity_hash TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (request_id) REFERENCES objection_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS objection_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        activity_id INTEGER,
        action TEXT NOT NULL,
        action_details TEXT,
        performed_by TEXT NOT NULL,
        performed_at TEXT DEFAULT (datetime('now')),
        history_hash TEXT NOT NULL,
        previous_history_hash TEXT,
        FOREIGN KEY (request_id) REFERENCES objection_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS marketing_preferences (
        preference_id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id TEXT,
        subject_email TEXT NOT NULL,
        channel TEXT NOT NULL,
        opted_out INTEGER DEFAULT 0,
        opted_out_at TEXT,
        opted_out_by TEXT,
        objection_request_id INTEGER,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT,
        FOREIGN KEY (objection_request_id) REFERENCES objection_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_objection_requests_status
                         ON objection_requests(status)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_objection_requests_subject
                         ON objection_requests(subject_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_marketing_preferences_subject
                         ON marketing_preferences(subject_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_marketing_preferences_email
                         ON marketing_preferences(subject_email)")

    list(success = TRUE, message = "Objection system initialized successfully")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Objection Types
#'
#' Returns valid objection types under Article 21.
#'
#' @return Named character vector of objection types
#' @export
get_objection_types <- function() {
  c(
    LEGITIMATE_INTEREST = "Objection to processing based on legitimate interest (Art. 21(1))",
    PUBLIC_TASK = "Objection to processing for public task (Art. 21(1))",
    DIRECT_MARKETING = "Objection to direct marketing (Art. 21(2)) - absolute right",
    PROFILING_MARKETING = "Objection to profiling for direct marketing (Art. 21(2))",
    RESEARCH = "Objection to research/statistics processing (Art. 21(6))"
  )
}

#' Get Objection Statuses
#'
#' Returns valid status values for objection requests.
#'
#' @return Named character vector of status values
#' @export
get_objection_statuses <- function() {
  c(
    RECEIVED = "Request received",
    UNDER_REVIEW = "Under review",
    UPHELD = "Objection upheld - processing stopped",
    PARTIALLY_UPHELD = "Partially upheld",
    OVERRIDDEN = "Objection overridden - compelling grounds",
    REJECTED = "Objection rejected",
    COMPLETED = "Request completed"
  )
}

#' Get Marketing Channels
#'
#' Returns valid marketing channel types.
#'
#' @return Named character vector of marketing channels
#' @export
get_marketing_channels <- function() {
  c(
    EMAIL = "Email marketing",
    SMS = "SMS/Text messaging",
    PHONE = "Telephone calls",
    POST = "Postal mail",
    PUSH = "Push notifications",
    SOCIAL = "Social media advertising",
    ALL = "All marketing channels"
  )
}

#' Get Legal Bases for Objection
#'
#' Returns legal bases that can be objected to.
#'
#' @return Named character vector of legal bases
#' @export
get_objectionable_legal_bases <- function() {
  c(
    LEGITIMATE_INTEREST = "Article 6(1)(f) - Legitimate interest",
    PUBLIC_TASK = "Article 6(1)(e) - Public task",
    DIRECT_MARKETING = "Direct marketing purposes",
    RESEARCH = "Scientific/historical research or statistics"
  )
}

# ============================================================================
# REQUEST MANAGEMENT
# ============================================================================

#' Create Objection Request
#'
#' Creates a new GDPR Article 21 objection request.
#'
#' @param subject_email Email address of the data subject
#' @param subject_name Name of the data subject
#' @param objection_type Type from get_objection_types()
#' @param processing_purpose Purpose of processing being objected to
#' @param objection_grounds Grounds for the objection
#' @param requested_by User ID creating the request
#' @param subject_id Optional subject identifier
#' @param situation_details Optional details of subject's particular situation
#' @param dsar_request_id Optional link to related DSAR request
#'
#' @return List with success status, request details or error message
#' @export
create_objection_request <- function(subject_email,
                                      subject_name,
                                      objection_type,
                                      processing_purpose,
                                      objection_grounds,
                                      requested_by,
                                      subject_id = NULL,
                                      situation_details = NULL,
                                      dsar_request_id = NULL) {
  tryCatch({
    if (missing(subject_email) || is.null(subject_email) || subject_email == "") {
      return(list(success = FALSE, error = "subject_email is required"))
    }
    if (missing(subject_name) || is.null(subject_name) || subject_name == "") {
      return(list(success = FALSE, error = "subject_name is required"))
    }
    if (missing(objection_type) || is.null(objection_type)) {
      return(list(success = FALSE, error = "objection_type is required"))
    }
    if (missing(processing_purpose) || is.null(processing_purpose) ||
        processing_purpose == "") {
      return(list(success = FALSE, error = "processing_purpose is required"))
    }
    if (missing(objection_grounds) || is.null(objection_grounds) ||
        nchar(objection_grounds) < 10) {
      return(list(success = FALSE,
                  error = "objection_grounds must be at least 10 characters"))
    }

    valid_types <- names(get_objection_types())
    if (!objection_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid objection_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    is_direct_marketing <- objection_type %in%
      c("DIRECT_MARKETING", "PROFILING_MARKETING")

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request_number <- generate_objection_number()
    received_date <- format(Sys.Date(), "%Y-%m-%d")
    due_date <- format(Sys.Date() + 30, "%Y-%m-%d")

    previous_hash <- NA_character_
    last_request <- DBI::dbGetQuery(con, "
      SELECT request_hash FROM objection_requests
      ORDER BY request_id DESC LIMIT 1
    ")
    if (nrow(last_request) > 0) {
      previous_hash <- last_request$request_hash[1]
    }

    hash_content <- paste(
      request_number,
      safe_scalar_objection(subject_id),
      subject_email,
      subject_name,
      objection_type,
      processing_purpose,
      received_date,
      requested_by,
      safe_scalar_objection(previous_hash),
      sep = "|"
    )
    request_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO objection_requests (
        request_number, dsar_request_id, subject_id, subject_email,
        subject_name, objection_type, processing_purpose, objection_grounds,
        situation_details, status, is_direct_marketing, received_date,
        due_date, requested_by, request_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_number,
      safe_int_objection(dsar_request_id),
      safe_scalar_objection(subject_id),
      subject_email,
      subject_name,
      objection_type,
      processing_purpose,
      objection_grounds,
      safe_scalar_objection(situation_details),
      "RECEIVED",
      as.integer(is_direct_marketing),
      received_date,
      due_date,
      requested_by,
      request_hash,
      safe_scalar_objection(previous_hash)
    ))

    request_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_objection_action(
      request_id = request_id,
      action = "REQUEST_CREATED",
      action_details = paste("Objection request created. Type:", objection_type,
                            "- Purpose:", processing_purpose),
      performed_by = requested_by
    )

    if (is_direct_marketing) {
      log_objection_action(
        request_id = request_id,
        action = "DIRECT_MARKETING_OBJECTION",
        action_details = "Direct marketing objection - absolute right applies",
        performed_by = "SYSTEM"
      )
    }

    list(
      success = TRUE,
      request_id = request_id,
      request_number = request_number,
      status = "RECEIVED",
      is_direct_marketing = is_direct_marketing,
      due_date = due_date,
      message = if (is_direct_marketing) {
        "Direct marketing objection created - processing must stop immediately"
      } else {
        "Objection request created successfully"
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Log Objection Action
#' @keywords internal
log_objection_action <- function(request_id, action, action_details,
                                  performed_by, activity_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    previous_hash <- NA_character_
    last_history <- DBI::dbGetQuery(con, "
      SELECT history_hash FROM objection_history
      WHERE request_id = ?
      ORDER BY history_id DESC LIMIT 1
    ", params = list(request_id))

    if (nrow(last_history) > 0) {
      previous_hash <- last_history$history_hash[1]
    }

    performed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    hash_content <- paste(
      request_id,
      safe_int_objection(activity_id),
      action,
      action_details,
      performed_by,
      performed_at,
      safe_scalar_objection(previous_hash),
      sep = "|"
    )
    history_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO objection_history (
        request_id, activity_id, action, action_details,
        performed_by, performed_at, history_hash, previous_history_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      safe_int_objection(activity_id),
      action,
      action_details,
      performed_by,
      performed_at,
      history_hash,
      safe_scalar_objection(previous_hash)
    ))

    list(success = TRUE)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# PROCESSING ACTIVITY MANAGEMENT
# ============================================================================

#' Add Processing Activity to Objection
#'
#' Adds a processing activity that the subject is objecting to.
#'
#' @param request_id Request ID
#' @param activity_name Name of the processing activity
#' @param legal_basis Legal basis for the activity
#' @param added_by User adding the activity
#' @param activity_description Optional description
#' @param data_categories Optional data categories involved
#'
#' @return List with success status and activity details
#' @export
add_objection_activity <- function(request_id,
                                    activity_name,
                                    legal_basis,
                                    added_by,
                                    activity_description = NULL,
                                    data_categories = NULL) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(activity_name) || is.null(activity_name) || activity_name == "") {
      return(list(success = FALSE, error = "activity_name is required"))
    }

    valid_bases <- names(get_objectionable_legal_bases())
    if (!legal_basis %in% valid_bases) {
      return(list(
        success = FALSE,
        error = paste("Invalid legal_basis. Must be one of:",
                     paste(valid_bases, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status FROM objection_requests WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    hash_content <- paste(
      request_id,
      activity_name,
      legal_basis,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    activity_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO objection_processing_activities (
        request_id, activity_name, activity_description, legal_basis,
        data_categories, activity_hash
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      activity_name,
      safe_scalar_objection(activity_description),
      legal_basis,
      safe_scalar_objection(data_categories),
      activity_hash
    ))

    activity_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_objection_action(
      request_id = request_id,
      activity_id = activity_id,
      action = "ACTIVITY_ADDED",
      action_details = paste("Processing activity added:", activity_name,
                            "- Legal basis:", legal_basis),
      performed_by = added_by
    )

    list(
      success = TRUE,
      activity_id = activity_id,
      message = "Processing activity added"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Stop Processing Activity
#'
#' Stops a processing activity due to objection.
#'
#' @param activity_id Activity ID
#' @param stopped_by User stopping the activity
#'
#' @return List with success status
#' @export
stop_processing_activity <- function(activity_id, stopped_by) {
  tryCatch({
    if (missing(activity_id) || is.null(activity_id)) {
      return(list(success = FALSE, error = "activity_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    activity <- DBI::dbGetQuery(con, "
      SELECT activity_id, request_id, processing_stopped
      FROM objection_processing_activities
      WHERE activity_id = ?
    ", params = list(activity_id))

    if (nrow(activity) == 0) {
      return(list(success = FALSE, error = "Activity not found"))
    }

    if (activity$processing_stopped[1] == 1) {
      return(list(success = FALSE, error = "Processing already stopped"))
    }

    stopped_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE objection_processing_activities
      SET processing_stopped = 1, stopped_at = ?, stopped_by = ?, status = 'STOPPED'
      WHERE activity_id = ?
    ", params = list(stopped_at, stopped_by, activity_id))

    log_objection_action(
      request_id = activity$request_id[1],
      activity_id = activity_id,
      action = "PROCESSING_STOPPED",
      action_details = "Processing activity stopped due to objection",
      performed_by = stopped_by
    )

    list(
      success = TRUE,
      stopped_at = stopped_at,
      message = "Processing stopped successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Resume Processing Activity
#'
#' Resumes a previously stopped processing activity (if compelling grounds).
#'
#' @param activity_id Activity ID
#' @param resumed_by User resuming the activity
#' @param resume_reason Reason for resuming (minimum 20 characters)
#'
#' @return List with success status
#' @export
resume_processing_activity <- function(activity_id, resumed_by, resume_reason) {
  tryCatch({
    if (missing(activity_id) || is.null(activity_id)) {
      return(list(success = FALSE, error = "activity_id is required"))
    }
    if (missing(resume_reason) || is.null(resume_reason) ||
        nchar(resume_reason) < 20) {
      return(list(success = FALSE,
                  error = "resume_reason must be at least 20 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    activity <- DBI::dbGetQuery(con, "
      SELECT a.activity_id, a.request_id, a.processing_stopped,
             r.is_direct_marketing
      FROM objection_processing_activities a
      JOIN objection_requests r ON a.request_id = r.request_id
      WHERE a.activity_id = ?
    ", params = list(activity_id))

    if (nrow(activity) == 0) {
      return(list(success = FALSE, error = "Activity not found"))
    }

    if (activity$is_direct_marketing[1] == 1) {
      return(list(success = FALSE,
                  error = "Cannot resume - direct marketing objection is absolute"))
    }

    if (activity$processing_stopped[1] == 0) {
      return(list(success = FALSE, error = "Processing is not stopped"))
    }

    resumed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE objection_processing_activities
      SET processing_stopped = 0, resumed_at = ?, resumed_by = ?,
          resume_reason = ?, status = 'RESUMED'
      WHERE activity_id = ?
    ", params = list(resumed_at, resumed_by, resume_reason, activity_id))

    log_objection_action(
      request_id = activity$request_id[1],
      activity_id = activity_id,
      action = "PROCESSING_RESUMED",
      action_details = paste("Processing resumed:", resume_reason),
      performed_by = resumed_by
    )

    list(
      success = TRUE,
      resumed_at = resumed_at,
      message = "Processing resumed"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# MARKETING PREFERENCES
# ============================================================================

#' Opt Out of Marketing
#'
#' Records marketing opt-out for a subject.
#'
#' @param subject_email Subject email
#' @param channel Marketing channel from get_marketing_channels()
#' @param opted_out_by User recording the opt-out
#' @param subject_id Optional subject ID
#' @param objection_request_id Optional link to objection request
#'
#' @return List with success status
#' @export
opt_out_marketing <- function(subject_email,
                               channel,
                               opted_out_by,
                               subject_id = NULL,
                               objection_request_id = NULL) {
  tryCatch({
    if (missing(subject_email) || is.null(subject_email) || subject_email == "") {
      return(list(success = FALSE, error = "subject_email is required"))
    }

    valid_channels <- names(get_marketing_channels())
    if (!channel %in% valid_channels) {
      return(list(
        success = FALSE,
        error = paste("Invalid channel. Must be one of:",
                     paste(valid_channels, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    opted_out_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    channels_to_update <- if (channel == "ALL") {
      setdiff(valid_channels, "ALL")
    } else {
      channel
    }

    for (ch in channels_to_update) {
      existing <- DBI::dbGetQuery(con, "
        SELECT preference_id FROM marketing_preferences
        WHERE subject_email = ? AND channel = ?
      ", params = list(subject_email, ch))

      if (nrow(existing) > 0) {
        DBI::dbExecute(con, "
          UPDATE marketing_preferences
          SET opted_out = 1, opted_out_at = ?, opted_out_by = ?,
              objection_request_id = ?, updated_at = ?
          WHERE subject_email = ? AND channel = ?
        ", params = list(
          opted_out_at,
          opted_out_by,
          safe_int_objection(objection_request_id),
          opted_out_at,
          subject_email,
          ch
        ))
      } else {
        DBI::dbExecute(con, "
          INSERT INTO marketing_preferences (
            subject_id, subject_email, channel, opted_out, opted_out_at,
            opted_out_by, objection_request_id
          ) VALUES (?, ?, ?, 1, ?, ?, ?)
        ", params = list(
          safe_scalar_objection(subject_id),
          subject_email,
          ch,
          opted_out_at,
          opted_out_by,
          safe_int_objection(objection_request_id)
        ))
      }
    }

    if (!is.null(objection_request_id)) {
      log_objection_action(
        request_id = objection_request_id,
        action = "MARKETING_OPT_OUT",
        action_details = paste("Opted out of marketing channel:", channel),
        performed_by = opted_out_by
      )
    }

    list(
      success = TRUE,
      channels_updated = length(channels_to_update),
      opted_out_at = opted_out_at,
      message = paste("Opted out of", length(channels_to_update), "channel(s)")
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Check Marketing Preference
#'
#' Checks if a subject has opted out of marketing.
#'
#' @param subject_email Subject email
#' @param channel Optional specific channel to check
#'
#' @return List with opt-out status
#' @export
check_marketing_preference <- function(subject_email, channel = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(channel)) {
      prefs <- DBI::dbGetQuery(con, "
        SELECT channel, opted_out, opted_out_at
        FROM marketing_preferences
        WHERE subject_email = ?
      ", params = list(subject_email))
    } else {
      prefs <- DBI::dbGetQuery(con, "
        SELECT channel, opted_out, opted_out_at
        FROM marketing_preferences
        WHERE subject_email = ? AND channel = ?
      ", params = list(subject_email, channel))
    }

    if (nrow(prefs) == 0) {
      list(
        success = TRUE,
        has_preferences = FALSE,
        opted_out = FALSE,
        message = "No marketing preferences recorded"
      )
    } else {
      opted_out_channels <- prefs$channel[prefs$opted_out == 1]
      list(
        success = TRUE,
        has_preferences = TRUE,
        opted_out = any(prefs$opted_out == 1),
        opted_out_channels = opted_out_channels,
        preferences = prefs,
        message = if (length(opted_out_channels) > 0) {
          paste("Opted out of:", paste(opted_out_channels, collapse = ", "))
        } else {
          "Not opted out of any channels"
        }
      )
    }

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REQUEST DECISIONS
# ============================================================================

#' Uphold Objection
#'
#' Upholds an objection and stops processing.
#'
#' @param request_id Request ID
#' @param upheld_by User upholding the objection
#' @param review_notes Optional review notes
#'
#' @return List with success status
#' @export
uphold_objection <- function(request_id, upheld_by, review_notes = NULL) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status, is_direct_marketing, subject_email
      FROM objection_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    reviewed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE objection_requests
      SET status = 'UPHELD', decision = 'UPHELD', reviewed_by = ?,
          reviewed_at = ?, review_notes = ?
      WHERE request_id = ?
    ", params = list(upheld_by, reviewed_at,
                     safe_scalar_objection(review_notes), request_id))

    DBI::dbExecute(con, "
      UPDATE objection_processing_activities
      SET processing_stopped = 1, stopped_at = ?, stopped_by = ?, status = 'STOPPED'
      WHERE request_id = ? AND processing_stopped = 0
    ", params = list(reviewed_at, upheld_by, request_id))

    if (request$is_direct_marketing[1] == 1) {
      opt_out_marketing(
        subject_email = request$subject_email[1],
        channel = "ALL",
        opted_out_by = upheld_by,
        objection_request_id = request_id
      )
    }

    log_objection_action(
      request_id = request_id,
      action = "OBJECTION_UPHELD",
      action_details = "Objection upheld - all processing stopped",
      performed_by = upheld_by
    )

    list(
      success = TRUE,
      status = "UPHELD",
      reviewed_at = reviewed_at,
      message = "Objection upheld - processing stopped"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Override Objection
#'
#' Overrides an objection based on compelling legitimate grounds.
#' Note: Cannot override direct marketing objections.
#'
#' @param request_id Request ID
#' @param overridden_by User overriding the objection
#' @param compelling_grounds Compelling grounds (minimum 50 characters)
#' @param review_notes Optional review notes
#'
#' @return List with success status
#' @export
override_objection <- function(request_id,
                                overridden_by,
                                compelling_grounds,
                                review_notes = NULL) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(compelling_grounds) || is.null(compelling_grounds) ||
        nchar(compelling_grounds) < 50) {
      return(list(success = FALSE,
                  error = "compelling_grounds must be at least 50 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status, is_direct_marketing
      FROM objection_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (request$is_direct_marketing[1] == 1) {
      return(list(success = FALSE,
                  error = "Cannot override direct marketing objection - it is an absolute right"))
    }

    reviewed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE objection_requests
      SET status = 'OVERRIDDEN', decision = 'OVERRIDDEN', reviewed_by = ?,
          reviewed_at = ?, review_notes = ?, compelling_grounds = ?
      WHERE request_id = ?
    ", params = list(overridden_by, reviewed_at,
                     safe_scalar_objection(review_notes),
                     compelling_grounds, request_id))

    log_objection_action(
      request_id = request_id,
      action = "OBJECTION_OVERRIDDEN",
      action_details = paste("Objection overridden. Compelling grounds:",
                            compelling_grounds),
      performed_by = overridden_by
    )

    list(
      success = TRUE,
      status = "OVERRIDDEN",
      reviewed_at = reviewed_at,
      message = "Objection overridden based on compelling legitimate grounds"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Reject Objection
#'
#' Rejects an objection request.
#' Note: Cannot reject direct marketing objections.
#'
#' @param request_id Request ID
#' @param rejected_by User rejecting the objection
#' @param decision_reason Reason for rejection (minimum 20 characters)
#'
#' @return List with success status
#' @export
reject_objection <- function(request_id, rejected_by, decision_reason) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(decision_reason) || is.null(decision_reason) ||
        nchar(decision_reason) < 20) {
      return(list(success = FALSE,
                  error = "decision_reason must be at least 20 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status, is_direct_marketing
      FROM objection_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (request$is_direct_marketing[1] == 1) {
      return(list(success = FALSE,
                  error = "Cannot reject direct marketing objection - it is an absolute right"))
    }

    reviewed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE objection_requests
      SET status = 'REJECTED', decision = 'REJECTED', reviewed_by = ?,
          reviewed_at = ?, decision_reason = ?, completed_date = ?
      WHERE request_id = ?
    ", params = list(rejected_by, reviewed_at, decision_reason,
                     reviewed_at, request_id))

    log_objection_action(
      request_id = request_id,
      action = "OBJECTION_REJECTED",
      action_details = paste("Objection rejected:", decision_reason),
      performed_by = rejected_by
    )

    list(
      success = TRUE,
      status = "REJECTED",
      completed_date = reviewed_at,
      message = "Objection rejected"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Complete Objection Request
#'
#' Completes an objection request after all actions taken.
#'
#' @param request_id Request ID
#' @param completed_by User completing the request
#'
#' @return List with success status
#' @export
complete_objection_request <- function(request_id, completed_by) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status, decision FROM objection_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (is.na(request$decision[1]) || request$decision[1] == "") {
      return(list(success = FALSE,
                  error = "Request must have a decision before completing"))
    }

    completed_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE objection_requests
      SET status = 'COMPLETED', completed_date = ?
      WHERE request_id = ?
    ", params = list(completed_date, request_id))

    log_objection_action(
      request_id = request_id,
      action = "REQUEST_COMPLETED",
      action_details = paste("Request completed. Decision:", request$decision[1]),
      performed_by = completed_by
    )

    list(
      success = TRUE,
      status = "COMPLETED",
      completed_date = completed_date,
      message = "Objection request completed"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# RETRIEVAL FUNCTIONS
# ============================================================================

#' Get Objection Request
#' @param request_id Optional request ID
#' @param request_number Optional request number
#' @return List with success status and request data
#' @export
get_objection_request <- function(request_id = NULL, request_number = NULL) {
  tryCatch({
    if (is.null(request_id) && is.null(request_number)) {
      return(list(success = FALSE,
                  error = "Either request_id or request_number required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (!is.null(request_id)) {
      request <- DBI::dbGetQuery(con, "
        SELECT * FROM objection_requests WHERE request_id = ?
      ", params = list(request_id))
    } else {
      request <- DBI::dbGetQuery(con, "
        SELECT * FROM objection_requests WHERE request_number = ?
      ", params = list(request_number))
    }

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    list(success = TRUE, request = request)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Objection Activities
#' @param request_id Request ID
#' @return List with success status and activities
#' @export
get_objection_activities <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    activities <- DBI::dbGetQuery(con, "
      SELECT * FROM objection_processing_activities WHERE request_id = ?
    ", params = list(request_id))

    list(success = TRUE, activities = activities, count = nrow(activities))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Objection History
#' @param request_id Request ID
#' @return List with success status and history
#' @export
get_objection_history <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    history <- DBI::dbGetQuery(con, "
      SELECT * FROM objection_history
      WHERE request_id = ?
      ORDER BY history_id ASC
    ", params = list(request_id))

    list(success = TRUE, history = history, count = nrow(history))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Pending Objection Requests
#' @return List with success status and requests
#' @export
get_pending_objection_requests <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    requests <- DBI::dbGetQuery(con, "
      SELECT * FROM objection_requests
      WHERE status IN ('RECEIVED', 'UNDER_REVIEW')
      ORDER BY due_date ASC
    ")

    list(success = TRUE, requests = requests, count = nrow(requests))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# STATISTICS AND REPORTING
# ============================================================================

#' Get Objection Statistics
#' @return List with statistics
#' @export
get_objection_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'RECEIVED' THEN 1 ELSE 0 END) as received,
        SUM(CASE WHEN status = 'UPHELD' THEN 1 ELSE 0 END) as upheld,
        SUM(CASE WHEN status = 'OVERRIDDEN' THEN 1 ELSE 0 END) as overridden,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) as completed,
        SUM(is_direct_marketing) as direct_marketing
      FROM objection_requests
    ")

    activity_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(processing_stopped) as stopped,
        SUM(CASE WHEN status = 'RESUMED' THEN 1 ELSE 0 END) as resumed
      FROM objection_processing_activities
    ")

    marketing_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(opted_out) as opted_out
      FROM marketing_preferences
    ")

    type_stats <- DBI::dbGetQuery(con, "
      SELECT objection_type, COUNT(*) as count
      FROM objection_requests
      GROUP BY objection_type
    ")

    list(
      success = TRUE,
      requests = as.list(request_stats),
      activities = as.list(activity_stats),
      marketing = as.list(marketing_stats),
      by_type = type_stats
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Generate Objection Report
#' @param output_file Output file path
#' @param format Report format: "txt" or "json"
#' @param organization Organization name
#' @param prepared_by Name of person preparing report
#' @return List with success status
#' @export
generate_objection_report <- function(output_file,
                                       format = "txt",
                                       organization = "Organization",
                                       prepared_by = "DPO") {
  tryCatch({
    stats <- get_objection_statistics()
    if (!stats$success) {
      return(list(success = FALSE, error = "Failed to get statistics"))
    }

    if (format == "json") {
      report_data <- list(
        report_type = "GDPR Article 21 Right to Object Report",
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
        "            GDPR ARTICLE 21 - RIGHT TO OBJECT REPORT",
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
        paste("  - Upheld:", stats$requests$upheld),
        paste("  - Overridden:", stats$requests$overridden),
        paste("  - Rejected:", stats$requests$rejected),
        paste("  - Completed:", stats$requests$completed),
        paste("  - Direct Marketing:", stats$requests$direct_marketing),
        "",
        "-------------------------------------------------------------------------------",
        "PROCESSING ACTIVITIES",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Activities:", stats$activities$total),
        paste("  - Stopped:", stats$activities$stopped),
        paste("  - Resumed:", stats$activities$resumed),
        "",
        "-------------------------------------------------------------------------------",
        "MARKETING PREFERENCES",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Preferences:", stats$marketing$total),
        paste("  - Opted Out:", stats$marketing$opted_out),
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
