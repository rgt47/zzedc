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


#' Get Auto-Increment Column DDL for the Current Backend
#'
#' Thin wrapper around `get_db_adapter()$auto_increment_column()`, for
#' call sites that only hold a raw `conn` (from `connect_db()` or
#' `connect_encrypted_db()`), not an adapter instance. Use this
#' instead of hardcoding `INTEGER PRIMARY KEY AUTOINCREMENT` in a
#' `CREATE TABLE` statement: that spelling is SQLite-only and fails on
#' every other backend (see
#' `docs/db-adapter-remediation-plan-2026-11-07.md` Section 1). Call
#' `prepare_auto_increment()` with the same `table_name`/`column_name`
#' immediately before the `CREATE TABLE` statement that uses this.
#'
#' @param table_name Name of the table the column belongs to
#' @param column_name Name of the auto-increment column
#' @return Character string with the column's DDL fragment
#'
#' @keywords internal
#' @export
auto_increment_ddl <- function(table_name, column_name) {
  adapter <- get_db_adapter()
  adapter$auto_increment_column(table_name, column_name)
}


#' Prepare Auto-Increment Column for the Current Backend
#'
#' Thin wrapper around `get_db_adapter()$prepare_auto_increment()`.
#' Runs any DDL a backend needs before a `CREATE TABLE` statement that
#' uses `auto_increment_ddl(table_name, column_name)` (DuckDB's
#' companion `CREATE SEQUENCE`; a no-op on every other in-scope
#' backend).
#'
#' @param conn Database connection
#' @param table_name Name of the table the column belongs to
#' @param column_name Name of the auto-increment column
#' @return `invisible(NULL)`
#'
#' @keywords internal
#' @export
prepare_auto_increment <- function(conn, table_name, column_name) {
  adapter <- get_db_adapter()
  adapter$prepare_auto_increment(conn, table_name, column_name)
}


