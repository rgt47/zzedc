library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Phase 0 of docs/encryption-compliance-plan-2026-11-10.md: security
# profiles, fail-closed encryption checks, honest verification,
# working re-keying, password-encrypted exports, and HMAC
# pseudonymization. Each block below was written to fail against the
# pre-Phase-0 code.

# These internals are not exported. Bind them from the namespace so
# the file runs against the installed package under R CMD check, not
# only under pkgload::load_all(), which exposes everything.
for (internal in c("reset_encryption_warnings", "enforce_encryption_at_rest",
                   "connect_encrypted", ".check_deployment_storage",
                   ".enter_validation_scope", ".hex_to_raw")) {
  assign(internal, get(internal, envir = asNamespace("zzedc")))
}

with_profile <- function(profile, code) {
  old <- options(zzedc.security_profile = profile)
  on.exit(options(old), add = TRUE)
  reset_encryption_warnings()
  force(code)
}

make_plain_sqlite <- function(path, value = "PLAINTEXT_MARKER") {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbWriteTable(con, "subjects", data.frame(subject_id = value))
  DBI::dbDisconnect(con)
  path
}

stock_rsqlite <- !sqlite_cipher_available()

duckdb_encryption_ok <- function() {
  if (!requireNamespace("duckdb", quietly = TRUE)) return(FALSE)
  tryCatch({
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    DBI::dbExecute(con, "INSTALL httpfs")
    DBI::dbExecute(con, "LOAD httpfs")
    TRUE
  }, error = function(e) FALSE)
}
duck_ok <- duckdb_encryption_ok()

# ---------------------------------------------------------------
# Profile resolution
# ---------------------------------------------------------------

local({
  old <- options(zzedc.security_profile = NULL)
  on.exit(options(old), add = TRUE)
  old_env <- Sys.getenv("ZZEDC_SECURITY_PROFILE", unset = NA)
  Sys.unsetenv("ZZEDC_SECURITY_PROFILE")
  on.exit(if (is.na(old_env)) Sys.unsetenv("ZZEDC_SECURITY_PROFILE")
          else Sys.setenv(ZZEDC_SECURITY_PROFILE = old_env), add = TRUE)

  none <- resolve_security_profile(config_path = tempfile())
  expect_identical(none$profile, "standard", info = "built-in default is standard")
  expect_identical(none$source, "default")

  top <- tempfile(fileext = ".yml")
  writeLines("security:\n  profile: regulated", top)
  expect_identical(resolve_security_profile(top)$profile, "regulated",
                   info = "top-level security.profile (load_db_config schema)")
  expect_identical(resolve_security_profile(top)$source, "config.yml")

  app <- tempfile(fileext = ".yml")
  writeLines("default:\n  security:\n    profile: development", app)
  expect_identical(resolve_security_profile(app)$profile, "development",
                   info = "default.security.profile (config::get schema)")

  expect_identical(
    resolve_security_profile(top, config_profile = "standard")$profile,
    "standard", info = "config_profile argument replaces reading the file"
  )

  Sys.setenv(ZZEDC_SECURITY_PROFILE = "development")
  expect_identical(resolve_security_profile(top)$source, "environment",
                   info = "environment variable outranks config.yml")
  options(zzedc.security_profile = "regulated")
  expect_identical(resolve_security_profile(top)$profile, "regulated",
                   info = "option outranks environment variable")

  options(zzedc.security_profile = "strict")
  expect_error(resolve_security_profile(), "Invalid zzedc security profile",
               info = "unknown profile names are rejected, not ignored")
  unlink(c(top, app))
})

# ---------------------------------------------------------------
# Policy enforcement
# ---------------------------------------------------------------

with_profile("regulated", {
  expect_error(enforce_encryption_at_rest(FALSE, "x.db", "why"),
               "NOT encrypted at rest", info = "regulated refuses")
  expect_true(enforce_encryption_at_rest(TRUE, "x.db", "why"),
              info = "verified encryption passes under regulated")
  expect_error(enforce_encryption_at_rest(NA, "x.db", "why"),
               info = "undetermined state is treated as not shown")
})

with_profile("standard", {
  expect_warning(enforce_encryption_at_rest(FALSE, "y.db", "why"),
                 "NOT encrypted at rest", info = "standard warns")
  expect_silent(enforce_encryption_at_rest(FALSE, "y.db", "why"))
})

