library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Regression test for a DuckDB-only bug found in a live browser
# walkthrough (2026-11-17): approve_correction() failed on every
# request with "Constraint Error: Violates foreign key constraint
# because key ... is still referenced by a foreign key in a different
# table." correction_history.request_id and
# correction_overrides.request_id both REFERENCES
# correction_requests(request_id); DuckDB can only update an indexed
# column in place when nothing references the row, and otherwise
# rewrites the UPDATE as a DELETE followed by an INSERT, which its
# "Over-Eager Constraint Checking in Foreign Keys" limitation (DuckDB
# docs, "Limitations of ART Indexes") flags on the DELETE half before
# the INSERT half restores the row. approve_correction()/
# reject_correction()/apply_correction() all UPDATE the (formerly
# indexed) status column. This never surfaced on SQLite, which
# updates the indexed column in place; see test_correction_apply.R
# for the SQLite-backed coverage of the same functions.

if (!requireNamespace("duckdb", quietly = TRUE)) {
  exit_file("duckdb package not installed")
}
if (!exists("apply_correction")) exit_file("data correction functions not available")
for (fn in c("ensure_data_entries_table", "db_insert_data_entry",
             "db_update_incomplete_data_entry", "migrate_correction_reasons")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

setup_duckdb <- function() {
  db <- tempfile(fileext = ".duckdb")
  config <- test_backend_config("duckdb")
  config$duckdb$path <- db
  get_db_adapter(config = config, force_new = TRUE)
  init_audit_logging(db_path = db)
  init_version_control(db_path = db)
  init_data_correction(db_path = db)
  conn <- connect_encrypted_db(db_path = db)
  DBI::dbExecute(conn, "CREATE TABLE vitals (id INTEGER PRIMARY KEY, sbp INTEGER)")
  DBI::dbExecute(conn, "INSERT INTO vitals VALUES (1, 220)")
  DBI::dbDisconnect(conn)
  db
}

cleanup_duckdb <- function(db) {
  tryCatch(get_db_adapter()$shutdown(), error = function(e) NULL)
  unlink(db)
}

query <- function(db, sql) {
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn))
  DBI::dbGetQuery(conn, sql)
}

local({
  db <- setup_duckdb()
  on.exit(cleanup_duckdb(db), add = TRUE)

  created <- create_correction_request(
    "vitals", "1", "sbp", "220", "120", "TRANSCRIPTION_ERROR",
    reason_details = "Source document differs",
    requested_by = "coordinator1", db_path = db
  )
  expect_true(created$success, info = created$error %||% "")

  approved <- approve_correction(created$request_id, reviewed_by = "data_manager",
                                 db_path = db)
  expect_true(approved$success,
              info = paste("approve_correction() on DuckDB:", approved$error %||% ""))
  expect_identical(query(db, "SELECT status FROM correction_requests")$status, "APPROVED")

  applied <- apply_correction(created$request_id, "data_manager", db_path = db)
  expect_true(applied$success,
              info = paste("apply_correction() on DuckDB:", applied$error %||% ""))
  expect_identical(query(db, "SELECT sbp FROM vitals WHERE id = 1")$sbp, 120L,
                   info = "the stored value is actually changed on DuckDB")
  expect_identical(query(db, "SELECT status FROM correction_requests")$status, "APPLIED")
})

# A second request on the same table, rejected rather than approved,
# exercises reject_correction()'s identical UPDATE pattern.
local({
  db <- setup_duckdb()
  on.exit(cleanup_duckdb(db), add = TRUE)

  created <- create_correction_request(
    "vitals", "1", "sbp", "220", "999", "TRANSCRIPTION_ERROR",
    reason_details = "Disputed value",
    requested_by = "coordinator1", db_path = db
  )
  rejected <- reject_correction(created$request_id, reviewed_by = "data_manager",
                                review_comments = "Source document confirms 220",
                                db_path = db)
  expect_true(rejected$success,
              info = paste("reject_correction() on DuckDB:", rejected$error %||% ""))
  expect_identical(query(db, "SELECT status FROM correction_requests")$status, "REJECTED")
  expect_identical(query(db, "SELECT sbp FROM vitals WHERE id = 1")$sbp, 220L,
                   info = "a rejected correction never touches the stored value")
})

