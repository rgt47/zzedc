library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Audit records of reads (2026-11-12): who saw or took which subjects'
# records, from the Data Explorer, the Export Center, the EDC entries
# list, the data-quality report and the subject case report.

if (!exists("log_record_read")) exit_file("log_record_read not available")
ns <- asNamespace("zzedc")
for (fn in c(".ensure_audit_tables", "ensure_data_entries_table", "db_insert_data_entry",
             "data_server")) {
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
  .ensure_audit_tables(con)
  list(path = path, con = con)
}

reads <- function(con) {
  DBI::dbGetQuery(con, "SELECT * FROM audit_log
                        WHERE event_type IN ('SELECT', 'EXPORT', 'REPORT_GENERATED')
                        ORDER BY audit_id")
}

# ---------------------------------------------------------------
# One record per read: who, which subjects, how many; no values
# ---------------------------------------------------------------

local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  shown <- data.frame(subject_id = c("S-002", "S-001", "S-002", NA),
                      sbp = c(181, 120, 175, 130))
  id <- log_record_read(db$con, "data_explorer", data = shown,
                        filters = list(form = "vitals"), user_id = "monitor1",
                        ip_address = "198.51.100.7", session_id = "tok1")
  expect_true(!is.null(id))
  ev <- reads(db$con)
  expect_equal(nrow(ev), 1)
  expect_identical(ev$event_type, "SELECT")
  expect_identical(ev$user_id, "monitor1")
  expect_identical(ev$ip_address, "198.51.100.7")
  expect_identical(ev$session_id, "tok1")
  expect_true(is.na(ev$record_id), info = "several subjects: no single record id")
  d <- jsonlite::fromJSON(ev$details)
  expect_identical(d$view, "data_explorer")
  expect_equal(d$n_records, 4)
  expect_identical(d$subject_ids, c("S-001", "S-002"), info = "distinct, sorted, NA dropped")
  expect_identical(d$filters$form, "vitals")
  expect_false(grepl("181", ev$details), info = "field values are not copied into the trail")
  expect_equal(DBI::dbGetQuery(db$con, "SELECT COUNT(*) AS n FROM audit_chain")$n, 1,
               info = "written to the hash chain")

  log_record_read(db$con, "subject_case_report", subject_ids = "S-001",
                  event_type = "REPORT_GENERATED", user_id = "pi1")
  ev <- reads(db$con)
  expect_identical(ev$record_id[2], "S-001", info = "one subject: its id is the record id")
  d <- jsonlite::fromJSON(ev$details[2])
  expect_identical(d$subject_ids, "S-001", info = "a single id is still a JSON array")
})

local({
  expect_null(log_record_read(NULL, "data_explorer"), info = "no connection, nothing read")
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  expect_error(log_record_read(db$con, "x", event_type = "UPDATE"), "event_type")
  expect_null(log_record_read(db$con, "data_quality_flagged",
                              data = data.frame(subject_id = character())))
  expect_equal(nrow(reads(db$con)), 0, info = "an empty result discloses nothing")
})

# ---------------------------------------------------------------
# A read that cannot be recorded: error under 'regulated'
# ---------------------------------------------------------------

local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  DBI::dbExecute(db$con, "ALTER TABLE audit_chain RENAME TO audit_chain_moved")
  with_profile("standard", {
    expect_warning(res <- log_record_read(db$con, "export_preview", subject_ids = "S-1"),
                   "could not be written")
    expect_null(res)
  })
  with_profile("regulated", {
    expect_error(log_record_read(db$con, "export_preview", subject_ids = "S-1"),
                 "are not shown")
  })
})

# ---------------------------------------------------------------
# Accounting of access: by subject (exact match) and by user
# ---------------------------------------------------------------

