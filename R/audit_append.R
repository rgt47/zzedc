#' Audit Trail: Append Path, Database Protection, and External Checkpoints
#'
#' The audit trail (`audit_log`, linked by `audit_chain`) is written
#' through one internal function, `.append_audit_record()`, which runs on
#' the caller's connection so that a data change and its audit record
#' commit or roll back together.
#'
#' Three layers protect the trail:
#'
#' 1. **Hash chain.** Each record's SHA-256 hash covers its content and
#'    the previous record's hash; `verify_audit_integrity()` recomputes
#'    every hash. This detects alteration by anyone who does not also
#'    recompute the later hashes.
#' 2. **Append-only tables.** On SQLite, PostgreSQL, and MySQL/MariaDB,
#'    database triggers reject `UPDATE` and `DELETE` on the audit tables
#'    (`audit_chain` may only have its verification columns updated).
#'    This stops the application, and anyone using its database account
#'    through ordinary SQL, from changing the trail. It does not stop a
#'    database administrator who drops the triggers. DuckDB has no
#'    triggers, so on DuckDB this layer is absent.
#' 3. **External checkpoints.** `audit_checkpoint()` records the chain's
#'    latest position and hash, with an HMAC under a key that is not
#'    stored in the database, in a file outside the database. Rewriting
#'    any record at or before a checkpoint changes the hash at that
#'    position, which `verify_audit_checkpoints()` detects even when the
#'    rewriter recomputed the whole chain. Records after the latest
#'    checkpoint are protected only by layers 1 and 2, so checkpoints
#'    should be frequent (the application writes one at every start when
#'    `audit.checkpoint_dir` is configured; schedule more with cron).
#'    The checkpoint directory should be on storage the database host
#'    cannot rewrite (another machine, or object storage with retention
#'    lock).
#'
#' @name audit_protection
#' @keywords internal
NULL


.audit_event_types <- c(
  "INSERT", "UPDATE", "DELETE", "SELECT", "EXPORT",
  "LOGIN", "LOGOUT", "ACCESS", "SESSION_START", "SESSION_END",
  "LOGIN_FAILED", "PASSWORD_CHANGE", "ROLE_CHANGE",
  "PERMISSION_CHANGE", "LOCKOUT", "UNLOCK",
  "BACKUP", "RESTORE", "MAINTENANCE", "STARTUP", "SHUTDOWN",
  "ERROR", "WARNING",
  "CONFIG_CHANGE", "SETTING_UPDATE", "FEATURE_TOGGLE",
  "SIGNATURE_REQUEST", "SIGNATURE_APPLIED", "SIGNATURE_REJECTED",
  "SIGNATURE_REVOKED",
  "AUDIT_REVIEW", "COMPLIANCE_CHECK", "REPORT_GENERATED",
  "INTEGRITY_VERIFIED",
  "MIGRATION_AUDIT_GAP",
  "RANDOMIZATION", "EMERGENCY_UNBLIND"
)


#' Backend of a DBI Connection or Pool (internal)
#' @param conn A DBI connection or pool.
#' @return `"postgresql"`, `"mysql"`, `"duckdb"`, `"sqlite"`, or `"other"`.
#' @keywords internal
.conn_backend <- function(conn) {
  if (inherits(conn, "Pool")) {
    cls <- tryCatch({
      c <- pool::poolCheckout(conn)
      on.exit(pool::poolReturn(c))
      class(c)
    }, error = function(e) character(0))
  } else {
    cls <- class(conn)
  }
  if (any(cls %in% c("PqConnection", "PostgreSQLConnection"))) return("postgresql")
  if (any(cls %in% c("MariaDBConnection", "MySQLConnection"))) return("mysql")
  if (any(grepl("duckdb", cls, ignore.case = TRUE))) return("duckdb")
  if (any(cls == "SQLiteConnection")) return("sqlite")
  "other"
}


#' Run Code in One Transaction on a Connection or Pool (internal)
#' @param conn A DBI connection or pool.
#' @param fun Function of one argument, the connection.
#' @return The value of `fun`.
#' @keywords internal
.with_db_transaction <- function(conn, fun) {
  if (inherits(conn, "Pool")) {
    pool::poolWithTransaction(conn, fun)
  } else {
    DBI::dbWithTransaction(conn, fun(conn))
  }
}


