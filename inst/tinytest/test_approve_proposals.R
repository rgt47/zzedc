library(tinytest)

# Regression tests for approve_proposals() (R/gsheets_monitor.R),
# which had zero test coverage before this file. Covers the batched
# proposal/rule lookups added to fix the N+1 query pattern in the
# per-id loop (one SELECT ... WHERE proposal_id = ? and one SELECT
# ... WHERE rule_id = ? per id, now one IN (...) query each): not
# found, not PENDING, the NEW-rule INSERT path, the existing-rule
# UPDATE/version-bump path, and a single call covering several ids
# at once (the case the batching itself changed).

if (requireNamespace("RSQLite", quietly = TRUE)) {

  .make_approve_fixture <- function() {
    db_path <- tempfile(fileext = ".db")
    init_res <- initialize_encrypted_database(db_path = db_path)
    zzedc:::init_proposals_table(db_path = db_path)

    conn <- connect_encrypted_db(db_path = db_path, key = init_res$key)
    zzedc:::prepare_auto_increment(conn, "dsl_validation_rules", "id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS dsl_validation_rules (
        id %s,
        rule_id TEXT UNIQUE NOT NULL,
        field_code TEXT NOT NULL,
        form_code TEXT,
        rule_name TEXT,
        rule_dsl TEXT NOT NULL,
        compiled_r TEXT,
        compiled_sql TEXT,
        error_message TEXT,
        severity TEXT DEFAULT 'ERROR',
        rule_category TEXT DEFAULT 'FIELD',
        is_active INTEGER DEFAULT 1,
        requires_approval INTEGER DEFAULT 0,
        approval_status TEXT DEFAULT 'PENDING',
        approved_by TEXT,
        approved_at TEXT,
        imported_by TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        updated_by TEXT,
        updated_at TEXT,
        version INTEGER DEFAULT 1
      )
    ", zzedc:::auto_increment_ddl("dsl_validation_rules", "id")))
    DBI::dbDisconnect(conn)

    list(db_path = db_path, key = init_res$key)
  }

  .add_proposal <- function(db_path, key, proposal_id, rule_id,
                             status = "PENDING", field_code = "age") {
    conn <- connect_encrypted_db(db_path = db_path, key = key)
    on.exit(DBI::dbDisconnect(conn))
    DBI::dbExecute(conn, "
      INSERT INTO dsl_rule_proposals
        (proposal_id, rule_id, change_type, proposed_dsl, current_dsl,
         field_code, form_code, rule_name, error_message, severity,
         rule_category, sheet_id, staged_by, staged_at, status)
      VALUES (?, ?, 'NEW', ?, NULL, ?, NULL, NULL, NULL, 'ERROR',
              'FIELD', 'sheet1', 'tester', ?, ?)
    ", params = list(proposal_id, rule_id, paste0(field_code, " >= 18"),
                     field_code, as.character(Sys.time()), status))
  }

  .add_existing_rule <- function(db_path, key, rule_id, field_code = "age",
                                  version = 1L) {
    conn <- connect_encrypted_db(db_path = db_path, key = key)
    on.exit(DBI::dbDisconnect(conn))
    DBI::dbExecute(conn, "
      INSERT INTO dsl_validation_rules
        (rule_id, field_code, rule_dsl, approval_status, imported_by,
         imported_at, version)
      VALUES (?, ?, ?, 'APPROVED', 'tester', ?, ?)
    ", params = list(rule_id, field_code, paste0(field_code, " >= 10"),
                     as.character(Sys.time()), version))
  }

  # Test: approving a brand-new rule inserts it, version 1
  local({
    fx <- .make_approve_fixture()
    on.exit(unlink(fx$db_path))
    .add_proposal(fx$db_path, fx$key, "P1", "RULE1")

    result <- suppressWarnings(approve_proposals(
      "P1", reviewer_id = "reviewer1", db_path = fx$db_path,
      comments = "looks fine"
    ))

    expect_equal(result$approved, 1L)
    expect_equal(length(result$errors), 0L)

    conn <- connect_encrypted_db(db_path = fx$db_path, key = fx$key)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    rule <- DBI::dbGetQuery(conn, "SELECT * FROM dsl_validation_rules WHERE rule_id = 'RULE1'")
    expect_equal(nrow(rule), 1L)
    expect_equal(rule$approval_status[1], "APPROVED")
    expect_equal(rule$version[1], 1L)

    proposal <- DBI::dbGetQuery(conn, "SELECT status FROM dsl_rule_proposals WHERE proposal_id = 'P1'")
    expect_equal(proposal$status[1], "APPROVED")
  })

  # Test: approving a proposal for an already-existing rule updates
  # it in place and bumps the version
  local({
    fx <- .make_approve_fixture()
    on.exit(unlink(fx$db_path))
    .add_existing_rule(fx$db_path, fx$key, "RULE2", version = 3L)
    .add_proposal(fx$db_path, fx$key, "P2", "RULE2")

    result <- suppressWarnings(approve_proposals(
      "P2", reviewer_id = "reviewer1", db_path = fx$db_path,
      comments = "version bump"
    ))

    expect_equal(result$approved, 1L)

    conn <- connect_encrypted_db(db_path = fx$db_path, key = fx$key)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    rule <- DBI::dbGetQuery(conn, "SELECT * FROM dsl_validation_rules WHERE rule_id = 'RULE2'")
    expect_equal(nrow(rule), 1L)
    expect_equal(rule$version[1], 4L)
  })

  # Test: a nonexistent proposal_id reports "Proposal not found" and
  # does not prevent other ids in the same call from being processed
  local({
    fx <- .make_approve_fixture()
    on.exit(unlink(fx$db_path))
    .add_proposal(fx$db_path, fx$key, "P3", "RULE3")

    result <- suppressWarnings(approve_proposals(
      c("P3", "DOES_NOT_EXIST"), reviewer_id = "reviewer1",
      db_path = fx$db_path, comments = "mixed batch"
    ))

    expect_equal(result$approved, 1L)
    expect_equal(result$errors[["DOES_NOT_EXIST"]], "Proposal not found")
  })

  # Test: a proposal that is not PENDING is rejected with a status
  # message naming its actual status, and is not re-approved
  local({
    fx <- .make_approve_fixture()
    on.exit(unlink(fx$db_path))
    .add_proposal(fx$db_path, fx$key, "P4", "RULE4", status = "REJECTED")

    result <- suppressWarnings(approve_proposals(
      "P4", reviewer_id = "reviewer1", db_path = fx$db_path,
      comments = "should not apply"
    ))

    expect_equal(result$approved, 0L)
    expect_true(grepl("REJECTED", result$errors[["P4"]], fixed = TRUE))
    expect_true(grepl("not PENDING", result$errors[["P4"]], fixed = TRUE))
  })

  # Test: a single call approving several ids at once -- the exact
  # case the batched proposal/rule lookups replaced a per-id SELECT
  # loop for. Mixes a new rule, an existing rule needing a version
  # bump, and a not-found id, confirming the batched lookups still
  # route each id to the right outcome.
  local({
    fx <- .make_approve_fixture()
    on.exit(unlink(fx$db_path))
    .add_proposal(fx$db_path, fx$key, "P5", "RULE5")
    .add_existing_rule(fx$db_path, fx$key, "RULE6", version = 1L)
    .add_proposal(fx$db_path, fx$key, "P6", "RULE6")
    .add_proposal(fx$db_path, fx$key, "P7", "RULE7")

    result <- suppressWarnings(approve_proposals(
      c("P5", "P6", "P7", "MISSING"), reviewer_id = "reviewer1",
      db_path = fx$db_path, comments = "batch of several"
    ))

    expect_equal(result$approved, 3L)
    expect_equal(result$errors[["MISSING"]], "Proposal not found")

    conn <- connect_encrypted_db(db_path = fx$db_path, key = fx$key)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    rules <- DBI::dbGetQuery(
      conn,
      "SELECT rule_id, version, approval_status FROM dsl_validation_rules ORDER BY rule_id"
    )
    expect_equal(rules$rule_id, c("RULE5", "RULE6", "RULE7"))
    expect_true(all(rules$approval_status == "APPROVED"))
    expect_equal(rules[rules$rule_id == "RULE6", "version"], 2L)
  })

} else {
  exit_file("RSQLite not available")
}
