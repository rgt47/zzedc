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
#' - compression: Native-protocol compression passed to RClickhouse,
#'   "none" (default) or "lz4". RClickhouse's own default, "lz4", fails
#'   against current ClickHouse servers (verified on 26.10) with
#'   "unsupported compression method 144"; use "lz4" only for a server
#'   known to accept it. Ignored by the HTTP `clickhouse` package.
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
        conn <- do.call(
          DBI::dbConnect,
          c(list(RClickhouse::clickhouse()), rclickhouse_connect_args(ch))
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
        do.call(
          pool::dbPool,
          c(
            list(RClickhouse::clickhouse()),
            rclickhouse_connect_args(ch),
            list(
              minSize = ch$pool_min %||% 1L,
              maxSize = ch$pool_max %||% 5L
            )
          )
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
    #' Describe this backend's encryption. Encryption at rest is a
    #' ClickHouse server or storage setting zzedc cannot observe; TLS
    #' depends on the connection settings. Earlier versions reported
    #' `supports_encryption() = TRUE` on the strength of TLS alone.
    #' @return List; see `DatabaseAdapter$encryption_capabilities()`
    encryption_capabilities = function() {
      list(
        at_rest = "server",
        at_rest_configured = NA,
        in_transit = "optional",
        detail = "Encryption at rest and TLS are configured on the ClickHouse server."
      )
    },

    #' @description
    #' Get backend name
    #' @return Character "clickhouse"
    backend_name = function() {
      "clickhouse"
    },

    #' @description
    #' Execute a SELECT query. RClickhouse does not bind parameters, so
    #' `params` are interpolated into `sql` with `DBI::sqlInterpolate()`
    #' using the driver's own quoting.
    #' @param conn Database connection or pool
    #' @param sql SQL query string with `?` placeholders
    #' @param params Optional list or vector of parameters
    #' @return Data frame with query results
    query = function(conn, sql, params = NULL) {
      with_clickhouse_conn(conn, function(con) {
        DBI::dbGetQuery(con, clickhouse_interpolate(con, sql, params))
      })
    },

    #' @description
    #' Execute a non-SELECT statement, interpolating `params` as in
    #' `query()`.
    #' @param conn Database connection or pool
    #' @param sql SQL statement with `?` placeholders
    #' @param params Optional list or vector of parameters
    #' @return Number of rows affected
    execute = function(conn, sql, params = NULL) {
      with_clickhouse_conn(conn, function(con) {
        DBI::dbExecute(con, clickhouse_interpolate(con, sql, params))
      })
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


#' Interpolate parameters into ClickHouse SQL
#'
#' RClickhouse implements no parameter binding: `DBI::dbExecute(conn,
#' sql, params = ...)` sends the `?` placeholders to the server
#' unchanged. This quotes each value with the connection's own
#' `dbQuoteLiteral()` methods via `DBI::sqlInterpolate()`, which also
#' leaves a `?` inside a quoted string literal alone and errors when
#' the number of values does not match the placeholders.
#'
#' @param con A DBI connection (not a pool).
#' @param sql SQL with positional `?` or named `?name` placeholders.
#' @param params `NULL`, a list, or an atomic vector of values.
#' @return The SQL string to send.
#' @keywords internal
#' @noRd
clickhouse_interpolate <- function(con, sql, params) {
  if (is.null(params) || length(params) == 0L) {
    return(sql)
  }
  as.character(DBI::sqlInterpolate(con, sql, .dots = as.list(params)))
}


#' Run a function with a plain connection, checking one out of a pool
#'
#' `sqlInterpolate()` quotes through the connection's methods, so a
#' pool is checked out for the duration of the call and returned.
#'
#' @param conn A DBI connection or a `pool::Pool`.
#' @param fn Function of one argument, the connection.
#' @return The value of `fn`.
#' @keywords internal
#' @noRd
with_clickhouse_conn <- function(conn, fn) {
  if (inherits(conn, "Pool")) {
    con <- pool::poolCheckout(conn)
    on.exit(pool::poolReturn(con), add = TRUE)
    return(fn(con))
  }
  fn(conn)
}


#' RClickhouse connection arguments from a clickhouse config section
#'
#' Shared by `ClickHouseAdapter$connect()` and `$pool()` so both pass
#' the same arguments. `compression` defaults to "none" because
#' RClickhouse's own default, "lz4", fails against current ClickHouse
#' servers with "unsupported compression method 144".
#'
#' @param ch The `config$clickhouse` list.
#' @return Named list of arguments for `DBI::dbConnect()` with an
#'   `RClickhouse::clickhouse()` driver.
#' @keywords internal
#' @noRd
rclickhouse_connect_args <- function(ch) {
  compression <- ch$compression %||% "none"
  if (!(is.character(compression) && length(compression) == 1L &&
        compression %in% c("none", "lz4"))) {
    stop("clickhouse$compression must be \"none\" or \"lz4\"",
         call. = FALSE)
  }
  list(
    host = ch$host,
    port = ch$port %||% 9000L,
    dbname = ch$database,
    user = ch$user %||% "default",
    password = ch$password %||% "",
    compression = compression
  )
}


# Null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
