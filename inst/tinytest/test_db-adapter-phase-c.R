library(tinytest)

if (file.exists("_setup.R")) source("_setup.R")

# Regression tests for the Phase C schema-portability fixes documented
# in docs/db-adapter-remediation-plan-2026-11-07.md. These were
# verified by one-off scratch scripts during that session; this file
# captures them permanently. Backends exercised: sqlite (always) and
# duckdb (whenever the duckdb package is installed), independent of
# ZZEDC_TEST_BACKENDS, since duckdb is where every Phase C bug
# actually surfaced (SQLite's lenient FK/auto-increment handling
# masked all of them).

phase_c_backends <- function() {
  backends <- "sqlite"
  if (requireNamespace("duckdb", quietly = TRUE)) {
    backends <- c(backends, "duckdb")
  }
  backends
}

with_phase_c_backend <- function(backend, desc, test_fn) {
  message(sprintf("[%s] %s", toupper(backend), desc))
  db_path <- tempfile(fileext = if (backend == "duckdb") ".duckdb" else ".db")
  on.exit(unlink(db_path), add = TRUE)
  config <- test_backend_config(backend)
  config[[backend]]$path <- db_path
  get_db_adapter(config = config, force_new = TRUE)

  if (backend == "sqlite") {
    # connect_encrypted_db() on the sqlite path (still the pre-Phase-B
    # legacy path; see its @details) requires an existing encrypted
    # file, unlike the other backends which connect_encrypted_db()
    # routes straight to adapter$connect().
    init_res <- initialize_encrypted_database(db_path = db_path)
    stopifnot(isTRUE(init_res$success))
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA)
    Sys.setenv(DB_ENCRYPTION_KEY = init_res$key)
    on.exit({
      if (is.na(old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY")
      else Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    }, add = TRUE)
  }

  test_fn(db_path)
}

# ============================================================================
# auto_increment_ddl() / prepare_auto_increment()
# ============================================================================

for (backend in phase_c_backends()) {
  with_phase_c_backend(backend, "auto-increment DDL produces working IDs", function(db_path) {
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    prepare_auto_increment(conn, "ai_test", "ai_id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE ai_test (
        ai_id %s,
        label TEXT
      )
    ", auto_increment_ddl("ai_test", "ai_id")))

    DBI::dbExecute(conn, "INSERT INTO ai_test (label) VALUES ('a')")
    DBI::dbExecute(conn, "INSERT INTO ai_test (label) VALUES ('b')")
    rows <- DBI::dbGetQuery(conn, "SELECT ai_id, label FROM ai_test ORDER BY ai_id")

    expect_equal(nrow(rows), 2, info = paste(backend, "auto-increment row count"))
    expect_true(!anyNA(rows$ai_id), info = paste(backend, "auto-increment IDs not NULL"))
    expect_true(rows$ai_id[2] > rows$ai_id[1],
                info = paste(backend, "auto-increment IDs strictly increasing"))
  })
}

# ============================================================================
# describe_table() / resolve_table_pk_column()
# ============================================================================

for (backend in phase_c_backends()) {
  with_phase_c_backend(backend, "describe_table() identifies a non-'id'-named PK", function(db_path) {
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    prepare_auto_increment(conn, "pk_test", "widget_id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE pk_test (
        widget_id %s,
        name TEXT NOT NULL
      )
    ", auto_increment_ddl("pk_test", "widget_id")))

    adapter <- get_db_adapter()
    desc <- adapter$describe_table(conn, "pk_test")

    expect_true(is.data.frame(desc), info = paste(backend, "describe_table returns a data.frame"))
    expect_true(all(c("name", "type", "notnull", "pk") %in% names(desc)),
                info = paste(backend, "describe_table columns"))
    expect_true("widget_id" %in% desc$name[desc$pk],
                info = paste(backend, "widget_id flagged as primary key"))
    expect_true(desc$notnull[desc$name == "name"],
                info = paste(backend, "NOT NULL column flagged"))

    pk_col <- resolve_table_pk_column(conn, "pk_test")
    expect_equal(pk_col, "widget_id",
                 info = paste(backend, "resolve_table_pk_column finds the real PK, not 'rowid'"))
  })
}

# ============================================================================
# sql_date_diff_days() / CURRENT_DATE
# ============================================================================

for (backend in phase_c_backends()) {
  with_phase_c_backend(backend, "sql_date_diff_days() and CURRENT_DATE are portable", function(db_path) {
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    DBI::dbExecute(conn, "CREATE TABLE date_test (a DATE, b DATE)")
    DBI::dbExecute(conn, "INSERT INTO date_test VALUES ('2026-01-05', '2026-01-01')")

    diff <- DBI::dbGetQuery(conn, sprintf(
      "SELECT %s AS d FROM date_test", sql_date_diff_days("a", "b")
    ))
    expect_equal(as.numeric(diff$d[1]), 4,
                 info = paste(backend, "sql_date_diff_days computes a 4-day difference"))

    # date('now') is SQLite-only and errors on duckdb; CURRENT_DATE is
    # the portable replacement used throughout the codebase after
    # Phase C. On duckdb, CURRENT_DATE can require the bundled `icu`
    # extension, which duckdb autoinstalls over the network on first
    # use; a sandboxed CI runner with no route to the extension
    # repository fails this with an "Extension Autoloading Error",
    # unrelated to whether the portable-SQL logic under test is
    # correct. Treat that specific failure as a skip, not a bug --
    # any other error from this query still fails the test normally.
    today <- tryCatch(
      DBI::dbGetQuery(conn, "SELECT CURRENT_DATE AS d"),
      error = function(e) {
        if (backend == "duckdb" && grepl("Extension Autoloading", conditionMessage(e))) {
          message(sprintf(
            "[%s] SKIP CURRENT_DATE check: icu extension unavailable (%s)",
            toupper(backend), conditionMessage(e)
          ))
          NULL
        } else {
          stop(e)
        }
      }
    )
    if (!is.null(today)) {
      expect_equal(nrow(today), 1, info = paste(backend, "CURRENT_DATE is a valid expression"))
    }
  })
}

# ============================================================================
# Forward-FK schema-ordering regressions (protocol_compliance, erasure)
# ============================================================================
#
# SQLite does not validate a REFERENCES target at CREATE TABLE time;
# DuckDB does. Both init_protocol_compliance() and init_erasure() had
# a table referencing another table defined later in the same
# function, which was invisible under SQLite and fatal under DuckDB
# ("Catalog Error: Table with name ... does not exist!"). Fixed by
# reordering the CREATE TABLE statements; these tests guard against
# the ordering regressing.

for (backend in phase_c_backends()) {
  with_phase_c_backend(backend, "init_protocol_compliance() succeeds (forward-FK ordering)", function(db_path) {
    result <- init_protocol_compliance(db_path = db_path)
    expect_true(isTRUE(result$success),
                info = paste(backend, "init_protocol_compliance did not error:",
                             result$message %||% ""))

    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    tables <- DBI::dbListTables(conn)
    expect_true("protocol_deviations" %in% tables, info = paste(backend, "protocol_deviations exists"))
    expect_true("subject_visits" %in% tables, info = paste(backend, "subject_visits exists"))
  })
}

for (backend in phase_c_backends()) {
  with_phase_c_backend(backend, "init_erasure() succeeds (forward-FK ordering, after init_dsar)", function(db_path) {
    dsar_result <- init_dsar(db_path = db_path)
    expect_true(isTRUE(dsar_result$success),
                info = paste(backend, "init_dsar prerequisite did not error"))

    result <- init_erasure(db_path = db_path)
    expect_true(isTRUE(result$success),
                info = paste(backend, "init_erasure did not error:",
                             result$message %||% ""))

    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    tables <- DBI::dbListTables(conn)
    expect_true("legal_holds" %in% tables, info = paste(backend, "legal_holds exists"))
    expect_true("erasure_requests" %in% tables, info = paste(backend, "erasure_requests exists"))
  })
}

# ============================================================================
# initialize_encrypted_database() multi-backend dispatch (Phase B
# finding, fixed 2026-11-08)
# ============================================================================
#
# This function used to always create a SQLCipher-encrypted SQLite
# file, regardless of config.yml's chosen backend. It now dispatches
# on backend: SQLite is unchanged, DuckDB creates an
# ENCRYPTION_KEY-attached file, and PostgreSQL/MySQL/MariaDB (server-
# hosted, no file to create, no application-level encryption key)
# just create the base tables and return key = NA. PostgreSQL/MariaDB
# were also verified directly against live Docker containers during
# this session (see the plan doc); not captured here permanently --
# same CI-reachable-server gap as the rest of Phase D.

message("[SQLITE] initialize_encrypted_database() creates base tables")
{
  db_path <- tempfile(fileext = ".db")
  on.exit(unlink(db_path), add = TRUE)
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = db_path)), force_new = TRUE)

  result <- initialize_encrypted_database(db_path = db_path)
  expect_true(isTRUE(result$success), info = paste("sqlite init:", result$error %||% ""))
  expect_true(!is.na(result$key), info = "sqlite returns a real encryption key")

  retry <- initialize_encrypted_database(db_path = db_path)
  expect_false(isTRUE(retry$success), info = "sqlite init refuses to overwrite without overwrite=TRUE")
}

