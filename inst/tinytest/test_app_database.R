library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# The Shiny application now builds its database pool from the
# configured adapter (inst/app/global.R) instead of always opening
# SQLite with RSQLite. These tests cover the configuration mapping, the
# startup storage check for each backend, and first-time
# initialization through the launcher's functions.

check_database_initialized <- get("check_database_initialized", envir = asNamespace("zzedc"))
reset_encryption_warnings <- get("reset_encryption_warnings", envir = asNamespace("zzedc"))

with_profile <- function(profile, code) {
  old <- options(zzedc.security_profile = profile)
  on.exit(options(old), add = TRUE)
  reset_encryption_warnings()
  force(code)
}

# ---------------------------------------------------------------
# app_database_config(): config.yml database section -> adapter config
# ---------------------------------------------------------------

local({
  wd <- tempfile("wd_")

  cfg <- app_database_config(list(database = list(path = "data/s.db", pool_size = 7)), wd)
  expect_identical(cfg$db_backend, "sqlite", info = "SQLite is the default backend")
  expect_identical(cfg$sqlite$path, file.path(wd, "data/s.db"),
                   info = "relative paths resolve against the launch directory")
  expect_identical(cfg$sqlite$pool_max, 7)

  cfg <- app_database_config(list(database = list(type = "duckdb", path = "/abs/s.duckdb")), wd)
  expect_identical(cfg$db_backend, "duckdb", info = "the setup wizard's `type` key is honored")
  expect_identical(cfg$duckdb$path, "/abs/s.duckdb", info = "absolute paths unchanged")

  old <- Sys.getenv("ZZEDC_TEST_APPKEY", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("ZZEDC_TEST_APPKEY")
          else Sys.setenv(ZZEDC_TEST_APPKEY = old), add = TRUE)
  Sys.setenv(ZZEDC_TEST_APPKEY = "abc")
  cfg <- app_database_config(list(database = list(
    backend = "duckdb", path = "d.duckdb", encryption_key = "${ZZEDC_TEST_APPKEY}",
    extension_directory = "ext", allow_extension_download = FALSE
  )), wd)
  expect_identical(cfg$duckdb$encryption_key, "abc", info = "${VAR} substituted")
  expect_identical(cfg$duckdb$extension_directory, file.path(wd, "ext"))
  expect_false(cfg$duckdb$allow_extension_download)

  Sys.unsetenv("ZZEDC_TEST_APPKEY")
  cfg <- app_database_config(list(database = list(
    backend = "duckdb", path = "d.duckdb", encryption_key = "${ZZEDC_TEST_APPKEY}"
  )), wd)
  expect_true(is.null(cfg$duckdb$encryption_key),
              info = "an unset variable leaves no key, rather than an empty string")

  cfg <- app_database_config(list(database = list(
    backend = "mariadb", host = "h", name = "n", user = "u", ssl_mode = "VERIFY_IDENTITY"
  )), wd)
  expect_identical(cfg$db_backend, "mysql", info = "mariadb maps to the mysql adapter")
  expect_identical(cfg$mysql$ssl_mode, "VERIFY_IDENTITY")
  expect_true(is.na(app_database_path(cfg)), info = "server backends have no file path")

  expect_error(app_database_config(list(database = list(backend = "oracle")), wd),
               "Unsupported database backend")
})

# ---------------------------------------------------------------
# check_storage_encryption(adapter = ): startup check per backend
# ---------------------------------------------------------------

if (!sqlite_cipher_available()) {
  with_profile("regulated", {
    adapter <- create_db_adapter(list(db_backend = "sqlite",
                                      sqlite = list(path = tempfile(fileext = ".db"))))
    expect_error(suppressMessages(check_storage_encryption(adapter = adapter)),
                 "NOT encrypted", info = "new keyless SQLite refused before creation")
  })
}

# Fake server adapter (no live server here): connects, reports TLS.
fake_pg <- function(section = list(sslmode = "verify-full"), tls = TRUE) {
  list(backend_name = function() "postgresql",
       config = list(postgresql = section),
       connect = function() "conn", disconnect = function(conn) invisible(TRUE),
       is_ssl_connected = function(conn) tls)
}
with_profile("regulated", {
  pg <- fake_pg()
  expect_error(suppressMessages(check_storage_encryption(adapter = pg)),
               "cannot be checked", info = "server at-rest encryption unknown, no attestation: refused under regulated")
})
with_profile("standard", {
  pg <- fake_pg()
  res <- suppressWarnings(suppressMessages(check_storage_encryption(adapter = pg)))
  expect_true(is.na(res$encrypted), info = "standard: reported as not verifiable, not as encrypted")
})

duck_ok <- requireNamespace("duckdb", quietly = TRUE) && tryCatch({
  ext_dir <- tempfile("ext_")
  all(install_duckdb_extensions(ext_dir)$loads_offline)
}, error = function(e) FALSE)

if (duck_ok) {
  with_profile("regulated", {
    wd <- tempfile("wd_")
    dir.create(file.path(wd, "data"), recursive = TRUE)
    key <- generate_db_key()
    db_config <- app_database_config(list(database = list(
      backend = "duckdb", path = "data/study.duckdb", encryption_key = key,
      extension_directory = ext_dir
    )), wd)
    adapter <- create_db_adapter(db_config)

    res <- suppressMessages(check_storage_encryption(adapter = adapter))
    expect_true(res$encrypted, info = "new DuckDB with a key passes: it will be created encrypted")

    # Launcher path: detect, initialize, migrate, all on encrypted DuckDB.
    expect_false(check_database_initialized(app_database_path(db_config),
                                            adapter_config = db_config))
    init <- initialize_default_database(app_database_path(db_config),
                                        adapter_config = db_config)
    expect_true(init$success, info = paste("encrypted DuckDB initialized:", init$message))
    expect_true(check_database_initialized(app_database_path(db_config),
                                           adapter_config = db_config),
                info = "initialized database detected through the adapter")

    v <- verify_database_encryption(app_database_path(db_config), key = key,
                                    adapter = adapter)
    expect_true(v$encrypted, info = "the study database the launcher created is encrypted")

    res <- suppressMessages(check_storage_encryption(adapter = adapter))
    expect_true(res$encrypted, info = "existing encrypted DuckDB passes the startup check")

    # The application's pool: login-style query against the admin row.
    p <- adapter$pool()
    users <- pool::dbGetQuery(p, "SELECT username, role FROM edc_users WHERE username = ?",
                              params = list("admin"))
    expect_identical(users$role, "Admin", info = "app pool reads the encrypted study database")
    pool::poolClose(p)
  })
}
