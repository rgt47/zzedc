# Test Data Factories and Fixtures
# Provides reproducible test data for unit tests

#' Create test users for authentication tests
#'
#' @return data.frame with test user credentials
create_test_users <- function() {
  tibble::tibble(
    user_id = c("test001", "test002", "test003", "admin001"),
    username = c("testuser1", "testuser2", "testcoord1", "admin"),
    full_name = c("Test User One", "Test User Two", "Coordinator One", "Admin User"),
    role = c("Data Manager", "Monitor", "Coordinator", "Admin"),
    password_plain = c("TestPass123!", "TestPass456!", "CoordPass789!", "AdminPass000!"),
    site_id = c("SITE_001", "SITE_001", "SITE_002", NA)
  )
}

#' Create sample dataset for visualization tests
#'
#' @param n Number of observations (default: 100)
#' @return data.frame with sample clinical data
create_sample_clinical_data <- function(n = 100) {
  data.frame(
    Subject_ID = paste0("SUBJ_", sprintf("%04d", 1:n)),
    Visit_Date = sample(seq(as.Date("2024-01-01"), as.Date("2024-12-31"), by = "day"), n, replace = TRUE),
    Age = rnorm(n, mean = 55, sd = 15) %>% pmax(18) %>% pmin(99) %>% round(0),
    Gender = sample(c("M", "F"), n, replace = TRUE),
    Height_cm = rnorm(n, mean = 170, sd = 10),
    Weight_kg = rnorm(n, mean = 75, sd = 15),
    Systolic_BP = rnorm(n, mean = 130, sd = 10),
    Diastolic_BP = rnorm(n, mean = 80, sd = 8),
    Lab_Value_1 = rnorm(n, mean = 100, sd = 15),
    Lab_Value_2 = rnorm(n, mean = 50, sd = 10),
    Treatment_Group = sample(c("Control", "Treatment A", "Treatment B"), n, replace = TRUE),
    Status = sample(c("Completed", "Ongoing", "Withdrawn"), n, replace = TRUE, prob = c(0.6, 0.3, 0.1)),
    Notes = sample(c("Normal", "Follow-up required", "Protocol deviation", NA), n, replace = TRUE, prob = c(0.5, 0.2, 0.1, 0.2))
  )
}

#' Create dataset with missing values
#'
#' Creates sample data with deliberately missing values for missing data tests
#'
#' @param n Number of observations
#' @param missing_rate Proportion of values to set as NA (0-1)
#' @return data.frame with missing values
create_sample_data_with_missing <- function(n = 100, missing_rate = 0.1) {
  data <- create_sample_clinical_data(n)

  # Introduce missing values randomly
  for (col in names(data)) {
    if (is.numeric(data[[col]])) {
      missing_idx <- sample(1:n, size = round(n * missing_rate), replace = FALSE)
      data[[col]][missing_idx] <- NA
    }
  }

  data
}

#' Create test audit log entries
#'
#' @return data.frame with sample audit log entries
create_sample_audit_log <- function() {
  tibble::tibble(
    timestamp = seq(Sys.time() - 3600, Sys.time(), length.out = 10),
    user_id = rep(c("user1", "user2"), 5),
    action = rep(c("LOGIN", "DATA_VIEW", "EXPORT", "LOGIN", "FORM_SUBMISSION"), 2),
    resource = c("auth", "subject_123", "report_export", "auth", "form_001"),
    status = rep(c("success", "success", "success", "failure", "success"), 2),
    record_hash = paste0("hash_", 1:10),
    previous_hash = c("", paste0("hash_", 1:9))
  )
}

#' Create test form metadata
#'
#' Defines form field types and validation rules
#'
#' @return list with form field definitions
create_test_form_metadata <- function() {
  list(
    age = list(
      type = "numeric",
      required = TRUE,
      min = 18,
      max = 120,
      label = "Age (years)"
    ),
    email = list(
      type = "email",
      required = TRUE,
      label = "Email Address"
    ),
    treatment_group = list(
      type = "select",
      required = TRUE,
      choices = c("Control", "Treatment A", "Treatment B"),
      label = "Treatment Group"
    ),
    visit_date = list(
      type = "date",
      required = TRUE,
      label = "Visit Date"
    ),
    notes = list(
      type = "text",
      required = FALSE,
      max_length = 500,
      label = "Additional Notes"
    )
  )
}

#' Create database connection for testing
#'
#' @return DBI connection to in-memory SQLite database
create_test_database <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")

  # Create test tables
  DBI::dbCreateTable(conn, "users",
    list(
      user_id = "TEXT PRIMARY KEY",
      username = "TEXT UNIQUE",
      full_name = "TEXT",
      role = "TEXT",
      password_hash = "TEXT"
    )
  )

  # Insert test users
  users <- create_test_users()
  DBI::dbAppendTable(conn, "users",
    data.frame(
      user_id = users$user_id,
      username = users$username,
      full_name = users$full_name,
      role = users$role,
      password_hash = paste0("hash_", users$user_id)
    )
  )

  conn
}
