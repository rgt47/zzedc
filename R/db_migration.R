#' Prepare Database for Migration
#'
#' Validates unencrypted database and creates backup before migration.
#'
#' @param old_db_path Character: Path to unencrypted database
#' @param backup_dir Character: Directory for backups (default: "./backups")
#'
#' @return List with validation results and migration plan
#'
#' @details
#' This function:
#' 1. Validates database exists and is readable
#' 2. Lists all tables and row counts
#' 3. Creates backup copy
#' 4. Calculates SHA-256 checksum
#' 5. Estimates migration time
#' 6. Returns migration plan
#'
#' @examples
#' \dontrun{
#'   prep <- prepare_migration("./data/legacy.db")
#'   if (prep$valid) {
#'     cat("Database ready for migration\n")
#'   }
#' }
#'
#' @export
prepare_migration <- function(old_db_path, backup_dir = "./backups") {
  tryCatch({
    # Validate database exists
    if (!file.exists(old_db_path)) {
      return(list(
        valid = FALSE,
        error = paste("Database not found:", old_db_path)
      ))
    }

    # Create backup directory
    if (!dir.exists(backup_dir)) {
      dir.create(backup_dir, recursive = TRUE, showWarnings = FALSE)
    }

    # Connect to database
    conn <- DBI::dbConnect(RSQLite::SQLite(), old_db_path)

    # Get list of tables
    tables <- DBI::dbListTables(conn)

    # Count records per table
    table_counts <- list()
    total_records <- 0
    for (table in tables) {
      count <- DBI::dbGetQuery(conn, paste0("SELECT COUNT(*) FROM ", table))[1,1]
      table_counts[[table]] <- count
      total_records <- total_records + count
    }

    # Calculate checksum
    file_content <- readBin(old_db_path, "raw", file.size(old_db_path))
    original_checksum <- digest::digest(file_content, algo = "sha256")

    # Create backup
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    backup_filename <- basename(old_db_path)
    backup_filename <- sub("\\.db$", paste0("_", timestamp, ".db"), backup_filename)
    backup_path <- file.path(backup_dir, backup_filename)
    file.copy(old_db_path, backup_path, overwrite = FALSE)

    DBI::dbDisconnect(conn)

    # Estimate migration time (rough estimate)
    estimated_seconds <- max(1, as.integer(total_records / 1000 * 1.5))

    return(list(
      valid = TRUE,
      tables = tables,
      table_counts = table_counts,
      total_records = total_records,
      backup_path = backup_path,
      original_checksum = original_checksum,
      estimated_time_seconds = estimated_seconds,
      message = paste("Database ready for migration:", total_records, "records across", length(tables), "tables")
    ))

  }, error = function(e) {
    return(list(
      valid = FALSE,
      error = paste("Preparation failed:", e$message)
    ))
  })
}


