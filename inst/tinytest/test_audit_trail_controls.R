library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Audit-trail controls added 2026-11-11 (21 CFR 11.10(e), HIPAA
# 164.312(b)): case report form entries audited in the same transaction
# as the data; fail-closed writes under 'regulated'; append-only
# triggers; no deletion of audit records; external checkpoints that
# detect a rewrite of the whole chain; an audit viewer that reads the
# real trail and escapes its content; parameterized trail queries;
# login and session events with client address and session token;
# a working automatic logoff.

ns <- asNamespace("zzedc")
for (fn in c(".ensure_audit_tables", ".append_audit_record", ".with_db_transaction",
             ".audit_hash_content", "ensure_data_entries_table", "db_insert_data_entry",
             "cleanup_audit_logs", "audit_log_display_frame", "enable_session_timeout",
             "log_security_event")) {
  assign(fn, get(fn, envir = ns))
}

with_profile <- function(profile, code) {
  old <- options(zzedc.security_profile = profile)
  on.exit(options(old), add = TRUE)
  force(code)
}

new_db <- function() {
  path <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, "CREATE TABLE placeholder (x INTEGER)")
  list(path = path, con = con)
}

with_cached_sqlite <- function(path, code) {
  cache <- get(".db_adapter_cache", envir = ns)
  had <- exists("adapter", envir = cache)
  prev <- if (had) cache$adapter else NULL
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = path)), force_new = TRUE)
  on.exit(if (had) assign("adapter", prev, envir = cache)
          else if (exists("adapter", envir = cache)) rm("adapter", envir = cache), add = TRUE)
  force(code)
}

# ---------------------------------------------------------------
# Case report form entries are audited with the data
# ---------------------------------------------------------------

local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  ensure_data_entries_table(db$con)
  res <- db_insert_data_entry(db$con, subject_id = "S-001", form_name = "visit1",
                              data = list(weight = 72.5, sbp = 120),
                              created_by = "coordinator1",
                              ip_address = "198.51.100.7", session_id = "tok123")
  expect_true(res$success)
  ev <- DBI::dbGetQuery(db$con, "SELECT * FROM audit_log WHERE table_name = 'data_entries'")
  expect_equal(nrow(ev), 1, info = "one audit record per entry")
  expect_identical(ev$event_type, "INSERT")
  expect_identical(ev$record_id, res$entry_id)
  expect_identical(ev$user_id, "coordinator1")
  expect_identical(ev$ip_address, "198.51.100.7", info = "client address recorded")
  expect_identical(ev$session_id, "tok123", info = "session recorded")
  d <- jsonlite::fromJSON(ev$details)
  expect_equal(d$new_values$weight, 72.5, info = "submitted values recorded")
  expect_identical(d$subject_id, "S-001")

  # Atomicity: if the audit record cannot be written, the entry is not saved.
  DBI::dbExecute(db$con, "ALTER TABLE audit_chain RENAME TO audit_chain_moved")
  bad <- db_insert_data_entry(db$con, subject_id = "S-002", form_name = "visit1",
                              data = list(weight = 80), created_by = "coordinator1")
  expect_false(bad$success, info = "save fails when its audit record fails")
  n <- DBI::dbGetQuery(db$con, "SELECT COUNT(*) AS n FROM data_entries WHERE subject_id = 'S-002'")$n
  expect_equal(n, 0, info = "no unaudited entry is left behind (rolled back)")
})

# ---------------------------------------------------------------
# Fail-closed under 'regulated'
# ---------------------------------------------------------------

local({
  db <- new_db()
  DBI::dbDisconnect(db$con)
  on.exit(unlink(db$path), add = TRUE)
  with_cached_sqlite(db$path, {
    # No audit tables: the write fails.
    with_profile("standard", {
      expect_warning(r <- log_audit_event("UPDATE", "t", "1", "op", user_id = "u"),
                     "Failed to log")
      expect_false(r, info = "standard: warning and FALSE, as before")
    })
    with_profile("regulated", {
      expect_error(log_audit_event("UPDATE", "t", "1", "op", user_id = "u"),
                   "could not be written", info = "regulated: an error")
    })
  })
})

# ---------------------------------------------------------------
# Append-only tables; no deletion
# ---------------------------------------------------------------

local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  .ensure_audit_tables(db$con)
  expect_identical(audit_protection_status(db$con), "database triggers")
  .with_db_transaction(db$con, function(c) {
    .append_audit_record(c, "UPDATE", "t", "1", "first", user_id = "u")
  })
  expect_error(DBI::dbExecute(db$con, "UPDATE audit_log SET user_id = 'x'"), "append-only")
  expect_error(DBI::dbExecute(db$con, "DELETE FROM audit_log"), "append-only")
  expect_error(DBI::dbExecute(db$con, "UPDATE audit_chain SET record_hash = 'x'"), "append-only")
  expect_error(DBI::dbExecute(db$con, "DELETE FROM audit_chain"), "append-only")
  expect_silent(DBI::dbExecute(db$con, "UPDATE audit_chain SET verified = 1, verification_date = '2026-01-01'"))
  expect_equal(DBI::dbGetQuery(db$con, "SELECT COUNT(*) AS n FROM audit_log")$n, 1)
  expect_error(cleanup_audit_logs(db$con, 1), "not deleted",
               info = "the audit-log purge function refuses")
})

