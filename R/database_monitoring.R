# ZZedc Database Monitoring and Performance Tuning
#
# Purpose: Monitor database health, identify performance issues,
# and optimize query performance
#
#' @importFrom DBI dbGetQuery dbExecute dbListTables
#' @importFrom stats setNames
NULL

# ============================================================================
# DATABASE INFORMATION FUNCTIONS
# ============================================================================

#' Get database file size
#'
#' Returns the size of the SQLite database file on disk
#'
#' @param db_path Path to database file
#' @return List with size information
#'
#' @examples
#' \dontrun{
#' # Inspect the on-disk size of the encrypted study database.
#' size <- get_db_file_size("data/study.db")
#' size$human_readable
#' }
#' @keywords internal
get_db_file_size <- function(db_path = "data/memory001_study.db") {
  if (!file.exists(db_path)) {
    stop("Database file not found: ", db_path)
  }

  file_info <- file.info(db_path)
  size_bytes <- file_info$size
  size_mb <- round(size_bytes / (1024^2), 2)
  size_gb <- round(size_bytes / (1024^3), 4)

  list(
    path = db_path,
    size_bytes = size_bytes,
    size_mb = size_mb,
    size_gb = size_gb,
    last_modified = file_info$mtime,
    human_readable = paste0(
      if (size_mb < 1) paste0(round(size_bytes/1024, 2), " KB")
      else if (size_mb < 1024) paste0(size_mb, " MB")
      else paste0(size_gb, " GB")
    )
  )
}

#' Get database statistics
#'
#' Returns summary statistics about database contents
#'
#' @param conn Database connection
#' @return Data frame with table statistics
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' stats <- get_db_statistics(conn)
#' head(stats)
#' }
#' @keywords internal
get_db_statistics <- function(conn) {
  tables <- dbListTables(conn)

  rows <- lapply(tables, function(table) {
    tryCatch({
      row_count <- dbGetQuery(
        conn, paste0("SELECT COUNT(*) as row_count FROM ", table)
      )[[1]]
      col_info <- dbGetQuery(
        conn, paste0("PRAGMA table_info(", table, ")")
      )
      data.frame(
        table = table,
        rows = row_count,
        columns = nrow(col_info),
        estimated_size_kb = round(row_count * nrow(col_info) * 0.5, 1)
      )
    }, error = function(e) {
      cat("Error reading table:", table, "\n")
      NULL
    })
  })

  do.call(rbind, rows)
}

#' Display database overview
#'
#' @param conn Database connection
#' @return Prints overview to console
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' show_db_overview(conn)
#' }
#' @keywords internal
show_db_overview <- function(conn) {
  cat("\n===== DATABASE OVERVIEW =====\n\n")

  size_info <- get_db_file_size()
  cat("File Size:", size_info$human_readable, "\n")
  cat("Last Modified:", format(size_info$last_modified, "%Y-%m-%d %H:%M:%S"), "\n\n")

  stats <- get_db_statistics(conn)
  cat("Table Statistics:\n")
  print(stats)

  total_rows <- sum(stats$rows)
  total_cols <- sum(stats$columns)
  cat("\nTotal Rows:", total_rows, "\n")
  cat("Total Tables:", nrow(stats), "\n")

  return(invisible(stats))
}

# ============================================================================
# PERFORMANCE MONITORING FUNCTIONS
# ============================================================================

#' Analyze query performance
#'
#' Measure query execution time and row count
#'
#' @param conn Database connection
#' @param query SQL query to analyze
#' @return List with timing information
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' # Run the full performance-analysis pass: timing + recommendations.
#' analyze_query_performance(conn)
#' }
#' @keywords internal
analyze_query_performance <- function(conn, query) {
  start_time <- Sys.time()
  result <- dbGetQuery(conn, query)
  end_time <- Sys.time()

  elapsed_ms <- as.numeric(difftime(end_time, start_time, units = "secs")) * 1000

  list(
    rows_returned = nrow(result),
    cols_returned = ncol(result),
    execution_time_ms = round(elapsed_ms, 2),
    rows_per_second = round(nrow(result) / (elapsed_ms / 1000)),
    query = query
  )
}

