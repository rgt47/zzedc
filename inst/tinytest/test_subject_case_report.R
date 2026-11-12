library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Tests for generate_subject_case_report() (Sec 11.10(b)): the Part 11
# remediation plan's Phase 7 follow-up, assembling one subject's
# data_entries, audit trail, and electronic signatures into a single
# complete-copy report.

if (!exists("generate_subject_case_report")) {
  exit_file("generate_subject_case_report not available")
}

# Internal helpers, bound from the namespace so the file also runs
# against the installed package (R CMD check), not only under load_all().
for (fn in c("ensure_data_entries_table", "ensure_edc_users_table",
             "db_insert_data_entry", "db_insert_user")) assign(fn, get(fn, envir = asNamespace("zzedc")))

setup_case_report_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") Sys.setenv("ZZEDC_OLD_KEY" = old_key)

  test_db <- tempfile(fileext = ".db")
  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  if (!init_result$success) stop("Failed to initialize database: ", init_result$error)
  Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)

  init_audit_logging(db_path = test_db)
  init_electronic_signatures(db_path = test_db)

  conn <- connect_encrypted_db(db_path = test_db)
  ensure_data_entries_table(conn)
  ensure_edc_users_table(conn)

  DBI::dbExecute(conn, "CREATE TABLE IF NOT EXISTS crf_definitions (
    crf_id INTEGER PRIMARY KEY, crf_code TEXT, crf_name TEXT)")
  DBI::dbExecute(conn, "INSERT INTO crf_definitions VALUES (1, 'visit1', 'Visit 1 Form')")
  DBI::dbExecute(conn, "CREATE TABLE IF NOT EXISTS designer_fields (
    field_id INTEGER PRIMARY KEY, design_id INTEGER, field_code TEXT,
    field_label TEXT, field_type TEXT, is_required INTEGER,
    placeholder TEXT, help_text TEXT, default_value TEXT, widget_file TEXT,
    help_detail TEXT, field_row INTEGER, field_column INTEGER)")
  DBI::dbExecute(conn, "INSERT INTO designer_fields
    (field_id, design_id, field_code, field_label, field_type, is_required,
     placeholder, help_text, default_value, widget_file, help_detail,
     field_row, field_column)
    VALUES (1, 1, 'temp_c', 'Temperature (C)', 'NUMBER', 1,
            NULL, NULL, NULL, NULL, NULL, 1, 1)")
  DBI::dbExecute(conn, "CREATE TABLE IF NOT EXISTS designer_field_options (
    option_id INTEGER PRIMARY KEY, field_id INTEGER, option_value TEXT,
    option_label TEXT, option_order INTEGER)")

  db_insert_user(conn, username = "signer1",
                  password_hash = digest::digest("x", algo = "sha256"),
                  full_name = "Dr. Signer", email = "s@example.org",
                  role = "pi", active = TRUE, created_by = "setup")

  entry <- db_insert_data_entry(conn, subject_id = "SUBJ-001", form_name = "visit1",
                                  data = list(temp_c = 37.2), visit_label = "Day 1",
                                  visit_date = "2026-01-05", created_by = "coord1")

  log_audit_event(event_type = "INSERT", table_name = "data_entries",
                   record_id = entry$entry_id, operation = "Created visit1 entry",
                   user_id = "coord1", db_path = test_db)

  apply_electronic_signature(
    table_name = "data_entries", record_id = entry$entry_id,
    signer_user_id = "signer1", signer_full_name = "Dr. Signer",
    signature_meaning = "REVIEWED_BY",
    password = "x", password_hash = digest::digest("x", algo = "sha256"),
    db_path = test_db
  )

  DBI::dbDisconnect(conn)
  list(test_db = test_db, entry_id = entry$entry_id, old_key = old_key)
}

cleanup_case_report_db <- function(fx) {
  unlink(fx$test_db)
  if (fx$old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = fx$old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
}

fx <- setup_case_report_db()

out_txt <- tempfile(fileext = ".txt")
res_txt <- generate_subject_case_report("SUBJ-001", out_txt, format = "txt",
                                          db_path = fx$test_db)
expect_true(res_txt$success, info = "txt report generation succeeds")
expect_equal(res_txt$entry_count, 1L)
expect_true(file.exists(out_txt))

txt_lines <- readLines(out_txt)
txt_body <- paste(txt_lines, collapse = "\n")
expect_true(grepl("Temperature \\(C\\)", txt_body),
            info = "field is rendered under its human-readable label, not its field code")
expect_true(grepl("Day 1", txt_body), info = "visit label is included")
expect_true(grepl("REVIEWED_BY", txt_body) && grepl("VALID", txt_body),
            info = "signature is listed and shown as valid")
expect_true(grepl("INSERT", txt_body), info = "the entry's audit event is listed")
expect_false(grepl("\\.\\.\\. and \\d+ more", txt_body),
             info = "txt report is a complete copy, not a bounded preview")

out_json <- tempfile(fileext = ".json")
res_json <- generate_subject_case_report("SUBJ-001", out_json, format = "json",
                                           db_path = fx$test_db)
expect_true(res_json$success, info = "json report generation succeeds")
parsed <- jsonlite::read_json(out_json)
expect_equal(parsed$subject_id, "SUBJ-001")
expect_equal(parsed$entry_count, 1L)
expect_equal(length(parsed$entries), 1L)
expect_equal(parsed$entries[[1]]$entry_id, fx$entry_id)
expect_true(length(parsed$entries[[1]]$signatures$signature_id) >= 1 ||
              length(parsed$entries[[1]]$signatures) >= 1,
            info = "json report includes the signature")

# A subject with no data_entries rows is not an error: the report
# generates with zero entries, matching generate_signature_report()'s
# own "empty, not refused" convention for a quiet date range.
out_empty <- tempfile(fileext = ".txt")
res_empty <- generate_subject_case_report("NO-SUCH-SUBJECT", out_empty,
                                            db_path = fx$test_db)
expect_true(res_empty$success)
expect_equal(res_empty$entry_count, 0L)

# subject_id is required.
res_missing_id <- generate_subject_case_report(NULL, tempfile(fileext = ".txt"),
                                                  db_path = fx$test_db)
expect_false(res_missing_id$success)

unlink(c(out_txt, out_json, out_empty))
cleanup_case_report_db(fx)
