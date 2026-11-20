library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# data_correction_module.R's "Create Request" view (2026-11-17): when
# Table Name is "data_entries" and Record ID resolves to a real
# entry, Field and Corrected Value become a CRF-aware dropdown/typed
# widget drawn from that entry's own form metadata, validated the
# same way the original form would have validated it
# (validate_crf_submission()). Any other table, or a data_entries
# record_id that does not resolve, falls back to the plain free-text
# inputs the module always had.

if (!exists("data_correction_server", envir = asNamespace("zzedc"))) {
  exit_file("data_correction_server not available")
}
for (fn in c("ensure_data_entries_table", "db_insert_data_entry",
             "init_crf_version", "init_crf_designer", "create_crf_definition",
             "ensure_designer_form_row", "add_form_field", "add_field_option",
             "get_db_adapter")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

setup_crf_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") Sys.setenv(ZZEDC_OLD_KEY = old_key)
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  invisible(get_db_adapter(
    config = list(db_backend = "sqlite", sqlite = list(path = db)),
    force_new = TRUE
  ))
  init_audit_logging(db_path = db)
  init_version_control(db_path = db)
  init_data_correction(db_path = db)
  init_crf_version()
  init_crf_designer()

  crf <- create_crf_definition("JOURNAL_REVIEWS", "Journal Reviews", created_by = "tester")
  ensure_designer_form_row(crf$crf_id, "JOURNAL_REVIEWS", "Journal Reviews", "tester")
  f <- add_form_field(crf$crf_id, "recommendation", "Recommendation", "RADIO",
                       is_required = TRUE)
  add_field_option(f$field_id, "approved", "Approved", option_order = 1)
  add_field_option(f$field_id, "not_reviewed", "Not Reviewed", option_order = 2)

  conn <- connect_encrypted_db(db_path = db)
  ensure_data_entries_table(conn)
  entry <- db_insert_data_entry(
    conn, "REV-001", "journal_reviews",
    data = list(recommendation = "not_reviewed"),
    created_by = "coordinator1"
  )
  DBI::dbDisconnect(conn)

  list(db = db, entry_id = entry$entry_id, crf_id = crf$crf_id)
}

cleanup_crf_db <- function(db) {
  unlink(db)
  old <- Sys.getenv("ZZEDC_OLD_KEY")
  if (old != "") { Sys.setenv(DB_ENCRYPTION_KEY = old); Sys.unsetenv("ZZEDC_OLD_KEY") }
}

# A data_entries record resolves to CRF-aware metadata, and the
# dropdown exposes the field's real choices.
local({
  s <- setup_crf_db()
  on.exit(cleanup_crf_db(s$db), add = TRUE)

  shiny::testServer(
    zzedc:::data_correction_server,
    args = list(
      current_user = shiny::reactive("coordinator1"),
      user_role    = shiny::reactive("Data Manager"),
      db_path      = s$db
    ),
    {
      session$setInputs(table_name = "data_entries", record_id = s$entry_id)
      ctx <- crf_context()
      expect_false(is.null(ctx), info = "a real data_entries record resolves to CRF metadata")
      expect_true("recommendation" %in% names(ctx$metadata))
      expect_identical(ctx$values$recommendation, "not_reviewed")

      picker <- output$field_picker
      expect_true(!is.null(picker), info = "field_picker renders without error")

      # Original Value's auto-fill observer calls updateTextInput(),
      # which shiny::testServer() does not reliably round-trip back
      # into input$original_value for an input never set via
      # setInputs() -- so this one behavior is left to the manual
      # browser walkthrough in the plan's verification section
      # rather than asserted here.
    }
  )
})

# An invalid choice for a RADIO field is rejected before
# create_correction_request() is ever called -- no request is
# created, and the error names the field.
local({
  s <- setup_crf_db()
  on.exit(cleanup_crf_db(s$db), add = TRUE)

  shiny::testServer(
    zzedc:::data_correction_server,
    args = list(
      current_user = shiny::reactive("coordinator1"),
      user_role    = shiny::reactive("Data Manager"),
      db_path      = s$db
    ),
    {
      session$setInputs(
        table_name = "data_entries", record_id = s$entry_id,
        field_name = "recommendation",
        corrected_value_widget = "not_a_real_choice",
        correction_reason = "SOURCE_DOC_ERROR",
        reason_details = "testing"
      )
      session$setInputs(submit_request = 1)

      pending <- tryCatch(
        get_pending_corrections(db_path = s$db),
        error = function(e) data.frame()
      )
      expect_true(nrow(pending) == 0,
                  info = "an out-of-choice-list value never reaches create_correction_request()")
    }
  )
})