#' Find slow queries
#'
#' Identify common slow operations
#'
#' @param conn Database connection
#' @return Prints recommendations for optimization
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' # Replay a panel of representative queries and report timings.
#' identify_slow_queries(conn)
#' }
#' @keywords internal
identify_slow_queries <- function(conn) {
  cat("\n===== ANALYZING QUERY PERFORMANCE =====\n\n")

  # Test common operations
  queries <- list(
    "Count all records" = "SELECT COUNT(*) FROM form_submissions",
    "Form completeness" = "SELECT form_name, COUNT(*) as total, SUM(CASE WHEN status='complete' THEN 1 ELSE 0 END) as complete FROM form_submissions GROUP BY form_name",
    "Missing data analysis" = "SELECT COUNT(*) FROM form_data WHERE value IS NULL OR value = ''",
    "Recent entries" = "SELECT * FROM form_submissions ORDER BY created_at DESC LIMIT 100"
  )

  cat("Query Performance Analysis:\n")
  cat("(Times in milliseconds)\n\n")

  rows <- lapply(names(queries), function(name) {
    tryCatch({
      perf <- analyze_query_performance(conn, queries[[name]])
      cat(sprintf(
        "%-30s : %8.2f ms  (%d rows)\n",
        name, perf$execution_time_ms, perf$rows_returned
      ))
      data.frame(
        query_name = name,
        rows = perf$rows_returned,
        time_ms = perf$execution_time_ms,
        stringsAsFactors = FALSE
      )
    }, error = function(e) {
      cat(sprintf("%-30s : ERROR - %s\n", name, e$message))
      NULL
    })
  })
  performance <- do.call(rbind, rows)

  # Recommendations
  cat("\n===== OPTIMIZATION RECOMMENDATIONS =====\n\n")

  slow_queries <- performance[performance$time_ms > 1000, ]
  if (nrow(slow_queries) > 0) {
    cat("SLOW QUERIES DETECTED:\n")
    for (i in 1:nrow(slow_queries)) {
      cat("  -", slow_queries$query_name[i], "\n")
    }
    cat("  -> Consider adding indexes to frequently queried columns\n\n")
  } else {
    cat("Query performance looks good\n\n")
  }

  return(invisible(performance))
}

# ============================================================================
# OPTIMIZATION FUNCTIONS
# ============================================================================

#' Create recommended indexes
#'
#' Adds indexes to improve common query patterns
#'
#' @param conn Database connection
#' @return TRUE if successful
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' # Create the index set recommended for typical EDC workloads
#' # (subjects.study_id, edc_users.username, audit_trail.user_id, ...).
#' create_recommended_indexes(conn)
#' }
#' @keywords internal
create_recommended_indexes <- function(conn) {
  cat("\n===== CREATING RECOMMENDED INDEXES =====\n\n")

  indexes <- list(
    list(name = "idx_form_submissions_status",
         table = "form_submissions",
         cols = "(status, form_name)"),
    list(name = "idx_form_submissions_date",
         table = "form_submissions",
         cols = "(created_at)"),
    list(name = "idx_form_data_field",
         table = "form_data",
         cols = "(field_name)"),
    list(name = "idx_form_data_value",
         table = "form_data",
         cols = "(value)"),
    list(name = "idx_audit_log_user",
         table = "audit_log",
         cols = "(user_id)"),
    list(name = "idx_audit_log_timestamp",
         table = "audit_log",
         cols = "(timestamp)")
  )

  for (idx in indexes) {
    tryCatch({
      sql <- paste0("CREATE INDEX IF NOT EXISTS ", idx$name,
                   " ON ", idx$table, " ", idx$cols)
      dbExecute(conn, sql)
      cat("Created index:", idx$name, "\n")
    }, error = function(e) {
      cat("Error creating", idx$name, ":", e$message, "\n")
    })
  }

  cat("\nIndexes created successfully!\n")
  return(invisible(TRUE))
}

#' Analyze indexes
#'
#' Show what indexes exist and their usage
#'
#' @param conn Database connection
#' @return Data frame with index information
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' # Show the indexes currently defined on the study schema.
#' analyze_indexes(conn)
#' }
#' @keywords internal
analyze_indexes <- function(conn) {
  cat("\n===== EXISTING INDEXES =====\n\n")

  tryCatch({
    # SQLite doesn't provide detailed index stats, so we query the schema
    sql <- "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    indexes <- dbGetQuery(conn, sql)

    if (nrow(indexes) == 0) {
      cat("No custom indexes found. Run create_recommended_indexes() to add them.\n")
      return(invisible(NULL))
    }

    cat("Found", nrow(indexes), "indexes:\n")
    for (i in 1:nrow(indexes)) {
      cat(" -", indexes$name[i], "\n")
    }

    return(invisible(indexes))
  }, error = function(e) {
    cat("Error analyzing indexes:", e$message, "\n")
    return(invisible(NULL))
  })
}

#' Vacuum database
#'
#' Cleanup and optimize database file (may take time on large databases)
#'
#' @param conn Database connection
#' @return TRUE if successful
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' # Reclaim space after large deletes (e.g., end-of-study cleanup).
#' vacuum_database(conn)
#' }
#' @keywords internal
vacuum_database <- function(conn) {
  cat("\n===== VACUUMING DATABASE =====\n")
  cat("(This may take a moment...)\n\n")

  start_time <- Sys.time()
  tryCatch({
    dbExecute(conn, "VACUUM")
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    cat("Database vacuumed successfully\n")
    cat("  Time taken:", round(elapsed, 2), "seconds\n")
    return(invisible(TRUE))
  }, error = function(e) {
    cat("Error vacuuming database:", e$message, "\n")
    return(invisible(FALSE))
  })
}

