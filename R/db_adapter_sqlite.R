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
#' - encryption_key: Optional encryption key (requires RSQLCipher)
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

      conn <- RSQLite::dbConnect(
        RSQLite::SQLite(),
        dbname = db_path
      )

      # Enable WAL mode for better concurrency
      DBI::dbExecute(conn, "PRAGMA journal_mode = WAL")

      # Enable foreign keys

      DBI::dbExecute(conn, "PRAGMA foreign_keys = ON")

      # Handle encryption if configured
      encryption_key <- self$config$sqlite$encryption_key
      if (!is.null(encryption_key) && nchar(encryption_key) > 0) {
        if (self$supports_encryption()) {
          DBI::dbExecute(conn, sprintf("PRAGMA key = '%s'", encryption_key))
        } else {
          warning("Encryption key provided but RSQLCipher not available. ",
                  "Database will not be encrypted.")
        }
      }

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

      pool::dbPool(
        RSQLite::SQLite(),
        dbname = db_path
      )
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
        upsert_syntax = "INSERT OR REPLACE"
      )
    },

    #' @description
    #' Check if encryption is supported (RSQLCipher available)
    #' @return Logical TRUE if RSQLCipher is available
    supports_encryption = function() {
      requireNamespace("RSQLCipher", quietly = TRUE)
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
  )
)
