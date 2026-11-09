library(tinytest)

if (file.exists("_setup.R")) source("_setup.R")

# Regression tests for the PostgreSQL `?`-placeholder shim
# (install_pg_placeholder_shim()/translate_pg_placeholders()) and the
# MySQL/MariaDB RETURNING shim
# (install_mysql_returning_shim()/strip_mysql_returning()), both
# fixed 2026-11-08. See docs/db-adapter-remediation-plan-2026-11-07.md.
#
# Root causes, confirmed by minimal repros outside this package's own
# code before any fix was written:
# - RPostgres does not translate `?` placeholders to its native
#   `$1, $2, ...` syntax; every one of this package's ~40 legacy
#   files was written using `?` only, assuming (incorrectly) that it
#   worked everywhere.
# - RETURNING is valid syntax on MariaDB 10.5+ but RMariaDB's
#   dbGetQuery() runs it without error and returns a 0-column result
#   -- the generated id is silently lost, not an error -- and
#   RETURNING is not valid syntax on MySQL proper at all.
#
# The pure string-transform/parse halves of both fixes need no live
# server and always run. The end-to-end halves need a reachable
# PostgreSQL/MariaDB server and are skipped otherwise, the same way
# test_db-adapter.R's own `with_backend("postgresql", ...)` test is
# gated on ZZEDC_TEST_PG_HOST/ZZEDC_TEST_PG_DB.

# ============================================================================
# translate_pg_placeholders() -- pure string transform, no server needed
# ============================================================================

local({
  expect_equal(
    zzedc:::translate_pg_placeholders("SELECT * FROM t WHERE a = ? AND b = ?"),
    "SELECT * FROM t WHERE a = $1 AND b = $2"
  )
  expect_equal(
    zzedc:::translate_pg_placeholders("INSERT INTO t (a,b) VALUES (?, ?)"),
    "INSERT INTO t (a,b) VALUES ($1, $2)"
  )
  expect_equal(
    zzedc:::translate_pg_placeholders("SELECT * FROM t WHERE x IN (?,?,?)"),
    "SELECT * FROM t WHERE x IN ($1,$2,$3)",
    info = "a dynamically built IN-clause placeholder list numbers sequentially"
  )
  expect_equal(
    zzedc:::translate_pg_placeholders("no placeholders here"),
    "no placeholders here"
  )
  expect_equal(
    zzedc:::translate_pg_placeholders("SELECT * FROM t WHERE note = 'what?' AND a = ?"),
    "SELECT * FROM t WHERE note = 'what?' AND a = $1",
    info = "a literal ? inside a single-quoted string is not translated"
  )
  expect_equal(
    zzedc:::translate_pg_placeholders("SELECT * FROM t WHERE note = 'it''s a ? test' AND a = ?"),
    "SELECT * FROM t WHERE note = 'it''s a ? test' AND a = $1",
    info = "a doubled '' escaped quote does not end the string early"
  )
})

# ============================================================================
# strip_mysql_returning() -- pure string parse, no server needed
# ============================================================================

local({
  parsed <- zzedc:::strip_mysql_returning("
    INSERT INTO t (a, b) VALUES (?, ?)
    RETURNING audit_id AS id
  ")
  expect_true(parsed$has_returning)
  expect_equal(parsed$alias, "id")
  expect_false(grepl("RETURNING", parsed$statement, ignore.case = TRUE))

  not_returning <- zzedc:::strip_mysql_returning("SELECT * FROM t WHERE a = ?")
  expect_false(not_returning$has_returning)
  expect_equal(not_returning$statement, "SELECT * FROM t WHERE a = ?")
  expect_null(not_returning$alias)
})

# ============================================================================
# End-to-end: live PostgreSQL (skipped unless configured/reachable)
# ============================================================================

pg_configured <- Sys.getenv("ZZEDC_TEST_PG_HOST", "") != "" ||
                 Sys.getenv("ZZEDC_TEST_PG_DB", "") != ""

if (pg_configured && requireNamespace("RPostgres", quietly = TRUE)) {
  pg_conn_ok <- tryCatch({
    test_conn <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("ZZEDC_TEST_PG_HOST", "localhost"),
      port = as.integer(Sys.getenv("ZZEDC_TEST_PG_PORT", "5432")),
      dbname = Sys.getenv("ZZEDC_TEST_PG_DB", "zzedc_test"),
      user = Sys.getenv("ZZEDC_TEST_PG_USER", "postgres"),
      password = Sys.getenv("ZZEDC_TEST_PG_PASSWORD", "")
    )
    DBI::dbDisconnect(test_conn)
    TRUE
  }, error = function(e) FALSE)

  if (pg_conn_ok) {
    message("[POSTGRESQL] ? placeholders work through dbExecute()/dbGetQuery() after the shim")
    get_db_adapter(config = list(
      db_backend = "postgresql",
      postgresql = list(
        host = Sys.getenv("ZZEDC_TEST_PG_HOST", "localhost"),
        port = as.integer(Sys.getenv("ZZEDC_TEST_PG_PORT", "5432")),
        name = Sys.getenv("ZZEDC_TEST_PG_DB", "zzedc_test"),
        user = Sys.getenv("ZZEDC_TEST_PG_USER", "postgres"),
        password = Sys.getenv("ZZEDC_TEST_PG_PASSWORD", "")
      )
    ), force_new = TRUE)

    conn <- connect_encrypted_db()
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS shim_test")
    DBI::dbExecute(conn, "CREATE TABLE shim_test (a TEXT, b TEXT)")
    DBI::dbExecute(conn, "INSERT INTO shim_test (a, b) VALUES (?, ?)",
                   params = list("x", "y"))
    result <- DBI::dbGetQuery(conn, "SELECT * FROM shim_test WHERE a = ?",
                               params = list("x"))
    expect_equal(nrow(result), 1)
    expect_equal(result$b[1], "y")
    DBI::dbExecute(conn, "DROP TABLE shim_test")
    DBI::dbDisconnect(conn)
  }
}

