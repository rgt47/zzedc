#' Google Sheets Change Monitor
#'
#' Polls the `Study_Users` tab of each site's Google Sheets workbook
#' for coordinator edits, stages proposed changes in the database
#' without modifying the live user roster, notifies the study manager,
#' and applies approved changes on the manager's instruction.
#'
#' ## Access model
#'
#' Each site coordinator holds editor access to the `Study_Users` tab
#' of their site's workbook only. The `Data_Dictionary` and
#' `validation_rules` tabs are viewer-only for coordinators (enforced
#' via Google Sheets tab protection). This file implements the
#' change-detection and approval layer for `Study_Users` edits.
#'
#' The validation-rule diff/stage/approve functions
#' ([diff_gsheets_rules()], [stage_gsheets_proposals()],
#' [approve_proposals()], [reject_proposals()]) are retained for
#' data-scientist-initiated rule changes and are not part of the
#' coordinator-facing workflow.
#'
#' ## Workflow
#'
#' 1. A cron job calls [poll_gsheets_and_stage()] for each site workbook.
#' 2. The function reads the `Study_Users` tab, diffs it against the
#'    live `edc_users` table, and writes any new or changed rows to
#'    the `user_proposals` staging table with `status = 'PENDING'`.
#'    The live user roster is not touched.
#' 3. The notifier function is called with a data frame of pending
#'    proposals. The default notifier writes a plain-text summary to a
#'    log file; supply a custom function to send email.
#' 4. The manager reviews proposals and calls [approve_user_proposals()]
#'    or [reject_user_proposals()]. Approval upserts the user into
#'    `edc_users`; rejection records the decision and leaves the roster
#'    unchanged.
#'
#' @name gsheets_monitor
NULL

# ============================================================================
# Schema initialisation
# ============================================================================

#' Initialise the Rule Proposals Table
#'
#' Creates `dsl_rule_proposals` if it does not already exist. Called
#' automatically by [poll_gsheets_and_stage()] on first use.
#'
#' @param db_path Path to the ZZedc SQLite database. When `NULL` the
#'   value returned by `get_db_path()` is used.
#'
#' @return Invisibly returns `TRUE` on success.
#'
#' @keywords internal
init_proposals_table <- function(db_path = NULL) {
  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS dsl_rule_proposals (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      proposal_id     TEXT UNIQUE NOT NULL,
      rule_id         TEXT NOT NULL,
      change_type     TEXT NOT NULL,
      proposed_dsl    TEXT,
      current_dsl     TEXT,
      field_code      TEXT,
      form_code       TEXT,
      rule_name       TEXT,
      error_message   TEXT,
      severity        TEXT,
      rule_category   TEXT,
      sheet_id        TEXT NOT NULL,
      staged_by       TEXT NOT NULL,
      staged_at       TEXT NOT NULL,
      status          TEXT NOT NULL DEFAULT 'PENDING',
      reviewed_by     TEXT,
      reviewed_at     TEXT,
      review_comments TEXT
    )
  ")

  invisible(TRUE)
}

# ============================================================================
# Change detection
# ============================================================================

