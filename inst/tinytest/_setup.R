# Test setup, helpers, and shared utilities for the zzedc tinytest
# suite. Consolidates the four testthat helper-*.R files
# (helper-test-setup, helper-skip, helper-db-backends,
# helper-test-utilities) into a single tinytest-compatible
# _setup.R.
#
# Each `inst/tinytest/test_*.R` sources this file at the top.
#
# Replaces testthat-specific machinery as follows:
#   testthat::skip(msg)  -> exit_file(msg)   (note: file-level, not block-level)
#   testthat::expect_*   -> tinytest expect_*
#   test_that(...)       -> direct execution (no wrapper)

# We avoid attaching `config` because it masks `base::get`, breaking
# tests that call `get(name, envir = ...)` positionally. bslib and
# plotly are now in zzedc Imports, so they are loaded with the
# package and we do not need to attach them here.
suppressPackageStartupMessages({
  library(shiny)
  library(DBI)
  library(RSQLite)
})

# Tinytest-friendly skip: in testthat, `skip("msg")` aborts the
# current `test_that()` block. In tinytest, the closest analogue is
# `exit_file("msg")` (aborts the current test file). For block-
# level skip semantics, prefer `if (!cond) local({...})` at the
# call site.
skip <- function(msg = "skipped") {
  exit_file(msg)
}

# ----------------------------------------------------------------
# Database fixtures (from helper-test-setup.R)
# ----------------------------------------------------------------

# Minimal in-memory SQLite database with edc_users only.
create_test_db <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(con, "
    CREATE TABLE edc_users (
      user_id INTEGER PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      full_name TEXT,
      role TEXT DEFAULT 'User',
      site_id TEXT DEFAULT '001',
      active INTEGER DEFAULT 1,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      last_login TIMESTAMP
    )
  ")
  test_salt <- "test_salt_123"
  test_password_hash <- digest::digest(paste0("testpass", test_salt),
                                       algo = "sha256")
  DBI::dbExecute(con, "
    INSERT INTO edc_users (username, password_hash, full_name,
                            role, site_id)
    VALUES (?, ?, ?, ?, ?)
  ", params = list("testuser", test_password_hash,
                   "Test User", "Admin", "001"))
  con
}

create_test_config <- function() {
  list(
    database = list(path = ":memory:", pool_size = 2),
    auth = list(salt_env_var = "TEST_SALT",
                default_salt = "test_salt_123",
                max_failed_attempts = 3,
                session_timeout_minutes = 30),
    app  = list(name = "ZZedc Test", version = "1.0.0-test",
                debug = TRUE)
  )
}

create_test_pool <- function() {
  # `:memory:` databases don't play well with `pool::dbPool()`, so
  # the helper returns a plain DBI connection.
  create_test_db()
}

setup_test_env <- function() {
  Sys.setenv(TEST_SALT = "test_salt_123")
  Sys.setenv(R_CONFIG_ACTIVE = "testing")
}

cleanup_test_env <- function() {
  Sys.unsetenv("TEST_SALT")
  Sys.unsetenv("R_CONFIG_ACTIVE")
}

# Apply test environment defaults at setup load time.
setup_test_env()

# ----------------------------------------------------------------
# Skip/source helpers (from helper-skip.R)
# ----------------------------------------------------------------

skip_if_not_installed <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    exit_file(paste("Package", pkg, "not available"))
  }
}

source_files_available <- function() {
  pkg_root <- tryCatch(
    normalizePath(file.path(getwd(), "..", "..")),
    error = function(e) NULL
  )
  !is.null(pkg_root) && file.exists(file.path(pkg_root, "R"))
}

skip_if_source_not_available <- function() {
  if (!source_files_available()) {
    exit_file("Source files not available (running via R CMD check)")
  }
}

safe_source <- function(path) {
  if (file.exists(path)) source(path)
}

# ----------------------------------------------------------------
# Database backend infrastructure (from helper-db-backends.R)
# ----------------------------------------------------------------

get_test_backends <- function() {
  backends_env <- Sys.getenv("ZZEDC_TEST_BACKENDS", "sqlite")
  trimws(strsplit(backends_env, ",")[[1]])
}

