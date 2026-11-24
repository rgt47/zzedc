library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Defect 11 (zzedc-modernization-whitepaper-2026-11-13.md, Section
# 2.2): `.ensure_audit_tables()`'s `CREATE TABLE IF NOT EXISTS
# audit_log (... CHECK(event_type IN (...)) ...)` bakes the allowed
# event types in at first creation only; `IF NOT EXISTS` is a no-op
# on every later call, so a database created before a new event type
# was added to `.audit_event_types` (RANDOMIZATION/EMERGENCY_UNBLIND,
# added in 4c802dc) keeps rejecting them forever.
# migrate_audit_event_types() rebuilds the constraint for such a
# database. Confirmed directly before this fix: logging a
# RANDOMIZATION event against a database with the pre-4c802dc
# constraint fails with a CHECK constraint violation.

.old_style_audit_tables <- function(conn, backend) {
  old_types <- setdiff(zzedc:::.audit_event_types, c("RANDOMIZATION", "EMERGENCY_UNBLIND"))
  list_sql <- paste0("'", old_types, "'", collapse = ", ")
  if (backend == "sqlite") {
    DBI::dbExecute(conn, "PRAGMA foreign_keys = ON")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE audit_log (
        audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, user_id TEXT,
        event_type TEXT NOT NULL CHECK(event_type IN (%s)),
        table_name TEXT, record_id TEXT, operation TEXT, details TEXT,
        ip_address TEXT, session_id TEXT, audit_hash TEXT, previous_hash TEXT,
        hash_verified BOOLEAN DEFAULT 1, created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )", list_sql))
    DBI::dbExecute(conn, "
      CREATE TABLE audit_events (
        event_id INTEGER PRIMARY KEY AUTOINCREMENT,
        audit_id INTEGER NOT NULL REFERENCES audit_log(audit_id),
        event_category TEXT, event_severity TEXT, event_message TEXT,
        recovery_action TEXT, created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )")
    DBI::dbExecute(conn, "
      CREATE TABLE audit_chain (
        chain_id INTEGER PRIMARY KEY AUTOINCREMENT,
        audit_id INTEGER NOT NULL UNIQUE REFERENCES audit_log(audit_id),
        record_hash TEXT NOT NULL UNIQUE, previous_hash TEXT, chain_order INTEGER,
        verified BOOLEAN DEFAULT 1, verification_date TIMESTAMP,
        created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )")
  } else {
    DBI::dbExecute(conn, "CREATE SEQUENCE IF NOT EXISTS audit_log_audit_id_seq")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE audit_log (
        audit_id INTEGER PRIMARY KEY DEFAULT nextval('audit_log_audit_id_seq'),
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, user_id TEXT,
        event_type TEXT NOT NULL CHECK(event_type IN (%s)),
        table_name TEXT, record_id TEXT, operation TEXT, details TEXT,
        ip_address TEXT, session_id TEXT, audit_hash TEXT, previous_hash TEXT,
        hash_verified BOOLEAN DEFAULT 1, created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )", list_sql))
    DBI::dbExecute(conn, "CREATE SEQUENCE IF NOT EXISTS audit_events_event_id_seq")
    DBI::dbExecute(conn, "
      CREATE TABLE audit_events (
        event_id INTEGER PRIMARY KEY DEFAULT nextval('audit_events_event_id_seq'),
        audit_id INTEGER NOT NULL REFERENCES audit_log(audit_id),
        event_category TEXT, event_severity TEXT, event_message TEXT,
        recovery_action TEXT, created_date TIMESTAMP
      )")
    DBI::dbExecute(conn, "CREATE SEQUENCE IF NOT EXISTS audit_chain_chain_id_seq")
    DBI::dbExecute(conn, "
      CREATE TABLE audit_chain (
        chain_id INTEGER PRIMARY KEY DEFAULT nextval('audit_chain_chain_id_seq'),
        audit_id INTEGER NOT NULL UNIQUE REFERENCES audit_log(audit_id),
        record_hash TEXT NOT NULL UNIQUE, previous_hash TEXT, chain_order INTEGER,
        verified BOOLEAN DEFAULT 1, verification_date TIMESTAMP, created_date TIMESTAMP
      )")
  }
}

.exercise_migration <- function(conn, backend, adapter) {
  DBI::dbExecute(conn, "INSERT INTO audit_log (user_id, event_type, operation) VALUES ('alice', 'LOGIN', 'x')")
  id1 <- if (backend == "sqlite") {
    DBI::dbGetQuery(conn, "SELECT last_insert_rowid() AS id")$id
  } else {
    DBI::dbGetQuery(conn, "SELECT audit_id AS id FROM audit_log WHERE user_id = 'alice'")$id
  }
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO audit_events (audit_id, event_message) VALUES (%d, 'test')", id1
  ))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO audit_chain (audit_id, record_hash, chain_order) VALUES (%d, 'h1', 1)", id1
  ))

  expect_error(
    DBI::dbExecute(conn, "INSERT INTO audit_log (user_id, event_type, operation) VALUES ('bob', 'RANDOMIZATION', 'x')"),
    info = "pre-migration: the stale CHECK constraint rejects a newer event type"
  )

  zzedc:::migrate_audit_event_types(conn, adapter = adapter)

  expect_silent(
    DBI::dbExecute(conn, "INSERT INTO audit_log (user_id, event_type, operation) VALUES ('bob', 'RANDOMIZATION', 'x')")
  )
  expect_equal(
    nrow(DBI::dbGetQuery(conn, sprintf("SELECT * FROM audit_events WHERE audit_id = %d", id1))), 1,
    info = "audit_events row (FK to audit_log) survives the rebuild"
  )
  expect_equal(
    nrow(DBI::dbGetQuery(conn, sprintf("SELECT * FROM audit_chain WHERE audit_id = %d", id1))), 1,
    info = "audit_chain row (FK to audit_log) survives the rebuild"
  )

  n_before <- DBI::dbGetQuery(conn, "SELECT COUNT(*) n FROM audit_log")$n
  zzedc:::migrate_audit_event_types(conn, adapter = adapter)
  n_after <- DBI::dbGetQuery(conn, "SELECT COUNT(*) n FROM audit_log")$n
  expect_equal(n_before, n_after, info = "re-running the migration is a no-op")
}

if (requireNamespace("RSQLite", quietly = TRUE)) local({
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db), add = TRUE)
  adapter <- zzedc:::create_db_adapter(list(db_backend = "sqlite", sqlite = list(path = db)))
  conn <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  .old_style_audit_tables(conn, "sqlite")
  .exercise_migration(conn, "sqlite", adapter)

  triggers <- DBI::dbGetQuery(conn, "SELECT name FROM sqlite_master WHERE type = 'trigger'")$name
  expect_true(all(zzedc:::.audit_trigger_names %in% triggers),
              info = "append-only triggers (dropped along with the rebuilt table) are restored")
  expect_error(
    DBI::dbExecute(conn, "UPDATE audit_log SET user_id = 'x' WHERE audit_id = 1"),
    info = "append-only protection still enforced on the rebuilt table"
  )
  expect_equal(nrow(DBI::dbGetQuery(conn, "PRAGMA foreign_key_check")), 0,
               info = "no dangling foreign keys after the rebuild")
  expect_equal(DBI::dbGetQuery(conn, "PRAGMA foreign_keys")[[1]][1], 1L,
               info = "PRAGMA foreign_keys is restored to its pre-migration value (ON), not left OFF")
})

