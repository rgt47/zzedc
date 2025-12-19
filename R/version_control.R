#' Enhanced Version Control System
#'
#' Data record versioning for FDA 21 CFR Part 11 compliance.
#' Tracks every change to every record with the ability to view previous
#' versions, compare changes, and maintain immutable version history.

# =============================================================================
# Database Schema Setup
# =============================================================================

#' Initialize Version Control System
#'
#' Creates database tables for record versioning.
#'
#' @param db_path Character: Database path (optional)
#'
#' @return List with initialization results
#'
#' @export
init_version_control <- function(db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS record_versions (
        version_id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        version_number INTEGER NOT NULL,
        data_snapshot TEXT NOT NULL,
        change_type TEXT NOT NULL CHECK(change_type IN
          ('CREATE', 'UPDATE', 'DELETE', 'RESTORE')),
        change_reason TEXT,
        changed_by TEXT NOT NULL,
        changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        version_hash TEXT NOT NULL,
        previous_version_hash TEXT,
        is_current BOOLEAN DEFAULT 0,
        metadata TEXT,
        UNIQUE(table_name, record_id, version_number)
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS version_metadata (
        metadata_id INTEGER PRIMARY KEY AUTOINCREMENT,
        version_id INTEGER NOT NULL REFERENCES record_versions(version_id),
        field_name TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS version_locks (
        lock_id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        locked_by TEXT NOT NULL,
        locked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        lock_reason TEXT,
        expires_at TIMESTAMP,
        UNIQUE(table_name, record_id)
      )
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_versions_table_record
      ON record_versions(table_name, record_id)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_versions_current
      ON record_versions(table_name, record_id, is_current)
    ")

    DBI::dbExecute(conn, "
      CREATE INDEX IF NOT EXISTS idx_versions_changed_at
      ON record_versions(changed_at)
    ")

    list(
      success = TRUE,
      tables_created = 3,
      message = "Version control system initialized successfully"
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    )
  })
}


# =============================================================================
# Version Creation
# =============================================================================

#' Create Record Version
#'
#' Creates a new version of a record, storing the complete data snapshot.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param data List or data.frame: Current record data
#' @param change_type Character: Type of change (CREATE, UPDATE, DELETE, RESTORE)
#' @param change_reason Character: Reason for the change
#' @param changed_by Character: User ID who made the change
#' @param field_changes List: Field-level changes (old_value, new_value pairs)
#' @param db_path Character: Database path (optional)
#'
#' @return List with version creation results
#'
#' @examples
#' \dontrun{
#'   create_record_version(
#'     table_name = "subjects",
#'     record_id = "S001",
#'     data = list(name = "John Doe", age = 45),
#'     change_type = "UPDATE",
#'     change_reason = "Corrected age",
#'     changed_by = "admin",
#'     field_changes = list(
#'       age = list(old_value = "44", new_value = "45")
#'     )
#'   )
#' }
#'
#' @export
create_record_version <- function(table_name, record_id, data,
                                   change_type = "UPDATE",
                                   change_reason = NULL, changed_by,
                                   field_changes = NULL, db_path = NULL) {
  if (!change_type %in% c("CREATE", "UPDATE", "DELETE", "RESTORE")) {
    stop("change_type must be one of: CREATE, UPDATE, DELETE, RESTORE")
  }

  safe_scalar <- function(x, default = NA_character_) {
    if (is.null(x) || length(x) == 0) {
      default
    } else if (length(x) > 1) {
      paste(x, collapse = "; ")
    } else {
      as.character(x)
    }
  }

  table_name <- safe_scalar(table_name)
  record_id <- safe_scalar(record_id)
  change_type <- safe_scalar(change_type)
  change_reason <- safe_scalar(change_reason)
  changed_by <- safe_scalar(changed_by)

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    current_version <- DBI::dbGetQuery(conn, "
      SELECT MAX(version_number) as max_version, version_hash
      FROM record_versions
      WHERE table_name = ? AND record_id = ?
    ", list(table_name, record_id))

    if (is.na(current_version$max_version[1])) {
      new_version_number <- 1
      previous_hash <- "GENESIS"
    } else {
      new_version_number <- current_version$max_version[1] + 1
      previous_hash <- current_version$version_hash[1]
    }

    data_json <- jsonlite::toJSON(data, auto_unbox = TRUE)

    hash_content <- paste(
      table_name, record_id, new_version_number, data_json,
      change_type, changed_by, Sys.time(), previous_hash,
      sep = "|"
    )
    version_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(conn, "
      UPDATE record_versions
      SET is_current = 0
      WHERE table_name = ? AND record_id = ?
    ", list(table_name, record_id))

    DBI::dbExecute(conn, "
      INSERT INTO record_versions
      (table_name, record_id, version_number, data_snapshot, change_type,
       change_reason, changed_by, version_hash, previous_version_hash, is_current)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
    ", list(
      table_name, record_id, new_version_number, as.character(data_json),
      change_type, change_reason, changed_by, version_hash, previous_hash
    ))

    version_id <- DBI::dbGetQuery(conn,
      "SELECT last_insert_rowid() as id")[1, 1]

    if (!is.null(field_changes) && length(field_changes) > 0) {
      for (field_name in names(field_changes)) {
        change <- field_changes[[field_name]]
        DBI::dbExecute(conn, "
          INSERT INTO version_metadata
          (version_id, field_name, old_value, new_value)
          VALUES (?, ?, ?, ?)
        ", list(
          version_id, field_name,
          as.character(change$old_value),
          as.character(change$new_value)
        ))
      }
    }

    audit_event_type <- switch(change_type,
      "CREATE" = "INSERT",
      "UPDATE" = "UPDATE",
      "DELETE" = "DELETE",
      "RESTORE" = "UPDATE",
      "UPDATE"
    )

    log_audit_event(
      event_type = audit_event_type,
      table_name = table_name,
      record_id = record_id,
      operation = paste("Version", new_version_number, "created:", change_type),
      details = jsonlite::toJSON(list(
        version_number = new_version_number,
        change_reason = change_reason,
        version_hash = version_hash
      ), auto_unbox = TRUE),
      user_id = changed_by,
      db_path = db_path
    )

    list(
      success = TRUE,
      version_id = version_id,
      version_number = new_version_number,
      version_hash = version_hash,
      message = paste("Version", new_version_number, "created successfully")
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Version creation failed:", e$message)
    )
  })
}


