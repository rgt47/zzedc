library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Regression tests for the "Save and Finish Later" / incomplete-form-
# resume feature (soft-orbiting-acorn.md, Part D): a CRF form can be
# saved with is_complete = 0 and later resumed and updated in place,
# distinct from the one-shot, always-is_complete-TRUE path every
# caller used before. Covers db_update_incomplete_data_entry()
# (R/db_data_entries.R), save_crf_entry()'s new is_complete argument
# and fill_crf_field_inputs() (both R/edc_dynamic_forms.R), and
# get_data_entries()'s new include_incomplete argument
# (R/edc_reports.R). Draft rejection by the correction workflow is
# covered separately in test_correction_crf_context.R.

if (!requireNamespace("RSQLite", quietly = TRUE) ||
      !requireNamespace("jsonlite", quietly = TRUE)) {
  exit_file("RSQLite and/or jsonlite not installed")
}

# -----------------------------------------------------------------
# db_update_incomplete_data_entry()
# -----------------------------------------------------------------

local({
  db_path <- tempfile(fileext = ".db")
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_data_entries_table(conn)

  draft <- zzedc:::db_insert_data_entry(
    conn, subject_id = "PUB-1", form_name = "manuscripts",
    data = list(tracking_id = "PUB-1", status = "ideation"),
    is_complete = FALSE, created_by = "rgt"
  )
  expect_true(draft$success)

  row <- DBI::dbGetQuery(conn, "SELECT is_complete FROM data_entries WHERE entry_id = ?",
                          params = list(draft$entry_id))
  expect_equal(row$is_complete, 0)

  # A second save while still incomplete: updates the SAME row in
  # place (no second row), is still_complete = 0, modified_by/
  # modified_date are set, and the audit trail gets its own UPDATE
  # record distinct from the original INSERT.
  upd <- zzedc:::db_update_incomplete_data_entry(
    conn, entry_id = draft$entry_id,
    data = list(tracking_id = "PUB-1", status = "submitted"),
    is_complete = FALSE, modified_by = "coordinator2"
  )
  expect_true(upd$success)
  expect_equal(upd$entry_id, draft$entry_id)

  rows <- DBI::dbGetQuery(conn, "SELECT * FROM data_entries")
  expect_equal(nrow(rows), 1, info = "an update, not a second insert")
  expect_equal(rows$is_complete, 0)
  expect_equal(rows$modified_by, "coordinator2")
  expect_true(!is.na(rows$modified_date))
  parsed <- jsonlite::fromJSON(rows$data_json[1])
  expect_equal(parsed$status, "submitted")

  audit <- DBI::dbGetQuery(
    conn, "SELECT event_type, record_id, user_id FROM audit_log WHERE record_id = ? ORDER BY audit_id",
    params = list(draft$entry_id)
  )
  expect_equal(audit$event_type, c("INSERT", "UPDATE"))
  expect_equal(audit$user_id[2], "coordinator2")

  # Completing it: the same function, is_complete = TRUE, is how a
  # draft becomes settled.
  done <- zzedc:::db_update_incomplete_data_entry(
    conn, entry_id = draft$entry_id,
    data = list(tracking_id = "PUB-1", status = "accepted"),
    is_complete = TRUE, modified_by = "coordinator2"
  )
  expect_true(done$success)
  row2 <- DBI::dbGetQuery(conn, "SELECT is_complete FROM data_entries WHERE entry_id = ?",
                           params = list(draft$entry_id))
  expect_equal(row2$is_complete, 1)

  # Once complete, this function refuses to touch it again -- that
  # path belongs to the correction workflow now, not here. Refusal
  # is returned (success = FALSE), not a silent no-op, and the row's
  # data_json is unchanged by the refused attempt.
  blocked <- zzedc:::db_update_incomplete_data_entry(
    conn, entry_id = draft$entry_id,
    data = list(tracking_id = "PUB-1", status = "should-not-apply"),
    is_complete = FALSE, modified_by = "someone_else"
  )
  expect_false(blocked$success)
  expect_true(grepl("already complete", blocked$error, fixed = TRUE))
  row3 <- DBI::dbGetQuery(conn, "SELECT data_json FROM data_entries WHERE entry_id = ?",
                           params = list(draft$entry_id))
  expect_equal(jsonlite::fromJSON(row3$data_json[1])$status, "accepted",
               info = "the refused update left the completed row's data untouched")
})

# A nonexistent entry_id is rejected cleanly, not an error that
# propagates out.
local({
  db_path <- tempfile(fileext = ".db")
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_data_entries_table(conn)

  res <- zzedc:::db_update_incomplete_data_entry(
    conn, entry_id = "DE-does-not-exist",
    data = list(a = 1), is_complete = FALSE, modified_by = "rgt"
  )
  expect_false(res$success)
  expect_true(grepl("not found", res$error, fixed = TRUE))
})

# -----------------------------------------------------------------
# save_crf_entry()'s is_complete argument
# -----------------------------------------------------------------

