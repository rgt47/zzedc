#' Change Control System (Feature #27)
#'
#' Provides formal change control for CRFs, protocols, and system
#' modifications with impact assessment and approval workflows.
#'
#' @name change_control
#' @docType package
NULL

#' @keywords internal
safe_scalar_cc <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize Change Control System
#' @return List with success status
#' @export
init_change_control <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS change_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT UNIQUE NOT NULL,
        request_title TEXT NOT NULL,
        request_type TEXT NOT NULL,
        change_category TEXT NOT NULL,
        priority TEXT DEFAULT 'MEDIUM',
        status TEXT DEFAULT 'DRAFT',
        requested_by TEXT NOT NULL,
        requested_at TEXT DEFAULT (datetime('now')),
        target_entity_type TEXT,
        target_entity_id INTEGER,
        description TEXT NOT NULL,
        justification TEXT,
        implementation_plan TEXT,
        rollback_plan TEXT,
        estimated_effort TEXT,
        target_date TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS change_impact_assessment (
        assessment_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        impact_area TEXT NOT NULL,
        impact_level TEXT NOT NULL,
        impact_description TEXT,
        mitigation_strategy TEXT,
        affected_subjects INTEGER DEFAULT 0,
        affected_records INTEGER DEFAULT 0,
        requires_revalidation INTEGER DEFAULT 0,
        assessed_by TEXT NOT NULL,
        assessed_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (request_id) REFERENCES change_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS change_approvals (
        approval_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        approval_role TEXT NOT NULL,
        approver_name TEXT NOT NULL,
        decision TEXT NOT NULL,
        decision_date TEXT DEFAULT (datetime('now')),
        comments TEXT,
        conditions TEXT,
        FOREIGN KEY (request_id) REFERENCES change_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS change_implementation (
        implementation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        implementation_step TEXT NOT NULL,
        step_order INTEGER DEFAULT 1,
        step_status TEXT DEFAULT 'PENDING',
        implemented_by TEXT,
        implemented_at TEXT,
        verification_result TEXT,
        verified_by TEXT,
        verified_at TEXT,
        notes TEXT,
        FOREIGN KEY (request_id) REFERENCES change_requests(request_id)
      )
    ")

    list(success = TRUE, message = "Change control system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Change Request Types
#' @return Named character vector
#' @export
get_change_request_types <- function() {
  c(
    CRF_MODIFICATION = "CRF form or field modification",
    PROTOCOL_AMENDMENT = "Protocol amendment implementation",
    SYSTEM_CONFIG = "System configuration change",
    VALIDATION_RULE = "Validation rule change",
    USER_ACCESS = "User access modification",
    DATA_CORRECTION = "Systematic data correction",
    INTEGRATION = "System integration change",
    SECURITY = "Security-related change"
  )
}

#' Get Change Categories
#' @return Named character vector
#' @export
get_change_categories <- function() {
  c(
    CRITICAL = "Affects safety or data integrity",
    MAJOR = "Significant functional change",
    MINOR = "Minor change with limited impact",
    ADMINISTRATIVE = "Administrative or documentation only"
  )
}

#' Get Change Priorities
#' @return Named character vector
#' @export
get_change_priorities <- function() {
  c(
    URGENT = "Requires immediate attention",
    HIGH = "Complete within 1 week",
    MEDIUM = "Complete within 1 month",
    LOW = "Complete as resources allow"
  )
}

#' Get Change Statuses
#' @return Named character vector
#' @export
get_change_statuses <- function() {
  c(
    DRAFT = "Request being drafted",
    SUBMITTED = "Submitted for review",
    IMPACT_ASSESSMENT = "Impact assessment in progress",
    PENDING_APPROVAL = "Awaiting approval",
    APPROVED = "Approved for implementation",
    IN_PROGRESS = "Implementation in progress",
    IMPLEMENTED = "Implementation complete",
    VERIFIED = "Changes verified",
    CLOSED = "Change request closed",
    REJECTED = "Request rejected",
    CANCELLED = "Request cancelled"
  )
}

#' Get Impact Levels
#' @return Named character vector
#' @export
get_impact_levels <- function() {
  c(
    HIGH = "Significant impact requiring extensive mitigation",
    MEDIUM = "Moderate impact with manageable mitigation",
    LOW = "Minimal impact",
    NONE = "No impact in this area"
  )
}

#' Create Change Request
#' @param request_title Title
#' @param request_type Type
#' @param change_category Category
#' @param description Description
#' @param requested_by User requesting
#' @param priority Priority level
#' @param justification Justification
#' @param target_entity_type Entity type
#' @param target_entity_id Entity ID
#' @param implementation_plan Implementation plan
#' @param rollback_plan Rollback plan
#' @param estimated_effort Effort estimate
#' @param target_date Target completion date
#' @return List with success status
#' @export
create_change_request <- function(request_title, request_type, change_category,
                                   description, requested_by,
                                   priority = "MEDIUM", justification = NULL,
                                   target_entity_type = NULL,
                                   target_entity_id = NULL,
                                   implementation_plan = NULL,
                                   rollback_plan = NULL,
                                   estimated_effort = NULL,
                                   target_date = NULL) {
  tryCatch({
    if (missing(request_title) || request_title == "") {
      return(list(success = FALSE, error = "request_title is required"))
    }

    valid_types <- names(get_change_request_types())
    if (!request_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid request_type:", request_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request_number <- paste0("CR-", format(Sys.time(), "%Y%m%d-%H%M%S"))

    DBI::dbExecute(con, "
      INSERT INTO change_requests (
        request_number, request_title, request_type, change_category,
        priority, description, justification, requested_by,
        target_entity_type, target_entity_id, implementation_plan,
        rollback_plan, estimated_effort, target_date
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_number, request_title, request_type, change_category,
      priority, description, safe_scalar_cc(justification), requested_by,
      safe_scalar_cc(target_entity_type),
      if (is.null(target_entity_id)) NA_integer_
        else as.integer(target_entity_id),
      safe_scalar_cc(implementation_plan), safe_scalar_cc(rollback_plan),
      safe_scalar_cc(estimated_effort), safe_scalar_cc(target_date)
    ))

    request_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, request_id = request_id,
         request_number = request_number)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Submit Change Request
#' @param request_id Request ID
#' @return List with success status
#' @export
submit_change_request <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE change_requests SET status = 'SUBMITTED'
      WHERE request_id = ?
    ", params = list(request_id))

    list(success = TRUE, message = "Change request submitted")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Impact Assessment
#' @param request_id Request ID
#' @param impact_area Area of impact
#' @param impact_level Level of impact
#' @param assessed_by Assessor
#' @param impact_description Description
#' @param mitigation_strategy Mitigation strategy
#' @param affected_subjects Number of affected subjects
#' @param affected_records Number of affected records
#' @param requires_revalidation Whether revalidation required
#' @return List with success status
#' @export
add_impact_assessment <- function(request_id, impact_area, impact_level,
                                   assessed_by, impact_description = NULL,
                                   mitigation_strategy = NULL,
                                   affected_subjects = 0,
                                   affected_records = 0,
                                   requires_revalidation = FALSE) {
  tryCatch({
    valid_levels <- names(get_impact_levels())
    if (!impact_level %in% valid_levels) {
      return(list(success = FALSE,
                  error = paste("Invalid impact_level:", impact_level)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO change_impact_assessment (
        request_id, impact_area, impact_level, impact_description,
        mitigation_strategy, affected_subjects, affected_records,
        requires_revalidation, assessed_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id, impact_area, impact_level,
      safe_scalar_cc(impact_description),
      safe_scalar_cc(mitigation_strategy),
      as.integer(affected_subjects), as.integer(affected_records),
      as.integer(requires_revalidation), assessed_by
    ))

    DBI::dbExecute(con, "
      UPDATE change_requests SET status = 'IMPACT_ASSESSMENT'
      WHERE request_id = ? AND status = 'SUBMITTED'
    ", params = list(request_id))

    list(success = TRUE, message = "Impact assessment added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Impact Assessments
#' @param request_id Request ID
#' @return List with assessments
#' @export
get_impact_assessments <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    assessments <- DBI::dbGetQuery(con, "
      SELECT * FROM change_impact_assessment
      WHERE request_id = ?
      ORDER BY assessed_at
    ", params = list(request_id))

    list(success = TRUE, assessments = assessments, count = nrow(assessments))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Change Approval
#' @param request_id Request ID
#' @param approval_role Role of approver
#' @param approver_name Name of approver
#' @param decision Decision (APPROVE, REJECT, CONDITIONAL)
#' @param comments Comments
#' @param conditions Conditions for approval
#' @return List with success status
#' @export
add_change_approval <- function(request_id, approval_role, approver_name,
                                 decision, comments = NULL, conditions = NULL) {
  tryCatch({
    if (!decision %in% c("APPROVE", "REJECT", "CONDITIONAL")) {
      return(list(success = FALSE, error = "Invalid decision"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO change_approvals (
        request_id, approval_role, approver_name, decision, comments, conditions
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id, approval_role, approver_name, decision,
      safe_scalar_cc(comments), safe_scalar_cc(conditions)
    ))

    new_status <- switch(decision,
      APPROVE = "APPROVED",
      REJECT = "REJECTED",
      CONDITIONAL = "PENDING_APPROVAL"
    )

    DBI::dbExecute(con, "
      UPDATE change_requests SET status = ?
      WHERE request_id = ?
    ", params = list(new_status, request_id))

    list(success = TRUE, message = paste("Change", tolower(decision), "d"))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Change Approvals
#' @param request_id Request ID
#' @return List with approvals
#' @export
get_change_approvals <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    approvals <- DBI::dbGetQuery(con, "
      SELECT * FROM change_approvals
      WHERE request_id = ?
      ORDER BY decision_date
    ", params = list(request_id))

    list(success = TRUE, approvals = approvals, count = nrow(approvals))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Implementation Step
#' @param request_id Request ID
#' @param implementation_step Step description
#' @param step_order Order
#' @return List with success status
#' @export
add_implementation_step <- function(request_id, implementation_step,
                                     step_order = 1) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO change_implementation (
        request_id, implementation_step, step_order
      ) VALUES (?, ?, ?)
    ", params = list(request_id, implementation_step, as.integer(step_order)))

    list(success = TRUE, message = "Implementation step added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Complete Implementation Step
#' @param implementation_id Implementation ID
#' @param implemented_by User implementing
#' @param notes Optional notes
#' @return List with success status
#' @export
complete_implementation_step <- function(implementation_id, implemented_by,
                                          notes = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE change_implementation
      SET step_status = 'COMPLETED', implemented_by = ?,
          implemented_at = ?, notes = ?
      WHERE implementation_id = ?
    ", params = list(
      implemented_by, format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      safe_scalar_cc(notes), implementation_id
    ))

    list(success = TRUE, message = "Implementation step completed")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Verify Implementation Step
#' @param implementation_id Implementation ID
#' @param verified_by User verifying
#' @param verification_result Result (PASS, FAIL)
#' @return List with success status
#' @export
verify_implementation_step <- function(implementation_id, verified_by,
                                        verification_result) {
  tryCatch({
    if (!verification_result %in% c("PASS", "FAIL")) {
      return(list(success = FALSE, error = "Result must be PASS or FAIL"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    new_status <- if (verification_result == "PASS") "VERIFIED" else "FAILED"

    DBI::dbExecute(con, "
      UPDATE change_implementation
      SET verification_result = ?, verified_by = ?, verified_at = ?,
          step_status = ?
      WHERE implementation_id = ?
    ", params = list(
      verification_result, verified_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"), new_status, implementation_id
    ))

    list(success = TRUE, message = "Implementation step verified")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Implementation Status
#' @param request_id Request ID
#' @return List with implementation steps
#' @export
get_implementation_status <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    steps <- DBI::dbGetQuery(con, "
      SELECT * FROM change_implementation
      WHERE request_id = ?
      ORDER BY step_order
    ", params = list(request_id))

    total <- nrow(steps)
    completed <- sum(steps$step_status == "COMPLETED", na.rm = TRUE)
    verified <- sum(steps$step_status == "VERIFIED", na.rm = TRUE)

    list(success = TRUE, steps = steps, total_steps = total,
         completed_steps = completed, verified_steps = verified)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update Change Request Status
#' @param request_id Request ID
#' @param new_status New status
#' @return List with success status
#' @export
update_change_request_status <- function(request_id, new_status) {
  tryCatch({
    valid_statuses <- names(get_change_statuses())
    if (!new_status %in% valid_statuses) {
      return(list(success = FALSE, error = "Invalid status"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE change_requests SET status = ?
      WHERE request_id = ?
    ", params = list(new_status, request_id))

    list(success = TRUE, message = "Status updated")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Change Requests
#' @param status Optional status filter
#' @param request_type Optional type filter
#' @param change_category Optional category filter
#' @return List with change requests
#' @export
get_change_requests <- function(status = NULL, request_type = NULL,
                                 change_category = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM change_requests WHERE 1=1"
    params <- list()

    if (!is.null(status)) {
      query <- paste(query, "AND status = ?")
      params <- append(params, list(status))
    }
    if (!is.null(request_type)) {
      query <- paste(query, "AND request_type = ?")
      params <- append(params, list(request_type))
    }
    if (!is.null(change_category)) {
      query <- paste(query, "AND change_category = ?")
      params <- append(params, list(change_category))
    }

    query <- paste(query, "ORDER BY requested_at DESC")

    if (length(params) > 0) {
      requests <- DBI::dbGetQuery(con, query, params = params)
    } else {
      requests <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, requests = requests, count = nrow(requests))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Change Request Details
#' @param request_id Request ID
#' @return List with full request details
#' @export
get_change_request_details <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT * FROM change_requests WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Change request not found"))
    }

    assessments <- get_impact_assessments(request_id)
    approvals <- get_change_approvals(request_id)
    implementation <- get_implementation_status(request_id)

    list(
      success = TRUE,
      request = as.list(request),
      assessments = assessments$assessments,
      approvals = approvals$approvals,
      implementation = implementation$steps
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Change Control Statistics
#' @return List with statistics
#' @export
get_change_control_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_requests,
        SUM(CASE WHEN status = 'APPROVED' THEN 1 ELSE 0 END) as approved,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected,
        SUM(CASE WHEN status = 'IN_PROGRESS' THEN 1 ELSE 0 END) as in_progress,
        SUM(CASE WHEN status = 'CLOSED' THEN 1 ELSE 0 END) as closed
      FROM change_requests
    ")

    by_type <- DBI::dbGetQuery(con, "
      SELECT request_type, COUNT(*) as count
      FROM change_requests
      GROUP BY request_type
    ")

    by_category <- DBI::dbGetQuery(con, "
      SELECT change_category, COUNT(*) as count
      FROM change_requests
      GROUP BY change_category
    ")

    list(success = TRUE, statistics = as.list(stats),
         by_type = by_type, by_category = by_category)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
