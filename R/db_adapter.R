#' Database Adapter Base Class
#'
#' Abstract base class defining the interface for all database adapters.
#' Concrete implementations exist for SQLite, DuckDB, and PostgreSQL.
#'
#' @description
#' This class provides a unified interface for database operations across
#' different backends. All database-specific logic is encapsulated in
#' adapter subclasses, allowing the rest of the application to be
#' database-agnostic.
#'
#' @details
#' The adapter pattern enables zzedc to support multiple database backends:
#' - SQLite: Proven stability, single-file, zero configuration
#' - DuckDB: Fast analytics, columnar storage, Parquet export
#' - PostgreSQL: Multi-user, enterprise deployment, managed cloud options
#'
#' @examples
#' \dontrun{
#'   # Create adapter from configuration
#'   adapter <- create_db_adapter(config)
#'
#'   # Connect and query
#'   conn <- adapter$connect()
#'   result <- adapter$query(conn, "SELECT * FROM users")
#'   adapter$disconnect(conn)
#'
#'   # Or use connection pooling
#'   pool <- adapter$pool()
#'   result <- adapter$query(pool, "SELECT * FROM users")
#'   adapter$pool_close(pool)
#' }
#'
#' @export
DatabaseAdapter <- R6::R6Class(
  "DatabaseAdapter",

  public = list(
    #' @field config Configuration list for this adapter
    config = NULL,

    #' @description
    #' Initialize the adapter with configuration
    #' @param config List containing database configuration
    initialize = function(config) {
      self$config <- config
    },

    #' @description
    #' Create a new database connection
    #' @return DBI connection object
    connect = function() {
      stop("Subclass must implement connect()")
    },

    #' @description
    #' Close a database connection
    #' @param conn DBI connection to close
    disconnect = function(conn) {
      if (!is.null(conn) && DBI::dbIsValid(conn)) {
        DBI::dbDisconnect(conn)
      }
    },

    #' @description
    #' Create a connection pool for concurrent access
    #' @return Pool object
    pool = function() {
      stop("Subclass must implement pool()")
    },

    #' @description
    #' Close a connection pool
    #' @param pool Pool object to close
    pool_close = function(pool) {
      if (inherits(pool, "Pool")) {
        pool::poolClose(pool)
      }
    },

    #' @description
    #' Execute a SELECT query and return results
    #' @param conn Database connection or pool
    #' @param sql SQL query string
    #' @param params Optional named list or vector of parameters
    #' @return Data frame with query results
    query = function(conn, sql, params = NULL) {
      # Extract operation name from SQL for profiling
      op_name <- extract_sql_operation(sql)

      with_profiling("db", op_name, {
        if (is.null(params)) {
          DBI::dbGetQuery(conn, sql)
        } else {
          DBI::dbGetQuery(conn, sql, params = params)
        }
      }, metadata = list(sql_preview = substr(sql, 1, 100)))
    },

    #' @description
    #' Execute a non-SELECT statement (INSERT, UPDATE, DELETE, DDL)
    #' @param conn Database connection or pool
    #' @param sql SQL statement
    #' @param params Optional named list or vector of parameters
    #' @return Number of rows affected
    execute = function(conn, sql, params = NULL) {
      op_name <- extract_sql_operation(sql)

      with_profiling("db", op_name, {
        if (is.null(params)) {
          DBI::dbExecute(conn, sql)
        } else {
          DBI::dbExecute(conn, sql, params = params)
        }
      }, metadata = list(sql_preview = substr(sql, 1, 100)))
    },

    #' @description
    #' Begin a database transaction
    #' @param conn Database connection
    begin = function(conn) {
      DBI::dbBegin(conn)
    },

    #' @description
    #' Commit a database transaction
    #' @param conn Database connection
    commit = function(conn) {
      DBI::dbCommit(conn)
    },

    #' @description
    #' Rollback a database transaction
    #' @param conn Database connection
    rollback = function(conn) {
      DBI::dbRollback(conn)
    },

    #' @description
    #' Execute code within a transaction with automatic rollback on error
    #' @param conn Database connection
    #' @param code Code to execute within transaction
    #' @return Result of code execution
    transaction = function(conn, code) {
      self$begin(conn)
      tryCatch(
        {
          result <- force(code)
          self$commit(conn)
          result
        },
        error = function(e) {
          self$rollback(conn)
          stop(e)
        }
      )
    },

    #' @description
    #' Get SQL dialect information for this backend
    #' @return List with dialect-specific SQL fragments
    dialect = function() {
      stop("Subclass must implement dialect()")
    },

    #' @description
    #' Check if this backend supports encryption
    #' @return Logical TRUE if encryption is supported
    supports_encryption = function() {
      FALSE
    },

    #' @description
    #' Check if a table exists in the database
    #' @param conn Database connection
    #' @param table_name Name of table to check
    #' @return Logical TRUE if table exists
    table_exists = function(conn, table_name) {
      DBI::dbExistsTable(conn, table_name)
    },

    #' @description
    #' List all tables in the database
    #' @param conn Database connection
    #' @return Character vector of table names
    list_tables = function(conn) {
      DBI::dbListTables(conn)
    },

    #' @description
    #' Get the backend type name
    #' @return Character string identifying the backend
    backend_name = function() {
      stop("Subclass must implement backend_name()")
    }
  )
)


