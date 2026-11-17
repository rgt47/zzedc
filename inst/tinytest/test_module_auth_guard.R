library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# F-NEW1 (pack review 2026-11-16, reconciliation item 1 and 2). The
# Admin, Compliance and Corrections module trees are mounted once, at
# first login, and stay mounted for the rest of the Shiny session.
# Logout (inst/app/auth.R) and automatic logoff (R/session_timeout.R)
# clear the session's identity but cannot unmount them, so every
# handler in those trees must check the current user itself. These
# tests mount each module as an authenticated user, log out exactly as
# auth.R does, and then drive the module's inputs. They also check
# that the corrections module enforces the reviewer role on the server
# and that an authorized user can still work.

if (!requireNamespace("RSQLite", quietly = TRUE)) exit_file("RSQLite not installed")

ns_get <- function(fn) get(fn, envir = asNamespace("zzedc"))

.login_session <- function(role, user_id, username) {
  shiny::reactiveValues(
    authenticated = TRUE, authentication_timestamp = Sys.time(),
    user_id = user_id, username = username, full_name = username,
    role = role, site_id = "001", must_change_password = FALSE
  )
}

# Mirrors the logout handler in inst/app/auth.R field for field.
.logout <- function(us) {
  us$authenticated <- FALSE
  us$authentication_timestamp <- NULL
  us$user_id <- NULL
  us$username <- NULL
  us$full_name <- NULL
  us$role <- NULL
  us$site_id <- NULL
  us$must_change_password <- FALSE
}

.blocked <- function(expr) {
  res <- tryCatch(expr, error = function(e) e)
  inherits(res, "shiny.silent.error")
}

old_work_dir <- Sys.getenv("ZZEDC_WORK_DIR", unset = NA_character_)
Sys.setenv(ZZEDC_WORK_DIR = tempfile("zzedc_guard_work_"))
dir.create(Sys.getenv("ZZEDC_WORK_DIR"))

# ------------------------------------------------------------------
# 1. Admin dashboard: user management after logout
# ------------------------------------------------------------------
local({
  db <- tempfile(fileext = ".db")
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = db)),
                 force_new = TRUE)
  conn <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  on.exit(unlink(db), add = TRUE)
  ns_get("ensure_edc_users_table")(conn)
  ns_get("db_insert_user")(conn, username = "admin1", password_hash = "orig_hash",
                           full_name = "Admin One", role = "Admin",
                           user_id = "U_ADMIN", created_by = "test")

  us <- .login_session("Admin", "U_ADMIN", "admin1")
  n_user <- function(name) {
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM edc_users WHERE username = ?",
                    params = list(name))$n[1]
  }

  shiny::testServer(
    ns_get("admin_dashboard_server"),
    args = list(db_pool = conn, user_session = us, db_path = shiny::reactive(db)),
    {
      clicks <- 0
      add_user <- function(name, role) {
        clicks <<- clicks + 1
        session$setInputs(`user_mgmt-add_user_btn` = clicks)
        session$setInputs(
          `user_mgmt-modal_username` = name,
          `user_mgmt-modal_fullname` = "Test Person",
          `user_mgmt-modal_email` = "person@example.org",
          `user_mgmt-modal_role` = role,
          `user_mgmt-modal_password` = "password123",
          `user_mgmt-modal_password_confirm` = "password123",
          `user_mgmt-modal_active` = TRUE
        )
        session$setInputs(`user_mgmt-modal_save` = clicks)
      }

      add_user("coord1", "Coordinator")
      expect_equal(n_user("coord1"), 1L,
                   info = "an authenticated Admin can still add a user")

      .logout(us)
      session$flushReact()

      add_user("mallory", "Admin")
      expect_equal(n_user("mallory"), 0L,
                   info = "after logout, user management must not create accounts")

      session$setInputs(`user_mgmt-reset_password` = "U_ADMIN")
      session$setInputs(`user_mgmt-reset_confirm` = 1)
      hash <- DBI::dbGetQuery(conn, "SELECT password_hash FROM edc_users WHERE user_id = 'U_ADMIN'")
      expect_equal(hash$password_hash[1], "orig_hash",
                   info = "after logout, user management must not reset passwords")

      session$setInputs(`user_mgmt-deactivate_user` = "U_ADMIN")
      session$setInputs(`user_mgmt-deactivate_confirm` = 1)
      active <- DBI::dbGetQuery(conn, "SELECT active FROM edc_users WHERE user_id = 'U_ADMIN'")
      expect_equal(as.integer(active$active[1]), 1L,
                   info = "after logout, user management must not deactivate accounts")
    }
  )
})

