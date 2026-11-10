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
#' already exists is a no-op, except for the `must_change_password`
#' migration below.
#'
#' A database provisioned before `must_change_password` existed
#' (any already-deployed study) will have `edc_users` but not this
#' column; every subsequent call here checks for it and adds it if
#' missing, so this doubles as the migration path, the same pattern
#' used for `data_entries` in `launch_zzedc()`. The migrated column
#' defaults to `0` (not `1`) for already-existing rows -- a user
#' who has been logging in fine for weeks should not suddenly be
#' locked into a forced password change by an unrelated upgrade;
#' only freshly created accounts (see [db_insert_user()] and the
#' setup-wizard inserts) are meant to start at `1`.
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
      must_change_password INTEGER DEFAULT 0,
      last_login     TIMESTAMP,
      created_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      created_by     TEXT,
      modified_date  TIMESTAMP,
      modified_by    TEXT
    )
  ")
  if (!"must_change_password" %in% DBI::dbListFields(conn, "edc_users")) {
    DBI::dbExecute(conn,
      "ALTER TABLE edc_users ADD COLUMN must_change_password INTEGER DEFAULT 0")
  }
  # §11.300 password-lockout columns, migrated in the same idempotent
  # style as must_change_password above. Defaulting both to 0/NULL on
  # migration means an already-deployed study's existing users start
  # unlocked, not retroactively penalized for login history that
  # predates this feature.
  if (!"failed_login_attempts" %in% DBI::dbListFields(conn, "edc_users")) {
    DBI::dbExecute(conn,
      "ALTER TABLE edc_users ADD COLUMN failed_login_attempts INTEGER DEFAULT 0")
  }
  if (!"locked_at" %in% DBI::dbListFields(conn, "edc_users")) {
    DBI::dbExecute(conn,
      "ALTER TABLE edc_users ADD COLUMN locked_at TIMESTAMP")
  }
  # §11.300(b) password periodic revision (expiry), migrated the same
  # way. Every write site that sets a new password_hash (db_insert_user(),
  # the self-service change-password flow, and both admin reset/edit
  # paths) also sets this column, so authenticate_user() can compare it
  # against cfg$auth$password_expiry_days. A row migrated here (no
  # password_changed_date yet) is backfilled from created_date rather
  # than left NULL -- NULL would otherwise read as "never set", which
  # would force every existing user to change their password the
  # moment this feature ships, the same over-eager-migration mistake
  # must_change_password's own comment above warns against.
  if (!"password_changed_date" %in% DBI::dbListFields(conn, "edc_users")) {
    DBI::dbExecute(conn,
      "ALTER TABLE edc_users ADD COLUMN password_changed_date TIMESTAMP")
    DBI::dbExecute(conn,
      "UPDATE edc_users SET password_changed_date = created_date
       WHERE password_changed_date IS NULL")
  }
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
#' @param must_change_password `TRUE` / `FALSE` or an integer
#'   flag; coerced to `0L` / `1L`. Defaults to `TRUE`: every path
#'   that creates a new account through this helper hands the user
#'   a password someone else chose (an admin-typed password, a
#'   generated temp password, or a Sheet-provisioned placeholder),
#'   so forcing a change on first login is the safe default. Pass
#'   `FALSE` explicitly for a caller that has a real reason not to
#'   (there is none among the current callers).
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
                            user_id = NULL,
                            must_change_password = TRUE) {
  if (is.null(user_id) || !nzchar(as.character(user_id))) {
    user_id <- paste0("USER_", as.integer(Sys.time()), "_",
                       sample(1e6, 1L))
  }
  active_int <- if (isTRUE(as.logical(active))) 1L else 0L
  must_change_int <- if (isTRUE(as.logical(must_change_password))) 1L else 0L

  tryCatch({
    DBI::dbExecute(conn, "
      INSERT INTO edc_users
        (user_id, username, password_hash, full_name, email,
         role, site_id, active, must_change_password, created_date,
         password_changed_date, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?)
    ", list(
      as.character(user_id),
      as.character(username),
      as.character(password_hash),
      as.character(full_name %||% username),
      as.character(email %||% ""),
      as.character(role),
      as.character(site_id),
      active_int,
      must_change_int,
      as.character(created_by)
    ))
    list(success = TRUE, user_id = user_id)
  }, error = function(e) {
    # §11.100: usernames are never deleted, only deactivated, so a
    # UNIQUE-constraint failure here almost always means the admin
    # typed a username that belongs to an existing (possibly
    # deactivated) account -- including a past attempt to reassign an
    # identifier to a different individual, which §11.100(a)
    # specifically prohibits. A bare "Database error" left that
    # indistinguishable from an unrelated DB failure.
    msg <- conditionMessage(e)
    if (grepl("UNIQUE|constraint", msg, ignore.case = TRUE)) {
      list(success = FALSE,
           error = paste0(
             "Username '", username, "' is already in use (possibly by a ",
             "deactivated account). Usernames are never reassigned to a ",
             "different individual; choose a different username."
           ))
    } else {
      list(success = FALSE, error = msg)
    }
  })
}