#' Create Database Adapter from Configuration
#'
#' Factory function that creates the appropriate database adapter based on
#' the db_backend setting in the configuration.
#'
#' @param config Configuration list containing at minimum:
#'   - db_backend: One of "sqlite", "duckdb", "postgresql", "postgres",
#'     "clickhouse"
#'   - Backend-specific settings (see individual adapter documentation)
#'
#' @return DatabaseAdapter subclass instance
#'
#' @details
#' Supported backends:
#' - "sqlite": Creates SQLiteAdapter, requires sqlite$path
#' - "duckdb": Creates DuckDBAdapter, requires duckdb$path
#' - "postgresql" or "postgres": Creates PostgreSQLAdapter, requires
#'   postgresql$host, postgresql$name, postgresql$user, postgresql$password
#' - "clickhouse": Creates ClickHouseAdapter, requires clickhouse$host,
#'   clickhouse$database
#'
#' @examples
#' \dontrun{
#'   # SQLite configuration
#'   config <- list(
#'     db_backend = "sqlite",
#'     sqlite = list(path = "data/zzedc.db")
#'   )
#'   adapter <- create_db_adapter(config)
#'
#'   # DuckDB configuration
#'   config <- list(
#'     db_backend = "duckdb",
#'     duckdb = list(path = "data/zzedc.duckdb")
#'   )
#'   adapter <- create_db_adapter(config)
#'
#'   # PostgreSQL configuration
#'   config <- list(
#'     db_backend = "postgresql",
#'     postgresql = list(
#'       host = "localhost",
#'       port = 5432,
#'       name = "zzedc",
#'       user = "zzedc_user",
#'       password = "secret"
#'     )
#'   )
#'   adapter <- create_db_adapter(config)
#'
#'   # ClickHouse configuration
#'   config <- list(
#'     db_backend = "clickhouse",
#'     clickhouse = list(
#'       host = "localhost",
#'       port = 8123,
#'       database = "zzedc",
#'       user = "default"
#'     )
#'   )
#'   adapter <- create_db_adapter(config)
#' }
#'
#' @export
create_db_adapter <- function(config) {
  backend <- config$db_backend %||% "sqlite"

  switch(
    tolower(backend),
    sqlite     = SQLiteAdapter$new(config),
    duckdb     = DuckDBAdapter$new(config),
    postgresql = PostgreSQLAdapter$new(config),
    postgres   = PostgreSQLAdapter$new(config),
    clickhouse = ClickHouseAdapter$new(config),
    mysql      = MySQLAdapter$new(config),
    mariadb    = MySQLAdapter$new(config),
    stop("Unsupported database backend: ", backend,
         "\nSupported backends: sqlite, duckdb, postgresql, ",
         "clickhouse, mysql")
  )
}


# Null coalescing operator (returns x if not NULL, otherwise y)
#' @importFrom R6 R6Class
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}


#' Extract SQL Operation Name for Profiling
#'
#' Parses SQL to extract a short operation name for profiling labels.
#'
#' @param sql SQL statement string
#' @return Character string like "SELECT:subjects" or "INSERT:audit_trail"
#'
#' @keywords internal
extract_sql_operation <- function(sql) {
  sql_clean <- trimws(toupper(sql))

  # Extract SQL verb
verb <- if (grepl("^SELECT", sql_clean)) {
    "SELECT"
  } else if (grepl("^INSERT", sql_clean)) {
    "INSERT"
  } else if (grepl("^UPDATE", sql_clean)) {
    "UPDATE"
  } else if (grepl("^DELETE", sql_clean)) {
    "DELETE"
  } else if (grepl("^CREATE", sql_clean)) {
    "CREATE"
  } else if (grepl("^DROP", sql_clean)) {
    "DROP"
  } else if (grepl("^ALTER", sql_clean)) {
    "ALTER"
  } else {
    "OTHER"
  }

  # Try to extract table name
  table_match <- regmatches(
    sql_clean,
    regexpr("(FROM|INTO|UPDATE|TABLE)\\s+([A-Z_][A-Z0-9_]*)", sql_clean)
  )

  if (length(table_match) > 0 && nchar(table_match) > 0) {
    table_name <- gsub("^(FROM|INTO|UPDATE|TABLE)\\s+", "", table_match)
    table_name <- tolower(table_name)
    paste0(verb, ":", table_name)
  } else {
    verb
  }
}