# =============================================================================
# Version Retrieval
# =============================================================================

#' Get Record Version History
#'
#' Retrieves the complete version history for a record.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param include_data Logical: Include full data snapshots? (default: FALSE)
#' @param db_path Character: Database path (optional)
#'
#' @return Data frame with version history
#'
#' @export
get_version_history <- function(table_name, record_id,
                                 include_data = FALSE, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (include_data) {
      query <- "
        SELECT version_id, version_number, data_snapshot, change_type,
               change_reason, changed_by, changed_at, version_hash,
               previous_version_hash, is_current
        FROM record_versions
        WHERE table_name = ? AND record_id = ?
        ORDER BY version_number DESC
      "
    } else {
      query <- "
        SELECT version_id, version_number, change_type, change_reason,
               changed_by, changed_at, version_hash, is_current
        FROM record_versions
        WHERE table_name = ? AND record_id = ?
        ORDER BY version_number DESC
      "
    }

    DBI::dbGetQuery(conn, query, list(table_name, record_id))

  }, error = function(e) {
    warning("Failed to get version history: ", e$message)
    data.frame()
  })
}


#' Get Specific Version
#'
#' Retrieves a specific version of a record.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param version_number Integer: Version number to retrieve
#' @param db_path Character: Database path (optional)
#'
#' @return List with version data
#'
#' @export
get_record_version <- function(table_name, record_id, version_number,
                                db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    version <- DBI::dbGetQuery(conn, "
      SELECT * FROM record_versions
      WHERE table_name = ? AND record_id = ? AND version_number = ?
    ", list(table_name, record_id, version_number))

    if (nrow(version) == 0) {
      return(list(
        found = FALSE,
        message = paste("Version", version_number, "not found")
      ))
    }

    field_changes <- DBI::dbGetQuery(conn, "
      SELECT field_name, old_value, new_value
      FROM version_metadata
      WHERE version_id = ?
    ", list(version$version_id[1]))

    data <- jsonlite::fromJSON(version$data_snapshot[1])

    list(
      found = TRUE,
      version_id = version$version_id[1],
      version_number = version$version_number[1],
      data = data,
      change_type = version$change_type[1],
      change_reason = version$change_reason[1],
      changed_by = version$changed_by[1],
      changed_at = version$changed_at[1],
      version_hash = version$version_hash[1],
      is_current = as.logical(version$is_current[1]),
      field_changes = if (nrow(field_changes) > 0) field_changes else NULL
    )

  }, error = function(e) {
    list(
      found = FALSE,
      error = paste("Failed to get version:", e$message)
    )
  })
}


