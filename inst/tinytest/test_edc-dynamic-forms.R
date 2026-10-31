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
        default_value TEXT
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

} else {
  exit_file("RSQLite and/or jsonlite not installed")
}
