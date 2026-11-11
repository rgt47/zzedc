#' Restoring a Study Database from a Backup
#'
#' A restore replaces the study database file. That cannot be done
#' safely while the application has the file open: its connection pool
#' is shared by every session, SQLite and DuckDB keep recent writes in a
#' separate write-ahead log beside the file, and a pool cannot be
#' reopened once closed. Before 2026-11-11 the Backup tab copied the
#' backup over the open file and then closed the shared pool, which
#' risked a corrupt database and left every session without a
#' connection.
#'
#' A restore is therefore done in two steps. `request_database_restore()`
#' (the Backup tab's Restore button) checks the backup and stages it
#' beside the database. `apply_pending_restore()`, which `launch_zzedc()`
#' and the application call at startup before any connection is opened,
#' keeps a copy of the current database (with its write-ahead log),
#' removes the old write-ahead log, and puts the backup in place.
#'
#' @name database_restore
#' @keywords internal
NULL

.restore_pending_path <- function(db_path) paste0(db_path, ".restore-pending")
.restore_record_path <- function(db_path) paste0(db_path, ".restore-pending.json")

# Files that belong to a database besides the main file: SQLite's
# write-ahead log, shared-memory index, and rollback journal; DuckDB's
# write-ahead log.
.db_companion_files <- function(db_path) {
  paste0(db_path, c("-wal", "-shm", "-journal", ".wal"))
}


#' Stage a Backup to Replace the Study Database at Next Start
#'
#' @param backup_file Character: path to a backup made by the Backup tab
#'   (`.db`, optionally gzip-compressed `.db.gz`).
#' @param db_path Character: path to the study database file.
#' @param backend Character: `"sqlite"` or `"duckdb"`.
#' @param requested_by Character: user recorded with the request.
#' @param passphrase Passphrase for an encrypted backup (`.enc`); defaults
#'   to the `ZZEDC_BACKUP_PASSPHRASE` environment variable.
#'
#' @return Invisibly, a list with `staged` (path of the staged file) and
#'   `message`. Stops with an error if the backup is missing, cannot be
#'   decrypted, or is not a database of the study's backend; nothing is
#'   staged in that case.
#'
#' @export
request_database_restore <- function(backup_file, db_path, backend = "sqlite",
                                     requested_by = NA_character_,
                                     passphrase = backup_passphrase()) {
  if (!backend %in% c("sqlite", "duckdb")) {
    stop("File restore applies to the SQLite and DuckDB backends only.", call. = FALSE)
  }
  if (!file.exists(backup_file)) {
    stop("Backup file not found: ", backup_file, call. = FALSE)
  }

  staged <- .restore_pending_path(db_path)
  tmp <- paste0(staged, ".tmp")
  unlink(tmp)

  # Undo the backup's layers in reverse: decrypt (.enc), then
  # decompress (.gz).
  source_file <- backup_file
  if (grepl("\\.enc$", source_file)) {
    if (is.null(passphrase)) {
      stop("This backup is encrypted; set ZZEDC_BACKUP_PASSPHRASE to its passphrase.",
           call. = FALSE)
    }
    decrypted <- tempfile(fileext = sub("\\.enc$", "", basename(source_file)))
    on.exit(unlink(decrypted), add = TRUE)
    decrypt_export_file(source_file, passphrase, output_path = decrypted)
    source_file <- decrypted
  }
  if (grepl("\\.gz$", source_file)) {
    R.utils::gunzip(source_file, destname = tmp, remove = FALSE, overwrite = TRUE)
  } else {
    file.copy(source_file, tmp, overwrite = TRUE)
  }

  # Refuse a file that is not a database of this study's backend. An
  # encrypted SQLite file has no recognizable header ("unknown"), so
  # that is accepted only where an encrypted SQLite file is possible
  # (an RSQLite that can encrypt) and the size is a whole number of
  # 512-byte units, as every SQLite page size is.
  format <- .detect_db_file_format(tmp)
  plausible_encrypted_sqlite <- identical(format, "unknown") &&
    sqlite_cipher_available() && file.size(tmp) %% 512 == 0
  ok <- if (backend == "duckdb") {
    identical(format, "duckdb")
  } else {
    identical(format, "sqlite") || plausible_encrypted_sqlite
  }
  if (!ok) {
    unlink(tmp)
    stop("The backup is not a ", backend, " database (detected: ",
         if (is.na(format)) "empty file" else format, ").", call. = FALSE)
  }

  file.rename(tmp, staged)
  jsonlite::write_json(list(
    source = normalizePath(backup_file, mustWork = FALSE),
    requested_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    requested_by = requested_by,
    backend = backend
  ), .restore_record_path(db_path), auto_unbox = TRUE, pretty = TRUE)

  invisible(list(
    staged = staged,
    message = paste(
      "Restore staged. It will be applied the next time the application",
      "starts; the current database will be kept as a pre-restore copy."
    )
  ))
}


