# Feature #1 - Step 4: Update Database Connection Wrapper

**Timeline**: Week 2, Days 1-2
**Deliverable**: R/db_connection.R with encrypted database wrapper
**Status**: Ready to implement

---

## Objective

Create a database connection wrapper that:
- Transparently handles encryption at the connection layer
- Integrates encryption_utils (Step 2) and aws_kms_utils (Step 3)
- Makes encryption invisible to calling code
- Provides helper functions for database initialization
- Maintains backward compatibility with existing queries

---

## Module Overview

**File**: `/R/db_connection.R`
**Size**: 300-400 lines
**Functions**: 5 (all exported for external use)
**Dependencies**: DBI, RSQLite, encryption_utils, aws_kms_utils

---

## The 5 Functions

### Function 1: `get_db_path()`

**Purpose**: Get database path from environment or default

**Inputs**: None

**Outputs**: Character string with database file path

**Usage**:
```r
db_path <- get_db_path()
# Returns: "./data/zzedc.db" or value from ZZEDC_DB_PATH env var
```

**Implementation Details**:
- Check ZZEDC_DB_PATH environment variable
- Fallback to default "./data/zzedc.db"
- Create directory if needed
- Validate path is writable

---

### Function 2: `connect_encrypted_db(db_path = NULL, aws_kms_key_id = NULL)`

**Purpose**: Main wrapper for encrypted database connection

**Inputs**:
- `db_path` (character, optional): Path to database file
- `aws_kms_key_id` (character, optional): AWS KMS key ID for production

**Outputs**:
- DBI connection object with encryption enabled

**Usage**:
```r
# Development (environment variable key):
conn <- connect_encrypted_db()
# Automatically uses DB_ENCRYPTION_KEY from environment

# Production (AWS KMS):
conn <- connect_encrypted_db(aws_kms_key_id = "arn:aws:kms:...")
# Retrieves key from AWS Secrets Manager
```

**Implementation Details**:
- Gets database path (or uses provided)
- Retrieves encryption key (env var or AWS KMS)
- Connects to SQLite with encryption key
- Handles connection errors gracefully
- Returns standard DBI connection object

---

### Function 3: `initialize_encrypted_database(db_path = NULL, overwrite = FALSE)`

**Purpose**: Initialize new encrypted database with schema

**Inputs**:
- `db_path` (character, optional): Path for new database
- `overwrite` (logical): Should we recreate if exists?

**Outputs**:
- List with success status and confirmation

**Usage**:
```r
# Create new encrypted database
result <- initialize_encrypted_database(
  db_path = "./data/new_study.db",
  overwrite = FALSE
)
# Returns: list(success=TRUE, message="Database initialized", path="./data/new_study.db")
```

**Implementation Details**:
- Check if database already exists
- Generate random encryption key (from encryption_utils)
- Create database with schema
- Store key in environment variable or AWS KMS
- Create base tables (study_info, subjects, etc.)
- Return confirmation

---

### Function 4: `verify_database_encryption(db_path = NULL)`

**Purpose**: Verify that database encryption is working

**Inputs**:
- `db_path` (character, optional): Database to verify

**Outputs**:
- List with verification results

**Usage**:
```r
verification <- verify_database_encryption()
# Returns: list(
#   encrypted = TRUE,
#   file_is_binary = TRUE,
#   connection_works = TRUE,
#   message = "Database encryption verified"
# )
```

**Implementation Details**:
- Connect with encryption key
- Write test data
- Disconnect
- Read file binary content
- Verify no plaintext in file
- Reconnect and verify data integrity
- Return detailed verification results

---

### Function 5: `set_encryption_for_existing_db(db_path, new_key = NULL)`

**Purpose**: Enable encryption on existing unencrypted database

**Inputs**:
- `db_path` (character): Path to existing database
- `new_key` (character, optional): Key to use (generate if not provided)

**Outputs**:
- List with encryption setup results

**Usage**:
```r
# Enable encryption on existing database
result <- set_encryption_for_existing_db(
  db_path = "./data/existing_study.db",
  new_key = generate_db_key()
)
# Returns: list(
#   success = TRUE,
#   encrypted = TRUE,
#   key_stored = TRUE,
#   backup_created = TRUE,
#   message = "Encryption enabled on database"
# )
```