if (requireNamespace("duckdb", quietly = TRUE)) {
  message("[DUCKDB] initialize_encrypted_database() creates an encrypted file")
  duckdb_path <- tempfile(fileext = ".duckdb")
  on.exit(unlink(duckdb_path), add = TRUE)
  get_db_adapter(config = list(db_backend = "duckdb", duckdb = list(path = duckdb_path)), force_new = TRUE)

  result <- initialize_encrypted_database()
  # Surfaced unconditionally (not just on failure) so a CI run's log
  # always shows the real cause if this ever regresses again --
  # result$error was previously only visible via expect_true()'s
  # info=, which tinytest does not print for a passing assertion and
  # which a later crash (normalizePath(NULL) below, when result$path
  # is absent) can prevent from ever being reported for a failing one.
  message(sprintf(
    "[DUCKDB] initialize_encrypted_database(): success=%s error=%s file.exists=%s",
    isTRUE(result$success), result$error %||% "(none)", file.exists(duckdb_path)
  ))
  expect_true(isTRUE(result$success), info = paste("duckdb init:", result$error %||% ""))
  if (!is.null(result$key)) {
    expect_true(!is.na(result$key), info = "duckdb returns a real encryption key")
  }
  if (!is.null(result$path)) {
    expect_equal(normalizePath(result$path), normalizePath(duckdb_path),
                 info = "duckdb init resolves the path from config$duckdb$path")
  }

  retry <- initialize_encrypted_database()
  expect_false(isTRUE(retry$success), info = "duckdb init refuses to overwrite without overwrite=TRUE")

  overwritten <- initialize_encrypted_database(overwrite = TRUE)
  expect_true(isTRUE(overwritten$success), info = "duckdb init honors overwrite=TRUE")
}