# ------------------------------------------------------------------
# 2. Admin dashboard: audit-log viewer after logout
# ------------------------------------------------------------------
local({
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  ns_get(".ensure_audit_tables")(con)
  for (k in 1:5) {
    ns_get(".with_db_transaction")(con, function(c) {
      ns_get(".append_audit_record")(c, "UPDATE", "subjects", paste0("R", k),
                                     "edit", user_id = "alice")
    })
  }
  us <- .login_session("Admin", "U_ADMIN", "admin1")

  shiny::testServer(
    ns_get("audit_log_viewer_server"),
    args = list(db_pool = con, user_session = us),
    {
      # output$audit_table is not asserted on: under testServer it
      # always raises a silent error from freezeReactiveValue() in
      # update_user_list(), so it cannot distinguish the guard. The
      # module's loaded state is asserted instead.
      session$flushReact()
      expect_equal(nrow(log_state$all_logs), 5L,
                   info = "the trail is loaded for an authenticated user")

      .logout(us)
      session$flushReact()

      expect_equal(nrow(log_state$all_logs), 0L,
                   info = "after logout, the loaded trail is dropped from the session")

      session$setInputs(refresh_logs = 1)
      expect_equal(nrow(log_state$all_logs), 0L,
                   info = "after logout, refreshing must not reload the audit trail")
    }
  )
})

# ------------------------------------------------------------------
# 3. Admin dashboard: randomization admin after logout
# ------------------------------------------------------------------
local({
  adapter <- get_db_adapter(config = test_backend_config("sqlite"), force_new = TRUE)
  conn <- adapter$connect()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  ns_get(".create_randomization_tables")(conn, adapter$dialect(), "sqlite", adapter)
  DBI::dbExecute(conn, "CREATE TABLE study_info (study_id TEXT PRIMARY KEY, study_name TEXT)")
  DBI::dbExecute(conn, "INSERT INTO study_info VALUES ('TESTSTUDY', 'Test Study')")
  DBI::dbExecute(conn, "CREATE TABLE edc_users (user_id TEXT, username TEXT)")
  DBI::dbExecute(conn, "INSERT INTO edc_users VALUES ('U_EVE', 'eve'), ('U_BOB', 'bob')")
  ns_get(".ensure_audit_tables")(conn, adapter = adapter)
  n_grants <- function(uid) {
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM study_unblinding_grants
                           WHERE user_id = ? AND revoked_date IS NULL",
                    params = list(uid))$n[1]
  }

  us <- .login_session("Admin", "U_ADMIN", "admin1")
  shiny::testServer(
    ns_get("randomization_admin_server"),
    args = list(db_pool = conn, user_session = us),
    {
      session$setInputs(grant_user = "U_BOB", grant_btn = 1)
      expect_equal(n_grants("U_BOB"), 1L,
                   info = "an authenticated Admin can still grant unblinded access")

      .logout(us)
      session$flushReact()

      # On 60b4c06 this grant also fails, though not because of any
      # access check (cause not traced); the grant-table render below
      # is the discriminating assertion.
      session$setInputs(grant_user = "U_EVE", grant_btn = 2)
      expect_equal(n_grants("U_EVE"), 0L,
                   info = "after logout, randomization admin must not grant unblinded access")
      expect_true(.blocked(output$grants_table),
                  info = "after logout, the unblinding-grant table must not render")
    }
  )
})