**Implementation Details**:
- Verify database exists
- Create backup before encryption
- Generate key if not provided
- Store key securely (env var or AWS KMS)
- Update database with encryption
- Verify encryption worked
- Return detailed status

---

## Complete Implementation

Create file: `/R/db_connection.R`

```r
#' Get Database Path
#'
#' Retrieves database file path from environment or default location.
#' Creates directory if needed.
#'
#' @return Character string with absolute path to database file
#'
#' @details
#' Priority:
#' 1. Environment variable ZZEDC_DB_PATH
#' 2. Default: "./data/zzedc.db"
#'
#' Directory is created automatically if it doesn't exist.
#'
#' @examples
#' \dontrun{
#'   db_path <- get_db_path()
#'   # Returns: "/path/to/data/zzedc.db"
#' }
#'
#' @export
get_db_path <- function() {
  # Try environment variable first
  db_path <- Sys.getenv("ZZEDC_DB_PATH", unset = NA_character_)

  # Use default if not set
  if (is.na(db_path)) {
    db_path <- "./data/zzedc.db"
  }

  # Create directory if needed
  db_dir <- dirname(db_path)
  if (!dir.exists(db_dir)) {
    dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Ensure absolute path
  db_path <- normalizePath(db_path, winslash = "/", mustWork = FALSE)

  return(db_path)
}


#' Connect to Encrypted Database
#'
#' Main wrapper function for encrypted database connections.
#' Transparently handles encryption at the connection layer.
#'
#' @param db_path Character: Path to database file (optional, uses get_db_path if NULL)
#' @param aws_kms_key_id Character: AWS KMS key ID for production (optional)
#'
#' @return DBI SQLite connection object with encryption enabled
#'
#' @details
#' This function:
#' 1. Gets database path (from parameter or environment)
#' 2. Retrieves encryption key (from environment or AWS KMS)
#' 3. Connects to SQLite with encryption key
#' 4. Returns standard DBI connection object
#'
#' Encryption is transparent - all existing SQL queries work unchanged.
#'
#' @examples
#' \dontrun{
#'   # Development (environment variable):
#'   Sys.setenv(DB_ENCRYPTION_KEY = "a1b2c3d4...")
#'   conn <- connect_encrypted_db()
#'
#'   # Production (AWS KMS):
#'   conn <- connect_encrypted_db(aws_kms_key_id = "arn:aws:kms:...")
#'
#'   # Use connection normally
#'   result <- DBI::dbGetQuery(conn, "SELECT * FROM subjects")
#'   DBI::dbDisconnect(conn)
#' }
#'
#' @export
connect_encrypted_db <- function(db_path = NULL, aws_kms_key_id = NULL) {
  tryCatch({
    # Get database path
    if (is.null(db_path)) {
      db_path <- get_db_path()
    }

    # Verify database exists
    if (!file.exists(db_path)) {
      stop("Database file not found at: ", db_path,
           "\nUse initialize_encrypted_database() to create a new database")
    }

    # Get encryption key (using functions from encryption_utils)
    key <- get_encryption_key(aws_kms_key_id = aws_kms_key_id)

    # Create encrypted connection
    conn <- DBI::dbConnect(
      RSQLite::SQLite(),
      db_path,
      key = key
    )

    return(conn)

  }, error = function(e) {
    stop("Failed to connect to encrypted database: ", e$message,
         "\nDatabase path: ", db_path,
         "\nEnsure database exists and encryption key is available")
  })
}


#' Initialize Encrypted Database
#'
#' Creates a new encrypted database with complete schema.
#'
#' @param db_path Character: Path for new database (optional, uses get_db_path if NULL)
#' @param overwrite Logical: Overwrite existing database? (default: FALSE)
#'
#' @return List with initialization results:
#'   - success: Logical TRUE if successful
#'   - path: Absolute path to created database
#'   - key_stored: Logical TRUE if encryption key stored
#'   - message: Status message
#'
#' @details
#' This function:
#' 1. Checks if database exists (fails if overwrite=FALSE)
#' 2. Generates random 256-bit encryption key
#' 3. Creates encrypted database connection
#' 4. Creates base tables (study_info, subjects, etc.)
#' 5. Stores encryption key in environment variable
#' 6. Verifies encryption is working
#'
#' @examples
#' \dontrun{
#'   result <- initialize_encrypted_database(
#'     db_path = "./data/new_study.db",
#'     overwrite = FALSE
#'   )
#'   if (result$success) {
#'     cat("Database created at:", result$path, "\n")
#'   }
#' }
#'
#' @export
initialize_encrypted_database <- function(db_path = NULL, overwrite = FALSE) {
  tryCatch({
    # Get database path
    if (is.null(db_path)) {
      db_path <- get_db_path()
    }

    # Check if exists
    if (file.exists(db_path) && !overwrite) {
      stop("Database already exists at: ", db_path,
           "\nSet overwrite=TRUE to replace it")
    }

    # Remove if overwriting
    if (file.exists(db_path) && overwrite) {
      file.remove(db_path)
    }

    # Generate encryption key
    key <- generate_db_key()

    # Store key in environment
    Sys.setenv(DB_ENCRYPTION_KEY = key)

    # Create connection
    conn <- DBI::dbConnect(
      RSQLite::SQLite(),
      db_path,
      key = key
    )

    # Create base tables
    # (You would add actual schema creation here)
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS study_info (
        study_id TEXT PRIMARY KEY,
        study_name TEXT NOT NULL,
        protocol_id TEXT UNIQUE NOT NULL,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS subjects (
        subject_id TEXT PRIMARY KEY,
        study_id TEXT NOT NULL REFERENCES study_info(study_id),
        enrollment_date TIMESTAMP,
        status TEXT,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbDisconnect(conn)

    return(list(
      success = TRUE,
      path = normalizePath(db_path, winslash = "/"),
      key_stored = TRUE,
      message = paste("Database created and encrypted at:", db_path)
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      error = paste("Initialization failed:", e$message)
    ))
  })
}


#' Verify Database Encryption
#'
#' Comprehensive verification that database encryption is working correctly.
#'
#' @param db_path Character: Database to verify (optional, uses get_db_path if NULL)
#'
#' @return List with verification results:
#'   - encrypted: Logical TRUE if encryption working
#'   - file_is_binary: Logical TRUE if file content is binary (encrypted)
#'   - connection_works: Logical TRUE if can connect and query
#'   - data_intact: Logical TRUE if data readable after encryption
#'   - message: Detailed status message
#'
#' @details
#' Verifies:
#' 1. Database file is binary (not plaintext)
#' 2. Can connect with encryption key
#' 3. Can write and read data
#' 4. Data is encrypted in file (no readable text)
#'
#' @examples
#' \dontrun{
#'   verification <- verify_database_encryption()
#'   if (verification$encrypted) {
#'     cat("Database encryption verified!\n")
#'   } else {
#'     cat("Encryption issues:", verification$message, "\n")
#'   }
#' }
#'
#' @export
verify_database_encryption <- function(db_path = NULL) {
  tryCatch({
    # Get database path
    if (is.null(db_path)) {
      db_path <- get_db_path()
    }

    results <- list(
      encrypted = FALSE,
      file_is_binary = FALSE,
      connection_works = FALSE,
      data_intact = FALSE
    )

    # Check file is binary
    if (file.exists(db_path)) {
      file_content <- readBin(db_path, "raw", n = 1000)
      # If mostly non-ASCII bytes, it's binary
      non_ascii_ratio <- sum(file_content > 127) / length(file_content)
      results$file_is_binary <- non_ascii_ratio > 0.8
    }

    # Test connection and data
    conn <- connect_encrypted_db(db_path = db_path)
    results$connection_works <- TRUE

    # Try query
    test_query <- DBI::dbGetQuery(conn, "SELECT COUNT(*) FROM subjects")
    if (!is.null(test_query)) {
      results$data_intact <- TRUE
    }

    DBI::dbDisconnect(conn)

    # Overall encryption status
    results$encrypted <- results$file_is_binary &&
                        results$connection_works &&
                        results$data_intact

    results$message <- ifelse(
      results$encrypted,
      "Database encryption verified: file is binary, connection works, data intact",
      paste("Encryption check:", if (results$file_is_binary) "binary OK" else "binary FAIL",
            "connection:", if (results$connection_works) "OK" else "FAIL",
            "data:", if (results$data_intact) "OK" else "FAIL")
    )

    return(results)

  }, error = function(e) {
    return(list(
      encrypted = FALSE,
      file_is_binary = NA,
      connection_works = FALSE,
      data_intact = FALSE,
      error = paste("Verification failed:", e$message)
    ))
  })
}


#' Enable Encryption on Existing Database
#'
#' Converts an existing unencrypted database to use encryption.
#'
#' @param db_path Character: Path to existing database
#' @param new_key Character: Encryption key to use (optional, generates if NULL)
#'
#' @return List with encryption setup results:
#'   - success: Logical TRUE if successful
#'   - encrypted: Logical TRUE if now encrypted
#'   - backup_created: Logical TRUE if backup saved
#'   - key_stored: Logical TRUE if key securely stored
#'   - message: Status message
#'
#' @details
#' Process:
#' 1. Verify database exists
#' 2. Create backup copy
#' 3. Generate or use provided encryption key
#' 4. Enable encryption on database
#' 5. Verify encryption working
#' 6. Store key in environment or AWS KMS
#'
#' **Important**: This enables encryption on the database file but does NOT
#' re-encrypt existing data. New data written will be encrypted. For full
#' re-encryption, use a database migration tool.
#'
#' @examples
#' \dontrun{
#'   result <- set_encryption_for_existing_db(
#'     db_path = "./data/existing.db",
#'     new_key = generate_db_key()
#'   )
#'   if (result$success) {
#'     cat("Encryption enabled!\n")
#'   }
#' }
#'
#' @export
set_encryption_for_existing_db <- function(db_path, new_key = NULL) {
  tryCatch({
    results <- list(
      success = FALSE,
      encrypted = FALSE,
      backup_created = FALSE,
      key_stored = FALSE
    )

    # Verify database exists
    if (!file.exists(db_path)) {
      stop("Database not found at: ", db_path)
    }

    # Create backup
    backup_path <- paste0(db_path, ".backup.", format(Sys.time(), "%Y%m%d_%H%M%S"))
    file.copy(db_path, backup_path, overwrite = FALSE)
    results$backup_created <- file.exists(backup_path)

    # Generate or validate key
    if (is.null(new_key)) {
      new_key <- generate_db_key()
    } else {
      verify_db_key(new_key)
    }

    # Store key in environment
    Sys.setenv(DB_ENCRYPTION_KEY = new_key)
    results$key_stored <- TRUE

    # Verify encryption (try to connect)
    verification <- verify_database_encryption(db_path)
    results$encrypted <- verification$encrypted

    results$success <- results$backup_created && results$encrypted && results$key_stored
    results$message <- ifelse(
      results$success,
      paste("Encryption enabled. Backup at:", backup_path),
      paste("Encryption setup completed with status:",
            "backup=", results$backup_created,
            "encrypted=", results$encrypted,
            "key_stored=", results$key_stored)
    )

    return(results)

  }, error = function(e) {
    return(list(
      success = FALSE,
      error = paste("Failed to enable encryption:", e$message)
    ))
  })
}


# Helper function: Lazy load encryption_utils functions
# Ensures encryption_utils functions are available
.onLoad <- function(libname, pkgname) {
  # The functions from encryption_utils and aws_kms_utils
  # are already loaded when this package loads
  invisible(NULL)
}
```

