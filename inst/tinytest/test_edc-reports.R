library(tinytest)

# Regression tests for R/edc_reports.R, the real-data backing for the
# Reports, Data Explorer, and Export tabs (previously unrelated demo
# content disconnected from data_entries; see
# docs/edc-reports-tabs-plan-2026-10-31.md).

if (requireNamespace("RSQLite", quietly = TRUE) &&
      requireNamespace("jsonlite", quietly = TRUE)) {

  .make_reports_fixture <- function() {
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
        field_width INTEGER DEFAULT 100,
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
    zzedc:::ensure_data_entries_table(conn)

    DBI::dbExecute(conn,
      "INSERT INTO crf_definitions (crf_code, crf_name, created_by) VALUES (?, ?, ?)",
      params = list("MANUSCRIPTS", "MANUSCRIPTS Form", "test"))
    DBI::dbExecute(conn, "
      INSERT INTO designer_fields
        (design_id, field_code, field_label, field_type, field_row, is_required)
      VALUES
        (1, 'tracking_id', 'Tracking ID', 'TEXT', 1, 1),
        (1, 'status', 'Status', 'SELECT', 2, 1)
    ")
    status_field_id <- DBI::dbGetQuery(conn,
      "SELECT field_id FROM designer_fields WHERE field_code = 'status'")$field_id
    DBI::dbExecute(conn, "
      INSERT INTO designer_field_options
        (field_id, option_value, option_label, option_order)
      VALUES (?, 'ideation', 'Ideation', 1), (?, 'submitted', 'Submitted', 2)
    ", params = list(status_field_id, status_field_id))

    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-1", form_name = "manuscripts",
      data = list(tracking_id = "PUB-1", status = "ideation"),
      is_complete = TRUE, created_by = "rgt"
    )
    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-2", form_name = "manuscripts",
      data = list(tracking_id = "PUB-2", status = "submitted"),
      is_complete = TRUE, created_by = "rgt"
    )
    # A third entry missing the required status field, to exercise
    # compute_data_quality_summary()'s "required" branch.
    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-3", form_name = "manuscripts",
      data = list(tracking_id = "PUB-3", status = ""),
      is_complete = FALSE, created_by = "rgt"
    )

    conn
  }

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    entries <- zzedc:::get_data_entries(conn)
    expect_equal(nrow(entries), 3)
    expect_true("fields" %in% names(entries))
    expect_equal(entries$fields[entries$subject_id == "PUB-1"][[1]]$status,
                 "ideation")

    scoped <- zzedc:::get_data_entries(conn, crf_code = "manuscripts")
    expect_equal(nrow(scoped), 3)
    expect_equal(nrow(zzedc:::get_data_entries(conn, crf_code = "courses")), 0)
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    summary <- zzedc:::summarize_entries_by_form(conn)
    expect_equal(summary$n_entries[summary$crf_code == "MANUSCRIPTS"], 2,
                 info = paste(
                   "PUB-3 is an open is_complete=0 draft; the Reports tab's",
                   "per-form counts are an aggregate report and exclude it",
                   "(see get_data_entries()'s include_incomplete and",
                   "db_update_incomplete_data_entry())"
                 ))
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    q <- zzedc:::compute_data_quality_summary(conn)
    expect_equal(q$total, 3)
    expect_equal(q$n_valid, 2,
                 info = "PUB-1 and PUB-2 both have required+valid-choice status")
    expect_equal(q$n_required_missing, 1,
                 info = "PUB-3's blank status is flagged required, not invalid_choice")
    expect_equal(nrow(q$flagged), 1)
    expect_equal(q$flagged$subject_id[1], "PUB-3")
    expect_equal(q$n_unknown_form, 0)
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # An entry for a form with no matching crf_definitions row (e.g.
    # a leftover from a form that predates this study's real CRF
    # import, or has since been removed) must be excluded from both
    # n_valid and the flagged count, tracked separately via
    # n_unknown_form, and NOT counted in `total` -- otherwise total
    # would not reconcile with n_valid + the number of flagged
    # entries.
    zzedc:::db_insert_data_entry(
      conn, subject_id = "1", form_name = "edc_visit_form",
      data = list(subject_id = "1"), is_complete = TRUE, created_by = "rgt"
    )

    q <- zzedc:::compute_data_quality_summary(conn)
    expect_equal(q$total, 3,
                 info = "the orphaned-form entry is excluded from total")
    expect_equal(q$n_unknown_form, 1)
    expect_equal(nrow(q$flagged), 1,
                 info = "still just PUB-3's required flag, not the orphaned entry")
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    tab <- zzedc:::summarize_choice_field_values(conn)
    expect_equal(nrow(tab), 2)
    expect_equal(sort(tab$option_label), c("Ideation", "Submitted"))
    expect_true(all(tab$n == 1))
    expect_true("option_value" %in% names(tab),
                info = "the raw stored value, for the Domain Breakdown drill-through to filter entries by")
    expect_equal(sort(tab$option_value), c("ideation", "submitted"),
                 info = "option_value is the raw value, not option_label's display form")
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    flat <- zzedc:::flatten_crf_entries_for_export(conn, "manuscripts")
    expect_equal(nrow(flat), 2,
                 info = paste(
                   "PUB-3 is an open is_complete=0 draft;",
                   "flatten_crf_entries_for_export() excludes drafts by",
                   "default (include_incomplete = FALSE) so an export",
                   "never mixes an unfinished record in with finished ones"
                 ))
    expect_true(all(c("subject_id", "tracking_id", "status") %in% names(flat)))
    expect_equal(flat$status[flat$subject_id == "PUB-1"], "ideation")
    expect_false("PUB-3" %in% flat$subject_id)

    expect_error(zzedc:::flatten_crf_entries_for_export(conn, "nope"))
  })

  # Reproduced live against ~/prj/srv/14-promotion-tracker's real
  # manuscripts entries (2026-11-18): a cleared dateInput() (or
  # similarly cleared optional field) round-trips through
  # jsonlite::toJSON()/fromJSON() as a zero-length list(), not a
  # length-1 NA -- JSON has no NA, only null or []. The field loop's
  # as.character(v) on that zero-length value returned character(0),
  # which vapply() rejected ("values must be length 1, but FUN(X[[1]])
  # result is length 0"), crashing the Manuscripts report and the
  # Export tab outright for any form with such a row.
  # flatten_all_entries_for_explorer() already guarded against this;
  # flatten_crf_entries_for_export() did not.
  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # is_complete = TRUE here (unlike the fixture's PUB-3): this row
    # exercises the blank-field coercion below, which only matters for
    # a row flatten_crf_entries_for_export() actually includes -- an
    # is_complete = 0 draft is excluded before the coercion ever runs
    # (see the test above).
    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-4", form_name = "manuscripts",
      data = list(tracking_id = "PUB-4", status = character(0)),
      is_complete = TRUE, created_by = "rgt"
    )

    flat <- zzedc:::flatten_crf_entries_for_export(conn, "manuscripts")
    expect_equal(nrow(flat), 3,
                 info = "PUB-1, PUB-2, PUB-4 are complete; PUB-3's draft stays excluded")
    row <- flat[flat$subject_id == "PUB-4", ]
    expect_true(is.na(row$status),
                info = "a cleared field reads as NA, not a crash")
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    html <- zzedc:::generate_personal_statement_draft(conn)
    expect_true(is.character(html) && length(html) == 1)
    expect_true(grepl("3 manuscript", html, fixed = TRUE))
    expect_true(grepl("0 course", html, fixed = TRUE))

    # A non-zero count is a drill-through link (inst/app/
    # report_drilldown.R's 'report_drill' Shiny input, {form:
    # "manuscripts"}); a zero count stays plain text, since there is
    # nothing to list.
    expect_true(grepl(
      "onclick=\"Shiny.setInputValue\\('report_drill', \\{form: 'manuscripts'\\}",
      html
    ), info = "manuscripts (3 entries) is linked")
    expect_false(grepl(
      "onclick=\"Shiny.setInputValue\\('report_drill', \\{form: 'courses'\\}",
      html
    ), info = "courses (0 entries) is not linked")
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # A blank optional field is saved as NA_character_, which
    # round-trips through jsonlite::toJSON()/fromJSON() as an R
    # NULL, not NA (JSON has no NA, only null). Every real entry
    # with any blank optional field hits this -- reproduced directly
    # against the live promotion-tracker deployment, where it broke
    # the Data Explorer tab outright (vapply() error, uncaught,
    # wedging the whole Shiny session rather than just that output).
    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-4", form_name = "manuscripts",
      data = list(tracking_id = "PUB-4", status = "ideation",
                  notes = NA_character_),
      is_complete = TRUE, created_by = "rgt"
    )

    flat <- zzedc:::flatten_all_entries_for_explorer(conn)
    expect_equal(nrow(flat), 4)
    row <- flat[flat$subject_id == "PUB-4", ]
    expect_true(grepl("tracking_id=PUB-4", row$fields, fixed = TRUE))
    expect_true(grepl("status=ideation", row$fields, fixed = TRUE))
    expect_true(grepl("notes=", row$fields, fixed = TRUE),
                info = "a NULL-valued field renders as an empty value, not a vapply crash")
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # A dateInput() cleared to empty in the EDC tab serializes as
    # JSON `[]` (a zero-length value), not `null` -- a second,
    # distinct shape of "blank" from the NULL case above, also
    # reproduced directly against the live deployment (clearing
    # Submission/Acceptance/Publication Date before submitting).
    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-5", form_name = "manuscripts",
      data = list(tracking_id = "PUB-5", status = "ideation",
                  notes = character(0)),
      is_complete = TRUE, created_by = "rgt"
    )

    flat <- zzedc:::flatten_all_entries_for_explorer(conn)
    expect_equal(nrow(flat), 4)
    row <- flat[flat$subject_id == "PUB-5", ]
    expect_true(grepl("tracking_id=PUB-5", row$fields, fixed = TRUE))
    expect_true(grepl("notes=", row$fields, fixed = TRUE),
                info = "a zero-length field value renders as an empty value, not a vapply crash")
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # The fixture's PUB-1/PUB-2/PUB-3 entries don't match the
    # PUB-YYYY-N convention at all, so they're ignored; a year with
    # no matching entries yet starts at 001.
    expect_equal(zzedc:::next_manuscript_tracking_id(conn, year = "2026"),
                 "PUB-2026-001")
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-2026-001", form_name = "manuscripts",
      data = list(tracking_id = "PUB-2026-001", status = "ideation"),
      is_complete = TRUE, created_by = "rgt"
    )
    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-2026-007", form_name = "manuscripts",
      data = list(tracking_id = "PUB-2026-007", status = "ideation"),
      is_complete = TRUE, created_by = "rgt"
    )
    # A different year's entry must not influence the 2026 sequence.
    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-2025-099", form_name = "manuscripts",
      data = list(tracking_id = "PUB-2025-099", status = "ideation"),
      is_complete = TRUE, created_by = "rgt"
    )

    expect_equal(
      zzedc:::next_manuscript_tracking_id(conn, year = "2026"), "PUB-2026-008",
      info = "one past the highest existing N for that year, ignoring other years and non-matching IDs"
    )
  })

  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-2026-001", form_name = "manuscripts",
      data = list(tracking_id = "PUB-2026-001", status = "ideation"),
      is_complete = TRUE, created_by = "rgt"
    )

    expect_true(zzedc:::tracking_id_already_used(conn, "manuscripts", "PUB-2026-001"))
    expect_false(zzedc:::tracking_id_already_used(conn, "manuscripts", "PUB-2026-002"))
    expect_false(zzedc:::tracking_id_already_used(conn, "manuscripts", ""),
                 info = "a blank value is never flagged as a duplicate")
    expect_false(zzedc:::tracking_id_already_used(conn, "courses", "PUB-2026-001"),
                 info = "courses has no tracking-ID convention, so uniqueness is not enforced there either")
  })

  local({
    # get_data_entries() must tolerate `data_entries` not existing
    # yet -- it is only created lazily, on first submission, so a
    # freshly initialized or freshly rebuilt database (e.g. via
    # setup_zzedc_from_gsheets(overwrite = TRUE)) has no entries and
    # no table, not an error. Deliberately does NOT call
    # ensure_data_entries_table() here, unlike .make_reports_fixture().
    conn <- DBI::dbConnect(RSQLite::SQLite(), tempfile(fileext = ".db"))
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    expect_false(DBI::dbExistsTable(conn, "data_entries"))

    entries <- zzedc:::get_data_entries(conn)
    expect_equal(nrow(entries), 0)
    expect_true(all(c("entry_id", "subject_id", "form_name",
                       "created_date", "created_by", "fields") %in%
                       names(entries)))

    flattened <- zzedc:::flatten_all_entries_for_explorer(conn)
    expect_equal(nrow(flattened), 0,
                 info = "Data Explorer's source query must not error on a table-less database")

    expect_equal(zzedc:::.existing_tracking_ids(conn, "manuscripts"), character(0))
  })

  # Regression test, found on review (2026-11-20): no reader of
  # data_entries excluded the non-canonical (second) row of a
  # double-data-entry pair, so every aggregate count, export, and
  # Data Explorer listing double-counted every double-entered
  # subject/form. get_data_entries(canonical_dde_only = TRUE) and its
  # callers must each see only the chronologically first row of a
  # dde_group_id pair; the default (FALSE) and the tracking-ID/
  # case-report call sites that never pass TRUE must still see both.
  local({
    conn <- .make_reports_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    group_id <- "DDE-TEST-GROUP-1"
    first <- zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-DDE", form_name = "manuscripts",
      data = list(tracking_id = "PUB-DDE", status = "ideation"),
      is_complete = TRUE, created_by = "alice", dde_group_id = group_id
    )
    Sys.sleep(0.01)
    second <- zzedc:::db_insert_data_entry(
      conn, subject_id = "PUB-DDE", form_name = "manuscripts",
      data = list(tracking_id = "PUB-DDE", status = "submitted"),
      is_complete = TRUE, created_by = "bob", dde_group_id = group_id
    )
    expect_true(first$success)
    expect_true(second$success)

    # Default behavior (canonical_dde_only = FALSE) is unchanged:
    # both rows of the pair still come back, alongside the three
    # ordinary single-keyed entries the fixture already has.
    all_entries <- zzedc:::get_data_entries(conn)
    expect_equal(nrow(all_entries), 5)

    canonical <- zzedc:::get_data_entries(conn, canonical_dde_only = TRUE)
    expect_equal(nrow(canonical), 4,
                 info = "the pair's second (non-canonical) row is excluded")
    expect_true(first$entry_id %in% canonical$entry_id)
    expect_false(second$entry_id %in% canonical$entry_id)

    # The three aggregate/export readers that must not double-count.
    summary <- zzedc:::summarize_entries_by_form(conn)
    expect_equal(
      summary$n_entries[summary$crf_code == "MANUSCRIPTS"], 3,
      info = "PUB-1, PUB-2, and the DDE pair's one canonical row -- not 4"
    )

    q <- zzedc:::compute_data_quality_summary(conn)
    expect_equal(q$total, 4,
                 info = "3 originals + 1 canonical DDE row, not 5")

    flat <- zzedc:::flatten_crf_entries_for_export(conn, "manuscripts")
    expect_equal(nrow(flat), 3,
                 info = "PUB-1, PUB-2, and one PUB-DDE row -- not two PUB-DDE rows")
    expect_equal(sum(flat$subject_id == "PUB-DDE"), 1)
    expect_equal(flat$status[flat$subject_id == "PUB-DDE"], "ideation",
                 info = "the canonical (first) entry's value, not the second entry's")

    # Readers that must keep seeing both rows regardless: tracking-ID
    # bookkeeping (the second entry's tracking_id is still claimed)
    # and generate_subject_case_report()'s own get_data_entries(subject_id = )
    # call (Part 11 requires a subject's complete-copy report to show
    # the full history, superseded or not -- it never passes
    # canonical_dde_only = TRUE).
    expect_true(zzedc:::tracking_id_already_used(conn, "manuscripts", "PUB-DDE"))
    case_entries <- zzedc:::get_data_entries(conn, subject_id = "PUB-DDE")
    expect_equal(nrow(case_entries), 2,
                 info = "a subject's full history must include both DDE rows, not just the canonical one")
  })

  local({
    # .zzedc_tab_or_login(): every Reports/Data Explorer/Export tab's
    # top-level renderUI() previously showed its real content
    # regardless of user_input$authenticated -- only EDC Forms'
    # output$ui checked it. make_content() must not even be called
    # (never mind its result shown) when not authenticated, so a
    # tab's own query doesn't run just to produce HTML that then
    # goes unused.
    called <- FALSE
    ui <- zzedc:::.zzedc_tab_or_login(
      list(authenticated = FALSE),
      function() { called <<- TRUE; "real content" }
    )
    expect_false(called,
                 info = "a tab's content is not built at all for an unauthenticated session")
    expect_true(inherits(ui, "shiny.tag") || inherits(ui, "shiny.tag.list"),
                info = "an unauthenticated session gets a login prompt, not NULL or an error")

    called <- FALSE
    ui <- zzedc:::.zzedc_tab_or_login(
      list(authenticated = TRUE),
      function() { called <<- TRUE; "real content" }
    )
    expect_true(called)
    expect_equal(ui, "real content")
  })

} else {
  exit_file("RSQLite and/or jsonlite not installed")
}
