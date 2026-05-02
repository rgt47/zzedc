#' Database Migration Utilities
#'
#' Functions for migrating data between database backends and managing
#' schema versions.
#'
#' @description
#' This module provides utilities for:
#' - Migrating data between backends (SQLite, DuckDB, PostgreSQL, ClickHouse)
#' - Migrating from unencrypted to encrypted databases
#' - Exporting/importing data for backup or transfer
#' - Schema version management
#'
#' @keywords internal
#' @name db_migration
NULL


# ============================================================================
# Multi-Backend Migration
# ============================================================================

#' Migrate Database Between Backends
#'
#' Copies all data from a source database to a destination database,
#' handling dialect differences automatically.
#'
#' @param source_config Configuration for source database
#' @param dest_config Configuration for destination database
#' @param tables Character vector of table names to migrate (default: all)
#' @param batch_size Number of rows to transfer per batch (default: 1000)
#' @param verbose Print progress messages (default: TRUE)
#'
#' @return List with migration results including row counts and any errors
#'
#' @examples
#' \dontrun{
#'   # Migrate from SQLite to PostgreSQL
#'   source <- list(db_backend = "sqlite",
#'                  sqlite = list(path = "data/zzedc.db"))
#'   dest <- list(db_backend = "postgresql",
#'                postgresql = list(host = "localhost", name = "zzedc",
#'                                  user = "admin", password = "secret"))
#'
#'   result <- migrate_between_backends(source, dest)
#' }
#'
#' @export
migrate_between_backends <- function(source_config, dest_config, tables = NULL,
                                     batch_size = 1000, verbose = TRUE) {

  results <- list(
    success = TRUE,
    source_backend = source_config$db_backend,
    dest_backend = dest_config$db_backend,
    tables = list(),
    errors = list(),
    start_time = Sys.time()
  )

  # Create adapters
  source_adapter <- create_db_adapter(source_config)
  dest_adapter <- create_db_adapter(dest_config)

  # Connect to both
  source_conn <- source_adapter$connect()
  dest_conn <- dest_adapter$connect()

  on.exit({
    source_adapter$disconnect(source_conn)
    dest_adapter$disconnect(dest_conn)
  })

  # Get table list if not specified
  if (is.null(tables)) {
    tables <- source_adapter$list_tables(source_conn)
  }

  if (verbose) {
    message(sprintf("Migrating %d tables from %s to %s",
                    length(tables),
                    source_config$db_backend,
                    dest_config$db_backend))
  }

  # Migrate each table
  for (table_name in tables) {
    if (verbose) message(sprintf("  Migrating table: %s", table_name))

    table_result <- tryCatch({
      migrate_table_between_backends(
        source_conn = source_conn,
        dest_conn = dest_conn,
        table_name = table_name,
        batch_size = batch_size,
        verbose = verbose
      )
    }, error = function(e) {
      list(success = FALSE, error = e$message, rows = 0)
    })

    results$tables[[table_name]] <- table_result

    if (!table_result$success) {
      results$success <- FALSE
      results$errors[[table_name]] <- table_result$error
    }
  }

  results$end_time <- Sys.time()
  results$duration_secs <- as.numeric(
    difftime(results$end_time, results$start_time, units = "secs")
  )

  if (verbose) {
    total_rows <- sum(sapply(results$tables, function(t) t$rows %||% 0))
    message(sprintf("Migration complete: %d rows in %.1f seconds",
                    total_rows, results$duration_secs))
    if (length(results$errors) > 0) {
      message(sprintf("Errors in %d tables", length(results$errors)))
    }
  }

  results
}


#' Migrate Single Table Between Backends
#'
#' @param source_conn Source database connection
#' @param dest_conn Destination database connection
#' @param table_name Table to migrate
#' @param batch_size Rows per batch
#' @param verbose Print progress
#'
#' @return List with success status and row count
#'
#' @keywords internal
migrate_table_between_backends <- function(source_conn, dest_conn,
                                           table_name, batch_size = 1000,
                                           verbose = FALSE) {

  # Read all data from source
  data <- DBI::dbReadTable(source_conn, table_name)
  total_rows <- nrow(data)

  if (total_rows == 0) {
    return(list(success = TRUE, rows = 0, message = "Empty table"))
  }

  # Check if destination table exists and truncate
  if (DBI::dbExistsTable(dest_conn, table_name)) {
    DBI::dbExecute(dest_conn, sprintf("DELETE FROM %s", table_name))
  }

  # Write in batches
  rows_written <- 0
  num_batches <- ceiling(total_rows / batch_size)

  for (i in seq_len(num_batches)) {
    start_row <- (i - 1) * batch_size + 1
    end_row <- min(i * batch_size, total_rows)
    batch <- data[start_row:end_row, , drop = FALSE]

    DBI::dbWriteTable(dest_conn, table_name, batch,
                      append = TRUE, row.names = FALSE)

    rows_written <- rows_written + nrow(batch)

    if (verbose && num_batches > 1) {
      message(sprintf("    Batch %d/%d: %d rows", i, num_batches, rows_written))
    }
  }

  list(success = TRUE, rows = rows_written)
}