# ============================================================================
# create_wizard_database() with NULL optional fields (Phase B finding,
# fixed 2026-11-08)
# ============================================================================
#
# config_list$pi_email, study_phase, target_enrollment,
# admin_fullname, and admin_email are documented as optional. Passing
# a raw R NULL for any of them as a DBI bind parameter has length 0;
# SQLite's binding tolerates this, DuckDB's does not ("Bind parameter
# values need to have the same length"). Fixed by coalescing each to
# NA (the portable way to bind a SQL NULL) in create_wizard_database().

if (requireNamespace("duckdb", quietly = TRUE)) {
  message("[DUCKDB] create_wizard_database() tolerates NULL optional fields")
  db_path <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db_path), add = TRUE)

  config_list <- list(
    study_name = "Test Study", protocol_id = "P-001", pi_name = "Dr Test",
    pi_email = NULL, study_phase = NULL, target_enrollment = NULL,
    admin_username = "admin", admin_password = "admin123",
    admin_fullname = NULL, admin_email = NULL, security_salt = "salt123"
  )
  result <- create_wizard_database(config_list, db_path = db_path, backend = "duckdb")

  expect_true(isTRUE(result$success),
              info = paste("duckdb create_wizard_database with NULL optional fields:",
                           result$message %||% ""))

  conn <- DBI::dbConnect(duckdb::duckdb(), db_path)
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)
  study_row <- DBI::dbGetQuery(conn, "SELECT pi_email, study_phase, target_enrollment FROM study_info")
  user_row <- DBI::dbGetQuery(conn, "SELECT full_name, email FROM edc_users WHERE username = 'admin'")

  expect_true(is.na(study_row$pi_email[1]), info = "NULL pi_email became a real SQL NULL")
  expect_true(is.na(study_row$target_enrollment[1]), info = "NULL target_enrollment became a real SQL NULL")
  expect_true(is.na(user_row$full_name[1]), info = "NULL admin_fullname became a real SQL NULL")
}

