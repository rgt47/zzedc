library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Phase 4 of docs/encryption-compliance-plan-2026-11-10.md: key custody,
# key-access audit, and key rotation.

key_source <- get(".key_source_description", envir = asNamespace("zzedc"))

with_profile <- function(profile, code) {
  old <- options(zzedc.security_profile = profile)
  on.exit(options(old), add = TRUE)
  force(code)
}

# 4.1 Custody: no literal key in config.yml
literal <- list(database = list(encryption_key = paste(rep("ab", 32), collapse = "")))
by_ref <- list(database = list(encryption_key = "${DB_ENCRYPTION_KEY}"))
with_profile("regulated", {
  expect_error(check_key_custody(literal), "contains the database encryption key",
               info = "regulated refuses a key written into config.yml")
  expect_true(check_key_custody(by_ref), info = "an environment reference is accepted")
  expect_true(check_key_custody(list(database = list())), info = "no key configured")
})
with_profile("standard", {
  expect_warning(check_key_custody(literal), "contains the database encryption key")
})
expect_identical(key_source(by_ref), "environment variable DB_ENCRYPTION_KEY")
expect_identical(key_source(literal), "config.yml")
expect_true(is.null(key_source(list(database = list()))))

# 4.3 Rotation and 4.5 access record, on encrypted DuckDB
duck_ok <- requireNamespace("duckdb", quietly = TRUE) && tryCatch(
  all(install_duckdb_extensions(tempfile("extk_"))$loads_offline),
  error = function(e) FALSE
)
if (duck_ok) with_profile("development", {
  cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
  had <- exists("adapter", envir = cache)
  prev <- if (had) cache$adapter else NULL
  on.exit(if (had) assign("adapter", prev, envir = cache)
          else if (exists("adapter", envir = cache)) rm("adapter", envir = cache), add = TRUE)

  dir <- tempfile("rot_")
  dir.create(dir)
  old_key <- generate_db_key()
  cfg <- list(db_backend = "duckdb",
              duckdb = list(path = file.path(dir, "study.duckdb"), encryption_key = old_key))
  a <- get_db_adapter(config = cfg, force_new = TRUE)
  init_audit_logging()
  con <- a$connect()
  DBI::dbExecute(con, "CREATE TABLE t AS SELECT 'KEEP_ME' AS v")
  a$disconnect(con)
  expect_true(log_key_access("environment variable DB_ENCRYPTION_KEY"),
              info = "key access recorded")
  con <- a$connect()
  ev <- DBI::dbGetQuery(con, "SELECT event_type, table_name, operation FROM audit_log WHERE table_name = 'encryption_key'")
  a$disconnect(con)
  a$shutdown()
  expect_equal(nrow(ev), 1)
  expect_false(grepl(old_key, ev$operation, fixed = TRUE), info = "the key itself is not logged")

  res <- rotate_database_key(cfg)
  expect_false(identical(res$new_key, old_key))
  new_cfg <- cfg
  new_cfg$duckdb$encryption_key <- res$new_key
  v_new <- verify_database_encryption(cfg$duckdb$path, key = res$new_key,
                                      adapter = create_db_adapter(new_cfg))
  expect_true(v_new$encrypted, info = "opens with the new key")
  v_old <- verify_database_encryption(cfg$duckdb$path, key = old_key,
                                      adapter = create_db_adapter(cfg))
  expect_false(v_old$connection_works, info = "no longer opens with the old key")
  a2 <- create_db_adapter(new_cfg)
  con <- a2$connect()
  expect_identical(DBI::dbGetQuery(con, "SELECT v FROM t")$v, "KEEP_ME", info = "data preserved")
  rot <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM audit_log WHERE event_type = 'CONFIG_CHANGE' AND table_name = 'encryption_key'")$n
  a2$disconnect(con)
  a2$shutdown()
  expect_equal(rot, 1, info = "rotation recorded in the audit log")
  expect_true(file.exists(res$previous_copy), info = "previous copy kept")
  expect_true(file.exists(file.path(dir, "key_rotation.log")))
  expect_false(any(grepl(res$new_key, readLines(file.path(dir, "key_rotation.log")), fixed = TRUE)),
               info = "the rotation log holds no key")
  expect_error(rotate_database_key(new_cfg, new_key = res$new_key), "same as the current")
  unlink(dir, recursive = TRUE)
})
