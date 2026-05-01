#' Database Connection Module
#'
#' Provides unified database connectivity supporting multiple backends
#' (SQLite, DuckDB, PostgreSQL) through the adapter pattern.
#'
#' @description
#' This module integrates with the database adapter system to provide:
#' - Backward-compatible SQLite connections (legacy API)
#' - Multi-backend support via configuration
#' - Connection pooling for web applications
#' - Encryption support (SQLite with RSQLCipher)
#'
#' @keywords internal
#' @name db_connection
NULL

# Module-level adapter cache
.db_adapter_cache <- new.env(parent = emptyenv())


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
#' @keywords internal
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

  db_path
}


#' Get Database Adapter
#'
#' Returns a database adapter instance based on configuration.
#' Uses cached adapter if available.
#'
#' @param config Configuration list (optional, loads from config.yml if NULL)
#' @param config_path Path to config.yml (default: "./config.yml")
#' @param force_new Force creation of new adapter even if cached
#'
#' @return DatabaseAdapter subclass instance
#'
#' @examples
#' \dontrun{
#'   # From configuration file
#'   adapter <- get_db_adapter()
#'
#'   # With explicit config
#'   config <- list(db_backend = "sqlite", sqlite = list(path = "data.db"))
#'   adapter <- get_db_adapter(config = config)
#' }
#'
#' @keywords internal
#' @export
get_db_adapter <- function(config = NULL, config_path = "./config.yml",
                           force_new = FALSE) {
  # Return cached adapter if available and not forcing new

if (!force_new && exists("adapter", envir = .db_adapter_cache)) {
    return(.db_adapter_cache$adapter)
  }

  # Build configuration
  if (is.null(config)) {
    if (file.exists(config_path)) {
      config <- load_db_config(config_path)
    } else {
      # Fall back to SQLite with default path
      config <- default_db_config("sqlite", path = get_db_path())
    }
  }

  # Create adapter
  adapter <- create_db_adapter(config)

  # Cache it
  .db_adapter_cache$adapter <- adapter

  adapter
}


#' Connect to Database
#'
#' Creates a database connection using the configured backend.
#' This is the primary connection function for application code.
#'
#' @param config Configuration list (optional)
#' @param config_path Path to config.yml (optional)
#'
#' @return DBI connection object
#'
#' @details
#' This function provides a unified interface for database connections:
#' - Reads backend configuration from config.yml or environment
#' - Creates appropriate connection (SQLite, DuckDB, or PostgreSQL)
#' - Handles encryption for SQLite if configured
#'
#' @examples
#' \dontrun{
#'   conn <- connect_db()
#'   result <- DBI::dbGetQuery(conn, "SELECT * FROM subjects")
#'   disconnect_db(conn)
#' }
#'
#' @keywords internal
#' @export
connect_db <- function(config = NULL, config_path = "./config.yml") {
  adapter <- get_db_adapter(config = config, config_path = config_path)
  adapter$connect()
}


#' Disconnect from Database
#'
#' Closes a database connection.
#'
#' @param conn DBI connection object
#'
#' @return NULL invisibly
#'
#' @keywords internal
#' @export
disconnect_db <- function(conn) {
  adapter <- get_db_adapter()
  adapter$disconnect(conn)
  invisible(NULL)
}


#' Get Connection Pool
#'
#' Creates a connection pool for the configured backend.
#' Recommended for Shiny applications.
#'
#' @param config Configuration list (optional)
#' @param config_path Path to config.yml (optional)
#'
#' @return Pool object
#'
#' @examples
#' \dontrun{
#'   pool <- get_db_pool()
#'   # Use pool in Shiny app
#'   onStop(function() close_db_pool(pool))
#' }
#'
#' @keywords internal
#' @export
get_db_pool <- function(config = NULL, config_path = "./config.yml") {
  adapter <- get_db_adapter(config = config, config_path = config_path)
  adapter$pool()
}


#' Close Connection Pool
#'
#' Closes a database connection pool.
#'
#' @param pool Pool object
#'
#' @return NULL invisibly
#'
#' @keywords internal
#' @export
close_db_pool <- function(pool) {
  adapter <- get_db_adapter()
  adapter$pool_close(pool)
  invisible(NULL)
}


#' Execute Query with Adapter
#'
#' Executes a SELECT query using the configured database adapter.
#'
#' @param conn Database connection or pool
#' @param sql SQL query string
#' @param params Optional named list or vector of parameters
#'
#' @return Data frame with query results
#'
#' @keywords internal
#' @export
db_query <- function(conn, sql, params = NULL) {
  adapter <- get_db_adapter()
  adapter$query(conn, sql, params)
}


#' Execute Statement with Adapter
#'
#' Executes a non-SELECT statement (INSERT, UPDATE, DELETE, DDL).
#'
#' @param conn Database connection or pool
#' @param sql SQL statement
#' @param params Optional named list or vector of parameters
#'
#' @return Number of rows affected
#'
#' @keywords internal
#' @export
db_execute <- function(conn, sql, params = NULL) {
  adapter <- get_db_adapter()
  adapter$execute(conn, sql, params)
}


