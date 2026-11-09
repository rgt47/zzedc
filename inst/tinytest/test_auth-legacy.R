library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Tests for legacy authentication module (inst/app/auth.R).
# These exercise authenticate_user() as actually deployed, by
# extracting it from the live inst/app/auth.R source rather than
# re-implementing it, so a regression in the shipped file is
# caught here.

.load_authenticate_user <- function() {
  .load_auth_env()$authenticate_user
}

# authenticate_user() and unlock_user_account() are the first two
# top-level definitions in inst/app/auth.R (everything after is the
# login observeEvent/UI, which needs a real Shiny reactive context to
# source). The second `^}` closes unlock_user_account(), so evaluating
# through it loads both without touching the Shiny-dependent code
# below.
.load_auth_env <- function() {
  app_dir <- system.file("app", package = "zzedc")
  lines <- readLines(file.path(app_dir, "auth.R"))
  end <- grep("^}", lines)[2]
  env <- new.env(parent = globalenv())
  eval(parse(text = lines[1:end]), envir = env)
  env
}

.make_auth_test_db <- function() {
  db_path <- tempfile(fileext = ".db")
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  zzedc:::ensure_edc_users_table(conn)
  pw_hash <- digest::digest(paste0("correct-horse", "test-salt"),
                             algo = "sha256")
  zzedc:::db_insert_user(conn, username = "testuser", password_hash = pw_hash,
                  full_name = "Test User", role = "Admin")
  DBI::dbDisconnect(conn)
  pool::dbPool(RSQLite::SQLite(), dbname = db_path, minSize = 1, maxSize = 2)
}

# Same as .make_auth_test_db(), but also wires up audit logging
# against the identical file, so the §11.300 lockout tests below can
# assert that LOCKOUT/UNLOCK rows actually land in audit_log, not
# just that authenticate_user()'s return value is correct. Returns
# list(pool=, db_path=); callers must also Sys.unsetenv(DB_ENCRYPTION_KEY)
# via on.exit alongside pool::poolClose() and get_db_adapter() reset,
# since this mutates process-wide state the same way other tests in
# this suite already do (see setup_cd_test()/cleanup_cd_test() in
# test_crf_designer.R).
.make_auth_test_db_with_audit <- function() {
  db_path <- tempfile(fileext = ".db")

  # connect_encrypted_db(db_path = NULL) only consults the cached
  # adapter for non-sqlite backends (R/db_connection.R); for "sqlite"
  # it falls through to get_db_path(), which reads ZZEDC_DB_PATH.
  # Both must be set for log_failed_login()/log_account_lockout()/
  # log_security_event() (all called with db_path = NULL from inside
  # inst/app/auth.R) to land in this same temp file.
  Sys.setenv(ZZEDC_DB_PATH = db_path)

  # Initialize the encrypted-db machinery first (creates study_info/
  # subjects and sets up the key), then add edc_users with a plain
  # connection to the same file -- doing it in the other order makes
  # initialize_encrypted_database() refuse to run ("Database already
  # exists") since ensure_edc_users_table() would have created the
  # file first.
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = db_path)),
                 force_new = TRUE)
  init_res <- initialize_encrypted_database(db_path)
  Sys.setenv(DB_ENCRYPTION_KEY = init_res$key)
  init_audit_logging()

  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  zzedc:::ensure_edc_users_table(conn)
  pw_hash <- digest::digest(paste0("correct-horse", "test-salt"),
                             algo = "sha256")
  zzedc:::db_insert_user(conn, username = "testuser", password_hash = pw_hash,
                  full_name = "Test User", role = "Admin")
  DBI::dbDisconnect(conn)

  list(
    pool = pool::dbPool(RSQLite::SQLite(), dbname = db_path, minSize = 1, maxSize = 2),
    db_path = db_path
  )
}