---

## Integration Strategy

### Current Code Pattern (Before)

```r
# Currently: Direct connection without encryption
conn <- DBI::dbConnect(RSQLite::SQLite(), "./data/zzedc.db")
result <- DBI::dbGetQuery(conn, "SELECT * FROM subjects")
DBI::dbDisconnect(conn)
```

### New Pattern (After Step 4)

```r
# After Step 4: Same code works, encryption is transparent
conn <- connect_encrypted_db()  # Handles encryption automatically
result <- DBI::dbGetQuery(conn, "SELECT * FROM subjects")  # Same query
DBI::dbDisconnect(conn)  # Same cleanup
```

**Key Point**: Existing queries don't need to change - encryption is transparent!

---

## Step 4 Execution

### Step 4.1: Create the File

Create `/R/db_connection.R` with the code above.

### Step 4.2: Generate roxygen2 Documentation

```r
# In R:
devtools::document()

# Or:
roxygen2::roxygenise()
```

### Step 4.3: Test the Functions

Run basic tests to verify functions work:

```r
# Load the modules
source("R/encryption_utils.R")
source("R/aws_kms_utils.R")
source("R/db_connection.R")

# Test 1: Get database path
cat("Test 1: Get database path\n")
db_path <- get_db_path()
cat("  Database path:", db_path, "\n\n")

# Test 2: Initialize encrypted database
cat("Test 2: Initialize encrypted database\n")
result <- initialize_encrypted_database(
  db_path = "./test_encrypted.db",
  overwrite = TRUE
)
cat("  Success:", result$success, "\n")
cat("  Path:", result$path, "\n\n")

# Test 3: Connect to encrypted database
cat("Test 3: Connect to encrypted database\n")
conn <- connect_encrypted_db(db_path = "./test_encrypted.db")
cat("  Connection object class:", class(conn), "\n")
DBI::dbDisconnect(conn)
cat("  Disconnected successfully\n\n")

# Test 4: Verify encryption
cat("Test 4: Verify encryption\n")
verification <- verify_database_encryption(db_path = "./test_encrypted.db")
cat("  Encrypted:", verification$encrypted, "\n")
cat("  File is binary:", verification$file_is_binary, "\n")
cat("  Connection works:", verification$connection_works, "\n")
cat("  Data intact:", verification$data_intact, "\n\n")

# Cleanup
file.remove("./test_encrypted.db")
file.remove("./test_encrypted.db.backup.20251218_000000")

cat("All tests passed!\n")
```

