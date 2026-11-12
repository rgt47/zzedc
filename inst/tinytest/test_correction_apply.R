library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# apply_correction() (2026-11-11). It used to mark a request APPLIED and
# write an audit record of the change without changing the stored
# value, and it never honored record locks (it tested a field,
# is_locked, that check_record_lock() does not return). These tests
# check the stored value itself.

if (!exists("apply_correction")) exit_file("data correction functions not available")
for (fn in c("ensure_data_entries_table", "db_insert_data_entry")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

setup_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") Sys.setenv(ZZEDC_OLD_KEY = old_key)
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  init_audit_logging(db_path = db)
  init_version_control(db_path = db)
  init_data_correction(db_path = db)
  conn <- connect_encrypted_db(db_path = db)
  DBI::dbExecute(conn, "CREATE TABLE vitals (id INTEGER PRIMARY KEY, subject_id TEXT,
                        sbp INTEGER, weight REAL, note TEXT)")
  DBI::dbExecute(conn, "INSERT INTO vitals (subject_id, sbp, weight, note)
                        VALUES ('S001', 220, 70.5, 'ok')")
  ensure_data_entries_table(conn)
  entry <- db_insert_data_entry(conn, "S001", "visit1", list(sbp = 220, arm = "A"),
                                created_by = "coordinator1")
  DBI::dbDisconnect(conn)
  list(db = db, entry_id = entry$entry_id)
}

cleanup_db <- function(db) {
  unlink(db)
  old <- Sys.getenv("ZZEDC_OLD_KEY")
  if (old != "") { Sys.setenv(DB_ENCRYPTION_KEY = old); Sys.unsetenv("ZZEDC_OLD_KEY") }
}

query <- function(db, sql, params = list()) {
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn))
  if (length(params)) DBI::dbGetQuery(conn, sql, params = params) else DBI::dbGetQuery(conn, sql)
}

request_and_approve <- function(db, table, record_id, field, from, to) {
  r <- create_correction_request(table, record_id, field, from, to, "TRANSCRIPTION_ERROR",
                                 reason_details = "Source document differs",
                                 requested_by = "coordinator1", db_path = db)
  approve_correction(r$request_id, reviewed_by = "data_manager", db_path = db)
  r$request_id
}