# migrate_add_randomization_tables() (R/randomization_module.R) is
# the one existing, already-documented entry point an operator with
# an old database actually runs; this confirms it closes the audit
# CHECK gap too, not just migrate_audit_event_types() called
# directly (which every block above does).
if (requireNamespace("RSQLite", quietly = TRUE)) local({
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db), add = TRUE)
  adapter <- zzedc:::create_db_adapter(list(db_backend = "sqlite", sqlite = list(path = db)))
  conn <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  .old_style_audit_tables(conn, "sqlite")
  zzedc::migrate_add_randomization_tables(conn, adapter = adapter)

  expect_true(DBI::dbExistsTable(conn, "randomization_config"),
              info = "migrate_add_randomization_tables() still creates its own tables")
  expect_silent(
    DBI::dbExecute(conn, "INSERT INTO audit_log (user_id, event_type, operation) VALUES ('x', 'RANDOMIZATION', 'y')")
  )
})

# `PRAGMA foreign_keys` is connection-scoped: toggling it on a Pool
# object (which can hand out any physical connection on each call)
# risks setting it on one connection while the migration's own
# transaction runs on another. migrate_audit_event_types() checks
# out a single connection up front for exactly this reason; this
# confirms the migration still works end to end through a real Pool,
# not just a plain connection.
if (requireNamespace("RSQLite", quietly = TRUE) && requireNamespace("pool", quietly = TRUE)) local({
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db), add = TRUE)
  adapter <- zzedc:::create_db_adapter(list(db_backend = "sqlite", sqlite = list(path = db)))

  setup_conn <- DBI::dbConnect(RSQLite::SQLite(), db)
  .old_style_audit_tables(setup_conn, "sqlite")
  DBI::dbDisconnect(setup_conn)

  # onCreate mirrors SQLiteAdapter$connect(), which turns this on
  # for every real connection it hands out.
  p <- pool::dbPool(RSQLite::SQLite(), dbname = db, minSize = 1, maxSize = 2,
                     onCreate = function(c) DBI::dbExecute(c, "PRAGMA foreign_keys = ON"))
  on.exit(pool::poolClose(p), add = TRUE)

  expect_error(
    pool::poolWithTransaction(p, function(c) {
      DBI::dbExecute(c, "INSERT INTO audit_log (user_id, event_type, operation) VALUES ('x', 'RANDOMIZATION', 'y')")
    }),
    info = "pre-migration: the pool's own connections still see the stale constraint"
  )

  zzedc:::migrate_audit_event_types(p, adapter = adapter)

  expect_silent(
    pool::poolWithTransaction(p, function(c) {
      DBI::dbExecute(c, "INSERT INTO audit_log (user_id, event_type, operation) VALUES ('x', 'RANDOMIZATION', 'y')")
    })
  )
  # The PRAGMA toggle must not leak OFF onto whatever connection the
  # pool hands out next.
  fk_state <- pool::poolWithTransaction(p, function(c) DBI::dbGetQuery(c, "PRAGMA foreign_keys")[[1]][1])
  expect_equal(fk_state, 1L, info = "foreign_keys PRAGMA restored to ON on pool connections too")
})

