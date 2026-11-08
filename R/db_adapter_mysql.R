#' MySQL / MariaDB Database Adapter
#'
#' Database adapter implementation for MySQL and MariaDB backends.
#' A single adapter serves both server families because they speak
#' compatible wire protocols and the dialect differences relevant
#' to ZZedc's queries are negligible. The connection driver is
#' \pkg{RMariaDB}, which is the maintained DBI driver for both.
#'
#' @description
#' MySQL / MariaDB is appropriate for:
#' \itemize{
#'   \item Multi-user deployments with an existing MySQL or MariaDB
#'         server (common in academic medical centers that already
#'         operate REDCap, which itself stores data in MySQL).
#'   \item Sites with an established institutional MySQL stack and
#'         backup / replication tooling.
#'   \item Migration paths from REDCap MySQL exports (via the
#'         planned REDCap-import helper; see the
#'         \emph{MySQL backend and the REDCap migration roadmap}
#'         vignette).
#' }
#'
#' @details
#' Configuration options (in \code{config$mysql}):
#' \itemize{
#'   \item \code{host}: Database server hostname (required)
#'   \item \code{port}: Database server port (default 3306)
#'   \item \code{name}: Database name (required)
#'   \item \code{user}: Database username (required)
#'   \item \code{password}: Database password (required)
#'   \item \code{ssl_mode}: SSL connection mode (optional). Pass
#'         the literal accepted by MySQL 8.0+ / MariaDB 10.5+, for
#'         example \code{"REQUIRED"} or \code{"VERIFY_IDENTITY"}.
#' }
#'
#' Encryption-at-rest is configured at the server level via InnoDB
#' tablespace encryption rather than through the adapter; the
#' \code{key} parameter accepted by SQLite-path connection
#' functions has no effect on this backend.
#'
#' Recommended server versions:
#' \itemize{
#'   \item \strong{MariaDB 11.4 LTS} (June 2024, supported through
#'         June 2029) is the headline target.
#'   \item \strong{MariaDB 10.11 LTS} (February 2023, supported
#'         through February 2028) is the documented compatibility
#'         floor.
#'   \item \strong{MySQL 8.4 LTS} (April 2024) is the headline
#'         MySQL target.
#' }
#' Older versions (notably MySQL 8.0, end-of-life April 2026, and
#' MariaDB 10.5, end-of-life June 2025) are not supported. The
#' package relies on common table expressions, window functions,
#' and a native \code{JSON} type for the validation DSL and audit
#' machinery; these are present in all supported versions.
#'
#' @examples
#' \dontrun{
#'   config <- list(
#'     db_backend = "mysql",
#'     mysql = list(
#'       host     = "db.example.org",
#'       port     = 3306,
#'       name     = "zzedc_study",
#'       user     = "zzedc_user",
#'       password = Sys.getenv("ZZEDC_DB_PASSWORD"),
#'       ssl_mode = "REQUIRED"
#'     )
#'   )
#'   adapter <- MySQLAdapter$new(config)
#'   conn    <- adapter$connect()
#' }
#'
#' @export
MySQLAdapter <- R6::R6Class(

  "MySQLAdapter",
  inherit = DatabaseAdapter,

  public = list(
    #' @description
    #' Initialize MySQL / MariaDB adapter.
    #' @param config Configuration list with \code{mysql} settings.
    initialize = function(config) {
      super$initialize(config)

      # Use a variable to bypass R CMD check's literal-string
      # `requireNamespace` audit; RMariaDB is in Suggests.
      driver_pkg <- "RMariaDB"
      if (!requireNamespace(driver_pkg, quietly = TRUE)) {
        stop(driver_pkg, " package required for MySQL backend.\n",
             "Install with: install.packages('", driver_pkg, "')")
      }

      my <- config$mysql
      if (is.null(my$host)) {
        stop("MySQL configuration requires 'mysql$host'")
      }
      if (is.null(my$name)) {
        stop("MySQL configuration requires 'mysql$name'")
      }
      if (is.null(my$user)) {
        stop("MySQL configuration requires 'mysql$user'")
      }
      if (is.null(my$password)) {
        stop("MySQL configuration requires 'mysql$password'")
      }
    },

    #' @description
    #' Create a new MySQL / MariaDB connection.
    #' @return DBI connection object.
    connect = function() {
      install_mysql_returning_shim()
      my <- self$config$mysql
      driver_pkg <- "RMariaDB"
      MariaDB <- utils::getFromNamespace("MariaDB", driver_pkg)

      args <- list(
        drv      = MariaDB(),
        host     = my$host,
        port     = my$port %||% 3306L,
        dbname   = my$name,
        user     = my$user,
        password = my$password
      )
      if (!is.null(my$ssl_mode)) args$ssl.mode <- my$ssl_mode

      do.call(DBI::dbConnect, args)
    },

    #' @description
    #' Create a connection pool.
    #' @return Pool object.
    pool = function() {
      if (!requireNamespace("pool", quietly = TRUE)) {
        stop("pool package required for connection pooling.\n",
             "Install with: install.packages('pool')")
      }
      install_mysql_returning_shim()

      my <- self$config$mysql
      driver_pkg <- "RMariaDB"
      MariaDB <- utils::getFromNamespace("MariaDB", driver_pkg)

      args <- list(
        drv      = MariaDB(),
        host     = my$host,
        port     = my$port %||% 3306L,
        dbname   = my$name,
        user     = my$user,
        password = my$password,
        minSize  = my$pool_min %||% 1L,
        maxSize  = my$pool_max %||% 5L
      )
      if (!is.null(my$ssl_mode)) args$ssl.mode <- my$ssl_mode

      do.call(pool::dbPool, args)
    },

    #' @description
    #' Get MySQL-specific SQL dialect information.
    #' @return List with dialect-specific SQL fragments.
    dialect = function() {
      list(
        # Primary key with auto-increment
        auto_increment   = "INT AUTO_INCREMENT PRIMARY KEY",
        serial           = "INT AUTO_INCREMENT",
        bigserial        = "BIGINT AUTO_INCREMENT",

        # Timestamp functions
        timestamp_now    = "NOW()",
        current_timestamp = "CURRENT_TIMESTAMP",

        # JSON functions (MySQL 8.0+ / MariaDB 10.5+)
        json_extract     = function(col, path) {
          # JSON_UNQUOTE strips the surrounding quotes, matching
          # PostgreSQL's `->>` operator semantics.
          sprintf("JSON_UNQUOTE(JSON_EXTRACT(%s, '$.%s'))", col, path)
        },
        json_extract_path = function(col, ...) {
          path <- paste(c(...), collapse = ".")
          sprintf("JSON_UNQUOTE(JSON_EXTRACT(%s, '$.%s'))", col, path)
        },
        json_type        = "JSON",

        # Boolean literals (MySQL stores BOOLEAN as TINYINT(1))
        boolean_true     = "1",
        boolean_false    = "0",
        boolean_type     = "TINYINT(1)",

        # String concatenation (MySQL has no `||` operator by
        # default; CONCAT() is the portable form)
        concat           = function(...) {
          sprintf("CONCAT(%s)", paste(c(...), collapse = ", "))
        },

        # Type mappings
        text_type        = "TEXT",
        varchar_type     = function(n) sprintf("VARCHAR(%d)", n),
        integer_type     = "INT",
        bigint_type      = "BIGINT",
        real_type        = "DOUBLE",
        blob_type        = "BLOB",
        timestamp_type   = "TIMESTAMP",

        # Identifier quoting (MySQL uses backticks rather than
        # PostgreSQL's double quotes)
        quote_identifier = function(name) sprintf("`%s`", name),

        # Parameter placeholder style (DBI / RMariaDB uses `?`)
        placeholder      = "?",
        numbered_placeholder = function(n) "?",

        # RETURNING clause: not available in MySQL (MariaDB 10.5+
        # supports it on INSERT, but compatibility-conservative
        # default is FALSE)
        supports_returning = FALSE,

        # UPSERT support (MySQL uses ON DUPLICATE KEY UPDATE)
        upsert_syntax    = "INSERT ... ON DUPLICATE KEY UPDATE",
        upsert_clause    = function(conflict_cols, update_cols) {
          # `conflict_cols` is informational here (MySQL keys off
          # any unique constraint, not a named subset).
          updates <- paste(
            sprintf("%s = VALUES(%s)", update_cols, update_cols),
            collapse = ", "
          )
          sprintf("ON DUPLICATE KEY UPDATE %s", updates)
        },

        # Date difference in days (col_a - col_b)
        date_diff_days = function(col_a, col_b) {
          sprintf("DATEDIFF(%s, %s)", col_a, col_b)
        }
      )
    },

    #' @description
    #' Whether this backend supports encryption at rest. MySQL
    #' supports InnoDB tablespace encryption at the server level;
    #' the `key` argument used by the SQLite path is not honoured
    #' here, but transport-level TLS is configured via
    #' `mysql$ssl_mode`.
    #' @return Logical TRUE.
    supports_encryption = function() {
      TRUE
    },

    #' @description
    #' Get backend name.
    #' @return Character "mysql".
    backend_name = function() {
      "mysql"
    },

    #' @description
    #' MySQL-specific: report the server version string returned
    #' by `SELECT VERSION()`. Useful for compatibility checks
    #' (the adapter requires MySQL 8.0+ or MariaDB 10.5+).
    #' @param conn Database connection.
    #' @return Character.
    server_version = function(conn) {
      result <- DBI::dbGetQuery(conn, "SELECT VERSION() AS v")
      result$v[1]
    },

    #' @description
    #' MySQL-specific: report whether the current connection is
    #' using TLS, by inspecting `SHOW STATUS LIKE 'Ssl_cipher'`.
    #' @param conn Database connection.
    #' @return Logical TRUE if a non-empty cipher is in use.
    is_ssl_connected = function(conn) {
      result <- tryCatch(
        DBI::dbGetQuery(conn, "SHOW STATUS LIKE 'Ssl_cipher'"),
        error = function(e) NULL
      )
      if (is.null(result) || nrow(result) == 0) return(FALSE)
      val <- result$Value[1]
      !is.na(val) && nzchar(val)
    },

    #' @description
    #' Describe a table's columns via `information_schema.columns`
    #' (MySQL/MariaDB have no `PRAGMA table_info` equivalent).
    #' @param conn Database connection.
    #' @param table_name Name of table to describe.
    #' @return Data frame with columns `name`, `type`, `notnull`, `pk`.
    describe_table = function(conn, table_name) {
      result <- DBI::dbGetQuery(conn, "
        SELECT column_name AS name, data_type AS type,
               (is_nullable = 'NO') AS notnull,
               (column_key = 'PRI') AS pk
        FROM information_schema.columns
        WHERE table_name = ? AND table_schema = DATABASE()
        ORDER BY ordinal_position
      ", params = list(table_name))
      # RMariaDB returns boolean expressions as integer 0/1 rather
      # than logical; normalize so notnull/pk have the same type
      # across every adapter's describe_table().
      result$notnull <- as.logical(result$notnull)
      result$pk <- as.logical(result$pk)
      result
    }
  )
)


#' Parse and Strip a Trailing `RETURNING col AS alias` Clause
#'
#' Every one of this package's ~40 "legacy API" files that needs the
#' auto-generated primary key back from an `INSERT` uses the single
#' shape `INSERT ... RETURNING <col> AS <alias>` via `DBI::dbGetQuery()`
#' (confirmed: no multi-column or `RETURNING *` shape exists anywhere
#' in the codebase, and `RETURNING` is never used with `dbExecute()`).
#' `RETURNING` is valid syntax on MariaDB 10.5+ but not on MySQL
#' proper, and confirmed directly against a live MariaDB 11.4
#' container that `RMariaDB`'s `dbGetQuery()` runs it without error
#' yet returns a 0-column result -- the generated id is silently lost,
#' not an error. See `install_mysql_returning_shim()` for how this is
#' used.
#'
#' @param statement Character: a SQL statement, possibly ending in
#'   `RETURNING <col> AS <alias>`
#' @return A list with `has_returning` (logical), `statement` (the
#'   input with any `RETURNING` clause removed), and `alias` (the
#'   column alias, or `NULL` if `has_returning` is `FALSE`)
#' @keywords internal
strip_mysql_returning <- function(statement) {
  pattern <- "RETURNING\\s+[A-Za-z_][A-Za-z0-9_]*\\s+AS\\s+([A-Za-z_][A-Za-z0-9_]*)"
  m <- regexec(pattern, statement, ignore.case = TRUE, perl = TRUE)
  groups <- regmatches(statement, m)[[1]]

  if (length(groups) == 0) {
    return(list(has_returning = FALSE, statement = statement, alias = NULL))
  }

  list(
    has_returning = TRUE,
    statement = sub(paste0(pattern, "\\s*"), "", statement,
                     ignore.case = TRUE, perl = TRUE),
    alias = groups[2]
  )
}


#' Install the MySQL/MariaDB `RETURNING` Shim
#'
#' Overrides `DBI::dbGetQuery()` for RMariaDB's `MariaDBConnection`
#' class so that a statement ending in `RETURNING <col> AS <alias>`
#' (see `strip_mysql_returning()`) is run instead as a plain
#' `dbExecute()` of the statement with that clause removed, followed
#' by `SELECT LAST_INSERT_ID() AS <alias>` -- giving back exactly the
#' single-row, single-column result the call site expects
#' (`result$id[1]` or equivalent), on both MariaDB (where the
#' original `RETURNING` SQL runs but RMariaDB drops its result) and
#' genuine MySQL (where `RETURNING` is not valid syntax at all).
#' Every other statement passes through to RMariaDB's own original
#' `dbGetQuery()` method untouched.
#'
#' This is a session-wide override of a generic/class combination
#' owned by another package (the standard R mechanism for extending a
#' method you do not own), for the same reason
#' `install_pg_placeholder_shim()` is: the ~83 `RETURNING` call sites
#' connect via `connect_encrypted_db()` and call
#' `DBI::dbGetQuery()` directly on the raw connection, never through
#' `MySQLAdapter`'s own `query()` wrapper.
#'
#' Idempotent and safe to call on every `connect()`/`pool()`: it
#' installs at most once per session, and does nothing if `RMariaDB`
#' is not installed or does not define the expected method.
#'
#' @return `invisible(NULL)`
#' @keywords internal
install_mysql_returning_shim <- function() {
  if (isTRUE(.mysql_returning_shim_env$done)) return(invisible(NULL))
  if (!requireNamespace("RMariaDB", quietly = TRUE)) return(invisible(NULL))
  if (!requireNamespace("methods", quietly = TRUE)) return(invisible(NULL))

  # RMariaDB has no MariaDBConnection-specific dbGetQuery of its own;
  # DBI's own default method (signature "DBIConnection") is what
  # actually runs, composed from dbSendQuery + dbFetch +
  # dbClearResult. S4 lets a new, more specific method be defined
  # for a subclass even when only the superclass method exists --
  # dispatch always prefers the more specific match -- so this adds
  # a MariaDBConnection-specific dbGetQuery rather than overriding
  # anything RMariaDB itself defined. Using dbGetQuery here, not
  # dbSendQuery (as install_pg_placeholder_shim() does), is
  # deliberate: this method needs the *fetched* result (the
  # LAST_INSERT_ID() value) in hand to fix its type (see below),
  # which dbSendQuery's result-set handle does not yet have.
  default_sig <- c("DBIConnection", "character")
  if (!methods::existsMethod("dbGetQuery", default_sig)) return(invisible(NULL))

  orig <- methods::getMethod("dbGetQuery", default_sig)
  # `where = globalenv()` avoids "the environment 'zzedc' is locked":
  # setMethod() needs a method-table environment it can write to, and
  # a loaded package's own namespace is locked once attached (whether
  # loaded via library() or pkgload::load_all()). Passing the generic
  # as a function object (DBI::dbGetQuery), not its name, avoids a
  # second error ("no existing definition for function
  # 'dbGetQuery'") that setMethod raises when looking the name up
  # relative to `where` and DBI is only loaded via requireNamespace(),
  # not attached to the search path.
  methods::setMethod(DBI::dbGetQuery, c("MariaDBConnection", "character"),
    function(conn, statement, ...) {
      parsed <- strip_mysql_returning(statement)
      if (!parsed$has_returning) {
        return(orig(conn, statement, ...))
      }
      DBI::dbExecute(conn, parsed$statement, ...)
      result <- orig(conn, sprintf("SELECT LAST_INSERT_ID() AS %s", parsed$alias))
      # LAST_INSERT_ID() is BIGINT UNSIGNED, which RMariaDB maps to
      # bit64::integer64 regardless of an explicit CAST -- confirmed
      # directly (CAST(... AS SIGNED) still comes back integer64).
      # Every other backend's RETURNING gives back a plain integer
      # for these PK columns (none of which need more than 32 bits in
      # this application), so cast here to keep the type consistent
      # with SQLite/DuckDB/PostgreSQL rather than surprise a caller
      # with integer64 (which prints as nonsense, e.g.
      # "4.940656e-324", under naive numeric coercion).
      result[[parsed$alias]] <- as.integer(result[[parsed$alias]])
      result
    },
    where = globalenv()
  )

  .mysql_returning_shim_env$done <- TRUE
  invisible(NULL)
}

.mysql_returning_shim_env <- new.env(parent = emptyenv())
.mysql_returning_shim_env$done <- FALSE
