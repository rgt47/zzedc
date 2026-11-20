library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Owner decisions of 2026-11-17 (docs/encryption-compliance-plan-2026-11-10.md
# Section 7):
#   F1: under the 'standard' profile, a SQLite driver that cannot encrypt
#       makes every request for an encrypted SQLite database fail, unless
#       security.accept_unencrypted_sqlite is set.
#   DuckDB, encrypted, is the default backend wherever a new study or
#       deployment configuration is created.
#   F-NEW8: the Google Sheets form loader opens the study database
#       through an adapter, so it obeys the same rules.
# Each block was written to fail against 60b4c06, where 'standard' only
# warned, the creation defaults were SQLite, and the loader sent every
# configuration down the SQLite path.

ns <- asNamespace("zzedc")
for (internal in c("reset_encryption_warnings", "connect_encrypted",
                   ".require_backend_package", "wizard_adapter_config",
                   ".detect_db_file_format")) {
  assign(internal, get(internal, envir = ns))
}

stock_rsqlite <- !sqlite_cipher_available()
has_duckdb <- requireNamespace("duckdb", quietly = TRUE)
duck_ok <- has_duckdb && tryCatch({
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "INSTALL httpfs")
  DBI::dbExecute(con, "LOAD httpfs")
  TRUE
}, error = function(e) FALSE)

# Run `code` with the profile and opt-in given, restoring options, the
# opt-in environment variable, the cached adapter, and the once-per-
# session notice state afterward.
with_policy <- function(profile, accept = NULL, code) {
  old <- options(zzedc.security_profile = profile,
                 zzedc.accept_unencrypted_sqlite = accept)
  old_env <- Sys.getenv("ZZEDC_ACCEPT_UNENCRYPTED_SQLITE", unset = NA)
  Sys.unsetenv("ZZEDC_ACCEPT_UNENCRYPTED_SQLITE")
  cache <- get(".db_adapter_cache", envir = ns)
  had_adapter <- exists("adapter", envir = cache)
  previous <- if (had_adapter) cache$adapter else NULL
  on.exit({
    options(old)
    if (is.na(old_env)) Sys.unsetenv("ZZEDC_ACCEPT_UNENCRYPTED_SQLITE")
    else Sys.setenv(ZZEDC_ACCEPT_UNENCRYPTED_SQLITE = old_env)
    if (had_adapter) assign("adapter", previous, envir = cache)
    else if (exists("adapter", envir = cache)) rm("adapter", envir = cache)
    reset_encryption_warnings()
  }, add = TRUE)
  reset_encryption_warnings()
  force(code)
}

use_sqlite_adapter <- function(path) {
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = path)),
                 force_new = TRUE)
}

make_plain_sqlite <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, "CREATE TABLE edc_forms (workingname TEXT, fullname TEXT)")
  DBI::dbExecute(con, "INSERT INTO edc_forms VALUES ('demo', 'Demo form')")
  DBI::dbDisconnect(con)
  path
}

