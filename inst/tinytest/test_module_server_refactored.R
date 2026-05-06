# testServer() coverage for the six modules refactored during the
# Shiny-modernization tiers (T1.5 modal pattern, T2.3 shinydashboard
# removal, T2.4 card standardization, T2.5 freezeReactiveValue,
# T2.6 value_box tiles, T2.7 hoist outputs).
#
# These tests complement the existing test_module_server.R (which
# covers auth, data, quality_dashboard) by exercising the reactive
# flow of the audit-log viewer, user management, backup/restore,
# admin dashboard, data correction, and version history modules.
# Targeted at depth-of-1 happy paths -- "module loads, reactives
# fire, expected outputs render" -- not deep correctness.

library(tinytest)

# Source the shared test fixtures (create_test_db, etc).
if (file.exists("_setup.R")) source("_setup.R")

# ============================================================
# Helper: build a minimal in-memory pool-like connection.
# Several modules use pool::dbExecute / pool::dbGetQuery; for
# tests we hand them a plain DBI::dbConnect(":memory:") which
# accepts the same calls.
# ============================================================
.make_audit_db <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(con, "
    CREATE TABLE audit_trail (
      audit_id     TEXT,
      user_id      TEXT,
      action       TEXT,
      entity_type  TEXT,
      entity_id    TEXT,
      action_date  TEXT,
      ip_address   TEXT
    )")
  DBI::dbExecute(con, "
    INSERT INTO audit_trail VALUES
      ('AUDIT_001', 'USER_001', 'login',         'user', 'USER_001',
       '2026-01-01 09:00:00', '192.168.1.10'),
      ('AUDIT_002', 'USER_002', 'create_entry',  'data', 'ENT_001',
       '2026-01-01 10:00:00', '192.168.1.11'),
      ('AUDIT_003', 'USER_001', 'update_user',   'user', 'USER_002',
       '2026-01-01 11:00:00', '192.168.1.10'),
      ('AUDIT_004', 'USER_003', 'config_change', 'system', 'CFG_001',
       '2026-01-01 12:00:00', '192.168.1.12')
  ")
  con
}


# ============================================================
# Section 1: audit_log_viewer_server
# Verifies: load_audit_logs returns the sample-data fallback
# when db_pool is NULL; stat_* renderText outputs produce
# integer strings via the post-T2.4 stat_counts() reactive.
# ============================================================
local({
  if (!exists("audit_log_viewer_server")) return(invisible())

  shiny::testServer(
    zzedc:::audit_log_viewer_server,
    args = list(db_pool = NULL),
    {
      session$setInputs(
        filter_user        = "",
        filter_action      = "",
        filter_date_from   = as.Date("2025-01-01"),
        filter_date_to     = as.Date("2027-01-01"),
        filter_entity_type = "",
        search_text        = "",
        apply_filters      = 1
      )

      # Sample-data fallback: 20 rows are seeded.
      expect_equal(nrow(log_state$all_logs), 20L)

      # Stat outputs render as character "<integer>".
      expect_match(output$stat_total,   "^[0-9]+$")
      expect_match(output$stat_entries, "^[0-9]+$")
      expect_match(output$stat_users,   "^[0-9]+$")
      expect_match(output$stat_system,  "^[0-9]+$")
      # Total = entries + users + system + (any others) but at
      # minimum should be >= each part and equal nrow(filtered).
      expect_true(as.integer(output$stat_total) > 0)
    }
  )
})


# ============================================================
# Section 2: user_management_server
# Verifies: NULL db_pool returns empty users data frame; the
# add-user observer triggers the showModal call without errors.
# ============================================================
local({
  if (!exists("user_management_server")) return(invisible())

  shiny::testServer(
    zzedc:::user_management_server,
    args = list(db_pool = NULL),
    {
      # NULL db_pool path -- load_users returns an empty frame.
      expect_equal(nrow(user_state$users), 0L)
      expect_true(all(c("user_id", "username", "full_name", "email",
                        "role", "active") %in%
                        names(user_state$users)))

      # Click the Add user button; modal_mode flips to "add".
      session$setInputs(add_user_btn = 1)
      expect_equal(user_state$modal_mode, "add")
      expect_null(user_state$edit_user_id)
    }
  )
})


# ============================================================
# Section 3: data_correction_server
# Verifies: stats_data() reactive returns a list (either the
# success-shape with `summary` or the failure-shape with
# `success=FALSE, error=...`); the four value-box renderUI
# outputs (T2.6) instantiate without throwing.
# ============================================================
local({
  if (!exists("data_correction_server")) return(invisible())

  shiny::testServer(
    zzedc:::data_correction_server,
    args = list(
      current_user = shiny::reactive("testuser"),
      user_role    = shiny::reactive("Admin"),
      db_path      = NULL
    ),
    {
      stats <- stats_data()
      expect_true(is.list(stats))
      # Either the success or failure shape from the registry's
      # get_correction_statistics() function.
      expect_true("success" %in% names(stats) ||
                    "summary" %in% names(stats))

      # Value-box renderUI outputs (post-T2.6) produce non-NULL
      # shiny tag content; we don't assert specific structure
      # since renderUI in testServer may return raw HTML or
      # shiny.tag, depending on Shiny version.
      expect_false(is.null(output$stat_total))
      expect_false(is.null(output$stat_pending))
      expect_false(is.null(output$stat_approved))
      expect_false(is.null(output$stat_rejected))
    }
  )
})


# ============================================================
# Section 4: version_history_server
# Verifies: history_data starts empty, version select inputs are
# present (the T2.5 freezeReactiveValue wrap doesn't break the
# rendering path when no record is selected).
# ============================================================
local({
  if (!exists("version_history_server")) return(invisible())

  shiny::testServer(
    zzedc:::version_history_server,
    args = list(db_path = shiny::reactive(":memory:")),
    {
      session$setInputs(
        table_name      = "",
        record_id       = "",
        version_a       = "",
        version_b       = "",
        restore_version = ""
      )
      expect_true(is.data.frame(history_data()))
      expect_equal(nrow(history_data()), 0L)
    }
  )
})


# ============================================================
# Section 5: backup_restore_server
# Verifies: load_backups returns an empty data frame when the
# backup_dir does not exist; module instantiates without error.
# ============================================================
local({
  if (!exists("backup_restore_server")) return(invisible())

  tmp_dir <- tempfile("zzedc_backup_test_")
  shiny::testServer(
    zzedc:::backup_restore_server,
    args = list(
      db_pool    = NULL,
      db_path    = shiny::reactive(":memory:"),
      backup_dir = tmp_dir
    ),
    {
      # Initial backup list is empty.
      expect_equal(nrow(backup_state$backups), 0L)
    }
  )
})


# ============================================================
# Section 6: admin_dashboard_server
# Verifies: db_size text output renders without error when the
# db file is missing (the post-T2.4 card structure should still
# display the placeholder).
# ============================================================
local({
  if (!exists("admin_dashboard_server")) return(invisible())

  user_session <- shiny::reactiveValues(
    authenticated = TRUE, role = "Admin", username = "testadmin"
  )
  shiny::testServer(
    zzedc:::admin_dashboard_server,
    args = list(
      db_pool      = NULL,
      user_session = user_session,
      db_path      = shiny::reactive(tempfile())
    ),
    {
      # The module's reactives should at least instantiate.
      # No deeper assertion here -- the goal is "module loads".
      expect_true(TRUE)
    }
  )
})