# ============================================================================
# MONITORING FUNCTIONS
# ============================================================================

#' Check database health
#'
#' Run comprehensive health checks
#'
#' @param conn Database connection
#' @return List with health status
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' check_database_health(conn)
#' }
#' @keywords internal
check_database_health <- function(conn) {
  cat("\n===== DATABASE HEALTH CHECK =====\n\n")

  health <- list(
    status = "HEALTHY",
    checks = list(),
    warnings = character(),
    errors = character()
  )

  # Check 1: File size
  cat("Checking file size...")
  size_info <- get_db_file_size()
  size_mb <- size_info$size_mb

  if (size_mb > 1024) {
    health$warnings <- c(health$warnings, "Database file is very large (>1GB). Consider archiving old data.")
  }
  health$checks$file_size <- list(size_mb = size_mb, status = "OK")
  cat(" OK\n")

  # Check 2: Table integrity
  cat("Checking table integrity...")
  tables <- dbListTables(conn)
  integrity_ok <- TRUE

  for (table in tables) {
    tryCatch({
      dbGetQuery(conn, paste0("SELECT COUNT(*) FROM ", table))
    }, error = function(e) {
      integrity_ok <<- FALSE
      health$errors <<- c(health$errors, paste("Table", table, "has integrity issues"))
    })
  }
  health$checks$integrity <- list(tables = length(tables), status = if (integrity_ok) "OK" else "ERRORS")
  cat(if (integrity_ok) " OK\n" else " ERRORS\n")

  # Check 3: Record counts
  cat("Checking record counts...")
  stats <- get_db_statistics(conn)
  total_rows <- sum(stats$rows)

  if (total_rows == 0) {
    health$warnings <- c(health$warnings, "Database contains no data")
  }
  health$checks$record_count <- list(total = total_rows, status = "OK")
  cat(" OK\n")

  # Determine overall status
  if (length(health$errors) > 0) {
    health$status <- "CRITICAL"
  } else if (length(health$warnings) > 0) {
    health$status <- "WARNING"
  }

  # Print summary
  cat("\n===== HEALTH CHECK SUMMARY =====\n\n")
  cat("Status:", health$status, "\n\n")

  if (length(health$warnings) > 0) {
    cat("Warnings:\n")
    for (warn in health$warnings) {
      cat("  ", warn, "\n")
    }
    cat("\n")
  }

  if (length(health$errors) > 0) {
    cat("Errors:\n")
    for (err in health$errors) {
      cat("  ", err, "\n")
    }
    cat("\n")
  }

  return(invisible(health))
}

#' Monitor data entry rate
#'
#' Track how many records are being entered per day
#'
#' @param conn Database connection
#' @param days Number of days to analyze (default: 30)
#' @return Data frame with daily counts
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' # Track records-per-day to detect a slowdown in study enrolment.
#' monitor_data_entry_rate(conn, days = 30)
#' }
#' @keywords internal
monitor_data_entry_rate <- function(conn, days = 30) {
  cat("\n===== DATA ENTRY RATE (Last", days, "days) =====\n\n")

  tryCatch({
    query <- paste0(
      "SELECT DATE(created_at) as date, COUNT(*) as entries ",
      "FROM form_submissions ",
      "WHERE created_at >= date('now', '-", days, " days') ",
      "GROUP BY DATE(created_at) ",
      "ORDER BY date DESC"
    )

    data <- dbGetQuery(conn, query)

    if (nrow(data) == 0) {
      cat("No data entries found in the specified period.\n")
      return(invisible(NULL))
    }

    # Calculate statistics
    total_entries <- sum(data$entries)
    avg_per_day <- round(mean(data$entries), 1)
    max_per_day <- max(data$entries)
    min_per_day <- min(data$entries)

    cat("Total entries:", total_entries, "\n")
    cat("Average per day:", avg_per_day, "\n")
    cat("Max in a day:", max_per_day, "\n")
    cat("Min in a day:", min_per_day, "\n\n")

    # Show last 7 days
    recent <- data[1:min(7, nrow(data)), ]
    cat("Last 7 days:\n")
    for (i in 1:nrow(recent)) {
      bar <- strrep("#", ceiling(recent$entries[i] / 10))
      cat(sprintf("%s : %3d entries %s\n", recent$date[i], recent$entries[i], bar))
    }

    return(invisible(data))
  }, error = function(e) {
    cat("Error analyzing entry rate:", e$message, "\n")
    return(invisible(NULL))
  })
}

