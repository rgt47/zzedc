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
      install_pg_placeholder_shim()
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
      install_pg_placeholder_shim()

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
        },

        # Date difference in days (col_a - col_b)
        date_diff_days = function(col_a, col_b) {
          sprintf("(%s::date - %s::date)", col_a, col_b)
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
    #' Describe a table's columns via `information_schema.columns`
    #' (PostgreSQL has no `PRAGMA table_info` equivalent)
    #' @param conn Database connection
    #' @param table_name Name of table to describe
    #' @return Data frame with columns `name`, `type`, `notnull`, `pk`
    describe_table = function(conn, table_name) {
      cols <- DBI::dbGetQuery(conn, "
        SELECT column_name AS name, data_type AS type,
               (is_nullable = 'NO') AS notnull
        FROM information_schema.columns
        WHERE table_name = $1
        ORDER BY ordinal_position
      ", params = list(table_name))

      pk_cols <- DBI::dbGetQuery(conn, "
        SELECT a.attname AS name
        FROM pg_index i
        JOIN pg_attribute a
          ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = $1::regclass AND i.indisprimary
      ", params = list(table_name))

      cols$pk <- cols$name %in% pk_cols$name
      cols
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


#' Translate Positional `?` Placeholders to PostgreSQL's `$n` Syntax
#'
#' Every one of this package's ~40 "legacy API" files (everything
#' that writes to the database outside the `DatabaseAdapter` classes
#' themselves) was written using the `?` placeholder convention --
#' the one SQLite, DuckDB, and MySQL/MariaDB all accept natively via
#' DBI. PostgreSQL's driver (`RPostgres`) does not translate `?`; it
#' requires `$1, $2, ...` and raises a syntax error otherwise
#' ("syntax error at or near ','"), confirmed directly against a live
#' PostgreSQL 15 container with a minimal repro outside this
#' package's own code. Rewriting several thousand call sites across
#' ~34 files to use `$n` directly was judged not worth the risk/churn
#' when the translation can instead be applied once, at the
#' connection boundary -- see `install_pg_placeholder_shim()`.
#'
#' This walks the SQL string once, replacing each `?` that is not
#' inside a single-quoted string literal with the next `$n`, left to
#' right (handling a doubled `''` as an escaped quote inside a
#' literal, so a help-text value like `'it''s required'` is not
#' mistaken for the end of a string). It relies on the same
#' assumption DBI's own positional-parameter binding already makes:
#' the number of `?` outside string literals equals `length(params)`.
#'
#' @param sql Character: SQL text using `?` placeholders
#' @return Character: the same SQL with `$1, $2, ...` in their place
#' @keywords internal
translate_pg_placeholders <- function(sql) {
  if (!grepl("?", sql, fixed = TRUE)) return(sql)

  chars <- strsplit(sql, "", fixed = TRUE)[[1]]
  out <- character(length(chars))
  in_string <- FALSE
  n <- 0L
  i <- 1L
  len <- length(chars)

  while (i <= len) {
    ch <- chars[i]
    if (ch == "'") {
      if (in_string && i < len && chars[i + 1] == "'") {
        out[i] <- "''"
        i <- i + 2L
        next
      }
      in_string <- !in_string
      out[i] <- ch
      i <- i + 1L
      next
    }
    if (ch == "?" && !in_string) {
      n <- n + 1L
      out[i] <- paste0("$", n)
    } else {
      out[i] <- ch
    }
    i <- i + 1L
  }

  paste(out, collapse = "")
}


#' Install the PostgreSQL Placeholder-Translation Shim
#'
#' Overrides `DBI::dbExecute()`/`dbGetQuery()`/`dbSendQuery()`/
#' `dbSendStatement()` for RPostgres's `PqConnection` class so that
#' every call through them translates `?` placeholders to `$n` first
#' (see `translate_pg_placeholders()`), then delegates to RPostgres's
#' own original method. This is a deliberate, session-wide override
#' of a generic/class combination owned by another package (the
#' standard R mechanism for extending a method you do not own) rather
#' than a `PostgreSQLAdapter`-local fix, because the ~2,100 call
#' sites that need this connect via `connect_encrypted_db()` and call
#' `DBI::dbExecute()`/`dbGetQuery()` directly on the raw connection,
#' never through the adapter's own `execute()`/`query()` wrappers.
#'
#' Idempotent and safe to call on every `connect()`/`pool()`: it
#' installs at most once per session (`.pg_placeholder_shim_env$done`
#' guards it), and does nothing if `RPostgres` is not installed or
#' does not define the expected methods (a version mismatch would
#' make this a no-op rather than an error, leaving the pre-shim
#' "syntax error at or near ..." failure mode, not a new one).
#'
#' @return `invisible(NULL)`
#' @keywords internal
install_pg_placeholder_shim <- function() {
  if (isTRUE(.pg_placeholder_shim_env$done)) return(invisible(NULL))
  if (!requireNamespace("RPostgres", quietly = TRUE)) return(invisible(NULL))
  if (!requireNamespace("methods", quietly = TRUE)) return(invisible(NULL))

  # RPostgres defines a PqConnection-specific method only for
  # dbSendQuery(conn) (dispatching on `conn` alone, signature
  # "PqConnection" -- confirmed via showMethods(); RPostgres does not
  # define PqConnection-specific dbExecute/dbGetQuery/dbSendStatement
  # methods at all). DBI's own default dbGetQuery/dbExecute methods
  # for DBIConnection are composed from dbSendQuery (or
  # dbSendStatement, which for Postgres resolves the same way) +
  # dbBind + dbFetch/dbGetRowsAffected + dbClearResult, so overriding
  # this one hook point covers every call site that goes through
  # dbExecute() or dbGetQuery() too -- confirmed directly against a
  # live PostgreSQL container, not just inferred from the dispatch
  # chain.
  if (!methods::existsMethod("dbSendQuery", "PqConnection")) {
    return(invisible(NULL))
  }
  orig <- methods::getMethod("dbSendQuery", "PqConnection")
  # `where = globalenv()` avoids "the environment 'zzedc' is locked":
  # setMethod() needs a method-table environment it can write to,
  # and a loaded package's own namespace is locked once attached
  # (whether loaded via library() or pkgload::load_all()). Passing
  # the generic as a function object (DBI::dbSendQuery), not its
  # name, avoids a second error ("no existing definition for
  # function 'dbSendQuery'") that setMethod raises when looking the
  # name up relative to `where` and DBI is only loaded via
  # requireNamespace(), not attached to the search path.
  methods::setMethod(DBI::dbSendQuery, "PqConnection", function(conn, statement, ...) {
    orig(conn, translate_pg_placeholders(statement), ...)
  }, where = globalenv())

  .pg_placeholder_shim_env$done <- TRUE
  invisible(NULL)
}

.pg_placeholder_shim_env <- new.env(parent = emptyenv())
.pg_placeholder_shim_env$done <- FALSE
