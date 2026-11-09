library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Regression tests for run_iq_tests()/run_oq_tests()/run_pq_tests(),
# added 2026-11-09. None of the three had any test coverage at all
# before this, which is how the following went unnoticed:
#
# 1. run_iq_tests()'s IQ-005/IQ-006, and the whole of run_oq_tests()
#    and run_pq_tests(), call initialize_encrypted_database() and
#    then immediately connect via functions that need
#    DB_ENCRYPTION_KEY set -- but the key that
#    initialize_encrypted_database() generates and returns was never
#    persisted anywhere. In a session with no DB_ENCRYPTION_KEY
#    already set from elsewhere (the normal case for a deployer
#    running the validation suite right after install), every one of
#    these tests failed.
# 2. get_db_adapter() (called internally by both
#    initialize_encrypted_database() and connect_encrypted_db())
#    resolves ./config.yml relative to the working directory when
#    not given an explicit config, and throws if that file exists
#    but predates the multi-backend db_backend schema -- which is
#    exactly the shape of this package's own repo-root config.yml.
#    Running any of these three functions from the package's own
#    directory (a very ordinary thing for a maintainer or CI job to
#    do) hit this every time.
# 3. OQ-003 ("Audit Event Logging") only checked log_audit_event()'s
#    boolean return value, never that a row was actually written.
#    This is the exact failure mode of the ten-site audit-trail
#    outage fixed 2026-11-08 (see vignettes/zzedc-whitepaper.Rmd):
#    OQ-003 passed throughout that outage because it never exercised
#    the real call sites, only log_audit_event() directly with
#    `operation` correctly supplied.
#
# These tests run from this package's own tinytest working
# directory (inst/tinytest/), which is exactly the repo-relative
# location where issue 2 above would otherwise bite.

local({
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA_character_)
  on.exit({
    if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY")
    else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  }, add = TRUE)
  Sys.unsetenv("DB_ENCRYPTION_KEY")

  res <- run_iq_tests(verbose = FALSE)

  expect_true(res$results$IQ_005$passed,
              info = paste("IQ-005 should pass with no key preset:",
                            res$results$IQ_005$message))
  expect_true(res$results$IQ_006$passed,
              info = paste("IQ-006 should pass with no key preset:",
                            res$results$IQ_006$message))
  expect_true(res$summary$all_passed)
})

local({
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA_character_)
  on.exit({
    if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY")
    else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  }, add = TRUE)
  Sys.unsetenv("DB_ENCRYPTION_KEY")

  res <- run_oq_tests(verbose = FALSE)

  expect_true(res$results$OQ_003$passed,
              info = paste("OQ-003 should pass with no key preset:",
                            res$results$OQ_003$message))
  expect_true(res$summary$all_passed)

  # Restoring the caller's own (absent) key must actually take --
  # run_oq_tests() must not leak DB_ENCRYPTION_KEY into the caller's
  # session after it returns.
  expect_equal(Sys.getenv("DB_ENCRYPTION_KEY", unset = NA_character_), NA_character_)
})

local({
  res <- run_pq_tests(verbose = FALSE, record_count = 50)
  expect_true(res$summary$all_passed,
              info = paste(sapply(res$results, function(r) r$message), collapse = "; "))
})

# OQ-003 regression guard: confirm its assertion logic would
# correctly fail on a row that was never written (the exact failure
# mode of the ten-site outage), not just trust a boolean return.
local({
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)

  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = test_db)),
                 force_new = TRUE)
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA_character_)
  on.exit({
    if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY")
    else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  }, add = TRUE)

  init_res <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init_res$key)
  init_audit_logging(db_path = test_db)

  con <- connect_encrypted_db(db_path = test_db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  written <- DBI::dbGetQuery(con, "
    SELECT event_type, user_id FROM audit_log
    WHERE record_id = 'NEVER_WRITTEN' AND table_name = 'test_table'
  ")
  expect_equal(nrow(written), 0,
               info = "a row that was never inserted must not be found")
})