local({
  db_path <- tempfile(fileext = ".db")
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  res <- zzedc:::save_crf_entry(
    conn, "MANUSCRIPTS",
    list(tracking_id = "PUB-2026-001", status = "ideation"),
    created_by = "rgt", is_complete = FALSE
  )
  expect_true(res$success)
  row <- DBI::dbGetQuery(conn, "SELECT is_complete FROM data_entries WHERE entry_id = ?",
                          params = list(res$entry_id))
  expect_equal(row$is_complete, 0)

  # Every existing caller that omits is_complete keeps getting a
  # complete (TRUE) row -- unchanged default behavior.
  res2 <- zzedc:::save_crf_entry(
    conn, "MANUSCRIPTS",
    list(tracking_id = "PUB-2026-002", status = "ideation"),
    created_by = "rgt"
  )
  expect_true(res2$success)
  row2 <- DBI::dbGetQuery(conn, "SELECT is_complete FROM data_entries WHERE entry_id = ?",
                           params = list(res2$entry_id))
  expect_equal(row2$is_complete, 1)
})

# -----------------------------------------------------------------
# get_data_entries()'s include_incomplete argument
# -----------------------------------------------------------------

local({
  db_path <- tempfile(fileext = ".db")
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_data_entries_table(conn)

  zzedc:::db_insert_data_entry(
    conn, subject_id = "PUB-1", form_name = "manuscripts",
    data = list(tracking_id = "PUB-1"), is_complete = TRUE, created_by = "rgt"
  )
  zzedc:::db_insert_data_entry(
    conn, subject_id = "PUB-2", form_name = "manuscripts",
    data = list(tracking_id = "PUB-2"), is_complete = FALSE, created_by = "rgt"
  )

  all_entries <- zzedc:::get_data_entries(conn)
  expect_equal(nrow(all_entries), 2,
               info = "default include_incomplete = TRUE preserves every pre-existing caller's behavior")

  complete_only <- zzedc:::get_data_entries(conn, include_incomplete = FALSE)
  expect_equal(nrow(complete_only), 1)
  expect_equal(complete_only$subject_id, "PUB-1")
})

# -----------------------------------------------------------------
# fill_crf_field_inputs()
# -----------------------------------------------------------------

local({
  # Same fake-session approach as reset_crf_field_inputs()'s own
  # tests (test_edc-dynamic-forms.R): shiny::testServer()'s
  # MockShinySession does not reflect update*Input() calls back into
  # input, so a minimal fake session capturing sendInputMessage()/
  # sendCustomMessage() calls is used instead.
  make_fake_session <- function() {
    self <- new.env()
    self$calls <- list()
    self$custom_calls <- list()
    self$sendInputMessage <- function(inputId, message) {
      self$calls[[inputId]] <- message
    }
    self$sendCustomMessage <- function(type, message) {
      self$custom_calls[[length(self$custom_calls) + 1]] <-
        list(type = type, message = message)
    }
    self$ns <- function(x) x
    class(self) <- c("MockShinySession", "environment")
    self
  }

  metadata <- list(
    tracking_id = list(type = "text"),
    count = list(type = "numeric"),
    visit_date = list(type = "date"),
    cleared_date = list(type = "date"),
    status = list(type = "select",
                   choices = c(Ideation = "ideation", Submitted = "submitted")),
    priority = list(type = "radio", choices = c(Low = "low", High = "high")),
    tags = list(type = "checkbox_group", choices = c(A = "a", B = "b", C = "c")),
    note = list(type = "notes"),
    attachment = list(type = "file")
  )

  # Parsed data_json shape (jsonlite::fromJSON(simplifyVector=FALSE)):
  # NULL for a JSON null, list() for a zero-length (cleared) value,
  # a length-1 list for a scalar, a longer list for a multi-select.
  values <- list(
    tracking_id = list("PUB-1"),
    count = list(42),
    visit_date = list("2026-11-19"),
    cleared_date = list(),
    status = list("submitted"),
    priority = NULL,
    tags = list("a", "c"),
    note = list("some notes"),
    attachment = list("/some/stored/path.pdf")
  )

  sess <- make_fake_session()
  zzedc:::fill_crf_field_inputs(sess, metadata, values)

  expect_equal(sess$calls$tracking_id$value, "PUB-1")
  # shiny::updateNumericInput() itself serializes value through
  # formatNoSci() before it ever reaches session$sendInputMessage(),
  # so the captured message's value is already a character string,
  # not a numeric -- this is shiny's own wire format, not something
  # fill_crf_field_inputs() controls.
  expect_equal(sess$calls$count$value, "42")
  expect_equal(sess$calls$status$value, "submitted")
  expect_equal(sess$calls$priority$value, character(0),
               info = "a NULL (JSON null) value for a radio field clears to nothing selected")
  expect_equal(sort(sess$calls$tags$value), c("a", "c"),
               info = "a multi-valued checkbox_group field keeps every selected value")
  expect_equal(sess$calls$note$value, "some notes")

  custom_types <- vapply(sess$custom_calls, `[[`, character(1), "type")
  date_calls <- Filter(function(c) c$type == "zzedc-clear-date-input", sess$custom_calls)
  date_targets <- vapply(date_calls, `[[`, character(1), "message")
  expect_true("cleared_date" %in% date_targets,
              info = "a zero-length (cleared) date value sends the same clear-date message reset_crf_field_inputs() uses")
  expect_false("visit_date" %in% date_targets,
               info = "a present date value is NOT cleared")
  # shiny::updateDateInput() likewise serializes its value through
  # dateYMD() to a "YYYY-MM-DD" character string before it reaches
  # session$sendInputMessage().
  expect_equal(sess$calls$visit_date$value, "2026-11-19")

  expect_true(is.null(sess$calls$attachment),
              info = "a file field is never touched -- there is no updateFileInput(), and the stored path must be carried forward by the caller instead")
})