# A valid choice for the same RADIO field is accepted and creates a
# real, pending correction request.
local({
  s <- setup_crf_db()
  on.exit(cleanup_crf_db(s$db), add = TRUE)

  shiny::testServer(
    zzedc:::data_correction_server,
    args = list(
      current_user = shiny::reactive("coordinator1"),
      user_role    = shiny::reactive("Data Manager"),
      db_path      = s$db
    ),
    {
      session$setInputs(table_name = "data_entries", record_id = s$entry_id)
      session$setInputs(field_name = "recommendation")
      session$setInputs(
        corrected_value_widget = "approved",
        correction_reason = "SOURCE_DOC_ERROR",
        reason_details = "testing"
      )
      session$setInputs(submit_request = 1)

      pending <- get_pending_corrections(db_path = s$db)
      expect_equal(nrow(pending), 1)
      expect_identical(pending$field_name[1], "recommendation")
      expect_identical(pending$corrected_value[1], "approved")
    }
  )
})

# A data_entries row still is_complete = 0 (an open "Save and Finish
# Later" draft) has no settled value yet to correct: crf_context()
# flags it as a draft rather than resolving CRF metadata, the field
# picker shows a message instead of either the typed picker or the
# free-text fallback, and no correction request is created even if a
# submit is attempted with stale/leftover field values.
local({
  s <- setup_crf_db()
  on.exit(cleanup_crf_db(s$db), add = TRUE)

  conn <- connect_encrypted_db(db_path = s$db)
  draft <- db_insert_data_entry(
    conn, "REV-DRAFT", "journal_reviews",
    data = list(recommendation = ""), is_complete = FALSE,
    created_by = "coordinator1"
  )
  DBI::dbDisconnect(conn)

  shiny::testServer(
    zzedc:::data_correction_server,
    args = list(
      current_user = shiny::reactive("coordinator1"),
      user_role    = shiny::reactive("Data Manager"),
      db_path      = s$db
    ),
    {
      session$setInputs(table_name = "data_entries", record_id = draft$entry_id)
      ctx <- crf_context()
      expect_true(isTRUE(ctx$draft),
                  info = "an is_complete=0 entry is flagged as a draft, not resolved to metadata")
      expect_identical(ctx$entry_id, draft$entry_id)

      picker_html <- paste(as.character(output$field_picker), collapse = " ")
      expect_true(grepl("open draft", picker_html, fixed = TRUE))

      session$setInputs(
        field_name = "recommendation",
        corrected_value_widget = "approved",
        correction_reason = "SOURCE_DOC_ERROR",
        reason_details = "testing"
      )
      session$setInputs(submit_request = 1)

      pending <- tryCatch(
        get_pending_corrections(db_path = s$db),
        error = function(e) data.frame()
      )
      expect_true(nrow(pending) == 0,
                  info = "a draft entry never creates a correction request")
    }
  )
})

# create_correction_request() itself refuses a draft data_entries row
# directly (not only via the Shiny module above), so a scripted
# caller gets the same protection.
local({
  s <- setup_crf_db()
  on.exit(cleanup_crf_db(s$db), add = TRUE)

  conn <- connect_encrypted_db(db_path = s$db)
  draft <- db_insert_data_entry(
    conn, "REV-DRAFT2", "journal_reviews",
    data = list(recommendation = ""), is_complete = FALSE,
    created_by = "coordinator1"
  )
  DBI::dbDisconnect(conn)

  res <- create_correction_request(
    table_name = "data_entries", record_id = draft$entry_id,
    field_name = "recommendation", original_value = "",
    corrected_value = "approved", correction_reason = "SOURCE_DOC_ERROR",
    reason_details = "testing", requested_by = "coordinator1",
    db_path = s$db
  )
  expect_false(res$success)
  expect_true(grepl("open draft", res$error, fixed = TRUE))

  # The existing, already-complete entry from setup_crf_db() is
  # unaffected -- this is a draft-specific refusal, not a general
  # regression in create_correction_request().
  res_ok <- create_correction_request(
    table_name = "data_entries", record_id = s$entry_id,
    field_name = "recommendation", original_value = "not_reviewed",
    corrected_value = "approved", correction_reason = "SOURCE_DOC_ERROR",
    reason_details = "testing", requested_by = "coordinator1",
    db_path = s$db
  )
  expect_true(res_ok$success)
})

# A table other than data_entries keeps the original free-text
# behavior (no CRF context, no crash).
local({
  s <- setup_crf_db()
  on.exit(cleanup_crf_db(s$db), add = TRUE)

  shiny::testServer(
    zzedc:::data_correction_server,
    args = list(
      current_user = shiny::reactive("coordinator1"),
      user_role    = shiny::reactive("Data Manager"),
      db_path      = s$db
    ),
    {
      session$setInputs(table_name = "subjects", record_id = "S001")
      expect_true(is.null(crf_context()),
                  info = "a non-data_entries table never resolves CRF context")
    }
  )
})