# ------------------------------------------------------------------
# 4. Compliance module after logout
# ------------------------------------------------------------------
local({
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA_character_)
  db <- tempfile(fileext = ".db")
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = db)),
                 force_new = TRUE)
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  init_audit_logging(db_path = db)
  init_electronic_signatures(db_path = db)
  on.exit({
    unlink(db)
    if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY") else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  }, add = TRUE)

  setup_conn <- DBI::dbConnect(RSQLite::SQLite(), db)
  ns_get("ensure_edc_users_table")(setup_conn)
  ns_get("db_insert_user")(setup_conn, username = "jdoe", password_hash = "h",
                           full_name = "Jane Doe", role = "Coordinator",
                           user_id = "USER_TEST_1", created_by = "test")
  ns_get("ensure_user_training_table")(setup_conn)
  ns_get("db_insert_training_record")(setup_conn, user_id = "USER_TEST_1",
                                      training_type = "GCP",
                                      training_date = Sys.Date())
  DBI::dbDisconnect(setup_conn)

  # record_training is not driven here: driven through a real
  # pool::dbPool() under testServer the run did not return (cause not
  # traced), and with a bare DBI connection poolCheckout() fails. The
  # renders and the report and verification handlers exercise the
  # guard.
  db_pool <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(db_pool), add = TRUE)
  assign("db_pool", db_pool, envir = globalenv())
  on.exit(rm("db_pool", envir = globalenv()), add = TRUE)

  us <- .login_session("Coordinator", "USER_TEST_1", "jdoe")
  shiny::testServer(
    ns_get("cfr_compliance_server"),
    args = list(user_id = shiny::reactive(us$user_id)),
    {
      session$flushReact()
      expect_false(.blocked(output$signature_count),
                   info = "an authenticated user sees the compliance summary")
      session$setInputs(generate_report = 1)
      expect_false(is.null(compliance_data$report),
                   info = "an authenticated user can generate the compliance report")

      .logout(us)
      session$flushReact()

      expect_true(.blocked(output$training_compliance_table),
                  info = "after logout, training records must not render")
      expect_true(.blocked(output$signature_count),
                  info = "after logout, the compliance summary must not render")
      expect_true(.blocked(output$compliance_report),
                  info = "after logout, the compliance report must not render")
      expect_true(is.null(compliance_data$training),
                  info = "after logout, loaded training records are dropped from the session")

      session$setInputs(verify_sig_id = "SIG_X", verify_signature = 1)
      verify_out <- tryCatch(output$signature_verification_result,
                             error = function(e) e)
      expect_true(inherits(verify_out, "error"),
                  info = "after logout, signature verification must not run")
    }
  )
})

