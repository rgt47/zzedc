library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Regression tests for zzedc:::ensure_data_entries_table() and
# zzedc:::db_insert_data_entry() (R/db_data_entries.R), which the
# EDC tab's study-specific forms/save.R uses to persist submitted
# visit data into the canonical `data_entries` table.

if (requireNamespace("RSQLite", quietly = TRUE) &&
      requireNamespace("jsonlite", quietly = TRUE)) {

  local({
    db_path <- tempfile(fileext = ".db")
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    zzedc:::ensure_data_entries_table(conn)
    expect_true("data_entries" %in% DBI::dbListTables(conn))

    # Idempotent: calling it again on an existing table must not error.
    expect_silent(zzedc:::ensure_data_entries_table(conn))
  })

  local({
    db_path <- tempfile(fileext = ".db")
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    zzedc:::ensure_data_entries_table(conn)

    res1 <- zzedc:::db_insert_data_entry(
      conn,
      subject_id = "S001",
      form_name = "edc_visit_form",
      data = list(subject_id = "S001", visit_date = "2026-10-28",
                  age = 54, sex = "F"),
      visit_label = "EDC Visit",
      visit_date = "2026-10-28",
      is_complete = TRUE,
      created_by = "rgt"
    )
    expect_true(res1$success)
    expect_true(is.character(res1$entry_id) && nzchar(res1$entry_id))

    res2 <- zzedc:::db_insert_data_entry(
      conn,
      subject_id = "S002",
      form_name = "edc_visit_form",
      data = list(subject_id = "S002", age = 61),
      created_by = "rgt"
    )
    expect_true(res2$success,
                info = "insert must succeed when visit_label/visit_date are omitted")
    expect_true(res1$entry_id != res2$entry_id,
                info = "two inserts in quick succession must get distinct entry_ids")

    rows <- DBI::dbGetQuery(conn,
                             "SELECT * FROM data_entries ORDER BY subject_id")
    expect_equal(nrow(rows), 2)
    expect_equal(rows$subject_id, c("S001", "S002"))
    expect_true(all(rows$is_complete == 1))

    parsed <- jsonlite::fromJSON(rows$data_json[1])
    expect_equal(parsed$age, 54)
    expect_equal(parsed$sex, "F")
  })

  # A NULL/NA subject_id (violating the NOT NULL constraint) must
  # fail cleanly via the returned list, not throw.
  local({
    db_path <- tempfile(fileext = ".db")
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    zzedc:::ensure_data_entries_table(conn)

    bad <- zzedc:::db_insert_data_entry(
      conn,
      subject_id = NA_character_,
      form_name = "edc_visit_form",
      data = list(age = 10),
      created_by = "rgt"
    )
    expect_false(bad$success)
    expect_true(is.character(bad$error) && nzchar(bad$error))
  })

} else {
  exit_file("RSQLite and/or jsonlite not installed")
}
