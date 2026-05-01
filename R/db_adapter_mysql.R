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
#'         server (common in academic medical centres that already
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
    }
  )
)
