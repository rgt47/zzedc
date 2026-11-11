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
#' - encryption_key: Encrypts the database file when set (optional)
#' - extension_directory: Persistent directory for DuckDB extensions
#'   (optional). Without it, the R duckdb package uses a per-session
#'   temporary directory, so extensions are downloaded again in every
#'   session. Populate it in advance with `install_duckdb_extensions()`.
#' - allow_extension_download: Whether DuckDB may download missing
#'   extensions at runtime (optional). Defaults to `FALSE` under the
#'   `regulated` security profile, where downloading unpinned code into
#'   a validated system is a change-control concern, and `TRUE`
#'   otherwise.
#'
#' Extensions are loaded when a connection opens: `httpfs` (needed for
#' an encrypted file) and `icu` (needed by `CURRENT_DATE` in deadline
#' queries). When downloads are disallowed, a missing extension is an
#' error at connection time, not at the first query that needs it.
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
    #' Create a new DuckDB connection. If `config$duckdb$encryption_key`
    #' is set, the database file is opened encrypted via
    #' `ATTACH ... (ENCRYPTION_KEY ...)` rather than a direct `dbdir`
    #' connection: DuckDB rejects a wrong key with an error (verified
    #' in `docs/db-adapter-remediation-plan-2026-11-07.md`), and all
    #' existing unqualified table references resolve against the
    #' attached database with no call-site changes.
    #'
    #' Every connection from this adapter, including those of its
    #' `pool()`, comes from one shared DuckDB instance. Separate
    #' instances in one R process can each attach the same file, and
    #' DuckDB's file lock (an operating-system lock, held per process)
    #' does not stop them writing concurrently. Before 2026-11-10 each
    #' call created its own instance, so a package function called by
    #' the application (through `connect_encrypted_db()`) wrote to the
    #' study file through a second instance while the application's pool
    #' held it through another.
    #' @return DBI connection object
    connect = function() {
      conn <- DBI::dbConnect(private$driver())
      private$prepare_connection(conn)
      conn
    },

    #' @description
    #' Create a connection pool on this adapter's shared DuckDB instance
    #' (see `connect()`).
    #' @return Pool object
    pool = function() {
      if (!requireNamespace("pool", quietly = TRUE)) {
        stop("pool package required for connection pooling.\n",
             "Install with: install.packages('pool')")
      }
      pool::dbPool(
        private$driver(),
        minSize = self$config$duckdb$pool_min %||% 1,
        maxSize = self$config$duckdb$pool_max %||% Inf,
        onCreate = function(conn) private$prepare_connection(conn)
      )
    },

    #' @description
    #' Close a connection. The shared instance stays open for this
    #' adapter's other connections; see `shutdown()`.
    #' @param conn Database connection
    disconnect = function(conn) {
      if (!is.null(conn) && DBI::dbIsValid(conn)) {
        DBI::dbDisconnect(conn)
      }
    },

    #' @description
    #' Shut down this adapter's shared DuckDB instance, releasing the
    #' database file. Call it when the adapter is finished with, before
    #' another adapter (for example a later application pool) opens the
    #' same file. Connections and pools from this adapter become invalid.
    shutdown = function() {
      if (!is.null(private$drv)) {
        tryCatch(duckdb::duckdb_shutdown(private$drv), error = function(e) NULL)
        private$drv <- NULL
      }
      invisible(NULL)
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
        upsert_syntax = "INSERT OR REPLACE",

        # Date difference in days (col_a - col_b)
        date_diff_days = function(col_a, col_b) {
          sprintf("date_diff('day', %s, %s)", col_b, col_a)
        }
      )
    },

    #' @description
    #' Get the DDL fragment for an auto-increment primary key column.
    #' DuckDB's plain `INTEGER PRIMARY KEY` (the `dialect()$auto_increment`
    #' value) has no default value generator and fails with a
    #' `NOT NULL constraint failed` error on an INSERT that omits the
    #' column (verified in
    #' `docs/db-adapter-remediation-plan-2026-11-07.md`); it needs a
    #' named sequence instead. Call `prepare_auto_increment()` before
    #' the `CREATE TABLE` statement that uses this fragment.
    #' @param table_name Name of the table the column belongs to
    #' @param column_name Name of the auto-increment column
    #' @return Character string with the column's DDL fragment
    auto_increment_column = function(table_name, column_name) {
      sprintf("INTEGER PRIMARY KEY DEFAULT nextval('%s')",
              private$sequence_name(table_name, column_name))
    },

    #' @description
    #' Create the sequence that `auto_increment_column()`'s DEFAULT
    #' references, if it does not already exist.
    #' @param conn Database connection
    #' @param table_name Name of the table the column belongs to
    #' @param column_name Name of the auto-increment column
    prepare_auto_increment = function(conn, table_name, column_name) {
      DBI::dbExecute(conn, sprintf(
        "CREATE SEQUENCE IF NOT EXISTS %s",
        private$sequence_name(table_name, column_name)
      ))
      invisible(NULL)
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
    #' Describe this backend's encryption. DuckDB encrypts the database
    #' file itself via `ATTACH ... (ENCRYPTION_KEY ...)` whenever
    #' `config$duckdb$encryption_key` is set (see `connect()`).
    #' @return List; see `DatabaseAdapter$encryption_capabilities()`
    encryption_capabilities = function() {
      key <- self$config$duckdb$encryption_key
      list(
        at_rest = "package",
        at_rest_configured = !is.null(key) && nzchar(key) &&
          !identical(self$config$duckdb$path, ":memory:"),
        in_transit = "not_applicable",
        detail = "DuckDB encrypts the database file when duckdb.encryption_key is set."
      )
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
  ),

  private = list(
    drv = NULL,
    extensions_ready = FALSE,

    is_encrypted = function() {
      key <- self$config$duckdb$encryption_key
      !is.null(key) && nzchar(key) && !identical(self$config$duckdb$path, ":memory:")
    },

    # The adapter's one DuckDB instance, created on first use and
    # recreated if it has been shut down (including by a caller's
    # DBI::dbDisconnect(conn, shutdown = TRUE) on one of its
    # connections). An encrypted file is attached to an in-memory
    # instance; an unencrypted file is the instance's own database.
    driver = function() {
      if (!is.null(private$drv) &&
          isTRUE(tryCatch(DBI::dbIsValid(private$drv), error = function(e) FALSE))) {
        return(private$drv)
      }
      db_path <- self$config$duckdb$path
      if (!identical(db_path, ":memory:")) {
        db_dir <- dirname(db_path)
        if (!dir.exists(db_dir) && db_dir != ".") {
          dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
        }
      }
      private$extensions_ready <- FALSE
      private$drv <- if (private$is_encrypted()) {
        duckdb::duckdb(dbdir = ":memory:")
      } else {
        private$check_unencrypted(db_path)
        duckdb::duckdb(dbdir = db_path, read_only = FALSE)
      }
      private$drv
    },

    # Per-connection setup on the shared instance. The encrypted file
    # is attached once per instance: a second ATTACH of the same file
    # fails with "Unique file handle conflict", which is what made a
    # second concurrent pool connection impossible before 2026-11-10.
    # USE is per-connection, so every connection runs it.
    prepare_connection = function(conn) {
      if (private$is_encrypted()) {
        attached <- DBI::dbGetQuery(conn, paste(
          "SELECT count(*) AS n FROM duckdb_databases()",
          "WHERE database_name = 'zzedc'"
        ))$n > 0
        if (!attached) {
          # ATTACH ... ENCRYPTION_KEY needs DuckDB's full (writable)
          # mbedtls crypto module. On at least one DuckDB build (1.5.4,
          # confirmed in CI), only a read-only crypto module is loaded
          # by default, and ATTACH with ENCRYPTION_KEY fails outright
          # ("DuckDB currently has a read-only crypto module loaded...
          # ensure httpfs is loaded using `LOAD httpfs`"). Loading httpfs
          # first pulls in the full module; verified harmless on a newer
          # build (2.0.0) where it was not otherwise required.
          private$prepare_extensions(conn, need_httpfs = TRUE)
          private$extensions_ready <- TRUE
          DBI::dbExecute(conn, sprintf(
            "ATTACH '%s' AS zzedc (ENCRYPTION_KEY '%s')",
            self$config$duckdb$path, self$config$duckdb$encryption_key
          ))
        }
        DBI::dbExecute(conn, "USE zzedc")
      } else if (!private$extensions_ready) {
        private$prepare_extensions(conn, need_httpfs = FALSE)
        private$extensions_ready <- TRUE
      }

      threads <- self$config$duckdb$threads
      if (!is.null(threads)) {
        DBI::dbExecute(conn, sprintf("SET threads = %d", as.integer(threads)))
      }
      memory_limit <- self$config$duckdb$memory_limit
      if (!is.null(memory_limit)) {
        DBI::dbExecute(conn, sprintf("SET memory_limit = '%s'", memory_limit))
      }
      invisible(conn)
    },

    # Deterministic sequence name for a table/column pair, shared by
    # auto_increment_column() and prepare_auto_increment() so the
    # DEFAULT nextval() expression always names a sequence that was
    # actually created.
    sequence_name = function(table_name, column_name) {
      sprintf("%s_%s_seq", table_name, column_name)
    },

    # Load the extensions a connection needs, from a persistent
    # directory when one is configured. httpfs is required before an
    # encrypted ATTACH; icu is loaded up front so that, when downloads
    # are disallowed, its absence fails here rather than at the first
    # CURRENT_DATE deadline query. When downloads are allowed and icu
    # is not yet installed, DuckDB's own autoload is left to fetch it
    # on first use, as before, so offline development machines are not
    # forced onto the network for databases that never need it.
    prepare_extensions = function(conn, need_httpfs) {
      cfg <- self$config$duckdb
      ext_dir <- cfg$extension_directory
      if (!is.null(ext_dir) && nzchar(ext_dir)) {
        dir.create(ext_dir, recursive = TRUE, showWarnings = FALSE)
        DBI::dbExecute(conn, sprintf(
          "SET extension_directory = '%s'",
          normalizePath(ext_dir, winslash = "/", mustWork = FALSE)
        ))
      }
      allow <- duckdb_extension_download_allowed(cfg)
      if (!allow) {
        DBI::dbExecute(conn, "SET autoinstall_known_extensions = false")
      }

      try_load <- function(ext) {
        tryCatch({
          DBI::dbExecute(conn, sprintf("LOAD %s", ext))
          TRUE
        }, error = function(e) FALSE)
      }
      missing_msg <- function(ext) {
        paste0(
          "DuckDB extension '", ext, "' is not installed",
          if (!is.null(ext_dir)) paste0(" in ", ext_dir) else
            " (no duckdb.extension_directory is configured, so DuckDB uses a per-session temporary directory)",
          ", and runtime downloads are disallowed (security profile '",
          get_security_profile(), "'). Pre-install it on a connected machine of ",
          "the same platform with install_duckdb_extensions(), copy the ",
          "directory to this host, and set duckdb.extension_directory; or set ",
          "duckdb.allow_extension_download: true."
        )
      }

      if (need_httpfs && !try_load("httpfs")) {
        if (!allow) stop(missing_msg("httpfs"), call. = FALSE)
        DBI::dbExecute(conn, "INSTALL httpfs")
        DBI::dbExecute(conn, "LOAD httpfs")
      }
      if (!try_load("icu") && !allow) {
        stop(missing_msg("icu"), call. = FALSE)
      }
      invisible(TRUE)
    },

    # Called only on the no-key path. An in-memory database holds
    # nothing at rest; any file opened without a key is plaintext.
    check_unencrypted = function(db_path) {
      if (identical(db_path, ":memory:")) {
        return(invisible(TRUE))
      }
      enforce_encryption_at_rest(
        FALSE, db_path, "No duckdb.encryption_key is configured."
      )
    }
  )
)


