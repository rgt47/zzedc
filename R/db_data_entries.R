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
  # Every insert is audited in its own transaction (see
  # db_insert_data_entry()), so the audit tables must exist wherever
  # data_entries does.
  .ensure_audit_tables(conn)
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
#' @param ip_address,session_id Client address and Shiny session token,
#'   recorded in the audit record when known.
#' @return Named list with `success` (logical) and either
#'   `entry_id` (on success) or `error` (the DBI error message).
#'
#' @details
#' The row and its audit record (an `INSERT` event on `data_entries`
#' whose details hold the submitted values) are written in one
#' transaction: if the audit record cannot be written, the entry is not
#' saved (21 CFR 11.10(e)).
#' @keywords internal
db_insert_data_entry <- function(conn,
                                  subject_id,
                                  form_name,
                                  data = list(),
                                  visit_label = NULL,
                                  visit_date = NULL,
                                  is_complete = TRUE,
                                  created_by,
                                  entry_id = NULL,
                                  ip_address = NULL,
                                  session_id = NULL) {
  if (is.null(entry_id)) {
    entry_id <- paste0(
      "DE-", format(Sys.time(), "%Y%m%d%H%M%OS3", tz = "UTC"),
      "-", sample.int(9999L, 1L)
    )
    entry_id <- gsub("[^A-Za-z0-9-]", "", entry_id)
  }

  data_json <- as.character(jsonlite::toJSON(data, auto_unbox = TRUE, null = "null"))
  result <- tryCatch({
    .with_db_transaction(conn, function(c) {
      DBI::dbExecute(
        c,
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
          data_json,
          if (isTRUE(is_complete)) 1L else 0L,
          created_by
        )
      )
      .append_audit_record(
        c, event_type = "INSERT", table_name = "data_entries",
        record_id = entry_id,
        operation = paste0("Case report form entry created (form ", form_name,
                           ", subject ", subject_id, ")"),
        details = as.character(jsonlite::toJSON(list(
          subject_id = subject_id, form_name = form_name,
          visit_label = visit_label, visit_date = visit_date,
          is_complete = isTRUE(is_complete),
          new_values = jsonlite::fromJSON(data_json, simplifyVector = FALSE)
        ), auto_unbox = TRUE, null = "null")),
        user_id = created_by, ip_address = ip_address, session_id = session_id
      )
    })
    list(success = TRUE, entry_id = entry_id)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })

  result
}