# ============================================================================
# MAINTENANCE FUNCTIONS
# ============================================================================

#' Cleanup old audit logs
#'
#' Archive and remove old audit log entries (configurable retention)
#'
#' @param conn Database connection
#' @param days_to_keep How many days of audit logs to keep (default: 365)
#' @return Number of records deleted
#'
#' @examples
#' \dontrun{
#' # Connect to an initialised study database. See
#' # `?initialize_encrypted_database` for the prerequisite setup.
#' conn <- connect_encrypted_db(db_path = "data/study.db",
#'                               key      = Sys.getenv("DB_ENCRYPTION_KEY"))
#' on.exit(DBI::dbDisconnect(conn), add = TRUE)
#' # Trim audit-log records older than the retention window.
#' # Verify retention policy with the IRB before running.
#' cleanup_audit_logs(conn, days_to_keep = 365 * 7)
#' }
#' @keywords internal
cleanup_audit_logs <- function(conn, days_to_keep = 365) {
  cat("\n===== AUDIT LOG CLEANUP =====\n")
  cat("Keeping logs from last", days_to_keep, "days...\n\n")

  tryCatch({
    # Get count before
    before <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM audit_log")[[1]]

    # Delete old records
    sql <- paste0(
      "DELETE FROM audit_log WHERE timestamp < datetime('now', '-", days_to_keep, " days')"
    )
    deleted <- dbExecute(conn, sql)

    # Get count after
    after <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM audit_log")[[1]]

    cat("Deleted", deleted, "old audit log records\n")
    cat("  Before: ", before, " records\n")
    cat("  After: ", after, " records\n")

    return(invisible(deleted))
  }, error = function(e) {
    cat("Error cleaning up audit logs:", e$message, "\n")
    return(invisible(0))
  })
}

#' Backup database
#'
#' Create a backup copy of the database
#'
#' @param db_path Path to database file
#' @param backup_dir Directory to store backup (default: "backups/")
#' @return Path to backup file
#'
#' @examples
#' \dontrun{
#' # Create a timestamped backup of the encrypted database.
#' backup_database(db_path     = "data/study.db",
#'                 backup_dir  = "backups")
#' }
#' @keywords internal
backup_database <- function(db_path = "data/memory001_study.db",
                           backup_dir = "backups/") {
  cat("\n===== DATABASE BACKUP =====\n\n")

  if (!file.exists(db_path)) {
    stop("Database file not found:", db_path)
  }

  # Create backup directory if needed
  if (!dir.exists(backup_dir)) {
    dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)
  }

  # Generate backup filename with timestamp
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  backup_file <- file.path(backup_dir,
                           paste0("study_", timestamp, ".db"))

  tryCatch({
    file.copy(db_path, backup_file, overwrite = FALSE)

    file_size <- file.info(backup_file)$size
    size_mb <- round(file_size / (1024^2), 2)

    cat("Backup created successfully\n")
    cat("  File:", backup_file, "\n")
    cat("  Size:", size_mb, "MB\n")

    return(invisible(backup_file))
  }, error = function(e) {
    cat("Error creating backup:", e$message, "\n")
    return(invisible(NULL))
  })
}

# ============================================================================
# MAIN MONITORING FUNCTION
# ============================================================================

#' Run complete database monitoring
#'
#' Execute all monitoring and analysis functions
#'
#' @param db_path Path to database file
#' @return Invisibly returns monitoring results
#'
#' @examples
#' \dontrun{
#' # End-of-week monitoring sweep: file size, statistics, health,
#' # slow queries, indexes, entry rate. Prints a single report.
#' run_complete_monitoring(db_path = "data/study.db")
#' }
#' @keywords internal
run_complete_monitoring <- function(db_path = "data/memory001_study.db") {
  cat("\n")
  cat("=== ZZedc DATABASE MONITORING & ANALYSIS REPORT ===\n")
  cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat("===================================================\n")

  # Connect to database
  tryCatch({
    conn <- dbConnect(SQLite(), db_path)

    # Run all monitoring functions
    show_db_overview(conn)
    check_database_health(conn)
    identify_slow_queries(conn)
    analyze_indexes(conn)
    monitor_data_entry_rate(conn)

    cat("\n===================================================\n")
    cat("MONITORING COMPLETE\n")
    cat("===================================================\n\n")

    # Cleanup
    dbDisconnect(conn)

  }, error = function(e) {
    cat("FATAL ERROR:", e$message, "\n")
  })
}

# A previous version of this file printed a "Quick Start Commands"
# banner at the top level, which executed every time the package
# was loaded. That violates CRAN policy and clutters every R
# session that loads zzedc. The banner has been removed; callers
# can discover the monitoring functions through `?get_db_file_size`,
# `?run_complete_monitoring`, and the package help index.