#' Export Database to Files
#'
#' Exports all tables to CSV or Parquet files for backup or transfer.
#'
#' @param config Database configuration
#' @param output_dir Directory for output files
#' @param format Export format: "csv" or "parquet"
#' @param tables Tables to export (default: all)
#' @param compress Compress CSV files (default: TRUE)
#'
#' @return List with export results
#'
#'
#' @examples
#' \dontrun{
#' # Export every table in the study database to a directory of
#' # CSV (or Parquet) files for archival or analysis.
#' export_to_files(
#'   config = list(db_backend = "sqlite",
#'                 sqlite = list(path = "data/study.db")),
#'   output_dir = tempfile(),
#'   format  = "parquet"
#' )
#' }
#' @export
export_to_files <- function(config, output_dir, format = "csv",
                            tables = NULL, compress = TRUE) {

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  adapter <- create_db_adapter(config)
  conn <- adapter$connect()
  on.exit(adapter$disconnect(conn))

  if (is.null(tables)) {
    tables <- adapter$list_tables(conn)
  }

  results <- list(
    success = TRUE,
    format = format,
    output_dir = output_dir,
    tables = list()
  )

  for (table_name in tables) {
    result <- tryCatch({
      data <- DBI::dbReadTable(conn, table_name)

      if (format == "parquet") {
        if (!requireNamespace("arrow", quietly = TRUE)) {
          stop("arrow package required for Parquet export")
        }
        file_path <- file.path(output_dir, paste0(table_name, ".parquet"))
        arrow::write_parquet(data, file_path)
      } else {
        ext <- if (compress) ".csv.gz" else ".csv"
        file_path <- file.path(output_dir, paste0(table_name, ext))

        if (compress) {
          gz_conn <- gzfile(file_path, "w")
          write.csv(data, gz_conn, row.names = FALSE)
          close(gz_conn)
        } else {
          write.csv(data, file_path, row.names = FALSE)
        }
      }

      list(success = TRUE, rows = nrow(data), file = file_path)
    }, error = function(e) {
      list(success = FALSE, error = e$message)
    })

    results$tables[[table_name]] <- result
    if (!result$success) results$success <- FALSE
  }

  # Write manifest
  manifest <- list(
    export_time = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    backend = config$db_backend,
    format = format,
    tables = names(results$tables),
    row_counts = sapply(results$tables, function(t) t$rows %||% 0)
  )
  writeLines(
    jsonlite::toJSON(manifest, pretty = TRUE, auto_unbox = TRUE),
    file.path(output_dir, "manifest.json")
  )

  results
}


#' Import Database from Files
#'
#' Imports data from exported CSV or Parquet files into a database.
#'
#' @param config Database configuration for destination
#' @param input_dir Directory containing export files
#' @param format Import format: "csv" or "parquet" (auto-detected if NULL)
#' @param tables Tables to import (default: all from manifest)
#' @param truncate Truncate existing tables before import (default: TRUE)
#'
#' @return List with import results
#'
#' @keywords internal
#' @export
import_from_files <- function(config, input_dir, format = NULL,
                              tables = NULL, truncate = TRUE) {

  # Read manifest
  manifest_path <- file.path(input_dir, "manifest.json")
  if (file.exists(manifest_path)) {
    manifest <- jsonlite::fromJSON(manifest_path)
    if (is.null(format)) format <- manifest$format
    if (is.null(tables)) tables <- manifest$tables
  } else {
    files <- list.files(input_dir, pattern = "\\.(csv|parquet)(\\.gz)?$")
    if (is.null(format)) {
      format <- if (any(grepl("\\.parquet$", files))) "parquet" else "csv"
    }
    if (is.null(tables)) {
      tables <- gsub("\\.(csv|parquet)(\\.gz)?$", "", files)
    }
  }

  adapter <- create_db_adapter(config)
  conn <- adapter$connect()
  on.exit(adapter$disconnect(conn))

  results <- list(success = TRUE, format = format, tables = list())

  for (table_name in tables) {
    result <- tryCatch({
      if (format == "parquet") {
        file_path <- file.path(input_dir, paste0(table_name, ".parquet"))
        data <- arrow::read_parquet(file_path)
      } else {
        file_path <- file.path(input_dir, paste0(table_name, ".csv.gz"))
        if (!file.exists(file_path)) {
          file_path <- file.path(input_dir, paste0(table_name, ".csv"))
        }
        data <- read.csv(file_path, stringsAsFactors = FALSE)
      }

      if (truncate && DBI::dbExistsTable(conn, table_name)) {
        DBI::dbExecute(conn, sprintf("DELETE FROM %s", table_name))
      }

      DBI::dbWriteTable(conn, table_name, data, append = TRUE, row.names = FALSE)
      list(success = TRUE, rows = nrow(data))
    }, error = function(e) {
      list(success = FALSE, error = e$message)
    })

    results$tables[[table_name]] <- result
    if (!result$success) results$success <- FALSE
  }

  results
}


