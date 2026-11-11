library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Fixes of 2026-11-11: one password-salt rule; restore staged and
# applied at startup instead of overwriting the open database; Google
# Sheets import on any backend, into an existing study; the first-run
# choice screen.

ns_get <- function(name) get(name, envir = asNamespace("zzedc"))
backup_restore_server <- ns_get("backup_restore_server")
setup_choice_server <- ns_get("setup_choice_server")
create_database_backup <- ns_get("create_database_backup")

with_env <- function(vars, code) {
  old <- Sys.getenv(names(vars), unset = NA, names = TRUE)
  on.exit(for (n in names(old)) {
    if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(old[[n]]), n))
  }, add = TRUE)
  for (n in names(vars)) {
    if (is.na(vars[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(vars[[n]]), n))
  }
  force(code)
}

# ---------------------------------------------------------------
# 1. One salt rule
# ---------------------------------------------------------------

local({
  old_opt <- options(zzedc.auth_salt = NULL)
  on.exit(options(old_opt), add = TRUE)
  cfg_env <- list(auth = list(salt_env_var = "ZZEDC_SALT", default_salt = "cfg_default"))
  with_env(c(ZZEDC_SALT = "env_salt"), {
    expect_identical(resolve_auth_salt(cfg_env), "env_salt",
                     info = "the configured salt variable wins when set")
  })
  with_env(c(ZZEDC_SALT = NA), {
    expect_identical(resolve_auth_salt(cfg_env), "cfg_default",
                     info = "falls back to the configured default salt")
    expect_identical(resolve_auth_salt(list(auth = list(default_salt = "d"))), "d",
                     info = "no salt variable configured: default salt")
    expect_identical(resolve_auth_salt(), "default_salt",
                     info = "outside the app, previous user-management fallback")
  })
  options(zzedc.auth_salt = "from_app")
  expect_identical(resolve_auth_salt(), "from_app",
                   info = "package modules inside the app follow the app's salt")
})

# The launcher's default administrator can log in when ZZEDC_SALT is set.
local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  with_env(c(ZZEDC_SALT = "custom_deployment_salt"), {
    cfg <- list(auth = list(salt_env_var = "ZZEDC_SALT", default_salt = "unused"))
    path <- tempfile(fileext = ".db")
    res <- suppressWarnings(initialize_default_database(path, salt = resolve_auth_salt(cfg)))
    expect_true(res$success)
    con <- DBI::dbConnect(RSQLite::SQLite(), path)
    stored <- DBI::dbGetQuery(con, "SELECT password_hash FROM edc_users WHERE username = 'admin'")$password_hash
    DBI::dbDisconnect(con)
    login_hash <- digest::digest(paste0("admin123", resolve_auth_salt(cfg)), algo = "sha256")
    expect_identical(stored, login_hash,
                     info = "admin password hashed with the salt login uses (was the built-in salt)")
    unlink(path)
  })
})

# ---------------------------------------------------------------
# 2. Restore: staged, applied at startup
# ---------------------------------------------------------------