#' Create the `user_training` table if it does not exist
#'
#' §11.10(i) training records. Before this, `user_training` was
#' referenced by exactly one query in the whole package -- the
#' read-only `SELECT` in `cfr_compliance_module.R`'s compliance
#' dashboard -- with no `CREATE TABLE` anywhere and no writer of any
#' kind; the dashboard's own "Record Training" button had no handler
#' behind it at all. This mirrors [ensure_edc_users_table()]'s
#' idempotent create-if-missing pattern.
#'
#' @param conn A DBI connection (or pool object that delegates DBI
#'   methods).
#' @return Invisible `NULL`.
#' @keywords internal
ensure_user_training_table <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS user_training (
      training_id       TEXT PRIMARY KEY,
      user_id            TEXT NOT NULL REFERENCES edc_users(user_id),
      training_type      TEXT NOT NULL,
      training_date      DATE NOT NULL,
      trainer_name       TEXT,
      training_score     REAL,
      completion_status  TEXT DEFAULT 'completed',
      expiry_date        DATE,
      created_date       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ")
  invisible(NULL)
}


#' Insert a single row into `user_training`
#'
#' @param conn A DBI connection (or pool object).
#' @param user_id The trainee's `edc_users.user_id`.
#' @param training_type One of the values `cfr_compliance_module.R`'s
#'   `training_type` select offers (e.g. `"cfr_part11_basics"`).
#' @param training_date The date training was completed.
#' @param trainer_name Optional trainer name.
#' @param training_score Optional numeric score (0-100).
#' @param completion_status Defaults to `"completed"` -- recording a
#'   training event through this path means it already happened, not
#'   that it is scheduled.
#' @param expiry_date Defaults to one year after `training_date`,
#'   the common renewal period for compliance training of this kind;
#'   pass a different date explicitly if a given `training_type`
#'   needs a different cycle.
#' @param training_id Optional pre-generated identifier; auto-
#'   generated if `NULL`.
#' @return Named list with `success` (logical) and either
#'   `training_id` (on success) or `error`.
#' @keywords internal
db_insert_training_record <- function(conn,
                                       user_id,
                                       training_type,
                                       training_date,
                                       trainer_name = NULL,
                                       training_score = NULL,
                                       completion_status = "completed",
                                       expiry_date = NULL,
                                       training_id = NULL) {
  if (is.null(training_id) || !nzchar(as.character(training_id))) {
    training_id <- paste0("TRAIN_", as.integer(Sys.time()), "_",
                           sample(1e6, 1L))
  }
  if (is.null(expiry_date)) {
    expiry_date <- as.character(as.Date(training_date) + 365)
  }

  tryCatch({
    DBI::dbExecute(conn, "
      INSERT INTO user_training
        (training_id, user_id, training_type, training_date,
         trainer_name, training_score, completion_status, expiry_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", list(
      as.character(training_id),
      as.character(user_id),
      as.character(training_type),
      as.character(training_date),
      if (is.null(trainer_name)) NA_character_ else as.character(trainer_name),
      if (is.null(training_score)) NA_real_ else as.numeric(training_score),
      as.character(completion_status),
      as.character(expiry_date)
    ))
    list(success = TRUE, training_id = training_id)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}
