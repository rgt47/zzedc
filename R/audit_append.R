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


#' Rebuild `audit_log`'s `event_type` `CHECK` Constraint (Defect 11)
#'
#' Defect 11 (zzedc-modernization-whitepaper-2026-11-13.md, Section
#' 2.2): `.ensure_audit_tables()`'s `CREATE TABLE IF NOT EXISTS
#' audit_log (...)` bakes the allowed `event_type` values into a
#' `CHECK` constraint at the moment the table is first created, and
#' `IF NOT EXISTS` is a no-op on every later call -- so a database
#' created before a new event type was added to `.audit_event_types`
#' (`RANDOMIZATION`/`EMERGENCY_UNBLIND`, added in `4c802dc`) keeps
#' its original, now-stale constraint forever. The practical effect:
#' logging one of those newer event types against such a database
#' fails outright with a `CHECK` constraint violation, not a graceful
#' degradation -- confirmed directly, by creating a database with the
#' old-style constraint and attempting a `RANDOMIZATION` insert
#' against it.
#'
#' Idempotent and safe to call unconditionally at the same points
#' `.ensure_audit_tables()`/schema-initialization already run: it
#' first checks whether the stored constraint already covers every
#' current `.audit_event_types` value and returns immediately if so,
#' so a database created (or already migrated) under the current
#' event type list pays only the cost of that one check.
#'
#' SQLite and DuckDB have no `ALTER TABLE ... DROP/ADD CONSTRAINT`
#' (confirmed directly: DuckDB raises "Not implemented ... No support
#' for that ALTER TABLE option yet!"), so both rebuild the table
#' rather than alter it in place, via SQLite's own documented
#' procedure for schema changes a plain `ALTER TABLE` cannot express:
#' create the replacement under a temporary name, copy every row
#' across by explicit column list (preserving `audit_id` values
#' exactly, since `audit_events.audit_id` and `audit_chain.audit_id`
#' both hold foreign keys to them), drop the original, then rename
#' the replacement into place.
#'
#' On SQLite, only `audit_log` itself needs rebuilding: at no point
#' does the name `audit_log` stop existing except between the `DROP`
#' and the final `RENAME`, both inside the same transaction, and the
#' original is never renamed away first (which would risk SQLite
#' silently rewriting `audit_events`'/`audit_chain`'s `REFERENCES
#' audit_log(...)` clauses to point at the archived table instead).
#' `PRAGMA foreign_keys` must also be turned off around the whole
#' operation (and, being a documented no-op inside a transaction, set
#' before `.with_db_transaction()` opens one): with it on (the
#' default this package connects with), `DROP TABLE audit_log` itself
#' fails outright -- confirmed directly -- because `audit_events`/
#' `audit_chain` still reference it. SQLite's append-only triggers
#' (`.audit_trigger_names`) are owned by the table they are defined
#' on and so do not survive a `DROP TABLE`; `.protect_audit_tables()`
#' re-creates them (via `CREATE TRIGGER IF NOT EXISTS`) once the
#' rebuild is complete.
#'
#' DuckDB has no `PRAGMA foreign_keys` equivalent at all (confirmed:
#' no such setting appears in `duckdb_settings()`) and refuses to
#' drop `audit_log` outright while `audit_events`/`audit_chain` still
#' reference it ("Catalog Error: Could not drop the table because
#' this table is main key table of the table 'audit_events'",
#' confirmed directly); it also refuses to rename a from-scratch
#' replacement table into place while anything still references it
#' ("Dependency Error: Cannot alter entry ... because there are
#' entries that depend on it", confirmed directly, rebuilding all
#' three tables under temporary names and renaming them into place
#' the same way SQLite does for `audit_log` alone). So for DuckDB,
#' all three tables' data is copied out to plain staging tables with
#' no constraints and no foreign keys between them -- nothing ever
#' depends on a staging table, so neither dropping nor leaving one
#' behind is blocked -- the three originals are then dropped (in
#' dependency order), the three real tables are created fresh
#' directly under their final names with the updated `CHECK`, and the
#' data is copied back in from staging. DuckDB has no append-only
#' triggers to restore either way (`.protect_audit_tables()` is a
#' no-op for it; append-only protection is currently
#' SQLite/PostgreSQL/MySQL only).
#'
#' PostgreSQL and MySQL/MariaDB support `ALTER TABLE ... DROP
#' CONSTRAINT`/`ADD CONSTRAINT ... CHECK (...)` directly, so both look
#' up the constraint's name (auto-generated, since none of the three
#' original `CREATE TABLE` statements in this package name it
#' explicitly) from the catalog and replace it in one statement (both
#' clauses comma-separated) -- no table rebuild needed. If the name
#' cannot be found, this is a `stop()`, not a silent no-op: a database
#' this function cannot locate the constraint on is left exactly as
#' stale as one it was never called on, and a return value alone
#' would not say so. This path is inspected, not verified against a
#' live server (none was reachable in this session) -- in particular,
#' whether MariaDB (as opposed to MySQL 8, where `DROP CHECK`/`DROP
#' CONSTRAINT` are both documented) accepts `DROP CONSTRAINT` for an
#' inline column-level `CHECK` has not been confirmed. The SQLite and
#' DuckDB paths are both verified end to end, including through the
#' package's own `log_audit_event()`/`.protect_audit_tables()`/
#' `verify_audit_integrity()` on SQLite (not just hand-built schema
#' and synthetic hashes), that a `RANDOMIZATION` event the old
#' constraint rejected is accepted after migration and that every
#' pre-existing row (and, on SQLite, its real hash chain) survives
#' unchanged.
#'
#' @param conn A DBI connection or pool.
#' @param adapter Optional pre-built adapter (as `.ensure_audit_tables()`
#'   accepts); resolved via `get_db_adapter()` if omitted.
#' @return `invisible(TRUE)`.
#' @export
migrate_audit_event_types <- function(conn, adapter = NULL) {
  adapter <- adapter %||% get_db_adapter()
  # Resolved once and used for everything below, including the
  # SQLite PRAGMA toggle: `PRAGMA foreign_keys` is connection-scoped,
  # so toggling it on a pool object (which can hand out any
  # connection on each call) risks setting it on one physical
  # connection while `.with_db_transaction()`'s `poolWithTransaction()`
  # runs on another, and restoring it on a third -- the PRAGMA would
  # never actually be off where the transaction runs. Checking out a
  # single connection up front and using it throughout (returned via
  # `on.exit()` either way) avoids that.
  is_pool <- inherits(conn, "Pool")
  work_conn <- if (is_pool) pool::poolCheckout(conn) else conn
  if (is_pool) on.exit(pool::poolReturn(work_conn), add = TRUE)

  backend <- .conn_backend(work_conn)
  expected_list <- paste0("'", .audit_event_types, "'", collapse = ", ")

  if (!DBI::dbExistsTable(work_conn, "audit_log")) {
    return(invisible(TRUE))
  }

  current_check <- .audit_log_check_text(work_conn, backend)
  # Matched as a quoted token ('TYPE'), not a bare substring: TYPE
  # itself (unquoted) can appear anywhere in the CREATE TABLE text
  # (e.g. in a column's own type name), and some event types are
  # substrings of others (LOGIN of LOGIN_FAILED, UPDATE of
  # SETTING_UPDATE), so a bare grepl() would false-positive on a
  # constraint that does not actually list that event type.
  if (!is.null(current_check) &&
        all(vapply(.audit_event_types,
                   function(e) grepl(paste0("'", e, "'"), current_check, fixed = TRUE),
                   logical(1)))) {
    return(invisible(TRUE))
  }

  if (backend == "sqlite") {
    # SQLite enforces `audit_events`/`audit_chain`'s `REFERENCES
    # audit_log(audit_id)` on every statement when `PRAGMA
    # foreign_keys = ON` (set at connect time by
    # SQLiteAdapter$connect()) -- including DROP TABLE audit_log
    # below, which fails outright with "FOREIGN KEY constraint
    # failed" while other tables still reference it. This PRAGMA is
    # a documented no-op if toggled inside a transaction, so it must
    # be set here, before `.with_db_transaction()` opens one, and
    # restored (to whatever it was before, not assumed to be ON)
    # after it closes.
    prior_fk <- DBI::dbGetQuery(work_conn, "PRAGMA foreign_keys")[[1]][1]
    DBI::dbExecute(work_conn, "PRAGMA foreign_keys = OFF")
    # `after = FALSE`: must run before poolReturn() (registered
    # above, when work_conn was checked out) restores this
    # connection to the pool -- otherwise the PRAGMA is restored on a
    # connection some other caller may already be using.
    on.exit(DBI::dbExecute(work_conn, sprintf("PRAGMA foreign_keys = %d", prior_fk)),
            add = TRUE, after = FALSE)

    .with_db_transaction(work_conn, function(c) {
      adapter$prepare_auto_increment(c, "audit_log", "audit_id")
      DBI::dbExecute(c, sprintf("
        CREATE TABLE zzedc_audit_log_rebuild (
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
      ", adapter$auto_increment_column("audit_log", "audit_id"), expected_list))

      DBI::dbExecute(c, "
        INSERT INTO zzedc_audit_log_rebuild (
          audit_id, timestamp, user_id, event_type, table_name, record_id,
          operation, details, ip_address, session_id, audit_hash,
          previous_hash, hash_verified, created_date
        )
        SELECT
          audit_id, timestamp, user_id, event_type, table_name, record_id,
          operation, details, ip_address, session_id, audit_hash,
          previous_hash, hash_verified, created_date
        FROM audit_log
      ")

      DBI::dbExecute(c, "DROP TABLE audit_log")
      DBI::dbExecute(c, "ALTER TABLE zzedc_audit_log_rebuild RENAME TO audit_log")

      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)")
      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_table ON audit_log(table_name)")
      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_date ON audit_log(timestamp)")
      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_event ON audit_log(event_type)")
      .protect_audit_tables(c)
    })
  } else if (backend == "duckdb") {
    # DuckDB has no `PRAGMA foreign_keys = OFF` equivalent (no such
    # setting exists among `duckdb_settings()`) and refuses to drop
    # `audit_log` while `audit_events`/`audit_chain` still reference
    # it (confirmed directly: "Catalog Error: Could not drop the
    # table because this table is main key table of the table
    # 'audit_events'"). It also refuses to rename a replacement table
    # into place while anything still depends on *it* (confirmed
    # directly: renaming a from-scratch "audit_log" replacement
    # failed with "Dependency Error: Cannot alter entry ... because
    # there are entries that depend on it" while the from-scratch
    # replacement "audit_events"/"audit_chain" tables' foreign keys
    # still pointed at it) -- so the three-table rebuild used for
    # SQLite's single table does not work here even extended to all
    # three.
    #
    # Instead, all three tables' data is copied into plain staging
    # tables with no constraints and no foreign keys between them
    # (nothing depends on a staging table, so dropping or leaving it
    # behind is never blocked); only then are the three originals
    # dropped, in dependency order; the three real tables are then
    # created fresh, directly under their final names with the
    # updated `CHECK`, and the data copied back in from staging.
    .with_db_transaction(work_conn, function(c) {
      DBI::dbExecute(c, "CREATE TABLE zzedc_audit_log_staging AS SELECT * FROM audit_log")
      DBI::dbExecute(c, "CREATE TABLE zzedc_audit_events_staging AS SELECT * FROM audit_events")
      DBI::dbExecute(c, "CREATE TABLE zzedc_audit_chain_staging AS SELECT * FROM audit_chain")

      DBI::dbExecute(c, "DROP TABLE audit_chain")
      DBI::dbExecute(c, "DROP TABLE audit_events")
      DBI::dbExecute(c, "DROP TABLE audit_log")

      adapter$prepare_auto_increment(c, "audit_log", "audit_id")
      DBI::dbExecute(c, sprintf("
        CREATE TABLE audit_log (
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
      ", adapter$auto_increment_column("audit_log", "audit_id"), expected_list))

      adapter$prepare_auto_increment(c, "audit_events", "event_id")
      DBI::dbExecute(c, sprintf("
        CREATE TABLE audit_events (
          event_id %s,
          audit_id INTEGER NOT NULL REFERENCES audit_log(audit_id),
          event_category TEXT,
          event_severity TEXT CHECK(event_severity IN ('info', 'warning', 'error', 'critical')),
          event_message TEXT,
          recovery_action TEXT,
          created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ", adapter$auto_increment_column("audit_events", "event_id")))

      adapter$prepare_auto_increment(c, "audit_chain", "chain_id")
      DBI::dbExecute(c, sprintf("
        CREATE TABLE audit_chain (
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

      # Explicit column lists on both sides, not positional `SELECT
      # *`: a positional copy would silently misalign columns if a
      # future edit ever changes the real tables' column order
      # without touching this migration (`CREATE TABLE ... AS SELECT
      # *` for the staging tables mirrors whatever order audit_log/
      # audit_events/audit_chain happen to have right now).
      DBI::dbExecute(c, "
        INSERT INTO audit_log (
          audit_id, timestamp, user_id, event_type, table_name, record_id,
          operation, details, ip_address, session_id, audit_hash,
          previous_hash, hash_verified, created_date
        )
        SELECT
          audit_id, timestamp, user_id, event_type, table_name, record_id,
          operation, details, ip_address, session_id, audit_hash,
          previous_hash, hash_verified, created_date
        FROM zzedc_audit_log_staging
      ")
      DBI::dbExecute(c, "
        INSERT INTO audit_events (
          event_id, audit_id, event_category, event_severity, event_message,
          recovery_action, created_date
        )
        SELECT
          event_id, audit_id, event_category, event_severity, event_message,
          recovery_action, created_date
        FROM zzedc_audit_events_staging
      ")
      DBI::dbExecute(c, "
        INSERT INTO audit_chain (
          chain_id, audit_id, record_hash, previous_hash, chain_order,
          verified, verification_date, created_date
        )
        SELECT
          chain_id, audit_id, record_hash, previous_hash, chain_order,
          verified, verification_date, created_date
        FROM zzedc_audit_chain_staging
      ")

      DBI::dbExecute(c, "DROP TABLE zzedc_audit_log_staging")
      DBI::dbExecute(c, "DROP TABLE zzedc_audit_events_staging")
      DBI::dbExecute(c, "DROP TABLE zzedc_audit_chain_staging")

      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)")
      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_table ON audit_log(table_name)")
      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_date ON audit_log(timestamp)")
      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_event ON audit_log(event_type)")
      DBI::dbExecute(c, "CREATE INDEX IF NOT EXISTS idx_audit_chain_order ON audit_chain(chain_order)")
    })
  } else if (backend %in% c("postgresql", "mysql")) {
    constraint_name <- .audit_log_check_constraint_name(work_conn, backend)
    if (is.null(constraint_name)) {
      # Silently returning here would be the original bug's failure
      # mode in a new shape: a database whose constraint this
      # package cannot locate is left exactly as stale as one this
      # function was never called on, with nothing in the return
      # value to say so.
      stop(
        "migrate_audit_event_types(): could not locate audit_log's event_type ",
        "CHECK constraint on this ", backend, " database; it was not migrated. ",
        "Inspect it manually (pg_constraint / information_schema.CHECK_CONSTRAINTS).",
        call. = FALSE
      )
    }
    # One statement, both clauses: PostgreSQL and MySQL/MariaDB both
    # accept multiple ALTER TABLE actions comma-separated in a single
    # statement, which (unlike a separate DROP followed by a separate
    # ADD) cannot be left with the constraint dropped and not yet
    # replaced if the ADD half were to fail -- a real risk on
    # MySQL/MariaDB in particular, where DDL auto-commits each
    # statement regardless of any enclosing transaction.
    # DROP CONSTRAINT (not DROP CHECK) is used for both backends:
    # PostgreSQL has only ever had DROP CONSTRAINT, and MySQL 8/
    # MariaDB 10.2+ both also accept it as the generic, portable form
    # for a CHECK constraint (not confirmed against a live MariaDB
    # server in this session; if a given MariaDB version turns out
    # to require DROP CHECK specifically, this statement would fail
    # loudly via DBI::dbExecute(), not silently no-op).
    .with_db_transaction(work_conn, function(c) {
      DBI::dbExecute(c, sprintf(
        "ALTER TABLE audit_log DROP CONSTRAINT %s, ADD CONSTRAINT %s CHECK (event_type IN (%s))",
        constraint_name, constraint_name, expected_list
      ))
    })
  }

  invisible(TRUE)
}


#' The `event_type` `CHECK` Constraint's Stored Text, if Discoverable
#'
#' @param conn A DBI connection or pool.
#' @param backend One of `"sqlite"`, `"duckdb"`, `"postgresql"`, `"mysql"`.
#' @return The constraint's SQL text (or expression), or `NULL` if it
#'   could not be found (a database this old is rebuilt/replaced
#'   unconditionally by [migrate_audit_event_types()] rather than
#'   risk leaving a stale constraint in place).
#' @keywords internal
.audit_log_check_text <- function(conn, backend) {
  tryCatch({
    if (backend == "sqlite") {
      row <- DBI::dbGetQuery(conn, "
        SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'audit_log'
      ")
      if (nrow(row) == 0) NULL else row$sql[1]
    } else if (backend == "duckdb") {
      row <- DBI::dbGetQuery(conn, "
        SELECT constraint_text FROM duckdb_constraints()
        WHERE table_name = 'audit_log' AND constraint_type = 'CHECK'
      ")
      if (nrow(row) == 0) NULL else paste(row$constraint_text, collapse = " ")
    } else if (backend == "postgresql") {
      row <- DBI::dbGetQuery(conn, "
        SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint
        WHERE conrelid = 'audit_log'::regclass AND contype = 'c'
      ")
      if (nrow(row) == 0) NULL else paste(row$def, collapse = " ")
    } else if (backend == "mysql") {
      row <- DBI::dbGetQuery(conn, "
        SELECT CHECK_CLAUSE AS def FROM information_schema.CHECK_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME IN (
            SELECT CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'audit_log'
              AND CONSTRAINT_TYPE = 'CHECK'
          )
      ")
      if (nrow(row) == 0) NULL else paste(row$def, collapse = " ")
    } else {
      NULL
    }
  }, error = function(e) NULL)
}


#' The `event_type` `CHECK` Constraint's Name, on PostgreSQL/MySQL
#'
#' Both original `CREATE TABLE audit_log (...)` statements
#' (`.ensure_audit_tables()`) leave the `event_type CHECK(...)`
#' constraint unnamed, so the server auto-generates one; dropping and
#' replacing it requires knowing what that name turned out to be.
#'
#' @param conn A DBI connection or pool.
#' @param backend `"postgresql"` or `"mysql"`.
#' @return The constraint's name, or `NULL` if it could not be found.
#' @keywords internal
.audit_log_check_constraint_name <- function(conn, backend) {
  tryCatch({
    if (backend == "postgresql") {
      row <- DBI::dbGetQuery(conn, "
        SELECT conname FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
        WHERE c.conrelid = 'audit_log'::regclass AND c.contype = 'c'
          AND a.attname = 'event_type'
      ")
      if (nrow(row) == 0) NULL else row$conname[1]
    } else if (backend == "mysql") {
      row <- DBI::dbGetQuery(conn, "
        SELECT tc.CONSTRAINT_NAME AS n
        FROM information_schema.TABLE_CONSTRAINTS tc
        JOIN information_schema.CHECK_CONSTRAINTS cc
          ON cc.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
          AND cc.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
        WHERE tc.TABLE_SCHEMA = DATABASE() AND tc.TABLE_NAME = 'audit_log'
          AND tc.CONSTRAINT_TYPE = 'CHECK' AND cc.CHECK_CLAUSE LIKE '%event_type%'
      ")
      if (nrow(row) == 0) NULL else row$n[1]
    } else {
      NULL
    }
  }, error = function(e) NULL)
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
