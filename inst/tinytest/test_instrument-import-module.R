library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Regression test: instrument_import_server()'s output$instruments_table
# rendering called a bare small(...) -- not a function anywhere in
# base R, shiny, or htmltools (the correct call is tags$small(...))
# -- added 2026-11-10 when a repo-wide sweep for the same bug already
# fixed this session in backup_restore_module.R,
# audit_log_viewer_module.R, admin_dashboard_module.R, and
# setup_wizard_module.R turned up one more instance here, plus two in
# cfr_compliance_module.R's signature-verification result renderer.
# This module is never mounted anywhere in inst/app/ (confirmed by
# grep), so it had no test coverage of any kind before this file --
# exactly how the bug went unnoticed.

if (!exists("instrument_import_server", where = asNamespace("zzedc"))) {
  exit_file("instrument_import_server not available")
}

local({
  instruments_dir <- system.file("extdata", "instruments", package = "zzedc")
  if (!dir.exists(instruments_dir) ||
        length(list.files(instruments_dir, pattern = "\\.csv$")) == 0) {
    exit_file("no shipped instrument CSVs available to test against")
  }

  result <- tryCatch({
    shiny::testServer(
      zzedc:::instrument_import_server,
      args = list(db_conn = NULL, instruments_dir = instruments_dir),
      {
        session$flushReact()
        # Force-evaluate the renderUI output, the same way a real
        # browser session requesting the output would -- testServer()
        # does not evaluate output$* on its own otherwise, which is
        # exactly why this bug was never caught by anything less than
        # actually rendering it.
        output$instruments_table
      }
    )
  }, error = function(e) e)

  expect_false(inherits(result, "error"),
               info = if (inherits(result, "error")) conditionMessage(result) else "")
})