local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  dir <- tempfile("restore_")
  dir.create(dir)
  path <- file.path(dir, "study.db")
  cfg <- list(db_backend = "sqlite", sqlite = list(path = path))
  adapter <- create_db_adapter(cfg)
  p <- adapter$pool()
  pool::dbExecute(p, "CREATE TABLE t (v TEXT)")
  pool::dbExecute(p, "INSERT INTO t VALUES ('A')")

  bk <- file.path(dir, "backup.db")
  create_database_backup(p, path, "sqlite", bk)
  pool::dbExecute(p, "INSERT INTO t VALUES ('B')")

  expect_error(request_database_restore(file.path(dir, "nope.db"), path, "sqlite"),
               "not found")
  junk <- file.path(dir, "junk.db")
  writeLines("not a database", junk)
  expect_error(request_database_restore(junk, path, "sqlite"), "not a sqlite database",
               info = "a file that is not a database is refused")
  expect_false(file.exists(paste0(path, ".restore-pending")))

  gz <- file.path(dir, "backup.db.gz")
  R.utils::gzip(bk, destname = gz, remove = FALSE)
  staged <- request_database_restore(gz, path, "sqlite", requested_by = "tester")
  expect_true(file.exists(staged$staged), info = "compressed backup staged")
  expect_equal(pool::dbGetQuery(p, "SELECT count(*) AS n FROM t")$n, 2,
               info = "the open database is not touched by the request")
  pool::poolClose(p)

  writeLines("stale", paste0(path, "-wal"))
  applied <- apply_pending_restore(cfg)
  expect_true(applied$applied)
  expect_false(file.exists(paste0(path, "-wal")),
               info = "a stale write-ahead log is not left beside the restored file")
  expect_true(file.exists(file.path(applied$pre_restore_dir, "study.db-wal")),
              info = "but it is kept with the pre-restore copy")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  expect_identical(DBI::dbGetQuery(con, "SELECT v FROM t")$v, "A", info = "restored content")
  DBI::dbDisconnect(con)
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(applied$pre_restore_dir, "study.db"))
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM t")$n, 2,
               info = "the replaced database is kept")
  DBI::dbDisconnect(con)
  expect_true(file.exists(file.path(dir, "restore_history.log")))
  expect_false(apply_pending_restore(cfg)$applied, info = "nothing pending afterward")
  unlink(dir, recursive = TRUE)
})

# The Backup tab accepts only its own backups (paths come from the browser).
if (requireNamespace("shinyjs", quietly = TRUE)) local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  dir <- tempfile("bkui_")
  bdir <- file.path(dir, "backups")
  dir.create(bdir, recursive = TRUE)
  path <- file.path(dir, "study.db")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbWriteTable(con, "t", data.frame(v = "A"))
  DBI::dbDisconnect(con)
  file.copy(path, file.path(bdir, "backup_1.db"))
  outside <- file.path(dir, "outside.txt")
  writeLines("keep me", outside)

  shiny::testServer(backup_restore_server,
    args = list(db_path = shiny::reactive(path), backup_dir = bdir), {
      session$setInputs(select_backup = outside)
      expect_true(is.null(backup_state$selected_backup),
                  info = "a path outside the backup folder is not selected")
      session$setInputs(delete_backup = outside)
      expect_true(file.exists(outside), info = "and cannot be deleted")
      session$setInputs(select_backup = file.path(bdir, "backup_1.db"))
      expect_identical(normalizePath(backup_state$selected_backup),
                       normalizePath(file.path(bdir, "backup_1.db")))
      session$setInputs(download_backup = outside)
      expect_true(is.null(download_target()),
                  info = "Download refuses a path outside the backup folder")
      session$setInputs(download_backup = file.path(bdir, "backup_1.db"))
      downloaded <- output$download_file
      expect_identical(unname(tools::md5sum(downloaded)),
                       unname(tools::md5sum(file.path(bdir, "backup_1.db"))),
                       info = "Download serves the selected backup (the button did nothing)")
      session$setInputs(restore_confirmation = "RESTORE", restore_btn = 1)
      expect_true(file.exists(paste0(path, ".restore-pending")),
                  info = "Restore stages the backup instead of overwriting the open file")
    })
  unlink(dir, recursive = TRUE)
})

duck_ok <- requireNamespace("duckdb", quietly = TRUE) && tryCatch(
  all(install_duckdb_extensions(tempfile("extp_"))$loads_offline),
  error = function(e) FALSE
)

if (duck_ok) local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  dir <- tempfile("duckrestore_")
  dir.create(dir)
  path <- file.path(dir, "study.duckdb")
  key <- generate_db_key()
  cfg <- list(db_backend = "duckdb", duckdb = list(path = path, encryption_key = key))
  adapter <- create_db_adapter(cfg)
  p <- adapter$pool()
  pool::dbExecute(p, "CREATE TABLE t (v VARCHAR)")
  pool::dbExecute(p, "INSERT INTO t VALUES ('A')")
  bk <- file.path(dir, "backup.db")
  create_database_backup(p, path, "duckdb", bk)
  pool::dbExecute(p, "INSERT INTO t VALUES ('B')")
  request_database_restore(bk, path, "duckdb")
  pool::poolClose(p)
  adapter$shutdown()

  expect_true(apply_pending_restore(cfg)$applied)
  a2 <- create_db_adapter(cfg)
  con <- a2$connect()
  expect_identical(DBI::dbGetQuery(con, "SELECT v FROM t")$v, "A",
                   info = "encrypted DuckDB restored")
  a2$disconnect(con)
  a2$shutdown()
  expect_true(verify_database_encryption(path, key = key)$encrypted,
              info = "and still encrypted")
  unlink(dir, recursive = TRUE)
})

