#' Study Reconciliation & Closeout System (Feature #26)
#'
#' Provides study closeout procedures, data reconciliation,
#' database lock management, and closeout checklists.
#'
#' @name study_closeout
#' @docType package
NULL

#' @keywords internal
safe_scalar_co <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize Study Closeout System
#' @return List with success status
#' @export
init_study_closeout <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS study_closeout (
        closeout_id INTEGER PRIMARY KEY AUTOINCREMENT,
        study_id INTEGER NOT NULL,
        closeout_status TEXT DEFAULT 'PENDING',
        closeout_type TEXT DEFAULT 'STANDARD',
        initiated_at TEXT DEFAULT (datetime('now')),
        initiated_by TEXT NOT NULL,
        completed_at TEXT,
        completed_by TEXT,
        database_locked INTEGER DEFAULT 0,
        database_locked_at TEXT,
        database_locked_by TEXT,
        final_subject_count INTEGER,
        final_record_count INTEGER,
        closeout_notes TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS closeout_checklist (
        item_id INTEGER PRIMARY KEY AUTOINCREMENT,
        closeout_id INTEGER NOT NULL,
        item_category TEXT NOT NULL,
        item_description TEXT NOT NULL,
        item_order INTEGER DEFAULT 1,
        is_required INTEGER DEFAULT 1,
        is_completed INTEGER DEFAULT 0,
        completed_at TEXT,
        completed_by TEXT,
        completion_notes TEXT,
        FOREIGN KEY (closeout_id) REFERENCES study_closeout(closeout_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS data_reconciliation (
        reconciliation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        closeout_id INTEGER NOT NULL,
        reconciliation_type TEXT NOT NULL,
        source_system TEXT,
        target_system TEXT,
        records_compared INTEGER DEFAULT 0,
        records_matched INTEGER DEFAULT 0,
        discrepancies_found INTEGER DEFAULT 0,
        discrepancies_resolved INTEGER DEFAULT 0,
        reconciliation_status TEXT DEFAULT 'PENDING',
        performed_at TEXT DEFAULT (datetime('now')),
        performed_by TEXT NOT NULL,
        resolution_notes TEXT,
        FOREIGN KEY (closeout_id) REFERENCES study_closeout(closeout_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS database_lock_log (
        lock_id INTEGER PRIMARY KEY AUTOINCREMENT,
        study_id INTEGER NOT NULL,
        lock_action TEXT NOT NULL,
        lock_scope TEXT DEFAULT 'FULL',
        reason TEXT,
        performed_at TEXT DEFAULT (datetime('now')),
        performed_by TEXT NOT NULL,
        authorized_by TEXT
      )
    ")

    list(success = TRUE, message = "Study closeout system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Closeout Status Values
#' @return Named character vector
#' @export
get_closeout_statuses <- function() {
  c(
    PENDING = "Closeout not yet started",
    IN_PROGRESS = "Closeout in progress",
    DATA_REVIEW = "Data review phase",
    RECONCILIATION = "Data reconciliation phase",
    LOCKED = "Database locked",
    COMPLETED = "Closeout completed",
    ARCHIVED = "Study archived"
  )
}

#' Get Closeout Types
#' @return Named character vector
#' @export
get_closeout_types <- function() {
  c(
    STANDARD = "Standard study closeout",
    EARLY_TERMINATION = "Early termination closeout",
    INTERIM = "Interim database lock",
    REGULATORY = "Regulatory submission lock"
  )
}

#' Get Checklist Categories
#' @return Named character vector
#' @export
get_checklist_categories <- function() {
  c(
    DATA_QUALITY = "Data quality checks",
    QUERY_RESOLUTION = "Query resolution",
    SAE_RECONCILIATION = "SAE reconciliation",
    PROTOCOL_DEVIATIONS = "Protocol deviation review",
    SOURCE_VERIFICATION = "Source data verification",
    SIGNATURES = "Required signatures",
    DOCUMENTATION = "Documentation completion",
    ARCHIVAL = "Archival preparation"
  )
}

#' Initiate Study Closeout
#' @param study_id Study ID
#' @param initiated_by User initiating closeout
#' @param closeout_type Type of closeout
#' @param closeout_notes Optional notes
#' @return List with success status
#' @export
initiate_study_closeout <- function(study_id, initiated_by,
                                     closeout_type = "STANDARD",
                                     closeout_notes = NULL) {
  tryCatch({
    if (missing(study_id)) {
      return(list(success = FALSE, error = "study_id is required"))
    }

    valid_types <- names(get_closeout_types())
    if (!closeout_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid closeout_type:", closeout_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO study_closeout (
        study_id, closeout_status, closeout_type, initiated_by, closeout_notes
      ) VALUES (?, 'IN_PROGRESS', ?, ?, ?)
    ", params = list(study_id, closeout_type, initiated_by,
                     safe_scalar_co(closeout_notes)))

    closeout_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, closeout_id = closeout_id,
         message = "Study closeout initiated")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Checklist Item
#' @param closeout_id Closeout ID
#' @param item_category Category
#' @param item_description Description
#' @param item_order Display order
#' @param is_required Whether required
#' @return List with success status
#' @export
add_checklist_item <- function(closeout_id, item_category, item_description,
                                item_order = 1, is_required = TRUE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO closeout_checklist (
        closeout_id, item_category, item_description, item_order, is_required
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(closeout_id, item_category, item_description,
                     as.integer(item_order), as.integer(is_required)))

    list(success = TRUE, message = "Checklist item added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Complete Checklist Item
#' @param item_id Item ID
#' @param completed_by User completing
#' @param completion_notes Optional notes
#' @return List with success status
#' @export
complete_checklist_item <- function(item_id, completed_by,
                                     completion_notes = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE closeout_checklist
      SET is_completed = 1, completed_at = ?, completed_by = ?,
          completion_notes = ?
      WHERE item_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      completed_by, safe_scalar_co(completion_notes), item_id
    ))

    list(success = TRUE, message = "Checklist item completed")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Load Standard Checklist
#' @param closeout_id Closeout ID
#' @return List with success status
#' @export
load_standard_checklist <- function(closeout_id) {
  tryCatch({
    items <- list(
      list(cat = "DATA_QUALITY", desc = "All edit checks resolved", order = 1),
      list(cat = "DATA_QUALITY", desc = "Missing data reviewed", order = 2),
      list(cat = "DATA_QUALITY", desc = "Range checks complete", order = 3),
      list(cat = "QUERY_RESOLUTION", desc = "All queries closed", order = 4),
      list(cat = "QUERY_RESOLUTION", desc = "Query metrics documented",
           order = 5),
      list(cat = "SAE_RECONCILIATION", desc = "SAE/CIOMS reconciliation",
           order = 6),
      list(cat = "SAE_RECONCILIATION", desc = "Regulatory reports filed",
           order = 7),
      list(cat = "PROTOCOL_DEVIATIONS",
           desc = "Protocol deviations documented", order = 8),
      list(cat = "SOURCE_VERIFICATION", desc = "SDV complete", order = 9),
      list(cat = "SIGNATURES", desc = "PI signature obtained", order = 10),
      list(cat = "SIGNATURES", desc = "Sponsor sign-off", order = 11),
      list(cat = "DOCUMENTATION", desc = "Final TMF review", order = 12),
      list(cat = "ARCHIVAL", desc = "Archive preparation complete", order = 13)
    )

    count <- 0
    for (item in items) {
      result <- add_checklist_item(
        closeout_id = closeout_id,
        item_category = item$cat,
        item_description = item$desc,
        item_order = item$order
      )
      if (result$success) count <- count + 1
    }

    list(success = TRUE, items_loaded = count)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Checklist Status
#' @param closeout_id Closeout ID
#' @return List with checklist
#' @export
get_checklist_status <- function(closeout_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    items <- DBI::dbGetQuery(con, "
      SELECT * FROM closeout_checklist
      WHERE closeout_id = ?
      ORDER BY item_order
    ", params = list(closeout_id))

    total <- nrow(items)
    completed <- sum(items$is_completed, na.rm = TRUE)
    required <- sum(items$is_required, na.rm = TRUE)
    required_completed <- sum(items$is_completed & items$is_required,
                              na.rm = TRUE)

    list(
      success = TRUE,
      items = items,
      total_items = total,
      completed_items = completed,
      required_items = required,
      required_completed = required_completed,
      completion_pct = if (total > 0) round(100 * completed / total, 1) else 0
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Record Data Reconciliation
#' @param closeout_id Closeout ID
#' @param reconciliation_type Type
#' @param performed_by User performing
#' @param source_system Source system
#' @param target_system Target system
#' @param records_compared Number compared
#' @param records_matched Number matched
#' @param discrepancies_found Number of discrepancies
#' @return List with success status
#' @export
record_data_reconciliation <- function(closeout_id, reconciliation_type,
                                        performed_by, source_system = NULL,
                                        target_system = NULL,
                                        records_compared = 0,
                                        records_matched = 0,
                                        discrepancies_found = 0) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    status <- if (discrepancies_found == 0) "COMPLETE" else "PENDING_RESOLUTION"

    DBI::dbExecute(con, "
      INSERT INTO data_reconciliation (
        closeout_id, reconciliation_type, source_system, target_system,
        records_compared, records_matched, discrepancies_found,
        reconciliation_status, performed_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      closeout_id, reconciliation_type,
      safe_scalar_co(source_system), safe_scalar_co(target_system),
      as.integer(records_compared), as.integer(records_matched),
      as.integer(discrepancies_found), status, performed_by
    ))

    reconciliation_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, reconciliation_id = reconciliation_id)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Resolve Reconciliation Discrepancy
#' @param reconciliation_id Reconciliation ID
#' @param resolved_by User resolving
#' @param discrepancies_resolved Number resolved
#' @param resolution_notes Notes
#' @return List with success status
#' @export
resolve_reconciliation_discrepancy <- function(reconciliation_id, resolved_by,
                                                discrepancies_resolved,
                                                resolution_notes = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    current <- DBI::dbGetQuery(con, "
      SELECT discrepancies_found, discrepancies_resolved
      FROM data_reconciliation WHERE reconciliation_id = ?
    ", params = list(reconciliation_id))

    new_resolved <- current$discrepancies_resolved[1] + discrepancies_resolved
    all_resolved <- new_resolved >= current$discrepancies_found[1]
    new_status <- if (all_resolved) "COMPLETE" else "PENDING_RESOLUTION"

    DBI::dbExecute(con, "
      UPDATE data_reconciliation
      SET discrepancies_resolved = ?, reconciliation_status = ?,
          resolution_notes = ?
      WHERE reconciliation_id = ?
    ", params = list(new_resolved, new_status,
                     safe_scalar_co(resolution_notes), reconciliation_id))

    list(success = TRUE, message = "Discrepancy resolved",
         all_resolved = all_resolved)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Reconciliation Status
#' @param closeout_id Closeout ID
#' @return List with reconciliations
#' @export
get_reconciliation_status <- function(closeout_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    reconciliations <- DBI::dbGetQuery(con, "
      SELECT * FROM data_reconciliation
      WHERE closeout_id = ?
      ORDER BY performed_at DESC
    ", params = list(closeout_id))

    list(success = TRUE, reconciliations = reconciliations,
         count = nrow(reconciliations))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Lock Database
#' @param study_id Study ID
#' @param locked_by User locking
#' @param authorized_by Authorizing user
#' @param reason Lock reason
#' @param lock_scope Scope (FULL, PARTIAL)
#' @return List with success status
#' @export
lock_database <- function(study_id, locked_by, authorized_by, reason = NULL,
                           lock_scope = "FULL") {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO database_lock_log (
        study_id, lock_action, lock_scope, reason, performed_by, authorized_by
      ) VALUES (?, 'LOCK', ?, ?, ?, ?)
    ", params = list(study_id, lock_scope, safe_scalar_co(reason),
                     locked_by, authorized_by))

    DBI::dbExecute(con, "
      UPDATE study_closeout
      SET database_locked = 1, database_locked_at = ?,
          database_locked_by = ?, closeout_status = 'LOCKED'
      WHERE study_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      locked_by, study_id
    ))

    list(success = TRUE, message = "Database locked")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Unlock Database
#' @param study_id Study ID
#' @param unlocked_by User unlocking
#' @param authorized_by Authorizing user
#' @param reason Unlock reason
#' @return List with success status
#' @export
unlock_database <- function(study_id, unlocked_by, authorized_by, reason) {
  tryCatch({
    if (missing(reason) || is.null(reason) || reason == "") {
      return(list(success = FALSE, error = "Reason required for unlock"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO database_lock_log (
        study_id, lock_action, reason, performed_by, authorized_by
      ) VALUES (?, 'UNLOCK', ?, ?, ?)
    ", params = list(study_id, reason, unlocked_by, authorized_by))

    DBI::dbExecute(con, "
      UPDATE study_closeout
      SET database_locked = 0, closeout_status = 'IN_PROGRESS'
      WHERE study_id = ?
    ", params = list(study_id))

    list(success = TRUE, message = "Database unlocked")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Lock History
#' @param study_id Study ID
#' @return List with lock history
#' @export
get_lock_history <- function(study_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    history <- DBI::dbGetQuery(con, "
      SELECT * FROM database_lock_log
      WHERE study_id = ?
      ORDER BY performed_at DESC
    ", params = list(study_id))

    list(success = TRUE, history = history, count = nrow(history))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Complete Study Closeout
#' @param closeout_id Closeout ID
#' @param completed_by User completing
#' @param final_subject_count Final subject count
#' @param final_record_count Final record count
#' @return List with success status
#' @export
complete_study_closeout <- function(closeout_id, completed_by,
                                     final_subject_count = NULL,
                                     final_record_count = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    checklist <- get_checklist_status(closeout_id)
    if (checklist$required_completed < checklist$required_items) {
      return(list(success = FALSE,
                  error = "Required checklist items not complete"))
    }

    DBI::dbExecute(con, "
      UPDATE study_closeout
      SET closeout_status = 'COMPLETED', completed_at = ?, completed_by = ?,
          final_subject_count = ?, final_record_count = ?
      WHERE closeout_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      completed_by,
      if (is.null(final_subject_count)) NA_integer_
        else as.integer(final_subject_count),
      if (is.null(final_record_count)) NA_integer_
        else as.integer(final_record_count),
      closeout_id
    ))

    list(success = TRUE, message = "Study closeout completed")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Closeout Status
#' @param closeout_id Closeout ID
#' @return List with closeout details
#' @export
get_closeout_status <- function(closeout_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    closeout <- DBI::dbGetQuery(con, "
      SELECT * FROM study_closeout WHERE closeout_id = ?
    ", params = list(closeout_id))

    if (nrow(closeout) == 0) {
      return(list(success = FALSE, error = "Closeout not found"))
    }

    list(success = TRUE, closeout = as.list(closeout))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Closeout Statistics
#' @return List with statistics
#' @export
get_closeout_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_closeouts,
        SUM(CASE WHEN closeout_status = 'COMPLETED' THEN 1 ELSE 0 END)
          as completed,
        SUM(CASE WHEN closeout_status = 'IN_PROGRESS' THEN 1 ELSE 0 END)
          as in_progress,
        SUM(CASE WHEN database_locked = 1 THEN 1 ELSE 0 END) as locked
      FROM study_closeout
    ")

    by_type <- DBI::dbGetQuery(con, "
      SELECT closeout_type, COUNT(*) as count
      FROM study_closeout
      GROUP BY closeout_type
    ")

    list(success = TRUE, statistics = as.list(stats), by_type = by_type)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