# db_update_incomplete_data_entry() (Part D, incomplete-form-resume)
# is also an UPDATE against an indexed column (data_entries.entry_id,
# its PRIMARY KEY), the same shape of statement that tripped the bug
# above -- but unlike correction_requests(request_id),
# data_entries(entry_id) has no other table's FOREIGN KEY pointing at
# it (confirmed: grep -rn "REFERENCES data_entries" across R/ and
# inst/ finds nothing), so DuckDB has nothing to rewrite the UPDATE
# around. Verified directly here rather than assumed.
if (!exists("db_update_incomplete_data_entry", envir = asNamespace("zzedc"))) {
  exit_file("db_update_incomplete_data_entry not available")
}
local({
  db <- setup_duckdb()
  on.exit(cleanup_duckdb(db), add = TRUE)

  conn <- connect_encrypted_db(db_path = db)
  ensure_data_entries_table(conn)
  draft <- db_insert_data_entry(
    conn, subject_id = "PUB-1", form_name = "manuscripts",
    data = list(tracking_id = "PUB-1", status = "ideation"),
    is_complete = FALSE, created_by = "rgt"
  )
  expect_true(draft$success, info = draft$error %||% "")

  upd <- db_update_incomplete_data_entry(
    conn, entry_id = draft$entry_id,
    data = list(tracking_id = "PUB-1", status = "submitted"),
    is_complete = FALSE, modified_by = "coordinator2"
  )
  expect_true(upd$success,
              info = paste("db_update_incomplete_data_entry() on DuckDB:", upd$error %||% ""))

  rows <- DBI::dbGetQuery(conn, "SELECT * FROM data_entries")
  expect_equal(nrow(rows), 1, info = "an update on DuckDB, not a second row")
  expect_equal(as.integer(rows$is_complete), 0L)

  done <- db_update_incomplete_data_entry(
    conn, entry_id = draft$entry_id,
    data = list(tracking_id = "PUB-1", status = "accepted"),
    is_complete = TRUE, modified_by = "coordinator2"
  )
  expect_true(done$success, info = done$error %||% "")

  blocked <- db_update_incomplete_data_entry(
    conn, entry_id = draft$entry_id,
    data = list(tracking_id = "PUB-1", status = "should-not-apply"),
    is_complete = FALSE, modified_by = "someone_else"
  )
  expect_false(blocked$success,
                info = "a completed entry is refused on DuckDB just as on SQLite")
  DBI::dbDisconnect(conn)
})

