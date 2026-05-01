#' Internal helpers for the `edc_users` table
#'
#' These helpers exist to remove duplication across three
#' callers that each need to provision and populate `edc_users`
#' programmatically:
#'
#' \itemize{
#'   \item the Shiny admin UI helper [save_user_to_db()];
#'   \item [setup_zzedc_from_gsheets()] (the Google Sheets
#'         authoring path);
#'   \item [import_redcap_to_zzedc_db()] (the REDCap migration
#'         importer, both `source = "db"` and `source = "api"`).
#' }
#'
#' Before this consolidation each caller carried its own
#' `CREATE TABLE IF NOT EXISTS` and `INSERT` statements with
#' subtly different column lists, leading to schema drift
#' (`user_id INTEGER PRIMARY KEY AUTOINCREMENT` in the
#' programmatic callers vs `user_id TEXT PRIMARY KEY` produced
#' by the canonical `create_core_tables()` path used by the
#' setup wizard). The helpers below adopt the canonical
#' `create_core_tables()` schema as the single source of truth.
#'
#' @name db_users
#' @keywords internal
NULL


#' Create the canonical `edc_users` table if it does not exist
#'
#' Mirrors the SQLite shape produced by
#' [create_core_tables()] for the `sqlite` backend. The schema
#' is hard-coded here rather than delegated to
#' `create_core_tables()` so callers that already hold a raw
#' DBI connection (the C2 importer, the gsheets setup) do not
#' need to instantiate a `DatabaseAdapter` just to provision
#' one table.
#'
#' Idempotent: calling this on a database where `edc_users`
#' already exists is a no-op.
#'
#' @param conn A DBI connection (or pool object that delegates
#'   DBI methods).
#' @return Invisible `NULL`.
#' @keywords internal
ensure_edc_users_table <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS edc_users (
      user_id        TEXT PRIMARY KEY,
      username       TEXT UNIQUE NOT NULL,
      password_hash  TEXT NOT NULL,
      full_name      TEXT,
      email          TEXT,
      role           TEXT,
      site_id        TEXT,
      active         INTEGER DEFAULT 1,
      last_login     TIMESTAMP,
      created_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      created_by     TEXT,
      modified_date  TIMESTAMP,
      modified_by    TEXT
    )
  ")
  invisible(NULL)
}


#' Insert a single user row into `edc_users`
#'
#' All callers that previously open-coded the same INSERT now
#' route through here. The helper does no password hashing of
#' its own; callers pass a pre-hashed `password_hash`. This
#' keeps each caller's salt strategy under its own control
#' (the Shiny UI uses `Sys.getenv("ZZEDC_SALT")` with a
#' fallback; the REDCap importer uses an importer-specific
#' placeholder; the gsheets setup uses its own placeholder).
#'
#' If `user_id` is `NULL`, a fresh `USER_<unix_seconds>`
#' identifier is generated. Callers that need a deterministic
#' ID (e.g., the Shiny admin UI generating IDs in `mode =
#' "add"`) can pass one explicitly.
#'
#' @param conn A DBI connection (or pool object).
#' @param username Unique username string.
#' @param password_hash Pre-hashed password (typically
#'   `digest::digest(paste0(password, salt), algo = "sha256")`).
#' @param full_name,email,role,site_id Optional columns; all
#'   default to sensible blanks where the canonical schema
#'   permits.
#' @param active `TRUE` / `FALSE` or an integer flag; coerced
#'   to `0L` / `1L` for the database.
#' @param created_by String identifying the path that created
#'   the user (e.g., `"setup_wizard"`, `"gsheets_setup"`,
#'   `"redcap_import"`, `"admin_ui"`).
#' @param user_id Optional pre-generated identifier; auto-
#'   generated if `NULL`.
#' @return Named list with `success` (logical) and either
#'   `user_id` (on success) or `error` (the DBI error message).
#' @keywords internal
db_insert_user <- function(conn,
                            username,
                            password_hash,
                            full_name = NULL,
                            email = NULL,
                            role = "Coordinator",
                            site_id = "001",
                            active = TRUE,
                            created_by = "programmatic",
                            user_id = NULL) {
  if (is.null(user_id) || !nzchar(as.character(user_id))) {
    user_id <- paste0("USER_", as.integer(Sys.time()), "_",
                       sample(1e6, 1L))
  }
  active_int <- if (isTRUE(as.logical(active))) 1L else 0L

  tryCatch({
    DBI::dbExecute(conn, "
      INSERT INTO edc_users
        (user_id, username, password_hash, full_name, email,
         role, site_id, active, created_date, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
    ", list(
      as.character(user_id),
      as.character(username),
      as.character(password_hash),
      as.character(full_name %||% username),
      as.character(email %||% ""),
      as.character(role),
      as.character(site_id),
      active_int,
      as.character(created_by)
    ))
    list(success = TRUE, user_id = user_id)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}
