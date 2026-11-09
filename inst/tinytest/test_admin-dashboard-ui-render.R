library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Regression tests: admin_dashboard_ui() and its nested sub-module
# UIs (backup_restore_ui(), audit_log_viewer_ui(), via
# admin_dashboard_module.R's own system_config_ui()/
# help_documentation_ui()) must render without error. Added
# 2026-11-09, when mounting admin_dashboard_server()/_ui() into the
# live app for the first time ever (confirmed by repo-wide grep: it
# was never called anywhere in inst/app/) surfaced that
# backup_restore_module.R, audit_log_viewer_module.R, and
# admin_dashboard_module.R itself all called bare label(...)/input(...)
# -- neither is a function anywhere in base R, shiny, or htmltools;
# the correct calls are tags$label(...)/tags$input(...) -- so every
# one of these UI functions had always thrown "could not find
# function" the moment anything actually called them. No test had
# ever called any of them before, which is exactly how this went
# unnoticed through every previous change to these files.

if (!exists("admin_dashboard_ui", where = asNamespace("zzedc"))) {
  exit_file("admin_dashboard_ui not available")
}

local({
  result <- tryCatch(zzedc:::admin_dashboard_ui("test"), error = function(e) e)
  expect_false(inherits(result, "error"),
               info = if (inherits(result, "error")) conditionMessage(result) else "")
})

local({
  result <- tryCatch(zzedc:::backup_restore_ui("test"), error = function(e) e)
  expect_false(inherits(result, "error"),
               info = if (inherits(result, "error")) conditionMessage(result) else "")
})

local({
  result <- tryCatch(zzedc:::audit_log_viewer_ui("test"), error = function(e) e)
  expect_false(inherits(result, "error"),
               info = if (inherits(result, "error")) conditionMessage(result) else "")
})

local({
  result <- tryCatch(zzedc:::system_config_ui("test"), error = function(e) e)
  expect_false(inherits(result, "error"),
               info = if (inherits(result, "error")) conditionMessage(result) else "")
})

local({
  result <- tryCatch(zzedc:::help_documentation_ui("test"), error = function(e) e)
  expect_false(inherits(result, "error"),
               info = if (inherits(result, "error")) conditionMessage(result) else "")
})

local({
  result <- tryCatch(zzedc:::cfr_compliance_ui("test"), error = function(e) e)
  expect_false(inherits(result, "error"),
               info = if (inherits(result, "error")) conditionMessage(result) else "")
})

local({
  result <- tryCatch(zzedc:::user_management_ui("test"), error = function(e) e)
  expect_false(inherits(result, "error"),
               info = if (inherits(result, "error")) conditionMessage(result) else "")
})