#' Serialize Appends to the Hash Chain (internal)
#'
#' Two writers that read the same latest hash would both link to it and
#' fork the chain. SQLite and DuckDB serialize writers themselves; on
#' PostgreSQL a transaction-scoped advisory lock and on MySQL/MariaDB a
#' locking read of the chain's last row make concurrent appends take
#' turns. Must be called inside the caller's transaction.
#'
#' @param conn A DBI connection, inside a transaction.
#' @return `invisible(TRUE)`.
#' @keywords internal
.lock_audit_chain <- function(conn) {
  backend <- .conn_backend(conn)
  if (backend == "postgresql") {
    DBI::dbGetQuery(conn, "SELECT pg_advisory_xact_lock(726354901)")
  } else if (backend == "mysql") {
    DBI::dbGetQuery(conn, "SELECT chain_order FROM audit_chain ORDER BY chain_order DESC LIMIT 1 FOR UPDATE")
  }
  invisible(TRUE)
}


#' Append One Record to the Audit Trail (internal)
#'
#' Must run inside a transaction on `conn` (see `.with_db_transaction()`)
#' so the record commits or rolls back with the change it describes.
#' Errors are not caught: a failed append fails the transaction.
#'
#' @param conn A DBI connection, inside a transaction.
#' @param event_type One of the audit event types.
#' @param table_name,record_id,operation,details,user_id,ip_address,session_id
#'   Record content; `NULL` is stored as `NA`.
#' @return The new record's `audit_id`.
#' @keywords internal
.append_audit_record <- function(conn, event_type, table_name, record_id = NULL,
                                 operation, details = NULL, user_id = NULL,
                                 ip_address = NULL, session_id = NULL) {
  s <- function(x) {
    if (is.null(x) || length(x) == 0) NA_character_
    else if (length(x) > 1) paste(x, collapse = "; ")
    else as.character(x)
  }
  event_type <- s(event_type)
  if (!event_type %in% .audit_event_types) {
    stop("Invalid event_type. Must be one of: ", paste(.audit_event_types, collapse = ", "))
  }
  table_name <- s(table_name)
  record_id <- s(record_id)
  operation <- s(operation)
  details <- s(details)
  user_id <- s(user_id)
  ip_address <- s(ip_address)
  session_id <- s(session_id)

  .lock_audit_chain(conn)
  last <- DBI::dbGetQuery(conn, "
    SELECT record_hash, chain_order FROM audit_chain
    ORDER BY chain_order DESC LIMIT 1
  ")
  previous_hash <- if (nrow(last) > 0) last$record_hash[1] else "GENESIS"
  chain_order <- if (nrow(last) > 0) as.integer(last$chain_order[1]) + 1L else 1L

  timestamp <- format(Sys.time(), tz = "UTC", "%Y-%m-%d %H:%M:%S")
  audit_hash <- digest::digest(
    .audit_hash_content(event_type, table_name, record_id, operation, details,
                        user_id, ip_address, session_id, timestamp, previous_hash),
    algo = "sha256"
  )

  insert_sql <- "
    INSERT INTO audit_log
    (timestamp, event_type, table_name, record_id, operation, details,
     user_id, ip_address, session_id, audit_hash, previous_hash)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  values <- list(timestamp, event_type, table_name, record_id, operation, details,
                 user_id, ip_address, session_id, audit_hash, previous_hash)
  audit_id <- if (.conn_backend(conn) == "mysql") {
    DBI::dbExecute(conn, insert_sql, params = values)
    DBI::dbGetQuery(conn, "SELECT LAST_INSERT_ID() AS id")$id[1]
  } else {
    DBI::dbGetQuery(conn, paste(insert_sql, "RETURNING audit_id AS id"), params = values)$id[1]
  }

  DBI::dbExecute(conn, "
    INSERT INTO audit_chain (audit_id, record_hash, previous_hash, chain_order, verified)
    VALUES (?, ?, ?, ?, 1)
  ", params = list(audit_id, audit_hash, previous_hash, chain_order))

  audit_id
}


#' Create the Audit Tables on a Connection (internal)
#'
#' Idempotent. Also installs the append-only triggers
#' (`.protect_audit_tables()`).
#'
#' @param conn A DBI connection.
#' @param adapter Optional `DatabaseAdapter` to resolve dialect-specific
#'   DDL (auto-increment columns) from directly. When `NULL` (the
#'   default), falls back to `get_db_adapter()`'s cached/`config.yml`-
#'   derived adapter -- which is wrong whenever `conn` was opened
#'   before a matching `config.yml` exists (e.g. a brand-new database
#'   being provisioned), since that fallback silently defaults to
#'   SQLite regardless of `conn`'s real backend. A caller that already
#'   holds the adapter that produced `conn` (as
#'   `create_wizard_database()` does) must pass it explicitly to avoid
#'   that mismatch -- confirmed to otherwise fail DuckDB with "syntax
#'   error at or near AUTOINCREMENT" (SQLite's DDL, issued against a
#'   DuckDB connection).
#' @return `invisible(TRUE)`.
#' @keywords internal
.ensure_audit_tables <- function(conn, adapter = NULL) {
  adapter <- adapter %||% get_db_adapter()

  adapter$prepare_auto_increment(conn, "audit_log", "audit_id")
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS audit_log (
      audit_id %s,
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      user_id TEXT,
      event_type TEXT NOT NULL CHECK(event_type IN (%s)),
      table_name TEXT,
      record_id TEXT,
      operation TEXT,
      details TEXT,
      ip_address TEXT,
      session_id TEXT,
      audit_hash TEXT,
      previous_hash TEXT,
      hash_verified BOOLEAN DEFAULT 1,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ", adapter$auto_increment_column("audit_log", "audit_id"),
     paste0("'", .audit_event_types, "'", collapse = ", ")))

  adapter$prepare_auto_increment(conn, "audit_events", "event_id")
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS audit_events (
      event_id %s,
      audit_id INTEGER NOT NULL REFERENCES audit_log(audit_id),
      event_category TEXT,
      event_severity TEXT CHECK(event_severity IN ('info', 'warning', 'error', 'critical')),
      event_message TEXT,
      recovery_action TEXT,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ", adapter$auto_increment_column("audit_events", "event_id")))

  adapter$prepare_auto_increment(conn, "audit_chain", "chain_id")
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS audit_chain (
      chain_id %s,
      audit_id INTEGER NOT NULL UNIQUE REFERENCES audit_log(audit_id),
      record_hash TEXT NOT NULL UNIQUE,
      previous_hash TEXT,
      chain_order INTEGER,
      verified BOOLEAN DEFAULT 1,
      verification_date TIMESTAMP,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ", adapter$auto_increment_column("audit_chain", "chain_id")))

  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_table ON audit_log(table_name)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_date ON audit_log(timestamp)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_event ON audit_log(event_type)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_audit_chain_order ON audit_chain(chain_order)")

  .protect_audit_tables(conn)
  invisible(TRUE)
}


.audit_trigger_names <- c(
  "zzedc_audit_log_no_update", "zzedc_audit_log_no_delete",
  "zzedc_audit_chain_no_update", "zzedc_audit_chain_no_delete",
  "zzedc_audit_events_no_update", "zzedc_audit_events_no_delete"
)


#' Install Append-Only Triggers on the Audit Tables (internal)
#'
#' @param conn A DBI connection.
#' @return The protection now in place (see `audit_protection_status()`).
#'   On MySQL/MariaDB, creating triggers needs the `TRIGGER` privilege
#'   (and, with binary logging, `log_bin_trust_function_creators`); when
#'   it is refused, a warning is issued and the status says so.
#' @keywords internal
.protect_audit_tables <- function(conn) {
  backend <- .conn_backend(conn)
  if (backend == "sqlite") {
    abort <- function(tbl) sprintf("SELECT RAISE(ABORT, '%s is append-only (audit trail)')", tbl)
    stmts <- c(
      sprintf("CREATE TRIGGER IF NOT EXISTS zzedc_audit_log_no_update BEFORE UPDATE ON audit_log BEGIN %s; END", abort("audit_log")),
      sprintf("CREATE TRIGGER IF NOT EXISTS zzedc_audit_log_no_delete BEFORE DELETE ON audit_log BEGIN %s; END", abort("audit_log")),
      sprintf("CREATE TRIGGER IF NOT EXISTS zzedc_audit_chain_no_update BEFORE UPDATE OF audit_id, record_hash, previous_hash, chain_order ON audit_chain BEGIN %s; END", abort("audit_chain")),
      sprintf("CREATE TRIGGER IF NOT EXISTS zzedc_audit_chain_no_delete BEFORE DELETE ON audit_chain BEGIN %s; END", abort("audit_chain")),
      sprintf("CREATE TRIGGER IF NOT EXISTS zzedc_audit_events_no_update BEFORE UPDATE ON audit_events BEGIN %s; END", abort("audit_events")),
      sprintf("CREATE TRIGGER IF NOT EXISTS zzedc_audit_events_no_delete BEFORE DELETE ON audit_events BEGIN %s; END", abort("audit_events"))
    )
    for (s in stmts) DBI::dbExecute(conn, s)
  } else if (backend == "postgresql") {
    DBI::dbExecute(conn, "
      CREATE OR REPLACE FUNCTION zzedc_audit_append_only() RETURNS trigger
      LANGUAGE plpgsql AS $f$
      BEGIN
        RAISE EXCEPTION '% is append-only (audit trail)', TG_TABLE_NAME;
      END;
      $f$")
    existing <- DBI::dbGetQuery(conn, "SELECT tgname FROM pg_trigger WHERE NOT tgisinternal")$tgname
    defs <- c(
      zzedc_audit_log_no_update = "BEFORE UPDATE OR DELETE ON audit_log FOR EACH ROW",
      zzedc_audit_log_no_delete = "BEFORE TRUNCATE ON audit_log FOR EACH STATEMENT",
      zzedc_audit_chain_no_update = "BEFORE UPDATE OF audit_id, record_hash, previous_hash, chain_order OR DELETE ON audit_chain FOR EACH ROW",
      zzedc_audit_chain_no_delete = "BEFORE TRUNCATE ON audit_chain FOR EACH STATEMENT",
      zzedc_audit_events_no_update = "BEFORE UPDATE OR DELETE ON audit_events FOR EACH ROW",
      zzedc_audit_events_no_delete = "BEFORE TRUNCATE ON audit_events FOR EACH STATEMENT"
    )
    for (nm in setdiff(names(defs), existing)) {
      DBI::dbExecute(conn, sprintf("CREATE TRIGGER %s %s EXECUTE FUNCTION zzedc_audit_append_only()",
                                   nm, defs[[nm]]))
    }
  } else if (backend == "mysql") {
    existing <- tryCatch(
      DBI::dbGetQuery(conn, "SELECT TRIGGER_NAME AS n FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE()")$n,
      error = function(e) character(0)
    )
    sig <- function(tbl) sprintf("SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '%s is append-only (audit trail)'", tbl)
    defs <- c(
      zzedc_audit_log_no_update = sprintf("BEFORE UPDATE ON audit_log FOR EACH ROW %s", sig("audit_log")),
      zzedc_audit_log_no_delete = sprintf("BEFORE DELETE ON audit_log FOR EACH ROW %s", sig("audit_log")),
      zzedc_audit_chain_no_update = sprintf(paste(
        "BEFORE UPDATE ON audit_chain FOR EACH ROW BEGIN",
        "IF NOT (NEW.audit_id <=> OLD.audit_id AND NEW.record_hash <=> OLD.record_hash",
        "AND NEW.previous_hash <=> OLD.previous_hash AND NEW.chain_order <=> OLD.chain_order)",
        "THEN %s; END IF; END"), sig("audit_chain")),
      zzedc_audit_chain_no_delete = sprintf("BEFORE DELETE ON audit_chain FOR EACH ROW %s", sig("audit_chain")),
      zzedc_audit_events_no_update = sprintf("BEFORE UPDATE ON audit_events FOR EACH ROW %s", sig("audit_events")),
      zzedc_audit_events_no_delete = sprintf("BEFORE DELETE ON audit_events FOR EACH ROW %s", sig("audit_events"))
    )
    for (nm in setdiff(names(defs), existing)) {
      tryCatch(
        DBI::dbExecute(conn, sprintf("CREATE TRIGGER %s %s", nm, defs[[nm]])),
        error = function(e) warning(
          "Could not install the audit append-only trigger ", nm, ": ", conditionMessage(e),
          ". Grant the TRIGGER privilege (and set log_bin_trust_function_creators ",
          "if binary logging is on), or have a DBA create it.", call. = FALSE)
      )
    }
  }
  audit_protection_status(conn)
}


#' How the Audit Tables Are Protected Against Change
#'
#' @param conn A DBI connection or pool to the study database.
#' @return `"database triggers"` when every append-only trigger is
#'   installed; `"partial triggers"` when some are; `"none"` otherwise.
#'   Always `"none"` on DuckDB, which has no triggers.
#' @export
audit_protection_status <- function(conn) {
  backend <- .conn_backend(conn)
  q <- switch(backend,
    sqlite = "SELECT name AS n FROM sqlite_master WHERE type = 'trigger'",
    postgresql = "SELECT tgname AS n FROM pg_trigger WHERE NOT tgisinternal",
    mysql = "SELECT TRIGGER_NAME AS n FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE()",
    NULL
  )
  if (is.null(q)) return("none")
  have <- tryCatch(DBI::dbGetQuery(conn, q)$n, error = function(e) character(0))
  n <- sum(.audit_trigger_names %in% have)
  if (n == length(.audit_trigger_names)) "database triggers" else if (n > 0) "partial triggers" else "none"
}


# ---------------------------------------------------------------------
# External checkpoints
# ---------------------------------------------------------------------

.checkpoint_canonical <- function(cp) {
  paste(cp$created_at, cp$database, cp$chain_order, cp$audit_id, cp$record_hash, sep = "|")
}


#' Record the Audit Chain's Position Outside the Database
#'
#' Appends one line to `audit_checkpoints.jsonl` in `checkpoint_dir`:
#' the chain's latest position, record, and hash, with an HMAC-SHA256
#' under `key`. See `?audit_protection` for what this protects against.
#'
#' @param checkpoint_dir Directory for the checkpoint file. It should be
#'   on storage the database host cannot rewrite.
#' @param key The checkpoint HMAC key (default: environment variable
#'   `ZZEDC_AUDIT_CHECKPOINT_KEY`). It must not be stored in the
#'   database or `config.yml`. With no key the checkpoint is written
#'   unkeyed and is only as trustworthy as the place it is stored.
#' @param conn A DBI connection or pool to the study database; when
#'   `NULL`, one is opened with `connect_encrypted_db(db_path)`.
#' @param db_path Database path, used when `conn` is `NULL`.
#' @param database A label for the database recorded in the checkpoint
#'   (default: the file name, or `"study"`).
#'
#' @return The checkpoint (a list), invisibly; `NULL` when the chain is
#'   empty.
#'
#' @examples
#' \dontrun{
#'   audit_checkpoint("/mnt/audit-checkpoints")
#'   verify_audit_checkpoints("/mnt/audit-checkpoints/audit_checkpoints.jsonl")
#' }
#' @export
audit_checkpoint <- function(checkpoint_dir,
                             key = Sys.getenv("ZZEDC_AUDIT_CHECKPOINT_KEY"),
                             conn = NULL, db_path = NULL, database = NULL) {
  if (is.null(conn)) {
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
  }
  head <- DBI::dbGetQuery(conn, "
    SELECT chain_order, audit_id, record_hash FROM audit_chain
    ORDER BY chain_order DESC LIMIT 1
  ")
  if (nrow(head) == 0) return(invisible(NULL))
  if (!dir.exists(checkpoint_dir)) dir.create(checkpoint_dir, recursive = TRUE)

  cp <- list(
    created_at = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
    database = database %||% if (!is.null(db_path)) basename(db_path) else "study",
    chain_order = as.integer(head$chain_order[1]),
    audit_id = as.character(head$audit_id[1]),
    record_hash = as.character(head$record_hash[1])
  )
  cp$keyed <- nzchar(key)
  cp$mac <- if (cp$keyed) {
    as.character(openssl::sha256(.checkpoint_canonical(cp), key = key))
  } else {
    digest::digest(.checkpoint_canonical(cp), algo = "sha256", serialize = FALSE)
  }
  cat(as.character(jsonlite::toJSON(cp, auto_unbox = TRUE)), "\n", sep = "",
      file = file.path(checkpoint_dir, "audit_checkpoints.jsonl"), append = TRUE)
  invisible(cp)
}


#' Verify the Audit Trail Against Its External Checkpoints
#'
#' For each checkpoint: checks its HMAC, then checks that the database's
#' chain still has the same record and hash at that position. Also runs
#' `verify_audit_integrity()` over the whole chain.
#'
#' @param checkpoint_file Path to `audit_checkpoints.jsonl`.
#' @param key The checkpoint HMAC key (default:
#'   `ZZEDC_AUDIT_CHECKPOINT_KEY`).
#' @param db_path Database path (default: the configured database).
#'
#' @return A list: `valid` (logical), `checkpoints_checked`,
#'   `failures` (data frame of failing checkpoints and why),
#'   `chain_valid`, and `message`.
#' @export
verify_audit_checkpoints <- function(checkpoint_file,
                                     key = Sys.getenv("ZZEDC_AUDIT_CHECKPOINT_KEY"),
                                     db_path = NULL) {
  lines <- readLines(checkpoint_file, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  conn <- connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  failures <- data.frame(line = integer(), chain_order = integer(), reason = character())
  for (i in seq_along(lines)) {
    cp <- tryCatch(jsonlite::fromJSON(lines[i]), error = function(e) NULL)
    if (is.null(cp)) {
      failures[nrow(failures) + 1, ] <- list(i, NA_integer_, "unreadable checkpoint line")
      next
    }
    expected <- if (isTRUE(cp$keyed)) {
      if (!nzchar(key)) {
        failures[nrow(failures) + 1, ] <- list(i, cp$chain_order, "keyed checkpoint but no key supplied")
        next
      }
      as.character(openssl::sha256(.checkpoint_canonical(cp), key = key))
    } else {
      digest::digest(.checkpoint_canonical(cp), algo = "sha256", serialize = FALSE)
    }
    if (!identical(expected, cp$mac)) {
      failures[nrow(failures) + 1, ] <- list(i, cp$chain_order, "checkpoint MAC does not match (checkpoint altered or wrong key)")
      next
    }
    row <- DBI::dbGetQuery(conn, "SELECT audit_id, record_hash FROM audit_chain WHERE chain_order = ?",
                           params = list(as.integer(cp$chain_order)))
    if (nrow(row) == 0) {
      failures[nrow(failures) + 1, ] <- list(i, cp$chain_order, "chain position no longer exists (records removed)")
    } else if (!identical(as.character(row$record_hash[1]), cp$record_hash) ||
               !identical(as.character(row$audit_id[1]), as.character(cp$audit_id))) {
      failures[nrow(failures) + 1, ] <- list(i, cp$chain_order, "hash at this position differs (records rewritten)")
    }
  }
  chain <- verify_audit_integrity(db_path = db_path)
  valid <- nrow(failures) == 0 && isTRUE(chain$valid)
  list(
    valid = valid,
    checkpoints_checked = length(lines),
    failures = failures,
    chain_valid = isTRUE(chain$valid),
    message = if (valid) {
      paste("Audit trail matches all", length(lines), "checkpoints and the chain verifies.")
    } else {
      paste0(nrow(failures), " checkpoint failure(s); chain ", if (isTRUE(chain$valid)) "verifies" else "does NOT verify", ".")
    }
  )
}


#' Client Address and Session Token for Audit Records
#'
#' @param session A Shiny session, or `NULL`.
#' @return A list with `ip_address` and `session_id` (each `NULL` when
#'   unknown). Behind a reverse proxy on the same machine, the client
#'   address is taken from the first `X-Forwarded-For` entry; the header
#'   is ignored from any other peer, which could set it to anything (the
#'   same rule as `session_https_status()`).
#' @export
session_audit_context <- function(session) {
  if (is.null(session)) return(list(ip_address = NULL, session_id = NULL))
  req <- tryCatch(session$request, error = function(e) NULL)
  remote <- req$REMOTE_ADDR %||% NULL
  forwarded <- req$HTTP_X_FORWARDED_FOR %||% ""
  ip <- if (!is.null(remote) && remote %in% c("127.0.0.1", "::1") && nzchar(forwarded)) {
    trimws(strsplit(forwarded, ",", fixed = TRUE)[[1]][1])
  } else {
    remote
  }
  list(ip_address = ip, session_id = tryCatch(session$token, error = function(e) NULL))
}