# ---------------------------------------------------------------
# 3. Google Sheets import into an existing study, on DuckDB
# ---------------------------------------------------------------

if (duck_ok && requireNamespace("googlesheets4", quietly = TRUE)) local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)

  sheets <- list(
    Study_Users = data.frame(
      username = c("admin", "coord1"), full_name = c("Admin", "Coordinator One"),
      email = c("a@x.org", "c@x.org"), role = c("Admin", "Coordinator"),
      password_initial = c("ignored", "Coord1Pass!"), stringsAsFactors = FALSE),
    Data_Dictionary = data.frame(
      form_code = c("ae", "ae"), field_name = c("ae_term", "ae_grade"),
      field_label = c("Term", "Grade"), field_type = c("text", "select"),
      required = c(TRUE, FALSE), validation = c(NA, "in(1,2,3)"),
      stringsAsFactors = FALSE),
    validation_rules = data.frame(rule_id = character(), field_code = character(),
                                  rule_dsl = character(), stringsAsFactors = FALSE)
  )
  gs_ns <- asNamespace("googlesheets4")
  original <- get("read_sheet", envir = gs_ns)
  unlockBinding("read_sheet", gs_ns)
  assign("read_sheet", function(ss, sheet = NULL, ...) sheets[[sheet]], envir = gs_ns)
  on.exit({
    assign("read_sheet", original, envir = gs_ns)
    lockBinding("read_sheet", gs_ns)
  }, add = TRUE)

  dir <- tempfile("gs_")
  dir.create(file.path(dir, "data"), recursive = TRUE)
  key <- generate_db_key()
  cfg <- list(db_backend = "duckdb",
              duckdb = list(path = file.path(dir, "data", "study.duckdb"), encryption_key = key))
  init <- initialize_default_database(cfg$duckdb$path, adapter_config = cfg, salt = "s")
  expect_true(init$success)

  # As inside the application: the cached adapter is the study's own.
  # Restore whatever was cached before, so later test files are not
  # left pointing at this temporary database.
  cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
  had_adapter <- exists("adapter", envir = cache)
  previous <- if (had_adapter) cache$adapter else NULL
  a <- get_db_adapter(config = cfg, force_new = TRUE)
  on.exit({
    a$shutdown()
    if (had_adapter) assign("adapter", previous, envir = cache)
    else if (exists("adapter", envir = cache)) rm("adapter", envir = cache)
  }, add = TRUE)

  res <- setup_zzedc_from_gsheets("fake-sheet-id", adapter_config = cfg,
                                  create_database = FALSE, salt = "s")
  expect_true(identical(get_db_adapter(), a),
              info = "the import reuses the cached adapter (no second DuckDB instance)")
  expect_equal(res$users$imported, 1, info = "new user imported on DuckDB")
  expect_equal(res$users$skipped, 1, info = "existing admin left unchanged")
  expect_equal(res$forms$imported_forms, 1)
  expect_equal(res$forms$imported_fields, 2)

  res2 <- setup_zzedc_from_gsheets("fake-sheet-id", adapter_config = cfg,
                                   create_database = FALSE, salt = "s")
  expect_equal(res2$users$skipped, 2, info = "re-import does not duplicate users")
  expect_equal(res2$forms$skipped, 1, info = "re-import skips the existing form")
  expect_true(res2$users$success && res2$forms$success,
              info = "and reports no errors for them")

  # A form created afterwards in the CRF designer must not collide with
  # the id the import gave its form in both tables.
  designed <- create_designer_form("NEWFORM", "New Form", created_by = "tester")
  expect_true(designed$success, info = paste("designer form after import:", designed$error))

  con <- a$connect()
  expect_equal(DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM designer_fields f JOIN crf_definitions c ON f.design_id = c.crf_id")$n,
    2, info = "imported fields join to their CRF, as the EDC tab reads them")
  h <- DBI::dbGetQuery(con, "SELECT password_hash FROM edc_users WHERE username = 'coord1'")$password_hash
  admin_h <- DBI::dbGetQuery(con, "SELECT password_hash FROM edc_users WHERE username = 'admin'")$password_hash
  a$disconnect(con)
  expect_identical(h, digest::digest(paste0("Coord1Pass!", "s"), algo = "sha256"))
  expect_identical(admin_h, digest::digest(paste0("admin123", "s"), algo = "sha256"),
                   info = "existing admin's password not reset by the import")
  a$shutdown()
  expect_true(verify_database_encryption(cfg$duckdb$path, key = key, adapter = a)$encrypted)
  unlink(dir, recursive = TRUE)
})

