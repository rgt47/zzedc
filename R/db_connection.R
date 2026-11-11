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

  # Use default if not set; an empty value is treated as unset, since
  # dirname("") would make dir.create() fail with a zero-length path.
  if (is.na(db_path) || !nzchar(db_path)) {
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

    # Path: explicit argument, then ZZEDC_DB_PATH, then the cached SQLite
    # adapter's path (which the Shiny application sets from its own
    # config.yml, so package functions it calls write to the same file
    # as its connection pool), then the default.
    sqlite_cfg <- if (!is.null(adapter)) adapter$config$sqlite else NULL
    if (is.null(db_path)) {
      db_path <- if (nzchar(Sys.getenv("ZZEDC_DB_PATH", unset = ""))) {
        get_db_path()
      } else {
        sqlite_cfg$path %||% get_db_path()
      }
    }

    # Verify database exists
    if (!file.exists(db_path)) {
      stop("Database file not found at: ", db_path,
           "\nUse initialize_encrypted_database() to create a new database")
    }

    # Resolve encryption key: explicit > adapter config > AWS KMS > env var
    if (is.null(key)) {
      adapter_key <- sqlite_cfg$encryption_key
      key <- if (!is.null(adapter_key) && nzchar(adapter_key) &&
                 identical(normalizePath(db_path, mustWork = FALSE),
                           normalizePath(sqlite_cfg$path %||% "", mustWork = FALSE))) {
        adapter_key
      } else {
        tryCatch(get_encryption_key(aws_kms_key_id = aws_kms_key_id),
                 error = function(e) e)
      }
    }

    # A plaintext SQLite file needs no key to open. Requiring one
    # anyway made every package function (audit logging included) fail
    # in a keyless SQLite deployment; the security profile, applied by
    # connect_encrypted() below, still decides whether that deployment
    # is acceptable. An encrypted file without a key is still an error.
    if (inherits(key, "error")) {
      if (isFALSE(sqlite_file_is_encrypted(db_path))) {
        enforce_encryption_at_rest(
          FALSE, db_path, "The file has a plaintext SQLite header and no key is configured."
        )
        return(DBI::dbConnect(RSQLite::SQLite(), db_path))
      }
      stop(conditionMessage(key), call. = FALSE)
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
#'   - encrypted: Logical. Whether the created file was verified to be
#'     encrypted at rest. On SQLite with a stock CRAN RSQLite build this
#'     is `FALSE`: the key is accepted but not applied. `NA` on
#'     server-hosted backends, where encryption at rest is a server
#'     setting this function cannot observe.
#'   - message: Status message, which states plainly when the database
#'     is not encrypted
#'
#' Under the `regulated` security profile (see
#' `resolve_security_profile()`), a SQLite database that would be
#' written unencrypted is removed and the function returns
#' `success = FALSE`. Under `standard` it succeeds with a warning;
#' under `development`, silently. In all profiles `encrypted` reports
#' the true state.
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

    # The key is passed explicitly; we deliberately do not write it to
    # the user's environment here. Callers who want it in the
    # environment can do so themselves with the key returned in the
    # result list.
    local({
      conn <- .connect_sqlite_with_key(db_path, key)
      on.exit(DBI::dbDisconnect(conn), add = TRUE)

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
    })

    # Judge the file only after the connection is closed and the
    # schema has been written, since an empty file has no header yet.
    encrypted <- isTRUE(sqlite_file_is_encrypted(db_path))
    tryCatch(
      enforce_encryption_at_rest(
        encrypted, db_path,
        "The installed RSQLite does not support SQLCipher or SQLite3MultipleCiphers, so the key was not applied."
      ),
      error = function(e) {
        # Do not leave a plaintext database behind when the profile
        # refuses one.
        unlink(db_path)
        stop(conditionMessage(e), call. = FALSE)
      }
    )

    return(list(
      success = TRUE,
      path = normalizePath(db_path, winslash = "/"),
      key = key,
      encrypted = encrypted,
      message = if (encrypted) {
        paste("Database created and encrypted at:", db_path)
      } else {
        paste(
          "Database created at:", db_path,
          "-- NOT encrypted at rest (stock RSQLite ignores the key)"
        )
      }
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

    # Build an adapter whose config carries the encryption key, and
    # cache it: unlike connect_encrypted_db()'s explicit-`key`
    # argument (a deliberately one-off connection), this function's
    # whole purpose is to leave the database usable afterward.
    # connect_encrypted_db()'s non-SQLite path reads the key from
    # the *cached* adapter's config, not from an env var the way the
    # SQLite path reads DB_ENCRYPTION_KEY -- so without updating the
    # cache here, every call after this one (add_form_field(), etc.)
    # would fail with "Cannot open encrypted database ... without a
    # key", even with the right key in hand, because nothing told the
    # cached adapter about it.
    config <- adapter$config
    config$duckdb$encryption_key <- key
    encrypted_adapter <- create_db_adapter(config)
    .db_adapter_cache$adapter <- encrypted_adapter
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

    # DuckDB refuses ATTACH ... ENCRYPTION_KEY outright when it cannot
    # encrypt, so reaching this point means the file is encrypted.
    list(
      success = TRUE,
      path = normalizePath(db_path, winslash = "/"),
      key = key,
      encrypted = TRUE,
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
      encrypted = NA,
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


#' Detect a Database File's Format (internal)
#'
#' @param db_path Character: path to the file.
#' @return `"sqlite"` (plaintext SQLite header), `"duckdb"` (DuckDB
#'   magic bytes at offset 8, present whether or not the file is
#'   encrypted), `"unknown"` (neither, which for a zzedc SQLite file
#'   means SQLCipher-style encryption), or `NA` if the file is missing
#'   or empty.
#' @keywords internal
.detect_db_file_format <- function(db_path) {
  if (is.null(db_path) || !file.exists(db_path) ||
      isTRUE(file.size(db_path) == 0)) {
    return(NA_character_)
  }
  header <- readBin(db_path, "raw", n = 16)
  if (identical(header, c(charToRaw("SQLite format 3"), as.raw(0)))) {
    return("sqlite")
  }
  if (length(header) >= 12 &&
      identical(header[9:12], charToRaw("DUCK"))) {
    return("duckdb")
  }
  "unknown"
}


#' Test Whether a Database File Opens Without a Key (internal)
#'
#' This is the property that encryption at rest exists to deny, so it
#' is tested directly rather than inferred from byte statistics.
#'
#' @param db_path Character: path to the file.
#' @param format Character: result of `.detect_db_file_format()`.
#' @return `TRUE` if the schema could be read with no key, `FALSE` if
#'   the engine refused, `NA` if the result could not be determined.
#' @keywords internal
.readable_without_key <- function(db_path, format) {
  if (is.na(format)) {
    return(NA)
  }
  if (format == "duckdb") {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      return(NA)
    }
    return(tryCatch({
      drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
      conn <- DBI::dbConnect(drv)
      on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)
      DBI::dbGetQuery(conn, "SELECT count(*) AS n FROM duckdb_tables()")
      TRUE
    }, error = function(e) {
      if (grepl("encrypted", conditionMessage(e), ignore.case = TRUE)) FALSE else NA
    }))
  }
  tryCatch({
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    DBI::dbGetQuery(conn, "SELECT count(*) AS n FROM sqlite_master")
    TRUE
  }, error = function(e) FALSE)
}


#' Verify Database Encryption
#'
#' Checks whether a SQLite or DuckDB database file is encrypted at
#' rest, by testing the property encryption exists to provide: the
#' file must be unreadable without the key, and readable with it.
#'
#' @param db_path Character: Database file to verify. If `NULL`, the
#'   configured backend decides: the DuckDB adapter's `duckdb.path`,
#'   otherwise `get_db_path()`.
#' @param key Character: Encryption key to test with. If `NULL`, the
#'   cached DuckDB adapter's configured key (for DuckDB files) or
#'   `get_encryption_key()` (for SQLite files) is used.
#' @param adapter Optional `DatabaseAdapter` whose configuration
#'   (backend, DuckDB extension directory and download policy) the
#'   check should follow; defaults to the cached adapter.
#'
#' @return List with verification results:
#'   - encrypted: `TRUE` only if the file could not be read without a
#'     key and could be read with one; `FALSE` otherwise; `NA` for
#'     server-hosted backends, where encryption at rest is a server
#'     setting not observable from here
#'   - backend: `"sqlite"`, `"duckdb"`, or the server backend name
#'   - readable_without_key: whether the schema could be read with no key
#'   - connection_works: whether a keyed connection succeeded
#'   - data_intact: whether the schema could be read through that
#'     connection
#'   - file_is_binary: retained for compatibility; equal to
#'     `!readable_without_key`
#'   - message: Status message
#'
#' @details
#' Earlier versions judged encryption by the share of bytes above 127
#' in the first kilobyte (requiring more than 80 percent). Ciphertext
#' is close to uniformly distributed, so roughly half its bytes exceed
#' 127, and a correctly encrypted file failed that check; it could not
#' distinguish encrypted from plaintext files. This version does not
#' use byte statistics.
#'
#' A DuckDB file that another connection in the same process holds
#' open read-write may fail the keyless probe with a lock error; the
#' result is then `readable_without_key = NA` and `encrypted = FALSE`.
#' Run the verification with no other connection open to the file.
#'
#' @examples
#' \dontrun{
#'   verification <- verify_database_encryption()
#'   if (verification$encrypted) {
#'     cat("Database encryption verified\n")
#'   } else {
#'     cat("Encryption issues:", verification$message, "\n")
#'   }
#' }
#'
#' @export
verify_database_encryption <- function(db_path = NULL, key = NULL,
                                       adapter = NULL) {
  results <- list(
    encrypted = FALSE,
    backend = NA_character_,
    readable_without_key = NA,
    connection_works = FALSE,
    data_intact = FALSE,
    file_is_binary = NA,
    message = NA_character_
  )

  tryCatch({
    adapter <- adapter %||% tryCatch(get_db_adapter(), error = function(e) NULL)
    configured_backend <- if (!is.null(adapter)) adapter$backend_name() else "sqlite"

    if (is.null(db_path)) {
      if (configured_backend %in% c("postgresql", "mysql", "clickhouse")) {
        results$backend <- configured_backend
        results$encrypted <- NA
        results$message <- paste(
          "Encryption at rest on", configured_backend,
          "is configured on the database server and cannot be verified",
          "from the client; see encryption_capabilities()."
        )
        return(results)
      }
      db_path <- if (configured_backend == "duckdb") {
        adapter$config$duckdb$path
      } else {
        get_db_path()
      }
    }

    if (!file.exists(db_path)) {
      stop("Database file not found at: ", db_path)
    }

    format <- .detect_db_file_format(db_path)
    results$backend <- if (identical(format, "duckdb")) "duckdb" else "sqlite"
    results$readable_without_key <- .readable_without_key(db_path, format)
    results$file_is_binary <- !results$readable_without_key

    schema_query <- if (results$backend == "duckdb") {
      "SELECT count(*) AS n FROM duckdb_tables()"
    } else {
      "SELECT count(*) AS n FROM sqlite_master"
    }

    if (is.null(key)) {
      key <- if (results$backend == "duckdb" && configured_backend == "duckdb") {
        adapter$config$duckdb$encryption_key
      } else {
        tryCatch(get_encryption_key(), error = function(e) NULL)
      }
    }

    keyed <- tryCatch({
      conn <- if (results$backend == "duckdb") {
        # Inherit the configured DuckDB settings (extension directory,
        # download policy), so the keyed test connection can load httpfs
        # the same way the application will.
        duck <- if (configured_backend == "duckdb") adapter$config$duckdb else list()
        duck$path <- db_path
        duck$encryption_key <- key
        create_db_adapter(list(db_backend = "duckdb", duckdb = duck))$connect()
      } else {
        .connect_sqlite_with_key(db_path, key %||% "")
      }
      on.exit(
        if (results$backend == "duckdb") {
          DBI::dbDisconnect(conn, shutdown = TRUE)
        } else {
          DBI::dbDisconnect(conn)
        },
        add = TRUE
      )
      out <- DBI::dbGetQuery(conn, schema_query)
      list(works = TRUE, intact = nrow(out) == 1)
    }, error = function(e) list(works = FALSE, intact = FALSE))

    results$connection_works <- keyed$works
    results$data_intact <- keyed$intact
    results$encrypted <- isFALSE(results$readable_without_key) &&
      results$connection_works && results$data_intact

    results$message <- if (results$encrypted) {
      paste("Encryption verified:", db_path,
            "cannot be read without the key and can be read with it")
    } else if (isTRUE(results$readable_without_key)) {
      paste("NOT encrypted:", db_path, "can be read without any key")
    } else {
      paste("Encryption not verified for", db_path, "-- readable without key:",
            results$readable_without_key, "; keyed connection works:",
            results$connection_works)
    }

    results
  }, error = function(e) {
    results$error <- paste("Verification failed:", conditionMessage(e))
    results$message <- results$error
    results
  })
}


#' Enable Encryption on Existing Database
#'
#' Converts an existing unencrypted SQLite or DuckDB database file into
#' an encrypted one, keeping a backup of the original.
#'
#' @param db_path Character: Path to existing database
#' @param new_key Character: Encryption key to use (optional, generates if NULL)
#'
#' @return List with encryption setup results:
#'   - success: Logical TRUE only if the rewritten file was verified to
#'     be encrypted
#'   - encrypted: Logical TRUE if the file is now encrypted
#'   - backup_created: Logical TRUE if backup saved
#'   - backup_path: Path to the plaintext backup. It contains every
#'     record in readable form; move it to protected storage or delete
#'     it once the encrypted file has been checked.
#'   - new_key: The encryption key used. The function does not persist
#'     it; the caller is responsible for storing it (for example
#'     `Sys.setenv(DB_ENCRYPTION_KEY = result$new_key)` for the current
#'     session, or AWS Secrets Manager / a password manager for
#'     production). Losing the key makes the database unrecoverable.
#'   - message: Status message
#'
#' On failure the function stops with an error and leaves the original
#' file unchanged.
#'
#' @details
#' DuckDB files are rewritten with `COPY FROM DATABASE` into a new file
#' attached with `ENCRYPTION_KEY`, which then replaces the original.
#'
#' SQLite files can be encrypted only when the installed RSQLite
#' actually supports a cipher (`sqlite_cipher_available()`); stock
#' CRAN RSQLite does not, and the function then stops with an error
#' rather than reporting success. Earlier versions created a backup and
#' a key but never rewrote the file.
#'
#' @examples
#' \dontrun{
#'   result <- set_encryption_for_existing_db(
#'     db_path = "./data/existing.duckdb",
#'     new_key = generate_db_key()
#'   )
#'   result$encrypted
#' }
#'
#' @export
set_encryption_for_existing_db <- function(db_path, new_key = NULL) {
  if (!file.exists(db_path)) {
    stop("Database not found at: ", db_path)
  }

  format <- .detect_db_file_format(db_path)
  if (is.na(format)) {
    stop("Database file is empty: ", db_path)
  }
  if (isFALSE(.readable_without_key(db_path, format))) {
    stop("Database is already encrypted (it cannot be read without a key): ", db_path)
  }
  if (format == "sqlite" && !sqlite_cipher_available()) {
    stop(
      "Cannot encrypt ", db_path, ": the installed RSQLite does not ",
      "support SQLCipher or SQLite3MultipleCiphers, so any key would be ",
      "ignored. Migrate to the DuckDB backend (which encrypts with ",
      "ENCRYPTION_KEY) or install a cipher-enabled RSQLite build."
    )
  }
  if (!format %in% c("sqlite", "duckdb")) {
    stop("Unrecognized database file format: ", db_path)
  }

  if (is.null(new_key)) {
    new_key <- generate_db_key()
  } else {
    verify_db_key(new_key)
  }

  backup_path <- paste0(db_path, ".backup.", format(Sys.time(), "%Y%m%d_%H%M%S"))
  if (!file.copy(db_path, backup_path, overwrite = FALSE)) {
    stop("Could not create backup at: ", backup_path)
  }

  tmp_path <- paste0(db_path, ".encrypting")
  unlink(tmp_path)
  on.exit(unlink(tmp_path), add = TRUE)

  if (format == "duckdb") {
    .encrypt_duckdb_file(db_path, tmp_path, new_key)
  } else {
    .encrypt_sqlite_file(db_path, tmp_path, new_key)
  }

  check <- verify_database_encryption(db_path = tmp_path, key = new_key)
  if (!isTRUE(check$encrypted)) {
    stop("Rewritten file failed encryption verification: ", check$message,
         ". Original left unchanged; backup at ", backup_path)
  }

  if (!file.rename(tmp_path, db_path)) {
    stop("Could not replace ", db_path, " with the encrypted copy. ",
         "Original left unchanged; backup at ", backup_path)
  }

  list(
    success = TRUE,
    encrypted = TRUE,
    backup_created = TRUE,
    backup_path = backup_path,
    new_key = new_key,
    message = paste0(
      "Encryption enabled for ", db_path, ". The plaintext backup at ",
      backup_path, " still contains every record unencrypted."
    )
  )
}


#' Rewrite a DuckDB File Encrypted (internal)
#' @param src Character: plaintext DuckDB file.
#' @param dest Character: path for the encrypted copy.
#' @param key Character: encryption key.
#' @keywords internal
.encrypt_duckdb_file <- function(src, dest, key) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("duckdb package required to encrypt a DuckDB file")
  }
  conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)
  # See DuckDBAdapter$connect(): ENCRYPTION_KEY needs httpfs loaded
  # first on at least one DuckDB build.
  DBI::dbExecute(conn, "INSTALL httpfs")
  DBI::dbExecute(conn, "LOAD httpfs")
  DBI::dbExecute(conn, sprintf("ATTACH '%s' AS zzedc_src (READ_ONLY)", src))
  DBI::dbExecute(conn, sprintf(
    "ATTACH '%s' AS zzedc_dest (ENCRYPTION_KEY '%s')", dest, key
  ))
  DBI::dbExecute(conn, "COPY FROM DATABASE zzedc_src TO zzedc_dest")
  DBI::dbExecute(conn, "DETACH zzedc_dest")
  DBI::dbExecute(conn, "DETACH zzedc_src")
  invisible(dest)
}


