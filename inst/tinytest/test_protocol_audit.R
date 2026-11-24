library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Protocol compliance writes and their audit records commit in one
# transaction. Before 2026-11-23 only create_protocol_deviation()
# wrote an audit record, on a separate connection whose failure was
# ignored; the other writers wrote none.

if (!(exists("init_protocol_compliance"))) {
  exit_file("Protocol compliance functions not available")
}

.pc_test_db <- function(with_audit = TRUE) {
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  if (!is.null(init$error)) stop(init$error)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  if (with_audit) stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
  stopifnot(isTRUE(init_protocol_compliance(db_path = db)$success))
  db
}

.pc_query <- function(db, sql) {
  con <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, sql)
}

.pc_audit <- function(db) {
  .pc_query(db, "SELECT event_type, table_name, record_id, user_id
                 FROM audit_log ORDER BY audit_id")
}

.pc_new_tables <- function(db, n0) {
  a <- .pc_audit(db)
  sort(utils::tail(a$table_name, nrow(a) - n0))
}

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

# Every writer adds audit records for each row it writes
local({
  db <- .pc_test_db()
  on.exit(unlink(db))

  p <- create_protocol(protocol_code = "P1", protocol_title = "t",
                       protocol_version = "1", effective_date = Sys.Date(),
                       created_by = "u1", db_path = db)
  expect_true(p$success, info = "protocol created")
  expect_equal(.pc_new_tables(db, 0L), "protocol_definitions",
               info = "create_protocol audited")

  n0 <- nrow(.pc_audit(db))
  v <- add_protocol_visit(protocol_id = p$protocol_id, visit_code = "W4",
                          visit_name = "Week 4", visit_order = 1,
                          target_day = 28, window_before = 3,
                          window_after = 3, db_path = db,
                          created_by = "u1")
  expect_true(v$success, info = "visit added")
  expect_equal(.pc_new_tables(db, n0), "protocol_visits",
               info = "add_protocol_visit audited")
  expect_equal(utils::tail(.pc_audit(db)$user_id, 1), "u1",
               info = "add_protocol_visit records the user")

  n0 <- nrow(.pc_audit(db))
  s <- schedule_subject_visit(subject_id = "S1",
                              protocol_id = p$protocol_id,
                              visit_id = v$visit_id,
                              scheduled_date = Sys.Date(), db_path = db,
                              scheduled_by = "u1")
  expect_true(s$success, info = "visit scheduled")
  expect_equal(.pc_new_tables(db, n0), "subject_visits",
               info = "schedule_subject_visit audited")

  n0 <- nrow(.pc_audit(db))
  cv <- complete_subject_visit(
    subject_id = "S1", protocol_id = p$protocol_id, visit_id = v$visit_id,
    actual_date = as.Date("2026-02-10"),
    baseline_date = as.Date("2026-01-01"),
    completed_by = "u1", db_path = db)
  expect_true(cv$success, info = "late visit completed")
  expect_true(isTRUE(cv$deviation_created) && !is.null(cv$deviation_id),
              info = "late visit has a deviation id")
  expect_equal(.pc_new_tables(db, n0),
               c("protocol_deviations", "subject_visits", "subject_visits"),
               info = "visit, deviation, and link all audited")

  n0 <- nrow(.pc_audit(db))
  d <- create_protocol_deviation(
    protocol_id = p$protocol_id, subject_id = "S1",
    deviation_type = "DOSING", severity = "MINOR",
    deviation_date = Sys.Date(), description = "d",
    reported_by = "u1", db_path = db)
  expect_true(d$success, info = "deviation created")
  expect_equal(.pc_new_tables(db, n0), "protocol_deviations",
               info = "create_protocol_deviation audited")

  n0 <- nrow(.pc_audit(db))
  r <- review_protocol_deviation(deviation_id = d$deviation_id,
                                 reviewed_by = "u2",
                                 review_status = "REVIEWED", db_path = db)
  expect_true(r$success, info = "deviation reviewed")
  expect_equal(.pc_new_tables(db, n0), "protocol_deviations",
               info = "review_protocol_deviation audited")
  expect_equal(utils::tail(.pc_audit(db)$user_id, 1), "u2",
               info = "review records the reviewer")

  n0 <- nrow(.pc_audit(db))
  ec <- add_eligibility_criterion(
    protocol_id = p$protocol_id, criterion_type = "INCLUSION",
    criterion_code = "AGE", criterion_text = "Age >= 18",
    field_name = "age", operator = "GE", value = "18", db_path = db,
    created_by = "u1")
  expect_true(ec$success, info = "criterion added")
  expect_equal(.pc_new_tables(db, n0), "eligibility_criteria",
               info = "add_eligibility_criterion audited")

  n0 <- nrow(.pc_audit(db))
  e <- check_subject_eligibility(subject_id = "S1",
                                 protocol_id = p$protocol_id,
                                 subject_data = list(age = 30),
                                 checked_by = "u1", db_path = db)
  expect_true(e$success, info = "eligibility checked")
  expect_equal(.pc_new_tables(db, n0), "eligibility_checks",
               info = "check_subject_eligibility audited")

  v <- verify_audit_integrity(db_path = db)
  expect_true(isTRUE(v$valid),
              info = "audit chain verifies after all protocol writes")
})

# Reviewing a deviation that does not exist is an error
local({
  db <- .pc_test_db()
  on.exit(unlink(db))
  r <- review_protocol_deviation(deviation_id = 999L, reviewed_by = "u2",
                                 review_status = "REVIEWED", db_path = db)
  expect_false(r$success, info = "unknown deviation is reported as failure")
})

# An audit failure leaves no unaudited visit or deviation
local({
  db <- .pc_test_db(with_audit = FALSE)
  on.exit(unlink(db))
  con <- connect_encrypted_db(db_path = db)
  DBI::dbExecute(con, "
    INSERT INTO protocol_definitions (protocol_code, protocol_title,
      protocol_version, effective_date, created_by)
    VALUES ('P1', 't', '1', '2026-01-01', 'u1')")
  pid <- DBI::dbGetQuery(con, "SELECT protocol_id FROM protocol_definitions")
  DBI::dbExecute(con, "
    INSERT INTO protocol_visits (protocol_id, visit_code, visit_name,
      visit_order, target_day, window_before, window_after)
    VALUES (?, 'W4', 'Week 4', 1, 28, 3, 3)",
    params = list(pid$protocol_id[1]))
  vid <- DBI::dbGetQuery(con, "SELECT visit_id FROM protocol_visits")
  DBI::dbDisconnect(con)

  cv <- complete_subject_visit(
    subject_id = "S1", protocol_id = pid$protocol_id[1],
    visit_id = vid$visit_id[1], actual_date = as.Date("2026-02-10"),
    baseline_date = as.Date("2026-01-01"), completed_by = "u1",
    db_path = db)
  expect_false(cv$success, info = "visit fails when audit cannot be written")
  n_sv <- .pc_query(db, "SELECT COUNT(*) AS n FROM subject_visits")$n
  n_dev <- .pc_query(db, "SELECT COUNT(*) AS n FROM protocol_deviations")$n
  expect_equal(n_sv, 0L, info = "no unaudited visit row")
  expect_equal(n_dev, 0L, info = "no unaudited deviation row")

  d <- suppressWarnings(create_protocol_deviation(
    protocol_id = pid$protocol_id[1], subject_id = "S1",
    deviation_type = "DOSING", severity = "MINOR",
    deviation_date = Sys.Date(), description = "d",
    reported_by = "u1", db_path = db))
  expect_false(d$success, info = "deviation fails without audit")
  n_dev <- .pc_query(db, "SELECT COUNT(*) AS n FROM protocol_deviations")$n
  expect_equal(n_dev, 0L, info = "no deviation stored without audit")
})

if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
