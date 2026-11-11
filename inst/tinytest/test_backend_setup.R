library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Choosing a database backend when a study is created: the shared
# backend descriptions, the config writers (launch_zzedc's default
# config and the setup wizard's), complete_wizard_setup() on DuckDB and
# SQLite, and the wizard module itself, driven through all six steps.

# Internal functions, bound from the namespace so the file also runs
# against the installed package under R CMD check.
backend_fits_profile <- get(".backend_fits_profile", envir = asNamespace("zzedc"))
prepare_new_backend <- get(".prepare_new_backend", envir = asNamespace("zzedc"))
setup_wizard_server <- get("setup_wizard_server", envir = asNamespace("zzedc"))

with_profile <- function(profile, code) {
  old <- options(zzedc.security_profile = profile)
  on.exit(options(old), add = TRUE)
  force(code)
}

# ---------------------------------------------------------------
# describe_backends()
# ---------------------------------------------------------------

local({
  d <- describe_backends()
  expect_identical(d$backend, c("sqlite", "duckdb", "postgresql", "mysql"))
  expect_true(all(nzchar(d$summary)) && all(nzchar(d$regulated)),
              info = "every backend has a summary and a regulated-profile statement")
  expect_identical(d$regulated[d$backend == "duckdb"], "Supported.")
})

# ---------------------------------------------------------------
# create_default_config(): readable by config::get(), right backend
# ---------------------------------------------------------------

for (b in c("sqlite", "duckdb", "postgresql", "mysql")) local({
  f <- tempfile(fileext = ".yml")
  create_default_config(f, backend = b)
  cfg <- config::get(file = f)
  expect_identical(cfg$database$backend, b, info = paste(b, "written and parsed"))
  expect_identical(cfg$security$profile, "regulated",
                   info = paste(b, "config defaults to the regulated profile"))
  txt <- paste(readLines(f), collapse = "\n")
  expect_false(grepl("[0-9a-f]{64}", txt), info = paste(b, "config contains no key"))
  dbc <- suppressWarnings(app_database_config(cfg, tempdir()))
  expect_identical(dbc$db_backend, b)
  unlink(f)
})

local({
  f <- tempfile(fileext = ".yml")
  create_default_config(f, backend = "duckdb")
  cfg <- config::get(file = f)
  expect_identical(cfg$database$encryption_key, "${DB_ENCRYPTION_KEY}",
                   info = "DuckDB key is an environment reference")
  expect_identical(cfg$database$extension_directory, "duckdb_extensions")
  unlink(f)
})

# ---------------------------------------------------------------
# create_wizard_config(): now readable by config::get()
# ---------------------------------------------------------------

local({
  f <- tempfile(fileext = ".yml")
  res <- create_wizard_config(list(
    study_name = "Trial: Phase \"2\"", protocol_id = "P-1", pi_name = "Dr. A",
    pi_email = "a@b.org", study_phase = "Pilot", target_enrollment = 10,
    session_timeout = 30, max_login_attempts = 3, enforce_https = "yes",
    db_backend = "duckdb", security_profile = "regulated"
  ), f, "salt123")
  expect_true(res$success)
  cfg <- tryCatch(config::get(file = f), error = function(e) e)
  expect_false(inherits(cfg, "error"),
               info = "wizard config parses (it was rejected: no default configuration)")
  expect_identical(cfg$study$name, "Trial: Phase \"2\"",
                   info = "a colon and quotes in the study name survive")
  expect_identical(cfg$database$backend, "duckdb")
  expect_identical(cfg$security$profile, "regulated")
  expect_true(isTRUE(cfg$security$https_only),
              info = "the wizard's HTTPS choice is written as the enforced https_only")
  unlink(f)
})

# ---------------------------------------------------------------
# Backend and profile compatibility used by the wizard
# ---------------------------------------------------------------