#' Update an incomplete (`is_complete = 0`) `data_entries` row in place
#'
#' [db_insert_data_entry()] is insert-only: one row per `entry_id`,
#' audited as a single `INSERT`. A "Save and Finish Later" draft that
#' is reopened and saved again needs a true update of that same row
#' instead of a second row -- this is that update path. It is
#' deliberately narrow: it only ever touches `data_json`,
#' `is_complete`, `modified_date`, and `modified_by`, never
#' `subject_id`, `form_name`, or `entry_id`, so a field value the
#' draft's own form happens to carry (e.g. `tracking_id`) can never
#' drift the row's real key out from under it.
#'
#' This is an ordinary save of a still-unsettled record, not a
#' correction to a settled one: it writes its own `"UPDATE"` audit
#' record directly, rather than going through
#' [create_correction_request()]/[approve_correction()]/
#' [apply_correction()]. Once a row's `is_complete` is `1`, it is
#' immutable except through that correction workflow -- enforced here,
#' not just by UI convention, by refusing (not silently no-oping) an
#' update to a row that is not currently `is_complete = 0`.
#'
#' The `UPDATE` targets `data_entries` by its primary key (`entry_id`)
#' alone, with the `is_complete = 0` guard folded into the same
#' statement's `WHERE` clause (`UPDATE ... WHERE entry_id = ? AND
#' is_complete = 0`) so the check and the write happen atomically, not
#' as a read-then-write race between two sessions resuming the same
#' draft. `data_entries` carries no index on any column another
#' table's `FOREIGN KEY` references (confirmed: `grep -rn "REFERENCES
#' data_entries"` across `R/`/`inst/` finds nothing), so this UPDATE
#' does not hit DuckDB's "Over-Eager Constraint Checking in Foreign
#' Keys" DELETE+INSERT rewrite that `apply_correction()`'s
#' `correction_requests(status)` index did (see commit `bf125aa`) --
#' there is nothing here for DuckDB to rewrite the UPDATE around.
#'
#' @param conn A DBI connection (or pool object).
#' @param entry_id The `data_entries.entry_id` to update. Must
#'   currently have `is_complete = 0`.
#' @param data Named list of the field values to save, replacing the
#'   row's `data_json` in full (not merged with the previous values --
#'   the caller is expected to pass the form's complete current
#'   state, as [save_crf_entry()]'s insert path already does).
#' @param is_complete `TRUE` / `FALSE`; coerced to `1L` / `0L`. `TRUE`
#'   is how an incomplete draft becomes a settled, immutable record
#'   (the ordinary "Submit" action on a resumed draft); `FALSE` keeps
#'   it open for a further "Save and Finish Later".
#' @param modified_by String identifying who made this save
#'   (typically the logged-in username). Required -- unlike
#'   `created_by` on the original insert, a resumed draft's editor is
#'   not assumed to be the original saver (cross-user resume is
#'   allowed by design, matching REDCap/Rave).
#' @param ip_address,session_id Client address and Shiny session
#'   token, recorded in the audit record when known.
#' @return Named list with `success` (logical) and either `entry_id`
#'   (on success) or `error` -- `"Entry <id> not found or is already
#'   complete (only an incomplete draft can be updated this way; use
#'   the correction workflow to change a completed entry)."` when the
#'   row does not exist, or exists but is already `is_complete = 1`.
#' @keywords internal
db_update_incomplete_data_entry <- function(conn,
                                             entry_id,
                                             data = list(),
                                             is_complete = FALSE,
                                             modified_by,
                                             ip_address = NULL,
                                             session_id = NULL) {
  data_json <- as.character(jsonlite::toJSON(data, auto_unbox = TRUE, null = "null"))

  result <- tryCatch({
    .with_db_transaction(conn, function(c) {
      before <- DBI::dbGetQuery(
        c, "SELECT data_json, is_complete FROM data_entries WHERE entry_id = ?",
        params = list(entry_id)
      )
      if (nrow(before) == 0) {
        stop("Entry ", entry_id, " not found.")
      }
      if (isTRUE(as.logical(as.integer(before$is_complete[1])))) {
        stop("Entry ", entry_id, " is already complete; use the correction ",
             "workflow (create_correction_request()) to change it, not this ",
             "function.")
      }

      n <- DBI::dbExecute(
        c,
        paste(
          "UPDATE data_entries SET",
          " data_json = ?, is_complete = ?,",
          " modified_date = CURRENT_TIMESTAMP, modified_by = ?",
          "WHERE entry_id = ? AND is_complete = 0"
        ),
        params = list(
          data_json,
          if (isTRUE(is_complete)) 1L else 0L,
          modified_by,
          entry_id
        )
      )
      if (n != 1) {
        # Lost the race: another session completed or updated this
        # same draft between the SELECT above and this UPDATE.
        stop("Entry ", entry_id, " is no longer an open draft; ",
             "nothing was saved.")
      }

      .append_audit_record(
        c, event_type = "UPDATE", table_name = "data_entries",
        record_id = entry_id,
        operation = paste0(
          "Case report form entry ",
          if (isTRUE(is_complete)) "completed" else "updated while incomplete",
          " (entry ", entry_id, ")"
        ),
        details = as.character(jsonlite::toJSON(list(
          is_complete = isTRUE(is_complete),
          old_values = jsonlite::fromJSON(before$data_json[1] %||% "{}", simplifyVector = FALSE),
          new_values = jsonlite::fromJSON(data_json, simplifyVector = FALSE)
        ), auto_unbox = TRUE, null = "null")),
        user_id = modified_by, ip_address = ip_address, session_id = session_id
      )
    })
    list(success = TRUE, entry_id = entry_id)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })

  result
}
