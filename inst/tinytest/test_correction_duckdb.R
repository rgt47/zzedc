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
for (fn in c("ensure_data_entries_table", "db_insert_data_entry")) {
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

# Reset the adapter cache so later test files in the same session
# resolve a plain sqlite backend again rather than the duckdb adapter
# this file's setup_duckdb() last configured (same reasoning as
# test_db-adapter-phase-c.R's matching reset).
get_db_adapter(
  config = list(db_backend = "sqlite", sqlite = list(path = tempfile(fileext = ".db"))),
  force_new = TRUE
)