#' Rewrite a SQLite File Encrypted (internal)
#'
#' Copies every table, then replays index, trigger, and view
#' definitions. Requires a cipher-enabled RSQLite; callers check
#' `sqlite_cipher_available()` first.
#'
#' @param src Character: plaintext SQLite file.
#' @param dest Character: path for the encrypted copy.
#' @param key Character: encryption key.
#' @keywords internal
.encrypt_sqlite_file <- function(src, dest, key) {
  src_conn <- DBI::dbConnect(RSQLite::SQLite(), src, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(src_conn), add = TRUE)
  dest_conn <- .connect_sqlite_with_key(dest, key)
  on.exit(DBI::dbDisconnect(dest_conn), add = TRUE)

  objects <- DBI::dbGetQuery(src_conn, "
    SELECT type, name, sql FROM sqlite_master
    WHERE name NOT LIKE 'sqlite_%' AND sql IS NOT NULL
  ")

  for (i in which(objects$type == "table")) {
    DBI::dbExecute(dest_conn, objects$sql[i])
    rows <- DBI::dbReadTable(src_conn, objects$name[i])
    if (nrow(rows) > 0) {
      DBI::dbAppendTable(dest_conn, objects$name[i], rows)
    }
  }
  for (i in which(objects$type %in% c("index", "trigger", "view"))) {
    DBI::dbExecute(dest_conn, objects$sql[i])
  }
  invisible(dest)
}
