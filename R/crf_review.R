#' CRF Design Review Workflow System
#'
#' Implements structured review workflow for CRF designs with
#' multiple review stages, reviewer assignments, comments,
#' and approval tracking.
#'
#' @name crf_review
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' @keywords internal
safe_scalar_rev <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' @keywords internal
safe_int_rev <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize CRF Review Workflow System
#'
#' Creates database tables for CRF design review workflow.
#'
#' @return List with success status and message
#' @export
init_crf_review <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_review_cycles (
        cycle_id INTEGER PRIMARY KEY AUTOINCREMENT,
        crf_id INTEGER NOT NULL,
        version_id INTEGER,
        cycle_number INTEGER NOT NULL,
        cycle_type TEXT NOT NULL,
        cycle_status TEXT DEFAULT 'OPEN',
        cycle_title TEXT NOT NULL,
        cycle_description TEXT,
        target_completion_date TEXT,
        priority TEXT DEFAULT 'NORMAL',
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        started_at TEXT,
        completed_at TEXT,
        completed_by TEXT,
        cycle_hash TEXT NOT NULL,
        FOREIGN KEY (crf_id) REFERENCES crf_definitions(crf_id),
        FOREIGN KEY (version_id) REFERENCES crf_versions(version_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_review_stages (
        stage_id INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_id INTEGER NOT NULL,
        stage_order INTEGER NOT NULL,
        stage_name TEXT NOT NULL,
        stage_type TEXT NOT NULL,
        stage_status TEXT DEFAULT 'PENDING',
        required_approvers INTEGER DEFAULT 1,
        current_approvers INTEGER DEFAULT 0,
        instructions TEXT,
        started_at TEXT,
        completed_at TEXT,
        stage_hash TEXT NOT NULL,
        FOREIGN KEY (cycle_id) REFERENCES crf_review_cycles(cycle_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_reviewers (
        assignment_id INTEGER PRIMARY KEY AUTOINCREMENT,
        stage_id INTEGER NOT NULL,
        reviewer_id TEXT NOT NULL,
        reviewer_name TEXT NOT NULL,
        reviewer_role TEXT NOT NULL,
        assignment_status TEXT DEFAULT 'ASSIGNED',
        assigned_at TEXT DEFAULT (datetime('now')),
        assigned_by TEXT NOT NULL,
        response_due_date TEXT,
        started_at TEXT,
        completed_at TEXT,
        decision TEXT,
        decision_notes TEXT,
        assignment_hash TEXT NOT NULL,
        FOREIGN KEY (stage_id) REFERENCES crf_review_stages(stage_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_review_comments (
        comment_id INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_id INTEGER NOT NULL,
        stage_id INTEGER,
        assignment_id INTEGER,
        parent_comment_id INTEGER,
        comment_type TEXT NOT NULL,
        comment_category TEXT,
        field_reference TEXT,
        section_reference TEXT,
        comment_text TEXT NOT NULL,
        severity TEXT DEFAULT 'MEDIUM',
        status TEXT DEFAULT 'OPEN',
        resolution TEXT,
        resolved_at TEXT,
        resolved_by TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        comment_hash TEXT NOT NULL,
        FOREIGN KEY (cycle_id) REFERENCES crf_review_cycles(cycle_id),
        FOREIGN KEY (stage_id) REFERENCES crf_review_stages(stage_id),
        FOREIGN KEY (assignment_id) REFERENCES crf_reviewers(assignment_id),
        FOREIGN KEY (parent_comment_id) REFERENCES crf_review_comments(comment_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_review_decisions (
        decision_id INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_id INTEGER NOT NULL,
        stage_id INTEGER NOT NULL,
        assignment_id INTEGER NOT NULL,
        decision TEXT NOT NULL,
        decision_rationale TEXT,
        conditions TEXT,
        follow_up_required INTEGER DEFAULT 0,
        follow_up_description TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        decision_hash TEXT NOT NULL,
        FOREIGN KEY (cycle_id) REFERENCES crf_review_cycles(cycle_id),
        FOREIGN KEY (stage_id) REFERENCES crf_review_stages(stage_id),
        FOREIGN KEY (assignment_id) REFERENCES crf_reviewers(assignment_id)
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_review_cycles_crf
                         ON crf_review_cycles(crf_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_review_stages_cycle
                         ON crf_review_stages(cycle_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_reviewers_stage
                         ON crf_reviewers(stage_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_comments_cycle
                         ON crf_review_comments(cycle_id)")

    list(success = TRUE, message = "CRF review workflow system initialized")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Review Cycle Types
#' @return Named character vector of cycle types
#' @export
get_review_cycle_types <- function() {
  c(
    INITIAL = "Initial design review",
    REVISION = "Revision review",
    AMENDMENT = "Protocol amendment review",
    PERIODIC = "Periodic review",
    FINAL = "Final approval review",
    EXPEDITED = "Expedited review"
  )
}

#' Get Review Cycle Statuses
#' @return Named character vector of cycle statuses
#' @export
get_review_cycle_statuses <- function() {
  c(
    OPEN = "Review cycle open",
    IN_PROGRESS = "Review in progress",
    PENDING_DECISION = "Awaiting final decision",
    APPROVED = "Approved",
    REJECTED = "Rejected",
    REVISION_REQUIRED = "Revision required",
    CANCELLED = "Cancelled"
  )
}

#' Get Review Stage Types
#' @return Named character vector of stage types
#' @export
get_review_stage_types <- function() {
  c(
    TECHNICAL = "Technical review",
    CLINICAL = "Clinical/medical review",
    REGULATORY = "Regulatory review",
    DATA_MANAGEMENT = "Data management review",
    STATISTICAL = "Statistical review",
    QA = "Quality assurance review",
    SPONSOR = "Sponsor review",
    FINAL_APPROVAL = "Final approval"
  )
}

#' Get Review Decisions
#' @return Named character vector of decisions
#' @export
get_review_decisions <- function() {
  c(
    APPROVE = "Approved as submitted",
    APPROVE_WITH_CONDITIONS = "Approved with conditions",
    REVISION_REQUIRED = "Revision required before approval",
    REJECT = "Rejected",
    DEFER = "Decision deferred",
    ABSTAIN = "Abstain from decision"
  )
}

#' Get Comment Types
#' @return Named character vector of comment types
#' @export
get_review_comment_types <- function() {
  c(
    QUESTION = "Question requiring clarification",
    SUGGESTION = "Suggestion for improvement",
    ISSUE = "Issue requiring resolution",
    OBSERVATION = "General observation",
    APPROVAL = "Approval note",
    REJECTION = "Rejection reason"
  )
}

#' Get Comment Severities
#' @return Named character vector of severities
#' @export
get_review_comment_severities <- function() {
  c(
    CRITICAL = "Must be addressed before approval",
    HIGH = "Should be addressed",
    MEDIUM = "Recommended to address",
    LOW = "Minor observation",
    INFO = "Informational only"
  )
}

# ============================================================================
# REVIEW CYCLE MANAGEMENT
# ============================================================================

#' Create Review Cycle
#'
#' Creates a new review cycle for a CRF.
#'
#' @param crf_id CRF ID
#' @param cycle_type Type from get_review_cycle_types()
#' @param cycle_title Title for the review cycle
#' @param created_by User creating the cycle
#' @param version_id Optional version ID
#' @param cycle_description Optional description
#' @param target_completion_date Optional target date
#' @param priority Priority level (LOW, NORMAL, HIGH, URGENT)
#'
#' @return List with success status and cycle details
#' @export
create_review_cycle <- function(crf_id,
                                 cycle_type,
                                 cycle_title,
                                 created_by,
                                 version_id = NULL,
                                 cycle_description = NULL,
                                 target_completion_date = NULL,
                                 priority = "NORMAL") {
  tryCatch({
    if (missing(crf_id) || is.null(crf_id)) {
      return(list(success = FALSE, error = "crf_id is required"))
    }
    if (missing(cycle_title) || is.null(cycle_title) || cycle_title == "") {
      return(list(success = FALSE, error = "cycle_title is required"))
    }

    valid_types <- names(get_review_cycle_types())
    if (!cycle_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid cycle_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    if (!priority %in% c("LOW", "NORMAL", "HIGH", "URGENT")) {
      return(list(success = FALSE,
                  error = "priority must be LOW, NORMAL, HIGH, or URGENT"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    cycle_count <- DBI::dbGetQuery(con, "
      SELECT COALESCE(MAX(cycle_number), 0) + 1 as next_num
      FROM crf_review_cycles WHERE crf_id = ?
    ", params = list(crf_id))$next_num[1]

    hash_content <- paste(
      crf_id,
      cycle_count,
      cycle_type,
      cycle_title,
      created_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    cycle_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_review_cycles (
        crf_id, version_id, cycle_number, cycle_type, cycle_title,
        cycle_description, target_completion_date, priority,
        created_by, cycle_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      crf_id,
      safe_int_rev(version_id),
      cycle_count,
      cycle_type,
      cycle_title,
      safe_scalar_rev(cycle_description),
      safe_scalar_rev(target_completion_date),
      priority,
      created_by,
      cycle_hash
    ))

    cycle_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      cycle_id = cycle_id,
      cycle_number = cycle_count,
      cycle_type = cycle_type,
      message = "Review cycle created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Review Cycles
#'
#' Retrieves review cycles for a CRF.
#'
#' @param crf_id CRF ID
#' @param status Optional filter by status
#'
#' @return List with success status and cycles
#' @export
get_review_cycles <- function(crf_id, status = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(status)) {
      cycles <- DBI::dbGetQuery(con, "
        SELECT * FROM crf_review_cycles
        WHERE crf_id = ?
        ORDER BY cycle_number DESC
      ", params = list(crf_id))
    } else {
      cycles <- DBI::dbGetQuery(con, "
        SELECT * FROM crf_review_cycles
        WHERE crf_id = ? AND cycle_status = ?
        ORDER BY cycle_number DESC
      ", params = list(crf_id, status))
    }

    list(success = TRUE, cycles = cycles, count = nrow(cycles))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Start Review Cycle
#'
#' Starts a review cycle, changing status to IN_PROGRESS.
#'
#' @param cycle_id Cycle ID
#' @param started_by User starting the cycle
#'
#' @return List with success status
#' @export
start_review_cycle <- function(cycle_id, started_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE crf_review_cycles
      SET cycle_status = 'IN_PROGRESS',
          started_at = ?
      WHERE cycle_id = ?
    ", params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), cycle_id))

    list(success = TRUE, message = "Review cycle started")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Complete Review Cycle
#'
#' Completes a review cycle with final status.
#'
#' @param cycle_id Cycle ID
#' @param final_status Final status (APPROVED, REJECTED, etc.)
#' @param completed_by User completing the cycle
#'
#' @return List with success status
#' @export
complete_review_cycle <- function(cycle_id, final_status, completed_by) {
  tryCatch({
    valid_statuses <- c("APPROVED", "REJECTED", "REVISION_REQUIRED", "CANCELLED")
    if (!final_status %in% valid_statuses) {
      return(list(
        success = FALSE,
        error = paste("final_status must be one of:",
                     paste(valid_statuses, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE crf_review_cycles
      SET cycle_status = ?,
          completed_at = ?,
          completed_by = ?
      WHERE cycle_id = ?
    ", params = list(
      final_status,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      completed_by,
      cycle_id
    ))

    list(success = TRUE, message = paste("Review cycle completed:", final_status))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REVIEW STAGE MANAGEMENT
# ============================================================================

#' Add Review Stage
#'
#' Adds a review stage to a cycle.
#'
#' @param cycle_id Cycle ID
#' @param stage_name Stage name
#' @param stage_type Type from get_review_stage_types()
#' @param stage_order Order in the workflow
#' @param created_by User creating the stage
#' @param required_approvers Number of required approvers
#' @param instructions Optional instructions
#'
#' @return List with success status and stage details
#' @export
add_review_stage <- function(cycle_id,
                              stage_name,
                              stage_type,
                              stage_order,
                              created_by,
                              required_approvers = 1,
                              instructions = NULL) {
  tryCatch({
    if (missing(cycle_id) || is.null(cycle_id)) {
      return(list(success = FALSE, error = "cycle_id is required"))
    }
    if (missing(stage_name) || is.null(stage_name) || stage_name == "") {
      return(list(success = FALSE, error = "stage_name is required"))
    }

    valid_types <- names(get_review_stage_types())
    if (!stage_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid stage_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    hash_content <- paste(
      cycle_id,
      stage_name,
      stage_type,
      stage_order,
      created_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    stage_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_review_stages (
        cycle_id, stage_order, stage_name, stage_type,
        required_approvers, instructions, stage_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      cycle_id,
      as.integer(stage_order),
      stage_name,
      stage_type,
      as.integer(required_approvers),
      safe_scalar_rev(instructions),
      stage_hash
    ))

    stage_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      stage_id = stage_id,
      stage_name = stage_name,
      message = "Review stage added"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Review Stages
#'
#' Retrieves stages for a review cycle.
#'
#' @param cycle_id Cycle ID
#'
#' @return List with success status and stages
#' @export
get_review_stages <- function(cycle_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stages <- DBI::dbGetQuery(con, "
      SELECT * FROM crf_review_stages
      WHERE cycle_id = ?
      ORDER BY stage_order
    ", params = list(cycle_id))

    list(success = TRUE, stages = stages, count = nrow(stages))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update Stage Status
#'
#' Updates the status of a review stage.
#'
#' @param stage_id Stage ID
#' @param status New status
#' @param updated_by User updating status
#'
#' @return List with success status
#' @export
update_stage_status <- function(stage_id, status, updated_by) {
  tryCatch({
    valid_statuses <- c("PENDING", "IN_PROGRESS", "COMPLETED", "SKIPPED")
    if (!status %in% valid_statuses) {
      return(list(
        success = FALSE,
        error = paste("status must be one of:",
                     paste(valid_statuses, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    if (status == "IN_PROGRESS") {
      DBI::dbExecute(con, "
        UPDATE crf_review_stages
        SET stage_status = ?, started_at = ?
        WHERE stage_id = ?
      ", params = list(status, timestamp, stage_id))
    } else if (status == "COMPLETED") {
      DBI::dbExecute(con, "
        UPDATE crf_review_stages
        SET stage_status = ?, completed_at = ?
        WHERE stage_id = ?
      ", params = list(status, timestamp, stage_id))
    } else {
      DBI::dbExecute(con, "
        UPDATE crf_review_stages
        SET stage_status = ?
        WHERE stage_id = ?
      ", params = list(status, stage_id))
    }

    list(success = TRUE, message = paste("Stage status updated to", status))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REVIEWER MANAGEMENT
# ============================================================================

#' Assign Reviewer
#'
#' Assigns a reviewer to a stage.
#'
#' @param stage_id Stage ID
#' @param reviewer_id Reviewer user ID
#' @param reviewer_name Reviewer display name
#' @param reviewer_role Role in the review
#' @param assigned_by User making assignment
#' @param response_due_date Optional due date
#'
#' @return List with success status and assignment details
#' @export
assign_reviewer <- function(stage_id,
                             reviewer_id,
                             reviewer_name,
                             reviewer_role,
                             assigned_by,
                             response_due_date = NULL) {
  tryCatch({
    if (missing(stage_id) || is.null(stage_id)) {
      return(list(success = FALSE, error = "stage_id is required"))
    }
    if (missing(reviewer_id) || is.null(reviewer_id) || reviewer_id == "") {
      return(list(success = FALSE, error = "reviewer_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    hash_content <- paste(
      stage_id,
      reviewer_id,
      reviewer_role,
      assigned_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    assignment_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_reviewers (
        stage_id, reviewer_id, reviewer_name, reviewer_role,
        assigned_by, response_due_date, assignment_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      stage_id,
      reviewer_id,
      reviewer_name,
      reviewer_role,
      assigned_by,
      safe_scalar_rev(response_due_date),
      assignment_hash
    ))

    assignment_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      assignment_id = assignment_id,
      reviewer_id = reviewer_id,
      message = paste("Reviewer", reviewer_name, "assigned")
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Stage Reviewers
#'
#' Retrieves reviewers for a stage.
#'
#' @param stage_id Stage ID
#'
#' @return List with success status and reviewers
#' @export
get_stage_reviewers <- function(stage_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    reviewers <- DBI::dbGetQuery(con, "
      SELECT * FROM crf_reviewers
      WHERE stage_id = ?
      ORDER BY assigned_at
    ", params = list(stage_id))

    list(success = TRUE, reviewers = reviewers, count = nrow(reviewers))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Submit Review Decision
#'
#' Submits a reviewer's decision.
#'
#' @param assignment_id Assignment ID
#' @param decision Decision from get_review_decisions()
#' @param decision_rationale Rationale for decision
#' @param submitted_by User submitting
#' @param conditions Optional conditions
#' @param follow_up_required Whether follow-up needed
#' @param follow_up_description Description of follow-up
#'
#' @return List with success status
#' @export
submit_review_decision <- function(assignment_id,
                                    decision,
                                    decision_rationale,
                                    submitted_by,
                                    conditions = NULL,
                                    follow_up_required = FALSE,
                                    follow_up_description = NULL) {
  tryCatch({
    valid_decisions <- names(get_review_decisions())
    if (!decision %in% valid_decisions) {
      return(list(
        success = FALSE,
        error = paste("Invalid decision. Must be one of:",
                     paste(valid_decisions, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    assignment <- DBI::dbGetQuery(con, "
      SELECT stage_id FROM crf_reviewers WHERE assignment_id = ?
    ", params = list(assignment_id))

    if (nrow(assignment) == 0) {
      return(list(success = FALSE, error = "Assignment not found"))
    }

    stage <- DBI::dbGetQuery(con, "
      SELECT cycle_id FROM crf_review_stages WHERE stage_id = ?
    ", params = list(assignment$stage_id[1]))

    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE crf_reviewers
      SET assignment_status = 'COMPLETED',
          completed_at = ?,
          decision = ?,
          decision_notes = ?
      WHERE assignment_id = ?
    ", params = list(timestamp, decision, decision_rationale, assignment_id))

    hash_content <- paste(
      stage$cycle_id[1],
      assignment$stage_id[1],
      assignment_id,
      decision,
      submitted_by,
      timestamp,
      sep = "|"
    )
    decision_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_review_decisions (
        cycle_id, stage_id, assignment_id, decision, decision_rationale,
        conditions, follow_up_required, follow_up_description,
        created_by, decision_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      stage$cycle_id[1],
      assignment$stage_id[1],
      assignment_id,
      decision,
      decision_rationale,
      safe_scalar_rev(conditions),
      as.integer(follow_up_required),
      safe_scalar_rev(follow_up_description),
      submitted_by,
      decision_hash
    ))

    if (decision == "APPROVE" || decision == "APPROVE_WITH_CONDITIONS") {
      DBI::dbExecute(con, "
        UPDATE crf_review_stages
        SET current_approvers = current_approvers + 1
        WHERE stage_id = ?
      ", params = list(assignment$stage_id[1]))
    }

    list(success = TRUE, decision = decision, message = "Decision submitted")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# COMMENT MANAGEMENT
# ============================================================================

#' Add Review Comment
#'
#' Adds a comment to a review cycle.
#'
#' @param cycle_id Cycle ID
#' @param comment_type Type from get_review_comment_types()
#' @param comment_text Comment text
#' @param created_by User creating comment
#' @param stage_id Optional stage ID
#' @param assignment_id Optional assignment ID
#' @param comment_category Optional category
#' @param field_reference Optional field reference
#' @param section_reference Optional section reference
#' @param severity Severity level
#' @param parent_comment_id Optional parent for threading
#'
#' @return List with success status and comment details
#' @export
add_review_comment <- function(cycle_id,
                                comment_type,
                                comment_text,
                                created_by,
                                stage_id = NULL,
                                assignment_id = NULL,
                                comment_category = NULL,
                                field_reference = NULL,
                                section_reference = NULL,
                                severity = "MEDIUM",
                                parent_comment_id = NULL) {
  tryCatch({
    if (missing(cycle_id) || is.null(cycle_id)) {
      return(list(success = FALSE, error = "cycle_id is required"))
    }
    if (missing(comment_text) || is.null(comment_text) ||
        nchar(comment_text) < 5) {
      return(list(success = FALSE,
                  error = "comment_text must be at least 5 characters"))
    }

    valid_types <- names(get_review_comment_types())
    if (!comment_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid comment_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    valid_severities <- names(get_review_comment_severities())
    if (!severity %in% valid_severities) {
      return(list(
        success = FALSE,
        error = paste("Invalid severity. Must be one of:",
                     paste(valid_severities, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    hash_content <- paste(
      cycle_id,
      comment_type,
      comment_text,
      created_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    comment_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_review_comments (
        cycle_id, stage_id, assignment_id, parent_comment_id,
        comment_type, comment_category, field_reference, section_reference,
        comment_text, severity, created_by, comment_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      cycle_id,
      safe_int_rev(stage_id),
      safe_int_rev(assignment_id),
      safe_int_rev(parent_comment_id),
      comment_type,
      safe_scalar_rev(comment_category),
      safe_scalar_rev(field_reference),
      safe_scalar_rev(section_reference),
      comment_text,
      severity,
      created_by,
      comment_hash
    ))

    comment_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      comment_id = comment_id,
      comment_type = comment_type,
      message = "Comment added"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Review Comments
#'
#' Retrieves comments for a review cycle.
#'
#' @param cycle_id Cycle ID
#' @param status Optional filter by status
#' @param severity Optional filter by severity
#'
#' @return List with success status and comments
#' @export
get_review_comments <- function(cycle_id, status = NULL, severity = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM crf_review_comments WHERE cycle_id = ?"
    params <- list(cycle_id)

    if (!is.null(status)) {
      query <- paste(query, "AND status = ?")
      params <- append(params, list(status))
    }

    if (!is.null(severity)) {
      query <- paste(query, "AND severity = ?")
      params <- append(params, list(severity))
    }

    query <- paste(query, "ORDER BY created_at")

    comments <- DBI::dbGetQuery(con, query, params = params)

    list(success = TRUE, comments = comments, count = nrow(comments))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Resolve Comment
#'
#' Resolves a review comment.
#'
#' @param comment_id Comment ID
#' @param resolution Resolution text
#' @param resolved_by User resolving
#'
#' @return List with success status
#' @export
resolve_comment <- function(comment_id, resolution, resolved_by) {
  tryCatch({
    if (missing(resolution) || is.null(resolution) || nchar(resolution) < 5) {
      return(list(success = FALSE,
                  error = "resolution must be at least 5 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE crf_review_comments
      SET status = 'RESOLVED',
          resolution = ?,
          resolved_at = ?,
          resolved_by = ?
      WHERE comment_id = ?
    ", params = list(
      resolution,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      resolved_by,
      comment_id
    ))

    list(success = TRUE, message = "Comment resolved")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# STATISTICS
# ============================================================================

#' Get Review Statistics
#'
#' Returns statistics about CRF reviews.
#'
#' @param crf_id Optional CRF ID to filter
#'
#' @return List with statistics
#' @export
get_review_statistics <- function(crf_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(crf_id)) {
      cycle_stats <- DBI::dbGetQuery(con, "
        SELECT
          COUNT(*) as total_cycles,
          SUM(CASE WHEN cycle_status = 'APPROVED' THEN 1 ELSE 0 END) as approved,
          SUM(CASE WHEN cycle_status = 'IN_PROGRESS' THEN 1 ELSE 0 END) as in_progress,
          SUM(CASE WHEN cycle_status = 'OPEN' THEN 1 ELSE 0 END) as open
        FROM crf_review_cycles
      ")

      comment_stats <- DBI::dbGetQuery(con, "
        SELECT
          COUNT(*) as total_comments,
          SUM(CASE WHEN status = 'OPEN' THEN 1 ELSE 0 END) as open_comments,
          SUM(CASE WHEN severity = 'CRITICAL' THEN 1 ELSE 0 END) as critical
        FROM crf_review_comments
      ")
    } else {
      cycle_stats <- DBI::dbGetQuery(con, "
        SELECT
          COUNT(*) as total_cycles,
          SUM(CASE WHEN cycle_status = 'APPROVED' THEN 1 ELSE 0 END) as approved,
          SUM(CASE WHEN cycle_status = 'IN_PROGRESS' THEN 1 ELSE 0 END) as in_progress,
          SUM(CASE WHEN cycle_status = 'OPEN' THEN 1 ELSE 0 END) as open
        FROM crf_review_cycles
        WHERE crf_id = ?
      ", params = list(crf_id))

      comment_stats <- DBI::dbGetQuery(con, "
        SELECT
          COUNT(*) as total_comments,
          SUM(CASE WHEN status = 'OPEN' THEN 1 ELSE 0 END) as open_comments,
          SUM(CASE WHEN severity = 'CRITICAL' THEN 1 ELSE 0 END) as critical
        FROM crf_review_comments c
        JOIN crf_review_cycles cy ON c.cycle_id = cy.cycle_id
        WHERE cy.crf_id = ?
      ", params = list(crf_id))
    }

    list(
      success = TRUE,
      cycles = as.list(cycle_stats),
      comments = as.list(comment_stats)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
