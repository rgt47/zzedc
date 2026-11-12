library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Phases 1.3 and 1.4: PostgreSQL and MySQL/MariaDB under the security
# profiles. No database server is available to the test suite, so the
# server is replaced by a fake adapter whose connect(), InnoDB rows, and
# TLS status are set by each test. These tests therefore cover zzedc's
# decision logic, not the SQL sent to a real server.

ns <- asNamespace("zzedc")
mysql_rows <- get(".mysql_encryption_from_rows", envir = ns)
tls_ok <- get(".tls_mode_verified", envir = ns)
server_state <- get(".server_storage_state", envir = ns)
reset_encryption_warnings <- get("reset_encryption_warnings", envir = ns)

with_profile <- function(profile, code) {
  old <- options(zzedc.security_profile = profile)
  on.exit(options(old), add = TRUE)
  reset_encryption_warnings()
  force(code)
}

fake_adapter <- function(backend, section, tls = TRUE, tablespaces = NULL) {
  list(
    backend_name = function() backend,
    config = setNames(list(section), backend),
    connect = function() structure(list(rows = tablespaces), class = "fake_conn"),
    disconnect = function(conn) invisible(TRUE),
    is_ssl_connected = function(conn) tls
  )
}

# The MySQL tablespace query is replaced for the fake connection.
real_query <- get(".mysql_tablespace_encryption", envir = ns)
unlockBinding(".mysql_tablespace_encryption", ns)
assign(".mysql_tablespace_encryption", function(conn, dbname) {
  if (inherits(conn, "fake_conn")) conn$rows else real_query(conn, dbname)
}, envir = ns)
on.exit_restore <- function() {
  assign(".mysql_tablespace_encryption", real_query, envir = ns)
  lockBinding(".mysql_tablespace_encryption", ns)
}

# ---------------------------------------------------------------
# Pure decision helpers
# ---------------------------------------------------------------

expect_true(is.na(mysql_rows(NULL)), info = "no rows (query failed): unknown")
expect_true(is.na(mysql_rows(data.frame(name = character(), encrypted = logical()))),
            info = "no tablespaces: unknown, not encrypted")
expect_true(mysql_rows(data.frame(name = c("s/a", "s/b"), encrypted = c(TRUE, TRUE))),
            info = "all encrypted")
expect_false(mysql_rows(data.frame(name = c("s/a", "s/b"), encrypted = c(TRUE, FALSE))),
             info = "one unencrypted tablespace: not encrypted")

expect_true(tls_ok("postgresql", list(sslmode = "verify-full")))
expect_true(tls_ok("postgresql", list(sslmode = "verify-ca")))
expect_false(tls_ok("postgresql", list(sslmode = "require")),
             info = "require encrypts but does not verify the server")
expect_false(tls_ok("postgresql", list()), info = "unset sslmode")
expect_true(tls_ok("mysql", list(ssl_mode = "verify_identity")), info = "case-insensitive")
expect_false(tls_ok("mysql", list(ssl_mode = "REQUIRED")))

s <- server_state("postgresql", list(sslmode = "verify-full"))
expect_true(is.na(s$at_rest), info = "PostgreSQL without attestation: unknown")
expect_identical(s$at_rest_basis, "unknown")
expect_true(grepl("at_rest_attestation", s$reason), info = "the reason says how to resolve it")

s <- server_state("postgresql", list(at_rest_attestation = "LUKS volume encryption"))
expect_true(s$at_rest)
expect_identical(s$at_rest_basis, "attested", info = "an attestation is labeled as such")
expect_true(grepl("not verified by zzedc", s$reason))

s <- server_state("mysql", list(at_rest_attestation = "claimed"),
                  tablespaces = data.frame(name = "s/t", encrypted = FALSE))
expect_false(s$at_rest, info = "a measured FALSE overrides an attestation")
expect_identical(s$at_rest_basis, "verified")
expect_true(grepl("s/t", s$reason), info = "names the unencrypted tablespace")

s <- server_state("mysql", list(), tablespaces = data.frame(name = "s/t", encrypted = TRUE))
expect_true(s$at_rest)
expect_identical(s$at_rest_basis, "verified")

