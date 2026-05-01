#' DuckDB Database Adapter
#'
#' Database adapter implementation for DuckDB backend.
#'
#' @description
#' DuckDB is recommended for:
#' - Analytics-heavy workloads requiring fast aggregation
#' - Single-server deployments needing columnar performance
#' - Direct Parquet/CSV export for data sharing
#'
#' @details
#' Configuration options (in config$duckdb):
#' - path: Path to database file (required, use ":memory:" for in-memory)
#' - threads: Number of threads for query execution (optional)
#' - memory_limit: Maximum memory usage (optional, e.g., "4GB")
#'
#' @examples
#' \dontrun{
#'   config <- list(
#'     db_backend = "duckdb",
#'     duckdb = list(
#'       path = "data/zzedc.duckdb"
#'     )
#'   )
#'   adapter <- DuckDBAdapter$new(config)
#'   conn <- adapter$connect()
#' }
#'
#' @export
DuckDBAdapter <- R6::R6Class(

  "DuckDBAdapter",
  inherit = DatabaseAdapter,

  public = list(
    #' @description
    #' Initialize DuckDB adapter
    #' @param config Configuration list with duckdb settings
    initialize = function(config) {
      super$initialize(config)

      if (!requireNamespace("duckdb", quietly = TRUE)) {
        stop("duckdb package required for DuckDB backend.\n",
             "Install with: install.packages('duckdb')")
      }

      # Validate configuration
      if (is.null(config$duckdb$path)) {
        stop("DuckDB configuration requires 'duckdb$path'")
      }
    },

    #' @description
    #' Create a new DuckDB connection
    #' @return DBI connection object
    connect = function() {
      db_path <- self$config$duckdb$path

      # Create directory if needed (unless in-memory)
      if (db_path != ":memory:") {
        db_dir <- dirname(db_path)
        if (!dir.exists(db_dir) && db_dir != ".") {
          dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
        }
      }

      conn <- DBI::dbConnect(
        duckdb::duckdb(),
        dbdir = db_path,
        read_only = FALSE
      )

      # Configure threads if specified
      threads <- self$config$duckdb$threads
      if (!is.null(threads)) {
        DBI::dbExecute(conn, sprintf("SET threads = %d", as.integer(threads)))
      }

      # Configure memory limit if specified
      memory_limit <- self$config$duckdb$memory_limit
      if (!is.null(memory_limit)) {
        DBI::dbExecute(conn, sprintf("SET memory_limit = '%s'", memory_limit))
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

      db_path <- self$config$duckdb$path

      # Create directory if needed (unless in-memory)
      if (db_path != ":memory:") {
        db_dir <- dirname(db_path)
        if (!dir.exists(db_dir) && db_dir != ".") {
          dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
        }
      }

      pool::dbPool(
        duckdb::duckdb(),
        dbdir = db_path,
        read_only = FALSE
      )
    },

    #' @description
    #' Get DuckDB-specific SQL dialect information
    #' @return List with dialect-specific SQL fragments
    dialect = function() {
      list(
        # Primary key with auto-increment (DuckDB uses sequences)
        auto_increment = "INTEGER PRIMARY KEY",
        serial = "INTEGER PRIMARY KEY",

        # Timestamp functions
        timestamp_now = "now()",
        current_timestamp = "CURRENT_TIMESTAMP",

        # JSON functions (DuckDB has native JSON support)
        json_extract = function(col, path) {
          sprintf("%s->>'%s'", col, path)
        },
        json_type = "JSON",

        # Boolean literals (DuckDB has native booleans)
        boolean_true = "TRUE",
        boolean_false = "FALSE",
        boolean_type = "BOOLEAN",

        # String concatenation
        concat = function(...) {
          sprintf("concat(%s)", paste(c(...), collapse = ", "))
        },

        # Type mappings
        text_type = "VARCHAR",
        varchar_type = function(n) sprintf("VARCHAR(%d)", n),
        integer_type = "INTEGER",
        bigint_type = "BIGINT",
        real_type = "DOUBLE",
        blob_type = "BLOB",
        timestamp_type = "TIMESTAMP",

        # Parameter placeholder style
        placeholder = "?",
        numbered_placeholder = function(n) "?",

        # RETURNING clause support
        supports_returning = TRUE,

        # UPSERT support (DuckDB uses INSERT OR REPLACE)
        upsert_syntax = "INSERT OR REPLACE"
      )
    },

    #' @description
    #' Check if encryption is supported
    #' @return Logical FALSE (DuckDB does not support native encryption)
    supports_encryption = function() {
      FALSE
    },

    #' @description
    #' Get backend name
    #' @return Character "duckdb"
    backend_name = function() {
      "duckdb"
    },

    #' @description
    #' DuckDB-specific: Export table to Parquet file
    #' @param conn Database connection
    #' @param table_name Name of table to export
    #' @param file_path Path for output Parquet file
    export_parquet = function(conn, table_name, file_path) {
      sql <- sprintf("COPY %s TO '%s' (FORMAT PARQUET)", table_name, file_path)
      DBI::dbExecute(conn, sql)
    },

    #' @description
    #' DuckDB-specific: Export table to CSV file
    #' @param conn Database connection
    #' @param table_name Name of table to export
    #' @param file_path Path for output CSV file
    #' @param header Include header row (default TRUE)
    export_csv = function(conn, table_name, file_path, header = TRUE) {
      header_str <- if (header) "TRUE" else "FALSE"
      sql <- sprintf("COPY %s TO '%s' (FORMAT CSV, HEADER %s)",
                     table_name, file_path, header_str)
      DBI::dbExecute(conn, sql)
    },

    #' @description
    #' DuckDB-specific: Import from Parquet file
    #' @param conn Database connection
    #' @param file_path Path to Parquet file
    #' @param table_name Target table name
    import_parquet = function(conn, file_path, table_name) {
      sql <- sprintf("CREATE TABLE %s AS SELECT * FROM '%s'",
                     table_name, file_path)
      DBI::dbExecute(conn, sql)
    },

    #' @description
    #' DuckDB-specific: Query Parquet file directly without importing
    #' @param conn Database connection
    #' @param file_path Path to Parquet file
    #' @param sql_where Optional WHERE clause
    #' @return Data frame with query results
    query_parquet = function(conn, file_path, sql_where = NULL) {
      sql <- sprintf("SELECT * FROM '%s'", file_path)
      if (!is.null(sql_where)) {
        sql <- paste(sql, "WHERE", sql_where)
      }
      DBI::dbGetQuery(conn, sql)
    },

    #' @description
    #' DuckDB-specific: Get database file size in bytes
    #' @return Integer file size or NA if in-memory or file doesn't exist
    file_size = function() {
      path <- self$config$duckdb$path
      if (path == ":memory:") {
        NA_integer_
      } else if (file.exists(path)) {
        file.info(path)$size
      } else {
        NA_integer_
      }
    }
  )
)