#' Apply a Staged Restore Before the Database Is Opened
#'
#' @param db_config Adapter configuration (`app_database_config()`).
#'
#' @return Invisibly, a list with `applied` (logical), and when applied,
#'   `pre_restore_dir` (where the replaced database and its write-ahead
#'   log were kept) and `source`.
#'
#' @details
#' Must run before any connection to the database is opened; the
#' launcher and the application's `global.R` call it first. If anything
#' fails before the swap, the current database is left as it was and the
#' staged file remains for another attempt.
#'
#' @export
apply_pending_restore <- function(db_config) {
  db_path <- app_database_path(db_config)
  if (is.na(db_path)) {
    return(invisible(list(applied = FALSE)))
  }
  staged <- .restore_pending_path(db_path)
  if (!file.exists(staged)) {
    return(invisible(list(applied = FALSE)))
  }
  record_file <- .restore_record_path(db_path)
  record <- if (file.exists(record_file)) {
    tryCatch(jsonlite::read_json(record_file), error = function(e) list())
  } else {
    list()
  }

  # Keep the current database, with its write-ahead log and other
  # companion files, so it can be recovered as it stood.
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  keep_dir <- file.path(dirname(db_path), paste0("pre_restore_", stamp))
  dir.create(keep_dir, recursive = TRUE, showWarnings = FALSE)
  existing <- c(db_path, .db_companion_files(db_path))
  existing <- existing[file.exists(existing)]
  if (length(existing) > 0) {
    copied <- file.copy(existing, keep_dir, overwrite = FALSE)
    if (!all(copied)) {
      stop("Could not keep a copy of the current database in ", keep_dir,
           "; the restore was not applied.", call. = FALSE)
    }
  }

  # A write-ahead log left beside the restored file would be replayed
  # into it; remove the old one before the swap.
  unlink(.db_companion_files(db_path))
  if (file.exists(db_path) && !file.remove(db_path)) {
    stop("Could not remove the current database file; the restore was not applied.",
         call. = FALSE)
  }
  if (!file.rename(staged, db_path)) {
    file.copy(file.path(keep_dir, basename(db_path)), db_path)
    stop("Could not move the staged backup into place; the previous ",
         "database was put back.", call. = FALSE)
  }
  unlink(record_file)

  history <- file.path(dirname(db_path), "restore_history.log")
  cat(sprintf("%s\trestored from %s\trequested by %s at %s\tprevious database kept in %s\n",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
              record$source %||% "unknown", record$requested_by %||% "unknown",
              record$requested_at %||% "unknown", keep_dir),
      file = history, append = TRUE)
  message("Applied staged restore: ", db_path, " replaced from ",
          record$source %||% "backup", "; previous database kept in ", keep_dir)

  invisible(list(applied = TRUE, pre_restore_dir = keep_dir,
                 source = record$source %||% NA_character_))
}


#' Backup Encryption Passphrase
#'
#' Backups are encrypted when the `ZZEDC_BACKUP_PASSPHRASE` environment
#' variable is set (at least 12 characters), with the same scheme as
#' password-encrypted exports (AES-256-CTR with an HMAC-SHA256 tag; key
#' derived with bcrypt-pbkdf; see `encrypt_export_file()`). The
#' passphrase is separate from the database key, so a backup can be
#' protected and moved without the key that opens the live database.
#'
#' @return The passphrase, or `NULL` when it is not set.
#' @export
backup_passphrase <- function() {
  p <- Sys.getenv("ZZEDC_BACKUP_PASSPHRASE", unset = "")
  if (nzchar(p)) p else NULL
}


#' Check a Backup Against the Security Profile (internal)
#'
#' A backup of a database that is not encrypted at rest contains every
#' record in readable form. Under the `regulated` profile such a backup
#' must be encrypted, so without a passphrase it is refused before
#' anything is written.
#'
#' @param db_encrypted Logical: whether the database file is encrypted
#'   at rest (in which case its copy is already ciphertext).
#' @param passphrase The backup passphrase, or `NULL`.
#' @return `invisible(TRUE)`; stops under `regulated` when the backup
#'   would be plaintext.
#' @keywords internal
check_backup_policy <- function(db_encrypted, passphrase) {
  if (!isTRUE(db_encrypted) && is.null(passphrase) &&
      get_security_profile() == "regulated") {
    stop("The 'regulated' security profile does not allow an unencrypted ",
         "backup of an unencrypted database. Set ZZEDC_BACKUP_PASSPHRASE ",
         "(at least 12 characters) so backups are encrypted.", call. = FALSE)
  }
  invisible(TRUE)
}


#' Compress and Encrypt a Backup File (internal)
#'
#' @param path The uncompressed backup (`.db`).
#' @param compress Logical: gzip it.
#' @param passphrase Encrypt with this passphrase when not `NULL`.
#' @return The final path (`.db`, `.db.gz`, `.db.enc`, or
#'   `.db.gz.enc`); intermediate files are removed.
#' @keywords internal
finalize_backup_file <- function(path, compress = FALSE, passphrase = NULL) {
  if (isTRUE(compress)) {
    R.utils::gzip(path, destname = paste0(path, ".gz"), remove = TRUE, overwrite = TRUE)
    path <- paste0(path, ".gz")
  }
  if (!is.null(passphrase)) {
    enc <- paste0(path, ".enc")
    encrypt_export_file(path, passphrase, output_path = enc)
    unlink(path)
    path <- enc
  }
  path
}


#' Make a Consistent Backup of an Open Study Database (internal)
#'
#' SQLite: `VACUUM INTO`, which writes a complete, consistent copy
#' through the open connection, including commits still in the
#' write-ahead log (a plain file copy can miss them). DuckDB:
#' `CHECKPOINT`, then a file copy.
#'
#' @param db_pool The application's pool.
#' @param db_path The database file.
#' @param backend `"sqlite"` or `"duckdb"`.
#' @param dest Destination file (must not exist).
#' @return `invisible(dest)`.
#' @keywords internal
create_database_backup <- function(db_pool, db_path, backend, dest) {
  unlink(dest)
  if (backend == "sqlite" && !is.null(db_pool)) {
    pool::dbExecute(db_pool, sprintf("VACUUM INTO '%s'", gsub("'", "''", dest)))
  } else {
    if (backend == "duckdb" && !is.null(db_pool)) {
      pool::dbExecute(db_pool, "CHECKPOINT")
    }
    if (!file.copy(db_path, dest, overwrite = TRUE)) {
      stop("Could not copy the database file to ", dest, call. = FALSE)
    }
  }
  invisible(dest)
}
