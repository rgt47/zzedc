library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# §11.10(g) authority checks, added 2026-11-09. require_role() is the
# shared gate now wired into approve_correction()/reject_correction()
# (data_correction.R), invalidate_signature() (electronic_signatures.R),
# lock_form_design() (crf_designer.R), and save_user_to_db()
# (user_management_module.R) -- none of which had any server-side role
# check before this.

local({
  denied <- zzedc:::require_role("Coordinator", c("Admin", "PI", "StudyManager"),
                                  "approve a data correction")
  expect_false(is.null(denied))
  expect_false(denied$success)
  expect_true(grepl("Coordinator", denied$error))
  expect_true(grepl("approve a data correction", denied$error))
})

local({
  allowed <- zzedc:::require_role("Admin", c("Admin", "PI", "StudyManager"),
                                   "approve a data correction")
  expect_null(allowed)
})

local({
  # Case- and space/underscore-insensitive matching: "Data Manager"
  # (the display string) must match an allow-list entry written the
  # same way, and the check is case-insensitive.
  expect_null(zzedc:::require_role("data manager", c("Admin", "Data Manager"), "x"))
  expect_null(zzedc:::require_role("ADMIN", c("Admin", "PI"), "x"))
  expect_false(is.null(zzedc:::require_role("Monitor", c("Admin", "PI"), "x")))
})

local({
  # NULL/unknown actor_role is denied, not silently allowed.
  denied <- zzedc:::require_role(NULL, c("Admin"), "x")
  expect_false(is.null(denied))
  expect_true(grepl("\\(none\\)", denied$error))
})

# Regression test: .assignable_roles("Data Manager") previously
# returned only "Monitor" (tier-3 fallback) because .ROLE_TIER's
# names use an underscore ("data_manager") while the display string
# has a space ("Data Manager"), and the old lookup only lowercased
# without replacing spaces. .normalize_role_name() fixes both this
# and require_role() the same way.
local({
  dm <- zzedc:::.assignable_roles("Data Manager")
  sm <- zzedc:::.assignable_roles("StudyManager")
  expect_equal(sort(dm), sort(sm),
               info = "Data Manager and StudyManager are both tier 2 and should assign the same set")
  expect_true("Coordinator" %in% dm)
  expect_true("Monitor" %in% dm)
})

local({
  expect_equal(zzedc:::.normalize_role_name("Data Manager"), "data_manager")
  expect_equal(zzedc:::.normalize_role_name("StudyManager"), "studymanager")
  expect_equal(zzedc:::.normalize_role_name(NULL), "")
  expect_equal(zzedc:::.normalize_role_name("  Admin  "), "admin")
})

# Defect 3 (zzedc-modernization-whitepaper-2026-11-13.md, Section
# 2.2): output$ui's user_input$authenticated switch only decided what
# rendered; observeEvent(input$submitcrf, ...),
# observeEvent(input$randomize_subject_btn, ...), export_data()
# (inst/app/export.R), and run_gsheets_import()
# (inst/app/gsheets_server_integration.R) had no authentication check
# of their own at all, reachable directly via Shiny.setInputValue()
# regardless of what was rendered to a given session.
# require_authenticated_action() is the shared gate now wired into
# all four.
if (requireNamespace("RSQLite", quietly = TRUE)) local({
  db_path <- tempfile(fileext = ".db")
  on.exit(unlink(db_path), add = TRUE)
  # 'standard' with plaintext SQLite now needs the deployer's opt-in
  # (owner decision 2026-11-17); this test is about authorization, not
  # storage, so it opts in.
  old_opts <- options(zzedc.security_profile = "standard",
                      zzedc.accept_unencrypted_sqlite = TRUE)
  on.exit(options(old_opts), add = TRUE)

  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
  init <- zzedc:::initialize_encrypted_database(db_path = db_path, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  on.exit({
    if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY")
    else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  }, add = TRUE)
  zzedc:::init_audit_logging(db_path = db_path)

  fake_session <- structure(
    list(token = "fake-session-token"),
    class = c("MockShinySession", "list")
  )

  # Authenticated: returns TRUE, logs nothing.
  expect_true(isTRUE(zzedc::require_authenticated_action(
    list(authenticated = TRUE), fake_session, db_path, "submit a CRF entry"
  )))

  # Unauthenticated: halts via shiny::req()'s silent-stop condition
  # (the same mechanism every other req() failure in this app uses),
  # rather than returning or throwing an ordinary error.
  err <- tryCatch({
    zzedc::require_authenticated_action(
      list(authenticated = FALSE), fake_session, db_path, "submit a CRF entry"
    )
    NULL
  }, error = function(e) e)
  expect_false(is.null(err))
  expect_true(inherits(err, "shiny.silent.error"))

  # ...and the denial is recorded, not just blocked silently --
  # required by Part 11 Sec. 11.10(e)'s audit-trail obligation; a
  # block with nothing logged leaves no record an attempt was made.
  con <- zzedc::connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rows <- DBI::dbGetQuery(
    con, "SELECT user_id, operation, details FROM audit_log WHERE event_type = 'ACCESS'"
  )
  expect_equal(nrow(rows), 1)
  expect_equal(rows$user_id[1], "unauthenticated")
  expect_equal(rows$operation[1], "DENIED")
  details <- jsonlite::fromJSON(rows$details[1])
  expect_equal(details$action, "submit a CRF entry")
  expect_equal(details$reason, "not authenticated")
})