s <- server_state("mysql", list(at_rest_attestation = "RDS storage encryption"))
expect_identical(s$at_rest_basis, "attested",
                 info = "MySQL falls back to the attestation when InnoDB cannot be queried")

# ---------------------------------------------------------------
# check_storage_encryption() under each profile
# ---------------------------------------------------------------

pg_good <- list(sslmode = "verify-full", at_rest_attestation = "AWS RDS storage encryption")

with_profile("regulated", {
  res <- suppressMessages(check_storage_encryption(adapter = fake_adapter("postgresql", pg_good)))
  expect_true(res$encrypted, info = "regulated accepts attested PostgreSQL with verified TLS")
  expect_identical(res$basis, "attested")
  expect_true(res$tls)

  expect_error(suppressMessages(check_storage_encryption(
    adapter = fake_adapter("postgresql", modifyList(pg_good, list(sslmode = "require"))))),
    "verify-full", info = "regulated refuses unverified TLS mode")

  expect_error(suppressMessages(check_storage_encryption(
    adapter = fake_adapter("postgresql", pg_good, tls = FALSE))),
    "not using TLS", info = "regulated refuses a live connection without TLS")

  expect_error(suppressMessages(check_storage_encryption(
    adapter = fake_adapter("postgresql", list(sslmode = "verify-full")))),
    "at_rest_attestation", info = "regulated refuses PostgreSQL without attestation")

  my <- fake_adapter("mysql", list(name = "s", ssl_mode = "VERIFY_IDENTITY"),
                     tablespaces = data.frame(name = c("s/a", "s/b"), encrypted = c(TRUE, TRUE)))
  res <- suppressMessages(check_storage_encryption(adapter = my))
  expect_true(res$encrypted, info = "regulated accepts verified InnoDB encryption")
  expect_identical(res$basis, "verified")

  my <- fake_adapter("mysql", list(name = "s", ssl_mode = "VERIFY_IDENTITY",
                                   at_rest_attestation = "claimed"),
                     tablespaces = data.frame(name = c("s/a", "s/b"), encrypted = c(TRUE, FALSE)))
  expect_error(suppressMessages(check_storage_encryption(adapter = my)),
               "s/b", info = "regulated refuses an unencrypted InnoDB tablespace despite attestation")

  broken <- fake_adapter("postgresql", pg_good)
  broken$connect <- function() stop("connection refused")
  expect_error(suppressMessages(check_storage_encryption(adapter = broken)),
               "Could not connect", info = "an unreachable server is an error, not a pass")
})

with_profile("standard", {
  res <- NULL
  w <- character()
  withCallingHandlers(
    res <- suppressMessages(check_storage_encryption(
      adapter = fake_adapter("postgresql", list(sslmode = "prefer"), tls = FALSE))),
    warning = function(cond) {
      w <<- c(w, conditionMessage(cond))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(is.na(res$encrypted), info = "standard: reported as unknown, not encrypted")
  expect_true(any(grepl("TLS", w)), info = "standard warns about TLS")
  expect_true(any(grepl("at_rest_attestation", w)), info = "standard warns about at-rest state")
})

with_profile("development", {
  res <- suppressMessages(check_storage_encryption(
    adapter = fake_adapter("postgresql", list(), tls = FALSE)))
  expect_true(is.na(res$encrypted), info = "development: no stop, no requirement")
})

# ---------------------------------------------------------------
# Configuration mapping
# ---------------------------------------------------------------

cfg <- app_database_config(list(database = list(
  backend = "postgresql", host = "db", name = "s", sslmode = "verify-full",
  at_rest_attestation = "LUKS")), tempdir())
expect_identical(cfg$postgresql$at_rest_attestation, "LUKS",
                 info = "attestation passes from config.yml to the adapter")
cfg <- app_database_config(list(database = list(
  backend = "mariadb", at_rest_attestation = "file-key-management plugin")), tempdir())
expect_identical(cfg$mysql$at_rest_attestation, "file-key-management plugin")

on.exit_restore()