# ---------------------------------------------------------------
# 4. First-run choice screen
# ---------------------------------------------------------------

local({
  closed <- FALSE
  shiny::testServer(setup_choice_server,
    args = list(on_console = function() closed <<- TRUE), {
      expect_true(is.null(session$returned()))
      session$setInputs(choose_wizard = 1)
      expect_identical(session$returned(), "wizard")
      session$setInputs(choose_shell = 1)
      expect_identical(session$returned(), "shell")
      session$setInputs(close_for_console = 1)
      expect_true(closed, info = "closing for the console path ends the setup page")
    })
})

# ---------------------------------------------------------------
# 5. setup_zzedc_from_csv() and the bundled ADHD example study
# ---------------------------------------------------------------

adhd_dir <- system.file("extdata", "adhd_trial", package = "zzedc")
if (!nzchar(adhd_dir)) adhd_dir <- normalizePath("../../inst/extdata/adhd_trial", mustWork = FALSE)

if (dir.exists(adhd_dir)) local({
  old <- options(zzedc.security_profile = "development")
  on.exit(options(old), add = TRUE)
  cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
  had_adapter <- exists("adapter", envir = cache)
  previous <- if (had_adapter) cache$adapter else NULL
  on.exit(if (had_adapter) assign("adapter", previous, envir = cache)
          else if (exists("adapter", envir = cache)) rm("adapter", envir = cache), add = TRUE)

  dir <- tempfile("adhd_")
  dir.create(file.path(dir, "data"), recursive = TRUE)
  db <- file.path(dir, "data", "study.db")
  res <- suppressWarnings(setup_zzedc_from_csv(adhd_dir, db_path = db, salt = "s"))
  expect_true(res$success, info = "the bundled example loads without errors")
  expect_equal(res$users$imported, 4)
  expect_equal(res$forms$imported_forms, 9)
  expect_equal(res$forms$imported_fields, 129)
  expect_equal(res$validation_rules$imported, 57)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  names <- DBI::dbGetQuery(con, "SELECT crf_name FROM crf_definitions WHERE crf_code = 'ADHD_RATING'")$crf_name
  inactive <- DBI::dbGetQuery(con, "SELECT active FROM edc_users WHERE username = 'backup_admin'")$active
  DBI::dbDisconnect(con)
  expect_identical(names, "ADHD Rating Scale", info = "form_name column used")
  expect_equal(inactive, 0, info = "the active column is honored (it was ignored)")

  again <- suppressWarnings(setup_zzedc_from_csv(adhd_dir, db_path = db, salt = "s",
                                                 create_database = FALSE))
  expect_true(again$success, info = "re-import into the existing study reports no errors")
  expect_equal(again$users$skipped, 4)
  expect_equal(again$forms$skipped, 9)
  expect_equal(again$validation_rules$already_present, 57,
               info = "existing validation rules are skipped, not duplicated")

  expect_false(setup_zzedc_from_csv(file.path(dir, "nope"), db_path = db)$success,
               info = "a missing folder is reported")
  unlink(dir, recursive = TRUE)
})