#' Get Current Version
#'
#' Retrieves the current (latest) version of a record.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param db_path Character: Database path (optional)
#'
#' @return List with current version data
#'
#' @export
get_current_version <- function(table_name, record_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    version <- DBI::dbGetQuery(conn, "
      SELECT * FROM record_versions
      WHERE table_name = ? AND record_id = ? AND is_current = 1
    ", list(table_name, record_id))

    if (nrow(version) == 0) {
      return(list(found = FALSE, message = "No current version found"))
    }

    data <- jsonlite::fromJSON(version$data_snapshot[1])

    list(
      found = TRUE,
      version_id = version$version_id[1],
      version_number = version$version_number[1],
      data = data,
      changed_by = version$changed_by[1],
      changed_at = version$changed_at[1],
      version_hash = version$version_hash[1]
    )

  }, error = function(e) {
    list(found = FALSE, error = e$message)
  })
}


# =============================================================================
# Version Comparison
# =============================================================================

#' Compare Two Versions
#'
#' Compares two versions of a record and returns the differences.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param version_a Integer: First version number
#' @param version_b Integer: Second version number
#' @param db_path Character: Database path (optional)
#'
#' @return List with comparison results
#'
#' @export
compare_versions <- function(table_name, record_id,
                              version_a, version_b, db_path = NULL) {
  version_a_data <- get_record_version(table_name, record_id, version_a,
                                        db_path = db_path)
  version_b_data <- get_record_version(table_name, record_id, version_b,
                                        db_path = db_path)

  if (!version_a_data$found) {
    return(list(
      success = FALSE,
      error = paste("Version", version_a, "not found")
    ))
  }

  if (!version_b_data$found) {
    return(list(
      success = FALSE,
      error = paste("Version", version_b, "not found")
    ))
  }

  data_a <- version_a_data$data
  data_b <- version_b_data$data

  if (is.data.frame(data_a)) data_a <- as.list(data_a)
  if (is.data.frame(data_b)) data_b <- as.list(data_b)

  all_fields <- unique(c(names(data_a), names(data_b)))

  differences <- list()
  for (field in all_fields) {
    val_a <- if (field %in% names(data_a)) as.character(data_a[[field]]) else NA
    val_b <- if (field %in% names(data_b)) as.character(data_b[[field]]) else NA

    if (!identical(val_a, val_b)) {
      differences[[field]] <- list(
        field = field,
        version_a_value = val_a,
        version_b_value = val_b,
        change_type = if (is.na(val_a)) {
          "ADDED"
        } else if (is.na(val_b)) {
          "REMOVED"
        } else {
          "MODIFIED"
        }
      )
    }
  }

  list(
    success = TRUE,
    table_name = table_name,
    record_id = record_id,
    version_a = list(
      number = version_a,
      changed_by = version_a_data$changed_by,
      changed_at = version_a_data$changed_at
    ),
    version_b = list(
      number = version_b,
      changed_by = version_b_data$changed_by,
      changed_at = version_b_data$changed_at
    ),
    differences = differences,
    fields_changed = length(differences),
    identical = length(differences) == 0
  )
}