is_backend_available <- function(backend) {
  switch(tolower(backend),
    sqlite = requireNamespace("RSQLite", quietly = TRUE),
    duckdb = requireNamespace("duckdb", quietly = TRUE),
    postgresql = {
      has_pkg <- requireNamespace("RPostgres", quietly = TRUE)
      has_config <- Sys.getenv("ZZEDC_TEST_PG_HOST", "") != "" ||
                    Sys.getenv("ZZEDC_TEST_PG_DB", "") != ""
      has_pkg && has_config
    },
    postgres = is_backend_available("postgresql"),
    clickhouse = {
      has_pkg <- requireNamespace("RClickhouse", quietly = TRUE) ||
                 requireNamespace("clickhouse",  quietly = TRUE)
      has_config <- Sys.getenv("ZZEDC_TEST_CH_HOST", "") != ""
      has_pkg && has_config
    },
    FALSE)
}

test_backend_config <- function(backend) {
  backend <- tolower(backend)
  switch(backend,
    sqlite = list(
      db_backend = "sqlite",
      sqlite = list(path = tempfile(fileext = ".db"))
    ),
    duckdb = list(
      db_backend = "duckdb",
      duckdb = list(path = tempfile(fileext = ".duckdb"))
    ),
    postgresql = list(
      db_backend = "postgresql",
      postgresql = list(
        host = Sys.getenv("ZZEDC_TEST_PG_HOST", "localhost"),
        port = as.integer(Sys.getenv("ZZEDC_TEST_PG_PORT", "5432")),
        name = Sys.getenv("ZZEDC_TEST_PG_DB", "zzedc_test"),
        user = Sys.getenv("ZZEDC_TEST_PG_USER", "postgres"),
        password = Sys.getenv("ZZEDC_TEST_PG_PASSWORD", "")
      )
    ),
    postgres = test_backend_config("postgresql"),
    clickhouse = list(
      db_backend = "clickhouse",
      clickhouse = list(
        host = Sys.getenv("ZZEDC_TEST_CH_HOST", "localhost"),
        port = as.integer(Sys.getenv("ZZEDC_TEST_CH_PORT", "9000")),
        database = Sys.getenv("ZZEDC_TEST_CH_DB", "zzedc_test"),
        user = Sys.getenv("ZZEDC_TEST_CH_USER", "default"),
        password = Sys.getenv("ZZEDC_TEST_CH_PASSWORD", "")
      )
    ),
    stop("Unknown backend: ", backend)
  )
}

create_test_adapter <- function(backend) {
  config <- test_backend_config(backend)
  adapter <- create_db_adapter(config)
  config$db_adapter <- adapter
  structure(list(adapter = adapter, config = config, backend = backend),
            class = "test_db_context")
}

create_test_schema <- function(ctx, conn) {
  if (ctx$backend == "clickhouse") {
    create_clickhouse_test_schema(conn)
  } else {
    create_standard_test_schema(conn, ctx$backend, ctx$adapter$dialect())
  }
}

create_standard_test_schema <- function(conn, backend, dialect) {
  pk_syntax <- if (backend == "sqlite") {
    "INTEGER PRIMARY KEY AUTOINCREMENT"
  } else if (backend == "postgresql") {
    "SERIAL PRIMARY KEY"
  } else {
    "INTEGER PRIMARY KEY"
  }
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS edc_users (
      user_id %s,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      full_name TEXT,
      role TEXT DEFAULT 'User',
      site_id TEXT DEFAULT '001',
      active INTEGER DEFAULT 1,
      created_date TEXT,
      last_login TEXT
    )", pk_syntax))
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS subjects (
      subject_id TEXT PRIMARY KEY,
      study_id TEXT NOT NULL,
      site_id TEXT DEFAULT '001',
      enrollment_date TEXT,
      status TEXT DEFAULT 'Enrolled',
      created_date TEXT
    )")
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS audit_trail (
      audit_id %s,
      event_type TEXT NOT NULL,
      entity_type TEXT,
      entity_id INTEGER,
      user_id INTEGER,
      old_value TEXT,
      new_value TEXT,
      ip_address TEXT,
      previous_hash TEXT,
      current_hash TEXT,
      created_at TEXT
    )", pk_syntax))
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE IF NOT EXISTS validation_rules (
      rule_id %s,
      field_name TEXT NOT NULL,
      rule_dsl TEXT NOT NULL,
      error_message TEXT,
      active INTEGER DEFAULT 1,
      created_date TEXT
    )", pk_syntax))
}