# ============================================================================
# DuckDB encrypted database stays usable after initialize_encrypted_database()
# (fixed 2026-11-08)
# ============================================================================
#
# Two bugs, both specific to DuckDB, both invisible on SQLite:
#
# 1. init_encrypted_duckdb_database() generated a key and used it to
#    build a one-off adapter for the CREATE TABLE statements, but
#    never updated the cached adapter get_db_adapter() returns.
#    Every later connect_encrypted_db() call (the normal way
#    add_form_field() etc. connect) resolved the cached, key-less
#    adapter and failed with "Cannot open encrypted database ...
#    without a key" -- even with the right key in hand, because
#    nothing told the cache about it. Fixed by caching the
#    key-carrying adapter.
# 2. Holding one connection open across a second connection's write to
#    the same encrypted file: DuckDB's first connection does not see
#    the second connection's write, even though a third, freshly
#    opened connection does (confirmed directly: a stale connection
#    reports 0 rows where a fresh one reports 1). This is why
#    add_form_field_by_code() opens and closes a separate connection
#    for each step instead of holding one open across
#    add_form_field()'s own connect() call.

if (requireNamespace("duckdb", quietly = TRUE)) {
  message("[DUCKDB] encrypted database stays usable across connections after init")
  db_path <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db_path), add = TRUE)
  get_db_adapter(config = list(db_backend = "duckdb", duckdb = list(path = db_path)), force_new = TRUE)

  init_res <- initialize_encrypted_database()
  expect_true(isTRUE(init_res$success), info = paste("duckdb init:", init_res$error %||% ""))

  # Bug 1's regression guard: a later connect_encrypted_db() call (no
  # key passed explicitly) must resolve the cached, key-carrying
  # adapter, not the original key-less one.
  conn <- connect_encrypted_db()
  tables <- DBI::dbListTables(conn)
  DBI::dbDisconnect(conn)
  expect_true("study_info" %in% tables,
              info = "a later connect_encrypted_db() call can still open the encrypted file")

  init_audit_logging()
  init_crf_designer()
  create_designer_form(form_code = "JOURNAL_REVIEWS", form_name = "Journal Reviews",
                        created_by = "admin")

  # Bug 2's regression guard: add_form_field_by_code() does lookup,
  # duplicate-check, insert, and verify-reread as four short-lived
  # connections; if any of them were held open across another's
  # write, this would come back unverified or with a spurious
  # "already exists" on the first call.
  result <- add_form_field_by_code(
    form_code = "journal_reviews", field_code = "review_assigned_date",
    field_label = "Review Assigned Date", field_type = "DATE",
    field_row = 35, is_required = FALSE,
    help_text = "Date the editor assigned this manuscript for review"
  )
  expect_true(isTRUE(result$success), info = paste("duckdb add_form_field_by_code:", result$error %||% ""))
  expect_true(isTRUE(result$verified), info = "duckdb add_form_field_by_code verifies its own write")
  expect_equal(length(result$mismatches), 0)
}

# Reset the adapter cache so later test files in the same session
# resolve a plain sqlite backend again rather than whichever backend
# this file's loop last configured. Pass an explicit config instead
# of NULL: NULL falls through to config.yml/ZZEDC_DB_PATH resolution,
# which depends on the working directory's environment and is not
# this file's concern to get right.
get_db_adapter(
  config = list(db_backend = "sqlite", sqlite = list(path = tempfile(fileext = ".db"))),
  force_new = TRUE
)
