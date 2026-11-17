library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# A DuckDB adapter keeps one instance from first use until shutdown().
# The duckdb package releases an instance when its last connection
# closes; before 2026-11-17 the adapter did not notice, so after a
# connect()/disconnect() cycle each later connection got its own
# instance, and two of them attached an encrypted study file at once
# and corrupted it (CI abort, duckdb 1.5.4.1: "MarkBlockAsModified
# called with already modified block id"). An in-memory database shows
# the same thing without a file: its contents live only as long as the
# instance.

if (!requireNamespace("duckdb", quietly = TRUE)) exit_file("duckdb not installed")

local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  a <- create_db_adapter(list(db_backend = "duckdb", duckdb = list(path = ":memory:")))
  on.exit(a$shutdown(), add = TRUE)

  c1 <- a$connect()
  DBI::dbExecute(c1, "CREATE TABLE marker (v INTEGER)")
  a$disconnect(c1)
  invisible(gc())

  c2 <- a$connect()
  c3 <- a$connect()
  expect_true("marker" %in% DBI::dbListTables(c2),
              info = "a connection after every other one closed reaches the same instance")
  DBI::dbExecute(c2, "CREATE TABLE second (v INTEGER)")
  expect_true("second" %in% DBI::dbListTables(c3),
              info = "two open connections share one instance")
  a$disconnect(c2)
  a$disconnect(c3)

  a$shutdown()
  c4 <- a$connect()
  expect_false("marker" %in% DBI::dbListTables(c4),
               info = "shutdown() releases the instance; the next connect() opens a new one")
  a$disconnect(c4)
})
