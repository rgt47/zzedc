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
  app_dir <- system.file("app", package = "zzedc")
  lines <- readLines(file.path(app_dir, "auth.R"))
  end <- grep("^}", lines)[1]
  env <- new.env(parent = globalenv())
  eval(parse(text = lines[1:end]), envir = env)
  env$authenticate_user
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

} else {
  exit_file("pool and/or digest not installed")
}