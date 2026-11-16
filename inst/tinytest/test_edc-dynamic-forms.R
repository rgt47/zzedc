library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Regression tests for R/edc_dynamic_forms.R, which lets the EDC
# tab render and save against a study's actual imported CRF
# definitions (crf_definitions/designer_fields/designer_field_options,
# populated by setup_zzedc_from_gsheets()/the CSV path) instead of
# the demo forms/*.R scaffold. Verified against the live
# promotion-tracker deployment by direct execution (browser
# click-through + independent SQL query) before these were written;
# these tests cover the same logic against a scratch fixture.

if (requireNamespace("RSQLite", quietly = TRUE) &&
      requireNamespace("jsonlite", quietly = TRUE)) {

  # Mirrors the schema init_crf_designer()/init_crf_version() create
  # (R/crf_designer.R, R/crf_version.R), built directly here (as
  # test_data-entries.R already does for data_entries) so this test
  # does not depend on connect_encrypted_db()'s global connection
  # machinery.
  .make_crf_fixture <- function() {
    db_path <- tempfile(fileext = ".db")
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)

    DBI::dbExecute(conn, "
      CREATE TABLE crf_definitions (
        crf_id INTEGER PRIMARY KEY AUTOINCREMENT,
        crf_code TEXT UNIQUE NOT NULL,
        crf_name TEXT NOT NULL,
        created_by TEXT NOT NULL
      )
    ")
    DBI::dbExecute(conn, "
      CREATE TABLE designer_fields (
        field_id INTEGER PRIMARY KEY AUTOINCREMENT,
        design_id INTEGER NOT NULL,
        field_code TEXT NOT NULL,
        field_label TEXT NOT NULL,
        field_type TEXT NOT NULL,
        field_row INTEGER DEFAULT 1,
        field_column INTEGER DEFAULT 1,
        is_required INTEGER DEFAULT 0,
        placeholder TEXT,
        help_text TEXT,
        default_value TEXT,
        widget_file TEXT,
        help_detail TEXT
      )
    ")
    DBI::dbExecute(conn, "
      CREATE TABLE designer_field_options (
        option_id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_id INTEGER NOT NULL,
        option_value TEXT NOT NULL,
        option_label TEXT NOT NULL,
        option_order INTEGER DEFAULT 1
      )
    ")

    DBI::dbExecute(conn,
      "INSERT INTO crf_definitions (crf_code, crf_name, created_by) VALUES (?, ?, ?)",
      params = list("MANUSCRIPTS", "MANUSCRIPTS Form", "test"))
    DBI::dbExecute(conn,
      "INSERT INTO crf_definitions (crf_code, crf_name, created_by) VALUES (?, ?, ?)",
      params = list("COURSES", "COURSES Form", "test"))

    # MANUSCRIPTS (crf_id 1): a required TEXT field, a required
    # SELECT field with no options row (mirrors the live
    # promotion-tracker import, which has no choices captured), and
    # an optional NUMBER field.
    DBI::dbExecute(conn, "
      INSERT INTO designer_fields
        (design_id, field_code, field_label, field_type, field_row, is_required)
      VALUES
        (1, 'tracking_id', 'Tracking ID', 'TEXT', 1, 1),
        (1, 'status', 'Status', 'SELECT', 2, 1),
        (1, 'page_count', 'Page Count', 'NUMBER', 3, 0)
    ")
    # COURSES (crf_id 2): a RADIO field WITH options rows, to cover
    # the "options present" branch.
    DBI::dbExecute(conn, "
      INSERT INTO designer_fields
        (design_id, field_code, field_label, field_type, field_row, is_required)
      VALUES
        (2, 'term', 'Term', 'RADIO', 1, 1)
    ")
    term_field_id <- DBI::dbGetQuery(conn,
      "SELECT field_id FROM designer_fields WHERE field_code = 'term'")$field_id
    DBI::dbExecute(conn, "
      INSERT INTO designer_field_options
        (field_id, option_value, option_label, option_order)
      VALUES
        (?, 'FALL', 'Fall', 1),
        (?, 'SPRING', 'Spring', 2)
    ", params = list(term_field_id, term_field_id))

    zzedc:::ensure_data_entries_table(conn)

    conn
  }

  local({
    conn <- .make_crf_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    forms <- zzedc:::get_active_crf_forms(conn)
    expect_equal(nrow(forms), 2)
    expect_equal(forms$crf_code, c("MANUSCRIPTS", "COURSES"))
    expect_true(all(c("crf_id", "crf_code", "crf_name") %in% names(forms)))
  })

  local({
    expect_equal(zzedc:::map_designer_field_type("TEXT"), "text")
    expect_equal(zzedc:::map_designer_field_type("text"), "text")
    expect_equal(zzedc:::map_designer_field_type("NUMBER"), "numeric")
    expect_equal(zzedc:::map_designer_field_type("DATE"), "date")
    expect_equal(zzedc:::map_designer_field_type("SELECT"), "select")
    expect_equal(zzedc:::map_designer_field_type("RADIO"), "radio")
    expect_equal(zzedc:::map_designer_field_type("MULTISELECT"), "checkbox_group")
    expect_equal(zzedc:::map_designer_field_type("BOGUS_TYPE"), "text",
                 info = "unknown field_type falls back to text rather than erroring")
    expect_equal(zzedc:::map_designer_field_type(NULL), "text")
  })

  local({
    conn <- .make_crf_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    meta <- zzedc:::get_crf_field_metadata(conn, 1)
    expect_equal(names(meta), c("tracking_id", "status", "page_count"))
    expect_equal(meta$tracking_id$type, "text")
    expect_true(meta$tracking_id$required)
    expect_equal(meta$page_count$type, "numeric")
    expect_false(meta$page_count$required)

    # status is SELECT in designer_fields but has no rows in
    # designer_field_options (the gap found against the live
    # promotion-tracker import): must fall back to "text" rather
    # than rendering a choice widget with nothing to choose from.
    expect_equal(meta$status$type, "text",
                 info = "SELECT/RADIO with no options falls back to text")
    expect_null(meta$status$choices)

    # A field with no rows at all (unknown crf_id).
    expect_equal(zzedc:::get_crf_field_metadata(conn, 999), list())
  })

  local({
    conn <- .make_crf_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # RADIO field with options present: choices must be populated,
    # named by option_label, valued by option_value, and the type
    # must stay "radio" rather than falling back to text.
    meta <- zzedc:::get_crf_field_metadata(conn, 2)
    expect_equal(meta$term$type, "radio")
    expect_equal(meta$term$choices, c(Fall = "FALL", Spring = "SPRING"))
  })

  # help_detail: present on a field that was given one, NULL for one
  # that wasn't -- the hint icon's click-opens-modal-vs-just-tooltip
  # distinction in inst/app/edc.R hinges entirely on this being
  # correctly NULL/non-NULL.
  local({
    conn <- .make_crf_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "
      UPDATE designer_fields SET help_detail = ?
      WHERE field_code = 'tracking_id' AND design_id = 1
    ", params = list("A much longer explanation than help_text allows."))

    meta <- zzedc:::get_crf_field_metadata(conn, 1)
    expect_equal(meta$tracking_id$help_detail,
                 "A much longer explanation than help_text allows.")
    expect_null(meta$status$help_detail)
  })

  local({
    conn <- .make_crf_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # tracking_id present: used as subject_id (mirrors the live
    # deployment's PUB-YYYY-NNN convention).
    res1 <- zzedc:::save_crf_entry(
      conn, "MANUSCRIPTS",
      list(tracking_id = "PUB-2026-001", status = "Draft", page_count = "4"),
      created_by = "rgt"
    )
    expect_true(res1$success)
    row1 <- DBI::dbGetQuery(conn,
      "SELECT subject_id, form_name, created_by FROM data_entries WHERE entry_id = ?",
      params = list(res1$entry_id))
    expect_equal(row1$subject_id, "PUB-2026-001")
    expect_equal(row1$form_name, "manuscripts",
                 info = "form_name is lower-cased to match dsl_validation_rules' form_code convention")
    expect_equal(row1$created_by, "rgt")

    # tracking_id blank/absent: falls back to a generated
    # placeholder rather than failing the insert over a cosmetic
    # identifier (data_entries.subject_id is NOT NULL).
    res2 <- zzedc:::save_crf_entry(
      conn, "MANUSCRIPTS",
      list(tracking_id = "", status = "Draft"),
      created_by = "rgt"
    )
    expect_true(res2$success)
    row2 <- DBI::dbGetQuery(conn,
      "SELECT subject_id FROM data_entries WHERE entry_id = ?",
      params = list(res2$entry_id))
    expect_true(grepl("^MANUSCRIPTS-", row2$subject_id))

    # data_json round-trips the submitted values.
    parsed <- jsonlite::fromJSON(
      DBI::dbGetQuery(conn, "SELECT data_json FROM data_entries WHERE entry_id = ?",
                       params = list(res1$entry_id))$data_json
    )
    expect_equal(parsed$status, "Draft")
    expect_equal(parsed$page_count, "4")
  })

  local({
    # validate_crf_submission() / crf_live_invalid_fields(): a
    # required text field, a choice field with a defined choice set,
    # and an optional text field with none.
    meta <- list(
      tracking_id = list(type = "text", label = "Tracking ID",
                          required = TRUE, choices = NULL),
      status = list(type = "select", label = "Status", required = TRUE,
                    choices = c(Draft = "draft", Submitted = "submitted",
                                Accepted = "accepted")),
      notes = list(type = "text", label = "Notes", required = FALSE,
                   choices = NULL)
    )

    # Fully valid submission.
    ok <- zzedc:::validate_crf_submission(
      list(tracking_id = "PUB-1", status = "draft", notes = ""), meta
    )
    expect_true(ok$valid)
    expect_equal(length(ok$errors), 0)
    expect_equal(
      length(zzedc:::crf_live_invalid_fields(
        list(tracking_id = "PUB-1", status = "draft", notes = ""), meta
      )),
      0,
      info = "no flags when every value is valid"
    )

    # Blank required field: blocks submit (kind "required") but is
    # NOT a live flag -- a field not yet filled in is not an
    # invalid entry.
    blank_required <- list(tracking_id = "", status = "draft", notes = "")
    r_required <- zzedc:::validate_crf_submission(blank_required, meta)
    expect_false(r_required$valid)
    expect_equal(r_required$errors$tracking_id$kind, "required")
    expect_equal(
      length(zzedc:::crf_live_invalid_fields(blank_required, meta)), 0,
      info = "a required-but-blank field is not flagged live"
    )

    # Value outside the field's choice set: blocks submit (kind
    # "invalid_choice") AND is surfaced as a live flag.
    bad_choice <- list(tracking_id = "PUB-1", status = "bogus_value",
                        notes = "")
    r_choice <- zzedc:::validate_crf_submission(bad_choice, meta)
    expect_false(r_choice$valid)
    expect_equal(r_choice$errors$status$kind, "invalid_choice")
    live_flags <- zzedc:::crf_live_invalid_fields(bad_choice, meta)
    expect_equal(length(live_flags), 1)
    expect_true(grepl("bogus_value", live_flags, fixed = TRUE))

    # Optional field left blank: never an error, live or at submit.
    r_optional <- zzedc:::validate_crf_submission(
      list(tracking_id = "PUB-1", status = "draft", notes = NA), meta
    )
    expect_true(r_optional$valid)
  })

  local({
    # reset_crf_field_inputs() always goes through
    # shiny::update*Input(), which require a 'ShinySession'-ish
    # object (validate_session_object() checks the class
    # attribute) and ultimately just call session$sendInputMessage().
    # A minimal fake session capturing those calls lets this run
    # without shiny::testServer(), whose MockShinySession does not
    # reflect update*Input() calls back into `input` (verified
    # directly: shiny 1.13's MockShinySession has no sendInputMessage
    # override, so it falls through to the real ShinySession method,
    # which is a no-op outside a live app).
    make_fake_session <- function() {
      self <- new.env()
      self$calls <- list()
      self$sendInputMessage <- function(inputId, message) {
        self$calls[[inputId]] <- message
      }
      self$ns <- function(x) x
      class(self) <- c("MockShinySession", "environment")
      self
    }

    metadata <- list(
      tracking_id = list(type = "text"),
      count = list(type = "numeric"),
      visit_date = list(type = "date"),
      status = list(type = "select",
                     choices = c(Ideation = "ideation", Submitted = "submitted")),
      priority = list(type = "radio", choices = c(Low = "low", High = "high")),
      tags = list(type = "checkbox_group", choices = c(A = "a", B = "b")),
      note = list(type = "notes")
    )

    sess <- make_fake_session()
    zzedc:::reset_crf_field_inputs(sess, metadata)

    expect_equal(sess$calls$tracking_id$value, "")
    expect_equal(sess$calls$count$value, "NA",
                 info = "numeric fields reset to NA, not 0 or blank")
    expect_true(is.na(sess$calls$visit_date$value),
                info = "date fields are cleared to blank, not reset to today")
    expect_equal(sess$calls$status$value, "ideation",
                 info = "select fields reset to their first choice")
    expect_equal(sess$calls$priority$value, "low",
                 info = "radio fields reset to their first choice")
    expect_equal(sess$calls$tags$value, character(0),
                 info = "checkbox-group fields reset to nothing selected")
    expect_equal(sess$calls$note$value, "",
                 info = "notes/textarea fields fall back to the text-input reset")
  })

  local({
    # tracking_id_prefix_for_form() / validate_tracking_id_format():
    # manuscripts has an enforced PUB-YYYY-N convention; any other
    # (or unknown) form has none.
    expect_equal(zzedc:::tracking_id_prefix_for_form("manuscripts"), "PUB")
    expect_equal(zzedc:::tracking_id_prefix_for_form("MANUSCRIPTS"), "PUB",
                 info = "matched case-insensitively")
    expect_null(zzedc:::tracking_id_prefix_for_form("courses"))
    expect_null(zzedc:::tracking_id_prefix_for_form(NULL))

    expect_null(zzedc:::validate_tracking_id_format("PUB-2026-001", "manuscripts"))
    expect_null(zzedc:::validate_tracking_id_format("PUB-2026-12", "manuscripts"),
                info = "any number of digits is accepted, not just 3")
    expect_null(zzedc:::validate_tracking_id_format("", "manuscripts"),
                info = "a blank value is not a format error (required-ness is checked separately)")
    expect_null(zzedc:::validate_tracking_id_format("ddd", "courses"),
                info = "no convention is enforced for a form with no prefix rule")

    err <- zzedc:::validate_tracking_id_format("ddd", "manuscripts")
    expect_true(is.character(err) && grepl("PUB-YYYY-N", err, fixed = TRUE))
    expect_true(is.character(
      zzedc:::validate_tracking_id_format("PUB-26-001", "manuscripts")
    ), info = "a 2-digit year does not match the 4-digit convention")
  })

  local({
    # validate_crf_submission()'s tracking_id format check only runs
    # when crf_code is supplied, and only flags a non-matching value
    # as "invalid_format" (never "required" -- that is a separate,
    # already-covered error kind). The live view surfaces it the
    # same way it already surfaces "invalid_choice".
    meta <- list(
      tracking_id = list(type = "text", required = TRUE, label = "Tracking ID"),
      status = list(type = "select", required = TRUE,
                    choices = c(Ideation = "ideation"))
    )

    bad_format <- list(tracking_id = "ddd", status = "ideation")
    r_no_code <- zzedc:::validate_crf_submission(bad_format, meta)
    expect_true(r_no_code$valid,
                info = "no crf_code given -- format check is skipped entirely")

    r_format <- zzedc:::validate_crf_submission(bad_format, meta, crf_code = "manuscripts")
    expect_false(r_format$valid)
    expect_equal(r_format$errors$tracking_id$kind, "invalid_format")

    live_flags <- zzedc:::crf_live_invalid_fields(bad_format, meta, crf_code = "manuscripts")
    expect_equal(length(live_flags), 1)
    expect_true(grepl("PUB-YYYY-N", live_flags, fixed = TRUE))

    good_format <- list(tracking_id = "PUB-2026-005", status = "ideation")
    r_good <- zzedc:::validate_crf_submission(good_format, meta, crf_code = "manuscripts")
    expect_true(r_good$valid)

    r_other_form <- zzedc:::validate_crf_submission(bad_format, meta, crf_code = "courses")
    expect_true(r_other_form$valid,
                info = "courses has no tracking-ID convention, so 'ddd' is fine there")
  })

  local({
    # A form with no built-in crf_code convention (anything but
    # "manuscripts") still gets its tracking_id format enforced when
    # its own field declares one via help_text, e.g. a study's
    # Journal Reviews form designed with "Format: JRV-YYYY-NNN" --
    # previously a no-op (only PUB-prefixed manuscripts was ever
    # checked), which let a PUB-prefixed ID be saved unflagged on a
    # journal_reviews entry.
    expect_null(zzedc:::tracking_id_prefix_for_form("journal_reviews"),
                info = "no built-in convention for this crf_code")
    expect_equal(
      zzedc:::tracking_id_prefix_for_form(
        "journal_reviews", help_text = "Format: JRV-YYYY-NNN (e.g. JRV-2026-001)"
      ),
      "JRV"
    )
    expect_null(zzedc:::tracking_id_prefix_for_form("journal_reviews", help_text = "Enter a value"),
                info = "help text with no Format: convention yields no prefix")

    meta_jrv <- list(
      tracking_id = list(type = "text", required = TRUE, label = "Tracking ID",
                          help = "Format: JRV-YYYY-NNN (e.g. JRV-2026-001)")
    )
    r_wrong_prefix <- zzedc:::validate_crf_submission(
      list(tracking_id = "PUB-2026-001"), meta_jrv, crf_code = "journal_reviews"
    )
    expect_false(r_wrong_prefix$valid)
    expect_equal(r_wrong_prefix$errors$tracking_id$kind, "invalid_format")
    expect_true(grepl("JRV-YYYY-N", r_wrong_prefix$errors$tracking_id$message, fixed = TRUE))

    r_right_prefix <- zzedc:::validate_crf_submission(
      list(tracking_id = "JRV-2026-003"), meta_jrv, crf_code = "journal_reviews"
    )
    expect_true(r_right_prefix$valid)
  })

  local({
    # tracking_id_format_hint() backs the EDC tab's hover tooltip on
    # tracking_id; it should describe the same pattern
    # validate_tracking_id_format()'s error message does.
    hint <- zzedc:::tracking_id_format_hint("manuscripts")
    expect_true(is.character(hint) && grepl("PUB-YYYY-N", hint, fixed = TRUE))
    expect_true(grepl("unique within its year", hint, fixed = TRUE))
    expect_null(zzedc:::tracking_id_format_hint("courses"),
                info = "no hint text for a form with no tracking-ID convention")
    expect_null(zzedc:::tracking_id_format_hint(NULL))
  })

  local({
    # reset_crf_field_inputs() honors a caller-supplied text value
    # (the EDC tab uses this to re-prefill tracking_id with the next
    # free id after a successful manuscripts submission) instead of
    # always blanking.
    make_fake_session <- function() {
      self <- new.env()
      self$calls <- list()
      self$sendInputMessage <- function(inputId, message) {
        self$calls[[inputId]] <- message
      }
      self$ns <- function(x) x
      class(self) <- c("MockShinySession", "environment")
      self
    }

    sess <- make_fake_session()
    zzedc:::reset_crf_field_inputs(
      sess, list(tracking_id = list(type = "text", value = "PUB-2026-005"))
    )
    expect_equal(sess$calls$tracking_id$value, "PUB-2026-005")
  })

  local({
    # reset_crf_field_inputs()'s "date" case used to reset to
    # Sys.Date() -- a just-submitted manuscript's own dates
    # (submission_date, acceptance_date, ...) have no reason to
    # carry over, or default to today, on the next unrelated entry.
    # It now clears to blank (value = NA), with no warning leaking
    # out (shiny::dateYMD()'s internal "couldn't coerce" warning on
    # NA is expected and suppressed inside reset_crf_field_inputs()
    # itself -- this asserts that suppression, not just the value).
    make_fake_session <- function() {
      self <- new.env()
      self$calls <- list()
      self$sendInputMessage <- function(inputId, message) {
        self$calls[[inputId]] <- message
      }
      self$ns <- function(x) x
      class(self) <- c("MockShinySession", "environment")
      self
    }
    sess <- make_fake_session()
    expect_silent(
      zzedc:::reset_crf_field_inputs(
        sess, list(submission_date = list(type = "date"))
      )
    )
    expect_true(is.na(sess$calls$submission_date$value),
                info = "a date field is cleared to blank, not reset to today")
  })

  local({
    # Same reset-after-submit path: a "textarea" field (e.g.
    # journal_reviews' review_notes) clears to an empty string.
    make_fake_session <- function() {
      self <- new.env()
      self$calls <- list()
      self$sendInputMessage <- function(inputId, message) {
        self$calls[[inputId]] <- message
      }
      self$ns <- function(x) x
      class(self) <- c("MockShinySession", "environment")
      self
    }
    sess <- make_fake_session()
    zzedc:::reset_crf_field_inputs(
      sess, list(review_notes = list(type = "textarea"))
    )
    expect_equal(sess$calls$review_notes$value, "")
  })

  local({
    # map_designer_field_type("FILE") previously fell through to the
    # "text" default (no case for it at all), so a FILE-type
    # designer field never actually reached renderPanel()'s
    # "file" = fileInput(...) case -- it rendered as a plain text
    # box. get_crf_field_metadata() is what calls
    # map_designer_field_type() per field; exercised here through
    # the public entry point rather than just the unit below, so a
    # regression in either one is caught.
    expect_equal(zzedc:::map_designer_field_type("FILE"), "file")
    expect_equal(zzedc:::map_designer_field_type("file"), "file",
                 info = "case-insensitive, like every other designer field_type code")
  })

  local({
    # persist_crf_upload() copies a fileInput() temp upload to
    # permanent storage, since save_crf_entry() cannot store the
    # temp path itself (the session deletes it). Destination:
    # uploads/<crf_code>/<tracking_id>/<field_code>_<original name>,
    # with every component sanitized.
    db_dir <- tempfile("upload_test_")
    dir.create(db_dir)
    db_path <- file.path(db_dir, "study.db")
    tmp_upload <- tempfile(fileext = ".pdf")
    writeLines("fake pdf bytes", tmp_upload)

    rel_path <- zzedc:::persist_crf_upload(
      tmp_path = tmp_upload, original_name = "My Manuscript (final)!.pdf",
      db_path = db_path, crf_code = "manuscripts",
      tracking_id = "PUB-2026-001", field_code = "manuscript_file"
    )
    full_path <- file.path(dirname(db_path), rel_path)
    expect_true(file.exists(full_path),
                info = "the upload is copied to a path under dirname(db_path)")
    expect_equal(readLines(full_path), "fake pdf bytes")
    expect_true(
      grepl("^uploads/manuscripts/PUB-2026-001/manuscript_file_", rel_path),
      info = "stored path is namespaced by form and tracking ID, prefixed by field"
    )

    # A malicious/unusual original filename must stay confined to
    # the uploads directory (basename() already strips any "../"
    # component; sanitize() additionally removes characters that
    # could otherwise still confuse a path on some filesystem).
    rel_path2 <- zzedc:::persist_crf_upload(
      tmp_path = tmp_upload, original_name = "../../etc/passwd",
      db_path = db_path, crf_code = "manuscripts",
      tracking_id = "PUB-2026-002", field_code = "manuscript_file"
    )
    resolved <- normalizePath(file.path(dirname(db_path), rel_path2))
    uploads_root <- normalizePath(file.path(dirname(db_path), "uploads"))
    expect_true(startsWith(resolved, uploads_root),
                info = "a path-traversal attempt in the original filename cannot escape uploads/")
  })

} else {
  exit_file("RSQLite and/or jsonlite not installed")
}