# ============================================================================
# End-to-end: live MariaDB/MySQL (skipped unless configured/reachable)
# ============================================================================

mysql_configured <- Sys.getenv("ZZEDC_TEST_MYSQL_HOST", "") != "" ||
                     Sys.getenv("ZZEDC_TEST_MYSQL_DB", "") != ""

if (mysql_configured && requireNamespace("RMariaDB", quietly = TRUE)) {
  mysql_conn_ok <- tryCatch({
    test_conn <- DBI::dbConnect(
      RMariaDB::MariaDB(),
      host = Sys.getenv("ZZEDC_TEST_MYSQL_HOST", "127.0.0.1"),
      port = as.integer(Sys.getenv("ZZEDC_TEST_MYSQL_PORT", "3306")),
      dbname = Sys.getenv("ZZEDC_TEST_MYSQL_DB", "zzedc_test"),
      user = Sys.getenv("ZZEDC_TEST_MYSQL_USER", "root"),
      password = Sys.getenv("ZZEDC_TEST_MYSQL_PASSWORD", "")
    )
    DBI::dbDisconnect(test_conn)
    TRUE
  }, error = function(e) FALSE)

  if (mysql_conn_ok) {
    message("[MYSQL] RETURNING ... AS id comes back as a plain integer after the shim")
    get_db_adapter(config = list(
      db_backend = "mysql",
      mysql = list(
        host = Sys.getenv("ZZEDC_TEST_MYSQL_HOST", "127.0.0.1"),
        port = as.integer(Sys.getenv("ZZEDC_TEST_MYSQL_PORT", "3306")),
        name = Sys.getenv("ZZEDC_TEST_MYSQL_DB", "zzedc_test"),
        user = Sys.getenv("ZZEDC_TEST_MYSQL_USER", "root"),
        password = Sys.getenv("ZZEDC_TEST_MYSQL_PASSWORD", "")
      )
    ), force_new = TRUE)

    conn <- connect_encrypted_db()
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS shim_test")
    DBI::dbExecute(conn, "CREATE TABLE shim_test (id INT AUTO_INCREMENT PRIMARY KEY, a TEXT)")
    result <- DBI::dbGetQuery(conn, "
      INSERT INTO shim_test (a) VALUES (?)
      RETURNING id AS id
    ", params = list("x"))
    expect_equal(nrow(result), 1)
    expect_true(!is.na(result$id[1]))
    expect_identical(class(result$id), "integer",
                      info = "LAST_INSERT_ID() is cast from integer64 to a plain integer")

    normal <- DBI::dbGetQuery(conn, "SELECT * FROM shim_test WHERE a = ?", params = list("x"))
    expect_equal(nrow(normal), 1, info = "a non-RETURNING query still passes through normally")

    DBI::dbExecute(conn, "DROP TABLE shim_test")
    DBI::dbDisconnect(conn)
  }
}

# Reset the adapter cache so later test files resolve a plain sqlite
# backend again rather than whichever backend this file last used.
get_db_adapter(
  config = list(db_backend = "sqlite", sqlite = list(path = tempfile(fileext = ".db"))),
  force_new = TRUE
)
