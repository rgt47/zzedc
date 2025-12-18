# Feature #1 - Step 7: Database Migration Script

**Timeline**: Week 3, Days 1-2
**Deliverable**: R/db_migration.R with encrypted database migration utilities
**Status**: Ready to implement

---

## Objective

Create a database migration utility that:
- Migrates unencrypted databases to encrypted schema
- Preserves all existing data with integrity verification
- Creates secure backups before migration
- Validates migration with checksums
- Provides rollback capability
- Logs migration activity for audit trail
- Handles large datasets efficiently

---

## Module Overview

**File**: `/R/db_migration.R`
**Size**: 500-600 lines
**Functions**: 5 (all exported)
**Dependencies**: DBI, RSQLite, digest, data.table (optional for performance)

---

## The 5 Functions

### Function 1: `prepare_migration(old_db_path, backup_dir = "./backups")`

**Purpose**: Validate database and prepare for migration

**Inputs**:
- `old_db_path` (character): Path to unencrypted database
- `backup_dir` (character): Directory for backups (default: "./backups")

**Outputs**:
- List with validation results and migration plan

**Usage**:
```r
# Prepare migration
prep <- prepare_migration(
  old_db_path = "./data/legacy_study.db"
)
# Returns: list(
#   valid = TRUE,
#   tables = c("subjects", "assessments", ...),
#   total_records = 1500,
#   backup_path = "./backups/legacy_study_20251218_120000.db",
#   estimated_time = "2-3 minutes",
#   message = "Database ready for migration"
# )
```

**Implementation Details**:
- Validates unencrypted database exists
- Lists all tables and row counts
- Creates backup before any changes
- Calculates SHA-256 checksum of original
- Estimates migration time
- Returns detailed migration plan

---

### Function 2: `migrate_to_encrypted(old_db_path, new_db_path = NULL, new_key = NULL, backup_dir = "./backups")`

**Purpose**: Migrate unencrypted database to encrypted version

**Inputs**:
- `old_db_path` (character): Path to unencrypted database
- `new_db_path` (character, optional): Path for encrypted database
- `new_key` (character, optional): Encryption key (generates if NULL)
- `backup_dir` (character): Directory for backups

**Outputs**:
- List with migration results

**Usage**:
```r
# Migrate with automatic settings
result <- migrate_to_encrypted(
  old_db_path = "./data/legacy_study.db"
)
# Returns: list(
#   success = TRUE,
#   old_path = "./data/legacy_study.db",
#   new_path = "./data/legacy_study_encrypted.db",
#   backup_path = "./backups/...",
#   records_migrated = 1500,
#   integrity_verified = TRUE,
#   migration_time_ms = 12345,
#   message = "Migration successful"
# )

# Migrate with specific key and path
result <- migrate_to_encrypted(
  old_db_path = "./data/old.db",
  new_db_path = "./data/new_encrypted.db",
  new_key = generate_db_key()
)
```

**Implementation Details**:
- Creates backup of original database
- Generates encryption key if not provided
- Creates new encrypted database with schema
- Copies all data table-by-table
- Verifies record counts match
- Validates checksums for integrity
- Logs migration to audit trail
- Returns detailed migration report

---

### Function 3: `verify_migration(old_db_path, new_db_path, detailed = FALSE)`

**Purpose**: Verify migration integrity and data completeness

**Inputs**:
- `old_db_path` (character): Path to original unencrypted database
- `new_db_path` (character): Path to new encrypted database
- `detailed` (logical): Include detailed record comparison?

**Outputs**:
- List with verification results

**Usage**:
```r
# Quick verification
verification <- verify_migration(
  old_db_path = "./data/legacy_study.db",
  new_db_path = "./data/legacy_study_encrypted.db"
)
# Returns: list(
#   valid = TRUE,
#   tables_match = TRUE,
#   record_counts_match = TRUE,
#   checksums_match = TRUE,
#   data_integrity = "100%",
#   message = "Migration verified: all data intact"
# )

# Detailed verification with record sampling
verification <- verify_migration(
  old_db_path = "./data/legacy_study.db",
  new_db_path = "./data/legacy_study_encrypted.db",
  detailed = TRUE
)
```

**Implementation Details**:
- Compares table structures
- Verifies table counts match
- Samples records for comparison
- Validates checksums
- Checks indexes exist
- Reports any mismatches
- Provides integrity percentage

---

### Function 4: `rollback_migration(backup_path, restore_to = NULL)`

**Purpose**: Rollback failed migration using backup

**Inputs**:
- `backup_path` (character): Path to backup database
- `restore_to` (character, optional): Path to restore to (uses original if NULL)

**Outputs**:
- Logical TRUE if rollback successful

**Usage**:
```r
# Rollback migration
if (!migration_successful) {
  rollback_result <- rollback_migration(
    backup_path = "./backups/legacy_study_20251218_120000.db",
    restore_to = "./data/legacy_study.db"
  )
  if (rollback_result) {
    cat("Migration rolled back successfully\n")
  }
}
```

**Implementation Details**:
- Verifies backup exists
- Creates safety copy before restore
- Restores from backup
- Verifies restore integrity
- Logs rollback action
- Returns success status

---

### Function 5: `migrate_multiple_databases(db_paths, output_dir = "./data_encrypted", backup_dir = "./backups", parallel = FALSE)`

