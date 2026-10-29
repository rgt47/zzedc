#' Internal helpers for the `data_entries` table
#'
#' `data_entries` is the canonical table (see
#' [create_core_tables()]) for storing one row per submitted
#' case-report-form entry, with the arbitrary field/value pairs
#' held as a JSON blob in `data_json`. These helpers give the EDC
#' tab's study-specific `forms/save.R` a stable way to persist a
#' submission without re-deriving the schema, mirroring the
#' `ensure_edc_users_table()` / `db_insert_user()` pattern in
#' `db_users.R`.
#'
#' @name db_data_entries
#' @keywords internal
NULL


#' Create the canonical `data_entries` table if it does not exist
#'
#' Mirrors the SQLite shape produced by [create_core_tables()].
#' The schema is hard-coded here (rather than delegated to
#' [create_core_tables()]) so callers that already hold a raw DBI
#' connection or pool, such as the EDC tab's `forms/save.R`, do
#' not need to instantiate a `DatabaseAdapter` just to provision
#' one table.
#'
#' Idempotent: calling this on a database where `data_entries`
#' already exists is a no-op.
#'
#' @param conn A DBI connection (or pool object that delegates
#'   DBI methods).
#' @return Invisible `NULL`.
#' @keywords internal
ensure_data_entries_table <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS data_entries (
      entry_id       TEXT PRIMARY KEY,
      subject_id     TEXT NOT NULL,
      form_name      TEXT NOT NULL,
      visit_label    TEXT,
      visit_date     TEXT,
      data_json      TEXT,
      is_complete    INTEGER DEFAULT 0,
      created_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      created_by     TEXT NOT NULL,
      modified_date  TIMESTAMP,
      modified_by    TEXT,
      locked         INTEGER DEFAULT 0
    )
  ")
  invisible(NULL)
}


#' Insert a single row into `data_entries`
#'
#' @param conn A DBI connection (or pool object).
#' @param subject_id Subject identifier for this entry. Required.
#' @param form_name Identifier for the form/panel that produced
#'   this entry (e.g. `"edc_visit_form"`).
#' @param data Named list of submitted field values; serialized
#'   to JSON and stored in `data_json`.
#' @param visit_label,visit_date Optional display label and date
#'   for the visit this entry belongs to.
#' @param is_complete `TRUE` / `FALSE`; coerced to `0L` / `1L`.
#' @param created_by String identifying who submitted the entry
#'   (typically the logged-in username).
#' @param entry_id Optional pre-generated identifier;
#'   auto-generated from a timestamp if `NULL`.
#' @return Named list with `success` (logical) and either
#'   `entry_id` (on success) or `error` (the DBI error message).
#' @keywords internal
db_insert_data_entry <- function(conn,
                                  subject_id,
                                  form_name,
                                  data = list(),
                                  visit_label = NULL,
                                  visit_date = NULL,
                                  is_complete = TRUE,
                                  created_by,
                                  entry_id = NULL) {
  if (is.null(entry_id)) {
    entry_id <- paste0(
      "DE-", format(Sys.time(), "%Y%m%d%H%M%OS3", tz = "UTC"),
      "-", sample.int(9999L, 1L)
    )
    entry_id <- gsub("[^A-Za-z0-9-]", "", entry_id)
  }

  result <- tryCatch({
    DBI::dbExecute(
      conn,
      paste(
        "INSERT INTO data_entries",
        "(entry_id, subject_id, form_name, visit_label, visit_date,",
        " data_json, is_complete, created_by)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      params = list(
        entry_id,
        subject_id,
        form_name,
        if (is.null(visit_label)) NA_character_ else visit_label,
        if (is.null(visit_date)) NA_character_ else visit_date,
        as.character(jsonlite::toJSON(data, auto_unbox = TRUE,
                                       null = "null")),
        if (isTRUE(is_complete)) 1L else 0L,
        created_by
      )
    )
    list(success = TRUE, entry_id = entry_id)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })

  result
}
