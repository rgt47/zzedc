library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")
if (!exists("init_audit_logging")) exit_file("audit functions not available")

# --- regressions -------------------------------------------------
#
# The audit trail's hash could not be recomputed from the row it
# described. Both writers hashed a Sys.time() that was never stored:
# the column took the database's CURRENT_TIMESTAMP default instead,
# a different clock and a different rendering. Verification therefore
# compared only the linkage fields, which proves they agree with each
# other and nothing about the content, so rewriting who performed an
# action, on what record, or when, went undetected while the function
# reported "Audit trail integrity verified" and stamped verified = 1
# into the chain.
#
# The two writers also hashed different field sets into the same table,
# so no single verifier could have checked both.

setup_audit_db <- function() {
  db <- tempfile(fileext = ".db")
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_12345678901234567890123")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  init_audit_logging(db_path = db)
  db
}

# A hash must be reproducible from the stored row.
db <- setup_audit_db()
log_audit_event("UPDATE", "subjects", "R1", "UPDATE", "changed dose",
                "alice", db_path = db)
conn <- connect_encrypted_db(db_path = db)
row <- DBI::dbGetQuery(conn, "SELECT * FROM audit_log ORDER BY audit_id DESC LIMIT 1")
DBI::dbDisconnect(conn)
expect_equal(
  digest::digest(zzedc:::.audit_hash_content(
    row$event_type, row$table_name, row$record_id, row$operation,
    row$details, row$user_id, row$ip_address, row$session_id,
    row$timestamp, row$previous_hash), algo = "sha256"),
  row$audit_hash,
  info = "the audit hash recomputes from the stored row")
unlink(db)

# A clean trail verifies; tampering with content does not.
tampers <- list(
  "the acting user is rewritten" =
    "UPDATE audit_log SET user_id = 'attacker' WHERE audit_id = 2",
  "the record acted on is changed" =
    "UPDATE audit_log SET record_id = 'R99' WHERE audit_id = 2",
  "the operation is downgraded" =
    "UPDATE audit_log SET operation = 'SELECT' WHERE audit_id = 2",
  "the timestamp is moved" =
    "UPDATE audit_log SET timestamp = '2020-01-01 00:00:00' WHERE audit_id = 3"
)
for (nm in names(tampers)) {
  db <- setup_audit_db()
  for (k in 1:4) {
    log_audit_event("UPDATE", "subjects", paste0("R", k), "UPDATE",
                    paste("edit", k), "alice", db_path = db)
  }
  expect_true(verify_audit_integrity(db_path = db)$valid,
    info = "an untampered trail verifies")
  conn <- connect_encrypted_db(db_path = db)
  DBI::dbExecute(conn, tampers[[nm]])
  DBI::dbDisconnect(conn)
  res <- verify_audit_integrity(db_path = db)
  expect_false(res$valid, info = paste("detected when", nm))
  expect_true(length(res$tampered_records) > 0,
    info = paste("the offending record is named when", nm))
  unlink(db)
}

# Both writers must produce rows the one verifier accepts. The extended
# writer hashed ip_address, session_id and event_category, the last of
# which is not even a column of audit_log.
db <- setup_audit_db()
log_audit_event("UPDATE", "subjects", "R1", "UPDATE", "base writer",
                "alice", db_path = db)
log_system_event("STARTUP", "Application started", severity = "info",
                 db_path = db)
log_failed_login("attacker", reason = "Invalid username",
                 ip_address = "10.0.0.1", db_path = db)
res <- verify_audit_integrity(db_path = db)
expect_true(res$valid,
  info = "rows from both audit writers verify under one rule")
expect_true(res$records_checked >= 3,
  info = "all three rows were checked, not skipped")

# Verifying a sub-range must not fail merely because its first record
# is not the head of the chain.
sub <- verify_audit_integrity(start_id = 2, db_path = db)
# [["error"]] rather than $error: `$` partial-matches, and this list
# also carries errors_found, so $error silently returns that count
# instead of the absent error element.
expect_true(is.null(sub[["error"]]),
  info = "a range query builds valid SQL")
expect_true(sub$valid,
  info = "a sub-range verifies without a spurious GENESIS failure")
expect_true(sub$records_checked < res$records_checked,
  info = "the range actually narrowed the set")
unlink(db)