# migrate_correction_reasons() (2026-11-19, DDE_DISCREPANCY):
# DuckDB-only bug found in this pass's own manual walkthrough --
# renaming correction_requests out of the way (the SQLite rebuild
# strategy) fails on DuckDB with "Dependency Error: Cannot alter entry
# ... because there are entries that depend on it", since
# correction_history/correction_overrides hold a REFERENCES
# correction_requests(request_id). Simulates an old (pre-
# DDE_DISCREPANCY) database by hand, with dependent rows in all three
# tables, then confirms the migration preserves them, a new
# DDE_DISCREPANCY request is accepted afterward, and a second run is a
# no-op.
local({
  db <- tempfile(fileext = ".duckdb")
  config <- test_backend_config("duckdb")
  config$duckdb$path <- db
  get_db_adapter(config = config, force_new = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbExecute(conn, "
    CREATE TABLE correction_requests (
      request_id INTEGER PRIMARY KEY,
      table_name TEXT NOT NULL, record_id TEXT NOT NULL, field_name TEXT NOT NULL,
      original_value TEXT, corrected_value TEXT NOT NULL,
      correction_reason TEXT NOT NULL CHECK(correction_reason IN
        ('TYPO', 'SOURCE_DOC_ERROR', 'CALCULATION_ERROR',
         'TRANSCRIPTION_ERROR', 'UNIT_ERROR', 'DATE_ERROR',
         'PROTOCOL_CLARIFICATION', 'QUERY_RESPONSE', 'OTHER')),
      reason_details TEXT, original_source_doc TEXT, corrected_source_doc TEXT,
      status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN
        ('PENDING', 'APPROVED', 'REJECTED', 'APPLIED', 'CANCELLED')),
      requested_by TEXT NOT NULL, requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      reviewed_by TEXT, reviewed_at TIMESTAMP, review_comments TEXT,
      applied_by TEXT, applied_at TIMESTAMP, request_hash TEXT NOT NULL,
      previous_request_hash TEXT, site_id TEXT, study_id TEXT, subject_id TEXT,
      visit_id TEXT, form_id TEXT
    )
  ")
  DBI::dbExecute(conn, "
    CREATE TABLE correction_history (
      history_id INTEGER PRIMARY KEY,
      request_id INTEGER NOT NULL REFERENCES correction_requests(request_id),
      action TEXT NOT NULL, action_by TEXT NOT NULL,
      action_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, action_details TEXT,
      action_hash TEXT NOT NULL, previous_hash TEXT
    )
  ")
  DBI::dbExecute(conn, "
    CREATE TABLE correction_overrides (
      override_id INTEGER PRIMARY KEY,
      request_id INTEGER NOT NULL REFERENCES correction_requests(request_id),
      override_type TEXT NOT NULL, override_reason TEXT NOT NULL,
      override_by TEXT NOT NULL, override_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      approved_by TEXT, approved_at TIMESTAMP, override_hash TEXT NOT NULL
    )
  ")
  DBI::dbExecute(conn, "INSERT INTO correction_requests (request_id, table_name, record_id, field_name, corrected_value, correction_reason, requested_by, request_hash) VALUES (1, 'vitals', '1', 'sbp', '120', 'TYPO', 'alice', 'h1')")
  DBI::dbExecute(conn, "INSERT INTO correction_history (history_id, request_id, action, action_by, action_hash) VALUES (1, 1, 'CREATED', 'alice', 'hh1')")
  DBI::dbExecute(conn, "INSERT INTO correction_overrides (override_id, request_id, override_type, override_reason, override_by, override_hash) VALUES (1, 1, 'LOCKED_RECORD', 'test', 'alice', 'ho1')")

  expect_true(isTRUE(as.logical(migrate_correction_reasons(conn))),
             info = "migration runs without the DuckDB Dependency Error")

  preserved <- DBI::dbGetQuery(conn, "SELECT request_id, correction_reason, requested_by FROM correction_requests")
  expect_equal(preserved$correction_reason, "TYPO")
  expect_equal(nrow(DBI::dbGetQuery(conn, "SELECT * FROM correction_history")), 1)
  expect_equal(nrow(DBI::dbGetQuery(conn, "SELECT * FROM correction_overrides")), 1)

  inserted <- DBI::dbExecute(conn, "INSERT INTO correction_requests (request_id, table_name, record_id, field_name, corrected_value, correction_reason, requested_by, request_hash) VALUES (2, 'data_entries', 'E1', 'sbp', '150', 'DDE_DISCREPANCY', 'bob', 'h2')")
  expect_equal(inserted, 1, info = "DDE_DISCREPANCY is now accepted by the migrated CHECK constraint")

  expect_true(isTRUE(as.logical(migrate_correction_reasons(conn))),
             info = "re-running the migration on an already-migrated table is a no-op")
  expect_equal(DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM correction_requests")$n, 2,
              info = "the second run did not duplicate or lose rows")
})

# Reset the adapter cache so later test files in the same session
# resolve a plain sqlite backend again rather than the duckdb adapter
# this file's setup_duckdb() last configured (same reasoning as
# test_db-adapter-phase-c.R's matching reset).
get_db_adapter(
  config = list(db_backend = "sqlite", sqlite = list(path = tempfile(fileext = ".db"))),
  force_new = TRUE
)