create_clickhouse_test_schema <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS edc_users (
      user_id UInt64,
      username String,
      password_hash String,
      full_name Nullable(String),
      role String DEFAULT 'User',
      site_id String DEFAULT '001',
      active UInt8 DEFAULT 1,
      created_date DateTime DEFAULT now(),
      last_login Nullable(DateTime)
    ) ENGINE = MergeTree() ORDER BY (user_id)")
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS subjects (
      subject_id String,
      study_id String,
      site_id String DEFAULT '001',
      enrollment_date Nullable(Date),
      status String DEFAULT 'Enrolled',
      created_date DateTime DEFAULT now()
    ) ENGINE = MergeTree() ORDER BY (subject_id)")
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS audit_trail (
      audit_id UInt64,
      event_type String,
      entity_type Nullable(String),
      entity_id Nullable(UInt64),
      user_id Nullable(UInt64),
      old_value Nullable(String),
      new_value Nullable(String),
      ip_address Nullable(String),
      previous_hash Nullable(String),
      current_hash Nullable(String),
      created_at DateTime DEFAULT now()
    ) ENGINE = MergeTree() ORDER BY (audit_id, created_at)")
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS validation_rules (
      rule_id UInt64,
      field_name String,
      rule_dsl String,
      error_message Nullable(String),
      active UInt8 DEFAULT 1,
      created_date DateTime DEFAULT now()
    ) ENGINE = MergeTree() ORDER BY (rule_id)")
}

