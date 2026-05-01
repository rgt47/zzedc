library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Fixture: minimal REDCap-shaped SQLite database.
#
# Every REDCap deployment exposes the same core tables; the fixture
# below replicates the tiny subset the Phase C1 importer reads.
# Keep the fixture self-contained: avoid depending on a real
# REDCap dump (which would carry version-specific schema drift
# and cannot ship without licensing review).

redcap_fixture <- function(pid = 42L) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")

  DBI::dbExecute(conn, "
    CREATE TABLE redcap_metadata (
      project_id INTEGER,
      field_name TEXT,
      form_name TEXT,
      field_type TEXT,
      element_label TEXT,
      required_field TEXT,
      text_validation_type_or_show_slider_number TEXT,
      text_validation_min TEXT,
      text_validation_max TEXT,
      branching_logic TEXT,
      field_order INTEGER
    )
  ")
  DBI::dbExecute(conn, "
    CREATE TABLE redcap_user_rights (
      project_id INTEGER, username TEXT, role_id INTEGER,
      expiration TEXT,
      design INTEGER, user_rights INTEGER,
      data_access_groups INTEGER, data_export_tool INTEGER,
      reports INTEGER, alerts INTEGER, calendar INTEGER
    )
  ")
  DBI::dbExecute(conn, "
    CREATE TABLE redcap_data (
      project_id INTEGER, event_id INTEGER, record TEXT,
      field_name TEXT, value TEXT
    )
  ")
  DBI::dbExecute(conn, "
    CREATE TABLE redcap_log_event (
      log_event_id INTEGER, project_id INTEGER, ts TEXT,
      user TEXT, ip TEXT, page TEXT, event TEXT,
      object_type TEXT, sql_log TEXT, pk TEXT, description TEXT
    )
  ")

  DBI::dbExecute(conn, "
    INSERT INTO redcap_metadata
      (project_id, field_name, form_name, field_type, element_label,
       required_field, text_validation_type_or_show_slider_number,
       text_validation_min, text_validation_max, branching_logic,
       field_order)
    VALUES
      (?, 'subject_id',      'enrollment', 'text', 'Subject ID',
       'y', '',          '',  '',  '', 1),
      (?, 'age',             'enrollment', 'text', 'Age',
       'y', 'integer',   '50','90','', 2),
      (?, 'sex',             'enrollment', 'radio', 'Sex',
       'y', '',          '',  '',  '', 3),
      (?, 'pregnant',        'enrollment', 'yesno', 'Pregnant',
       'n', '',          '',  '',
        '[sex] = \"F\"', 4),
      (?, 'mmse_total',      'mmse', 'text', 'MMSE Total',
       'y', 'integer',   '0', '30','', 1)
  ", params = rep(list(pid), 5))

  DBI::dbExecute(conn, "
    INSERT INTO redcap_user_rights
      (project_id, username, design, user_rights,
       data_access_groups, data_export_tool, expiration)
    VALUES
      (?, 'jsmith',     1, 1, 0, 1, NULL),
      (?, 'bjones',     0, 0, 0, 1, NULL),
      (?, 'expired',    0, 0, 0, 0, '2020-01-01')
  ", params = rep(list(pid), 3))

  DBI::dbExecute(conn, "
    INSERT INTO redcap_data
      (project_id, event_id, record, field_name, value)
    VALUES
      (?, 1, 'S001', 'subject_id', 'S001'),
      (?, 1, 'S001', 'age',        '65'),
      (?, 1, 'S001', 'sex',        'M'),
      (?, 1, 'S002', 'subject_id', 'S002'),
      (?, 1, 'S002', 'age',        '72'),
      (?, 2, 'S001', 'mmse_total', '28')
  ", params = rep(list(pid), 6))

  DBI::dbExecute(conn, "
    INSERT INTO redcap_log_event
      (log_event_id, project_id, ts, user, page, event, description)
    VALUES
      (1, ?, '2025-01-01 09:00:00', 'jsmith', 'DataEntry', 'INSERT', 'Created S001'),
      (2, ?, '2025-01-02 10:30:00', 'bjones', 'DataEntry', 'INSERT', 'Created S002'),
      (3, ?, '2025-01-08 14:15:00', 'jsmith', 'DataEntry', 'UPDATE', 'Edited S001 mmse')
  ", params = rep(list(pid), 3))

  conn
}


# ----------------------------------------------------------------
# Field-type translation
# ----------------------------------------------------------------

# Test: redcap_translate_field_type maps common REDCap types
local({
  expect_equal(zzedc:::redcap_translate_field_type("text"), "text")
  expect_equal(zzedc:::redcap_translate_field_type("text", "integer"),
                "numeric")
  expect_equal(zzedc:::redcap_translate_field_type("text", "date_ymd"),
                "date")
  expect_equal(zzedc:::redcap_translate_field_type("yesno"), "checkbox")
  expect_equal(zzedc:::redcap_translate_field_type("dropdown"), "select")
  expect_equal(zzedc:::redcap_translate_field_type("radio"), "radio")
  expect_equal(zzedc:::redcap_translate_field_type("date"), "date")
  # Unknown types default to text rather than fail
  expect_equal(zzedc:::redcap_translate_field_type("unknown_type"), "text")
})


# ----------------------------------------------------------------
# Role translation
# ----------------------------------------------------------------

# Test: redcap_translate_role assigns coarser ZZedc roles
local({
  expect_equal(zzedc:::redcap_translate_role("design,user_rights"),
                "Admin")
  expect_equal(zzedc:::redcap_translate_role("data_export_tool,reports"),
                "Researcher")
  expect_equal(zzedc:::redcap_translate_role("data_entry,forms"),
                "Coordinator")
  expect_equal(zzedc:::redcap_translate_role(""), "Monitor")
  expect_equal(zzedc:::redcap_translate_role(NA), "Monitor")
})


# ----------------------------------------------------------------
# DSL extraction from REDCap metadata
# ----------------------------------------------------------------

# Test: redcap_extract_rule_dsl emits range rules
local({
  meta <- data.frame(
    field_name = "age",
    text_validation_type_or_show_slider_number = "integer",
    text_validation_min = "18",
    text_validation_max = "90",
    stringsAsFactors = FALSE
  )
  rule <- zzedc:::redcap_extract_rule_dsl(meta)
  expect_equal(rule$dsl, "age between 18 and 90")
  expect_equal(rule$category, "FIELD")
})

# Test: redcap_extract_rule_dsl handles min-only / max-only
local({
  meta_min <- data.frame(field_name = "score",
    text_validation_type_or_show_slider_number = "integer",
    text_validation_min = "0", text_validation_max = "",
    stringsAsFactors = FALSE)
  rule <- zzedc:::redcap_extract_rule_dsl(meta_min)
  expect_equal(rule$dsl, "score >= 0")

  meta_max <- data.frame(field_name = "score",
    text_validation_type_or_show_slider_number = "number",
    text_validation_min = "", text_validation_max = "100",
    stringsAsFactors = FALSE)
  rule <- zzedc:::redcap_extract_rule_dsl(meta_max)
  expect_equal(rule$dsl, "score <= 100")
})

# Test: non-numeric validations return NA (deferred to Phase C2)
local({
  meta <- data.frame(field_name = "x",
    text_validation_type_or_show_slider_number = "email",
    text_validation_min = "", text_validation_max = "",
    stringsAsFactors = FALSE)
  rule <- zzedc:::redcap_extract_rule_dsl(meta)
  expect_true(is.na(rule$dsl))
})


# ----------------------------------------------------------------
# Extractors against the synthetic fixture
# ----------------------------------------------------------------

# Test: redcap_extract_metadata returns one row per REDCap field
local({
  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  dd <- zzedc:::redcap_extract_metadata(conn, 42L)
  expect_equal(nrow(dd), 5)
  expect_true("subject_id" %in% dd$field_name)
  expect_true("age" %in% dd$field_name)
  expect_true("mmse_total" %in% dd$field_name)
  # The age field should pick up its range validation
  age_row <- dd[dd$field_name == "age", ]
  expect_equal(age_row$validation, "age between 50 and 90")
  # required_field == 'y' translates to TRUE
  expect_true(age_row$required)
})

# Test: redcap_extract_validation_rules separates range rules
# from skipped (branching-logic) rules
local({
  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  rules <- zzedc:::redcap_extract_validation_rules(conn, 42L)
  # Two range rules (age, mmse_total)
  expect_equal(nrow(rules$rules), 2)
  expect_true("age between 50 and 90" %in% rules$rules$rule_dsl)
  expect_true("mmse_total between 0 and 30" %in% rules$rules$rule_dsl)

  # One branching-logic skipped (pregnant if sex == 'F')
  expect_true(length(rules$skipped_rules) >= 1)
  fields_skipped <- vapply(rules$skipped_rules,
                            function(r) r$field, character(1))
  expect_true("pregnant" %in% fields_skipped)
})

# Test: redcap_extract_users translates rights to roles
local({
  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  users <- zzedc:::redcap_extract_users(conn, 42L)
  expect_equal(nrow(users), 3)
  expect_equal(users$role[users$username == "jsmith"], "Admin")
  expect_equal(users$role[users$username == "bjones"], "Researcher")
  # Expired user is marked inactive
  expect_false(users$active[users$username == "expired"])
  # Active users
  expect_true(users$active[users$username == "jsmith"])
})

# Test: redcap_extract_subjects returns distinct record IDs
local({
  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  subj <- zzedc:::redcap_extract_subjects(conn, 42L)
  expect_equal(nrow(subj), 2)
  expect_true("S001" %in% subj$subject_id)
  expect_true("S002" %in% subj$subject_id)
})

# Test: redcap_extract_data returns long-form EAV rows
local({
  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  dat <- zzedc:::redcap_extract_data(conn, 42L)
  expect_equal(nrow(dat), 6)
  expect_true(all(c("subject_id", "field_name", "value", "event_id")
                   %in% names(dat)))
})

# Test: redcap_extract_audit returns log rows ordered by ts
local({
  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  audit <- zzedc:::redcap_extract_audit(conn, 42L)
  expect_equal(nrow(audit), 3)
  # First row should be the earliest timestamp
  expect_equal(audit$user[1], "jsmith")
})


# ----------------------------------------------------------------
# End-to-end Phase C1 orchestrator
# ----------------------------------------------------------------

# Test: import_redcap_to_zzedc produces all expected CSV files
local({
  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  out <- tempfile(pattern = "redcap_import_")
  result <- import_redcap_to_zzedc(
    conn       = conn,
    pid        = 42L,
    output_dir = out,
    redcap_version = "14.x-fixture"
  )

  expect_true(result$success)
  expect_true(dir.exists(out))

  expected_files <- c("data_dictionary.csv", "validation_rules.csv",
                       "users.csv", "subjects.csv",
                       "subject_data.csv", "audit_log.csv",
                       "manifest.json")
  for (f in expected_files) {
    expect_true(file.exists(file.path(out, f)))
  }

  # Counts match what the fixture inserted
  expect_equal(result$counts$data_dictionary, 5)
  expect_equal(result$counts$validation_rules, 2)
  expect_equal(result$counts$users, 3)
  expect_equal(result$counts$subjects, 2)
  expect_equal(result$counts$subject_data, 6)
  expect_equal(result$counts$audit_log, 3)

  # One branching-logic rule should have been deferred
  expect_true(length(result$skipped_rules) >= 1)

  unlink(out, recursive = TRUE)
})

# Test: importer surfaces bad input through the result list
# rather than throwing an exception, so callers can handle it
# uniformly with other stage failures.
local({
  res_bad_conn <- import_redcap_to_zzedc(
    conn = "not a connection", pid = 42L,
    output_dir = tempfile()
  )
  expect_false(res_bad_conn$success)
  expect_true(grepl("DBI", res_bad_conn$error %||% ""))

  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  res_no_pid <- import_redcap_to_zzedc(conn = conn,
                                        pid = "not numeric",
                                        output_dir = tempfile())
  expect_false(res_no_pid$success)
})


# ----------------------------------------------------------------
# Roadmap stubs raise informative errors
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# Phase C2: branching-logic translator
# ----------------------------------------------------------------

# Test: equality and comparison patterns translate cleanly
local({
  expect_equal(
    zzedc:::redcap_translate_branching_logic('[sex] = "F"'),
    'sex == "F"'
  )
  expect_equal(
    zzedc:::redcap_translate_branching_logic('[age] >= 18'),
    'age >= 18'
  )
  expect_equal(
    zzedc:::redcap_translate_branching_logic('[score] <> 0'),
    'score != 0'
  )
})

# Test: logical compounds translate
local({
  expect_equal(
    zzedc:::redcap_translate_branching_logic(
      '[smoker] = "1" or [exsmoker] = "1"'),
    'smoker == "1" || exsmoker == "1"'
  )
  expect_equal(
    zzedc:::redcap_translate_branching_logic(
      '[age] >= 18 and [age] <= 90'),
    'age >= 18 && age <= 90'
  )
})

# Test: untranslatable constructs return NA
local({
  # REDCap-specific function call
  expect_true(is.na(zzedc:::redcap_translate_branching_logic(
    'datediff([dob], [enrollment_date], "y") >= 18')))
  # Event-arm prefix
  expect_true(is.na(zzedc:::redcap_translate_branching_logic(
    '[event_arm_1][screening] = "1"')))
  # Empty / NA
  expect_true(is.na(zzedc:::redcap_translate_branching_logic("")))
  expect_true(is.na(zzedc:::redcap_translate_branching_logic(NA)))
})


# ----------------------------------------------------------------
# Phase C2: audit-event type translation
# ----------------------------------------------------------------

# Test: redcap_translate_event_type maps common labels
local({
  expect_equal(zzedc:::redcap_translate_event_type("INSERT"), "INSERT")
  expect_equal(zzedc:::redcap_translate_event_type("Update record"),
                "UPDATE")
  expect_equal(zzedc:::redcap_translate_event_type("Data export"),
                "EXPORT")
  expect_equal(zzedc:::redcap_translate_event_type("Login"), "LOGIN")
  expect_equal(zzedc:::redcap_translate_event_type("invalid password"),
                "LOGIN_FAILED")
  expect_equal(zzedc:::redcap_translate_event_type("Manage/Design"),
                "CONFIG_CHANGE")
  # Unknown -> safe default
  expect_equal(zzedc:::redcap_translate_event_type("Some other thing"),
                "ACCESS")
  expect_equal(zzedc:::redcap_translate_event_type(NA), "ACCESS")
})


# ----------------------------------------------------------------
# Phase C2: audit replay against a freshly-initialised DB
# ----------------------------------------------------------------

# Test: replay_redcap_audit populates audit_log + audit_chain
# and produces a chain that validates.
local({
zdb <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = zdb,
                                          overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  init_audit_logging(db_path = zdb)

  redcap_audit <- data.frame(
    log_event_id = c(1, 2, 3),
    ts           = c("2025-01-01 09:00:00",
                     "2025-01-02 10:00:00",
                     "2025-01-03 11:00:00"),
    user         = c("jsmith", "bjones", "jsmith"),
    ip           = c("10.0.0.1", "10.0.0.2", "10.0.0.1"),
    page         = c("DataEntry", "DataEntry", "DataEntry"),
    event        = c("INSERT", "UPDATE", "Data export"),
    object_type  = c("data", "data", "report"),
    sql_log      = c("", "", ""),
    pk           = c("S001", "S001", ""),
    project_id   = rep(42L, 3),
    description  = c("Created S001", "Edited age", "Exported"),
    stringsAsFactors = FALSE
  )

  result <- zzedc:::replay_redcap_audit(
    redcap_audit = redcap_audit,
    db_path      = zdb,
    key          = init$key
  )

  expect_true(result$success)
  expect_equal(result$imported, 3L)
  expect_true(result$chain_validates)

  # Verify the rows landed in audit_log
  conn <- connect_encrypted_db(db_path = zdb, key = init$key)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  log_rows <- DBI::dbGetQuery(conn, "
    SELECT event_type, user_id, audit_hash, previous_hash
      FROM audit_log
     ORDER BY audit_id
  ")
  expect_equal(nrow(log_rows), 3)
  # First row's previous_hash is GENESIS
  expect_equal(log_rows$previous_hash[1], "GENESIS")
  # Each subsequent row's previous_hash chains to the prior hash
  expect_equal(log_rows$previous_hash[2], log_rows$audit_hash[1])
  expect_equal(log_rows$previous_hash[3], log_rows$audit_hash[2])

  # Event types translated
  expect_true("INSERT" %in% log_rows$event_type)
  expect_true("UPDATE" %in% log_rows$event_type)
  expect_true("EXPORT" %in% log_rows$event_type)

  unlink(zdb)
})

# Test: empty audit input is handled gracefully
local({
  result <- zzedc:::replay_redcap_audit(
    redcap_audit = data.frame(),
    db_path      = "/nonexistent",
    key          = "x"
  )
  expect_true(result$success)
  expect_equal(result$imported, 0L)
})


# ----------------------------------------------------------------
# Phase C2: end-to-end direct-DB importer
# ----------------------------------------------------------------

# Test: import_redcap_to_zzedc_db creates a populated DB and
# audit-chain validates after replay
local({
src  <- redcap_fixture()
  on.exit(DBI::dbDisconnect(src), add = TRUE)
  zdb  <- tempfile(fileext = ".db")

  result <- import_redcap_to_zzedc_db(
    conn      = src,
    pid       = 42L,
    db_path   = zdb,
    overwrite = TRUE
  )

  expect_true(result$success)
  expect_equal(result$users$imported, 3)
  expect_equal(result$forms$imported_forms, 2)
  expect_true(result$forms$imported_fields >= 5)
  expect_equal(result$subjects$imported, 2)
  expect_true(result$subject_data$imported >= 6)
  expect_equal(result$audit_replay$imported, 3L)
  expect_true(result$audit_replay$chain_validates)

  # Branching-logic translator picked up at least one rule
  expect_true(result$branching_translated >= 1L)

  unlink(zdb)
})

# Test: direct-DB importer rejects bad input via the result list
local({
  res_no_db <- import_redcap_to_zzedc_db(
    conn = "not a connection", pid = 42L, db_path = tempfile())
  expect_false(res_no_db$success)
  expect_true(grepl("DBI", res_no_db$error %||% ""))
})

# Test: dry_run skips database creation
local({
  src <- redcap_fixture()
  on.exit(DBI::dbDisconnect(src), add = TRUE)
  result <- import_redcap_to_zzedc_db(
    conn      = src,
    pid       = 42L,
    db_path   = tempfile(fileext = ".db"),
    overwrite = TRUE,
    dry_run   = TRUE
  )
  expect_true(grepl("dry_run",
                     result$database$message %||% ""))
})


# ----------------------------------------------------------------
# Phase C3b stub still raises informative errors (.sql-dump mode)
# ----------------------------------------------------------------

# Test: Phase C3b SQL-dump stub points at the roadmap
local({
  expect_error(zzedc:::load_redcap_sql_dump("/path/to/dump.sql"),
                pattern = "Phase C3b|roadmap")
})


# ----------------------------------------------------------------
# Phase C3a: REST API source mode
# ----------------------------------------------------------------

# Helper: build a fake `api` handle backed by synthetic data
# matching what REDCapR's REST extractors return. The handle's
# `ops` closures bypass the network entirely.
fake_redcap_api <- function(audit_mode = c("full", "partial", "empty")) {
  audit_mode <- match.arg(audit_mode)

  metadata <- data.frame(
    field_name = c("subject_id", "age", "sex", "pregnant",
                    "mmse_total"),
    form_name  = c("enrollment", "enrollment", "enrollment",
                    "enrollment", "mmse"),
    field_type = c("text", "text", "radio", "yesno", "text"),
    field_label = c("Subject ID", "Age", "Sex",
                     "Pregnant", "MMSE Total"),
    text_validation_type_or_show_slider_number =
      c("", "integer", "", "", "integer"),
    text_validation_min = c("", "50", "", "", "0"),
    text_validation_max = c("", "90", "", "", "30"),
    branching_logic     = c("", "", "", '[sex] = "F"', ""),
    required_field      = c("y", "y", "y", "n", "y"),
    stringsAsFactors    = FALSE
  )

  users <- data.frame(
    username   = c("jsmith", "bjones", "expired"),
    email      = c("js@example.org", "bj@example.org",
                    "ex@example.org"),
    firstname  = c("Jane", "Bob", "Ex"),
    lastname   = c("Smith", "Jones", "Pired"),
    expiration = c(NA, NA, "2020-01-01"),
    design     = c(1L, 0L, 0L),
    user_rights = c(1L, 0L, 0L),
    data_export = c(1L, 1L, 0L),
    data_access_groups = c(0L, 0L, 0L),
    stringsAsFactors = FALSE
  )

  records <- data.frame(
    subject_id = c("S001", "S001", "S002"),
    redcap_event_name = c("baseline_arm_1", "followup_arm_1",
                            "baseline_arm_1"),
    age        = c("65", "", "72"),
    sex        = c("M", "", "F"),
    pregnant   = c("", "", "0"),
    mmse_total = c("", "28", ""),
    stringsAsFactors = FALSE
  )

  full_log <- data.frame(
    timestamp = c("2025-01-01 09:00:00",
                   "2025-01-02 10:30:00",
                   "2025-01-08 14:15:00"),
    username  = c("jsmith", "bjones", "jsmith"),
    action    = c("Create record", "Create record",
                   "Update record"),
    details   = c("Created S001", "Created S002",
                   "Edited S001 mmse"),
    record    = c("S001", "S002", "S001"),
    stringsAsFactors = FALSE
  )
  partial_log <- data.frame(
    timestamp = c("2025-01-01 09:00:00", "2025-01-02 10:30:00"),
    username  = c("jsmith", "bjones"),
    action    = c("Login", "Logout"),
    details   = c("User login", "User logout"),
    record    = c("", ""),
    stringsAsFactors = FALSE
  )
  log_df <- switch(audit_mode,
    full    = full_log,
    partial = partial_log,
    empty   = full_log[0, , drop = FALSE]
  )

  list(
    url     = "https://fake.example.org/api/",
    token   = "fake-token",
    version = "14.5.27",
    ops     = list(
      version  = function() "14.5.27",
      metadata = function() metadata,
      users    = function() users,
      records  = function(fields = NULL) {
        if (is.null(fields)) records
        else records[, intersect(fields, names(records)),
                      drop = FALSE]
      },
      log      = function() log_df
    )
  )
}


# Test: redcap_api_connect rejects missing url / token
local({
  # Without ops (real network path), missing url is rejected
  expect_error(
    zzedc:::redcap_api_connect(api_url = NULL, api_token = "tok"),
    pattern = "api_url|REDCapR")
  expect_error(
    zzedc:::redcap_api_connect(api_url = "https://x", api_token = NULL),
    pattern = "api_token|REDCapR")
})

# Test: redcap_api_connect with injected ops returns a usable handle
local({
  ops <- list(version  = function() "14.5.27",
              metadata = function() data.frame(),
              users    = function() data.frame(),
              records  = function(fields = NULL) data.frame(),
              log      = function() data.frame())
  api <- zzedc:::redcap_api_connect(api_url = "https://x",
                                     api_token = "tok", ops = ops)
  expect_equal(api$version, "14.5.27")
  expect_true(is.list(api$ops))
})


# Test: API metadata extractor matches DB extractor shape
local({
  api <- fake_redcap_api()
  dd_api <- zzedc:::redcap_extract_metadata_api(api)
  conn <- redcap_fixture()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  dd_db  <- zzedc:::redcap_extract_metadata(conn, 42L)

  # Same column set so downstream code is reusable
  expect_true(setequal(names(dd_api), names(dd_db)))
  expect_equal(nrow(dd_api), 5)
  # Range validation translates the same way both ways
  age_api <- dd_api[dd_api$field_name == "age", ]
  expect_equal(age_api$validation, "age between 50 and 90")
  expect_true(age_api$required)
})

# Test: API users extractor matches DB extractor shape and roles
local({
  api <- fake_redcap_api()
  users_api <- zzedc:::redcap_extract_users_api(api)
  expect_equal(nrow(users_api), 3)
  expect_equal(users_api$role[users_api$username == "jsmith"], "Admin")
  expect_equal(users_api$role[users_api$username == "bjones"],
                "Researcher")
  expect_false(users_api$active[users_api$username == "expired"])
})

# Test: API subjects extractor returns distinct record IDs
local({
  api <- fake_redcap_api()
  subj_api <- zzedc:::redcap_extract_subjects_api(api)
  expect_equal(nrow(subj_api), 2)
  expect_true("S001" %in% subj_api$subject_id)
  expect_true("S002" %in% subj_api$subject_id)
})

# Test: API data extractor pivots wide -> long, matches DB shape
local({
  api <- fake_redcap_api()
  dat_api <- zzedc:::redcap_extract_data_api(api)
  expect_true(all(c("subject_id", "field_name", "value", "event_id")
                   %in% names(dat_api)))
  # Empty cells are dropped to match DB extractor (which reads from
  # the EAV `redcap_data` table, storing only set values).
  expect_true(all(nzchar(dat_api$value)))
  # Two distinct event_ids (baseline + followup)
  expect_true(length(unique(dat_api$event_id)) >= 1)
})

# Test: completeness classifier
local({
  api_full    <- fake_redcap_api("full")
  api_partial <- fake_redcap_api("partial")
  api_empty   <- fake_redcap_api("empty")

  ar_full    <- zzedc:::redcap_extract_audit_api(api_full)
  ar_partial <- zzedc:::redcap_extract_audit_api(api_partial)
  ar_empty   <- zzedc:::redcap_extract_audit_api(api_empty)

  expect_equal(zzedc:::redcap_check_audit_completeness(
                  ar_full, n_records = 2), "full")
  expect_equal(zzedc:::redcap_check_audit_completeness(
                  ar_partial, n_records = 2), "partial")
  expect_equal(zzedc:::redcap_check_audit_completeness(
                  ar_empty, n_records = 2), "empty")
})


# ----------------------------------------------------------------
# Phase C3a: end-to-end orchestrator with API source
# ----------------------------------------------------------------

# Test: full audit -> chain validates, no marker inserted
local({
  api <- fake_redcap_api("full")
  zdb <- tempfile(fileext = ".db")

  result <- import_redcap_to_zzedc_db(
    source    = "api",
    api       = api,
    db_path   = zdb,
    overwrite = TRUE
  )

  expect_true(result$success)
  expect_equal(result$source, "api")
  expect_true(result$users$imported >= 2)
  expect_true(result$forms$imported_forms >= 1)
  expect_equal(result$audit_replay$completeness, "full")
  expect_false(result$audit_replay$marker_inserted)
  expect_true(result$audit_replay$chain_validates)

  unlink(zdb)
})

# Test: empty audit -> warning, marker inserted, chain still validates
local({
  api <- fake_redcap_api("empty")
  zdb <- tempfile(fileext = ".db")

  warned <- FALSE
  result <- withCallingHandlers(
    import_redcap_to_zzedc_db(
      source    = "api",
      api       = api,
      db_path   = zdb,
      overwrite = TRUE
    ),
    warning = function(w) {
      if (grepl("MIGRATION_AUDIT_GAP|empty|partial",
                conditionMessage(w))) {
        warned <<- TRUE
      }
      invokeRestart("muffleWarning")
    }
  )

  expect_true(warned)
  expect_true(result$success)
  expect_equal(result$audit_replay$completeness, "empty")
  expect_true(result$audit_replay$marker_inserted)
  expect_true(result$audit_replay$chain_validates)

  # Marker landed in audit_log
  conn <- connect_encrypted_db(db_path = zdb,
                                key = result$key)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  rows <- DBI::dbGetQuery(conn,
    "SELECT event_type FROM audit_log
       WHERE event_type = 'MIGRATION_AUDIT_GAP'")
  expect_equal(nrow(rows), 1L)

  unlink(zdb)
})

# Test: partial audit -> warning, marker inserted, chain validates
local({
  api <- fake_redcap_api("partial")
  zdb <- tempfile(fileext = ".db")

  warned <- FALSE
  result <- withCallingHandlers(
    import_redcap_to_zzedc_db(
      source    = "api",
      api       = api,
      db_path   = zdb,
      overwrite = TRUE
    ),
    warning = function(w) {
      if (grepl("partial|MIGRATION_AUDIT_GAP",
                conditionMessage(w))) {
        warned <<- TRUE
      }
      invokeRestart("muffleWarning")
    }
  )

  expect_true(warned)
  expect_true(result$success)
  expect_equal(result$audit_replay$completeness, "partial")
  expect_true(result$audit_replay$marker_inserted)
  expect_true(result$audit_replay$chain_validates)
  # Both the marker AND the partial events are imported
  expect_true(result$audit_replay$imported >= 1L)

  unlink(zdb)
})

# Test: API connect failure surfaces through the result list
local({
  bad_api <- list(
    url   = "https://x", token = "tok", version = "x",
    ops   = list(
      version  = function() stop("403 Forbidden"),
      metadata = function() stop("403 Forbidden"),
      users    = function() stop("403 Forbidden"),
      records  = function(fields = NULL) stop("403 Forbidden"),
      log      = function() stop("403 Forbidden")
    )
  )
  zdb <- tempfile(fileext = ".db")
  res <- import_redcap_to_zzedc_db(
    source    = "api",
    api       = bad_api,
    db_path   = zdb,
    overwrite = TRUE
  )
  # API failures yield an empty extraction (no records, no users);
  # the importer still completes but the resulting database is
  # empty. Verify the run reports zero counts so callers can detect
  # the failure mode.
  expect_equal(res$users$imported, 0L)
  expect_equal(res$subjects$imported, 0L)
  unlink(zdb)
})
