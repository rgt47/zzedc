#' CRF Version Control & Change Log System
#'
#' Manages versioning and change tracking for Case Report Forms.
#' Provides detailed change logs, version comparison, and rollback
#' capabilities for regulatory compliance.
#'
#' @name crf_version
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' @keywords internal
safe_scalar_crfv <- function(x, default = NA_character_) {

if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' @keywords internal
safe_int_crfv <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

#' @keywords internal
generate_version_id <- function(prefix = "VER") {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(c(0:9, LETTERS), 4, replace = TRUE), collapse = "")
  paste0(prefix, "-", timestamp, "-", random)
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize CRF Version Control System
#'
#' Creates database tables for CRF version control and change tracking.
#'
#' @return List with success status and message
#' @export
init_crf_version <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_definitions (
        crf_id INTEGER PRIMARY KEY AUTOINCREMENT,
        crf_code TEXT UNIQUE NOT NULL,
        crf_name TEXT NOT NULL,
        crf_description TEXT,
        crf_category TEXT,
        current_version TEXT DEFAULT '1.0.0',
        current_status TEXT DEFAULT 'DRAFT',
        is_locked INTEGER DEFAULT 0,
        locked_at TEXT,
        locked_by TEXT,
        lock_reason TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_versions (
        version_id INTEGER PRIMARY KEY AUTOINCREMENT,
        crf_id INTEGER NOT NULL,
        version_number TEXT NOT NULL,
        version_type TEXT NOT NULL,
        version_status TEXT DEFAULT 'DRAFT',
        parent_version_id INTEGER,
        effective_date TEXT,
        expiry_date TEXT,
        change_summary TEXT NOT NULL,
        change_rationale TEXT,
        regulatory_impact TEXT,
        backwards_compatible INTEGER DEFAULT 1,
        requires_retraining INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        reviewed_at TEXT,
        reviewed_by TEXT,
        approved_at TEXT,
        approved_by TEXT,
        version_hash TEXT NOT NULL,
        previous_hash TEXT,
        FOREIGN KEY (crf_id) REFERENCES crf_definitions(crf_id),
        FOREIGN KEY (parent_version_id) REFERENCES crf_versions(version_id),
        UNIQUE(crf_id, version_number)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_change_log (
        change_id INTEGER PRIMARY KEY AUTOINCREMENT,
        version_id INTEGER NOT NULL,
        change_type TEXT NOT NULL,
        change_category TEXT NOT NULL,
        field_code TEXT,
        field_name TEXT,
        attribute_changed TEXT,
        old_value TEXT,
        new_value TEXT,
        change_description TEXT NOT NULL,
        change_justification TEXT,
        impact_assessment TEXT,
        affected_data INTEGER DEFAULT 0,
        data_migration_required INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        change_hash TEXT NOT NULL,
        FOREIGN KEY (version_id) REFERENCES crf_versions(version_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_version_snapshots (
        snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
        version_id INTEGER NOT NULL,
        snapshot_type TEXT NOT NULL,
        snapshot_data TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        snapshot_hash TEXT NOT NULL,
        FOREIGN KEY (version_id) REFERENCES crf_versions(version_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS crf_version_comparisons (
        comparison_id INTEGER PRIMARY KEY AUTOINCREMENT,
        version_id_old INTEGER NOT NULL,
        version_id_new INTEGER NOT NULL,
        comparison_date TEXT DEFAULT (datetime('now')),
        compared_by TEXT NOT NULL,
        fields_added INTEGER DEFAULT 0,
        fields_removed INTEGER DEFAULT 0,
        fields_modified INTEGER DEFAULT 0,
        validation_changes INTEGER DEFAULT 0,
        comparison_summary TEXT,
        comparison_hash TEXT NOT NULL,
        FOREIGN KEY (version_id_old) REFERENCES crf_versions(version_id),
        FOREIGN KEY (version_id_new) REFERENCES crf_versions(version_id)
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_crf_versions_crf
                         ON crf_versions(crf_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_crf_changelog_version
                         ON crf_change_log(version_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_crf_snapshots_version
                         ON crf_version_snapshots(version_id)")

    list(success = TRUE, message = "CRF version control system initialized")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Version Types
#' @return Named character vector of version types
#' @export
get_crf_version_types <- function() {
  c(
    MAJOR = "Major version - significant structural changes",
    MINOR = "Minor version - field additions or modifications",
    PATCH = "Patch version - corrections and clarifications",
    HOTFIX = "Hotfix - urgent corrections"
  )
}

#' Get Version Statuses
#' @return Named character vector of version statuses
#' @export
get_crf_version_statuses <- function() {
  c(
    DRAFT = "In development",
    REVIEW = "Under review",
    APPROVED = "Approved for use",
    ACTIVE = "Currently in production",
    SUPERSEDED = "Replaced by newer version",
    RETIRED = "No longer in use"
  )
}

#' Get Change Types
#' @return Named character vector of change types
#' @export
get_crf_change_types <- function() {
  c(
    ADD = "Field or section added",
    REMOVE = "Field or section removed",
    MODIFY = "Field or section modified",
    RENAME = "Field or section renamed",
    REORDER = "Display order changed",
    VALIDATION = "Validation rule changed",
    LOGIC = "Skip logic or branching changed",
    FORMAT = "Format or display changed",
    CORRECTION = "Error correction"
  )
}
#' Get Change Categories
#' @return Named character vector of change categories
#' @export
get_crf_change_categories <- function() {
  c(
    FIELD = "Individual field change",
    SECTION = "Section-level change",
    FORM = "Form-level change",
    VALIDATION = "Validation rule change",
    LAYOUT = "Layout or formatting change",
    METADATA = "Metadata or documentation change"
  )
}

# ============================================================================
# CRF DEFINITION MANAGEMENT
# ============================================================================

#' Create CRF Definition
#'
#' Creates a new CRF definition for version control.
#'
#' @param crf_code Unique CRF code
#' @param crf_name CRF name
#' @param created_by User creating the CRF
#' @param crf_description Optional description
#' @param crf_category Optional category
#'
#' @return List with success status and CRF details
#' @export
create_crf_definition <- function(crf_code,
                                   crf_name,
                                   created_by,
                                   crf_description = NULL,
                                   crf_category = NULL) {
  tryCatch({
    if (missing(crf_code) || is.null(crf_code) || crf_code == "") {
      return(list(success = FALSE, error = "crf_code is required"))
    }
    if (missing(crf_name) || is.null(crf_name) || crf_name == "") {
      return(list(success = FALSE, error = "crf_name is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    existing <- DBI::dbGetQuery(con, "
      SELECT crf_id FROM crf_definitions WHERE crf_code = ?
    ", params = list(crf_code))

    if (nrow(existing) > 0) {
      return(list(success = FALSE, error = "crf_code already exists"))
    }

    DBI::dbExecute(con, "
      INSERT INTO crf_definitions (
        crf_code, crf_name, crf_description, crf_category, created_by
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(
      crf_code,
      crf_name,
      safe_scalar_crfv(crf_description),
      safe_scalar_crfv(crf_category),
      created_by
    ))

    crf_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      crf_id = crf_id,
      crf_code = crf_code,
      message = "CRF definition created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CRF Definitions
#'
#' Retrieves CRF definitions.
#'
#' @param crf_category Optional filter by category
#' @param include_locked Include locked CRFs
#'
#' @return List with success status and CRF definitions
#' @export
get_crf_definitions <- function(crf_category = NULL, include_locked = TRUE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM crf_definitions WHERE 1=1"
    params <- list()

    if (!is.null(crf_category)) {
      query <- paste(query, "AND crf_category = ?")
      params <- append(params, list(crf_category))
    }

    if (!include_locked) {
      query <- paste(query, "AND is_locked = 0")
    }

    query <- paste(query, "ORDER BY crf_name")

    if (length(params) > 0) {
      crfs <- DBI::dbGetQuery(con, query, params = params)
    } else {
      crfs <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, crfs = crfs, count = nrow(crfs))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Lock CRF Definition
#'
#' Locks a CRF to prevent further modifications.
#'
#' @param crf_id CRF ID
#' @param locked_by User locking the CRF
#' @param lock_reason Reason for locking
#'
#' @return List with success status
#' @export
lock_crf_definition <- function(crf_id, locked_by, lock_reason) {
  tryCatch({
    if (missing(lock_reason) || is.null(lock_reason) || nchar(lock_reason) < 10) {
      return(list(success = FALSE,
                  error = "lock_reason must be at least 10 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE crf_definitions
      SET is_locked = 1, locked_at = ?, locked_by = ?, lock_reason = ?,
          updated_at = ?, updated_by = ?
      WHERE crf_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      locked_by,
      lock_reason,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      locked_by,
      crf_id
    ))

    list(success = TRUE, message = "CRF locked successfully")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Unlock CRF Definition
#'
#' Unlocks a previously locked CRF.
#'
#' @param crf_id CRF ID
#' @param unlocked_by User unlocking the CRF
#' @param unlock_reason Reason for unlocking
#'
#' @return List with success status
#' @export
unlock_crf_definition <- function(crf_id, unlocked_by, unlock_reason) {
  tryCatch({
    if (missing(unlock_reason) || is.null(unlock_reason) ||
        nchar(unlock_reason) < 10) {
      return(list(success = FALSE,
                  error = "unlock_reason must be at least 10 characters"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE crf_definitions
      SET is_locked = 0, locked_at = NULL, locked_by = NULL,
          lock_reason = NULL, updated_at = ?, updated_by = ?
      WHERE crf_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      unlocked_by,
      crf_id
    ))

    list(success = TRUE, message = "CRF unlocked successfully")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# VERSION MANAGEMENT
# ============================================================================

#' Create CRF Version
#'
#' Creates a new version of a CRF.
#'
#' @param crf_id CRF ID
#' @param version_number Version number (e.g., "1.1.0")
#' @param version_type Type from get_crf_version_types()
#' @param change_summary Summary of changes
#' @param created_by User creating version
#' @param change_rationale Rationale for changes
#' @param regulatory_impact Regulatory impact assessment
#' @param backwards_compatible Whether backwards compatible
#' @param requires_retraining Whether retraining required
#' @param effective_date When version becomes effective
#'
#' @return List with success status and version details
#' @export
create_crf_version <- function(crf_id,
                                version_number,
                                version_type,
                                change_summary,
                                created_by,
                                change_rationale = NULL,
                                regulatory_impact = NULL,
                                backwards_compatible = TRUE,
                                requires_retraining = FALSE,
                                effective_date = NULL) {
  tryCatch({
    if (missing(crf_id) || is.null(crf_id)) {
      return(list(success = FALSE, error = "crf_id is required"))
    }
    if (missing(version_number) || is.null(version_number) ||
        version_number == "") {
      return(list(success = FALSE, error = "version_number is required"))
    }
    if (missing(change_summary) || is.null(change_summary) ||
        nchar(change_summary) < 10) {
      return(list(success = FALSE,
                  error = "change_summary must be at least 10 characters"))
    }

    valid_types <- names(get_crf_version_types())
    if (!version_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid version_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    crf <- DBI::dbGetQuery(con, "
      SELECT crf_id, is_locked FROM crf_definitions WHERE crf_id = ?
    ", params = list(crf_id))

    if (nrow(crf) == 0) {
      return(list(success = FALSE, error = "CRF not found"))
    }

    if (crf$is_locked[1] == 1) {
      return(list(success = FALSE, error = "CRF is locked"))
    }

    parent <- DBI::dbGetQuery(con, "
      SELECT version_id, version_hash FROM crf_versions
      WHERE crf_id = ?
      ORDER BY version_id DESC LIMIT 1
    ", params = list(crf_id))

    parent_version_id <- if (nrow(parent) > 0) parent$version_id[1] else NULL
    previous_hash <- if (nrow(parent) > 0) parent$version_hash[1] else NULL

    hash_content <- paste(
      crf_id,
      version_number,
      version_type,
      change_summary,
      created_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      if (!is.null(previous_hash)) previous_hash else "",
      sep = "|"
    )
    version_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_versions (
        crf_id, version_number, version_type, change_summary,
        change_rationale, regulatory_impact, backwards_compatible,
        requires_retraining, effective_date, created_by,
        parent_version_id, version_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      crf_id,
      version_number,
      version_type,
      change_summary,
      safe_scalar_crfv(change_rationale),
      safe_scalar_crfv(regulatory_impact),
      as.integer(backwards_compatible),
      as.integer(requires_retraining),
      safe_scalar_crfv(effective_date),
      created_by,
      safe_int_crfv(parent_version_id),
      version_hash,
      safe_scalar_crfv(previous_hash)
    ))

    version_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    DBI::dbExecute(con, "
      UPDATE crf_definitions
      SET current_version = ?, updated_at = ?, updated_by = ?
      WHERE crf_id = ?
    ", params = list(
      version_number,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      created_by,
      crf_id
    ))

    list(
      success = TRUE,
      version_id = version_id,
      version_number = version_number,
      version_type = version_type,
      message = "CRF version created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CRF Versions
#'
#' Retrieves version history for a CRF.
#'
#' @param crf_id CRF ID
#' @param status Optional filter by status
#'
#' @return List with success status and versions
#' @export
get_crf_versions <- function(crf_id, status = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(status)) {
      versions <- DBI::dbGetQuery(con, "
        SELECT * FROM crf_versions
        WHERE crf_id = ?
        ORDER BY version_id DESC
      ", params = list(crf_id))
    } else {
      versions <- DBI::dbGetQuery(con, "
        SELECT * FROM crf_versions
        WHERE crf_id = ? AND version_status = ?
        ORDER BY version_id DESC
      ", params = list(crf_id, status))
    }

    list(success = TRUE, versions = versions, count = nrow(versions))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Update Version Status
#'
#' Updates the status of a CRF version.
#'
#' @param version_id Version ID
#' @param status New status from get_crf_version_statuses()
#' @param updated_by User updating status
#'
#' @return List with success status
#' @export
update_crf_version_status <- function(version_id, status, updated_by) {
  tryCatch({
    valid_statuses <- names(get_crf_version_statuses())
    if (!status %in% valid_statuses) {
      return(list(
        success = FALSE,
        error = paste("Invalid status. Must be one of:",
                     paste(valid_statuses, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    if (status == "REVIEW") {
      DBI::dbExecute(con, "
        UPDATE crf_versions
        SET version_status = ?, reviewed_at = ?, reviewed_by = ?
        WHERE version_id = ?
      ", params = list(status, timestamp, updated_by, version_id))
    } else if (status == "APPROVED" || status == "ACTIVE") {
      DBI::dbExecute(con, "
        UPDATE crf_versions
        SET version_status = ?, approved_at = ?, approved_by = ?
        WHERE version_id = ?
      ", params = list(status, timestamp, updated_by, version_id))
    } else {
      DBI::dbExecute(con, "
        UPDATE crf_versions
        SET version_status = ?
        WHERE version_id = ?
      ", params = list(status, version_id))
    }

    list(success = TRUE, message = paste("Version status updated to", status))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# CHANGE LOG MANAGEMENT
# ============================================================================

#' Log CRF Change
#'
#' Records a change in the CRF change log.
#'
#' @param version_id Version ID
#' @param change_type Type from get_crf_change_types()
#' @param change_category Category from get_crf_change_categories()
#' @param change_description Description of change
#' @param created_by User logging change
#' @param field_code Optional field code
#' @param field_name Optional field name
#' @param attribute_changed Optional attribute that changed
#' @param old_value Optional old value
#' @param new_value Optional new value
#' @param change_justification Optional justification
#' @param impact_assessment Optional impact assessment
#' @param affected_data Whether existing data affected
#' @param data_migration_required Whether migration needed
#'
#' @return List with success status and change details
#' @export
log_crf_change <- function(version_id,
                            change_type,
                            change_category,
                            change_description,
                            created_by,
                            field_code = NULL,
                            field_name = NULL,
                            attribute_changed = NULL,
                            old_value = NULL,
                            new_value = NULL,
                            change_justification = NULL,
                            impact_assessment = NULL,
                            affected_data = FALSE,
                            data_migration_required = FALSE) {
  tryCatch({
    if (missing(version_id) || is.null(version_id)) {
      return(list(success = FALSE, error = "version_id is required"))
    }
    if (missing(change_description) || is.null(change_description) ||
        nchar(change_description) < 10) {
      return(list(success = FALSE,
                  error = "change_description must be at least 10 characters"))
    }

    valid_types <- names(get_crf_change_types())
    if (!change_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid change_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    valid_categories <- names(get_crf_change_categories())
    if (!change_category %in% valid_categories) {
      return(list(
        success = FALSE,
        error = paste("Invalid change_category. Must be one of:",
                     paste(valid_categories, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    hash_content <- paste(
      version_id,
      change_type,
      change_category,
      change_description,
      created_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    change_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_change_log (
        version_id, change_type, change_category, field_code, field_name,
        attribute_changed, old_value, new_value, change_description,
        change_justification, impact_assessment, affected_data,
        data_migration_required, created_by, change_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      version_id,
      change_type,
      change_category,
      safe_scalar_crfv(field_code),
      safe_scalar_crfv(field_name),
      safe_scalar_crfv(attribute_changed),
      safe_scalar_crfv(old_value),
      safe_scalar_crfv(new_value),
      change_description,
      safe_scalar_crfv(change_justification),
      safe_scalar_crfv(impact_assessment),
      as.integer(affected_data),
      as.integer(data_migration_required),
      created_by,
      change_hash
    ))

    change_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      change_id = change_id,
      change_type = change_type,
      message = "Change logged"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get CRF Change Log
#'
#' Retrieves change log entries for a version.
#'
#' @param version_id Version ID
#' @param change_type Optional filter by type
#' @param change_category Optional filter by category
#'
#' @return List with success status and changes
#' @export
get_crf_change_log <- function(version_id,
                                change_type = NULL,
                                change_category = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM crf_change_log WHERE version_id = ?"
    params <- list(version_id)

    if (!is.null(change_type)) {
      query <- paste(query, "AND change_type = ?")
      params <- append(params, list(change_type))
    }

    if (!is.null(change_category)) {
      query <- paste(query, "AND change_category = ?")
      params <- append(params, list(change_category))
    }

    query <- paste(query, "ORDER BY change_id")

    changes <- DBI::dbGetQuery(con, query, params = params)

    list(success = TRUE, changes = changes, count = nrow(changes))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Full CRF History
#'
#' Retrieves complete change history across all versions.
#'
#' @param crf_id CRF ID
#'
#' @return List with success status and full history
#' @export
get_crf_full_history <- function(crf_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    history <- DBI::dbGetQuery(con, "
      SELECT
        v.version_number,
        v.version_type,
        v.version_status,
        v.change_summary,
        v.created_at as version_date,
        v.created_by as version_author,
        c.change_id,
        c.change_type,
        c.change_category,
        c.field_code,
        c.field_name,
        c.old_value,
        c.new_value,
        c.change_description,
        c.created_at as change_date,
        c.created_by as change_author
      FROM crf_versions v
      LEFT JOIN crf_change_log c ON v.version_id = c.version_id
      WHERE v.crf_id = ?
      ORDER BY v.version_id DESC, c.change_id
    ", params = list(crf_id))

    list(success = TRUE, history = history, count = nrow(history))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# VERSION SNAPSHOTS
# ============================================================================

#' Create Version Snapshot
#'
#' Creates a snapshot of CRF state at a specific version.
#'
#' @param version_id Version ID
#' @param snapshot_type Type of snapshot (FULL, FIELDS, VALIDATION)
#' @param snapshot_data JSON data representing the snapshot
#' @param created_by User creating snapshot
#'
#' @return List with success status and snapshot details
#' @export
create_version_snapshot <- function(version_id,
                                     snapshot_type,
                                     snapshot_data,
                                     created_by) {
  tryCatch({
    if (missing(version_id) || is.null(version_id)) {
      return(list(success = FALSE, error = "version_id is required"))
    }
    if (!snapshot_type %in% c("FULL", "FIELDS", "VALIDATION", "LAYOUT")) {
      return(list(success = FALSE,
                  error = "snapshot_type must be FULL, FIELDS, VALIDATION, or LAYOUT"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    hash_content <- paste(
      version_id,
      snapshot_type,
      snapshot_data,
      created_by,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    snapshot_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_version_snapshots (
        version_id, snapshot_type, snapshot_data, created_by, snapshot_hash
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(
      version_id,
      snapshot_type,
      snapshot_data,
      created_by,
      snapshot_hash
    ))

    snapshot_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      snapshot_id = snapshot_id,
      snapshot_type = snapshot_type,
      message = "Snapshot created"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Version Snapshots
#'
#' Retrieves snapshots for a version.
#'
#' @param version_id Version ID
#' @param snapshot_type Optional filter by type
#'
#' @return List with success status and snapshots
#' @export
get_version_snapshots <- function(version_id, snapshot_type = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(snapshot_type)) {
      snapshots <- DBI::dbGetQuery(con, "
        SELECT * FROM crf_version_snapshots
        WHERE version_id = ?
        ORDER BY snapshot_id DESC
      ", params = list(version_id))
    } else {
      snapshots <- DBI::dbGetQuery(con, "
        SELECT * FROM crf_version_snapshots
        WHERE version_id = ? AND snapshot_type = ?
        ORDER BY snapshot_id DESC
      ", params = list(version_id, snapshot_type))
    }

    list(success = TRUE, snapshots = snapshots, count = nrow(snapshots))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# VERSION COMPARISON
# ============================================================================

#' Compare CRF Versions
#'
#' Compares two versions of a CRF.
#'
#' @param version_id_old Old version ID
#' @param version_id_new New version ID
#' @param compared_by User performing comparison
#'
#' @return List with success status and comparison details
#' @export
compare_crf_versions <- function(version_id_old,
                                  version_id_new,
                                  compared_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    changes_old <- DBI::dbGetQuery(con, "
      SELECT change_type, COUNT(*) as count
      FROM crf_change_log
      WHERE version_id = ?
      GROUP BY change_type
    ", params = list(version_id_old))

    changes_new <- DBI::dbGetQuery(con, "
      SELECT * FROM crf_change_log WHERE version_id = ?
    ", params = list(version_id_new))

    fields_added <- sum(changes_new$change_type == "ADD" &
                        changes_new$change_category == "FIELD")
    fields_removed <- sum(changes_new$change_type == "REMOVE" &
                          changes_new$change_category == "FIELD")
    fields_modified <- sum(changes_new$change_type == "MODIFY" &
                           changes_new$change_category == "FIELD")
    validation_changes <- sum(changes_new$change_category == "VALIDATION")

    summary_parts <- c()
    if (fields_added > 0) {
      summary_parts <- c(summary_parts, paste(fields_added, "fields added"))
    }
    if (fields_removed > 0) {
      summary_parts <- c(summary_parts, paste(fields_removed, "fields removed"))
    }
    if (fields_modified > 0) {
      summary_parts <- c(summary_parts, paste(fields_modified, "fields modified"))
    }
    if (validation_changes > 0) {
      summary_parts <- c(summary_parts,
                         paste(validation_changes, "validation changes"))
    }
    comparison_summary <- if (length(summary_parts) > 0) {
      paste(summary_parts, collapse = "; ")
    } else {
      "No significant changes detected"
    }

    hash_content <- paste(
      version_id_old,
      version_id_new,
      compared_by,
      comparison_summary,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    comparison_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO crf_version_comparisons (
        version_id_old, version_id_new, compared_by, fields_added,
        fields_removed, fields_modified, validation_changes,
        comparison_summary, comparison_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      version_id_old,
      version_id_new,
      compared_by,
      fields_added,
      fields_removed,
      fields_modified,
      validation_changes,
      comparison_summary,
      comparison_hash
    ))

    comparison_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(
      success = TRUE,
      comparison_id = comparison_id,
      fields_added = fields_added,
      fields_removed = fields_removed,
      fields_modified = fields_modified,
      validation_changes = validation_changes,
      comparison_summary = comparison_summary,
      changes = changes_new
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Version Comparisons
#'
#' Retrieves comparison history.
#'
#' @param crf_id Optional CRF ID to filter comparisons
#'
#' @return List with success status and comparisons
#' @export
get_version_comparisons <- function(crf_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(crf_id)) {
      comparisons <- DBI::dbGetQuery(con, "
        SELECT c.*, v1.version_number as old_version,
               v2.version_number as new_version
        FROM crf_version_comparisons c
        JOIN crf_versions v1 ON c.version_id_old = v1.version_id
        JOIN crf_versions v2 ON c.version_id_new = v2.version_id
        ORDER BY c.comparison_date DESC
      ")
    } else {
      comparisons <- DBI::dbGetQuery(con, "
        SELECT c.*, v1.version_number as old_version,
               v2.version_number as new_version
        FROM crf_version_comparisons c
        JOIN crf_versions v1 ON c.version_id_old = v1.version_id
        JOIN crf_versions v2 ON c.version_id_new = v2.version_id
        WHERE v1.crf_id = ? OR v2.crf_id = ?
        ORDER BY c.comparison_date DESC
      ", params = list(crf_id, crf_id))
    }

    list(success = TRUE, comparisons = comparisons, count = nrow(comparisons))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# STATISTICS
# ============================================================================

#' Get CRF Version Statistics
#'
#' Returns statistics about CRF versions and changes.
#'
#' @return List with statistics
#' @export
get_crf_version_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    crf_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_crfs,
        SUM(is_locked) as locked_crfs
      FROM crf_definitions
    ")

    version_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_versions,
        SUM(CASE WHEN version_status = 'DRAFT' THEN 1 ELSE 0 END) as draft,
        SUM(CASE WHEN version_status = 'ACTIVE' THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN version_status = 'APPROVED' THEN 1 ELSE 0 END) as approved
      FROM crf_versions
    ")

    change_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_changes,
        SUM(affected_data) as changes_affecting_data,
        SUM(data_migration_required) as requiring_migration
      FROM crf_change_log
    ")

    by_type <- DBI::dbGetQuery(con, "
      SELECT change_type, COUNT(*) as count
      FROM crf_change_log
      GROUP BY change_type
    ")

    list(
      success = TRUE,
      crfs = as.list(crf_stats),
      versions = as.list(version_stats),
      changes = as.list(change_stats),
      by_change_type = by_type
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
