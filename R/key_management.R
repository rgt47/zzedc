#' Encryption Key Custody and Rotation
#'
#' Rules for the keys zzedc uses, and the operations on them.
#'
#' - **Where keys live.** A database key is supplied at runtime, from an
#'   environment variable (`DB_ENCRYPTION_KEY`, referenced in
#'   `config.yml` as `${DB_ENCRYPTION_KEY}`), a secrets manager, or AWS
#'   (`get_encryption_key(aws_kms_key_id = ...)`). It is never written
#'   into `config.yml` or kept beside the database; `check_key_custody()`
#'   enforces that at startup.
#' - **One key per purpose.** The database key, the backup passphrase
#'   (`ZZEDC_BACKUP_PASSPHRASE`), each export's password, and the
#'   pseudonymization key (`get_pseudonymization_key()`, derived
#'   separately from the database key or set as `ZZEDC_PSEUDONYM_KEY`)
#'   are distinct, so disclosing one does not disclose the others.
#' - **Rotation.** `rotate_database_key()` re-encrypts the database
#'   under a new key.
#' - **Loss.** An encrypted database cannot be opened without its key,
#'   and nothing in zzedc can recover it. Keep the key in at least two
#'   places under separate custody (for example a secrets manager and a
#'   sealed record held by the sponsor), and keep previous keys for as
#'   long as backups encrypted under them are retained.
#' - **Access record.** The application records each time it loads the
#'   database key in the audit log (`log_key_access()`), without the
#'   key itself.
#'
#' @name key_management
#' @keywords internal
NULL


#' Check That No Key Is Written into config.yml
#'
#' @param cfg Application configuration (`config::get()`), before
#'   `${VAR}` substitution.
#' @return `invisible(TRUE)`. Under the `regulated` profile, stops when
#'   `database.encryption_key` holds a literal key rather than a
#'   `${VAR}` reference; under `standard`, warns.
#' @export
check_key_custody <- function(cfg) {
  raw <- cfg$database$encryption_key
  if (is.null(raw) || !is.character(raw) || !nzchar(raw) || grepl("^\\$\\{", raw)) {
    return(invisible(TRUE))
  }
  msg <- paste(
    "config.yml contains the database encryption key itself. Anyone who",
    "can read the configuration (or a copy of the project) can decrypt the",
    "study database. Replace it with encryption_key: ${DB_ENCRYPTION_KEY}",
    "and supply the key from the environment or a secrets manager."
  )
  profile <- get_security_profile()
  if (profile == "regulated") stop(msg, call. = FALSE)
  if (profile == "standard") warning(msg, call. = FALSE, immediate. = TRUE)
  invisible(TRUE)
}


#' Record That the Application Loaded the Database Key
#'
#' Writes an `ACCESS` event on the `encryption_key` "table" to the audit
#' log, naming where the key came from. The key itself is never logged.
#'
#' @param source Character: where the key came from, for example
#'   `"environment variable DB_ENCRYPTION_KEY"`.
#' @param user_id Character: recorded as the actor (default `"system"`).
#' @return `invisible(TRUE)` if recorded, `invisible(FALSE)` otherwise
#'   (for example before the audit tables exist).
#' @export
log_key_access <- function(source, user_id = "system") {
  ok <- tryCatch(
    log_audit_event(
      event_type = "ACCESS", table_name = "encryption_key",
      operation = paste("Database encryption key loaded from", source),
      user_id = user_id
    ),
    error = function(e) FALSE
  )
  invisible(isTRUE(ok))
}


#' Where the Application's Database Key Comes From (internal)
#'
#' @param cfg Application configuration, before substitution.
#' @return Description, or `NULL` when no key is configured.
#' @keywords internal
.key_source_description <- function(cfg) {
  raw <- cfg$database$encryption_key
  if (is.null(raw) || !nzchar(raw)) return(NULL)
  m <- regmatches(raw, regexec("^\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}$", raw))[[1]]
  if (length(m) == 2) paste("environment variable", m[2]) else "config.yml"
}