# The block above uses hand-built schema/data, which confirms the
# rebuild's SQL is correct but not that it survives real
# `.append_audit_record()` writes, real `.protect_audit_tables()`
# triggers, or a real hash chain `verify_audit_integrity()` accepts
# both before and after. This block builds a database the same way
# the package itself would -- `.audit_event_types` is temporarily
# shrunk back to its pre-4c802dc contents (an unlockBinding/
# lockBinding round trip; the namespace is locked even under
# pkgload::load_all()) so init_audit_logging()'s own
# `.ensure_audit_tables()` call creates the old-style constraint,
# then restored before exercising the real event writer and
# verifier -- not a hand-written imitation of either.
if (requireNamespace("RSQLite", quietly = TRUE)) local({
  # 'standard' with plaintext SQLite now needs the deployer's opt-in
  # (owner decision 2026-11-17); this test is about the audit
  # constraint migration, not storage, so it opts in.
  old_opts <- options(zzedc.security_profile = "standard",
                      zzedc.accept_unencrypted_sqlite = TRUE)
  on.exit(options(old_opts), add = TRUE)

  ns <- asNamespace("zzedc")
  full_types <- get(".audit_event_types", envir = ns)
  on.exit({
    if (bindingIsLocked(".audit_event_types", ns)) unlockBinding(".audit_event_types", ns)
    assign(".audit_event_types", full_types, envir = ns)
    lockBinding(".audit_event_types", ns)
  }, add = TRUE)
  unlockBinding(".audit_event_types", ns)
  assign(".audit_event_types", setdiff(full_types, c("RANDOMIZATION", "EMERGENCY_UNBLIND")), envir = ns)
  lockBinding(".audit_event_types", ns)

  db_path <- tempfile(fileext = ".db")
  on.exit(unlink(db_path), add = TRUE)
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
  on.exit({
    if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY") else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  }, add = TRUE)

  init <- zzedc:::initialize_encrypted_database(db_path = db_path, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  setup <- zzedc::init_audit_logging(db_path = db_path)
  expect_true(setup$success, info = "init_audit_logging() builds a real old-style database")

  expect_true(zzedc::log_audit_event(
    event_type = "LOGIN", table_name = "edc_users", operation = "x",
    user_id = "alice", db_path = db_path
  ))
  expect_warning(
    zzedc::log_audit_event(
      event_type = "RANDOMIZATION", table_name = "randomization_history",
      operation = "z", db_path = db_path
    ),
    "Invalid event_type",
    info = paste(
      "with .audit_event_types itself shrunk back to its pre-4c802dc",
      "contents, the R-level validation in .append_audit_record()",
      "rejects RANDOMIZATION first; the live-sqlite-schema block above",
      "already confirms the DB's own CHECK constraint independently",
      "rejects it too"
    )
  )

  # .audit_event_types is restored by the on.exit() above only at
  # the very end of this block; restore it here too so the
  # migration call below (and the rest of the suite) see the real,
  # current list.
  unlockBinding(".audit_event_types", ns)
  assign(".audit_event_types", full_types, envir = ns)
  lockBinding(".audit_event_types", ns)

  conn <- zzedc::connect_encrypted_db(db_path = db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  pre_chain <- zzedc::verify_audit_integrity(conn = conn)
  expect_true(pre_chain$valid, info = "real hash chain verifies before migration")

  adapter <- zzedc:::create_db_adapter(list(
    db_backend = "sqlite", sqlite = list(path = db_path, encryption_key = init$key)
  ))
  zzedc:::migrate_audit_event_types(conn, adapter = adapter)

  expect_true(zzedc::log_audit_event(
    event_type = "RANDOMIZATION", table_name = "randomization_history",
    operation = "z", user_id = "carol", db_path = db_path
  ), info = "RANDOMIZATION accepted through the real writer after migration")

  post_chain <- zzedc::verify_audit_integrity(conn = conn)
  expect_true(post_chain$valid,
              info = "real hash chain (pre-existing rows plus the new RANDOMIZATION row) verifies after migration")
})

duck_ok <- requireNamespace("duckdb", quietly = TRUE) && tryCatch(
  all(zzedc:::install_duckdb_extensions(tempfile("extk_"))$loads_offline),
  error = function(e) FALSE
)
if (duck_ok) local({
  dir <- tempfile("duck_migrate_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  db <- file.path(dir, "study.duckdb")
  adapter <- zzedc:::create_db_adapter(list(db_backend = "duckdb", duckdb = list(path = db)))
  conn <- DBI::dbConnect(duckdb::duckdb(), db)
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)

  .old_style_audit_tables(conn, "duckdb")
  .exercise_migration(conn, "duckdb", adapter)

  expect_error(
    DBI::dbExecute(conn, "INSERT INTO audit_events (audit_id, event_message) VALUES (999999, 'bogus')"),
    info = "foreign key from audit_events to audit_log still enforced after the rebuild"
  )
})

# DuckDB, the default backend, with a real hash chain (added
# 2026-11-23, before new audit event types were added for the
# monitoring plan). The block above checks the DuckDB rebuild with
# hand-built rows; this one builds the audit tables the way the
# package does, writes real records through the real writer, and
# checks that verify_audit_integrity() accepts the chain before and
# after migrate_audit_event_types(), as the SQLite block does.
if (duck_ok) local({
  old_opts <- options(zzedc.security_profile = "development")
  on.exit(options(old_opts), add = TRUE)

  ns <- asNamespace("zzedc")
  full_types <- get(".audit_event_types", envir = ns)
  cache <- get(".db_adapter_cache", envir = ns)
  had_adapter <- exists("adapter", envir = cache)
  saved_adapter <- if (had_adapter) cache$adapter else NULL
  on.exit({
    if (bindingIsLocked(".audit_event_types", ns)) unlockBinding(".audit_event_types", ns)
    assign(".audit_event_types", full_types, envir = ns)
    lockBinding(".audit_event_types", ns)
    tryCatch(zzedc:::get_db_adapter()$shutdown(), error = function(e) NULL)
    if (had_adapter) {
      assign("adapter", saved_adapter, envir = cache)
    } else if (exists("adapter", envir = cache)) {
      rm("adapter", envir = cache)
    }
  }, add = TRUE)

  dir <- tempfile("duck_chain_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  db <- file.path(dir, "study.duckdb")
  config <- list(db_backend = "duckdb", duckdb = list(path = db))
  adapter <- zzedc:::get_db_adapter(config = config, force_new = TRUE)

  unlockBinding(".audit_event_types", ns)
  assign(".audit_event_types",
         setdiff(full_types, c("RANDOMIZATION", "EMERGENCY_UNBLIND")),
         envir = ns)
  lockBinding(".audit_event_types", ns)

  setup <- zzedc::init_audit_logging(db_path = db)
  expect_true(setup$success,
              info = "DuckDB: init_audit_logging() builds an old-style database")
  for (u in c("alice", "bob", "carol")) {
    expect_true(zzedc::log_audit_event(
      event_type = "LOGIN", table_name = "edc_users", operation = "x",
      user_id = u, db_path = db),
      info = paste("DuckDB: pre-migration record for", u))
  }

  unlockBinding(".audit_event_types", ns)
  assign(".audit_event_types", full_types, envir = ns)
  lockBinding(".audit_event_types", ns)

  conn <- zzedc::connect_encrypted_db(db_path = db)
  pre_chain <- zzedc::verify_audit_integrity(conn = conn)
  expect_true(isTRUE(pre_chain$valid),
              info = "DuckDB: real hash chain verifies before migration")

  zzedc:::migrate_audit_event_types(conn, adapter = adapter)
  DBI::dbDisconnect(conn)

  expect_true(zzedc::log_audit_event(
    event_type = "RANDOMIZATION", table_name = "randomization_history",
    operation = "z", user_id = "dave", db_path = db),
    info = "DuckDB: RANDOMIZATION accepted after migration")

  conn <- zzedc::connect_encrypted_db(db_path = db)
  post_chain <- zzedc::verify_audit_integrity(conn = conn)
  n <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM audit_log")$n
  DBI::dbDisconnect(conn)
  expect_true(isTRUE(post_chain$valid),
              info = "DuckDB: real hash chain verifies after migration")
  expect_equal(as.integer(n), 4L,
               info = "DuckDB: pre-existing records survive the migration")
})