insert_test_data <- function(ctx, conn) {
  test_hash <- digest::digest("testpass_salt", algo = "sha256")
  ctx$adapter$execute(conn, sprintf("
    INSERT INTO edc_users (user_id, username, password_hash,
                            full_name, role)
    VALUES (1, 'testuser', '%s', 'Test User', 'Admin')",
    test_hash))
  ctx$adapter$execute(conn, "
    INSERT INTO subjects (subject_id, study_id, site_id, status)
    VALUES ('SUBJ-001', 'TEST-001', '001', 'Enrolled')")
  ctx$adapter$execute(conn, "
    INSERT INTO validation_rules (rule_id, field_name, rule_dsl,
                                   error_message)
    VALUES (1, 'age', 'x >= 18 AND x <= 120',
            'Age must be between 18 and 120')")
}

cleanup_test_db <- function(ctx, conn = NULL) {
  if (!is.null(conn)) {
    tables <- c("validation_rules", "audit_trail", "subjects",
                "edc_users")
    cascade <- if (ctx$backend == "postgresql") " CASCADE" else ""
    for (tbl in tables) {
      tryCatch(
        DBI::dbExecute(conn,
          paste0("DROP TABLE IF EXISTS ", tbl, cascade)),
        error = function(e) NULL)
    }
    ctx$adapter$disconnect(conn)
  }
  if (ctx$backend %in% c("sqlite", "duckdb")) {
    db_path <- ctx$config[[ctx$backend]]$path
    if (file.exists(db_path)) unlink(db_path)
  }
}

# Multi-backend test wrappers. Note: testthat's versions wrapped each
# backend in its own `test_that()` block; tinytest's analogue is to
# run each backend's tests inline. The descriptive label is preserved
# through a comment line printed via `message()` for traceability
# when reading test output.
with_test_backends <- function(desc, test_fn) {
  for (backend in get_test_backends()) {
    if (!is_backend_available(backend)) {
      message(sprintf("[SKIP %s] %s (backend not available)",
                      toupper(backend), desc))
      next
    }
    message(sprintf("[%s] %s", toupper(backend), desc))
    ctx <- create_test_adapter(backend)
    conn <- ctx$adapter$connect()
    adapter <- ctx$adapter
    tryCatch({
      create_test_schema(ctx, conn)
      insert_test_data(ctx, conn)
    }, error = function(e) {
      cleanup_test_db(ctx, conn)
      stop("Failed to set up test database: ", e$message)
    })
    tryCatch(test_fn(ctx, conn, adapter),
             finally = cleanup_test_db(ctx, conn))
  }
}

with_backend <- function(backend, desc, test_fn) {
  if (!is_backend_available(backend)) {
    message(sprintf("[SKIP %s] %s (backend not available)",
                    toupper(backend), desc))
    return(invisible(NULL))
  }
  message(sprintf("[%s] %s", toupper(backend), desc))
  ctx <- create_test_adapter(backend)
  conn <- ctx$adapter$connect()
  adapter <- ctx$adapter
  tryCatch({
    create_test_schema(ctx, conn)
    insert_test_data(ctx, conn)
    test_fn(ctx, conn, adapter)
  }, finally = cleanup_test_db(ctx, conn))
}

skip_if_no_backend <- function(backend) {
  if (!is_backend_available(backend)) {
    exit_file(paste("Backend not available:", backend))
  }
}

skip_if_not_ci <- function() {
  if (Sys.getenv("CI", "") == "") exit_file("Not running on CI")
}

# Custom expectations originally defined in helper-db-backends.R.
expect_table_exists <- function(conn, table_name) {
  tables <- DBI::dbListTables(conn)
  expect_true(tolower(table_name) %in% tolower(tables))
}

expect_row_count <- function(conn, table_name, expected_count) {
  result <- DBI::dbGetQuery(conn,
    sprintf("SELECT COUNT(*) AS n FROM %s", table_name))
  expect_equal(result$n, expected_count)
}

# ----------------------------------------------------------------
# Test utilities (from helper-test-utilities.R)
# ----------------------------------------------------------------

create_full_test_db <- function(include_sample_data = TRUE) {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(con, "
    CREATE TABLE study_info (
      study_id TEXT PRIMARY KEY,
      study_name TEXT NOT NULL,
      pi_name TEXT,
      start_date DATE,
      end_date DATE,
      target_enrollment INTEGER,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )")
  DBI::dbExecute(con, "
    CREATE TABLE subjects (
      subject_id TEXT PRIMARY KEY,
      study_id TEXT NOT NULL,
      site_id TEXT DEFAULT '001',
      enrollment_date DATE,
      randomization_group TEXT
        CHECK(randomization_group IN ('Active', 'Placebo')),
      status TEXT DEFAULT 'Enrolled',
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )")
  DBI::dbExecute(con, "
    CREATE TABLE edc_users (
      user_id INTEGER PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      full_name TEXT,
      role TEXT DEFAULT 'User',
      site_id TEXT DEFAULT '001',
      active INTEGER DEFAULT 1,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      last_login TIMESTAMP
    )")
  DBI::dbExecute(con, "
    CREATE TABLE forms (
      form_id INTEGER PRIMARY KEY,
      form_name TEXT NOT NULL,
      version TEXT DEFAULT '1.0',
      active INTEGER DEFAULT 1,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )")
  DBI::dbExecute(con, "
    CREATE TABLE form_data (
      record_id INTEGER PRIMARY KEY,
      subject_id TEXT,
      form_id INTEGER,
      field_name TEXT,
      field_value TEXT,
      visit_code TEXT,
      data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      user_id INTEGER,
      FOREIGN KEY (subject_id) REFERENCES subjects(subject_id),
      FOREIGN KEY (form_id) REFERENCES forms(form_id),
      FOREIGN KEY (user_id) REFERENCES edc_users(user_id)
    )")

  if (include_sample_data) {
    DBI::dbExecute(con, "
      INSERT INTO study_info (study_id, study_name, pi_name,
                               start_date, end_date,
                               target_enrollment)
      VALUES ('TEST-001', 'Test Study', 'Dr. Test PI',
              '2024-01-01', '2024-12-31', 50)")
    test_salt <- "test_salt_123"
    admin_hash <- digest::digest(paste0("adminpass", test_salt),
                                  algo = "sha256")
    user_hash  <- digest::digest(paste0("userpass",  test_salt),
                                  algo = "sha256")
    DBI::dbExecute(con, "
      INSERT INTO edc_users (username, password_hash, full_name,
                              role, site_id)
      VALUES
        ('testadmin', ?, 'Test Administrator', 'Admin', '001'),
        ('testuser',  ?, 'Test User',          'User',  '001'),
        ('testpi',    ?, 'Test PI',            'PI',    '001')",
      params = list(admin_hash, user_hash, admin_hash))
    DBI::dbExecute(con, "
      INSERT INTO subjects (subject_id, study_id, site_id,
                             enrollment_date,
                             randomization_group, status)
      VALUES
        ('SUBJ-001', 'TEST-001', '001', '2024-01-15',
         'Active', 'Enrolled'),
        ('SUBJ-002', 'TEST-001', '001', '2024-01-16',
         'Placebo', 'Enrolled'),
        ('SUBJ-003', 'TEST-001', '001', '2024-01-17',
         'Active', 'Completed')")
    DBI::dbExecute(con, "
      INSERT INTO forms (form_name, version)
      VALUES ('Demographics', '1.0'), ('Medical History', '1.0'),
             ('Assessment', '1.1')")
    DBI::dbExecute(con, "
      INSERT INTO form_data (subject_id, form_id, field_name,
                              field_value, visit_code, user_id)
      VALUES
        ('SUBJ-001', 1, 'age',    '65', 'Baseline', 1),
        ('SUBJ-001', 1, 'gender', 'M',  'Baseline', 1),
        ('SUBJ-002', 1, 'age',    '72', 'Baseline', 2),
        ('SUBJ-002', 1, 'gender', 'F',  'Baseline', 2)")
  }
  con
}

create_test_reactive_values <- function(authenticated = FALSE) {
  shiny::reactiveValues(
    authenticated = authenticated,
    authenticated_enroll = FALSE,
    valid_credentials = FALSE,
    user_id = NULL, username = NULL, full_name = NULL,
    role = NULL, site_id = NULL
  )
}

mock_file_input <- function(content, filename = "test.csv") {
  temp_file <- tempfile(fileext = ".csv")
  if (is.data.frame(content)) {
    write.csv(content, temp_file, row.names = FALSE)
  } else {
    writeLines(content, temp_file)
  }
  list(name = filename,
       size = file.size(temp_file),
       type = "text/csv",
       datapath = temp_file)
}

create_sample_clinical_data <- function(n_subjects = 20,
                                        n_visits = 3) {
  subjects <- paste0("SUBJ-", sprintf("%03d", 1:n_subjects))
  visits <- paste0("Visit-", 1:n_visits)
  combos <- expand.grid(Subject = subjects, Visit = visits,
                        stringsAsFactors = FALSE)
  combos$Age    <- sample(50:80, nrow(combos), replace = TRUE)
  combos$Gender <- sample(c("M", "F"), nrow(combos),
                          replace = TRUE)
  combos$Weight <- round(rnorm(nrow(combos), 70, 10), 1)
  combos$Height <- round(rnorm(nrow(combos), 170, 8), 0)
  combos$Score_1 <- round(rnorm(nrow(combos), 25, 5), 1)
  combos$Score_2 <- round(rnorm(nrow(combos), 30, 6), 1)
  combos$Visit_Date <- sample(
    seq(as.Date("2024-01-01"), as.Date("2024-12-31"),
        by = "day"),
    nrow(combos), replace = TRUE)
  combos$Status <- sample(c("Complete", "Incomplete", "Pending"),
                          nrow(combos), replace = TRUE)
  miss_idx <- sample(seq_len(nrow(combos)),
                     size = round(nrow(combos) * 0.05))
  combos$Score_1[miss_idx] <- NA
  combos
}

test_all_user_types <- function(db_connection, cfg) {
  if (!exists("authenticate_user")) {
    stop("authenticate_user function not available")
  }
  assign("db_pool", db_connection, envir = .GlobalEnv)
  assign("cfg",     cfg,           envir = .GlobalEnv)
  results <- list(
    admin   = authenticate_user("testadmin", "adminpass"),
    user    = authenticate_user("testuser",  "userpass"),
    pi      = authenticate_user("testpi",    "adminpass"),
    invalid = authenticate_user("invalid",   "invalid"))
  rm("db_pool", "cfg", envir = .GlobalEnv)
  results
}

validate_ui_elements <- function(ui_output, expected_elements,
                                  element_type = "text") {
  ui_html <- as.character(ui_output)
  if (element_type == "text") {
    sapply(expected_elements,
           function(x) grepl(x, ui_html, fixed = TRUE))
  } else if (element_type == "class") {
    sapply(expected_elements,
           function(x) grepl(paste0('class=".*', x), ui_html))
  } else {
    stop("element_type must be 'text' or 'class'")
  }
}

setup_test_environment <- function(config_env = "testing") {
  original_env <- Sys.getenv("R_CONFIG_ACTIVE")
  Sys.setenv(R_CONFIG_ACTIVE = config_env)
  cfg <- create_test_config()
  test_db <- create_full_test_db(include_sample_data = TRUE)
  user_input <- create_test_reactive_values()
  assign("db_pool",    test_db,    envir = .GlobalEnv)
  assign("cfg",        cfg,        envir = .GlobalEnv)
  assign("user_input", user_input, envir = .GlobalEnv)
  list(original_env = original_env,
       cfg = cfg,
       test_db = test_db,
       user_input = user_input)
}

cleanup_test_environment <- function(setup_result) {
  if (inherits(setup_result$test_db, "SQLiteConnection")) {
    DBI::dbDisconnect(setup_result$test_db)
  }
  for (g in c("db_pool", "cfg", "user_input")) {
    if (exists(g, envir = .GlobalEnv)) rm(list = g, envir = .GlobalEnv)
  }
  if (setup_result$original_env != "") {
    Sys.setenv(R_CONFIG_ACTIVE = setup_result$original_env)
  } else {
    Sys.unsetenv("R_CONFIG_ACTIVE")
  }
}

create_missing_data_test <- function(n_rows = 100,
                                      missing_percent = 0.1) {
  data.frame(
    ID = seq_len(n_rows),
    Complete_Var = paste0("Value_", seq_len(n_rows)),
    Partial_Missing = sample(c("A", "B", "C", NA), n_rows,
                              replace = TRUE,
                              prob = c(0.4, 0.3,
                                       0.3 - missing_percent,
                                       missing_percent)),
    High_Missing = sample(c("X", "Y", NA), n_rows, replace = TRUE,
                           prob = c(0.2, 0.3, 0.5)),
    Numeric_Complete = rnorm(n_rows, 50, 10),
    Numeric_Missing = ifelse(runif(n_rows) < missing_percent, NA,
                              rnorm(n_rows, 100, 15)))
}

test_module_server <- function(module_server, module_id,
                                test_inputs = NULL,
                                test_function) {
  shiny::testServer(module_server(module_id), {
    if (!is.null(test_inputs)) {
      do.call(session$setInputs, test_inputs)
    }
    test_function(input, output, session)
  })
}

validate_config_structure <- function(config, required_sections,
                                       required_fields) {
  if (!all(required_sections %in% names(config))) return(FALSE)
  for (section in names(required_fields)) {
    if (section %in% names(config)) {
      if (!all(required_fields[[section]] %in%
                names(config[[section]]))) return(FALSE)
    }
  }
  TRUE
}

create_test_csv_content <- function(data_type = "simple") {
  switch(data_type,
    "simple" = c("ID,Name,Value",
                  "1,Test1,10.5",
                  "2,Test2,20.3",
                  "3,Test3,15.7"),
    "clinical" = c("Subject,Visit,Age,Gender,Score",
                    "SUBJ-001,Baseline,65,M,25.4",
                    "SUBJ-002,Baseline,72,F,28.1",
                    "SUBJ-001,Week4,65,M,26.2"),
    "missing" = c("ID,Complete,Partial,Missing",
                   "1,Value1,A,",
                   "2,Value2,,Data",
                   "3,Value3,C,"))
}

# Null-coalesce helper used by some tests.
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
