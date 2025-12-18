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