#' Get Version Diff Summary
#'
#' Returns a human-readable summary of changes between versions.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param version_a Integer: First version number
#' @param version_b Integer: Second version number
#' @param db_path Character: Database path (optional)
#'
#' @return Character vector with diff summary
#'
#' @export
get_version_diff_summary <- function(table_name, record_id,
                                      version_a, version_b, db_path = NULL) {
  comparison <- compare_versions(table_name, record_id, version_a, version_b,
                                  db_path = db_path)

  if (!comparison$success) {
    return(comparison$error)
  }

  if (comparison$identical) {
    return("No differences between versions")
  }

  summary_lines <- c(
    paste("Comparing version", version_a, "to version", version_b),
    paste("Record:", table_name, "/", record_id),
    paste("Fields changed:", comparison$fields_changed),
    ""
  )

  for (diff in comparison$differences) {
    line <- switch(diff$change_type,
      "ADDED" = paste("+", diff$field, ":", diff$version_b_value),
      "REMOVED" = paste("-", diff$field, ":", diff$version_a_value),
      "MODIFIED" = paste("~", diff$field, ":",
                         diff$version_a_value, "->", diff$version_b_value)
    )
    summary_lines <- c(summary_lines, line)
  }

  summary_lines
}


# =============================================================================
# Version Restoration
# =============================================================================

#' Restore Record Version
#'
#' Restores a record to a previous version, creating a new version entry.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param version_number Integer: Version number to restore
#' @param restore_reason Character: Reason for restoration
#' @param restored_by Character: User performing the restore
#' @param db_path Character: Database path (optional)
#'
#' @return List with restoration results
#'
#' @export
restore_record_version <- function(table_name, record_id, version_number,
                                    restore_reason, restored_by,
                                    db_path = NULL) {
  old_version <- get_record_version(table_name, record_id, version_number,
                                     db_path = db_path)

  if (!old_version$found) {
    return(list(
      success = FALSE,
      error = paste("Version", version_number, "not found")
    ))
  }

  current <- get_current_version(table_name, record_id, db_path = db_path)
  field_changes <- NULL

  if (current$found) {
    current_data <- current$data
    old_data <- old_version$data

    if (is.data.frame(current_data)) current_data <- as.list(current_data)
    if (is.data.frame(old_data)) old_data <- as.list(old_data)

    all_fields <- unique(c(names(current_data), names(old_data)))
    field_changes <- list()

    for (field in all_fields) {
      old_val <- if (field %in% names(current_data)) current_data[[field]] else NA
      new_val <- if (field %in% names(old_data)) old_data[[field]] else NA

      if (!identical(as.character(old_val), as.character(new_val))) {
        field_changes[[field]] <- list(
          old_value = old_val,
          new_value = new_val
        )
      }
    }
  }

  result <- create_record_version(
    table_name = table_name,
    record_id = record_id,
    data = old_version$data,
    change_type = "RESTORE",
    change_reason = paste("Restored from version", version_number, "-",
                          restore_reason),
    changed_by = restored_by,
    field_changes = field_changes,
    db_path = db_path
  )

  if (result$success) {
    result$restored_from_version <- version_number
    result$message <- paste("Record restored from version", version_number,
                            "to new version", result$version_number)
  }

  result
}


# =============================================================================
# Version Integrity
# =============================================================================

#' Verify Version Chain Integrity
#'
#' Verifies the hash chain integrity of a record's version history.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param db_path Character: Database path (optional)
#'
#' @return List with verification results
#'
#' @export
verify_version_integrity <- function(table_name, record_id, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    versions <- DBI::dbGetQuery(conn, "
      SELECT version_number, version_hash, previous_version_hash
      FROM record_versions
      WHERE table_name = ? AND record_id = ?
      ORDER BY version_number ASC
    ", list(table_name, record_id))

    if (nrow(versions) == 0) {
      return(list(
        valid = TRUE,
        versions_checked = 0,
        message = "No versions found"
      ))
    }

    errors <- 0
    error_details <- list()

    for (i in seq_len(nrow(versions))) {
      if (i == 1) {
        if (versions$previous_version_hash[i] != "GENESIS") {
          errors <- errors + 1
          error_details <- c(error_details, list(
            paste("Version 1 should have GENESIS as previous hash")
          ))
        }
      } else {
        expected_prev <- versions$version_hash[i - 1]
        actual_prev <- versions$previous_version_hash[i]

        if (expected_prev != actual_prev) {
          errors <- errors + 1
          error_details <- c(error_details, list(
            paste("Version", versions$version_number[i],
                  "has broken chain link")
          ))
        }
      }
    }

    list(
      valid = errors == 0,
      versions_checked = nrow(versions),
      errors_found = errors,
      error_details = error_details,
      message = if (errors == 0) {
        paste("Version chain integrity verified:", nrow(versions), "versions")
      } else {
        paste("INTEGRITY FAILED:", errors, "chain errors found")
      }
    )

  }, error = function(e) {
    list(
      valid = FALSE,
      error = paste("Verification failed:", e$message)
    )
  })
}