#' Re-encrypt the Study Database under a New Key
#'
#' Run with the application stopped. For DuckDB, the database is copied
#' into a new file encrypted with `new_key` (DuckDB has no in-place
#' rekey), the copy is verified, and it replaces the original; the file
#' as it was is kept beside it until you delete it. For SQLite, this
#' requires an RSQLite build with SQLCipher or SQLite3MultipleCiphers,
#' which re-encrypts in place (`PRAGMA rekey`).
#'
#' @param db_config Adapter configuration (`app_database_config(cfg)`),
#'   holding the current key.
#' @param new_key The new 64-hex-character key (default: a new random
#'   key from `generate_db_key()`).
#'
#' @return A list with `new_key` (store it before discarding the old
#'   one), `previous_copy` (path of the file encrypted under the old key,
#'   for DuckDB), and `message`. Stops with an error, leaving the
#'   database unchanged, if any step fails.
#'
#' @details
#' After rotation, set `DB_ENCRYPTION_KEY` (or the secret) to the new key
#' before starting the application. Keep the old key while any backup
#' made under it is retained: those backups still need it. The rotation
#' is recorded in `key_rotation.log` beside the database and, through
#' the audit log, as a `CONFIG_CHANGE` event; neither records a key.
#'
#' @examples
#' \dontrun{
#'   cfg <- config::get(file = "config.yml")
#'   result <- rotate_database_key(app_database_config(cfg))
#'   result$new_key   # store in the secrets manager, then restart
#' }
#' @export
rotate_database_key <- function(db_config, new_key = generate_db_key()) {
  verify_db_key(new_key)
  backend <- db_config$db_backend
  path <- app_database_path(db_config)
  if (!backend %in% c("sqlite", "duckdb") || is.na(path) || !file.exists(path)) {
    stop("Key rotation applies to an existing SQLite or DuckDB database file.", call. = FALSE)
  }
  old_key <- db_config[[backend]]$encryption_key
  if (is.null(old_key) || !nzchar(old_key)) {
    stop("The configuration has no current encryption key; to encrypt an ",
         "unencrypted database use set_encryption_for_existing_db().", call. = FALSE)
  }
  if (identical(old_key, new_key)) stop("The new key is the same as the current key.", call. = FALSE)

  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  previous_copy <- NA_character_

  if (backend == "duckdb") {
    tmp <- paste0(path, ".rotating")
    unlink(tmp)
    on.exit(unlink(tmp), add = TRUE)
    .encrypt_duckdb_file(path, tmp, new_key, src_key = old_key,
                         extension_directory = db_config$duckdb$extension_directory)
    new_config <- db_config
    new_config$duckdb$encryption_key <- new_key
    new_config$duckdb$path <- tmp
    check <- verify_database_encryption(tmp, key = new_key,
                                        adapter = create_db_adapter(new_config))
    if (!isTRUE(check$encrypted)) {
      stop("The re-encrypted copy failed verification: ", check$message,
           ". The database was not changed.", call. = FALSE)
    }
    previous_copy <- paste0(path, ".pre_rotation_", stamp)
    if (!file.rename(path, previous_copy)) {
      stop("Could not move the current database aside; it was not changed.", call. = FALSE)
    }
    unlink(paste0(path, ".wal"))
    if (!file.rename(tmp, path)) {
      file.rename(previous_copy, path)
      stop("Could not put the re-encrypted database in place; the original was restored.",
           call. = FALSE)
    }
  } else {
    if (!sqlite_cipher_available()) {
      stop("This RSQLite cannot encrypt, so the SQLite database cannot be ",
           "re-keyed; see ?set_encryption_for_existing_db.", call. = FALSE)
    }
    conn <- .connect_sqlite_with_key(path, old_key)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    DBI::dbExecute(conn, sprintf("PRAGMA rekey = '%s'", new_key))
  }

  cat(sprintf("%s\tdatabase key rotated (%s)%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
              backend, if (!is.na(previous_copy)) paste0("\tprevious copy: ", previous_copy) else ""),
      file = file.path(dirname(path), "key_rotation.log"), append = TRUE)

  # Audit event, written through the database under its new key.
  new_config <- db_config
  new_config[[backend]]$encryption_key <- new_key
  local({
    cache <- .db_adapter_cache
    had <- exists("adapter", envir = cache)
    prev <- if (had) cache$adapter else NULL
    adapter <- get_db_adapter(config = new_config, force_new = TRUE)
    on.exit({
      adapter$shutdown()
      if (had) cache$adapter <- prev else if (exists("adapter", envir = cache)) rm("adapter", envir = cache)
    }, add = TRUE)
    tryCatch(log_audit_event(event_type = "CONFIG_CHANGE", table_name = "encryption_key",
                             operation = "Database encryption key rotated", user_id = "system"),
             error = function(e) NULL)
  })

  list(
    new_key = new_key,
    previous_copy = previous_copy,
    message = paste0(
      "Key rotated. Set DB_ENCRYPTION_KEY (or the secret) to the new key before ",
      "starting the application. Keep the old key while backups made under it ",
      "are retained",
      if (!is.na(previous_copy)) paste0("; delete ", previous_copy, " once satisfied") else "",
      "."
    )
  )
}