# ---------------------------------------------------------------
# External checkpoints detect a full-chain rewrite
# ---------------------------------------------------------------

rewrite_chain_from <- function(con, from_order, new_user) {
  # An attacker with schema rights: drop the triggers, alter a record,
  # and recompute every later hash so the chain verifies again.
  for (t in c("zzedc_audit_log_no_update", "zzedc_audit_chain_no_update")) {
    DBI::dbExecute(con, paste("DROP TRIGGER IF EXISTS", t))
  }
  rows <- DBI::dbGetQuery(con, "
    SELECT c.chain_order, l.* FROM audit_chain c JOIN audit_log l ON l.audit_id = c.audit_id
    ORDER BY c.chain_order")
  prev <- if (from_order > 1) rows$audit_hash[from_order - 1] else "GENESIS"
  for (i in from_order:nrow(rows)) {
    r <- rows[i, ]
    if (i == from_order) r$user_id <- new_user
    h <- digest::digest(.audit_hash_content(r$event_type, r$table_name, r$record_id, r$operation,
                                            r$details, r$user_id, r$ip_address, r$session_id,
                                            r$timestamp, prev), algo = "sha256")
    DBI::dbExecute(con, "UPDATE audit_log SET user_id = ?, previous_hash = ?, audit_hash = ? WHERE audit_id = ?",
                   params = list(r$user_id, prev, h, r$audit_id))
    DBI::dbExecute(con, "UPDATE audit_chain SET previous_hash = ?, record_hash = ? WHERE audit_id = ?",
                   params = list(prev, h, r$audit_id))
    prev <- h
  }
}

local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  .ensure_audit_tables(db$con)
  for (k in 1:5) {
    .with_db_transaction(db$con, function(c) {
      .append_audit_record(c, "UPDATE", "subjects", paste0("R", k), "edit", user_id = "alice")
    })
  }
  dir <- tempfile("cp_")
  key <- "checkpoint-test-key-0123456789"
  cp <- audit_checkpoint(dir, key = key, conn = db$con, database = "study.db")
  expect_equal(cp$chain_order, 5L)
  cpfile <- file.path(dir, "audit_checkpoints.jsonl")

  with_cached_sqlite(db$path, with_profile("development", {
    v <- verify_audit_checkpoints(cpfile, key = key)
    expect_true(v$valid, info = paste("clean trail matches its checkpoint:", v$message))

    rewrite_chain_from(db$con, 2, "mallory")
    expect_true(verify_audit_integrity()$valid,
                info = "a full recompute fools the hash chain alone (why checkpoints are needed)")
    v <- verify_audit_checkpoints(cpfile, key = key)
    expect_false(v$valid, info = "the checkpoint detects the rewrite")
    expect_true(grepl("rewritten", v$failures$reason[1]))

    expect_false(verify_audit_checkpoints(cpfile, key = "wrong-key-wrong-key")$valid,
                 info = "a wrong key fails the checkpoint")
    lines <- readLines(cpfile)
    forged <- jsonlite::fromJSON(lines[1])
    forged$record_hash <- "0000"
    writeLines(as.character(jsonlite::toJSON(forged, auto_unbox = TRUE)), cpfile)
    v <- verify_audit_checkpoints(cpfile, key = key)
    expect_true(grepl("MAC", v$failures$reason[1]), info = "an edited checkpoint is detected")
  }))
  unlink(dir, recursive = TRUE)
})

local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  .ensure_audit_tables(db$con)
  for (k in 1:3) .with_db_transaction(db$con, function(c) .append_audit_record(c, "UPDATE", "t", k, "e", user_id = "a"))
  dir <- tempfile("cp_")
  audit_checkpoint(dir, key = "k-0123456789abcdef", conn = db$con)
  DBI::dbExecute(db$con, "DROP TRIGGER zzedc_audit_chain_no_delete")
  DBI::dbExecute(db$con, "DROP TRIGGER zzedc_audit_log_no_delete")
  DBI::dbExecute(db$con, "DELETE FROM audit_chain WHERE chain_order = 3")
  DBI::dbExecute(db$con, "DELETE FROM audit_log WHERE audit_id = 3")
  with_cached_sqlite(db$path, with_profile("development", {
    v <- verify_audit_checkpoints(file.path(dir, "audit_checkpoints.jsonl"),
                                  key = "k-0123456789abcdef")
    expect_false(v$valid)
    expect_true(grepl("removed", v$failures$reason[1]), info = "truncation of the tail is detected")
  }))
  unlink(dir, recursive = TRUE)
})

# ---------------------------------------------------------------
# get_audit_trail(): filters are parameters
# ---------------------------------------------------------------

