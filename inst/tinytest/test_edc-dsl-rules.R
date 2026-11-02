library(tinytest)

# Regression tests for R/edc_dsl_rules.R, the generic runtime
# enforcement of dsl_validation_rules (the study data dictionary's
# validation DSL) -- previously imported from Google Sheets but
# never actually run by the EDC tab's submit path.

if (requireNamespace("RSQLite", quietly = TRUE)) {

  .make_dsl_fixture <- function() {
    db_path <- tempfile(fileext = ".db")
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    DBI::dbExecute(conn, "
      CREATE TABLE dsl_validation_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
    ")

    add_rule <- function(rule_id, field_code, form_code, rule_dsl, error_message,
                          is_active = 1, requires_approval = 0, approval_status = "PENDING") {
      DBI::dbExecute(conn, "
        INSERT INTO dsl_validation_rules
          (rule_id, field_code, form_code, rule_dsl, error_message,
           is_active, requires_approval, approval_status,
           imported_by, imported_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'test', datetime('now'))
      ", params = list(rule_id, field_code, form_code, rule_dsl, error_message,
                        is_active, requires_approval, approval_status))
    }

    # Mirrors the real ACCEPT_AFTER_SUBMIT rule imported from this
    # package's own manuscripts data dictionary.
    add_rule(
      "ACCEPT_AFTER_SUBMIT", "acceptance_date", "manuscripts",
      'if acceptance_date != "" then acceptance_date >= submission_date endif',
      "Acceptance date must be on or after submission date"
    )
    add_rule(
      "ENROLL_RANGE", "student_count", "courses",
      "student_count between 1 and 500",
      "Student count must be between 1 and 500"
    )
    # Inactive: must never fire.
    add_rule(
      "RETIRED_RULE", "notes", "manuscripts",
      "notes between 1 and 2", "should never run",
      is_active = 0
    )
    # Requires approval but isn't approved yet: must never fire.
    add_rule(
      "PENDING_RULE", "doi", "manuscripts",
      'doi != ""', "DOI is required",
      requires_approval = 1, approval_status = "PENDING"
    )
    # Requires approval AND is approved: must fire -- unlike
    # PENDING_RULE above, a plain required-ness check (fails on
    # blank, trivially passes once anything is present) isn't a
    # meaningful test here: that is exactly the shape
    # validate_dsl_rules() now deliberately skips when the field is
    # blank (required-ness is validate_crf_submission()'s job, not
    # the DSL engine's), so this uses a range check that can still
    # fail on a PRESENT value instead.
    add_rule(
      "APPROVED_RULE", "draft_number", "manuscripts",
      "draft_number between 1 and 10", "Draft number must be between 1 and 10",
      requires_approval = 1, approval_status = "APPROVED"
    )
    # Malformed DSL: must be skipped, not error out the whole check.
    add_rule(
      "BROKEN_RULE", "status", "manuscripts",
      "this is not >>> valid dsl ((((", "should never surface"
    )

    conn
  }

  local({
    conn <- .make_dsl_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    active <- zzedc:::active_dsl_rules_for_form(conn, "manuscripts")
    expect_equal(sort(active$rule_id), c("ACCEPT_AFTER_SUBMIT", "APPROVED_RULE", "BROKEN_RULE"))

    active_upper <- zzedc:::active_dsl_rules_for_form(conn, "MANUSCRIPTS")
    expect_equal(nrow(active_upper), nrow(active),
                 info = "form_code matched case-insensitively")

    expect_equal(nrow(zzedc:::active_dsl_rules_for_form(conn, "nonexistent_form")), 0)
  })

  local({
    conn <- .make_dsl_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # Guard false (optional field blank) -- passes, no error.
    ok <- list(tracking_id = "PUB-2026-001", submission_date = "2026-01-01",
               acceptance_date = "", draft_number = 5)
    expect_equal(zzedc:::validate_dsl_rules(conn, "manuscripts", ok), list())

    # Guard true, order violated -- flagged, using the rule's own
    # error_message rather than the validator's generic one.
    bad <- list(tracking_id = "PUB-2026-001", submission_date = "2026-02-01",
                acceptance_date = "2026-01-01", draft_number = 5)
    errors <- zzedc:::validate_dsl_rules(conn, "manuscripts", bad)
    expect_equal(errors$acceptance_date$kind, "dsl_rule")
    expect_equal(errors$acceptance_date$message,
                 "Acceptance date must be on or after submission date")

    # A bare (unguarded) rule is skipped, not flagged, while its own
    # field is still blank -- required-ness is validate_crf_submission()'s
    # job, not this one's, and a form still being filled in must not
    # get a premature DSL complaint before the user has typed anything.
    blank_draft <- list(tracking_id = "PUB-2026-001", submission_date = "2026-01-01",
                         acceptance_date = "", draft_number = "")
    errors_blank <- zzedc:::validate_dsl_rules(conn, "manuscripts", blank_draft)
    expect_null(errors_blank$draft_number)

    # The approved requires_approval rule DOES fire once its field
    # actually has a value...
    bad_draft <- list(tracking_id = "PUB-2026-001", submission_date = "2026-01-01",
                       acceptance_date = "", draft_number = 99)
    errors2 <- zzedc:::validate_dsl_rules(conn, "manuscripts", bad_draft)
    expect_equal(errors2$draft_number$message, "Draft number must be between 1 and 10")

    # ...but the still-PENDING one never does, and the inactive one
    # never does, regardless of field_data.
    pending_data <- list(tracking_id = "PUB-2026-001", submission_date = "2026-01-01",
                          acceptance_date = "", draft_number = 5, doi = "", notes = 3)
    errors3 <- zzedc:::validate_dsl_rules(conn, "manuscripts", pending_data)
    expect_null(errors3$doi, info = "requires_approval + still PENDING -- never enforced")
    expect_null(errors3$notes, info = "is_active = 0 -- never enforced")

    # The malformed rule is silently skipped, not a crash and not a
    # false-positive flag.
    status_data <- list(tracking_id = "PUB-2026-001", submission_date = "2026-01-01",
                         acceptance_date = "", draft_number = 5, status = "ideation")
    expect_null(zzedc:::validate_dsl_rules(conn, "manuscripts", status_data)$status)
  })

  local({
    conn <- .make_dsl_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    courses_bad <- list(student_count = 600)
    errors <- zzedc:::validate_dsl_rules(conn, "courses", courses_bad)
    expect_equal(errors$student_count$message, "Student count must be between 1 and 500")

    expect_equal(zzedc:::validate_dsl_rules(conn, NULL, courses_bad), list(),
                 info = "no crf_code -- skipped entirely, no rules fetched")
  })

} else {
  exit_file("RSQLite not installed")
}
