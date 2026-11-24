library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Regression test (2026-11-23): on DuckDB, upgrade_to_sae() and
# resolve_adverse_event() failed for any adverse event with a
# follow-up, and review_protocol_deviation() failed for any deviation
# linked to a visit, with "Violates foreign key constraint because key
# ... is still referenced by a foreign key in a different table".
# adverse_events(is_serious), adverse_events(status), and
# protocol_deviations(review_status) were indexed, and DuckDB rewrites
# an UPDATE of an indexed column on a referenced row as DELETE plus
# INSERT (see test_correction_duckdb.R for the same limitation).

if (!requireNamespace("duckdb", quietly = TRUE)) {
  exit_file("duckdb package not installed")
}
if (!exists("init_adverse_events")) exit_file("AE functions not available")

# This file points the cached adapter at DuckDB; restore the previous
# one at the end so later test files keep their backend.
.zz_cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
.had_adapter <- exists("adapter", envir = .zz_cache)
.saved_adapter <- if (.had_adapter) .zz_cache$adapter else NULL

setup_duckdb <- function(pre_existing_indexes = FALSE) {
  db <- tempfile(fileext = ".duckdb")
  config <- test_backend_config("duckdb")
  config$duckdb$path <- db
  get_db_adapter(config = config, force_new = TRUE)
  init_audit_logging(db_path = db)
  if (pre_existing_indexes) {
    # A study initialized before the fix: create the old indexes
    # first, so initialization must drop them.
    stopifnot(isTRUE(init_adverse_events(db_path = db)$success))
    stopifnot(isTRUE(init_protocol_compliance(db_path = db)$success))
    conn <- connect_encrypted_db(db_path = db)
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_ae_serious
                          ON adverse_events(is_serious)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_ae_status
                          ON adverse_events(status)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_deviations_status
                          ON protocol_deviations(review_status)")
    DBI::dbDisconnect(conn)
  }
  stopifnot(isTRUE(init_adverse_events(db_path = db)$success))
  stopifnot(isTRUE(init_protocol_compliance(db_path = db)$success))
  db
}

cleanup_duckdb <- function(db) {
  tryCatch(get_db_adapter()$shutdown(), error = function(e) NULL)
  unlink(db)
}

exercise <- function(db, label) {
  ae <- create_adverse_event(
    study_id = "S1", subject_id = "P1", onset_date = Sys.Date(),
    ae_term = "Headache", ae_description = "d", severity = "MILD",
    causality = "UNLIKELY", outcome = "NOT_RECOVERED", reported_by = "u1",
    db_path = db)
  expect_true(ae$success, info = paste(label, "create AE"))
  fu <- add_ae_followup(ae_id = ae$ae_id, followup_type = "ADDITIONAL_INFO",
                        notes = "n", recorded_by = "u1", db_path = db)
  expect_true(fu$success, info = paste(label, "follow-up"))

  sae <- upgrade_to_sae(ae_id = ae$ae_id, sae_criteria = "HOSPITALIZATION",
                        awareness_date = Sys.Date(), narrative = "n",
                        upgraded_by = "u1", db_path = db)
  expect_true(sae$success,
              info = paste(label, "upgrade_to_sae with a follow-up:",
                           sae$error %||% ""))

  res <- resolve_adverse_event(ae_id = ae$ae_id, resolution_date = Sys.Date(),
                               outcome = "RECOVERED", resolved_by = "u1",
                               db_path = db)
  expect_true(res$success,
              info = paste(label, "resolve_adverse_event with follow-ups:",
                           res$error %||% ""))

  p <- create_protocol(protocol_code = "P1", protocol_title = "t",
                       protocol_version = "1", effective_date = Sys.Date(),
                       created_by = "u1", db_path = db)
  v <- add_protocol_visit(protocol_id = p$protocol_id, visit_code = "W4",
                          visit_name = "Week 4", visit_order = 1,
                          target_day = 28, window_before = 3,
                          window_after = 3, db_path = db)
  cv <- complete_subject_visit(
    subject_id = "S1", protocol_id = p$protocol_id, visit_id = v$visit_id,
    actual_date = as.Date("2026-02-10"),
    baseline_date = as.Date("2026-01-01"), completed_by = "u1",
    db_path = db)
  expect_true(isTRUE(cv$success) && !is.null(cv$deviation_id),
              info = paste(label, "late visit creates a linked deviation"))

  rv <- review_protocol_deviation(deviation_id = cv$deviation_id,
                                  reviewed_by = "u2",
                                  review_status = "REVIEWED", db_path = db)
  expect_true(rv$success,
              info = paste(label, "review of a visit-linked deviation:",
                           rv$error %||% ""))
}

local({
  db <- setup_duckdb()
  on.exit(cleanup_duckdb(db), add = TRUE)
  exercise(db, "new database:")
})

local({
  db <- setup_duckdb(pre_existing_indexes = TRUE)
  on.exit(cleanup_duckdb(db), add = TRUE)
  idx <- DBI::dbGetQuery(
    (conn <- connect_encrypted_db(db_path = db)),
    "SELECT index_name FROM duckdb_indexes()")$index_name
  DBI::dbDisconnect(conn)
  expect_false(any(c("idx_ae_serious", "idx_ae_status",
                     "idx_deviations_status") %in% idx),
               info = "re-initialization drops the old indexes")
  exercise(db, "pre-existing indexes:")
})

if (.had_adapter) {
  assign("adapter", .saved_adapter, envir = .zz_cache)
} else if (exists("adapter", envir = .zz_cache)) {
  rm("adapter", envir = .zz_cache)
}