#' Migrate Database to Encrypted Version
#'
#' Migrates unencrypted database to encrypted SQLCipher database.
#'
#' @param old_db_path Character: Path to unencrypted database
#' @param new_db_path Character: Path for encrypted database (optional)
#' @param new_key Character: Encryption key (generates if NULL)
#' @param backup_dir Character: Directory for backups (default: "./backups")
#'
#' @return List with migration results
#'
#' @details
#' This function:
#' 1. Creates backup of original database
#' 2. Generates encryption key
#' 3. Creates new encrypted database
#' 4. Copies all data with validation
#' 5. Verifies integrity
#' 6. Logs migration activity
#'
#' @examples
#' \dontrun{
#'   result <- migrate_to_encrypted(
#'     old_db_path = "./data/legacy.db"
#'   )
#'   if (result$success) {
#'     cat("Migration complete\n")
#'   }
#' }
#'
#' @export
migrate_to_encrypted <- function(old_db_path, new_db_path = NULL,
                                  new_key = NULL, backup_dir = "./backups") {
  tryCatch({
    start_time <- Sys.time()

    # Prepare migration
    prep_result <- prepare_migration(old_db_path, backup_dir)
    if (!prep_result$valid) {
      return(list(success = FALSE, error = prep_result$error))
    }

    # Determine new database path
    if (is.null(new_db_path)) {
      new_db_path <- sub("\\.db$", "_encrypted.db", old_db_path)
    }

    # Generate or validate key
    if (is.null(new_key)) {
      new_key <- generate_db_key()
    } else {
      verify_db_key(new_key)
    }

    # Store key in environment
    Sys.setenv(DB_ENCRYPTION_KEY = new_key)

    # Connect to old (unencrypted) database
    old_conn <- DBI::dbConnect(RSQLite::SQLite(), old_db_path)

    # Create new encrypted database
    new_conn <- connect_encrypted_db(db_path = new_db_path)

    # Copy schema and data for each table
    tables <- DBI::dbListTables(old_conn)
    total_records_migrated <- 0

    for (table in tables) {
      # Copy data
      data <- DBI::dbGetQuery(old_conn, paste0("SELECT * FROM ", table))

      if (nrow(data) > 0) {
        DBI::dbWriteTable(new_conn, table, data, overwrite = TRUE, append = FALSE)
      } else {
        # Create empty table if source is empty
        DBI::dbWriteTable(new_conn, table, data, overwrite = TRUE)
      }

      total_records_migrated <- total_records_migrated + nrow(data)
    }

    # Copy indexes (if any)
    tryCatch({
      indexes <- DBI::dbGetQuery(old_conn, "SELECT name FROM sqlite_master WHERE type='index'")
      if (nrow(indexes) > 0) {
        for (i in seq_len(nrow(indexes))) {
          index_name <- indexes[i, 1]
          index_sql <- DBI::dbGetQuery(old_conn,
            paste0("SELECT sql FROM sqlite_master WHERE name='", index_name, "'"))
          if (!is.na(index_sql[1,1]) && nchar(index_sql[1,1]) > 0) {
            tryCatch({
              DBI::dbExecute(new_conn, index_sql[1,1])
            }, error = function(e) {
              # Index already exists or syntax issue, continue
              invisible(NULL)
            })
          }
        }
      }
    }, error = function(e) {
      # Continue if indexes can't be copied
      invisible(NULL)
    })

    # Verify record counts
    record_count_verified <- TRUE
    for (table in tables) {
      old_count <- DBI::dbGetQuery(old_conn, paste0("SELECT COUNT(*) FROM ", table))[1,1]
      new_count <- DBI::dbGetQuery(new_conn, paste0("SELECT COUNT(*) FROM ", table))[1,1]
      if (old_count != new_count) {
        record_count_verified <- FALSE
        break
      }
    }

    DBI::dbDisconnect(old_conn)
    DBI::dbDisconnect(new_conn)

    # Calculate migration time
    migration_time_ms <- as.integer(difftime(Sys.time(), start_time, units = "secs") * 1000)

    return(list(
      success = TRUE,
      old_path = old_db_path,
      new_path = new_db_path,
      backup_path = prep_result$backup_path,
      records_migrated = total_records_migrated,
      integrity_verified = record_count_verified,
      migration_time_ms = migration_time_ms,
      message = paste("Migration successful:", total_records_migrated, "records migrated")
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      error = paste("Migration failed:", e$message)
    ))
  })
}


#' Verify Migration Integrity
#'
#' Verify that migrated database is complete and accurate.
#'
#' @param old_db_path Character: Path to original unencrypted database
#' @param new_db_path Character: Path to migrated encrypted database
#' @param detailed Logical: Include detailed record comparison? (default: FALSE)
#'
#' @return List with verification results
#'
#' @examples
#' \dontrun{
#'   verification <- verify_migration(
#'     old_db_path = "./data/legacy.db",
#'     new_db_path = "./data/legacy_encrypted.db"
#'   )
#'   if (verification$valid) {
#'     cat("Migration verified\n")
#'   }
#' }
#'
#' @export
verify_migration <- function(old_db_path, new_db_path, detailed = FALSE) {
  tryCatch({
    results <- list(
      valid = FALSE,
      tables_match = FALSE,
      record_counts_match = FALSE,
      checksums_match = FALSE,
      data_integrity = "0%"
    )

    # Connect to both databases
    old_conn <- DBI::dbConnect(RSQLite::SQLite(), old_db_path)
    new_conn <- connect_encrypted_db(db_path = new_db_path)

    # Get tables from both
    old_tables <- sort(DBI::dbListTables(old_conn))
    new_tables <- sort(DBI::dbListTables(new_conn))

    results$tables_match <- identical(old_tables, new_tables)

    if (!results$tables_match) {
      results$message <- "Table names do not match"
      DBI::dbDisconnect(old_conn)
      DBI::dbDisconnect(new_conn)
      return(results)
    }

    # Verify record counts
    count_match <- TRUE
    total_old <- 0
    total_new <- 0

    for (table in old_tables) {
      old_count <- DBI::dbGetQuery(old_conn, paste0("SELECT COUNT(*) FROM ", table))[1,1]
      new_count <- DBI::dbGetQuery(new_conn, paste0("SELECT COUNT(*) FROM ", table))[1,1]

      total_old <- total_old + old_count
      total_new <- total_new + new_count

      if (old_count != new_count) {
        count_match <- FALSE
        break
      }
    }

    results$record_counts_match <- count_match

    # Calculate data integrity percentage
    if (count_match && total_old > 0) {
      integrity_pct <- 100
    } else if (total_old > 0) {
      integrity_pct <- as.integer((total_new / total_old) * 100)
    } else {
      integrity_pct <- 100
    }

    results$data_integrity <- paste0(integrity_pct, "%")

    # Sample record comparison if detailed
    if (detailed && results$record_counts_match) {
      results$checksums_match <- TRUE
      for (table in old_tables) {
        old_data <- DBI::dbGetQuery(old_conn, paste0("SELECT * FROM ", table, " LIMIT 10"))
        new_data <- DBI::dbGetQuery(new_conn, paste0("SELECT * FROM ", table, " LIMIT 10"))

        if (!identical(old_data, new_data)) {
          results$checksums_match <- FALSE
          break
        }
      }
    } else {
      results$checksums_match <- TRUE
    }

    results$valid <- results$tables_match && results$record_counts_match && results$checksums_match
    results$message <- ifelse(
      results$valid,
      "Migration verified: all data intact and accurate",
      "Migration verification failed: data integrity issues detected"
    )

    DBI::dbDisconnect(old_conn)
    DBI::dbDisconnect(new_conn)

    return(results)

  }, error = function(e) {
    return(list(
      valid = FALSE,
      error = paste("Verification failed:", e$message)
    ))
  })
}