with_profile("development", {
  expect_silent(enforce_encryption_at_rest(FALSE, "z.db", "why"))
})

# ---------------------------------------------------------------
# SQLite: detection and honest results on stock RSQLite
# ---------------------------------------------------------------

local({
  plain <- make_plain_sqlite(tempfile(fileext = ".db"))
  expect_false(sqlite_file_is_encrypted(plain), info = "plaintext header detected")
  expect_true(is.na(sqlite_file_is_encrypted(tempfile())), info = "missing file is NA")
  rnd <- tempfile()
  writeBin(openssl::rand_bytes(4096), rnd)
  expect_true(sqlite_file_is_encrypted(rnd), info = "ciphertext-like bytes are not plaintext SQLite")
  unlink(c(plain, rnd))
})

if (stock_rsqlite) {
  # Defect 3.1: initialize_encrypted_database() reported "encrypted" for a
  # plaintext file.
  with_profile("development", {
    db <- tempfile(fileext = ".db")
    res <- initialize_encrypted_database(db_path = db)
    expect_true(res$success)
    expect_false(res$encrypted, info = "stock RSQLite result says not encrypted")
    expect_true(grepl("NOT encrypted", res$message), info = "message says so plainly")
    unlink(db)
  })

  with_profile("regulated", {
    db <- tempfile(fileext = ".db")
    res <- initialize_encrypted_database(db_path = db)
    expect_false(res$success, info = "regulated refuses a plaintext SQLite database")
    expect_false(file.exists(db), info = "no plaintext file is left behind")
  })

  with_profile("regulated", {
    plain <- make_plain_sqlite(tempfile(fileext = ".db"))
    expect_error(connect_encrypted(plain, generate_db_key()), "NOT encrypted",
                 info = "connect_encrypted fails closed on a plaintext file")
    unlink(plain)
  })

  with_profile("development", {
    expect_error(test_encryption(tempfile(fileext = ".db"), generate_db_key()),
                 "Encryption is not active",
                 info = "test_encryption errors rather than warning on stock RSQLite")
  })

  # migrate_to_encrypted() now reports the destination's true state.
  with_profile("development", {
    old_db <- make_plain_sqlite(tempfile(fileext = ".db"))
    get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = old_db)),
                   force_new = TRUE)
    res <- migrate_to_encrypted(old_db, backup_dir = tempfile())
    expect_true(res$success)
    expect_false(res$encrypted, info = "migration result does not claim encryption")
    unlink(c(old_db, res$new_path))
  })
}

# SQLite adapter: fail closed with no key, nothing at rest for :memory:
with_profile("regulated", {
  path <- tempfile(fileext = ".db")
  adapter <- SQLiteAdapter$new(list(db_backend = "sqlite", sqlite = list(path = path)))
  expect_error(adapter$connect(), "NOT encrypted", info = "keyless SQLite adapter refused")
  mem <- SQLiteAdapter$new(list(db_backend = "sqlite", sqlite = list(path = ":memory:")))
  con <- mem$connect()
  expect_true(DBI::dbIsValid(con), info = ":memory: holds nothing at rest")
  DBI::dbDisconnect(con)
})

# ---------------------------------------------------------------
# verify_database_encryption(): defect 3.6
# ---------------------------------------------------------------

with_profile("development", {
  plain <- make_plain_sqlite(tempfile(fileext = ".db"))
  v <- verify_database_encryption(db_path = plain, key = generate_db_key())
  expect_false(v$encrypted, info = "plaintext SQLite is not reported encrypted")
  expect_true(v$readable_without_key, info = "the keyless read is what decides it")
  expect_true(grepl("NOT encrypted", v$message))
  unlink(plain)
})

if (duck_ok) {
  with_profile("development", {
    key <- generate_db_key()
    enc <- tempfile(fileext = ".duckdb")
    adapter <- create_db_adapter(list(db_backend = "duckdb",
                                      duckdb = list(path = enc, encryption_key = key)))
    con <- adapter$connect()
    DBI::dbExecute(con, "CREATE TABLE t AS SELECT 'SECRETVALUE' AS v")
    DBI::dbDisconnect(con, shutdown = TRUE)

    v <- verify_database_encryption(db_path = enc, key = key)
    expect_true(v$encrypted,
                info = "a correctly encrypted file now verifies (old byte-ratio check failed it)")
    expect_false(v$readable_without_key)
    expect_identical(v$backend, "duckdb")

    bytes <- readBin(enc, "raw", n = file.size(enc))
    expect_equal(length(grepRaw(charToRaw("SECRETVALUE"), bytes, fixed = TRUE)), 0,
                 info = "no plaintext value in the encrypted DuckDB file")
    unlink(enc)
  })
}