#' Diff Google Sheet Rules Against Live Database Rules
#'
#' Reads `sheet_name` from `sheet_id` and compares each row against the
#' current `dsl_validation_rules` table. Returns a list of new, modified,
#' and deleted rules. Deleted rules are flagged but never automatically
#' removed from the database.
#'
#' @param sheet_id Google Sheets ID or full URL.
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#' @param sheet_name Name of the tab containing validation rules.
#'
#' @return A list with elements `new`, `modified`, and `deleted`, each a
#'   data frame of rule rows from the sheet (or database for `deleted`).
#'
#' @export
diff_gsheets_rules <- function(sheet_id,
                                db_path    = NULL,
                                sheet_name = 'validation_rules') {
  if (!requireNamespace('googlesheets4', quietly = TRUE)) {
    stop(
      "Package 'googlesheets4' is required. ",
      "Install with: install.packages('googlesheets4')"
    )
  }

  sheet_rules <- googlesheets4::read_sheet(sheet_id, sheet = sheet_name)

  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  db_rules <- DBI::dbGetQuery(
    con,
    "SELECT rule_id, rule_dsl FROM dsl_validation_rules"
  )

  sheet_ids <- as.character(sheet_rules$rule_id)
  db_ids    <- db_rules$rule_id

  new_rows  <- sheet_rules[!sheet_ids %in% db_ids, , drop = FALSE]

  common_ids <- sheet_ids[sheet_ids %in% db_ids]
  if (length(common_ids) > 0) {
    sheet_common <- sheet_rules[sheet_ids %in% common_ids, , drop = FALSE]
    db_map       <- stats::setNames(db_rules$rule_dsl, db_rules$rule_id)
    changed      <- vapply(
      seq_len(nrow(sheet_common)),
      function(i) {
        rid <- as.character(sheet_common$rule_id[i])
        !identical(
          as.character(sheet_common$rule_dsl[i]),
          as.character(db_map[rid])
        )
      },
      logical(1)
    )
    modified_rows <- sheet_common[changed, , drop = FALSE]
  } else {
    modified_rows <- sheet_rules[integer(0), , drop = FALSE]
  }

  deleted_rows <- db_rules[!db_ids %in% sheet_ids, , drop = FALSE]

  list(new = new_rows, modified = modified_rows, deleted = deleted_rows)
}

# ============================================================================
# Staging
# ============================================================================