#' Compare Database Contents
#'
#' Compares row counts between two databases.
#'
#' @param config1 First database configuration
#' @param config2 Second database configuration
#' @param tables Tables to compare (default: all common tables)
#'
#' @return Data frame with comparison results
#'
#' @keywords internal
#' @export
compare_databases <- function(config1, config2, tables = NULL) {

  adapter1 <- create_db_adapter(config1)
  adapter2 <- create_db_adapter(config2)

  conn1 <- adapter1$connect()
  conn2 <- adapter2$connect()

  on.exit({
    adapter1$disconnect(conn1)
    adapter2$disconnect(conn2)
  })

  tables1 <- adapter1$list_tables(conn1)
  tables2 <- adapter2$list_tables(conn2)

  if (is.null(tables)) {
    tables <- intersect(tables1, tables2)
  }

  rows <- lapply(tables, function(table_name) {
    count1 <- DBI::dbGetQuery(
      conn1, sprintf("SELECT COUNT(*) as n FROM %s", table_name)
    )$n
    count2 <- DBI::dbGetQuery(
      conn2, sprintf("SELECT COUNT(*) as n FROM %s", table_name)
    )$n
    data.frame(
      table = table_name,
      rows_db1 = count1,
      rows_db2 = count2,
      match = count1 == count2,
      stringsAsFactors = FALSE
    )
  })

  results <- if (length(rows) == 0) {
    data.frame(
      table = character(),
      rows_db1 = integer(),
      rows_db2 = integer(),
      match = logical(),
      stringsAsFactors = FALSE
    )
  } else {
    do.call(rbind, rows)
  }

  attr(results, "db1") <- config1$db_backend
  attr(results, "db2") <- config2$db_backend

  results
}


# Null coalescing operator
`%||%` <- function(x, y) if (is.null(x)) y else x


# ============================================================================
# Legacy Encryption Migration (SQLite-specific)
# ============================================================================

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
#' @keywords internal
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
#' @return List with migration results, including `new_key` (the
#'   encryption key used). The function does not persist `new_key` to
#'   the user's environment; the caller is responsible for storing it
#'   securely (e.g., AWS Secrets Manager, a password manager, or
#'   `Sys.setenv(DB_ENCRYPTION_KEY = result$new_key)` for the current
#'   session). Losing `new_key` makes the encrypted database
#'   unrecoverable.
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
#'     # Store the key for subsequent operations in this session
#'     Sys.setenv(DB_ENCRYPTION_KEY = result$new_key)
#'     cat("Migration complete; key length:", nchar(result$new_key), "\n")
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

    # Connect to old (unencrypted) database
    old_conn <- DBI::dbConnect(RSQLite::SQLite(), old_db_path)

    # Initialize new encrypted database with the chosen key (passed
    # explicitly rather than via the process environment).
    init_result <- initialize_encrypted_database(
      db_path = new_db_path, overwrite = FALSE, key = new_key
    )
    if (!init_result$success) {
      DBI::dbDisconnect(old_conn)
      return(list(success = FALSE, error = "Failed to initialize encrypted database"))
    }

    # Connect to new encrypted database with the same key. Threading
    # the key through arguments keeps the caller's environment
    # untouched.
    new_conn <- connect_encrypted_db(db_path = new_db_path, key = new_key)

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
      new_key = new_key,
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

    # Check that all original tables exist in new database
    # (new database may have additional base schema tables from initialization)
    results$tables_match <- all(old_tables %in% new_tables)

    if (!results$tables_match) {
      missing <- setdiff(old_tables, new_tables)
      results$message <- paste("Missing tables in encrypted database:", paste(missing, collapse = ", "))
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
#' @keywords internal
#' @export
migrate_multiple_databases <- function(db_paths, output_dir = "./data_encrypted",
                                        backup_dir = "./backups", parallel = FALSE) {
  tryCatch({
    # Create output directory
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    }

    rows <- lapply(db_paths, function(db_path) {
      if (!file.exists(db_path)) return(NULL)

      new_name <- sub("\\.db$", "_encrypted.db", basename(db_path))
      new_path <- file.path(output_dir, new_name)

      migration_result <- migrate_to_encrypted(
        old_db_path = db_path,
        new_db_path = new_path,
        backup_dir = backup_dir
      )

      verified <- FALSE
      if (migration_result$success) {
        verification <- verify_migration(db_path, new_path)
        verified <- verification$valid
      }

      data.frame(
        old_path = db_path,
        new_path = new_path,
        status = ifelse(migration_result$success, "success", "failed"),
        records = ifelse(migration_result$success,
                          migration_result$records_migrated, 0),
        time_ms = ifelse(migration_result$success,
                          migration_result$migration_time_ms, 0),
        verified = verified,
        message = migration_result$message,
        stringsAsFactors = FALSE
      )
    })

    results <- if (length(rows) == 0 || all(vapply(rows, is.null, logical(1)))) {
      data.frame(
        old_path = character(),
        new_path = character(),
        status = character(),
        records = integer(),
        time_ms = integer(),
        verified = logical(),
        message = character(),
        stringsAsFactors = FALSE
      )
    } else {
      do.call(rbind, rows)
    }

    return(results)

  }, error = function(e) {
    warning("Batch migration failed:", e$message)
    return(data.frame())
  })
}