# ---------------------------------------------------------------
# 6. Phase 2.1: encrypted backups
# ---------------------------------------------------------------

local({
  check_backup_policy <- get("check_backup_policy", envir = asNamespace("zzedc"))
  finalize_backup_file <- get("finalize_backup_file", envir = asNamespace("zzedc"))
  perform_automatic_backup <- get("perform_automatic_backup", envir = asNamespace("zzedc"))
  dir <- tempfile("encbk_")
  dir.create(dir)
  db <- file.path(dir, "study.db")
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbWriteTable(con, "t", data.frame(v = "SECRET_ROW"))
  DBI::dbDisconnect(con)

  old <- options(zzedc.security_profile = "regulated")
  on.exit(options(old), add = TRUE)
  with_env(c(ZZEDC_BACKUP_PASSPHRASE = NA), {
    expect_error(check_backup_policy(FALSE, backup_passphrase()), "ZZEDC_BACKUP_PASSPHRASE",
                 info = "regulated: plaintext backup of a plaintext database refused")
    expect_true(check_backup_policy(TRUE, NULL),
                info = "an encrypted database's copy is already ciphertext")
    res <- perform_automatic_backup(db, backup_dir = file.path(dir, "auto"))
    expect_false(isTRUE(res$success), info = "scheduled backup refused too")
    expect_equal(length(list.files(file.path(dir, "auto"))), 0, info = "and nothing written")
  })

  with_env(c(ZZEDC_BACKUP_PASSPHRASE = "a long backup passphrase"), {
    res <- perform_automatic_backup(db, backup_dir = file.path(dir, "auto"))
    expect_true(res$success)
    bk <- res$filepath
    expect_true(grepl("\\.db\\.gz\\.enc$", bk), info = "compressed, then encrypted")
    bytes <- readBin(bk, "raw", n = file.size(bk))
    expect_equal(length(grepRaw(charToRaw("SECRET_ROW"), bytes, fixed = TRUE)), 0,
                 info = "no plaintext record in the backup")

    target <- file.path(dir, "restored.db")
    file.copy(db, target)
    staged <- request_database_restore(bk, target, "sqlite")
    expect_true(file.exists(staged$staged), info = "encrypted backup decrypted and staged")
    expect_error(request_database_restore(bk, target, "sqlite", passphrase = "wrong passphrase!"),
                 "wrong password", info = "wrong passphrase refused")
  })
  unlink(dir, recursive = TRUE)
})

# ---------------------------------------------------------------
# 7. Phase 3.1: HTTPS enforcement
# ---------------------------------------------------------------

local({
  fake_session <- function(protocol, hostname, forwarded = NULL, remote = "203.0.113.5") {
    list(clientData = list(url_protocol = protocol, url_hostname = hostname),
         request = list(HTTP_X_FORWARDED_PROTO = forwarded, REMOTE_ADDR = remote))
  }
  expect_true(session_https_status(fake_session("https:", "study.example.edu"))$ok)
  expect_false(session_https_status(fake_session("http:", "study.example.edu"))$ok,
               info = "plain HTTP from outside is refused")
  expect_true(session_https_status(fake_session("http:", "study.example.edu", "https", "127.0.0.1"))$ok,
              info = "X-Forwarded-Proto trusted from a local proxy")
  expect_false(session_https_status(fake_session("http:", "study.example.edu", "https", "203.0.113.5"))$ok,
               info = "but not from a remote client, which could set it")
  expect_true(session_https_status(fake_session("http:", "localhost"))$ok,
              info = "loopback connections allowed")

  old <- options(zzedc.security_profile = "standard")
  on.exit(options(old), add = TRUE)
  expect_false(https_required(list(security = list(https_only = FALSE))))
  expect_true(https_required(list(security = list(https_only = TRUE))))
  expect_true(https_required(list(security = list(enforce_https = TRUE))),
              info = "the wizard's older key is honored")
  options(zzedc.security_profile = "regulated")
  expect_true(https_required(list()), info = "regulated always requires HTTPS")
})
