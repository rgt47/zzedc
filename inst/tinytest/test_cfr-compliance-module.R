library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Tests for cfr_compliance_server()'s apply_signature/verify_signature
# handlers, added 2026-11-09. Both were stubs before this: applying a
# signature fabricated a fake signature_id and never checked the
# password or wrote any row; verifying one always reported "verified
# successfully" for any non-empty id, including one that does not
# exist. These exercise the real wiring through
# apply_electronic_signature()/verify_electronic_signature()
# (R/electronic_signatures.R), via shiny::testServer() the same way
# test_change-password-module.R drives change_password_server().

if (!exists("cfr_compliance_server", where = asNamespace("zzedc"))) {
  exit_file("cfr_compliance_server not available")
}

setup_test_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY", unset = NA_character_)

  test_db <- tempfile(fileext = ".db")
  get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = test_db)),
                 force_new = TRUE)
  Sys.setenv(ZZEDC_DB_PATH = test_db)

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
  init_audit_logging(db_path = test_db)
  init_electronic_signatures(db_path = test_db)

  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  zzedc:::ensure_edc_users_table(conn)
  password_hash <- digest::digest(paste0("correct-horse", resolve_auth_salt()),
                                  algo = "sha256")
  zzedc:::db_insert_user(conn, username = "jdoe", password_hash = password_hash,
                  full_name = "Jane Doe", role = "Coordinator",
                  user_id = "USER_TEST_1", created_by = "test")
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS test_records (
      id INTEGER PRIMARY KEY, subject_id TEXT, status TEXT
    )
  ")
  DBI::dbExecute(conn, "INSERT INTO test_records (subject_id, status) VALUES ('S001', 'draft')")
  DBI::dbDisconnect(conn)

  list(test_db = test_db, old_key = old_key)
}

cleanup_test_db <- function(ctx) {
  if (file.exists(ctx$test_db)) unlink(ctx$test_db)
  Sys.unsetenv("ZZEDC_DB_PATH")
  if (is.na(ctx$old_key)) Sys.unsetenv("DB_ENCRYPTION_KEY")
  else Sys.setenv(DB_ENCRYPTION_KEY = ctx$old_key)
}

