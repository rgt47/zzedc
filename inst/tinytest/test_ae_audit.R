library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Adverse event writes and their audit records commit in one
# transaction. Before 2026-11-23 only create_adverse_event() wrote an
# audit record, in a separate connection whose failure was ignored;
# the other five writers wrote none.

if (!(exists("init_adverse_events"))) exit_file("AE functions not available")

.ae_test_db <- function(with_audit = TRUE) {
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  if (!is.null(init$error)) stop(init$error)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  if (with_audit) stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
  stopifnot(isTRUE(init_adverse_events(db_path = db)$success))
  db
}

.ae_query <- function(db, sql, params = NULL) {
  con <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(con))
  if (is.null(params)) DBI::dbGetQuery(con, sql)
  else DBI::dbGetQuery(con, sql, params = params)
}

.ae_audit_rows <- function(db) {
  .ae_query(db, "SELECT event_type, table_name, record_id, user_id
                 FROM audit_log ORDER BY audit_id")
}

.new_ae <- function(db) {
  create_adverse_event(
    study_id = "S1", subject_id = "P1", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "Mild headache",
    severity = "MILD", causality = "UNLIKELY", outcome = "NOT_RECOVERED",
    reported_by = "u1", db_path = db
  )
}

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

# Every writer adds audit records for each row it writes
local({
  db <- .ae_test_db()
  on.exit(unlink(db))

  ae <- .new_ae(db)
  expect_true(ae$success, info = "create succeeds")
  a <- .ae_audit_rows(db)
  expect_equal(nrow(a), 1L, info = "create: one audit record")
  expect_equal(a$table_name, "adverse_events", info = "create: table")
  expect_equal(a$event_type, "INSERT", info = "create: event type")
  expect_equal(a$record_id, as.character(ae$ae_id), info = "create: id")

  n0 <- nrow(.ae_audit_rows(db))
  r <- add_ae_followup(ae_id = ae$ae_id, followup_type = "ADDITIONAL_INFO",
                       notes = "n", recorded_by = "u2", db_path = db)
  a <- .ae_audit_rows(db)
  expect_true(r$success, info = "follow-up succeeds")
  expect_equal(nrow(a) - n0, 1L, info = "follow-up: one audit record")
  expect_equal(tail(a$table_name, 1), "ae_followups",
               info = "follow-up: table")
  expect_equal(tail(a$user_id, 1), "u2", info = "follow-up: user")

  n0 <- nrow(a)
  r <- update_ae_causality(ae_id = ae$ae_id, causality = "POSSIBLE",
                           rationale = "r", updated_by = "u1",
                           db_path = db)
  a <- .ae_audit_rows(db)
  expect_true(r$success, info = "causality succeeds")
  expect_equal(sort(tail(a$table_name, nrow(a) - n0)),
               c("adverse_events", "ae_followups"),
               info = "causality: AE update and follow-up audited")

  n0 <- nrow(a)
  sae <- upgrade_to_sae(ae_id = ae$ae_id, sae_criteria = "HOSPITALIZATION",
                        awareness_date = Sys.Date(), narrative = "n",
                        upgraded_by = "u1", hospitalization = TRUE,
                        db_path = db)
  a <- .ae_audit_rows(db)
  expect_true(sae$success, info = "upgrade succeeds")
  expect_equal(sort(tail(a$table_name, nrow(a) - n0)),
               c("adverse_events", "ae_followups", "sae_details"),
               info = "upgrade: AE, SAE, and follow-up audited")

  n0 <- nrow(a)
  r <- record_sae_notification(sae_id = sae$sae_id,
                               notification_type = "IRB",
                               notification_date = Sys.Date(),
                               recorded_by = "u1", db_path = db)
  a <- .ae_audit_rows(db)
  expect_true(r$success, info = "notification succeeds")
  expect_equal(sort(tail(a$table_name, nrow(a) - n0)),
               c("ae_followups", "sae_details"),
               info = "notification: SAE update and follow-up audited")

  n0 <- nrow(a)
  r <- resolve_adverse_event(ae_id = ae$ae_id, resolution_date = Sys.Date(),
                             outcome = "RECOVERED", resolved_by = "u1",
                             db_path = db)
  a <- .ae_audit_rows(db)
  expect_true(r$success, info = "resolve succeeds")
  expect_equal(sort(tail(a$table_name, nrow(a) - n0)),
               c("adverse_events", "ae_followups"),
               info = "resolve: AE update and follow-up audited")

  v <- verify_audit_integrity(db_path = db)
  expect_true(isTRUE(v$valid),
              info = "audit chain verifies after all AE writes")
})

# An audit failure leaves no unaudited AE row
local({
  db <- .ae_test_db(with_audit = FALSE)
  on.exit(unlink(db))
  r <- suppressWarnings(.new_ae(db))
  expect_false(r$success, info = "create fails when audit cannot be written")
  n <- .ae_query(db, "SELECT COUNT(*) AS n FROM adverse_events")$n
  expect_equal(n, 0L, info = "no AE row stored without its audit record")
})

# A failed upgrade rolls back every part of it
local({
  db <- .ae_test_db(with_audit = FALSE)
  on.exit(unlink(db))
  con <- connect_encrypted_db(db_path = db)
  DBI::dbExecute(con, "
    INSERT INTO adverse_events (ae_number, study_id, subject_id, onset_date,
      ae_term, ae_description, severity, is_serious, causality, outcome,
      reported_by, ae_hash, previous_hash)
    VALUES ('AE-1', 'S1', 'P1', '2026-01-01', 't', 'd', 'MILD', 0,
      'UNLIKELY', 'NOT_RECOVERED', 'u1', 'h', 'GENESIS')")
  ae_id <- DBI::dbGetQuery(con, "SELECT ae_id FROM adverse_events")$ae_id[1]
  DBI::dbDisconnect(con)

  r <- upgrade_to_sae(ae_id = ae_id, sae_criteria = "HOSPITALIZATION",
                      awareness_date = Sys.Date(), narrative = "n",
                      upgraded_by = "u1", db_path = db)
  expect_false(r$success, info = "upgrade fails when audit cannot be written")
  ae <- .ae_query(db, "SELECT is_serious FROM adverse_events")
  expect_equal(as.integer(ae$is_serious), 0L,
               info = "AE not left marked serious")
  n_sae <- .ae_query(db, "SELECT COUNT(*) AS n FROM sae_details")$n
  n_fu <- .ae_query(db, "SELECT COUNT(*) AS n FROM ae_followups")$n
  expect_equal(n_sae, 0L, info = "no orphan SAE details")
  expect_equal(n_fu, 0L, info = "no orphan follow-up")
})

# Notifying an SAE that does not exist is an error, not a success
local({
  db <- .ae_test_db()
  on.exit(unlink(db))
  r <- record_sae_notification(sae_id = 999L, notification_type = "IRB",
                               notification_date = Sys.Date(),
                               recorded_by = "u1", db_path = db)
  expect_false(r$success, info = "unknown SAE is reported as failure")
})

if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