# ---------------------------------------------------------------
# set_encryption_for_existing_db(): defect 3.5
# ---------------------------------------------------------------

if (stock_rsqlite) {
  with_profile("development", {
    plain <- make_plain_sqlite(tempfile(fileext = ".db"))
    before <- unname(tools::md5sum(plain))
    expect_error(set_encryption_for_existing_db(plain), "does not support SQLCipher",
                 info = "stock RSQLite: error instead of a key that was never applied")
    expect_identical(unname(tools::md5sum(plain)), before, info = "original untouched")
    unlink(plain)
  })
}

if (duck_ok) {
  with_profile("development", {
    path <- tempfile(fileext = ".duckdb")
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
    DBI::dbExecute(con, "CREATE TABLE subjects AS SELECT * FROM (VALUES ('S1'), ('S2')) t(subject_id)")
    DBI::dbDisconnect(con, shutdown = TRUE)

    res <- set_encryption_for_existing_db(path)
    expect_true(res$success)
    expect_true(res$encrypted)
    expect_true(file.exists(res$backup_path), info = "plaintext backup kept")

    v <- verify_database_encryption(db_path = path, key = res$new_key)
    expect_true(v$encrypted, info = "rewritten file verifies as encrypted")

    adapter <- create_db_adapter(list(db_backend = "duckdb",
                                      duckdb = list(path = path, encryption_key = res$new_key)))
    con <- adapter$connect()
    rows <- DBI::dbGetQuery(con, "SELECT subject_id FROM subjects ORDER BY subject_id")
    DBI::dbDisconnect(con, shutdown = TRUE)
    expect_identical(rows$subject_id, c("S1", "S2"), info = "data preserved")

    expect_error(set_encryption_for_existing_db(path), "already encrypted")
    unlink(c(path, res$backup_path))
  })

  with_profile("regulated", {
    path <- tempfile(fileext = ".duckdb")
    adapter <- create_db_adapter(list(db_backend = "duckdb", duckdb = list(path = path)))
    expect_error(adapter$connect(), "NOT encrypted",
                 info = "keyless DuckDB file refused under regulated")
  })
}

# ---------------------------------------------------------------
# Adapter capabilities: defect 3.3 (TLS is not encryption at rest)
# ---------------------------------------------------------------

local({
  sq <- SQLiteAdapter$new(list(db_backend = "sqlite", sqlite = list(path = ":memory:")))
  caps <- sq$encryption_capabilities()
  expect_identical(caps$in_transit, "not_applicable")
  if (stock_rsqlite) {
    expect_identical(caps$at_rest, "none")
    expect_false(sq$supports_encryption(),
                 info = "stock RSQLite does not claim encryption support")
  }

  if (requireNamespace("duckdb", quietly = TRUE)) {
    dk <- create_db_adapter(list(db_backend = "duckdb", duckdb = list(path = ":memory:")))
    expect_identical(dk$encryption_capabilities()$at_rest, "package")
    expect_true(dk$supports_encryption())
  }

  pg_caps <- PostgreSQLAdapter$public_methods$encryption_capabilities
  fake <- new.env()
  fake$self <- list(config = list(postgresql = list(sslmode = "verify-full")))
  environment(pg_caps) <- fake
  expect_identical(pg_caps()$at_rest, "server",
                   info = "PostgreSQL at-rest encryption is the server's, not zzedc's")
  expect_identical(pg_caps()$in_transit, "enforced")

  my_caps <- MySQLAdapter$public_methods$encryption_capabilities
  fake$self <- list(config = list(mysql = list(ssl_mode = "PREFERRED")))
  environment(my_caps) <- fake
  expect_identical(my_caps()$at_rest, "server")
  expect_identical(my_caps()$in_transit, "optional",
                   info = "PREFERRED does not require TLS")
})

# ---------------------------------------------------------------
# Password-encrypted exports: defect 3.8
# ---------------------------------------------------------------