# =============================================================================
# Version Statistics
# =============================================================================

#' Get Version Statistics
#'
#' Returns statistics about version history for a table or record.
#'
#' @param table_name Character: Name of the table (optional)
#' @param record_id Character: Record identifier (optional)
#' @param db_path Character: Database path (optional)
#'
#' @return List with version statistics
#'
#' @export
get_version_statistics <- function(table_name = NULL, record_id = NULL,
                                    db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    if (!is.null(table_name) && !is.null(record_id)) {
      stats <- DBI::dbGetQuery(conn, "
        SELECT
          COUNT(*) as total_versions,
          MIN(changed_at) as first_version_at,
          MAX(changed_at) as last_version_at,
          COUNT(DISTINCT changed_by) as unique_editors
        FROM record_versions
        WHERE table_name = ? AND record_id = ?
      ", list(table_name, record_id))

      by_type <- DBI::dbGetQuery(conn, "
        SELECT change_type, COUNT(*) as count
        FROM record_versions
        WHERE table_name = ? AND record_id = ?
        GROUP BY change_type
      ", list(table_name, record_id))

    } else if (!is.null(table_name)) {
      stats <- DBI::dbGetQuery(conn, "
        SELECT
          COUNT(DISTINCT record_id) as total_records,
          COUNT(*) as total_versions,
          AVG(version_count) as avg_versions_per_record
        FROM (
          SELECT record_id, COUNT(*) as version_count
          FROM record_versions
          WHERE table_name = ?
          GROUP BY record_id
        )
      ", list(table_name))

      by_type <- DBI::dbGetQuery(conn, "
        SELECT change_type, COUNT(*) as count
        FROM record_versions
        WHERE table_name = ?
        GROUP BY change_type
      ", list(table_name))

    } else {
      stats <- DBI::dbGetQuery(conn, "
        SELECT
          COUNT(DISTINCT table_name) as tables_tracked,
          COUNT(DISTINCT table_name || '/' || record_id) as total_records,
          COUNT(*) as total_versions
        FROM record_versions
      ")

      by_type <- DBI::dbGetQuery(conn, "
        SELECT change_type, COUNT(*) as count
        FROM record_versions
        GROUP BY change_type
      ")
    }

    list(
      statistics = as.list(stats),
      by_change_type = by_type,
      generated_at = as.character(Sys.time())
    )

  }, error = function(e) {
    list(error = e$message)
  })
}


# =============================================================================
# Record Locking
# =============================================================================

#' Lock Record for Editing
#'
#' Creates an exclusive lock on a record to prevent concurrent edits.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param locked_by Character: User ID acquiring the lock
#' @param lock_reason Character: Reason for locking
#' @param duration_minutes Integer: Lock duration (default: 30)
#' @param db_path Character: Database path (optional)
#'
#' @return List with lock results
#'
#' @export
lock_record <- function(table_name, record_id, locked_by,
                         lock_reason = NULL, duration_minutes = 30,
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

  table_name <- safe_scalar(table_name)
  record_id <- safe_scalar(record_id)
  locked_by <- safe_scalar(locked_by)
  lock_reason <- safe_scalar(lock_reason)

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    current_time <- as.character(Sys.time())
    DBI::dbExecute(conn, "
      DELETE FROM version_locks
      WHERE expires_at < ?
    ", list(current_time))

    existing <- DBI::dbGetQuery(conn, "
      SELECT * FROM version_locks
      WHERE table_name = ? AND record_id = ?
    ", list(table_name, record_id))

    if (nrow(existing) > 0) {
      if (existing$locked_by[1] == locked_by) {
        new_expires <- as.character(Sys.time() + (duration_minutes * 60))
        DBI::dbExecute(conn, "
          UPDATE version_locks
          SET expires_at = ?,
              lock_reason = ?
          WHERE table_name = ? AND record_id = ?
        ", list(new_expires, lock_reason, table_name, record_id))

        return(list(
          success = TRUE,
          action = "EXTENDED",
          message = "Lock extended"
        ))
      } else {
        return(list(
          success = FALSE,
          locked_by = existing$locked_by[1],
          locked_at = existing$locked_at[1],
          expires_at = existing$expires_at[1],
          message = paste("Record locked by", existing$locked_by[1])
        ))
      }
    }

    expires_at <- as.character(Sys.time() + (duration_minutes * 60))

    DBI::dbExecute(conn, "
      INSERT INTO version_locks
      (table_name, record_id, locked_by, lock_reason, expires_at)
      VALUES (?, ?, ?, ?, ?)
    ", list(table_name, record_id, locked_by, lock_reason, expires_at))

    list(
      success = TRUE,
      action = "ACQUIRED",
      expires_at = expires_at,
      message = "Lock acquired"
    )

  }, error = function(e) {
    list(
      success = FALSE,
      error = paste("Lock failed:", e$message)
    )
  })
}


#' Unlock Record
#'
#' Releases a lock on a record.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param unlocked_by Character: User ID releasing the lock
#' @param force Logical: Force unlock even if locked by another user
#' @param db_path Character: Database path (optional)
#'
#' @return List with unlock results
#'
#' @export
unlock_record <- function(table_name, record_id, unlocked_by,
                           force = FALSE, db_path = NULL) {
  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    existing <- DBI::dbGetQuery(conn, "
      SELECT * FROM version_locks
      WHERE table_name = ? AND record_id = ?
    ", list(table_name, record_id))

    if (nrow(existing) == 0) {
      return(list(success = TRUE, message = "No lock to release"))
    }

    if (!force && existing$locked_by[1] != unlocked_by) {
      return(list(
        success = FALSE,
        message = paste("Record locked by", existing$locked_by[1],
                        "- use force=TRUE to override")
      ))
    }

    DBI::dbExecute(conn, "
      DELETE FROM version_locks
      WHERE table_name = ? AND record_id = ?
    ", list(table_name, record_id))

    list(success = TRUE, message = "Lock released")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}


#' Check Record Lock Status
#'
#' Checks if a record is currently locked.
#'
#' @param table_name Character: Name of the table
#' @param record_id Character: Record identifier
#' @param db_path Character: Database path (optional)
#'
#' @return List with lock status
#'
#' @export
check_record_lock <- function(table_name, record_id, db_path = NULL) {
  safe_scalar <- function(x, default = NA_character_) {
    if (is.null(x) || length(x) == 0) {
      default
    } else {
      as.character(x)
    }
  }

  table_name <- safe_scalar(table_name)
  record_id <- safe_scalar(record_id)

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    current_time <- as.character(Sys.time())
    DBI::dbExecute(conn, "
      DELETE FROM version_locks
      WHERE expires_at < ?
    ", list(current_time))

    lock <- DBI::dbGetQuery(conn, "
      SELECT * FROM version_locks
      WHERE table_name = ? AND record_id = ?
    ", list(table_name, record_id))

    if (nrow(lock) == 0) {
      list(locked = FALSE)
    } else {
      list(
        locked = TRUE,
        locked_by = lock$locked_by[1],
        locked_at = lock$locked_at[1],
        expires_at = lock$expires_at[1],
        lock_reason = lock$lock_reason[1]
      )
    }

  }, error = function(e) {
    list(locked = FALSE, error = e$message)
  })
}