with_env <- function(vars, code) {
  old <- Sys.getenv(names(vars), unset = NA, names = TRUE)
  on.exit(for (n in names(old)) {
    if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, as.list(old[n]))
  }, add = TRUE)
  for (n in names(vars)) {
    if (is.na(vars[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, as.list(vars[n]))
  }
  force(code)
}

# ---------------------------------------------------------------
# 1. The opt-in is resolved like the profile
# ---------------------------------------------------------------

with_policy("standard", NULL, {
  expect_identical(resolve_accept_unencrypted_sqlite(tempfile())$accept, FALSE,
                   info = "the opt-in defaults to FALSE")
  top <- tempfile(fileext = ".yml")
  writeLines("security:\n  accept_unencrypted_sqlite: true", top)
  nested <- tempfile(fileext = ".yml")
  writeLines("default:\n  security:\n    accept_unencrypted_sqlite: yes", nested)
  expect_identical(resolve_accept_unencrypted_sqlite(top)$source, "config.yml",
                   info = "top-level security.accept_unencrypted_sqlite is read")
  expect_true(resolve_accept_unencrypted_sqlite(nested)$accept,
              info = "default.security.accept_unencrypted_sqlite is read")
  with_env(c(ZZEDC_ACCEPT_UNENCRYPTED_SQLITE = "false"), {
    expect_identical(resolve_accept_unencrypted_sqlite(top)$source, "environment",
                     info = "the environment variable outranks config.yml")
    expect_false(resolve_accept_unencrypted_sqlite(top)$accept,
                 info = "the environment variable's value is used")
  })
  options(zzedc.accept_unencrypted_sqlite = "maybe")
  expect_error(resolve_accept_unencrypted_sqlite(top), "Use true or false",
               info = "an unrecognized value is an error, not FALSE")
  options(zzedc.accept_unencrypted_sqlite = NULL)
  writeLines("security:\n  profile: standard\n  accept_unencrypted_sqlite: true", top)
  Sys.setFileTime(top, Sys.time() + 5)
  expect_identical(resolve_security_profile(top)$profile, "standard",
                   info = "profile and opt-in share one cached section")
  expect_true(resolve_accept_unencrypted_sqlite(top)$accept,
              info = "the opt-in is not shadowed by the cached profile")
  unlink(c(top, nested))
})

# ---------------------------------------------------------------
# 2. F1: standard refuses unhonored SQLite encryption requests
# ---------------------------------------------------------------

if (stock_rsqlite) {
  with_policy("standard", NULL, {
    p <- tempfile(fileext = ".db")
    use_sqlite_adapter(p)
    res <- suppressWarnings(initialize_encrypted_database(db_path = p))
    expect_false(isTRUE(res$success),
                 info = "F1: standard no longer reports success for an unencrypted database")
    expect_true(grepl("DuckDB", res$error %||% "") &&
                  grepl("accept_unencrypted_sqlite", res$error %||% ""),
                info = "F1: the error names DuckDB and the opt-in")
    expect_false(file.exists(p), info = "F1: no plaintext file is left behind")

    plain <- make_plain_sqlite(tempfile(fileext = ".db"))
    expect_error(connect_encrypted(plain, generate_db_key()),
                 "accept_unencrypted_sqlite",
                 info = "F1: connect_encrypted() refuses an existing plaintext file")
    fresh <- tempfile(fileext = ".db")
    expect_error(connect_encrypted(fresh, generate_db_key()),
                 "accept_unencrypted_sqlite",
                 info = "F1: connect_encrypted() refuses a new file it cannot encrypt")
    expect_false(file.exists(fresh), info = "F1: the refused new file is not created")
    use_sqlite_adapter(plain)
    expect_error(connect_encrypted_db(db_path = plain, key = generate_db_key()),
                 "accept_unencrypted_sqlite",
                 info = "F1: connect_encrypted_db() refuses with a key")
    expect_error(with_env(c(DB_ENCRYPTION_KEY = NA), connect_encrypted_db(db_path = plain)),
                 "accept_unencrypted_sqlite",
                 info = "F1: dropping the key does not bypass the rule")
    adapter <- create_db_adapter(list(db_backend = "sqlite", sqlite = list(path = plain)))
    expect_error(adapter$connect(), "accept_unencrypted_sqlite",
                 info = "F1: the SQLite adapter applies the same rule")
    expect_error(suppressMessages(check_storage_encryption(plain, config_profile = "standard")),
                 "accept_unencrypted_sqlite",
                 info = "F1: the startup check refuses plaintext SQLite under standard")
    unlink(plain)
  })

  with_policy("standard", TRUE, {
    p <- tempfile(fileext = ".db")
    use_sqlite_adapter(p)
    expect_message(res <- initialize_encrypted_database(db_path = p),
                   "deployer's responsibility",
                   info = "opt-in: a notice names the deployer's responsibility")
    expect_false(isTRUE(res$success),
                 info = "F1 fix: opt-in creates the file, but success reports it is NOT encrypted")
    expect_identical(res$encrypted, FALSE, info = "opt-in: encrypted = FALSE is reported")
    expect_true(file.exists(res$path), info = "opt-in: the file is still created and usable")
    expect_true(!is.null(res$key), info = "opt-in: a usable key is still returned")
    expect_silent(con <- connect_encrypted(p, res$key))
    DBI::dbDisconnect(con)
    unlink(p)
  })

  with_policy("standard", NULL, with_env(c(ZZEDC_ACCEPT_UNENCRYPTED_SQLITE = "true"), {
    plain <- make_plain_sqlite(tempfile(fileext = ".db"))
    con <- suppressMessages(connect_encrypted(plain, generate_db_key()))
    expect_true(DBI::dbIsValid(con), info = "opt-in by environment variable")
    DBI::dbDisconnect(con)
    unlink(plain)
  }))

  with_policy(NULL, NULL, {
    old_env <- Sys.getenv("ZZEDC_SECURITY_PROFILE", unset = NA)
    Sys.unsetenv("ZZEDC_SECURITY_PROFILE")
    on.exit(if (!is.na(old_env)) Sys.setenv(ZZEDC_SECURITY_PROFILE = old_env), add = TRUE)
    plain <- make_plain_sqlite(tempfile(fileext = ".db"))
    st <- suppressMessages(check_storage_encryption(
      plain, config_profile = "standard", config_accept_unencrypted_sqlite = TRUE))
    expect_true(st$accept_unencrypted_sqlite,
                info = "opt-in from the application configuration is honored")
    expect_identical(getOption("zzedc.accept_unencrypted_sqlite"), TRUE,
                     info = "the opt-in is fixed for the session, like the profile")
    unlink(plain)
  })

  with_policy("development", NULL, {
    p <- tempfile(fileext = ".db")
    use_sqlite_adapter(p)
    res <- initialize_encrypted_database(db_path = p)
    expect_false(isTRUE(res$success),
                 info = "F1 fix: development allows plaintext SQLite, but success mirrors encrypted")
    expect_identical(res$encrypted, FALSE, info = "development: true state reported")
    expect_true(file.exists(res$path), info = "development: file still created and usable")
    unlink(p)
  })

  with_policy("regulated", TRUE, {
    p <- tempfile(fileext = ".db")
    use_sqlite_adapter(p)
    res <- initialize_encrypted_database(db_path = p)
    expect_false(isTRUE(res$success),
                 info = "regulated refuses plaintext SQLite even with the opt-in")
  })
}

# ---------------------------------------------------------------
# 3. DuckDB is the default backend for new studies
# ---------------------------------------------------------------

expect_error(.require_backend_package("zzedcNoSuchPackage"),
             "install.packages\\('zzedcNoSuchPackage'\\)",
             info = "a missing backend package fails with an install hint")
expect_error(.require_backend_package("zzedcNoSuchPackage"),
             "does not fall back to SQLite",
             info = "the failure says there is no SQLite fallback")

expect_identical(wizard_adapter_config(list(), tempdir())$db_backend, "duckdb",
                 info = "wizard_adapter_config(): duckdb when no backend is named")
expect_identical(
  wizard_adapter_config(list(db_backend = "sqlite"), tempdir())$db_backend, "sqlite",
  info = "an explicit backend is unaffected")

if (has_duckdb) {
  f <- tempfile(fileext = ".yml")
  create_default_config(f)
  y <- yaml::read_yaml(f)
  expect_identical(y$default$database$backend, "duckdb",
                   info = "create_default_config(): duckdb by default")
  expect_identical(y$default$database$encryption_key, "${DB_ENCRYPTION_KEY}",
                   info = "create_default_config(): encryption key configured")
  expect_identical(y$default$security$accept_unencrypted_sqlite, FALSE,
                   info = "create_default_config(): the opt-in is written, off")
  unlink(f)

  f <- tempfile(fileext = ".yml")
  suppressMessages(generate_sample_config(output_path = f))
  expect_identical(yaml::read_yaml(f)$database$backend, "duckdb",
                   info = "generate_sample_config(): duckdb by default")
  unlink(f)

  f <- tempfile(fileext = ".yml")
  res <- create_wizard_config(list(study_name = "S", protocol_id = "P"), f, "salt")
  expect_identical(yaml::read_yaml(f)$default$database$backend, "duckdb",
                   info = "create_wizard_config(): duckdb by default")
  unlink(f)

  k <- generate_db_key()
  cfg <- default_db_config(encryption_key = k)
  expect_identical(cfg$db_backend, "duckdb", info = "default_db_config(): duckdb by default")
  expect_identical(cfg$duckdb$encryption_key, k, info = "default_db_config(): keyed")
  with_env(c(DB_ENCRYPTION_KEY = NA), {
    expect_error(default_db_config(), "needs a key",
                 info = "default_db_config(): no unencrypted default")
  })
  expect_identical(default_db_config("sqlite")$db_backend, "sqlite",
                   info = "default_db_config(): an explicit backend is unaffected")
}

if (duck_ok) {
  with_policy("development", NULL, with_env(c(DB_ENCRYPTION_KEY = NA), {
    base <- tempfile("wiz_default_")
    cl <- list(study_name = "Default Study", protocol_id = "DEF-1",
               admin_username = "admin1", admin_password = "Str0ng!pass",
               admin_fullname = "Admin", admin_email = "a@example.org",
               security_salt = "0123456789abcdef", install_extensions = FALSE)
    res <- suppressWarnings(suppressMessages(complete_wizard_setup(cl, base_path = base)))
    expect_true(isTRUE(res$overall_success),
                info = "complete_wizard_setup(): succeeds with no backend named")
    db <- file.path(base, "data", "zzedc.duckdb")
    expect_identical(.detect_db_file_format(db), "duckdb",
                     info = "complete_wizard_setup(): the study is on DuckDB")
    expect_true(isTRUE(res$database_encrypted),
                info = "complete_wizard_setup(): the study database is encrypted")
    expect_true(grepl("^[0-9a-f]{64}$", res$encryption_key %||% ""),
                info = "complete_wizard_setup(): a generated key is returned")
    unlink(base, recursive = TRUE)
  }))

  with_env(c(DB_ENCRYPTION_KEY = generate_db_key()), {
    cl <- list(study_name = "S", protocol_id = "P", admin_username = "a",
               admin_password = "Str0ng!pass", security_salt = "s")
    p <- tempfile(fileext = ".duckdb")
    res <- suppressWarnings(initialize_default_database(p))
    expect_true(isTRUE(res$success),
                info = "initialize_default_database(): DuckDB with DB_ENCRYPTION_KEY")
    expect_identical(.detect_db_file_format(p), "duckdb",
                     info = "initialize_default_database(): DuckDB by default")
    unlink(p)
  })
  with_env(c(DB_ENCRYPTION_KEY = NA), {
    res <- create_wizard_database(list(study_name = "S", protocol_id = "P",
                                       admin_username = "a", admin_password = "x",
                                       security_salt = "s"),
                                  db_path = tempfile(fileext = ".duckdb"))
    expect_false(isTRUE(res$success),
                 info = "create_wizard_database(): no key, no unencrypted default")
  })
}

adhd_dir <- system.file("extdata", "adhd_trial", package = "zzedc")
if (!nzchar(adhd_dir)) {
  adhd_dir <- normalizePath("../../inst/extdata/adhd_trial", mustWork = FALSE)
}
if (duck_ok && dir.exists(adhd_dir)) {
  with_policy("development", NULL, with_env(c(DB_ENCRYPTION_KEY = NA, ZZEDC_DB_PATH = NA), {
    db <- file.path(tempfile("csv_default_"), "study.duckdb")
    dir.create(dirname(db))
    res <- suppressWarnings(suppressMessages(
      setup_zzedc_from_csv(adhd_dir, db_path = db, salt = "s")))
    expect_true(isTRUE(res$success), info = "setup_zzedc_from_csv(): DuckDB default works")
    expect_identical(.detect_db_file_format(db), "duckdb",
                     info = "setup_zzedc_from_csv(): a new study is created on DuckDB")
    expect_true(grepl("^[0-9a-f]{64}$", res$key %||% ""),
                info = "setup_zzedc_from_csv(): the generated key is returned")
    expect_true(isTRUE(res$database$encrypted),
                info = "setup_zzedc_from_csv(): the new database is reported encrypted")
    bytes <- readBin(db, "raw", n = file.size(db))
    expect_equal(length(grepRaw(charToRaw("backup_admin"), bytes, fixed = TRUE)), 0,
                 info = "setup_zzedc_from_csv(): an imported username is not stored in plaintext")
    unlink(dirname(db), recursive = TRUE)
  }))
}
if (stock_rsqlite && dir.exists(adhd_dir)) {
  with_policy("standard", NULL, with_env(c(ZZEDC_DB_PATH = NA), {
    db <- tempfile(fileext = ".db")
    res <- suppressWarnings(suppressMessages(
      setup_zzedc_from_csv(adhd_dir, db_path = db, salt = "s", backend = "sqlite")))
    expect_false(isTRUE(res$success),
                 info = "setup_zzedc_from_csv(backend = 'sqlite'): refused under standard without the opt-in")
    unlink(db)
  }))
}

# ---------------------------------------------------------------
# 4. F-NEW8: the Google Sheets form loader uses the adapter path
# ---------------------------------------------------------------

loader <- system.file("app", "gsheets_form_loader.R", package = "zzedc")
if (!nzchar(loader)) {
  loader <- normalizePath("../../inst/app/gsheets_form_loader.R", mustWork = FALSE)
}
if (file.exists(loader)) {
  # Parent baseenv(): no 'cfg' or 'db_pool' from this file or another
  # test is visible to the loader unless assigned into env.
  env <- new.env(parent = baseenv())
  suppressMessages(sys.source(loader, envir = env))
  forms_dir <- tempfile("forms_generated_")
  dir.create(forms_dir)

  if (stock_rsqlite) {
    with_policy("standard", NULL, {
      plain <- make_plain_sqlite(tempfile(fileext = ".db"))
      expect_error(suppressMessages(env$load_gsheets_forms(forms_dir, db_path = plain)),
                   "accept_unencrypted_sqlite",
                   info = "F-NEW8: the loader obeys the standard-profile SQLite rule")
      unlink(plain)
    })
    with_policy("standard", TRUE, {
      plain <- make_plain_sqlite(tempfile(fileext = ".db"))
      out <- suppressWarnings(suppressMessages(
        env$load_gsheets_forms(forms_dir, db_path = plain)))
      expect_equal(nrow(out$forms_overview), 1L,
                   info = "F-NEW8: with the opt-in the loader reads the forms")
      unlink(plain)
    })
  }

  with_policy("development", NULL, {
    work <- tempfile("loader_nocfg_")
    dir.create(work)
    old_wd <- setwd(work)
    expect_error(suppressMessages(env$load_gsheets_forms(forms_dir)),
                 "No database configured",
                 info = "F-NEW8: no configuration is an error, not a guessed SQLite path")
    expect_false(file.exists(file.path(work, "data", "zzedc_gsheets.db")),
                 info = "F-NEW8: no database file is created")
    setwd(old_wd)
    unlink(work, recursive = TRUE)
  })

  if (duck_ok) {
    # 'standard', not 'regulated': regulated also requires pre-installed
    # DuckDB extensions, which this test does not set up.
    with_policy("standard", NULL, {
      k <- generate_db_key()
      dbfile <- tempfile(fileext = ".duckdb")
      a <- create_db_adapter(list(db_backend = "duckdb",
                                  duckdb = list(path = dbfile, encryption_key = k)))
      con <- a$connect()
      DBI::dbExecute(con, "CREATE TABLE edc_forms (workingname TEXT, fullname TEXT)")
      DBI::dbExecute(con, "INSERT INTO edc_forms VALUES ('demo', 'Demo form')")
      a$disconnect(con)
      a$shutdown()
      assign("cfg", list(database = list(backend = "duckdb", path = dbfile,
                                         encryption_key = "${DB_ENCRYPTION_KEY}")),
             envir = env)
      out <- with_env(c(DB_ENCRYPTION_KEY = k), suppressWarnings(suppressMessages(
        env$load_gsheets_forms(forms_dir))))
      expect_equal(nrow(out$forms_overview), 1L,
                   info = "F-NEW8: a DuckDB study is read through its adapter and key")
      out2 <- with_env(c(DB_ENCRYPTION_KEY = k), suppressWarnings(suppressMessages(
        env$load_gsheets_forms(forms_dir, db_path = dbfile))))
      expect_equal(nrow(out2$forms_overview), 1L,
                   info = "F-NEW8: an explicit DuckDB db_path is opened as DuckDB")
      rm("cfg", envir = env)
      unlink(dbfile)
    })
  }
  unlink(forms_dir, recursive = TRUE)
}
