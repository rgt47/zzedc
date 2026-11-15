# Fixes made so that the manuscript's descriptions hold:
# 1. a spreadsheet or CSV import writes one hash-chained audit event;
# 2. init() writes a security profile its own database satisfies.

with_adapter_restored <- function(code) {
  cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
  had_adapter <- exists("adapter", envir = cache)
  previous <- if (had_adapter) cache$adapter else NULL
  on.exit(if (had_adapter) assign("adapter", previous, envir = cache)
          else if (exists("adapter", envir = cache)) rm("adapter", envir = cache))
  force(code)
}

# ---------------------------------------------------------------
# 1. Import audit event
# ---------------------------------------------------------------

adhd_dir <- system.file("extdata", "adhd_trial", package = "zzedc")
if (!nzchar(adhd_dir)) {
  adhd_dir <- normalizePath("../../inst/extdata/adhd_trial", mustWork = FALSE)
}

if (dir.exists(adhd_dir)) local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  old_env <- Sys.getenv("ZZEDC_DB_PATH", unset = NA)
  on.exit(if (is.na(old_env)) Sys.unsetenv("ZZEDC_DB_PATH")
          else Sys.setenv(ZZEDC_DB_PATH = old_env), add = TRUE)

  with_adapter_restored({
    dir <- tempfile("imp_audit_")
    dir.create(file.path(dir, "data"), recursive = TRUE)
    db <- file.path(dir, "data", "study.db")
    res <- suppressWarnings(setup_zzedc_from_csv(adhd_dir, db_path = db,
                                                 salt = "s"))
    expect_true(res$success, info = "example study imports")
    expect_true(grepl("^[0-9a-f]{64}$", res$config_sha256 %||% ""),
                info = "the import reports a SHA-256 configuration digest")

    con <- DBI::dbConnect(RSQLite::SQLite(), db)
    ev <- DBI::dbGetQuery(con, "
      SELECT event_type, table_name, details FROM audit_log
      WHERE table_name = 'study_configuration'")
    DBI::dbDisconnect(con)
    expect_equal(nrow(ev), 1L, info = "one audit event per import")
    expect_equal(ev$event_type, "CONFIG_CHANGE")
    det <- jsonlite::fromJSON(ev$details)
    expect_equal(det$rules_imported, 56, info = "rule count recorded")
    expect_equal(det$forms_imported, 9, info = "form count recorded")
    expect_identical(det$config_sha256, res$config_sha256,
                     info = "the logged digest matches the returned one")
    expect_false(grepl("password", ev$details, ignore.case = TRUE),
                 info = "no password material in the audit details")

    expect_true(isTRUE(verify_audit_integrity(db_path = db)$valid),
                info = "the chain still verifies after the import event")

    dry <- suppressWarnings(setup_zzedc_from_csv(adhd_dir, db_path = db,
                                                 salt = "s", dry_run = TRUE,
                                                 create_database = FALSE))
    con <- DBI::dbConnect(RSQLite::SQLite(), db)
    n <- DBI::dbGetQuery(con, "
      SELECT COUNT(*) AS n FROM audit_log
      WHERE table_name = 'study_configuration'")$n
    DBI::dbDisconnect(con)
    expect_equal(n, 1L, info = "a dry run writes no audit event")
    unlink(dir, recursive = TRUE)
  })
})

# ---------------------------------------------------------------
# 1b. Non-ASCII audit text verifies
# ---------------------------------------------------------------
# The hash input is serialized with its encoding mark; a native-marked
# string at write time and a UTF-8-marked one read back from the
# database used to hash differently.

local({
  hc <- get(".audit_hash_content", envir = asNamespace("zzedc"))
  utf8 <- "Temperature (°C), José"
  native <- iconv(utf8, "UTF-8", "")
  Encoding(native) <- "unknown"
  h <- function(s) digest::digest(hc("INSERT", "t", "1", "op", s, "u",
                                     NA, NA, "2026-01-01 00:00:00", "GENESIS"),
                                  algo = "sha256")
  expect_identical(h(native), h(utf8),
                   info = "hash does not depend on the string's encoding mark")
  expect_identical(
    digest::digest(hc("INSERT", "t", "1", "op", "ascii", "u", NA, NA,
                      "2026-01-01 00:00:00", "GENESIS"), algo = "sha256"),
    digest::digest(paste("INSERT", "t", "1", "op", "ascii", "u", "", "",
                         "2026-01-01 00:00:00", "GENESIS", sep = "|"),
                   algo = "sha256"),
    info = "ASCII hashes are unchanged by the fix"
  )
})

# ---------------------------------------------------------------
# 2. init() security profile
# ---------------------------------------------------------------

local({
  execute_init_setup <- get("execute_init_setup", envir = asNamespace("zzedc"))
  base_cfg <- list(
    study_name = "Profile Test", protocol_id = "PT-1",
    pi_name = "PI", pi_email = "pi@example.org",
    target_enrollment = 10, study_phase = "Pilot",
    admin_username = "admin1", admin_fullname = "Admin One",
    admin_email = "admin@example.org", admin_password = "Str0ng!pass",
    security_salt = "0123456789abcdef0123456789abcdef",
    session_timeout = 30, enforce_https = FALSE,
    team_members = data.frame()
  )

  with_adapter_restored({
    dir <- tempfile("init_prof_")
    dir.create(dir)
    res <- suppressWarnings(utils::capture.output(
      out <- execute_init_setup(base_cfg, project_dir = dir)
    ))
    expect_true(isTRUE(out$success), info = "init setup completes")
    cfg <- yaml::read_yaml(out$config_path)
    prof <- cfg$default$security$profile %||% cfg$security$profile
    encrypted <- isTRUE(zzedc:::sqlite_file_is_encrypted(out$database_path))
    expect_identical(prof, if (encrypted) "regulated" else "standard",
                     info = "the profile matches the database init() created")
    unlink(dir, recursive = TRUE)

    dir2 <- tempfile("init_prof2_")
    dir.create(dir2)
    cfg2 <- base_cfg
    cfg2$security_profile <- "regulated"
    if (!encrypted) {
      expect_warning(
        utils::capture.output(execute_init_setup(cfg2, project_dir = dir2)),
        pattern = "refuse to start",
        info = "an explicit regulated profile over plaintext storage warns"
      )
    }
    unlink(dir2, recursive = TRUE)
  })
})