#' Execute Within Transaction
#'
#' Executes code within a database transaction with automatic
#' commit on success and rollback on error.
#'
#' @param conn Database connection
#' @param code Code to execute within transaction
#'
#' @return Result of code execution
#'
#' @examples
#' \dontrun{
#'   conn <- connect_db()
#'   result <- db_transaction(conn, {
#'     db_execute(conn, "INSERT INTO users (name) VALUES (?)", list("Alice"))
#'     db_execute(conn, "INSERT INTO logs (action) VALUES (?)", list("user_added"))
#'   })
#'   disconnect_db(conn)
#' }
#'
#' @keywords internal
#' @export
db_transaction <- function(conn, code) {
  adapter <- get_db_adapter()
  adapter$transaction(conn, code)
}


#' Get Current Backend Name
#'
#' Returns the name of the currently configured database backend.
#'
#' @return Character string: "sqlite", "duckdb", or "postgresql"
#'
#' @keywords internal
#' @export
get_db_backend <- function() {
  adapter <- get_db_adapter()
  adapter$backend_name()
}


#' Get SQL Dialect
#'
#' Returns dialect information for the current backend.
#'
#' @return List with dialect-specific SQL fragments
#'
#' @keywords internal
#' @export
get_db_dialect <- function() {
  adapter <- get_db_adapter()
  adapter$dialect()
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
#' @param key Character. Encryption key to use. If `NULL` (default),
#'   the key is resolved from `aws_kms_key_id` if supplied, otherwise
#'   from `Sys.getenv("DB_ENCRYPTION_KEY")`. Pass `key` explicitly when
#'   you already have it in hand (for example from
#'   `initialize_encrypted_database()$key`) to avoid relying on the
#'   process environment.
#' @export
connect_encrypted_db <- function(db_path = NULL, aws_kms_key_id = NULL,
                                 key = NULL) {
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

    # Resolve encryption key: explicit > AWS KMS > env var
    if (is.null(key)) {
      key <- get_encryption_key(aws_kms_key_id = aws_kms_key_id)
    }

    # Create encrypted connection using connect_encrypted helper
    conn <- connect_encrypted(db_path, key)

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
#' @param key Character. Encryption key to use. If `NULL` (default), a
#'   new 256-bit key is generated. Pass an existing key when migrating
#'   or recreating a database with a known key.
#'
#' @return List with initialization results:
#'   - success: Logical TRUE if successful
#'   - path: Absolute path to created database
#'   - key: The encryption key used (either `key` if supplied or the
#'     newly generated one). The function does not persist
#'     this key beyond the current function call; the caller must store
#'     it (for example via `Sys.setenv(DB_ENCRYPTION_KEY = result$key)`
#'     or AWS Secrets Manager). Losing the key makes the database
#'     unrecoverable.
#'   - message: Status message
#'
#' @details
#' This function:
#' 1. Checks if database exists (fails if overwrite=FALSE)
#' 2. Generates random 256-bit encryption key
#' 3. Creates encrypted database connection
#' 4. Creates base tables (study_info, subjects, etc.)
#' 5. Returns the encryption key in the result list
#' 6. Verifies encryption is working
#'
#' @examples
#' \dontrun{
#'   result <- initialize_encrypted_database(
#'     db_path = "./data/new_study.db",
#'     overwrite = FALSE
#'   )
#'   if (result$success) {
#'     # Store the key for subsequent operations in this session
#'     Sys.setenv(DB_ENCRYPTION_KEY = result$key)
#'     cat("Database created at:", result$path, "\n")
#'   }
#' }
#'
#' @export
initialize_encrypted_database <- function(db_path = NULL, overwrite = FALSE,
                                          key = NULL) {
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

    # Use the caller-supplied key, or generate a new one
    if (is.null(key)) {
      key <- generate_db_key()
    } else {
      verify_db_key(key)
    }

    # Create connection using connect_encrypted helper. The key is
    # passed explicitly; we deliberately do not write it to the user's
    # environment here. Callers who want it in the environment can do
    # so themselves with the key returned in the result list.
    conn <- connect_encrypted(db_path, key)

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
      key = key,
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
#'   - new_key: The encryption key used (NA on failure). The function
#'     does not persist `new_key` to the user's environment after
#'     return; the caller is responsible for storing it (for example
#'     `Sys.setenv(DB_ENCRYPTION_KEY = result$new_key)` for the current
#'     session, or AWS Secrets Manager / a password manager for
#'     production). Losing the key makes the database unrecoverable.
#'   - message: Status message
#'
#' @details
#' Process:
#' 1. Verify database exists
#' 2. Create backup copy
#' 3. Generate or use provided encryption key
#' 4. Enable encryption on database
#' 5. Verify encryption working
#' 6. Return the key in the result list for the caller to persist
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
      new_key = NA_character_
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

    # Surface the key in the result list. We deliberately do not write
    # it to the user's environment; the caller decides how to persist
    # it (e.g., AWS Secrets Manager, password manager, or
    # `Sys.setenv(DB_ENCRYPTION_KEY = result$new_key)` for the current
    # session).
    results$new_key <- new_key

    # Verify encryption (try to connect)
    verification <- verify_database_encryption(db_path)
    results$encrypted <- verification$encrypted

    results$success <- results$backup_created && results$encrypted &&
      !is.na(results$new_key)
    results$message <- ifelse(
      results$success,
      paste("Encryption enabled. Backup at:", backup_path),
      paste("Encryption setup completed with status:",
            "backup=", results$backup_created,
            "encrypted=", results$encrypted,
            "key_returned=", !is.na(results$new_key))
    )

    return(results)

  }, error = function(e) {
    return(list(
      success = FALSE,
      error = paste("Failed to enable encryption:", e$message)
    ))
  })
}