expect_true(backend_fits_profile("duckdb", "regulated")$ok)
expect_false(backend_fits_profile("postgresql", "regulated")$ok,
             info = "server backends cannot satisfy regulated yet")
expect_true(backend_fits_profile("postgresql", "standard")$ok)
if (!sqlite_cipher_available()) {
  expect_false(backend_fits_profile("sqlite", "regulated")$ok,
               info = "stock RSQLite cannot satisfy regulated")
  expect_true(backend_fits_profile("sqlite", "standard")$ok)
}

# ---------------------------------------------------------------
# launch_zzedc's preparation: no key, non-interactive, DuckDB
# ---------------------------------------------------------------

local({
  old <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("DB_ENCRYPTION_KEY")
          else Sys.setenv(DB_ENCRYPTION_KEY = old), add = TRUE)
  Sys.unsetenv("DB_ENCRYPTION_KEY")
  d <- tempfile("prep_")
  dir.create(d)
  expect_error(prepare_new_backend("duckdb", project_dir = d), "DB_ENCRYPTION_KEY",
               info = "non-interactive DuckDB setup without a key stops with instructions")
  expect_false(dir.exists(file.path(d, "duckdb_extensions")),
               info = "and stops before downloading anything")
})

base_study_config <- function() list(
  study_name = "Backend Test Study", protocol_id = "BT-1",
  pi_name = "Dr. Test", pi_email = "pi@example.org", study_phase = "Pilot",
  target_enrollment = 10, admin_username = "admin", admin_password = "Adm1nPass!",
  admin_fullname = "Admin User", admin_email = "admin@example.org",
  security_salt = "0123456789abcdef0123456789abcdef", session_timeout = 30,
  max_login_attempts = 3, enforce_https = "no"
)

duck_ok <- requireNamespace("duckdb", quietly = TRUE) && tryCatch(
  all(install_duckdb_extensions(tempfile("extprobe_"))$loads_offline),
  error = function(e) FALSE
)

# ---------------------------------------------------------------
# complete_wizard_setup(): DuckDB and SQLite
# ---------------------------------------------------------------

if (duck_ok) with_profile("development", {
  base <- tempfile("wiz_duck_")
  key <- generate_db_key()
  cl <- c(base_study_config(), list(db_backend = "duckdb", db_encryption_key = key,
                                    security_profile = "regulated", install_extensions = TRUE))
  res <- complete_wizard_setup(cl, base_path = base)
  expect_true(res$overall_success, info = paste(res$summary, collapse = " "))
  expect_true(isTRUE(res$database_encrypted), info = "wizard-created DuckDB database is encrypted")
  expect_true(file.exists(file.path(base, "data", "zzedc.duckdb")))
  expect_true(res$steps$duckdb_extensions$success)

  cfg <- config::get(file = file.path(base, "config.yml"))
  old <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
  Sys.setenv(DB_ENCRYPTION_KEY = key)
  dbc <- app_database_config(cfg, base)
  if (is.na(old)) Sys.unsetenv("DB_ENCRYPTION_KEY") else Sys.setenv(DB_ENCRYPTION_KEY = old)
  expect_identical(dbc$duckdb$encryption_key, key,
                   info = "the config the wizard wrote resolves to the key it used")
  init_check <- get("check_database_initialized", envir = asNamespace("zzedc"))
  expect_true(init_check(app_database_path(dbc), adapter_config = dbc),
              info = "launch_zzedc would find the study initialized")

  script <- readLines(file.path(base, "launch_app.R"))
  expect_true(any(grepl("setwd\\(", script)), info = "launch script changes to the study directory")
  expect_true(any(grepl("DB_ENCRYPTION_KEY", script)), info = "launch script checks for the key")
  expect_false(any(grepl(key, script, fixed = TRUE)), info = "launch script does not contain the key")
  unlink(base, recursive = TRUE)
})