local({
  f <- tempfile(fileext = ".csv")
  write.csv(data.frame(name = c("PATIENT_NAME_X", "PATIENT_NAME_Y")), f, row.names = FALSE)
  pw <- "correct horse battery staple"

  enc <- encrypt_export_file(f, pw)
  bytes <- readBin(enc, "raw", n = file.size(enc))
  expect_identical(bytes[1:8], charToRaw("ZZEDCENC"))
  expect_equal(length(grepRaw(charToRaw("PATIENT_NAME"), bytes, fixed = TRUE)), 0,
               info = "no plaintext in the encrypted file")

  out <- decrypt_export_file(enc, pw)
  expect_identical(unname(tools::md5sum(out)), unname(tools::md5sum(f)),
                   info = "round trip is byte-identical")

  expect_error(decrypt_export_file(enc, "wrong password entirely"), "wrong password",
               info = "wrong password detected by the HMAC, nothing written")

  tampered <- tempfile(fileext = ".enc")
  b <- bytes
  b[60] <- xor(b[60], as.raw(1))
  writeBin(b, tampered)
  expect_error(decrypt_export_file(tampered, pw), "modified",
               info = "a single flipped ciphertext bit is detected")

  expect_error(encrypt_export_file(f, "short"), "at least 12",
               info = "short passwords refused")

  empty <- tempfile()
  file.create(empty)
  e2 <- encrypt_export_file(empty, pw)
  expect_equal(file.size(decrypt_export_file(e2, pw)), 0, info = "empty file round trip")
  unlink(c(f, enc, out, tampered, empty, e2))
})

with_profile("development", {
  db <- tempfile(fileext = ".db")
  export_dir <- tempfile("exports_")
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = db)),
                 force_new = TRUE)
  init <- initialize_encrypted_database(db_path = db)
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  con <- connect_encrypted_db(db_path = db)
  DBI::dbWriteTable(con, "pts", data.frame(name = "PATIENT_NAME_Z"))
  DBI::dbDisconnect(con)

  pw <- "a long passphrase for the recipient"
  out <- suppressWarnings(export_encrypted_data(
    "SELECT * FROM pts", format = "csv", password = pw,
    export_dir = export_dir, db_path = db
  ))
  expect_true(grepl("\\.csv\\.enc$", out), info = "password export is a .enc file")
  written <- list.files(export_dir)
  expect_false(any(grepl("\\.csv$", written)),
               info = "no plaintext copy left in the export directory")
  expect_true(verify_exported_data(out)$valid, info = "hash covers the encrypted file")
  dec <- decrypt_export_file(out, pw)
  expect_identical(read.csv(dec)$name, "PATIENT_NAME_Z")

  expect_error(export_encrypted_data("SELECT * FROM pts", password = "short",
                                     export_dir = export_dir, db_path = db),
               "at least 12")

  if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY") else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  unlink(c(db, dec))
  unlink(export_dir, recursive = TRUE)
})

# ---------------------------------------------------------------
# HMAC pseudonymization: defect 3.9
# ---------------------------------------------------------------

local({
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
  old_pk <- Sys.getenv("ZZEDC_PSEUDONYM_KEY", unset = NA)
  on.exit({
    if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY") else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    if (is.na(old_pk)) Sys.unsetenv("ZZEDC_PSEUDONYM_KEY") else Sys.setenv(ZZEDC_PSEUDONYM_KEY = old_pk)
  }, add = TRUE)
  Sys.unsetenv("ZZEDC_PSEUDONYM_KEY")
  db_key <- generate_db_key()
  Sys.setenv(DB_ENCRYPTION_KEY = db_key)

  pk <- get_pseudonymization_key()
  expect_false(identical(pk, .hex_to_raw(db_key)),
               info = "pseudonymization key is not the database key")

  p <- pseudonymize_values(c("SUBJ-001", "SUBJ-001", NA), key = pk)
  expect_identical(p[1], p[2], info = "deterministic, so records stay linkable")
  expect_true(is.na(p[3]))
  expected <- as.character(openssl::sha256("SUBJ-001", key = pk))
  expect_identical(p[1], expected, info = "HMAC-SHA256 under the pseudonymization key")
  old_style <- digest::digest(paste0("SUBJ-001", db_key), algo = "sha256")
  expect_false(identical(p[1], old_style), info = "not the old sha256(value || key)")

  export_dir <- tempfile("pseudo_")
  df <- data.frame(subject_id = c("SUBJ-001", "SUBJ-002"), score = c(10, 20))
  out <- selective_field_export(df, fields_to_pseudonymize = "subject_id",
                                export_dir = export_dir)
  got <- read.csv(out)
  expect_identical(got$subject_id, pseudonymize_values(df$subject_id))
  expect_equal(got$score, df$score, info = "non-selected columns unchanged")
  meta <- jsonlite::read_json(paste0(out, ".metadata.json"))
  expect_identical(meta$pseudonymization_method[[1]], "HMAC-SHA256")

  expect_warning(selective_field_export(df, fields_to_encrypt = "subject_id",
                                        export_dir = export_dir),
                 "deprecated", info = "old argument name still works, with a warning")
  expect_error(selective_field_export(df, fields_to_pseudonymize = "subjectid",
                                      export_dir = export_dir),
               "not found", info = "a misspelled field is an error, not left in the clear")
  unlink(export_dir, recursive = TRUE)
})