# A column correction changes the stored value, with audit and versions.
local({
  s <- setup_db()
  on.exit(cleanup_db(s$db), add = TRUE)
  id <- request_and_approve(s$db, "vitals", "1", "sbp", "220", "120")
  res <- apply_correction(id, "data_manager", db_path = s$db)
  expect_true(res$success, info = res$error %||% "")
  expect_identical(query(s$db, "SELECT sbp FROM vitals WHERE id = 1")$sbp, 120L,
                   info = "the stored value is changed, and keeps its integer type")
  ev <- query(s$db, "SELECT details, user_id FROM audit_log
                     WHERE event_type = 'UPDATE' AND table_name = 'vitals'
                       AND operation LIKE 'Data correction applied%'")
  expect_equal(nrow(ev), 1)
  d <- jsonlite::fromJSON(ev$details)
  expect_identical(d$old_value, "220")
  expect_identical(d$new_value, "120")
  expect_identical(d$reason, "TRANSCRIPTION_ERROR")
  expect_identical(d$approved_by, "data_manager")
  v <- query(s$db, "SELECT version_number, change_type, data_snapshot FROM record_versions
                    WHERE table_name = 'vitals' AND record_id = '1' ORDER BY version_number")
  expect_identical(v$change_type, c("CREATE", "UPDATE"),
                   info = "baseline of the prior state, then the corrected state")
  expect_true(grepl("220", v$data_snapshot[1]) && grepl("120", v$data_snapshot[2]))
  expect_true(res$version_recorded)

  again <- apply_correction(id, "data_manager", db_path = s$db)
  expect_false(again$success, info = "a request cannot be applied twice")
})

# A request whose original value no longer matches is refused, with no change.
local({
  s <- setup_db()
  on.exit(cleanup_db(s$db), add = TRUE)
  id <- request_and_approve(s$db, "vitals", "1", "sbp", "210", "120")
  res <- apply_correction(id, "data_manager", db_path = s$db)
  expect_false(res$success)
  expect_true(grepl("changed since", res$error))
  expect_identical(query(s$db, "SELECT sbp FROM vitals WHERE id = 1")$sbp, 220L)
  expect_identical(query(s$db, "SELECT status FROM correction_requests WHERE request_id = ?",
                         list(id))$status, "APPROVED", info = "the request stays approved")
  expect_equal(query(s$db, "SELECT COUNT(*) AS n FROM audit_log WHERE table_name = 'vitals'")$n, 0,
               info = "no audit record of a change that did not happen")
})

# Numeric comparison of the original value; type checks on the new value.
local({
  s <- setup_db()
  on.exit(cleanup_db(s$db), add = TRUE)
  id <- request_and_approve(s$db, "vitals", "1", "weight", "70.50", "75.5")
  expect_true(apply_correction(id, "data_manager", db_path = s$db)$success,
              info = "70.50 matches a stored 70.5")
  expect_equal(query(s$db, "SELECT weight FROM vitals WHERE id = 1")$weight, 75.5)

  id <- request_and_approve(s$db, "vitals", "1", "sbp", "220", "one-twenty")
  res <- apply_correction(id, "data_manager", db_path = s$db)
  expect_false(res$success)
  expect_true(grepl("not a number", res$error))
})

# A field inside a data_entries row's JSON is corrected.
local({
  s <- setup_db()
  on.exit(cleanup_db(s$db), add = TRUE)
  id <- request_and_approve(s$db, "data_entries", s$entry_id, "sbp", "220", "120")
  res <- apply_correction(id, "data_manager", db_path = s$db)
  expect_true(res$success, info = res$error %||% "")
  row <- query(s$db, "SELECT data_json, modified_by FROM data_entries WHERE entry_id = ?",
               list(s$entry_id))
  fields <- jsonlite::fromJSON(row$data_json)
  expect_equal(fields$sbp, 120, info = "JSON field corrected, still numeric")
  expect_identical(fields$arm, "A", info = "other fields untouched")
  expect_identical(row$modified_by, "data_manager")

  id <- request_and_approve(s$db, "data_entries", s$entry_id, "no_such_field", "", "x")
  # an absent field has an empty current value, so it can be filled
  expect_true(apply_correction(id, "data_manager", db_path = s$db)$success)
})

# Locks: a locked data_entries row, and a version lock held by another user.
local({
  s <- setup_db()
  on.exit(cleanup_db(s$db), add = TRUE)
  conn <- connect_encrypted_db(db_path = s$db)
  DBI::dbExecute(conn, "UPDATE data_entries SET locked = 1")
  DBI::dbDisconnect(conn)
  id <- request_and_approve(s$db, "data_entries", s$entry_id, "sbp", "220", "120")
  res <- apply_correction(id, "data_manager", db_path = s$db)
  expect_false(res$success)
  expect_true(isTRUE(res$requires_override), info = "a locked entry needs an override")

  ov <- request_correction_override(id, "LOCKED_RECORD",
                                    "Source document verified by monitor at visit 3",
                                    override_by = "data_manager", db_path = s$db)
  approve_override(ov$override_id, approved_by = "pi_user", db_path = s$db)
  expect_true(apply_correction(id, "data_manager", db_path = s$db)$success,
              info = "applied once the override is approved")

  lock_record("vitals", "1", locked_by = "monitor1", db_path = s$db)
  id2 <- request_and_approve(s$db, "vitals", "1", "sbp", "220", "130")
  res <- apply_correction(id2, "data_manager", db_path = s$db)
  expect_false(res$success, info = "a version lock held by someone else is honored")
  expect_true(grepl("locked by monitor1", res$error))
  expect_identical(query(s$db, "SELECT sbp FROM vitals WHERE id = 1")$sbp, 220L)
})

# Protected tables and columns.
local({
  s <- setup_db()
  on.exit(cleanup_db(s$db), add = TRUE)
  id <- request_and_approve(s$db, "audit_log", "1", "user_id", "x", "y")
  expect_true(grepl("cannot be changed", apply_correction(id, "dm", db_path = s$db)$error))
  id <- request_and_approve(s$db, "vitals", "1", "id", "1", "2")
  expect_true(grepl("cannot be changed", apply_correction(id, "dm", db_path = s$db)$error),
              info = "primary key refused")
})

# Atomicity: if the audit record fails, the data and the request are unchanged.
local({
  s <- setup_db()
  on.exit(cleanup_db(s$db), add = TRUE)
  id <- request_and_approve(s$db, "vitals", "1", "sbp", "220", "120")
  conn <- connect_encrypted_db(db_path = s$db)
  DBI::dbExecute(conn, "ALTER TABLE audit_chain RENAME TO audit_chain_moved")
  DBI::dbDisconnect(conn)
  res <- apply_correction(id, "data_manager", db_path = s$db)
  expect_false(res$success)
  expect_identical(query(s$db, "SELECT sbp FROM vitals WHERE id = 1")$sbp, 220L,
                   info = "value unchanged when its audit record cannot be written")
  expect_identical(query(s$db, "SELECT status FROM correction_requests WHERE request_id = ?",
                         list(id))$status, "APPROVED")
})