#' Whether DuckDB May Download Extensions at Runtime
#'
#' @param duckdb_config The `duckdb` section of a database
#'   configuration.
#' @return `TRUE` or `FALSE`. An explicit
#'   `allow_extension_download` setting wins; otherwise downloads are
#'   disallowed under the `regulated` security profile and allowed
#'   under the others.
#' @examples
#' duckdb_extension_download_allowed(list(allow_extension_download = FALSE))
#' @export
duckdb_extension_download_allowed <- function(duckdb_config = list()) {
  explicit <- duckdb_config$allow_extension_download
  if (!is.null(explicit)) {
    return(isTRUE(as.logical(explicit)))
  }
  get_security_profile() != "regulated"
}


#' Pre-install DuckDB Extensions into a Persistent Directory
#'
#' Downloads the DuckDB extensions zzedc needs into
#' `extension_directory`, then confirms each one loads from there with
#' automatic installation switched off. Run it on a machine with
#' network access and the same operating system, CPU architecture, and
#' DuckDB version as the deployment host (the directory layout is
#' `v<duckdb version>/<platform>/`), then copy the directory to the
#' host and point `duckdb.extension_directory` at it.
#'
#' @param extension_directory Character: directory to install into.
#'   Created if needed.
#' @param extensions Character vector of extension names (default
#'   `c("httpfs", "icu")`: `httpfs` is required for encrypted files,
#'   `icu` for `CURRENT_DATE`).
#'
#' @return A data frame with one row per extension: `extension`,
#'   `loads_offline` (logical), and `install_path`.
#'
#' @examples
#' \dontrun{
#'   install_duckdb_extensions("/srv/zzedc/duckdb_extensions")
#' }
#'
#' @export
install_duckdb_extensions <- function(extension_directory,
                                      extensions = c("httpfs", "icu")) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("duckdb package required. Install with: install.packages('duckdb')")
  }
  dir.create(extension_directory, recursive = TRUE, showWarnings = FALSE)
  dir_sql <- sprintf(
    "SET extension_directory = '%s'",
    normalizePath(extension_directory, winslash = "/", mustWork = TRUE)
  )

  local({
    conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)
    DBI::dbExecute(conn, dir_sql)
    for (ext in extensions) {
      DBI::dbExecute(conn, sprintf("INSTALL %s", ext))
    }
  })

  # Verify in a fresh instance that nothing depends on the network.
  conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(conn, dir_sql)
  DBI::dbExecute(conn, "SET autoinstall_known_extensions = false")
  loads <- vapply(extensions, function(ext) {
    tryCatch({
      DBI::dbExecute(conn, sprintf("LOAD %s", ext))
      TRUE
    }, error = function(e) FALSE)
  }, logical(1))
  info <- DBI::dbGetQuery(conn, "SELECT extension_name, install_path FROM duckdb_extensions()")
  data.frame(
    extension = extensions,
    loads_offline = unname(loads),
    install_path = info$install_path[match(extensions, info$extension_name)],
    stringsAsFactors = FALSE
  )
}
