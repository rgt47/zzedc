library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Phase 6.1: the startup compliance self-check and its audit record.

with_profile <- function(profile, code) {
  old <- options(zzedc.security_profile = profile)
  on.exit(options(old), add = TRUE)
  force(code)
}

# ---------------------------------------------------------------
# compliance_self_check(): classification of what was observed
# ---------------------------------------------------------------

with_profile("regulated", {
  cfg <- list(database = list(backend = "duckdb", encryption_key = "${DB_ENCRYPTION_KEY}",
                              extension_directory = "/srv/ext"),
              security = list(profile = "regulated"))
  st <- list(profile = "regulated", source = "config.yml", backend = "duckdb",
             encrypted = TRUE, reason = "verified")
  chk <- compliance_self_check(cfg, st, app_database_config(cfg, tempdir()))
  expect_identical(chk$at_rest, "yes")
  expect_identical(chk$at_rest_mechanism, "package-enforced",
                   info = "DuckDB encryption is enforced by the package")
  expect_identical(chk$tls, "not applicable")
  expect_identical(chk$key_source, "environment variable DB_ENCRYPTION_KEY")
  expect_true(grepl("/srv/ext", chk$extensions))
  expect_true(grepl("not allowed", chk$extensions),
              info = "regulated disallows extension downloads by default")
  expect_true(chk$https_required, info = "regulated requires HTTPS")
})

with_profile("regulated", {
  cfg <- list(database = list(backend = "postgresql", sslmode = "verify-full",
                              at_rest_attestation = "LUKS"))
  st <- list(profile = "regulated", source = "config.yml", backend = "postgresql",
             encrypted = TRUE, basis = "attested", tls = TRUE, reason = "Attested")
  chk <- compliance_self_check(cfg, st, app_database_config(cfg, tempdir()))
  expect_identical(chk$at_rest_mechanism, "server-attested",
                   info = "an attestation is not reported as verification")
  expect_identical(chk$tls, "yes")
  expect_identical(chk$key_source, "no key configured")
})

with_profile("standard", {
  cfg <- list(database = list(backend = "mysql"))
  st <- list(profile = "standard", source = "default", backend = "mysql",
             encrypted = TRUE, basis = "verified", tls = FALSE, reason = "InnoDB")
  chk <- compliance_self_check(cfg, st, app_database_config(cfg, tempdir()))
  expect_identical(chk$at_rest_mechanism, "server-verified")
  expect_identical(chk$tls, "no")

  cfg <- list(database = list(backend = "sqlite", path = "x.db"))
  st <- list(profile = "standard", source = "default", backend = "sqlite",
             encrypted = FALSE, reason = "plaintext header")
  chk <- compliance_self_check(cfg, st, app_database_config(cfg, tempdir()))
  expect_identical(chk$at_rest, "no")
  expect_identical(chk$at_rest_mechanism, "none")
  expect_false(chk$https_required)

  st$encrypted <- NA
  chk <- compliance_self_check(cfg, st, app_database_config(cfg, tempdir()))
  expect_identical(chk$at_rest, "unknown", info = "NA is reported as unknown, not as no or yes")
})

# ---------------------------------------------------------------
# record_compliance_check(): written to the hash-chained audit log
# ---------------------------------------------------------------

with_profile("development", {
  cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
  had <- exists("adapter", envir = cache)
  prev <- if (had) cache$adapter else NULL
  dir <- tempfile("cc_")
  dir.create(dir)
  db <- file.path(dir, "study.db")
  cfg <- list(database = list(backend = "sqlite", path = db))
  db_config <- app_database_config(cfg, dir)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "CREATE TABLE placeholder (x INTEGER)")
  DBI::dbDisconnect(con)
  a <- get_db_adapter(config = db_config, force_new = TRUE)
  init_audit_logging(db_path = db)

  st <- list(profile = "development", source = "option", backend = "sqlite",
             encrypted = FALSE, reason = "plaintext header")
  chk <- compliance_self_check(cfg, st, db_config)
  expect_true(record_compliance_check(chk), info = "the record is written")

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  ev <- DBI::dbGetQuery(con, "SELECT operation, details FROM audit_log WHERE event_type = 'COMPLIANCE_CHECK'")
  DBI::dbDisconnect(con)
  expect_equal(nrow(ev), 1)
  expect_true(grepl("encrypted at rest no", ev$operation))
  parsed <- jsonlite::fromJSON(ev$details)
  expect_identical(parsed$at_rest_mechanism, "none", info = "full check stored as JSON")
  expect_true(isTRUE(verify_audit_integrity(db_path = db)$valid),
              info = "the record is part of the intact hash chain")

  a$shutdown()
  if (had) assign("adapter", prev, envir = cache) else if (exists("adapter", envir = cache)) rm("adapter", envir = cache)
})

# ---------------------------------------------------------------
# Phase 6.2: security controls in Operational Qualification
# ---------------------------------------------------------------

local({
  oq <- run_oq_tests(verbose = FALSE)
  ids <- vapply(oq$results, function(r) r$test_id, "")
  expect_true(all(sprintf("OQ-%03d", 11:20) %in% ids),
              info = "OQ-011 to OQ-020 (security controls) are part of run_oq_tests()")
  sec <- oq$results[ids %in% sprintf("OQ-%03d", 11:20)]
  expect_true(all(vapply(sec, function(r) isTRUE(r$passed), TRUE)),
              info = paste(vapply(sec, function(r) paste(r$test_id, r$message), ""), collapse = "; "))
})
