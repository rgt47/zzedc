#' PostgreSQL Database Adapter
#'
#' Database adapter implementation for PostgreSQL backend.
#'
#' @description
#' PostgreSQL is recommended for:
#' - Multi-server deployments with load balancing
#' - AWS RDS or managed cloud database services
#' - Enterprise deployments requiring centralized database
#'
#' @details
#' Configuration options (in config$postgresql):
#' - host: Database server hostname (required)
#' - port: Database server port (default 5432)
#' - name: Database name (required)
#' - user: Database username (required)
#' - password: Database password (required)
#' - sslmode: SSL connection mode (optional, e.g., "require")
#'
#' @examples
#' \dontrun{
#'   config <- list(
#'     db_backend = "postgresql",
#'     postgresql = list(
#'       host = "localhost",
#'       port = 5432,
#'       name = "zzedc",
#'       user = "zzedc_user",
#'       password = Sys.getenv("ZZEDC_DB_PASSWORD")
#'     )
#'   )
#'   adapter <- PostgreSQLAdapter$new(config)
#'   conn <- adapter$connect()
#' }
#'
#' @export
PostgreSQLAdapter <- R6::R6Class(

  "PostgreSQLAdapter",
  inherit = DatabaseAdapter,

  public = list(
    #' @description
    #' Initialize PostgreSQL adapter
    #' @param config Configuration list with postgresql settings
    initialize = function(config) {
      super$initialize(config)

      if (!requireNamespace("RPostgres", quietly = TRUE)) {
        stop("RPostgres package required for PostgreSQL backend.\n",
             "Install with: install.packages('RPostgres')")
      }

      # Validate configuration
      pg <- config$postgresql
      if (is.null(pg$host)) {
        stop("PostgreSQL configuration requires 'postgresql$host'")
      }
      if (is.null(pg$name)) {
        stop("PostgreSQL configuration requires 'postgresql$name'")
      }
      if (is.null(pg$user)) {
        stop("PostgreSQL configuration requires 'postgresql$user'")
      }
      if (is.null(pg$password)) {
        stop("PostgreSQL configuration requires 'postgresql$password'")
      }
    },

    #' @description
    #' Create a new PostgreSQL connection
    #' @return DBI connection object
    connect = function() {
      pg <- self$config$postgresql

      conn <- DBI::dbConnect(
        RPostgres::Postgres(),
        host = pg$host,
        port = pg$port %||% 5432L,
        dbname = pg$name,
        user = pg$user,
        password = pg$password,
        sslmode = pg$sslmode
      )

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

      pg <- self$config$postgresql

      pool::dbPool(
        RPostgres::Postgres(),
        host = pg$host,
        port = pg$port %||% 5432L,
        dbname = pg$name,
        user = pg$user,
        password = pg$password,
        sslmode = pg$sslmode,
        minSize = pg$pool_min %||% 1L,
        maxSize = pg$pool_max %||% 5L
      )
    },

    #' @description
    #' Get PostgreSQL-specific SQL dialect information
    #' @return List with dialect-specific SQL fragments
    dialect = function() {
      list(
        # Primary key with auto-increment
        auto_increment = "SERIAL PRIMARY KEY",
        serial = "SERIAL",
        bigserial = "BIGSERIAL",

        # Timestamp functions
        timestamp_now = "NOW()",
        current_timestamp = "CURRENT_TIMESTAMP",

        # JSON functions (PostgreSQL has excellent JSON support)
        json_extract = function(col, path) {
          sprintf("%s->>'%s'", col, path)
        },
        json_extract_path = function(col, ...) {
          paths <- paste(sprintf("'%s'", c(...)), collapse = ", ")
          sprintf("jsonb_extract_path_text(%s, %s)", col, paths)
        },
        json_type = "JSONB",

        # Boolean literals
        boolean_true = "TRUE",
        boolean_false = "FALSE",
        boolean_type = "BOOLEAN",

        # String concatenation
        concat = function(...) {
          sprintf("CONCAT(%s)", paste(c(...), collapse = ", "))
        },

        # Type mappings
        text_type = "TEXT",
        varchar_type = function(n) sprintf("VARCHAR(%d)", n),
        integer_type = "INTEGER",
        bigint_type = "BIGINT",
        real_type = "DOUBLE PRECISION",
        blob_type = "BYTEA",
        timestamp_type = "TIMESTAMP WITH TIME ZONE",

        # Parameter placeholder style (PostgreSQL uses $1, $2, ...)
        placeholder = "$1",
        numbered_placeholder = function(n) sprintf("$%d", n),

        # RETURNING clause support
        supports_returning = TRUE,

        # UPSERT support (PostgreSQL uses ON CONFLICT)
        upsert_syntax = "INSERT ... ON CONFLICT",
        upsert_clause = function(conflict_cols, update_cols) {
          conflict <- paste(conflict_cols, collapse = ", ")
          updates <- paste(
            sprintf("%s = EXCLUDED.%s", update_cols, update_cols),
            collapse = ", "
          )
          sprintf("ON CONFLICT (%s) DO UPDATE SET %s", conflict, updates)
        }
      )
    },

    #' @description
    #' Check if encryption is supported
    #' @return Logical TRUE (PostgreSQL supports SSL/TLS)
    supports_encryption = function() {
      TRUE
    },

    #' @description
    #' Get backend name
    #' @return Character "postgresql"
    backend_name = function() {
      "postgresql"
    },

    #' @description
    #' PostgreSQL-specific: Check if connected via SSL

    #' @param conn Database connection
    #' @return Logical TRUE if using SSL
    is_ssl_connected = function(conn) {
      result <- DBI::dbGetQuery(conn, "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")
      if (nrow(result) == 0) FALSE else result$ssl[1]
    },

    #' @description
    #' PostgreSQL-specific: Get server version
    #' @param conn Database connection
    #' @return Character string with PostgreSQL version
    server_version = function(conn) {
      result <- DBI::dbGetQuery(conn, "SELECT version()")
      result$version[1]
    },

    #' @description
    #' PostgreSQL-specific: LISTEN for notifications
    #' @param conn Database connection
    #' @param channel Channel name to listen on
    listen = function(conn, channel) {
      DBI::dbExecute(conn, sprintf("LISTEN %s", channel))
    },

    #' @description
    #' PostgreSQL-specific: NOTIFY a channel
    #' @param conn Database connection
    #' @param channel Channel name
    #' @param payload Optional payload string
    notify = function(conn, channel, payload = NULL) {
      if (is.null(payload)) {
        DBI::dbExecute(conn, sprintf("NOTIFY %s", channel))
      } else {
        DBI::dbExecute(conn, sprintf("NOTIFY %s, '%s'", channel, payload))
      }
    },

    #' @description
    #' PostgreSQL-specific: Create index concurrently (non-blocking)
    #' @param conn Database connection
    #' @param table_name Table name
    #' @param index_name Index name
    #' @param columns Column names
    create_index_concurrent = function(conn, table_name, index_name, columns) {
      cols <- paste(columns, collapse = ", ")
      sql <- sprintf("CREATE INDEX CONCURRENTLY IF NOT EXISTS %s ON %s (%s)",
                     index_name, table_name, cols)
      DBI::dbExecute(conn, sql)
    }
  )
)
