#' ClickHouse Database Adapter
#'
#' Database adapter implementation for ClickHouse backend.
#'
#' @description
#' ClickHouse is recommended for:
#' - Very large datasets with billions of rows
#' - Real-time analytics and aggregation queries
#' - Time-series data and log analysis
#' - Read-heavy workloads with columnar storage
#'
#' @details
#' Configuration options (in config$clickhouse):
#' - host: ClickHouse server hostname (required)
#' - port: HTTP port (default 8123) or native port (default 9000)
#' - database: Database name (required)
#' - user: Username (default "default")
#' - password: Password (optional)
#' - use_https: Use HTTPS connection (default FALSE)
#'
#' Note: ClickHouse has different transaction semantics than traditional
#' RDBMS. It uses eventual consistency and is optimized for batch inserts.
#'
#' @examples
#' \dontrun{
#'   config <- list(
#'     db_backend = "clickhouse",
#'     clickhouse = list(
#'       host = "localhost",
#'       port = 8123,
#'       database = "zzedc",
#'       user = "default"
#'     )
#'   )
#'   adapter <- ClickHouseAdapter$new(config)
#'   conn <- adapter$connect()
#' }
#'
#' @export
ClickHouseAdapter <- R6::R6Class(

  "ClickHouseAdapter",
  inherit = DatabaseAdapter,

  public = list(
    #' @description
    #' Initialize ClickHouse adapter
    #' @param config Configuration list with clickhouse settings
    initialize = function(config) {
      super$initialize(config)

      if (!requireNamespace("RClickhouse", quietly = TRUE)) {
        if (!requireNamespace("clickhouse", quietly = TRUE)) {
          stop("RClickhouse or clickhouse package required for ClickHouse.\n",
               "Install with: install.packages('RClickhouse')\n",
               "Or: install.packages('clickhouse')")
        }
      }

      # Validate configuration
      ch <- config$clickhouse
      if (is.null(ch$host)) {
        stop("ClickHouse configuration requires 'clickhouse$host'")
      }
      if (is.null(ch$database)) {
        stop("ClickHouse configuration requires 'clickhouse$database'")
      }
    },

    #' @description
    #' Create a new ClickHouse connection
    #' @return DBI connection object
    connect = function() {
      ch <- self$config$clickhouse

      # Try RClickhouse first (DBI-compliant)
      if (requireNamespace("RClickhouse", quietly = TRUE)) {
        conn <- DBI::dbConnect(
          RClickhouse::clickhouse(),
          host = ch$host,
          port = ch$port %||% 9000L,
          db = ch$database,
          user = ch$user %||% "default",
          password = ch$password %||% ""
        )
      } else {
        # Fall back to clickhouse package
        conn <- DBI::dbConnect(
          clickhouse::clickhouse(),
          host = ch$host,
          port = ch$port %||% 8123L,
          db = ch$database,
          user = ch$user %||% "default",
          password = ch$password %||% "",
          https = ch$use_https %||% FALSE
        )
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

      ch <- self$config$clickhouse

      if (requireNamespace("RClickhouse", quietly = TRUE)) {
        pool::dbPool(
          RClickhouse::clickhouse(),
          host = ch$host,
          port = ch$port %||% 9000L,
          db = ch$database,
          user = ch$user %||% "default",
          password = ch$password %||% "",
          minSize = ch$pool_min %||% 1L,
          maxSize = ch$pool_max %||% 5L
        )
      } else {
        pool::dbPool(
          clickhouse::clickhouse(),
          host = ch$host,
          port = ch$port %||% 8123L,
          db = ch$database,
          user = ch$user %||% "default",
          password = ch$password %||% "",
          https = ch$use_https %||% FALSE,
          minSize = ch$pool_min %||% 1L,
          maxSize = ch$pool_max %||% 5L
        )
      }
    },

    #' @description
    #' Get ClickHouse-specific SQL dialect information
    #' @return List with dialect-specific SQL fragments
    dialect = function() {
      list(
        # Primary key (ClickHouse uses ORDER BY for primary key in MergeTree)
        auto_increment = "UInt64",
        serial = "UInt64",

        # Timestamp functions
        timestamp_now = "now()",
        current_timestamp = "now()",

        # JSON functions (ClickHouse has native JSON support)
        json_extract = function(col, path) {
          sprintf("JSONExtractString(%s, '%s')", col, path)
        },
        json_extract_raw = function(col, path) {
          sprintf("JSONExtractRaw(%s, '%s')", col, path)
        },
        json_type = "String",

        # Boolean literals (ClickHouse uses UInt8 for booleans)
        boolean_true = "1",
        boolean_false = "0",
        boolean_type = "UInt8",

        # String concatenation
        concat = function(...) {
          sprintf("concat(%s)", paste(c(...), collapse = ", "))
        },

        # Type mappings
        text_type = "String",
        varchar_type = function(n) "String",
        integer_type = "Int32",
        bigint_type = "Int64",
        real_type = "Float64",
        blob_type = "String",
        timestamp_type = "DateTime",
        date_type = "Date",

        # ClickHouse-specific types
        uuid_type = "UUID",
        ipv4_type = "IPv4",
        ipv6_type = "IPv6",
        nullable = function(type) sprintf("Nullable(%s)", type),

        # Parameter placeholder style
        placeholder = "?",
        numbered_placeholder = function(n) "?",

        # RETURNING clause support (not supported in ClickHouse)
        supports_returning = FALSE,

        # UPSERT support (ClickHouse uses ReplacingMergeTree)
        upsert_syntax = "INSERT",

        # Table engine (required for ClickHouse)
        default_engine = "MergeTree()",
        replicated_engine = function(path, replica) {

          sprintf("ReplicatedMergeTree('%s', '%s')", path, replica)
        }
      )
    },

    #' @description
    #' Check if encryption is supported
    #' @return Logical TRUE (ClickHouse supports TLS)
    supports_encryption = function() {
      TRUE
    },

    #' @description
    #' Get backend name
    #' @return Character "clickhouse"
    backend_name = function() {
      "clickhouse"
    },

    #' @description
    #' ClickHouse-specific: Execute batch insert for better performance
    #' @param conn Database connection
    #' @param table_name Name of table
    #' @param data Data frame to insert
    insert_batch = function(conn, table_name, data) {
      DBI::dbWriteTable(conn, table_name, data, append = TRUE)
    },

    #' @description
    #' ClickHouse-specific: Create table with MergeTree engine
    #' @param conn Database connection
    #' @param table_name Table name
    #' @param columns Column definitions
    #' @param order_by Columns for ORDER BY clause (required for MergeTree)
    #' @param partition_by Optional partition expression
    #' @param engine Table engine (default MergeTree)
    create_table = function(conn, table_name, columns, order_by,
                            partition_by = NULL, engine = "MergeTree()") {
      col_defs <- paste(columns, collapse = ",\n  ")

      partition_clause <- if (!is.null(partition_by)) {
        sprintf("PARTITION BY %s", partition_by)
      } else {
        ""
      }

      sql <- sprintf("
        CREATE TABLE IF NOT EXISTS %s (
          %s
        )
        ENGINE = %s
        %s
        ORDER BY (%s)
      ", table_name, col_defs, engine, partition_clause,
         paste(order_by, collapse = ", "))

      DBI::dbExecute(conn, sql)
    },

    #' @description
    #' ClickHouse-specific: Optimize table (merge parts)
    #' @param conn Database connection
    #' @param table_name Table name
    #' @param final Run FINAL optimization
    optimize = function(conn, table_name, final = FALSE) {
      sql <- sprintf("OPTIMIZE TABLE %s%s",
                     table_name,
                     if (final) " FINAL" else "")
      DBI::dbExecute(conn, sql)
    },

    #' @description
    #' ClickHouse-specific: Get table size and row count
    #' @param conn Database connection
    #' @param table_name Table name
    #' @return List with rows and bytes
    table_stats = function(conn, table_name) {
      sql <- sprintf("
        SELECT
          sum(rows) as rows,
          sum(bytes) as bytes
        FROM system.parts
        WHERE table = '%s' AND active
      ", table_name)
      result <- DBI::dbGetQuery(conn, sql)
      list(rows = result$rows[1], bytes = result$bytes[1])
    },

    #' @description
    #' Override transaction methods (ClickHouse has limited transaction support)
    #' @param conn Database connection
    begin = function(conn) {
      warning("ClickHouse has limited transaction support. ",
              "Operations are atomic at the block level.")
    },

    #' @description
    #' Override commit (no-op for ClickHouse)
    #' @param conn Database connection
    commit = function(conn) {
      invisible(NULL)
    },

    #' @description
    #' Override rollback (not supported in ClickHouse)
    #' @param conn Database connection
    rollback = function(conn) {
      warning("ClickHouse does not support rollback. ",
              "Data modifications are immediate.")
    }
  )
)


# Null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
