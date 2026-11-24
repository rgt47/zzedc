library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Regression test (2026-11-23): check_subject_eligibility() reported a
# subject eligible when the data for an inclusion criterion was absent
# (the criterion was skipped), and failed with an error when the value
# was NA. Missing data must never make a subject eligible.

if (!exists("check_subject_eligibility")) {
  exit_file("Protocol compliance functions not available")
}

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

.elig_db <- function() {
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  if (!is.null(init$error)) stop(init$error)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
  stopifnot(isTRUE(init_protocol_compliance(db_path = db)$success))
  p <- create_protocol(protocol_code = "P1", protocol_title = "t",
                       protocol_version = "1", effective_date = Sys.Date(),
                       created_by = "u1", db_path = db)
  add_eligibility_criterion(p$protocol_id, "INCLUSION", "AGE",
                            "Age >= 18", "age", "GE", "18", db_path = db)
  add_eligibility_criterion(p$protocol_id, "EXCLUSION", "PREG",
                            "Pregnant", "pregnant", "EQ", "YES",
                            db_path = db)
  list(db = db, protocol_id = p$protocol_id)
}

.check <- function(s, data) {
  check_subject_eligibility(subject_id = "S1", protocol_id = s$protocol_id,
                            subject_data = data, checked_by = "u1",
                            db_path = s$db)
}

local({
  s <- .elig_db()
  on.exit(unlink(s$db))

  r <- .check(s, list(age = 30, pregnant = "NO"))
  expect_true(r$success && r$eligible, info = "complete data: eligible")
  expect_false(r$indeterminate, info = "complete data: determinate")

  r <- .check(s, list(pregnant = "NO"))
  expect_true(r$success, info = "absent inclusion field: no error")
  expect_false(r$eligible, info = "absent inclusion field: not eligible")
  expect_true(r$indeterminate, info = "absent inclusion field: indeterminate")
  expect_equal(r$indeterminate_criteria, "AGE",
               info = "absent inclusion field: criterion named")

  r <- .check(s, list(age = NA, pregnant = "NO"))
  expect_true(r$success, info = "NA inclusion value: no error")
  expect_false(r$eligible, info = "NA inclusion value: not eligible")
  expect_true(r$indeterminate, info = "NA inclusion value: indeterminate")

  r <- .check(s, list(age = "", pregnant = "NO"))
  expect_false(r$eligible, info = "empty inclusion value: not eligible")
  expect_true(r$indeterminate, info = "empty inclusion value: indeterminate")

  r <- .check(s, list(age = 30))
  expect_false(r$eligible, info = "absent exclusion field: not eligible")
  expect_equal(r$indeterminate_criteria, "PREG",
               info = "absent exclusion field: criterion named")

  r <- .check(s, list())
  expect_false(r$eligible, info = "no data: not eligible")
  expect_equal(sort(r$indeterminate_criteria), c("AGE", "PREG"),
               info = "no data: both criteria indeterminate")

  r <- .check(s, list(age = 16))
  expect_false(r$eligible, info = "failed inclusion: not eligible")
  expect_equal(r$message, "Subject is not eligible",
               info = "a failed criterion is reported as not eligible")

  stored <- DBI::dbGetQuery(
    (con <- connect_encrypted_db(db_path = s$db)),
    "SELECT overall_eligible FROM eligibility_checks ORDER BY check_id")
  DBI::dbDisconnect(con)
  expect_equal(as.integer(stored$overall_eligible),
               c(1L, 0L, 0L, 0L, 0L, 0L, 0L),
               info = "only the complete, passing check is stored eligible")
})

# A criterion without a field is manual: reported, not evaluated
local({
  s <- .elig_db()
  on.exit(unlink(s$db))
  add_eligibility_criterion(s$protocol_id, "INCLUSION", "CONSENT",
                            "Written informed consent", db_path = s$db)
  r <- .check(s, list(age = 30, pregnant = "NO"))
  expect_true(r$eligible, info = "manual criterion does not block")
  expect_equal(r$manual_criteria, "CONSENT",
               info = "manual criterion is listed")
  expect_equal(r$criteria_results$CONSENT$status, "MANUAL",
               info = "manual criterion status")
})

if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
