library(tinytest)

# Smoke tests for module server reactivity using
# `shiny::testServer()`. Complements the existing module tests
# in test_auth-module.R / test_data-module.R / test_quality-
# dashboard.R, which target helper functions and UI structure
# rather than reactive flow.
#
# Each block exercises one module's server end-to-end through
# `shiny::testServer()` so that downstream reactives, observers,
# and outputs are evaluated in the same context the running app
# uses. The intent is breadth (Tier 1 safety net) rather than
# depth: a single happy-path trigger per module.

if (file.exists("_setup.R")) source("_setup.R")

# `shinyalert` is fired from observers in auth_server etc. but is
# not exercised by these tests. Stub to a no-op so the modal call
# does not warn during testServer flushes.
if (!exists("shinyalert", mode = "function")) {
  shinyalert <- function(...) invisible(NULL)
  assign("shinyalert", shinyalert, envir = .GlobalEnv)
}

# ----------------------------------------------------------------
# auth_server: login button populates session reactive values
# ----------------------------------------------------------------

local({
  if (!exists("auth_server")) return(invisible())

  # auth_server depends on globals db_pool and cfg via
  # authenticate_user(). Provide a minimal seeded SQLite DB and
  # matching test config in .GlobalEnv before invoking testServer.
  test_con <- create_test_db()
  assign("db_pool", test_con, envir = .GlobalEnv)
  assign("cfg",     create_test_config(), envir = .GlobalEnv)

  user_input <- shiny::reactiveValues(
    authenticated = FALSE,
    user_id = NULL, username = NULL, full_name = NULL,
    role = NULL, site_id = NULL
  )

  shiny::testServer(
    zzedc:::auth_server,
    args = list(user_input = user_input),
    {
      # Drive the login flow as the user would.
      session$setInputs(
        username     = "testuser",
        password     = "testpass",
        login_button = 1
      )

      expect_true(isolate(user_input$authenticated))
      expect_equal(isolate(user_input$username),  "testuser")
      expect_equal(isolate(user_input$full_name), "Test User")
      expect_equal(isolate(user_input$role),      "Admin")
    }
  )

  DBI::dbDisconnect(test_con)
  rm("db_pool", "cfg", envir = .GlobalEnv)
})

# ----------------------------------------------------------------
# data_server: sample data source populates reactive data
# ----------------------------------------------------------------

local({
  if (!exists("data_server")) return(invisible())

  shiny::testServer(zzedc:::data_server, {
    session$setInputs(
      data_source = "sample",
      max_rows    = 50
    )

    # `current_data()` is a private reactive in the module; access
    # via `session$getReturned()` would require the module to
    # expose it. Instead, drive an output that depends on it and
    # verify the rendered string is non-empty. The "sample"
    # branch produces a 50-row data frame, so the summary output
    # contains "Rows: 50".
    summary_text <- output$data_summary
    expect_true(grepl("Rows: 50", summary_text, fixed = TRUE))
    expect_true(grepl("Columns: 9", summary_text, fixed = TRUE))
  })
})

# ----------------------------------------------------------------
# quality_dashboard_server: metric outputs render from a seeded DB
# ----------------------------------------------------------------

local({
  if (!exists("quality_dashboard_server")) return(invisible())

  # quality_dashboard_server queries form_submissions and
  # form_field_values. Build a minimal SQLite fixture with the
  # exact columns the module reads.
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(con, "
    CREATE TABLE form_submissions (
      subject_id      TEXT,
      form_name       TEXT,
      status          TEXT,
      submission_date TEXT
    )")
  DBI::dbExecute(con, "
    CREATE TABLE form_field_values (
      field_name  TEXT,
      field_value TEXT,
      required    INTEGER
    )")
  DBI::dbExecute(con, "
    INSERT INTO form_submissions
      (subject_id, form_name, status, submission_date)
    VALUES
      ('S-001', 'Demographics', 'complete', date('now')),
      ('S-002', 'Demographics', 'complete', date('now')),
      ('S-003', 'Demographics', 'incomplete', date('now')),
      ('S-004', 'Labs',         'flagged',  date('now'))
  ")
  DBI::dbExecute(con, "
    INSERT INTO form_field_values (field_name, field_value, required)
    VALUES
      ('age',    '65',  1),
      ('age',    NULL,  1),
      ('weight', NULL,  1)
  ")

  # `db_conn` is invoked as a function inside the module, so wrap
  # the connection in a closure rather than passing it directly.
  db_conn_fn <- function() con

  shiny::testServer(
    zzedc:::quality_dashboard_server,
    args = list(db_conn = db_conn_fn, refresh_interval = 60000),
    {
      expect_equal(output$metric_total,         "4")
      expect_equal(output$metric_complete,      "2")
      expect_equal(output$metric_incomplete_pct, "50%")
      expect_equal(output$metric_flagged,       "1")
    }
  )

  DBI::dbDisconnect(con)
})