local({
  db <- new_db()
  on.exit({ DBI::dbDisconnect(db$con); unlink(db$path) }, add = TRUE)
  log_record_read(db$con, "data_explorer", subject_ids = c("S1", "S2"), user_id = "u1")
  log_record_read(db$con, "export_download", subject_ids = "S10",
                  event_type = "EXPORT", user_id = "u2")
  DBI::dbWithTransaction(db$con, get(".append_audit_record", envir = ns)(
    db$con, "SELECT", "data_entries", operation = "other SELECT",
    details = "{\"note\":\"S1\"}", user_id = "u3"))

  a <- get_record_access_log(db$con, subject_id = "S1")
  expect_equal(nrow(a), 1, info = "S1 matches S1 only: not S10, not unrelated records")
  expect_identical(a$user_id, "u1")
  expect_identical(a$view, "data_explorer")
  expect_equal(a$n_subjects, 2)

  expect_equal(nrow(get_record_access_log(db$con, subject_id = "S10")), 1)
  expect_identical(get_record_access_log(db$con, user_id = "u2")$event_type, "EXPORT")
  expect_equal(nrow(get_record_access_log(db$con)), 2)
  expect_equal(nrow(get_record_access_log(db$con, subject_id = "S99")), 0)
})

# ---------------------------------------------------------------
# Data Explorer: a load and a download are each recorded, under the user
# ---------------------------------------------------------------

local({
  db <- new_db()
  on.exit({
    DBI::dbDisconnect(db$con); unlink(db$path)
    if (exists("db_pool", envir = .GlobalEnv)) rm("db_pool", envir = .GlobalEnv)
  }, add = TRUE)
  ensure_data_entries_table(db$con)
  db_insert_data_entry(db$con, subject_id = "S-001", form_name = "visit1",
                       data = list(sbp = 120), created_by = "coord1")
  db_insert_data_entry(db$con, subject_id = "S-002", form_name = "visit1",
                       data = list(sbp = 135), created_by = "coord1")
  assign("db_pool", db$con, envir = .GlobalEnv)

  shiny::testServer(data_server, args = list(user_id = function() "monitor1"), {
    session$setInputs(data_source = "zzedc", max_rows = 50)
    invisible(output$data_summary)
    invisible(output$data_table)
    ev <- reads(db$con)
    expect_equal(nrow(ev), 1, info = "one record per load, not per output")
    expect_identical(ev$user_id, "monitor1")
    expect_identical(jsonlite::fromJSON(ev$details)$subject_ids, c("S-001", "S-002"))

    path <- output$export_current_data
    expect_true(file.exists(path))
    ev <- reads(db$con)
    expect_identical(ev$event_type, c("SELECT", "EXPORT"))
    expect_identical(jsonlite::fromJSON(ev$details[2])$view, "data_explorer_csv")

    session$setInputs(refresh_data = 1)
    invisible(output$data_summary)
    expect_equal(sum(reads(db$con)$event_type == "SELECT"), 2,
                 info = "Refresh re-reads the records, and that read is recorded")
  })
})

# ---------------------------------------------------------------
# Subject case report: recorded; not produced under 'regulated' if not
# ---------------------------------------------------------------

local({
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  on.exit({
    unlink(db)
    if (nzchar(old_key)) Sys.setenv(DB_ENCRYPTION_KEY = old_key) else Sys.unsetenv("DB_ENCRYPTION_KEY")
  }, add = TRUE)
  init_audit_logging(db_path = db)
  init_electronic_signatures(db_path = db)
  conn <- connect_encrypted_db(db_path = db)
  ensure_data_entries_table(conn)
  DBI::dbExecute(conn, "CREATE TABLE crf_definitions (crf_id INTEGER PRIMARY KEY,
                        crf_code TEXT, crf_name TEXT)")
  db_insert_data_entry(conn, subject_id = "S-001", form_name = "visit1",
                       data = list(sbp = 120), created_by = "coord1")
  DBI::dbDisconnect(conn)

  out <- tempfile(fileext = ".txt")
  res <- generate_subject_case_report("S-001", out, prepared_by = "pi1", db_path = db)
  expect_true(res$success, info = res$error %||% "")
  conn <- connect_encrypted_db(db_path = db)
  ev <- reads(conn)
  DBI::dbDisconnect(conn)
  expect_identical(ev$event_type, "REPORT_GENERATED")
  expect_identical(ev$record_id, "S-001")
  expect_identical(ev$user_id, "pi1")

  conn <- connect_encrypted_db(db_path = db)
  DBI::dbExecute(conn, "ALTER TABLE audit_chain RENAME TO audit_chain_moved")
  DBI::dbDisconnect(conn)
  out2 <- tempfile(fileext = ".txt")
  with_profile("regulated", {
    res <- generate_subject_case_report("S-001", out2, prepared_by = "pi1", db_path = db)
  })
  expect_false(res$success)
  expect_false(file.exists(out2), info = "no report when its disclosure cannot be recorded")
})