if (requireNamespace("RSQLite", quietly = TRUE) &&
      requireNamespace("digest", quietly = TRUE)) local({

  # Applying a signature with the correct password writes a real row
  # and reports the real signature_code (not a fabricated one), and
  # a wrong password is rejected -- neither was true of the stub.
  local({
    ctx <- setup_test_db()
    on.exit(cleanup_test_db(ctx), add = TRUE)

    db_pool <- DBI::dbConnect(RSQLite::SQLite(), ctx$test_db)
    on.exit(DBI::dbDisconnect(db_pool), add = TRUE)
    assign("db_pool", db_pool, envir = globalenv())
    on.exit(rm("db_pool", envir = globalenv()), add = TRUE)

    shiny::testServer(
      zzedc:::cfr_compliance_server,
      args = list(user_id = shiny::reactive("USER_TEST_1")),
      {
        session$setInputs(
          sig_table = "test_records", sig_record_id = "1",
          sig_meaning = "CREATED_BY", sig_password = "wrong-password",
          sig_reason = "", apply_signature = 1
        )
      }
    )

    rows <- DBI::dbGetQuery(db_pool, "SELECT COUNT(*) AS n FROM electronic_signatures")
    expect_equal(rows$n[1], 0L,
                 info = "a wrong password must not create a signature row")

    shiny::testServer(
      zzedc:::cfr_compliance_server,
      args = list(user_id = shiny::reactive("USER_TEST_1")),
      {
        session$setInputs(
          sig_table = "test_records", sig_record_id = "1",
          sig_meaning = "CREATED_BY", sig_password = "correct-horse",
          sig_reason = "", apply_signature = 1
        )
      }
    )

    written <- DBI::dbGetQuery(db_pool, "
      SELECT signer_user_id, signature_meaning, table_name, record_id
      FROM electronic_signatures
    ")
    expect_equal(nrow(written), 1L,
                 info = "the correct password must create exactly one signature row")
    expect_equal(written$signer_user_id[1], "USER_TEST_1")
    expect_equal(written$signature_meaning[1], "CREATED_BY")
    expect_equal(written$table_name[1], "test_records")
  })

  # Verifying a signature that was never created reports failure, not
  # the old stub's unconditional "verified successfully".
  local({
    ctx <- setup_test_db()
    on.exit(cleanup_test_db(ctx), add = TRUE)

    db_pool <- DBI::dbConnect(RSQLite::SQLite(), ctx$test_db)
    on.exit(DBI::dbDisconnect(db_pool), add = TRUE)
    assign("db_pool", db_pool, envir = globalenv())
    on.exit(rm("db_pool", envir = globalenv()), add = TRUE)

    result <- verify_electronic_signature("SIG_DOES_NOT_EXIST", db_path = ctx$test_db)
    expect_false(isTRUE(result$is_valid))
  })

  # A signature that does exist verifies as valid, and its signature
  # code (not a fabricated one) round-trips through verification.
  local({
    ctx <- setup_test_db()
    on.exit(cleanup_test_db(ctx), add = TRUE)

    sig <- apply_electronic_signature(
      table_name = "test_records", record_id = "1",
      signer_user_id = "USER_TEST_1", signer_full_name = "Jane Doe",
      signature_meaning = "CREATED_BY", password = "correct-horse",
      password_hash = digest::digest(paste0("correct-horse", resolve_auth_salt()),
                                     algo = "sha256"),
      db_path = ctx$test_db
    )
    expect_true(sig$success)

    result <- verify_electronic_signature(sig$signature_code, db_path = ctx$test_db)
    expect_true(result$is_valid)
  })

  # Regression test, added 2026-11-10: output$signature_verification_result's
  # renderUI called a bare small(...) -- not a function anywhere in
  # base R, shiny, or htmltools -- on both the success and failure
  # branches. The two blocks above call verify_electronic_signature()
  # directly, never through the Shiny module's own observeEvent +
  # renderUI, so neither one actually exercises the UI that crashed;
  # this drives it through cfr_compliance_server() itself, the same
  # way a real browser session would, and is exactly how this bug
  # went unnoticed until now.
  local({
    ctx <- setup_test_db()
    on.exit(cleanup_test_db(ctx), add = TRUE)

    db_pool <- DBI::dbConnect(RSQLite::SQLite(), ctx$test_db)
    on.exit(DBI::dbDisconnect(db_pool), add = TRUE)
    assign("db_pool", db_pool, envir = globalenv())
    on.exit(rm("db_pool", envir = globalenv()), add = TRUE)

    result <- tryCatch({
      shiny::testServer(
        zzedc:::cfr_compliance_server,
        args = list(user_id = shiny::reactive("USER_TEST_1")),
        {
          session$setInputs(verify_sig_id = "SIG_DOES_NOT_EXIST", verify_signature = 1)
          session$flushReact()
          output$signature_verification_result
        }
      )
    }, error = function(e) e)

    expect_false(inherits(result, "error"),
                 info = if (inherits(result, "error")) conditionMessage(result) else "")
  })

  # Regression test (2026-11-18): load_compliance_data()'s audit-trail
  # query read "enhanced_audit_trail", a table nothing in the package
  # ever created -- Catalog Error on every study. Its columns
  # (timestamp, user_id) are exactly audit_log's (R/audit_append.R,
  # initialized by launch_zzedc() via init_audit_logging()), so the
  # fix is reading from audit_log instead. system_validation had the
  # same gap with no table at all; ensure_system_validation_table()
  # (R/db_users.R) now closes it, wired into launch_zzedc()'s startup
  # checklist alongside ensure_user_training_table(). This replicates
  # that full checklist directly (launch_zzedc() itself cannot be
  # unit-tested: it ends in a blocking shiny::runApp()) and then runs
  # the dashboard's own two previously-failing queries.
  local({
    ctx <- setup_test_db()
    on.exit(cleanup_test_db(ctx), add = TRUE)

    conn <- DBI::dbConnect(RSQLite::SQLite(), ctx$test_db)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    zzedc:::ensure_user_training_table(conn)
    zzedc:::ensure_system_validation_table(conn)
    expect_true(DBI::dbExistsTable(conn, "system_validation"))

    DBI::dbExecute(conn, "
      INSERT INTO audit_log (timestamp, user_id, event_type, operation)
      VALUES (CURRENT_TIMESTAMP, 'USER_TEST_1', 'LOGIN', 'test login')
    ")

    cutoff <- format(Sys.Date() - 30, "%Y-%m-%d")
    audit_trail <- tryCatch(
      DBI::dbGetQuery(conn, "
        SELECT e.*, u.full_name as user_name
        FROM audit_log e
        JOIN edc_users u ON e.user_id = u.user_id
        WHERE e.timestamp >= ?
        ORDER BY e.timestamp DESC
      ", params = list(cutoff)),
      error = function(e) e
    )
    expect_false(inherits(audit_trail, "error"),
                 info = "the dashboard's audit-trail query must not error on a fresh study")
    expect_equal(nrow(audit_trail), 1L)
    expect_equal(audit_trail$user_name[1], "Jane Doe")

    validations <- tryCatch(
      DBI::dbGetQuery(conn, "
        SELECT v.*, u1.full_name as validator_name,
               u2.full_name as reviewer_name, u3.full_name as approver_name
        FROM system_validation v
        LEFT JOIN edc_users u1 ON v.validator_user_id = u1.user_id
        LEFT JOIN edc_users u2 ON v.reviewer_user_id = u2.user_id
        LEFT JOIN edc_users u3 ON v.approver_user_id = u3.user_id
        ORDER BY v.execution_date DESC
      "),
      error = function(e) e
    )
    expect_false(inherits(validations, "error"),
                 info = "the dashboard's system_validation query must not error on a fresh study")
    expect_equal(nrow(validations), 0L)
  })

}) else {
  exit_file("RSQLite and/or digest not installed")
}