#' Stage Proposed Rule Changes
#'
#' Writes each row in `diff` to the `dsl_rule_proposals` table with
#' `status = 'PENDING'`. Live rules in `dsl_validation_rules` are not
#' modified. Any rule already in `PENDING` state for the same `rule_id`
#' is updated in place rather than duplicated.
#'
#' @param diff Output of [diff_gsheets_rules()].
#' @param sheet_id Google Sheets ID (stored with each proposal for
#'   traceability).
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#' @param staged_by Username of the account performing the staging
#'   (typically the cron service account, e.g. `'system_monitor'`).
#'
#' @return A list with `staged` (count of proposals written) and
#'   `skipped` (count already in `PENDING` with identical content).
#'
#' @keywords internal
stage_gsheets_proposals <- function(diff, sheet_id, db_path = NULL,
                                     staged_by = 'system_monitor') {
  init_proposals_table(db_path = db_path)

  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  staged  <- 0L
  skipped <- 0L
  now     <- as.character(Sys.time())

  write_proposal <- function(row, change_type) {
    rid         <- as.character(row$rule_id)
    proposed_dsl <- as.character(row$rule_dsl)
    proposal_id <- paste0(rid, '_', gsub('[^0-9]', '', now))

    existing <- DBI::dbGetQuery(
      con,
      "SELECT id, proposed_dsl FROM dsl_rule_proposals
         WHERE rule_id = ? AND status = 'PENDING'
         ORDER BY staged_at DESC LIMIT 1",
      params = list(rid)
    )

    if (nrow(existing) > 0 &&
        identical(existing$proposed_dsl[1], proposed_dsl)) {
      skipped <<- skipped + 1L
      return(invisible(NULL))
    }

    if (nrow(existing) > 0) {
      DBI::dbExecute(
        con,
        "UPDATE dsl_rule_proposals
           SET proposed_dsl = ?, staged_by = ?, staged_at = ?
         WHERE id = ?",
        params = list(proposed_dsl, staged_by, now, existing$id[1])
      )
    } else {
      current_dsl <- if (change_type == 'MODIFIED') {
        res <- DBI::dbGetQuery(
          con,
          "SELECT rule_dsl FROM dsl_validation_rules WHERE rule_id = ?",
          params = list(rid)
        )
        if (nrow(res) > 0) res$rule_dsl[1] else NA_character_
      } else {
        NA_character_
      }

      DBI::dbExecute(
        con,
        "INSERT INTO dsl_rule_proposals
           (proposal_id, rule_id, change_type, proposed_dsl, current_dsl,
            field_code, form_code, rule_name, error_message, severity,
            rule_category, sheet_id, staged_by, staged_at, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING')",
        params = list(
          proposal_id, rid, change_type, proposed_dsl, current_dsl,
          if ('field_code'     %in% names(row)) as.character(row$field_code)     else NA,
          if ('form_code'      %in% names(row)) as.character(row$form_code)      else NA,
          if ('rule_name'      %in% names(row)) as.character(row$rule_name)      else NA,
          if ('error_message'  %in% names(row)) as.character(row$error_message)  else NA,
          if ('severity'       %in% names(row)) as.character(row$severity)       else 'ERROR',
          if ('rule_category'  %in% names(row)) as.character(row$rule_category)  else 'FIELD',
          as.character(sheet_id), staged_by, now
        )
      )
    }

    staged <<- staged + 1L
  }

  if (nrow(diff$new) > 0) {
    for (i in seq_len(nrow(diff$new))) write_proposal(diff$new[i, ], 'NEW')
  }
  if (nrow(diff$modified) > 0) {
    for (i in seq_len(nrow(diff$modified))) write_proposal(diff$modified[i, ], 'MODIFIED')
  }

  list(staged = staged, skipped = skipped)
}

# ============================================================================
# Notification
# ============================================================================

#' Retrieve Pending Proposals
#'
#' Returns all proposals currently in `PENDING` status.
#'
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#'
#' @return Data frame of pending proposals, or an empty data frame if
#'   none exist.
#'
#' @export
get_pending_proposals <- function(db_path = NULL) {
  tryCatch({
    con <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    DBI::dbGetQuery(
      con,
      "SELECT id, proposal_id, rule_id, change_type,
              current_dsl, proposed_dsl, field_code,
              form_code, staged_by, staged_at
         FROM dsl_rule_proposals
        WHERE status = 'PENDING'
        ORDER BY staged_at DESC"
    )
  }, error = function(e) {
    data.frame()
  })
}

#' Default Notifier: Write Pending Proposals to a Log File
#'
#' Writes a plain-text summary of pending proposals to
#' `ZZEDC_PROPOSAL_LOG` (if set) or `~/zzedc_pending_proposals.log`.
#' Supply a replacement function as the `notifier` argument of
#' [poll_gsheets_and_stage()] to send email instead.
#'
#' @param proposals Data frame returned by [get_pending_proposals()].
#'
#' @return Invisibly returns the log file path.
#'
#' @export
default_proposal_notifier <- function(proposals) {
  log_path <- Sys.getenv('ZZEDC_PROPOSAL_LOG',
                          unset = '~/zzedc_pending_proposals.log')
  log_path <- path.expand(log_path)

  lines <- c(
    paste0('--- ZZedc pending rule proposals: ',
           format(Sys.time(), '%Y-%m-%d %H:%M %Z'), ' ---'),
    paste0(nrow(proposals), ' proposal(s) awaiting review.'),
    '',
    apply(proposals, 1, function(r) {
      paste0(
        '[', r['change_type'], '] ', r['rule_id'],
        ' (field: ', r['field_code'], ')',
        '\n  Current : ', r['current_dsl'],
        '\n  Proposed: ', r['proposed_dsl'],
        '\n  Staged  : ', r['staged_at']
      )
    }),
    '---'
  )

  cat(paste(lines, collapse = '\n'), '\n', file = log_path, append = TRUE)
  message('Pending proposals written to: ', log_path)
  invisible(log_path)
}

# ============================================================================
# Approval and rejection
# ============================================================================

#' Approve Pending Proposals
#'
#' For each `proposal_id` in `ids`: compiles and writes the proposed DSL
#' to the live `dsl_validation_rules` row (or inserts a new row for
#' `NEW` changes), sets `is_active = 1`, and records the approval
#' decision in `dsl_rule_proposals`. The live rule is rebuilt atomically
#' -- the old compiled R and SQL expressions are replaced with those
#' derived from the approved DSL.
#'
#' @param ids Character vector of `proposal_id` values to approve.
#' @param reviewer_id Username of the approving manager.
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#' @param comments Optional comments recorded on each approval.
#'
#' @return A list with `approved` (count) and `errors` (named list of
#'   rule IDs that failed with their error messages).
#'
#' @export
approve_proposals <- function(ids, reviewer_id, db_path = NULL,
                               comments = NULL) {
  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  approved <- 0L
  errors   <- list()
  now      <- as.character(Sys.time())

  for (pid in ids) {
    tryCatch({
      proposal <- DBI::dbGetQuery(
        con,
        "SELECT * FROM dsl_rule_proposals WHERE proposal_id = ?",
        params = list(pid)
      )

      if (nrow(proposal) == 0) {
        errors[[pid]] <- 'Proposal not found'
        next
      }
      if (proposal$status[1] != 'PENDING') {
        errors[[pid]] <- paste0('Proposal status is ', proposal$status[1],
                                ', not PENDING')
        next
      }

      p <- proposal[1, ]

      compiled_r <- tryCatch({
        ast <- parse_dsl_rule(p$proposed_dsl)
        generate_r_validator(ast)
      }, error = function(e) NA_character_)

      compiled_sql <- tryCatch({
        ast <- parse_dsl_rule(p$proposed_dsl)
        generate_sql_check(ast, p$field_code)
      }, error = function(e) NA_character_)

      existing <- DBI::dbGetQuery(
        con,
        "SELECT id, version FROM dsl_validation_rules WHERE rule_id = ?",
        params = list(p$rule_id)
      )

      if (nrow(existing) > 0) {
        new_version <- existing$version[1] + 1L
        DBI::dbExecute(con, "
          UPDATE dsl_validation_rules
             SET rule_dsl        = ?,
                 compiled_r      = ?,
                 compiled_sql    = ?,
                 field_code      = COALESCE(?, field_code),
                 form_code       = COALESCE(?, form_code),
                 rule_name       = COALESCE(?, rule_name),
                 error_message   = COALESCE(?, error_message),
                 severity        = COALESCE(?, severity),
                 rule_category   = COALESCE(?, rule_category),
                 is_active       = 1,
                 approval_status = 'APPROVED',
                 approved_by     = ?,
                 approved_at     = ?,
                 updated_by      = ?,
                 updated_at      = ?,
                 version         = ?
           WHERE rule_id = ?",
          params = list(
            p$proposed_dsl, compiled_r, compiled_sql,
            p$field_code, p$form_code, p$rule_name,
            p$error_message, p$severity, p$rule_category,
            reviewer_id, now, reviewer_id, now,
            new_version, p$rule_id
          )
        )
      } else {
        DBI::dbExecute(con, "
          INSERT INTO dsl_validation_rules
            (rule_id, field_code, form_code, rule_name, rule_dsl,
             compiled_r, compiled_sql, error_message, severity,
             rule_category, is_active, requires_approval,
             approval_status, approved_by, approved_at,
             imported_by, imported_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0,
                  'APPROVED', ?, ?, ?, ?)",
          params = list(
            p$rule_id,
            p$field_code  %||% '',
            p$form_code,
            p$rule_name   %||% p$rule_id,
            p$proposed_dsl,
            compiled_r, compiled_sql,
            p$error_message,
            p$severity      %||% 'ERROR',
            p$rule_category %||% 'FIELD',
            reviewer_id, now, reviewer_id, now
          )
        )
      }

      DBI::dbExecute(con, "
        UPDATE dsl_rule_proposals
           SET status = 'APPROVED', reviewed_by = ?,
               reviewed_at = ?, review_comments = ?
         WHERE proposal_id = ?",
        params = list(reviewer_id, now, comments, pid)
      )

      log_dsl_rule_action(
        rule_id    = p$rule_id,
        action     = 'APPROVED_FROM_SHEET',
        old_value  = p$current_dsl,
        new_value  = p$proposed_dsl,
        changed_by = reviewer_id,
        reason     = comments,
        con        = con
      )

      approved <- approved + 1L
    }, error = function(e) {
      errors[[pid]] <<- e$message
    })
  }

  list(approved = approved, errors = errors)
}

#' Reject Pending Proposals
#'
#' Marks each proposal in `ids` as `REJECTED`. Live rules are not
#' modified. The rejection reason is recorded in the audit log.
#'
#' @param ids Character vector of `proposal_id` values to reject.
#' @param reviewer_id Username of the rejecting manager.
#' @param comments Required rationale for the rejection; recorded in
#'   the audit trail.
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#'
#' @return A list with `rejected` (count) and `errors`.
#'
#' @export
reject_proposals <- function(ids, reviewer_id, comments,
                              db_path = NULL) {
  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  rejected <- 0L
  errors   <- list()
  now      <- as.character(Sys.time())

  for (pid in ids) {
    tryCatch({
      proposal <- DBI::dbGetQuery(
        con,
        "SELECT * FROM dsl_rule_proposals WHERE proposal_id = ?",
        params = list(pid)
      )

      if (nrow(proposal) == 0) {
        errors[[pid]] <- 'Proposal not found'
        next
      }
      if (proposal$status[1] != 'PENDING') {
        errors[[pid]] <- paste0('Proposal status is ', proposal$status[1],
                                ', not PENDING')
        next
      }

      DBI::dbExecute(con, "
        UPDATE dsl_rule_proposals
           SET status = 'REJECTED', reviewed_by = ?,
               reviewed_at = ?, review_comments = ?
         WHERE proposal_id = ?",
        params = list(reviewer_id, now, comments, pid)
      )

      log_dsl_rule_action(
        rule_id    = proposal$rule_id[1],
        action     = 'REJECTED_FROM_SHEET',
        old_value  = proposal$current_dsl[1],
        new_value  = proposal$proposed_dsl[1],
        changed_by = reviewer_id,
        reason     = comments,
        con        = con
      )

      rejected <- rejected + 1L
    }, error = function(e) {
      errors[[pid]] <<- e$message
    })
  }

  list(rejected = rejected, errors = errors)
}

# ============================================================================
# Cron-facing orchestrator
# ============================================================================

#' Poll Google Sheet and Stage Proposed Changes
#'
#' Combines [diff_gsheets_rules()], [stage_gsheets_proposals()], and
#' notification into a single call suitable for a scheduled cron job.
#' When no changes are detected the function returns silently without
#' calling the notifier.
#'
#' @param sheet_id Google Sheets ID or full URL.
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#' @param staged_by Username recorded on each staged proposal.
#' @param sheet_name Name of the validation-rules tab in the workbook.
#' @param notifier A function that accepts a data frame of pending
#'   proposals and sends a notification. Defaults to
#'   [default_proposal_notifier()], which writes to a log file.
#'   Replace with a function that sends email for production use
#'   (see the technical guide for a `blastula` example).
#'
#' @return Invisibly returns a list with `new`, `modified`, `deleted`
#'   counts and `staged` count. Returns `NULL` silently if no changes
#'   were found.
#'
#' @examples
#' \dontrun{
#' poll_gsheets_and_stage(
#'   sheet_id  = 'https://docs.google.com/spreadsheets/d/YOUR_ID',
#'   db_path   = '~/prj/praz-large/data/praz-large.db',
#'   staged_by = 'system_monitor'
#' )
#' }
#'
#' @export
poll_gsheets_and_stage <- function(sheet_id,
                                    db_path    = NULL,
                                    staged_by  = 'system_monitor',
                                    sheet_name = 'Study_Users',
                                    notifier   = default_proposal_notifier) {
  diff <- diff_gsheets_users(
    sheet_id   = sheet_id,
    db_path    = db_path,
    sheet_name = sheet_name
  )

  n_changes <- nrow(diff$new) + nrow(diff$modified)

  if (n_changes == 0) {
    return(invisible(NULL))
  }

  stage_result <- stage_gsheets_user_proposals(
    diff      = diff,
    sheet_id  = sheet_id,
    db_path   = db_path,
    staged_by = staged_by
  )

  if (stage_result$staged > 0) {
    pending <- get_pending_user_proposals(db_path = db_path)
    notifier(pending)
  }

  invisible(list(
    new      = nrow(diff$new),
    modified = nrow(diff$modified),
    staged   = stage_result$staged
  ))
}

# ============================================================================
# User roster change detection, staging, and approval
# ============================================================================

#' Initialise the User Proposals Table
#'
#' Creates `user_proposals` if it does not already exist. Called
#' automatically by [poll_gsheets_and_stage()] on first use.
#'
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#'
#' @return Invisibly returns `TRUE` on success.
#'
#' @keywords internal
init_user_proposals_table <- function(db_path = NULL) {
  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS user_proposals (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      proposal_id        TEXT UNIQUE NOT NULL,
      username           TEXT NOT NULL,
      change_type        TEXT NOT NULL,
      proposed_full_name TEXT,
      proposed_email     TEXT,
      proposed_role      TEXT,
      proposed_site_id   TEXT,
      proposed_active    INTEGER,
      current_role       TEXT,
      current_email      TEXT,
      sheet_id           TEXT NOT NULL,
      staged_by          TEXT NOT NULL,
      staged_at          TEXT NOT NULL,
      status             TEXT NOT NULL DEFAULT 'PENDING',
      reviewed_by        TEXT,
      reviewed_at        TEXT,
      review_comments    TEXT
    )
  ")

  invisible(TRUE)
}

#' Diff Google Sheet Study_Users Against Live User Roster
#'
#' Reads `sheet_name` from `sheet_id` and compares each row against
#' the `edc_users` table. Returns new and modified users. Deletions
#' are not auto-staged; removing a user from the live roster requires
#' explicit data-scientist action.
#'
#' @param sheet_id Google Sheets ID or full URL.
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#' @param sheet_name Name of the tab containing the user roster.
#'
#' @return A list with elements `new` and `modified`, each a data
#'   frame of user rows from the sheet.
#'
#' @export
diff_gsheets_users <- function(sheet_id,
                                db_path    = NULL,
                                sheet_name = 'Study_Users') {
  if (!requireNamespace('googlesheets4', quietly = TRUE)) {
    stop(
      "Package 'googlesheets4' is required. ",
      "Install with: install.packages('googlesheets4')"
    )
  }

  sheet_users <- googlesheets4::read_sheet(sheet_id, sheet = sheet_name)
  sheet_users$username <- as.character(sheet_users$username)

  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  db_users <- DBI::dbGetQuery(
    con,
    "SELECT username, role, email FROM edc_users"
  )

  sheet_names <- sheet_users$username
  db_names    <- db_users$username

  new_rows <- sheet_users[!sheet_names %in% db_names, , drop = FALSE]

  common <- sheet_names[sheet_names %in% db_names]
  if (length(common) > 0) {
    sheet_common <- sheet_users[sheet_names %in% common, , drop = FALSE]
    db_map_role  <- stats::setNames(db_users$role,  db_users$username)
    db_map_email <- stats::setNames(db_users$email, db_users$username)

    changed <- vapply(seq_len(nrow(sheet_common)), function(i) {
      u <- sheet_common$username[i]
      role_changed  <- !identical(
        toupper(as.character(sheet_common$role[i])),
        toupper(as.character(db_map_role[u]))
      )
      email_changed <- !identical(
        as.character(sheet_common$email[i]),
        as.character(db_map_email[u])
      )
      role_changed || email_changed
    }, logical(1))

    modified_rows <- sheet_common[changed, , drop = FALSE]
  } else {
    modified_rows <- sheet_users[integer(0), , drop = FALSE]
  }

  list(new = new_rows, modified = modified_rows)
}

#' Stage Proposed User Roster Changes
#'
#' Writes each row in `diff` to the `user_proposals` table with
#' `status = 'PENDING'`. The live `edc_users` table is not modified.
#' An existing `PENDING` proposal for the same username is updated
#' in place if the proposed values have changed.
#'
#' @param diff Output of [diff_gsheets_users()].
#' @param sheet_id Google Sheets ID (stored for traceability).
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#' @param staged_by Username of the account performing the staging.
#'
#' @return A list with `staged` and `skipped` counts.
#'
#' @keywords internal
stage_gsheets_user_proposals <- function(diff, sheet_id,
                                          db_path   = NULL,
                                          staged_by = 'system_monitor') {
  init_user_proposals_table(db_path = db_path)

  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  staged  <- 0L
  skipped <- 0L
  now     <- as.character(Sys.time())

  write_user_proposal <- function(row, change_type) {
    uname        <- as.character(row$username)
    prop_role    <- as.character(row$role %||% NA)
    prop_email   <- as.character(row$email %||% NA)
    proposal_id  <- paste0(uname, '_', gsub('[^0-9]', '', now))

    existing <- DBI::dbGetQuery(
      con,
      "SELECT id, proposed_role, proposed_email
         FROM user_proposals
        WHERE username = ? AND status = 'PENDING'
        ORDER BY staged_at DESC LIMIT 1",
      params = list(uname)
    )

    if (nrow(existing) > 0 &&
        identical(existing$proposed_role[1],  prop_role) &&
        identical(existing$proposed_email[1], prop_email)) {
      skipped <<- skipped + 1L
      return(invisible(NULL))
    }

    current <- DBI::dbGetQuery(
      con,
      "SELECT role, email FROM edc_users WHERE username = ?",
      params = list(uname)
    )

    if (nrow(existing) > 0) {
      DBI::dbExecute(con, "
        UPDATE user_proposals
           SET proposed_role = ?, proposed_email = ?,
               staged_by = ?, staged_at = ?
         WHERE id = ?",
        params = list(prop_role, prop_email, staged_by, now,
                      existing$id[1])
      )
    } else {
      DBI::dbExecute(con, "
        INSERT INTO user_proposals
          (proposal_id, username, change_type,
           proposed_full_name, proposed_email, proposed_role,
           proposed_site_id, proposed_active,
           current_role, current_email,
           sheet_id, staged_by, staged_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING')",
        params = list(
          proposal_id, uname, change_type,
          if ('full_name'  %in% names(row)) as.character(row$full_name)  else NA,
          prop_email, prop_role,
          if ('site_id'    %in% names(row)) as.character(row$site_id)    else NA,
          if ('active'     %in% names(row)) as.integer(as.logical(row$active)) else 1L,
          if (nrow(current) > 0) current$role[1]  else NA,
          if (nrow(current) > 0) current$email[1] else NA,
          as.character(sheet_id), staged_by, now
        )
      )
    }

    staged <<- staged + 1L
  }

  if (nrow(diff$new) > 0) {
    for (i in seq_len(nrow(diff$new)))
      write_user_proposal(diff$new[i, ], 'NEW')
  }
  if (nrow(diff$modified) > 0) {
    for (i in seq_len(nrow(diff$modified)))
      write_user_proposal(diff$modified[i, ], 'MODIFIED')
  }

  list(staged = staged, skipped = skipped)
}

#' Retrieve Pending User Proposals
#'
#' Returns all user roster proposals currently in `PENDING` status.
#'
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#'
#' @return Data frame of pending proposals, or an empty data frame.
#'
#' @export
get_pending_user_proposals <- function(db_path = NULL) {
  tryCatch({
    con <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    DBI::dbGetQuery(con, "
      SELECT id, proposal_id, username, change_type,
             current_role, proposed_role,
             current_email, proposed_email,
             proposed_full_name, proposed_site_id,
             staged_by, staged_at
        FROM user_proposals
       WHERE status = 'PENDING'
       ORDER BY staged_at DESC
    ")
  }, error = function(e) data.frame())
}

#' Approve Pending User Proposals
#'
#' For each `proposal_id` in `ids`: inserts or updates the user in
#' `edc_users` from the proposal record, marks the proposal
#' `'APPROVED'`, and writes an audit entry. Passwords for `NEW` users
#' are set to a secure random initial value that the coordinator must
#' change on first login; the hash is recorded but never returned.
#'
#' @param ids Character vector of `proposal_id` values to approve.
#' @param reviewer_id Username of the approving manager.
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#' @param comments Optional comments recorded on each approval.
#'
#' @return A list with `approved` (count) and `errors`.
#'
#' @export
approve_user_proposals <- function(ids, reviewer_id, db_path = NULL,
                                    comments = NULL) {
  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  approved <- 0L
  errors   <- list()
  now      <- as.character(Sys.time())

  for (pid in ids) {
    tryCatch({
      proposal <- DBI::dbGetQuery(
        con,
        "SELECT * FROM user_proposals WHERE proposal_id = ?",
        params = list(pid)
      )

      if (nrow(proposal) == 0) {
        errors[[pid]] <- 'Proposal not found'; next
      }
      if (proposal$status[1] != 'PENDING') {
        errors[[pid]] <- paste0('Status is ', proposal$status[1],
                                ', not PENDING'); next
      }

      p <- proposal[1, ]

      if (p$change_type == 'NEW') {
        init_pw   <- paste0(
          sample(c(letters, LETTERS, 0:9), 12, replace = TRUE),
          collapse = ''
        )
        pw_hash <- digest::digest(
          paste0(init_pw, 'gsheets_setup_salt_change_in_production'),
          algo = 'sha256'
        )
        db_insert_user(
          conn      = con,
          username  = p$username,
          password_hash = pw_hash,
          full_name = p$proposed_full_name %||% p$username,
          email     = p$proposed_email     %||% '',
          role      = p$proposed_role      %||% 'Coordinator',
          site_id   = p$proposed_site_id   %||% '',
          active    = as.logical(p$proposed_active %||% TRUE),
          created_by = reviewer_id
        )
      } else {
        DBI::dbExecute(con, "
          UPDATE edc_users
             SET role       = COALESCE(?, role),
                 email      = COALESCE(?, email),
                 full_name  = COALESCE(?, full_name),
                 site_id    = COALESCE(?, site_id),
                 active     = COALESCE(?, active)
           WHERE username = ?",
          params = list(
            p$proposed_role,
            p$proposed_email,
            p$proposed_full_name,
            p$proposed_site_id,
            p$proposed_active,
            p$username
          )
        )
      }

      DBI::dbExecute(con, "
        UPDATE user_proposals
           SET status = 'APPROVED', reviewed_by = ?,
               reviewed_at = ?, review_comments = ?
         WHERE proposal_id = ?",
        params = list(reviewer_id, now, comments, pid)
      )

      approved <- approved + 1L
    }, error = function(e) {
      errors[[pid]] <<- e$message
    })
  }

  list(approved = approved, errors = errors)
}

#' Reject Pending User Proposals
#'
#' Marks each proposal in `ids` as `'REJECTED'`. The live `edc_users`
#' table is not modified.
#'
#' @param ids Character vector of `proposal_id` values to reject.
#' @param reviewer_id Username of the rejecting manager.
#' @param comments Required rationale for the rejection.
#' @param db_path Path to the ZZedc SQLite database. `NULL` uses
#'   `get_db_path()`.
#'
#' @return A list with `rejected` (count) and `errors`.
#'
#' @export
reject_user_proposals <- function(ids, reviewer_id, comments,
                                   db_path = NULL) {
  con <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  rejected <- 0L
  errors   <- list()
  now      <- as.character(Sys.time())

  for (pid in ids) {
    tryCatch({
      proposal <- DBI::dbGetQuery(
        con,
        "SELECT proposal_id, status FROM user_proposals
          WHERE proposal_id = ?",
        params = list(pid)
      )

      if (nrow(proposal) == 0) {
        errors[[pid]] <- 'Proposal not found'; next
      }
      if (proposal$status[1] != 'PENDING') {
        errors[[pid]] <- paste0('Status is ', proposal$status[1],
                                ', not PENDING'); next
      }

      DBI::dbExecute(con, "
        UPDATE user_proposals
           SET status = 'REJECTED', reviewed_by = ?,
               reviewed_at = ?, review_comments = ?
         WHERE proposal_id = ?",
        params = list(reviewer_id, now, comments, pid)
      )

      rejected <- rejected + 1L
    }, error = function(e) {
      errors[[pid]] <<- e$message
    })
  }

  list(rejected = rejected, errors = errors)
}
