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

# Whether this adapter still holds its instance open.
holds_instance <- function(adapter) {
  anchor <- adapter$.__enclos_env__$private$anchor
  !is.null(anchor) && isTRUE(DBI::dbIsValid(anchor))
}

# get_db_adapter(force_new = TRUE) shuts down the cached adapter it
# replaces when both are on the same DuckDB file, and only then.
local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
  had <- exists("adapter", envir = cache)
  previous <- if (had) cache$adapter else NULL
  on.exit({
    if (had) assign("adapter", previous, envir = cache)
    else if (exists("adapter", envir = cache)) rm("adapter", envir = cache)
  }, add = TRUE)

  dir <- tempfile("forcenew_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE, after = FALSE)
  cfg <- function(file, threads = NULL) {
    list(db_backend = "duckdb",
         duckdb = list(path = file.path(dir, file), threads = threads))
  }

  a1 <- get_db_adapter(config = cfg("one.duckdb"), force_new = TRUE)
  con <- a1$connect()
  DBI::dbExecute(con, "CREATE TABLE t (v INTEGER)")
  a1$disconnect(con)
  expect_true(holds_instance(a1), info = "a used adapter holds its instance")

  a2 <- get_db_adapter(config = cfg("one.duckdb", threads = 1), force_new = TRUE)
  expect_false(holds_instance(a1),
               info = "force_new shuts down the replaced adapter on the same file")
  con <- a2$connect()
  expect_true("t" %in% DBI::dbListTables(con), info = "the new adapter opens the file")
  a2$disconnect(con)

  a3 <- get_db_adapter(config = cfg("two.duckdb"), force_new = TRUE)
  expect_true(holds_instance(a2),
              info = "an adapter on another file is not shut down (it may serve a pool)")
  a2$shutdown()
  a3$shutdown()
})

# A short-lived adapter releases the file when the function returns.
# Opening it read-only in this process fails while a read-write
# instance of it is still open (duckdb >= 2.0.0 refuses the differing
# setting instead of ignoring it).
if (requireNamespace("duckdb", quietly = TRUE) &&
    utils::packageVersion("duckdb") >= "2.0.0") local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  dir <- tempfile("export_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  cfg <- list(db_backend = "duckdb", duckdb = list(path = file.path(dir, "study.duckdb")))
  setup <- create_db_adapter(cfg)
  con <- setup$connect()
  DBI::dbExecute(con, "CREATE TABLE t AS SELECT 1 AS v")
  setup$disconnect(con)
  setup$shutdown()

  res <- export_to_files(cfg, file.path(dir, "out"), compress = FALSE)
  expect_true(res$success)
  opened <- tryCatch({
    ro <- DBI::dbConnect(duckdb::duckdb(dbdir = cfg$duckdb$path, read_only = TRUE))
    DBI::dbDisconnect(ro, shutdown = TRUE)
    TRUE
  }, error = function(e) conditionMessage(e))
  expect_true(isTRUE(opened),
              info = paste("export_to_files() released the database file:", opened))
})