# ------------------------------------------------------------------
# 5. Corrections module: role enforcement and post-logout access
# ------------------------------------------------------------------
local({
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA_character_)
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  on.exit({
    unlink(db)
    if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY") else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  }, add = TRUE)
  init_audit_logging(db_path = db)
  init_version_control(db_path = db)
  init_data_correction(db_path = db)
  conn <- connect_encrypted_db(db_path = db)
  DBI::dbExecute(conn, "CREATE TABLE vitals (id INTEGER PRIMARY KEY, subject_id TEXT, sbp INTEGER)")
  DBI::dbExecute(conn, "INSERT INTO vitals (subject_id, sbp) VALUES ('S001', 220), ('S002', 210),
                        ('S003', 200)")
  DBI::dbDisconnect(conn)

  q <- function(sql, params = list()) {
    c2 <- connect_encrypted_db(db_path = db)
    on.exit(DBI::dbDisconnect(c2))
    if (length(params)) DBI::dbGetQuery(c2, sql, params = params) else DBI::dbGetQuery(c2, sql)
  }
  request <- function(record_id, from, to) {
    create_correction_request("vitals", record_id, "sbp", from, to, "TRANSCRIPTION_ERROR",
                              reason_details = "Source document differs",
                              requested_by = "coord1", db_path = db)$request_id
  }
  status_of <- function(id) {
    q("SELECT status FROM correction_requests WHERE request_id = ?", list(id))$status[1]
  }
  sbp_of <- function(id) q("SELECT sbp FROM vitals WHERE id = ?", list(id))$sbp[1]
  n_denials <- function() {
    q("SELECT COUNT(*) AS n FROM audit_log WHERE event_type = 'ACCESS'
       AND operation = 'DENIED'")$n[1]
  }

  # 5a. A Coordinator (not a reviewer role) cannot apply or approve.
  approved_id <- request("1", "220", "120")
  approve_correction(approved_id, reviewed_by = "dm1", db_path = db,
                     reviewer_role = "Data Manager")
  pending_id <- request("2", "210", "110")
  approved_id_2 <- request("3", "200", "100")
  approve_correction(approved_id_2, reviewed_by = "dm1", db_path = db,
                     reviewer_role = "Data Manager")

  us <- .login_session("Coordinator", "U_COORD", "coord1")
  shiny::testServer(
    ns_get("data_correction_server"),
    args = list(current_user = shiny::reactive(us$username),
                user_role = shiny::reactive(us$role), db_path = db),
    {
      rv$selected_request <- approved_id
      session$setInputs(apply_btn = 1)
      expect_equal(status_of(approved_id), "APPROVED",
                   info = "a Coordinator must not apply a correction")
      expect_equal(sbp_of(1), 220L,
                   info = "a Coordinator's apply attempt must not change the stored value")

      rv$selected_request <- pending_id
      session$setInputs(review_comments = "looks right to me", approve_btn = 1)
      expect_equal(status_of(pending_id), "PENDING",
                   info = "a Coordinator must not approve a correction")
    }
  )
  expect_true(n_denials() >= 1L,
              info = "a denied correction action is recorded as an ACCESS/DENIED audit event")

  # 5b. A Data Manager can still apply; after logout nothing works.
  us <- .login_session("Data Manager", "U_DM", "dm1")
  shiny::testServer(
    ns_get("data_correction_server"),
    args = list(current_user = shiny::reactive(us$username),
                user_role = shiny::reactive(us$role), db_path = db),
    {
      rv$selected_request <- approved_id
      session$setInputs(apply_btn = 1)
      expect_equal(status_of(approved_id), "APPLIED",
                   info = "a Data Manager can still apply an approved correction")
      expect_equal(sbp_of(1), 120L,
                   info = "the authorized apply changes the stored value")
      expect_false(.blocked(output$pending_table),
                   info = "an authorized reviewer sees the pending queue")

      .logout(us)
      session$flushReact()

      # On 60b4c06 this approve also fails, though not because of any
      # access check (cause not traced); the apply below is the
      # discriminating post-logout write.
      rv$selected_request <- pending_id
      session$setInputs(review_comments = "approving after logout", approve_btn = 1)
      expect_equal(status_of(pending_id), "PENDING",
                   info = "after logout, the corrections module must not approve")
      rv$selected_request <- approved_id_2
      session$setInputs(apply_btn = 2)
      expect_equal(status_of(approved_id_2), "APPROVED",
                   info = "after logout, the corrections module must not apply an approved correction")
      expect_equal(sbp_of(3), 200L,
                   info = "after logout, the corrections module must not change data")
      expect_true(.blocked(output$pending_table),
                  info = "after logout, the pending-corrections queue must not render")
      expect_true(.blocked(output$all_corrections_table),
                  info = "after logout, the correction history must not render")
    }
  )
})

# ------------------------------------------------------------------
# 6. The guard itself, and the session flag the app now passes
# ------------------------------------------------------------------
guard_fn <- tryCatch(ns_get(".module_access_guard"), error = function(e) NULL)
expect_true(is.function(guard_fn), info = "the shared module access guard exists")
if (is.function(guard_fn)) local({
  g <- guard_fn()
  expect_false(shiny::isolate(g$authorized()),
               info = "a module mounted with no identity at all is denied")

  us <- .login_session("Coordinator", "U1", "coord1")
  g <- guard_fn(user_session = us)
  expect_true(shiny::isolate(g$authorized()),
              info = "an authenticated session is authorized")
  expect_false(shiny::isolate(g$authorized(roles = c("Admin", "PI"))),
               info = "a role outside the allowed set is denied")
  expect_true(shiny::isolate(g$authorized(roles = c("coordinator"))),
              info = "roles match case-insensitively, as in require_role()")

  # The flag wins over identity fields that were not cleared.
  us$authenticated <- FALSE
  expect_false(shiny::isolate(g$authorized()),
               info = "authenticated = FALSE denies even with a username still set")

  g <- guard_fn(user = shiny::reactive(""), role = shiny::reactive("Admin"))
  expect_false(shiny::isolate(g$authorized()),
               info = "an empty user is denied without a session")
})

local({
  us <- .login_session("Coordinator", "USER_TEST_1", "jdoe")
  us$authenticated <- FALSE
  res <- tryCatch(shiny::testServer(
    ns_get("cfr_compliance_server"),
    args = list(user_id = shiny::reactive("USER_TEST_1"), user_session = us),
    {
      expect_true(.blocked(output$signature_count),
                  info = "with user_session$authenticated FALSE, compliance renders nothing")
    }
  ), error = function(e) e)
  expect_false(inherits(res, "error"),
               info = "cfr_compliance_server() accepts the app's user_session")

  res <- tryCatch(shiny::testServer(
    ns_get("data_correction_server"),
    args = list(current_user = shiny::reactive("dm1"),
                user_role = shiny::reactive("Data Manager"),
                db_path = NULL, user_session = us),
    {
      expect_true(.blocked(output$pending_table),
                  info = "with user_session$authenticated FALSE, corrections renders nothing")
    }
  ), error = function(e) e)
  expect_false(inherits(res, "error"),
               info = "data_correction_server() accepts the app's user_session")
})

# ------------------------------------------------------------------
# 7. Backup and restore after logout
# ------------------------------------------------------------------
if (requireNamespace("shinyjs", quietly = TRUE)) local({
  dir <- tempfile("bkguard_")
  bdir <- file.path(dir, "backups")
  dir.create(bdir, recursive = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  path <- file.path(dir, "study.db")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbWriteTable(con, "t", data.frame(v = "A"))
  DBI::dbDisconnect(con)
  backup <- file.path(bdir, "backup_1.db")
  file.copy(path, backup)

  us <- .login_session("Admin", "U_ADMIN", "admin1")
  shiny::testServer(
    ns_get("backup_restore_server"),
    args = list(db_path = shiny::reactive(path), backup_dir = bdir, user_session = us),
    {
      session$setInputs(select_backup = backup)
      expect_false(is.null(backup_state$selected_backup),
                   info = "an authenticated user can select a backup")

      .logout(us)
      session$flushReact()

      expect_equal(nrow(backup_state$backups), 0L,
                   info = "after logout, the backup list is dropped from the session")
      backup_state$selected_backup <- backup
      session$setInputs(restore_confirmation = "RESTORE", restore_btn = 1)
      expect_false(file.exists(paste0(path, ".restore-pending")),
                   info = "after logout, a restore cannot be staged")
      session$setInputs(delete_backup = backup)
      session$setInputs(confirm_delete = TRUE)
      expect_true(file.exists(backup),
                  info = "after logout, a backup cannot be deleted")
      session$setInputs(download_backup = backup)
      expect_true(inherits(tryCatch(output$download_file, error = function(e) e), "error"),
                  info = "after logout, a backup cannot be downloaded")
    }
  )
})

if (is.na(old_work_dir)) Sys.unsetenv("ZZEDC_WORK_DIR") else Sys.setenv(ZZEDC_WORK_DIR = old_work_dir)