if (requireNamespace("pool", quietly = TRUE) &&
      requireNamespace("digest", quietly = TRUE)) {

  # inst/app/auth.R calls bare digest(), relying on global.R's
  # package-loading loop (library(pkg, character.only = TRUE,
  # quietly = TRUE)) to have attached it already in the real app.
  # This test harness does not run global.R, so attach it here to
  # match the real deployment's environment.
  library(digest)

  # Regression test: config.yml files scaffolded by launch_zzedc()
  # (and any config missing auth$salt_env_var) must not crash login.
  # cfg$auth$salt_env_var being NULL previously made
  # Sys.getenv(NULL) return every environment variable on the
  # machine, so `salt == ""` compared a length > 100 vector and
  # `if()` threw "the condition has length > 1" on every login
  # attempt. See inst/app/auth.R.
  local({
    authenticate_user <- .load_authenticate_user()
    db_pool <- .make_auth_test_db()
    on.exit(pool::poolClose(db_pool), add = TRUE)

    assign("db_pool", db_pool, envir = globalenv())
    assign("cfg", list(auth = list(default_salt = "test-salt")),
           envir = globalenv())
    on.exit({
      rm("db_pool", envir = globalenv())
      rm("cfg", envir = globalenv())
    }, add = TRUE)

    result <- authenticate_user("testuser", "correct-horse")
    expect_true(result$success,
                info = "login must succeed when auth$salt_env_var is absent from config")
    expect_equal(result$username, "testuser")
  })

  # Correct credentials, with salt_env_var present, succeed.
  local({
    authenticate_user <- .load_authenticate_user()
    db_pool <- .make_auth_test_db()
    on.exit(pool::poolClose(db_pool), add = TRUE)

    withr::local_envvar(c(ZZEDC_TEST_SALT = "test-salt"))
    assign("db_pool", db_pool, envir = globalenv())
    assign("cfg", list(auth = list(salt_env_var = "ZZEDC_TEST_SALT",
                                    default_salt = "wrong-salt")),
           envir = globalenv())
    on.exit({
      rm("db_pool", envir = globalenv())
      rm("cfg", envir = globalenv())
    }, add = TRUE)

    result <- authenticate_user("testuser", "correct-horse")
    expect_true(result$success,
                info = "login must succeed using the salt from salt_env_var when set")
  })

  # Wrong password fails cleanly (no error), regardless of
  # salt_env_var configuration.
  local({
    authenticate_user <- .load_authenticate_user()
    db_pool <- .make_auth_test_db()
    on.exit(pool::poolClose(db_pool), add = TRUE)

    assign("db_pool", db_pool, envir = globalenv())
    assign("cfg", list(auth = list(default_salt = "test-salt")),
           envir = globalenv())
    on.exit({
      rm("db_pool", envir = globalenv())
      rm("cfg", envir = globalenv())
    }, add = TRUE)

    result <- authenticate_user("testuser", "wrong-password")
    expect_false(result$success)
    expect_equal(result$message, "Invalid password")
  })

  # Unknown username fails cleanly (no error).
  local({
    authenticate_user <- .load_authenticate_user()
    db_pool <- .make_auth_test_db()
    on.exit(pool::poolClose(db_pool), add = TRUE)

    assign("db_pool", db_pool, envir = globalenv())
    assign("cfg", list(auth = list(default_salt = "test-salt")),
           envir = globalenv())
    on.exit({
      rm("db_pool", envir = globalenv())
      rm("cfg", envir = globalenv())
    }, add = TRUE)

    result <- authenticate_user("no-such-user", "correct-horse")
    expect_false(result$success)
  })

  # §11.300 password lockout, added 2026-11-09. authenticate_user()
  # had no concept of counting failed attempts at all (despite
  # inst/app/auth.R declaring an unused num_fails_to_lockout <- 3
  # constant); these tests exercise the real lockout/auto-unlock/
  # manual-unlock behavior as actually deployed.

  # Reaching max_failed_attempts locks the account, even on a
  # subsequent attempt with the correct password.
  local({
    auth_env <- .load_auth_env()
    authenticate_user <- auth_env$authenticate_user
    test_db <- .make_auth_test_db_with_audit()
    on.exit({
      pool::poolClose(test_db$pool)
      unlink(test_db$db_path)
      Sys.unsetenv('ZZEDC_DB_PATH')
    }, add = TRUE)

    assign("db_pool", test_db$pool, envir = globalenv())
    assign("cfg", list(auth = list(default_salt = "test-salt",
                                    max_failed_attempts = 3,
                                    lockout_duration_minutes = 15)),
           envir = globalenv())
    on.exit({
      rm("db_pool", envir = globalenv())
      rm("cfg", envir = globalenv())
    }, add = TRUE)

    r1 <- authenticate_user("testuser", "wrong-password")
    r2 <- authenticate_user("testuser", "wrong-password")
    r3 <- authenticate_user("testuser", "wrong-password")
    expect_false(r1$success)
    expect_false(r2$success)
    expect_false(r3$success)
    expect_true(grepl("locked", r3$message, ignore.case = TRUE),
                info = "3rd failed attempt should report the account as locked")

    r4 <- authenticate_user("testuser", "correct-horse")
    expect_false(r4$success,
                 info = "the correct password must still be rejected while locked")
    expect_true(grepl("locked", r4$message, ignore.case = TRUE))

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    rows <- DBI::dbGetQuery(con, "SELECT event_type, user_id FROM audit_log")
    expect_true("LOCKOUT" %in% rows$event_type,
                info = "locking an account must write a LOCKOUT row to audit_log")
  })

  # The account auto-unlocks once the configured lockout window has
  # elapsed, without any manual intervention.
  local({
    auth_env <- .load_auth_env()
    authenticate_user <- auth_env$authenticate_user
    test_db <- .make_auth_test_db_with_audit()
    on.exit({
      pool::poolClose(test_db$pool)
      unlink(test_db$db_path)
      Sys.unsetenv('ZZEDC_DB_PATH')
    }, add = TRUE)

    assign("db_pool", test_db$pool, envir = globalenv())
    # A fractional-minute window (1.2s) keeps this test fast while
    # still exercising the real elapsed-time comparison.
    assign("cfg", list(auth = list(default_salt = "test-salt",
                                    max_failed_attempts = 3,
                                    lockout_duration_minutes = 0.02)),
           envir = globalenv())
    on.exit({
      rm("db_pool", envir = globalenv())
      rm("cfg", envir = globalenv())
    }, add = TRUE)

    for (i in 1:3) authenticate_user("testuser", "wrong-password")
    still_locked <- authenticate_user("testuser", "correct-horse")
    expect_false(still_locked$success)

    Sys.sleep(1.5)
    after_wait <- authenticate_user("testuser", "correct-horse")
    expect_true(after_wait$success,
                info = "login must succeed once the lockout window has elapsed")

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    rows <- DBI::dbGetQuery(con, "SELECT event_type FROM audit_log")
    expect_true("UNLOCK" %in% rows$event_type,
                info = "the auto-unlock must write an UNLOCK row to audit_log")
  })

  # A successful login resets the failed-attempt counter -- a user
  # who mistypes their password once or twice, then gets it right,
  # should not be one mistake away from lockout afterward.
  local({
    authenticate_user <- .load_authenticate_user()
    db_pool <- .make_auth_test_db()
    on.exit(pool::poolClose(db_pool), add = TRUE)

    assign("db_pool", db_pool, envir = globalenv())
    assign("cfg", list(auth = list(default_salt = "test-salt",
                                    max_failed_attempts = 3,
                                    lockout_duration_minutes = 15)),
           envir = globalenv())
    on.exit({
      rm("db_pool", envir = globalenv())
      rm("cfg", envir = globalenv())
    }, add = TRUE)

    authenticate_user("testuser", "wrong-password")
    authenticate_user("testuser", "wrong-password")
    reset <- authenticate_user("testuser", "correct-horse")
    expect_true(reset$success)

    row <- pool::dbGetQuery(db_pool,
      "SELECT failed_login_attempts FROM edc_users WHERE username = 'testuser'")
    expect_equal(as.integer(row$failed_login_attempts[1]), 0L)
  })

  # unlock_user_account() restores access immediately, without
  # waiting for the lockout window -- the admin "loss management"
  # path §11.300 also requires.
  local({
    auth_env <- .load_auth_env()
    authenticate_user <- auth_env$authenticate_user
    unlock_user_account <- auth_env$unlock_user_account
    test_db <- .make_auth_test_db_with_audit()
    on.exit({
      pool::poolClose(test_db$pool)
      unlink(test_db$db_path)
      Sys.unsetenv('ZZEDC_DB_PATH')
    }, add = TRUE)

    assign("db_pool", test_db$pool, envir = globalenv())
    assign("cfg", list(auth = list(default_salt = "test-salt",
                                    max_failed_attempts = 3,
                                    lockout_duration_minutes = 15)),
           envir = globalenv())
    on.exit({
      rm("db_pool", envir = globalenv())
      rm("cfg", envir = globalenv())
    }, add = TRUE)

    for (i in 1:3) authenticate_user("testuser", "wrong-password")
    expect_false(authenticate_user("testuser", "correct-horse")$success)

    unlock_result <- unlock_user_account("testuser", "admin_tester")
    expect_true(unlock_result$success)

    after_unlock <- authenticate_user("testuser", "correct-horse")
    expect_true(after_unlock$success,
                info = "login must succeed immediately after a manual unlock")

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    rows <- DBI::dbGetQuery(con, "
      SELECT event_type, operation FROM audit_log WHERE event_type = 'UNLOCK'
    ")
    expect_true(any(grepl("admin_tester", rows$operation)),
                info = "the manual unlock must be attributed to the admin who performed it")
  })

} else {
  exit_file("pool and/or digest not installed")
}