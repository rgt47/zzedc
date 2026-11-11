#' SQLite Database Adapter
#'
#' Database adapter implementation for SQLite backend.
#'
#' @description
#' SQLite is recommended for:
#' - Desktop/local single-user deployments
#' - Development and testing
#' - Maximum compatibility and proven stability
#'
#' @details
#' Configuration options (in config$sqlite):
#' - path: Path to database file (required)
#' - encryption_key: Optional encryption key. It is applied only by an
#'   RSQLite build compiled with SQLCipher or SQLite3MultipleCiphers;
#'   stock CRAN RSQLite ignores it, and the file is written in
#'   plaintext. Whether that is allowed depends on the security
#'   profile (see `resolve_security_profile()`).
#'
#' @examples
#' \dontrun{
#'   config <- list(
#'     db_backend = "sqlite",
#'     sqlite = list(
#'       path = "data/zzedc.db"
#'     )
#'   )
#'   adapter <- SQLiteAdapter$new(config)
#'   conn <- adapter$connect()
#' }
#'
#' @export
SQLiteAdapter <- R6::R6Class(

  "SQLiteAdapter",
  inherit = DatabaseAdapter,

  public = list(
    #' @description
    #' Initialize SQLite adapter
    #' @param config Configuration list with sqlite settings
    initialize = function(config) {
      super$initialize(config)

      if (!requireNamespace("RSQLite", quietly = TRUE)) {
        stop("RSQLite package required for SQLite backend.\n",
             "Install with: install.packages('RSQLite')")
      }

      # Validate configuration
      if (is.null(config$sqlite$path)) {
        stop("SQLite configuration requires 'sqlite$path'")
      }
    },

    #' @description
    #' Create a new SQLite connection
    #' @return DBI connection object
    connect = function() {
      db_path <- self$config$sqlite$path

      # Create directory if needed
      db_dir <- dirname(db_path)
      if (!dir.exists(db_dir) && db_dir != ".") {
        dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
      }

      private$check_at_rest()

      # The key must be applied before any other statement: a cipher
      # build reads the first page on the first statement, so running
      # PRAGMA journal_mode first would fail on an encrypted file.
      encryption_key <- self$config$sqlite$encryption_key
      conn <- if (!is.null(encryption_key) && nzchar(encryption_key)) {
        .connect_sqlite_with_key(db_path, encryption_key)
      } else {
        RSQLite::dbConnect(RSQLite::SQLite(), dbname = db_path)
      }

      DBI::dbExecute(conn, "PRAGMA journal_mode = WAL")
      DBI::dbExecute(conn, "PRAGMA foreign_keys = ON")

      conn
    },

    #' @description
    #' Create a connection pool
    #' @return Pool object
    pool = function() {
      if (!requireNamespace("pool", quietly = TRUE)) {
        stop("pool package required for connection pooling.\n",
             "Install with: install.packages('pool')")
      }

      db_path <- self$config$sqlite$path

      # Create directory if needed
      db_dir <- dirname(db_path)
      if (!dir.exists(db_dir) && db_dir != ".") {
        dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
      }

      private$check_at_rest()

      encryption_key <- self$config$sqlite$encryption_key
      min_size <- self$config$sqlite$pool_min %||% 1
      max_size <- self$config$sqlite$pool_max %||% Inf
      if (!is.null(encryption_key) && nzchar(encryption_key)) {
        pool::dbPool(
          RSQLite::SQLite(),
          dbname = db_path,
          minSize = min_size,
          maxSize = max_size,
          onCreate = function(conn) {
            DBI::dbExecute(conn, "PRAGMA cipher = 'sqlcipher'")
            DBI::dbExecute(conn, sprintf("PRAGMA key = '%s'", encryption_key))
          }
        )
      } else {
        pool::dbPool(
          RSQLite::SQLite(),
          dbname = db_path,
          minSize = min_size,
          maxSize = max_size
        )
      }
    },

    #' @description
    #' Get SQLite-specific SQL dialect information
    #' @return List with dialect-specific SQL fragments
    dialect = function() {
      list(
        # Primary key with auto-increment
        auto_increment = "INTEGER PRIMARY KEY AUTOINCREMENT",
        serial = "INTEGER PRIMARY KEY AUTOINCREMENT",

        # Timestamp functions
        timestamp_now = "datetime('now')",
        current_timestamp = "CURRENT_TIMESTAMP",

        # JSON functions
        json_extract = function(col, path) {
          sprintf("json_extract(%s, '$.%s')", col, path)
        },
        json_type = "TEXT",

        # Boolean literals (SQLite uses 0/1)
        boolean_true = "1",
        boolean_false = "0",
        boolean_type = "INTEGER",

        # String concatenation
        concat = function(...) {
          paste(c(...), collapse = " || ")
        },

        # Type mappings
        text_type = "TEXT",
        varchar_type = function(n) sprintf("VARCHAR(%d)", n),
        integer_type = "INTEGER",
        real_type = "REAL",
        blob_type = "BLOB",
        timestamp_type = "TEXT",  # SQLite stores timestamps as TEXT

        # Parameter placeholder style
        placeholder = "?",
        numbered_placeholder = function(n) "?",

        # RETURNING clause support (SQLite 3.35+)
        supports_returning = TRUE,

        # UPSERT support
        upsert_syntax = "INSERT OR REPLACE",

        # Date difference in days (col_a - col_b)
        date_diff_days = function(col_a, col_b) {
          sprintf("(julianday(%s) - julianday(%s))", col_a, col_b)
        }
      )
    },

    #' @description
    #' Describe this backend's encryption. At-rest encryption is
    #' available only when the installed RSQLite actually encrypts a
    #' keyed file (`sqlite_cipher_available()`, a functional test), not
    #' merely when some package is installed.
    #' @return List; see `DatabaseAdapter$encryption_capabilities()`
    encryption_capabilities = function() {
      cipher <- sqlite_cipher_available()
      key <- self$config$sqlite$encryption_key
      list(
        at_rest = if (cipher) "package" else "none",
        at_rest_configured = cipher && !is.null(key) && nzchar(key),
        in_transit = "not_applicable",
        detail = if (cipher) {
          "The installed RSQLite encrypts keyed files (SQLCipher-compatible)."
        } else {
          "Stock RSQLite has no cipher; SQLite files are stored in plaintext."
        }
      )
    },

    #' @description
    #' Describe a table's columns via `PRAGMA table_info`
    #' @param conn Database connection
    #' @param table_name Name of table to describe
    #' @return Data frame with columns `name`, `type`, `notnull`, `pk`
    describe_table = function(conn, table_name) {
      info <- DBI::dbGetQuery(conn, sprintf("PRAGMA table_info('%s')", table_name))
      data.frame(
        name = info$name,
        type = info$type,
        notnull = info$notnull > 0,
        pk = info$pk > 0,
        stringsAsFactors = FALSE
      )
    },

    #' @description
    #' Get backend name
    #' @return Character "sqlite"
    backend_name = function() {
      "sqlite"
    },

    #' @description
    #' SQLite-specific: Enable Write-Ahead Logging for better concurrency
    #' @param conn Database connection
    enable_wal = function(conn) {
      DBI::dbExecute(conn, "PRAGMA journal_mode = WAL")
    },

    #' @description
    #' SQLite-specific: Optimize database (VACUUM and ANALYZE)
    #' @param conn Database connection
    optimize = function(conn) {
      DBI::dbExecute(conn, "VACUUM")
      DBI::dbExecute(conn, "ANALYZE")
    },

    #' @description
    #' SQLite-specific: Get database file size in bytes
    #' @return Integer file size or NA if file doesn't exist
    file_size = function() {
      path <- self$config$sqlite$path
      if (file.exists(path)) {
        file.info(path)$size
      } else {
        NA_integer_
      }
    }
  ),

  private = list(
    # Apply the security profile before opening the file. An in-memory
    # database holds nothing at rest. An existing file is judged by its
    # header; a new file is judged by whether a key can be applied at
    # all, since its header does not exist yet.
    check_at_rest = function() {
      db_path <- self$config$sqlite$path
      if (identical(db_path, ":memory:")) {
        return(invisible(TRUE))
      }
      key <- self$config$sqlite$encryption_key
      has_key <- !is.null(key) && nzchar(key)
      on_disk <- sqlite_file_is_encrypted(db_path)
      encrypted <- if (!is.na(on_disk)) {
        on_disk
      } else {
        has_key && sqlite_cipher_available()
      }
      reason <- if (!has_key) {
        "No sqlite.encryption_key is configured."
      } else {
        "The installed RSQLite does not support SQLCipher or SQLite3MultipleCiphers, so the key is ignored."
      }
      enforce_encryption_at_rest(encrypted, db_path, reason)
    }
  )
)