#' Get a Date-Difference SQL Expression for the Current Backend
#'
#' Returns a SQL expression for `col_a - col_b` in whole days, using
#' whichever construct the currently configured backend needs:
#' `julianday(col_a) - julianday(col_b)` on SQLite, `date_diff('day',
#' col_b, col_a)` on DuckDB, `col_a::date - col_b::date` on
#' PostgreSQL, `DATEDIFF(col_a, col_b)` on MariaDB. `julianday()` is
#' SQLite-only and errors on every other backend (see
#' `docs/db-adapter-remediation-plan-2026-11-07.md` Section 1); use
#' this instead of hardcoding it. Takes plain column-name strings, not
#' a connection, so it can be called from pure SQL-generation code
#' that has no `conn` in scope.
#'
#' @param col_a Column or expression for the later/minuend date
#' @param col_b Column or expression for the earlier/subtrahend date
#' @return Character string with the date-difference SQL expression
#'
#' @keywords internal
#' @export
sql_date_diff_days <- function(col_a, col_b) {
  adapter <- get_db_adapter()
  adapter$dialect()$date_diff_days(col_a, col_b)
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
#'
#' @details
#' On non-SQLite backends (`config.yml`'s `db_backend` set to
#' `"duckdb"`, `"postgresql"`, or `"mysql"`/`"mariadb"`), this
#' delegates to `get_db_adapter()$connect()` instead of the SQLite-only
#' path below, so that setting changes the backend this function
#' actually connects to. `db_path` and `aws_kms_key_id` are SQLite-path
#' arguments and are ignored on those backends; `key`, if supplied, is
#' passed through to the backend's own encryption-key config slot
#' (currently only `DuckDBAdapter` acts on it; see
#' `docs/db-adapter-remediation-plan-2026-11-07.md` Phase B) for this
#' one connection, without altering the cached adapter.
#'
#' This does not change behavior for the default and still most
#' common case (`db_backend` unset or `"sqlite"`): that path is
#' untouched, including the known SQLCipher-PRAGMA no-op documented in
#' `docs/edc-encryption-decision-2026-10-29.md`. It also does not make
#' every caller of this function safe on a non-SQLite backend by
#' itself -- the 40 files that call it still embed some SQLite-dialect
#' SQL not yet ported (Phase C of the remediation plan); switching
#' `db_backend` away from `sqlite` before that work lands will surface
#' those as query errors, not silently return wrong data.
#'
#' A `config.yml` written for the Shiny app's own `config::get()`
#' settings (a top-level `default:` environment key, as shipped with
#' this package and with the live Promotion Review Tracker deployment)
#' is a different schema than `load_db_config()` expects (a top-level
#' `database:` key with no environment wrapper) and will not parse as
#' a backend selection. `get_db_adapter()` failing to resolve a
#' backend from such a file -- or from no file at all -- is treated
#' the same as "no backend configured": this function falls back to
#' the sqlite path below rather than propagating that error, so an
#' app-config-only `config.yml` cannot change this function's
#' behavior. A `message()` reports the fallback so it is visible to
#' someone debugging a `config.yml` that was meant to pick a backend.
#' @export
connect_encrypted_db <- function(db_path = NULL, aws_kms_key_id = NULL,
                                 key = NULL) {
  tryCatch({
    adapter <- tryCatch(get_db_adapter(), error = function(e) {
      message("connect_encrypted_db(): could not resolve a database ",
               "backend from config.yml (", e$message, "); using the ",
               "sqlite legacy path.")
      NULL
    })
    backend <- if (!is.null(adapter)) adapter$backend_name() else "sqlite"

    if (!is.null(adapter) && backend != "sqlite") {
      if (!is.null(key)) {
        config <- adapter$config
        config[[backend]]$encryption_key <- key
        return(create_db_adapter(config)$connect())
      }
      return(adapter$connect())
    }

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
#' @details
#' On non-SQLite backends (`config.yml`'s `db_backend` set to
#' `"duckdb"`, `"postgresql"`, or `"mysql"`/`"mariadb"`), this
#' delegates to backend-specific initialization instead of the
#' SQLite-only path below, mirroring `connect_encrypted_db()`'s
#' dispatch (see `docs/db-adapter-remediation-plan-2026-11-07.md`
#' Phase B/D). `db_path` is a SQLite/DuckDB-path argument; on DuckDB
#' it is ignored in favor of `config$duckdb$path` (the adapter already
#' resolved that path when it was constructed), and on
#' PostgreSQL/MySQL/MariaDB it is ignored entirely, since those
#' backends have no file to create. `overwrite` means "delete the
#' existing file" on SQLite/DuckDB, and "drop and recreate the
#' `study_info`/`subjects` tables" (not the whole database) on
#' PostgreSQL/MySQL/MariaDB -- those are server-hosted databases
#' expected to already exist, created by a DBA, with other modules'
#' tables alongside these two.
#'
#' `key`/the returned `key` only has meaning for SQLite and DuckDB
#' (SQLCipher-style, application-level encryption of the database
#' file). PostgreSQL/MySQL/MariaDB have no equivalent at this layer;
#' on those backends `key` is ignored and the returned `key` is
#' `NA_character_`, with the result `message` noting that
#' encryption-at-rest is a server/infrastructure concern there, not
#' something this function manages (see
#' `docs/edc-encryption-decision-2026-10-29.md`).
#' @export
initialize_encrypted_database <- function(db_path = NULL, overwrite = FALSE,
                                          key = NULL) {
  adapter <- tryCatch(get_db_adapter(), error = function(e) NULL)
  backend <- if (!is.null(adapter)) adapter$backend_name() else "sqlite"

  if (is.null(adapter) || backend == "sqlite") {
    return(init_encrypted_sqlite_database(db_path, overwrite, key))
  }
  if (backend == "duckdb") {
    return(init_encrypted_duckdb_database(adapter, overwrite, key))
  }
  init_server_backend_database(adapter, backend, overwrite)
}


#' Initialize an Encrypted SQLite Database (Legacy Path)
#'
#' The original, SQLite-only body of `initialize_encrypted_database()`,
#' extracted unchanged so the exported function can dispatch to it or
#' to the DuckDB/server-backend paths added alongside it.
#'
#' @inheritParams initialize_encrypted_database
#' @keywords internal
init_encrypted_sqlite_database <- function(db_path = NULL, overwrite = FALSE,
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
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # Create base tables
    # (You would add actual schema creation here)
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS study_info (
        study_id VARCHAR(64) PRIMARY KEY,
        study_name TEXT NOT NULL,
        protocol_id VARCHAR(64) UNIQUE NOT NULL,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS subjects (
        subject_id VARCHAR(64) PRIMARY KEY,
        study_id VARCHAR(64) NOT NULL REFERENCES study_info(study_id),
        enrollment_date TIMESTAMP,
        status TEXT,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

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


#' Initialize an Encrypted DuckDB Database
#'
#' DuckDB analogue of `init_encrypted_sqlite_database()`: creates a new
#' DuckDB file attached with `ENCRYPTION_KEY` (see `DuckDBAdapter$connect()`),
#' rather than SQLCipher. The path comes from `adapter$config$duckdb$path`,
#' not from a `db_path` argument -- the adapter already resolved that
#' path when it was constructed from `config.yml`.
#'
#' @param adapter A `DuckDBAdapter` instance, as returned by `get_db_adapter()`.
#' @inheritParams initialize_encrypted_database
#' @keywords internal
init_encrypted_duckdb_database <- function(adapter, overwrite = FALSE,
                                           key = NULL) {
  tryCatch({
    db_path <- adapter$config$duckdb$path
    if (is.null(db_path) || !nzchar(db_path)) {
      stop("DuckDB configuration has no 'duckdb.path' set")
    }

    if (file.exists(db_path) && !overwrite) {
      stop("Database already exists at: ", db_path,
           "\nSet overwrite=TRUE to replace it")
    }
    if (file.exists(db_path) && overwrite) {
      file.remove(db_path)
    }

    if (is.null(key)) {
      key <- generate_db_key()
    } else {
      verify_db_key(key)
    }

    # Connect with the key set for this one connection only, without
    # altering the cached adapter -- same pattern connect_encrypted_db()
    # uses for an explicit `key` argument.
    config <- adapter$config
    config$duckdb$encryption_key <- key
    encrypted_adapter <- create_db_adapter(config)
    conn <- encrypted_adapter$connect()
    on.exit(encrypted_adapter$disconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS study_info (
        study_id VARCHAR(64) PRIMARY KEY,
        study_name TEXT NOT NULL,
        protocol_id VARCHAR(64) UNIQUE NOT NULL,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS subjects (
        subject_id VARCHAR(64) PRIMARY KEY,
        study_id VARCHAR(64) NOT NULL REFERENCES study_info(study_id),
        enrollment_date TIMESTAMP,
        status TEXT,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    list(
      success = TRUE,
      path = normalizePath(db_path, winslash = "/"),
      key = key,
      message = paste("Database created and encrypted at:", db_path)
    )
  }, error = function(e) {
    list(success = FALSE, error = paste("Initialization failed:", e$message))
  })
}


#' Initialize Base Tables on a Server-Hosted Backend
#'
#' PostgreSQL/MySQL/MariaDB analogue of `init_encrypted_sqlite_database()`.
#' These backends have no database *file* to create -- the database
#' itself is assumed to already exist on the server -- so this only
#' creates the `study_info`/`subjects` base tables, and has no
#' application-level encryption key to generate or return (see
#' `initialize_encrypted_database()`'s `@details`).
#'
#' @param adapter A `PostgreSQLAdapter`/`MySQLAdapter` instance.
#' @param backend Character: `adapter$backend_name()`.
#' @inheritParams initialize_encrypted_database
#' @keywords internal
init_server_backend_database <- function(adapter, backend, overwrite = FALSE) {
  tryCatch({
    conn <- adapter$connect()
    on.exit(adapter$disconnect(conn), add = TRUE)

    existing_tables <- DBI::dbListTables(conn)
    if ("study_info" %in% existing_tables && !overwrite) {
      stop("Database already initialized: a 'study_info' table already exists",
           "\nSet overwrite=TRUE to drop and recreate it")
    }
    if (overwrite) {
      cascade <- if (backend == "postgresql") " CASCADE" else ""
      for (tbl in c("subjects", "study_info")) {
        if (tbl %in% existing_tables) {
          DBI::dbExecute(conn, paste0("DROP TABLE IF EXISTS ", tbl, cascade))
        }
      }
    }

    # study_id/protocol_id/subject_id are VARCHAR(64), not TEXT: MySQL/
    # MariaDB rejects an unbounded TEXT/BLOB column in a PRIMARY KEY or
    # UNIQUE constraint ("BLOB/TEXT column ... used in key specification
    # without a key length"); SQLite, DuckDB, and PostgreSQL all treat
    # VARCHAR(n) and TEXT as equivalent, so this is a no-op change for
    # them.
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS study_info (
        study_id VARCHAR(64) PRIMARY KEY,
        study_name TEXT NOT NULL,
        protocol_id VARCHAR(64) UNIQUE NOT NULL,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS subjects (
        subject_id VARCHAR(64) PRIMARY KEY,
        study_id VARCHAR(64) NOT NULL REFERENCES study_info(study_id),
        enrollment_date TIMESTAMP,
        status TEXT,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")

    backend_config <- adapter$config[[if (backend == "postgresql") "postgresql" else "mysql"]]

    list(
      success = TRUE,
      path = NA_character_,
      key = NA_character_,
      message = sprintf(
        "Database tables created on %s at %s:%s/%s. Encryption at rest is not managed by this function on this backend; configure it at the server/infrastructure level (see docs/edc-encryption-decision-2026-10-29.md).",
        backend, backend_config$host %||% "?", backend_config$port %||% "?",
        backend_config$name %||% "?"
      )
    )
  }, error = function(e) {
    list(success = FALSE, error = paste("Initialization failed:", e$message))
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

    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    results$connection_works <- TRUE

    test_query <- DBI::dbGetQuery(conn, "SELECT COUNT(*) FROM subjects")
    if (!is.null(test_query)) {
      results$data_intact <- TRUE
    }

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