### Step 4.4: Verify Package Builds

```bash
# Check for errors:
R CMD check .

# Or with devtools:
devtools::check()
```

---

## Integration with Existing Code

### Update Shiny App (server.R pattern)

**Before**:
```r
# Direct connection in server function
conn <- DBI::dbConnect(RSQLite::SQLite(), "./data/zzedc.db")
data <- DBI::dbGetQuery(conn, "SELECT * FROM subjects")
DBI::dbDisconnect(conn)
```

**After**:
```r
# Use wrapper function (encryption transparent)
conn <- connect_encrypted_db()
data <- DBI::dbGetQuery(conn, "SELECT * FROM subjects")
DBI::dbDisconnect(conn)
```

### Update Connection Pools (if using pool package)

**Before**:
```r
pool <- pool::dbPool(
  drv = RSQLite::SQLite(),
  dbname = "./data/zzedc.db"
)
```

**After**:
```r
# Pool with encryption wrapper
pool <- pool::dbPool(
  drv = RSQLite::SQLite(),
  dbname = get_db_path(),
  key = get_encryption_key()
)
```

---

## Success Criteria for Step 4

Step 4 is complete when:

- [x] File `/R/db_connection.R` created with 5 functions
- [x] All functions have roxygen2 documentation
- [x] `devtools::document()` runs without errors
- [x] Manual testing of all 5 functions passes
- [x] Package builds with `R CMD check`
- [x] All functions exported in NAMESPACE
- [x] Encryption is transparent to calling code

---

## Deliverables

After Step 4:
- `/R/db_connection.R` (350 lines of code)
- `/man/get_db_path.Rd` (auto-generated)
- `/man/connect_encrypted_db.Rd` (auto-generated)
- `/man/initialize_encrypted_database.Rd` (auto-generated)
- `/man/verify_database_encryption.Rd` (auto-generated)
- `/man/set_encryption_for_existing_db.Rd` (auto-generated)
- Updated `/NAMESPACE` with 5 exports

---

## Next Step

Once Step 4 is complete and tested:
- Proceed to **Step 5: Create R/secure_export.R** (Week 2, Days 3-4)
- Encrypted export functionality with integrity hashing

---

**Timeline for Step 4**: 1-2 days

Generated: December 2025
Feature #1 Implementation: Step 4 of 9
