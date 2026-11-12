#' Build the Shiny Application's Database Configuration
#'
#' Translates the `database:` section of the application's
#' `config.yml` (read with `config::get()`) into a configuration for
#' `create_db_adapter()`, so the application opens the same backend the
#' package's data functions use. Before 2026-11-10 the application
#' ignored the backend entirely and always opened SQLite with RSQLite.
#'
#' @param cfg The application configuration list (`config::get()`).
#' @param work_dir Directory that relative paths are resolved against
#'   (the directory the application was launched from).
#'
#' @return A configuration list for `create_db_adapter()`.
#'
#' @details
#' The `database:` section is flat. `backend` (or the setup wizard's
#' `type`) selects `sqlite` (the default), `duckdb`, `postgresql`, or
#' `mysql`/`mariadb`. Recognized keys:
#'
#' - File backends: `path`, `encryption_key`, and for DuckDB
#'   `extension_directory`, `allow_extension_download`, `threads`,
#'   `memory_limit`.
#' - Server backends: `host`, `port`, `name`, `user`, `password`, and
#'   `sslmode` (PostgreSQL) or `ssl_mode` (MySQL/MariaDB), and
#'   `at_rest_attestation`: the deployer's statement of how the server
#'   encrypts its storage (see `?server_encryption`).
#' - All backends: `pool_size` (maximum pool connections).
#'
#' Values of the form `${VAR}` are replaced from the environment, so
#' keys and passwords need not be written into the file. An empty value
#' (an unset variable) is treated as absent.
#'
#' @examples
#' cfg <- list(database = list(backend = "duckdb", path = "data/study.duckdb",
#'                             pool_size = 5))
#' str(app_database_config(cfg, work_dir = tempdir()))
#'
#' @export
app_database_config <- function(cfg, work_dir = getwd()) {
  db <- suppressWarnings(substitute_env_vars(cfg$database %||% list()))
  db <- Filter(function(v) !is.null(v) && !(is.character(v) && !nzchar(v)), db)
  backend <- tolower(db$backend %||% db$type %||% "sqlite")
  if (backend == "mariadb") backend <- "mysql"

  resolve <- function(p) {
    if (is.null(p) || identical(p, ":memory:") || grepl("^/|^[A-Za-z]:|^~", p)) {
      return(p)
    }
    file.path(work_dir, p)
  }
  pool_max <- db$pool_size %||% 5L
  compact <- function(x) Filter(Negate(is.null), x)

  section <- switch(
    backend,
    sqlite = compact(list(
      path = resolve(db$path %||% "data/zzedc.db"),
      encryption_key = db$encryption_key,
      pool_max = pool_max
    )),
    duckdb = compact(list(
      path = resolve(db$path %||% "data/zzedc.duckdb"),
      encryption_key = db$encryption_key,
      extension_directory = resolve(db$extension_directory),
      allow_extension_download = db$allow_extension_download,
      threads = db$threads,
      memory_limit = db$memory_limit,
      pool_max = pool_max
    )),
    postgresql = compact(list(
      host = db$host, port = db$port, name = db$name, user = db$user,
      password = db$password, sslmode = db$sslmode,
      at_rest_attestation = db$at_rest_attestation, pool_max = pool_max
    )),
    mysql = compact(list(
      host = db$host, port = db$port, name = db$name, user = db$user,
      password = db$password, ssl_mode = db$ssl_mode,
      at_rest_attestation = db$at_rest_attestation, pool_max = pool_max
    )),
    stop("Unsupported database backend in config.yml: '", backend,
         "'. Use sqlite, duckdb, postgresql, or mysql.", call. = FALSE)
  )

  out <- list(db_backend = backend)
  out[[backend]] <- section
  out
}


#' Database File Path from an Adapter Configuration
#'
#' @param db_config A configuration list from `app_database_config()`.
#' @return The database file path for SQLite and DuckDB, or
#'   `NA_character_` for server backends, which have no file.
#' @export
app_database_path <- function(db_config) {
  backend <- db_config$db_backend
  if (backend %in% c("sqlite", "duckdb")) {
    db_config[[backend]]$path
  } else {
    NA_character_
  }
}
