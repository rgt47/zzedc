library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Phase 1.2 of docs/encryption-compliance-plan-2026-11-10.md: DuckDB
# extensions from a persistent directory, no runtime downloads under
# the regulated profile, and missing extensions reported at connection
# time. Also the encrypted-pool concurrency fix found while preparing
# Phase 1.2.

if (!requireNamespace("duckdb", quietly = TRUE)) exit_file("duckdb not installed")
if (!requireNamespace("pool", quietly = TRUE)) exit_file("pool not installed")

with_profile <- function(profile, code) {
  old <- options(zzedc.security_profile = profile)
  on.exit(options(old), add = TRUE)
  force(code)
}

network_ok <- tryCatch({
  probe_dir <- tempfile("ext_probe_")
  res <- install_duckdb_extensions(probe_dir)
  all(res$loads_offline)
}, error = function(e) FALSE)

# ---------------------------------------------------------------
# Download policy
# ---------------------------------------------------------------

with_profile("regulated", {
  expect_false(duckdb_extension_download_allowed(list()),
               info = "regulated disallows runtime downloads by default")
  expect_true(duckdb_extension_download_allowed(list(allow_extension_download = TRUE)),
              info = "an explicit setting wins")
})
with_profile("standard", {
  expect_true(duckdb_extension_download_allowed(list()))
  expect_false(duckdb_extension_download_allowed(list(allow_extension_download = FALSE)))
})

# ---------------------------------------------------------------
# Missing extension fails at connection time, with instructions
# ---------------------------------------------------------------

with_profile("regulated", {
  empty_dir <- tempfile("ext_empty_")
  dir.create(empty_dir)
  adapter <- create_db_adapter(list(
    db_backend = "duckdb",
    duckdb = list(path = tempfile(fileext = ".duckdb"),
                  encryption_key = generate_db_key(),
                  extension_directory = empty_dir)
  ))
  expect_error(adapter$connect(), "install_duckdb_extensions",
               info = "missing httpfs is an error at connect, naming the remedy")
})

if (network_ok) {
  # ---------------------------------------------------------------
  # Pre-installed extensions: works offline under regulated
  # ---------------------------------------------------------------
  ext_dir <- tempfile("ext_")
  installed <- install_duckdb_extensions(ext_dir)
  expect_true(all(installed$loads_offline),
              info = "install_duckdb_extensions verifies an offline load")
  expect_identical(installed$extension, c("httpfs", "icu"))

  with_profile("regulated", {
    path <- tempfile(fileext = ".duckdb")
    key <- generate_db_key()
    adapter <- create_db_adapter(list(
      db_backend = "duckdb",
      duckdb = list(path = path, encryption_key = key, extension_directory = ext_dir)
    ))
    con <- adapter$connect()
    expect_true(DBI::dbIsValid(con), info = "regulated + pre-installed extensions connects")
    d <- DBI::dbGetQuery(con, "SELECT CURRENT_DATE AS d")$d
    expect_equal(as.Date(d), Sys.Date(), info = "CURRENT_DATE works without downloads")
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(path)
  })

  # ---------------------------------------------------------------
  # Encrypted pool: second concurrent connection (was impossible)
  # ---------------------------------------------------------------
  with_profile("development", {
    path <- tempfile(fileext = ".duckdb")
    key <- generate_db_key()
    adapter <- create_db_adapter(list(
      db_backend = "duckdb",
      duckdb = list(path = path, encryption_key = key, extension_directory = ext_dir)
    ))
    p <- adapter$pool()
    pool::dbExecute(p, "CREATE TABLE t (id INTEGER)")
    c1 <- pool::poolCheckout(p)
    c2 <- tryCatch(pool::poolCheckout(p), error = function(e) e)
    expect_false(inherits(c2, "error"),
                 info = "second concurrent connection to an encrypted pool succeeds")
    if (!inherits(c2, "error")) {
      DBI::dbExecute(c1, "INSERT INTO t VALUES (1)")
      expect_equal(DBI::dbGetQuery(c2, "SELECT count(*) AS n FROM t")$n, 1,
                   info = "connections share the attached encrypted database")
      pool::poolReturn(c2)
    }
    pool::poolReturn(c1)
    pool::poolClose(p)
    expect_true(verify_database_encryption(path, key = key)$encrypted,
                info = "file written through the pool is encrypted")
    unlink(path)
  })
}