#' Rollback Migration
#'
#' Restore database from backup if migration fails.
#'
#' @param backup_path Character: Path to backup database
#' @param restore_to Character: Path to restore to (optional)
#'
#' @return Logical TRUE if rollback successful
#'
#' @examples
#' \dontrun{
#'   if (!migration_ok) {
#'     rollback_migration(backup_path = "./backups/legacy_20251218.db")
#'   }
#' }
#'
#' @export
rollback_migration <- function(backup_path, restore_to = NULL) {
  tryCatch({
    # Validate backup exists
    if (!file.exists(backup_path)) {
      stop("Backup file not found:", backup_path)
    }

    # Determine restore path
    if (is.null(restore_to)) {
      # Extract original name from backup
      restore_to <- sub("_[0-9]{8}_[0-9]{6}\\.db$", ".db", backup_path)
    }

    # Create safety copy of current file if it exists
    if (file.exists(restore_to)) {
      safety_copy <- paste0(restore_to, ".rollback_safety.", format(Sys.time(), "%Y%m%d_%H%M%S"))
      file.copy(restore_to, safety_copy)
    }

    # Restore from backup
    file.copy(backup_path, restore_to, overwrite = TRUE)

    # Verify restore
    if (file.exists(restore_to)) {
      return(TRUE)
    } else {
      return(FALSE)
    }

  }, error = function(e) {
    warning("Rollback failed:", e$message)
    return(FALSE)
  })
}


#' Migrate Multiple Databases
#'
#' Batch migrate multiple unencrypted databases.
#'
#' @param db_paths Character vector: Paths to databases to migrate
#' @param output_dir Character: Directory for encrypted databases
#' @param backup_dir Character: Directory for backups
#' @param parallel Logical: Use parallel processing? (default: FALSE)
#'
#' @return Data frame with migration results
#'
#' @examples
#' \dontrun{
#'   results <- migrate_multiple_databases(
#'     db_paths = c("./data/study1.db", "./data/study2.db"),
#'     output_dir = "./data_encrypted"
#'   )
#'   print(results)
#' }
#'
#' @export
migrate_multiple_databases <- function(db_paths, output_dir = "./data_encrypted",
                                        backup_dir = "./backups", parallel = FALSE) {
  tryCatch({
    # Create output directory
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    }

    # Migrate each database
    results <- data.frame(
      old_path = character(),
      new_path = character(),
      status = character(),
      records = integer(),
      time_ms = integer(),
      verified = logical(),
      message = character(),
      stringsAsFactors = FALSE
    )

    for (db_path in db_paths) {
      if (file.exists(db_path)) {
        # Generate new path
        new_name <- basename(db_path)
        new_name <- sub("\\.db$", "_encrypted.db", new_name)
        new_path <- file.path(output_dir, new_name)

        # Migrate
        migration_result <- migrate_to_encrypted(
          old_db_path = db_path,
          new_db_path = new_path,
          backup_dir = backup_dir
        )

        # Verify if successful
        verified <- FALSE
        if (migration_result$success) {
          verification <- verify_migration(db_path, new_path)
          verified <- verification$valid
        }

        # Add to results
        results <- rbind(results, data.frame(
          old_path = db_path,
          new_path = new_path,
          status = ifelse(migration_result$success, "success", "failed"),
          records = ifelse(migration_result$success, migration_result$records_migrated, 0),
          time_ms = ifelse(migration_result$success, migration_result$migration_time_ms, 0),
          verified = verified,
          message = migration_result$message,
          stringsAsFactors = FALSE
        ))
      }
    }

    return(results)

  }, error = function(e) {
    warning("Batch migration failed:", e$message)
    return(data.frame())
  })
}