local({
  db <- new_db()
  DBI::dbDisconnect(db$con)
  on.exit(unlink(db$path), add = TRUE)
  with_cached_sqlite(db$path, with_profile("development", {
    init_audit_logging()
    log_audit_event("UPDATE", "t", "1", "op", user_id = "alice")
    log_audit_event("UPDATE", "t", "2", "op", user_id = "bob")
    expect_equal(nrow(get_audit_trail(list(user = "alice"))), 1)
    inj <- get_audit_trail(list(user = "x' OR '1'='1"))
    expect_equal(nrow(inj), 0, info = "a quote in a filter value cannot widen the query")
  }))
})

# ---------------------------------------------------------------
# Client address and session token
# ---------------------------------------------------------------

ctx <- session_audit_context(list(request = list(REMOTE_ADDR = "127.0.0.1",
                                                 HTTP_X_FORWARDED_FOR = "203.0.113.9, 10.0.0.1"),
                                  token = "abc"))
expect_identical(ctx$ip_address, "203.0.113.9", info = "client address from a local proxy")
expect_identical(ctx$session_id, "abc")
ctx <- session_audit_context(list(request = list(REMOTE_ADDR = "198.51.100.4",
                                                 HTTP_X_FORWARDED_FOR = "1.2.3.4")))
expect_identical(ctx$ip_address, "198.51.100.4",
                 info = "X-Forwarded-For from a remote peer is not believed")

# ---------------------------------------------------------------
# Audit viewer: the real trail, escaped, no fabricated rows
# ---------------------------------------------------------------

local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  .ensure_audit_tables(db$con)
  .with_db_transaction(db$con, function(c) {
    .append_audit_record(c, "LOGIN_FAILED", "security", NULL, "Failed login",
                         user_id = "<script>alert(1)</script>")
  })
  .with_db_transaction(db$con, function(c) {
    .append_audit_record(c, "INSERT", "data_entries", "DE-1", "entry", user_id = "alice")
  })
  rows <- DBI::dbGetQuery(db$con, "SELECT * FROM audit_log")
  f <- audit_log_display_frame(rows)
  expect_equal(nrow(f), 2)
  expect_identical(sort(f$entity_type), c("data", "user"))

  shiny::testServer(zzedc:::audit_log_viewer_server, args = list(db_pool = db$con), {
    session$setInputs(filter_user = "", filter_action = "", filter_entity_type = "",
                      search_text = "", filter_date_from = as.Date("2000-01-01"),
                      filter_date_to = Sys.Date() + 1)
    expect_equal(nrow(log_state$all_logs), 2, info = "reads audit_log")
  })
  tbl <- zzedc:::audit_log_table_data(f, "x-view_details")
  expect_false(any(grepl("<script>", unlist(tbl), fixed = TRUE)),
               info = "user-supplied text is escaped, not rendered as script")
  expect_true(any(grepl("&lt;script&gt;", tbl$User, fixed = TRUE)))

  shiny::testServer(zzedc:::audit_log_viewer_server, args = list(db_pool = NULL), {
    expect_equal(nrow(log_state$all_logs), 0, info = "no connection: no fabricated sample rows")
    expect_true(nzchar(log_state$load_error))
  })
})

# log_audit_action() now appends to the hash-chained audit_log.
local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  .ensure_audit_tables(db$con)
  log_audit_action(db$con, "alice", "export", "data", "DE-9")
  ev <- DBI::dbGetQuery(db$con, "SELECT event_type, record_id FROM audit_log")
  expect_identical(ev$event_type, "EXPORT")
  expect_equal(DBI::dbGetQuery(db$con, "SELECT COUNT(*) AS n FROM audit_chain")$n, 1,
               info = "linked into the hash chain")
})

# ---------------------------------------------------------------
# Automatic logoff works and is recorded
# ---------------------------------------------------------------

local({
  db <- new_db()
  DBI::dbDisconnect(db$con)
  on.exit(unlink(db$path), add = TRUE)
  with_cached_sqlite(db$path, with_profile("development", {
    init_audit_logging()
    user_input <- shiny::reactiveValues(authenticated = TRUE, username = "alice")
    shiny::testServer(function(input, output, session) {
      tracker <- enable_session_timeout(session, user_input,
                                        list(session_timeout_minutes = 1))
      session$userData$tracker <- tracker
    }, {
      session$flushReact()
      session$userData$tracker$last_activity(Sys.time() - 600)
      session$elapse(61000)
      expect_false(shiny::isolate(user_input$authenticated),
                   info = "an idle session is logged off")
    })
    con <- DBI::dbConnect(RSQLite::SQLite(), db$path)
    ev <- DBI::dbGetQuery(con, "SELECT user_id, operation FROM audit_log WHERE event_type = 'LOGOUT'")
    DBI::dbDisconnect(con)
    expect_equal(nrow(ev), 1, info = "the automatic logoff is recorded")
    expect_identical(ev$user_id, "alice")
  }))
})