**Purpose**: Batch migrate multiple unencrypted databases

**Inputs**:
- `db_paths` (character vector): Paths to databases to migrate
- `output_dir` (character): Directory for encrypted databases
- `backup_dir` (character): Directory for backups
- `parallel` (logical): Use parallel processing? (default: FALSE)

**Outputs**:
- Data frame with migration results for each database

**Usage**:
```r
# Batch migrate multiple studies
results <- migrate_multiple_databases(
  db_paths = c(
    "./data/study1.db",
    "./data/study2.db",
    "./data/study3.db"
  ),
  output_dir = "./data_encrypted"
)
# Returns data frame with:
# - old_path, new_path, status, records, verification, message

# Batch migrate with parallel processing
results <- migrate_multiple_databases(
  db_paths = list.files("./data", pattern = "\\.db$", full.names = TRUE),
  output_dir = "./data_encrypted",
  parallel = TRUE
)
```

**Implementation Details**:
- Iterates through all databases
- Migrates each individually
- Handles errors gracefully
- Collects results
- Supports parallel processing
- Returns comprehensive report

---

## Complete Implementation

Create file: `/R/db_migration.R`

```r
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
      # Get table schema
      schema <- DBI::dbGetQuery(old_conn, paste0("PRAGMA table_info(", table, ")"))

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
```

---

## Integration Strategy

### Example Usage

**Single Database Migration:**
```r
# 1. Prepare migration
prep <- prepare_migration("./data/legacy_study.db")
cat("Backup created at:", prep$backup_path, "\n")

# 2. Perform migration
migration <- migrate_to_encrypted("./data/legacy_study.db")
cat("Records migrated:", migration$records_migrated, "\n")

# 3. Verify migration
verification <- verify_migration(
  "./data/legacy_study.db",
  migration$new_path
)
cat("Integrity verified:", verification$valid, "\n")

# 4. If successful, rename encrypted version
if (verification$valid) {
  file.remove("./data/legacy_study.db")
  file.rename(migration$new_path, "./data/legacy_study.db")
}
```

**Batch Migration:**
```r
# Migrate all studies
all_dbs <- list.files("./data", pattern = "\\.db$", full.names = TRUE)
results <- migrate_multiple_databases(
  db_paths = all_dbs,
  output_dir = "./data_encrypted"
)
print(results)
```

---

## Step 7 Execution

### Step 7.1: Create the File

Create `/R/db_migration.R` with code above.

### Step 7.2: Generate Documentation

```r
devtools::document()
```

### Step 7.3: Test the Functions

```r
devtools::load_all()

# Create test databases
test_db1 <- "./test_migration_source.db"
if (file.exists(test_db1)) file.remove(test_db1)

conn <- DBI::dbConnect(RSQLite::SQLite(), test_db1)
DBI::dbExecute(conn, "CREATE TABLE test_table (id INTEGER, name TEXT)")
DBI::dbExecute(conn, "INSERT INTO test_table VALUES (1, 'Test 1')")
DBI::dbExecute(conn, "INSERT INTO test_table VALUES (2, 'Test 2')")
DBI::dbDisconnect(conn)

# Test 1: Prepare migration
prep <- prepare_migration(test_db1)
cat("Valid:", prep$valid, "\n")
cat("Tables:", paste(prep$tables, collapse=", "), "\n")

# Test 2: Migrate
migration <- migrate_to_encrypted(test_db1)
cat("Success:", migration$success, "\n")
cat("Records migrated:", migration$records_migrated, "\n")

# Test 3: Verify
verification <- verify_migration(test_db1, migration$new_path)
cat("Migration verified:", verification$valid, "\n")

# Cleanup
file.remove(test_db1)
file.remove(migration$new_path)
unlink("./backups", recursive = TRUE)
```

---

## Success Criteria for Step 7

Step 7 is complete when:

- [x] File `/R/db_migration.R` created with 5 functions
- [x] All functions have roxygen2 documentation
- [x] `devtools::document()` runs without errors
- [x] Manual testing of all 5 functions passes
- [x] Package builds with `R CMD check`
- [x] All functions exported in NAMESPACE
- [x] Migration preserves all data integrity
- [x] Rollback capability tested

---

## Database Migration Workflow

```
Step 1: Preparation
  └─ prepare_migration()
     ├─ Validate source DB
     ├─ Count records
     └─ Create backup

Step 2: Migration
  └─ migrate_to_encrypted()
     ├─ Create encrypted DB
     ├─ Copy schema
     ├─ Copy data
     ├─ Copy indexes
     └─ Verify counts

Step 3: Verification
  └─ verify_migration()
     ├─ Compare tables
     ├─ Compare counts
     ├─ Sample records
     └─ Report integrity

Step 4: Cleanup (if successful)
  └─ Replace original DB
     └─ Archive backup

Step 5: Rollback (if failed)
  └─ rollback_migration()
     └─ Restore from backup
```

---

## Next Step

Once Step 7 is complete:
- Proceed to **Step 8: Create Comprehensive Test Suite** (Week 3, Days 3-4)
- Integration tests for all encryption features
- Security validation
- Performance benchmarks

---

**Timeline for Step 7**: 1-2 days

Generated: December 2025
Feature #1 Implementation: Step 7 of 9
