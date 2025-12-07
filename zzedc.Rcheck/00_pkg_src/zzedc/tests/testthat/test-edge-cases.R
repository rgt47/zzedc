# Edge Case Tests for ZZedc
# Tests for unusual inputs and boundary conditions

test_that("validate_filename handles path traversal attempts", {
  library(zzedc)  # Assumes package is loaded

  # Path traversal attempts
  expect_equal(validate_filename("../../../etc/passwd"), "passwd")
  expect_equal(validate_filename("..\\..\\windows\\system32"), "system32")

  # Special characters
  expect_equal(validate_filename("export<2024>.csv"), "export_2024_.csv")
  expect_equal(validate_filename("file|name.csv"), "file_name.csv")

  # Very long names
  long_name <- paste(rep("a", 200), collapse = "")
  result <- validate_filename(long_name)
  expect_lte(nchar(result), 100)

  # Empty and NULL
  expect_equal(validate_filename(""), "export")
  expect_equal(validate_filename(character(0)), "")
})

test_that("validate_numeric_range rejects out-of-bounds values", {
  library(zzedc)

  expect_error(validate_numeric_range(150, min = 0, max = 100))
  expect_error(validate_numeric_range(-5, min = 0, max = 100))
  expect_no_error(validate_numeric_range(50, min = 0, max = 100))
})

test_that("audit logging handles empty log", {
  library(zzedc)

  audit_log <- init_audit_log()
  expect_equal(nrow(audit_log()), 0)

  # First record should verify as valid
  expect_true(verify_audit_log_integrity(audit_log))
})

test_that("validate_form_field handles all field types", {
  library(zzedc)

  # Email validation
  valid_email <- validate_form_field("test@example.com", type = "email")
  expect_true(valid_email$valid)

  invalid_email <- validate_form_field("not-an-email", type = "email")
  expect_false(invalid_email$valid)

  # Numeric validation
  valid_numeric <- validate_form_field("42", type = "numeric")
  expect_true(valid_numeric$valid)

  invalid_numeric <- validate_form_field("abc", type = "numeric")
  expect_false(invalid_numeric$valid)

  # Date validation
  valid_date <- validate_form_field("2024-01-01", type = "date")
  expect_true(valid_date$valid)

  invalid_date <- validate_form_field("not-a-date", type = "date")
  expect_false(invalid_date$valid)
})

test_that("session timeout handles concurrent activity updates", {
  skip("Requires Shiny test server context")
})

test_that("error_response and success_response have consistent structure", {
  library(zzedc)

  error <- error_response("Test error", code = "ERR001")
  expect_false(error$success)
  expect_equal(error$message, "Test error")
  expect_equal(error$code, "ERR001")
  expect_true("timestamp" %in% names(error))

  success <- success_response("Test success", data = list(id = 123))
  expect_true(success$success)
  expect_equal(success$message, "Test success")
  expect_equal(success$data$id, 123)
  expect_true("timestamp" %in% names(success))
})

test_that("query_audit_log filters correctly", {
  library(zzedc)

  audit_log <- init_audit_log()

  # Add test records
  log_audit_event(audit_log, "user1", "LOGIN", "auth", status = "success")
  log_audit_event(audit_log, "user2", "LOGIN", "auth", status = "failure")
  log_audit_event(audit_log, "user1", "EXPORT", "data", status = "success")

  # Test filters
  user1_logs <- query_audit_log(audit_log, user_id = "user1")
  expect_equal(nrow(user1_logs), 2)

  login_logs <- query_audit_log(audit_log, action = "LOGIN")
  expect_equal(nrow(login_logs), 2)

  failure_logs <- query_audit_log(audit_log, status = "failure")
  expect_equal(nrow(failure_logs), 1)
})