with_profile("development", {
  base <- tempfile("wiz_sqlite_")
  cl <- c(base_study_config(), list(db_backend = "sqlite", security_profile = "standard"))
  res <- suppressWarnings(complete_wizard_setup(cl, base_path = base))
  expect_true(res$overall_success)
  expect_true(file.exists(file.path(base, "data", "zzedc.db")))
  cfg <- config::get(file = file.path(base, "config.yml"))
  expect_identical(cfg$security$profile, "standard")
  expect_identical(cfg$database$backend, "sqlite")
  unlink(base, recursive = TRUE)
})

# ---------------------------------------------------------------
# The wizard module, driven through all six steps
# ---------------------------------------------------------------

if (duck_ok && requireNamespace("shinyjs", quietly = TRUE)) with_profile("development", {
  base <- tempfile("wiz_ui_")
  dir.create(base)
  launched <- FALSE
  shiny::testServer(
    setup_wizard_server,
    args = list(base_path = base, on_launch = function() launched <<- TRUE),
    {
      session$setInputs(study_name = "UI Study", protocol_id = "UI-1", pi_name = "Dr. UI",
                        pi_email = "ui@example.org", target_enrollment = 20,
                        study_phase = "Pilot")
      session$setInputs(step1_next = 1)
      expect_equal(wizard_state$current_step, 2)

      session$setInputs(admin_username = "uiadmin", admin_fullname = "UI Admin",
                        admin_email = "uiadmin@example.org",
                        admin_password = "Str0ngPass!", admin_password_confirm = "Str0ngPass!")
      session$setInputs(step2_next = 1)
      expect_equal(wizard_state$current_step, 3)

      session$setInputs(security_profile = "regulated", confirm_salt = TRUE,
                        session_timeout = 30, enforce_https = "no", max_login_attempts = 3)
      session$setInputs(step3_next = 1)
      expect_equal(wizard_state$current_step, 4, info = "the Database step follows Security")

      session$setInputs(db_backend = "postgresql", db_host = "h", db_name = "n", db_user = "u")
      session$setInputs(stepdb_next = 1)
      expect_equal(wizard_state$current_step, 4,
                   info = "a server backend under regulated does not advance")

      session$setInputs(db_backend = "duckdb", confirm_db_key = FALSE)
      session$setInputs(stepdb_next = 2)
      expect_equal(wizard_state$current_step, 4, info = "the key must be confirmed as saved")

      session$setInputs(confirm_db_key = TRUE, install_extensions = TRUE)
      session$setInputs(stepdb_next = 3)
      expect_equal(wizard_state$current_step, 5)
      expect_identical(wizard_state$system_config$db_backend, "duckdb")

      session$setInputs(step4_next = 1)
      expect_equal(wizard_state$current_step, 6)

      session$setInputs(step5_finish = 1)
      expect_true(wizard_state$setup_complete, info = "Create Study actually creates the study")
      expect_true(file.exists(file.path(base, "config.yml")))
      expect_true(file.exists(file.path(base, "data", "zzedc.duckdb")))
      expect_true(isTRUE(wizard_state$result$database_encrypted))

      # Launch sets DB_ENCRYPTION_KEY and ZZEDC_SALT for the session;
      # restore both so later test files are unaffected.
      old <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
      old_salt <- Sys.getenv("ZZEDC_SALT", unset = NA)
      session$setInputs(launch_app = 1)
      expect_true(launched, info = "Launch calls the launch callback")
      expect_identical(Sys.getenv("DB_ENCRYPTION_KEY"),
                       wizard_state$system_config$db_encryption_key,
                       info = "the key is set for an immediate launch")
      if (is.na(old)) Sys.unsetenv("DB_ENCRYPTION_KEY") else Sys.setenv(DB_ENCRYPTION_KEY = old)
      if (is.na(old_salt)) Sys.unsetenv("ZZEDC_SALT") else Sys.setenv(ZZEDC_SALT = old_salt)
    }
  )
  unlink(base, recursive = TRUE)
})