# ---------------------------------------------------------------
# KMS fallback: defect 3.12
# ---------------------------------------------------------------

if (!requireNamespace("paws", quietly = TRUE)) {
  local({
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
    on.exit({
      if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY") else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
      clear_encryption_key_cache()
    }, add = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = generate_db_key())
    clear_encryption_key_cache()

    with_profile("regulated", {
      expect_error(get_encryption_key(aws_kms_key_id = "zzedc/test"),
                   "does not allow falling back",
                   info = "regulated: KMS failure is an error")
    })
    with_profile("standard", {
      expect_warning(get_encryption_key(aws_kms_key_id = "zzedc/test"),
                     "falling back", info = "standard: fallback is a warning, not a message")
    })
  })
}

# ---------------------------------------------------------------
# Application startup check
# ---------------------------------------------------------------

if (stock_rsqlite) {
  local({
    old <- options(zzedc.security_profile = NULL)
    on.exit(options(old), add = TRUE)
    plain <- make_plain_sqlite(tempfile(fileext = ".db"))
    reset_encryption_warnings()
    expect_error(
      suppressMessages(check_storage_encryption(plain, config_profile = "regulated")),
      "NOT encrypted", info = "app refuses to start on plaintext SQLite under regulated"
    )
    options(zzedc.security_profile = NULL)
    res <- suppressWarnings(suppressMessages(
      check_storage_encryption(plain, config_profile = "standard")
    ))
    expect_false(res$encrypted)
    expect_identical(getOption("zzedc.security_profile"), "standard",
                     info = "profile fixed for the rest of the session")
    unlink(plain)
  })
}

# ---------------------------------------------------------------
# Validation suite: IQ-008 and scope restoration
# ---------------------------------------------------------------

if (stock_rsqlite) {
  local({
    plain <- make_plain_sqlite(tempfile(fileext = ".db"))
    with_profile("regulated", {
      chk <- .check_deployment_storage(db_path = plain)
      expect_false(chk$passed, info = "IQ-008 fails a plaintext deployment under regulated")
    })
    with_profile("standard", {
      chk <- .check_deployment_storage(db_path = plain)
      expect_true(chk$passed)
      expect_true(grepl("NOT encrypted", chk$message), info = "but still reports the truth")
    })
    unlink(plain)
  })
}

local({
  old_path <- Sys.getenv("ZZEDC_DB_PATH", unset = NA)
  on.exit(if (is.na(old_path)) Sys.unsetenv("ZZEDC_DB_PATH")
          else Sys.setenv(ZZEDC_DB_PATH = old_path), add = TRUE)
  Sys.setenv(ZZEDC_DB_PATH = "")
  chk <- with_profile("standard", .check_deployment_storage())
  expect_true(is.list(chk) && is.logical(chk$passed),
              info = "an empty ZZEDC_DB_PATH no longer aborts IQ-008")
  expect_true(nzchar(get_db_path()), info = "get_db_path() treats empty as unset")
})

local({
  sentinel <- SQLiteAdapter$new(list(db_backend = "sqlite", sqlite = list(path = ":memory:")))
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = ":memory:")),
                 force_new = TRUE)
  zzedc_cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
  assign("adapter", sentinel, envir = zzedc_cache)
  with_profile("regulated", {
    f <- function() {
      .enter_validation_scope()
      get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = tempfile())),
                     force_new = TRUE)
      getOption("zzedc.security_profile")
    }
    expect_identical(f(), "development", info = "functional checks run under development")
    expect_identical(getOption("zzedc.security_profile"), "regulated",
                     info = "profile restored after the validation run")
    expect_identical(get_db_adapter(), sentinel,
                     info = "caller's cached adapter restored after the validation run")
  })
})
