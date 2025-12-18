# Test Utilities and Helpers
# Shared utility functions for testing ZZedc application

#' Create a temporary test database with full schema
#'
#' @param include_sample_data Logical, whether to include sample data
#' @return Database connection
create_full_test_db <- function(include_sample_data = TRUE) {
  con <- dbConnect(RSQLite::SQLite(), ":memory:")

  # Create all required tables (simplified version of setup_database.R)

  # Study metadata table
  dbExecute(con, "
    CREATE TABLE study_info (
      study_id TEXT PRIMARY KEY,
      study_name TEXT NOT NULL,
      pi_name TEXT,
      start_date DATE,
      end_date DATE,
      target_enrollment INTEGER,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ")

  # Subjects table
  dbExecute(con, "
    CREATE TABLE subjects (
      subject_id TEXT PRIMARY KEY,
      study_id TEXT NOT NULL,
      site_id TEXT DEFAULT '001',
      enrollment_date DATE,
      randomization_group TEXT CHECK(randomization_group IN ('Active', 'Placebo')),
      status TEXT DEFAULT 'Enrolled',
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ")

  # EDC Users table
  dbExecute(con, "
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

  # Forms table
  dbExecute(con, "
    CREATE TABLE forms (
      form_id INTEGER PRIMARY KEY,
      form_name TEXT NOT NULL,
      version TEXT DEFAULT '1.0',
      active INTEGER DEFAULT 1,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ")

  # Form data table
  dbExecute(con, "
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
    )
  ")

  if (include_sample_data) {
    # Insert sample study info
    dbExecute(con, "
      INSERT INTO study_info (study_id, study_name, pi_name, start_date, end_date, target_enrollment)
      VALUES ('TEST-001', 'Test Study', 'Dr. Test PI', '2024-01-01', '2024-12-31', 50)
    ")

    # Insert sample users
    test_salt <- "test_salt_123"
    admin_hash <- digest::digest(paste0("adminpass", test_salt), algo = "sha256")
    user_hash <- digest::digest(paste0("userpass", test_salt), algo = "sha256")

    dbExecute(con, "
      INSERT INTO edc_users (username, password_hash, full_name, role, site_id)
      VALUES
      ('testadmin', ?, 'Test Administrator', 'Admin', '001'),
      ('testuser', ?, 'Test User', 'User', '001'),
      ('testpi', ?, 'Test Principal Investigator', 'PI', '001')
    ", params = list(admin_hash, user_hash, admin_hash))

    # Insert sample subjects
    dbExecute(con, "
      INSERT INTO subjects (subject_id, study_id, site_id, enrollment_date, randomization_group, status)
      VALUES
      ('SUBJ-001', 'TEST-001', '001', '2024-01-15', 'Active', 'Enrolled'),
      ('SUBJ-002', 'TEST-001', '001', '2024-01-16', 'Placebo', 'Enrolled'),
      ('SUBJ-003', 'TEST-001', '001', '2024-01-17', 'Active', 'Completed')
    ")

    # Insert sample forms
    dbExecute(con, "
      INSERT INTO forms (form_name, version)
      VALUES
      ('Demographics', '1.0'),
      ('Medical History', '1.0'),
      ('Assessment', '1.1')
    ")

    # Insert sample form data
    dbExecute(con, "
      INSERT INTO form_data (subject_id, form_id, field_name, field_value, visit_code, user_id)
      VALUES
      ('SUBJ-001', 1, 'age', '65', 'Baseline', 1),
      ('SUBJ-001', 1, 'gender', 'M', 'Baseline', 1),
      ('SUBJ-002', 1, 'age', '72', 'Baseline', 2),
      ('SUBJ-002', 1, 'gender', 'F', 'Baseline', 2)
    ")
  }

  con
}

#' Create test reactive values with standard structure
#'
#' @param authenticated Initial authentication status
#' @return Reactive values object
create_test_reactive_values <- function(authenticated = FALSE) {
  reactiveValues(
    authenticated = authenticated,
    authenticated_enroll = FALSE,  # Fixed naming consistency
    valid_credentials = FALSE,
    user_id = NULL,
    username = NULL,
    full_name = NULL,
    role = NULL,
    site_id = NULL
  )
}

#' Mock file input for testing
#'
#' @param content Data frame or CSV content to mock
#' @param filename Name of the mock file
#' @return Mock file input object
mock_file_input <- function(content, filename = "test.csv") {
  temp_file <- tempfile(fileext = ".csv")

  if (is.data.frame(content)) {
    write.csv(content, temp_file, row.names = FALSE)
  } else {
    writeLines(content, temp_file)
  }

  list(
    name = filename,
    size = file.size(temp_file),
    type = "text/csv",
    datapath = temp_file
  )
}

#' Create sample clinical data for testing
#'
#' @param n_subjects Number of subjects to generate
#' @param n_visits Number of visits per subject
#' @return Data frame with sample clinical data
create_sample_clinical_data <- function(n_subjects = 20, n_visits = 3) {
  subjects <- paste0("SUBJ-", sprintf("%03d", 1:n_subjects))
  visits <- paste0("Visit-", 1:n_visits)

  # Generate all combinations
  combinations <- expand.grid(
    Subject = subjects,
    Visit = visits,
    stringsAsFactors = FALSE
  )

  # Add clinical data
  combinations$Age <- sample(50:80, nrow(combinations), replace = TRUE)
  combinations$Gender <- sample(c("M", "F"), nrow(combinations), replace = TRUE)
  combinations$Weight <- round(rnorm(nrow(combinations), 70, 10), 1)
  combinations$Height <- round(rnorm(nrow(combinations), 170, 8), 0)
  combinations$Score_1 <- round(rnorm(nrow(combinations), 25, 5), 1)
  combinations$Score_2 <- round(rnorm(nrow(combinations), 30, 6), 1)
  combinations$Visit_Date <- sample(seq(as.Date("2024-01-01"), as.Date("2024-12-31"), by = "day"),
                                   nrow(combinations), replace = TRUE)
  combinations$Status <- sample(c("Complete", "Incomplete", "Pending"), nrow(combinations), replace = TRUE)

  # Add some missing data randomly
  missing_indices <- sample(1:nrow(combinations), size = round(nrow(combinations) * 0.05))
  combinations$Score_1[missing_indices] <- NA

  combinations
}

#' Test authentication with different user types
#'
#' @param db_connection Database connection
#' @param cfg Configuration object
#' @return List of test results
test_all_user_types <- function(db_connection, cfg) {
  assign("db_pool", db_connection, envir = .GlobalEnv)
  assign("cfg", cfg, envir = .GlobalEnv)

  source(here::here("R/modules/auth_module.R"))

  results <- list(
    admin = authenticate_user("testadmin", "adminpass"),
    user = authenticate_user("testuser", "userpass"),
    pi = authenticate_user("testpi", "adminpass"),
    invalid = authenticate_user("invalid", "invalid")
  )

  rm(db_pool, envir = .GlobalEnv)
  rm(cfg, envir = .GlobalEnv)

  results
}

#' Validate UI output contains expected elements
#'
#' @param ui_output UI output from module
#' @param expected_elements Vector of expected text/elements
#' @param element_type Type of check ("text" or "class")
#' @return Logical vector indicating which elements were found
validate_ui_elements <- function(ui_output, expected_elements, element_type = "text") {
  ui_html <- as.character(ui_output)

  if (element_type == "text") {
    sapply(expected_elements, function(x) grepl(x, ui_html, fixed = TRUE))
  } else if (element_type == "class") {
    sapply(expected_elements, function(x) grepl(paste0('class=".*', x), ui_html))
  } else {
    stop("element_type must be 'text' or 'class'")
  }
}

#' Create test environment with all necessary globals
#'
#' @param config_env Environment name for configuration
#' @return List containing setup objects
setup_test_environment <- function(config_env = "testing") {
  # Set environment
  original_env <- Sys.getenv("R_CONFIG_ACTIVE")
  Sys.setenv(R_CONFIG_ACTIVE = config_env)

  # Create configuration
  cfg <- config::get(file = here::here("config.yml"))

  # Create database
  test_db <- create_full_test_db(include_sample_data = TRUE)

  # Create reactive values
  user_input <- create_test_reactive_values()

  # Set globals
  assign("db_pool", test_db, envir = .GlobalEnv)
  assign("cfg", cfg, envir = .GlobalEnv)
  assign("user_input", user_input, envir = .GlobalEnv)

  list(
    original_env = original_env,
    cfg = cfg,
    test_db = test_db,
    user_input = user_input
  )
}

#' Clean up test environment
#'
#' @param setup_result Result from setup_test_environment
cleanup_test_environment <- function(setup_result) {
  # Close database
  if (inherits(setup_result$test_db, "SQLiteConnection")) {
    dbDisconnect(setup_result$test_db)
  }

  # Remove globals
  if (exists("db_pool", envir = .GlobalEnv)) {
    rm(db_pool, envir = .GlobalEnv)
  }
  if (exists("cfg", envir = .GlobalEnv)) {
    rm(cfg, envir = .GlobalEnv)
  }
  if (exists("user_input", envir = .GlobalEnv)) {
    rm(user_input, envir = .GlobalEnv)
  }

  # Restore environment
  if (setup_result$original_env != "") {
    Sys.setenv(R_CONFIG_ACTIVE = setup_result$original_env)
  } else {
    Sys.unsetenv("R_CONFIG_ACTIVE")
  }
}

#' Generate test data with specific missing data patterns
#'
#' @param n_rows Number of rows
#' @param missing_percent Percentage of missing data
#' @return Data frame with controlled missing data
create_missing_data_test <- function(n_rows = 100, missing_percent = 0.1) {
  data <- data.frame(
    ID = 1:n_rows,
    Complete_Var = paste0("Value_", 1:n_rows),
    Partial_Missing = sample(c("A", "B", "C", NA), n_rows, replace = TRUE,
                           prob = c(0.4, 0.3, 0.3 - missing_percent, missing_percent)),
    High_Missing = sample(c("X", "Y", NA), n_rows, replace = TRUE,
                        prob = c(0.2, 0.3, 0.5)),
    Numeric_Complete = rnorm(n_rows, 50, 10),
    Numeric_Missing = ifelse(runif(n_rows) < missing_percent, NA, rnorm(n_rows, 100, 15))
  )

  data
}

#' Test module server functionality
#'
#' @param module_server Module server function
#' @param module_id Module ID for testing
#' @param test_inputs List of inputs to test
#' @param test_function Function to run tests within testServer
test_module_server <- function(module_server, module_id, test_inputs = NULL, test_function) {
  testServer(module_server(module_id), {
    if (!is.null(test_inputs)) {
      do.call(session$setInputs, test_inputs)
    }
    test_function(input, output, session)
  })
}

#' Validate configuration structure
#'
#' @param config Configuration object
#' @param required_sections List of required section names
#' @param required_fields List of required fields per section
#' @return Logical indicating if validation passed
validate_config_structure <- function(config, required_sections, required_fields) {
  # Check sections
  sections_valid <- all(required_sections %in% names(config))

  if (!sections_valid) {
    return(FALSE)
  }

  # Check fields in each section
  for (section in names(required_fields)) {
    if (section %in% names(config)) {
      fields_valid <- all(required_fields[[section]] %in% names(config[[section]]))
      if (!fields_valid) {
        return(FALSE)
      }
    }
  }

  TRUE
}

#' Create test CSV content for file input testing
#'
#' @param data_type Type of test data ("clinical", "simple", "missing")
#' @return Character vector with CSV content
create_test_csv_content <- function(data_type = "simple") {
  switch(data_type,
    "simple" = c(
      "ID,Name,Value",
      "1,Test1,10.5",
      "2,Test2,20.3",
      "3,Test3,15.7"
    ),
    "clinical" = c(
      "Subject,Visit,Age,Gender,Score",
      "SUBJ-001,Baseline,65,M,25.4",
      "SUBJ-002,Baseline,72,F,28.1",
      "SUBJ-001,Week4,65,M,26.2"
    ),
    "missing" = c(
      "ID,Complete,Partial,Missing",
      "1,Value1,A,",
      "2,Value2,,Data",
      "3,Value3,C,"
    )
  )
}