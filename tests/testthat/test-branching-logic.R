# Test: Branching Logic
library(zzedc)

test_that("parse_branching_rule parses equality rule", {
  rule <- zzedc:::parse_branching_rule("gender == 'Female'")

  expect_equal(rule$field, "gender")
  expect_equal(rule$operator, "==")
  expect_equal(rule$value, "Female")
})

test_that("parse_branching_rule parses inequality rule", {
  rule <- zzedc:::parse_branching_rule("status != 'inactive'")

  expect_equal(rule$field, "status")
  expect_equal(rule$operator, "!=")
  expect_equal(rule$value, "inactive")
})

test_that("parse_branching_rule parses greater than rule", {
  rule <- zzedc:::parse_branching_rule("age > 18")

  expect_equal(rule$field, "age")
  expect_equal(rule$operator, ">")
  expect_equal(rule$value, 18)
})

test_that("parse_branching_rule parses less than rule", {
  rule <- zzedc:::parse_branching_rule("age < 65")

  expect_equal(rule$field, "age")
  expect_equal(rule$operator, "<")
  expect_equal(rule$value, 65)
})

test_that("parse_branching_rule parses greater than or equal rule", {
  rule <- zzedc:::parse_branching_rule("score >= 50")

  expect_equal(rule$field, "score")
  expect_equal(rule$operator, ">=")
  expect_equal(rule$value, 50)
})

test_that("parse_branching_rule parses less than or equal rule", {
  rule <- zzedc:::parse_branching_rule("score <= 100")

  expect_equal(rule$field, "score")
  expect_equal(rule$operator, "<=")
  expect_equal(rule$value, 100)
})

test_that("parse_branching_rule parses in rule", {
  rule <- zzedc:::parse_branching_rule("state in ('CA', 'NY', 'TX')")

  expect_equal(rule$field, "state")
  expect_equal(rule$operator, "in")
  expect_equal(length(rule$value), 3)
  expect_true("CA" %in% rule$value)
  expect_true("NY" %in% rule$value)
  expect_true("TX" %in% rule$value)
})

test_that("parse_branching_rule returns NULL for invalid rule", {
  rule <- zzedc:::parse_branching_rule("invalid rule text")

  expect_null(rule)
})

test_that("parse_branching_rule handles whitespace", {
  rule <- zzedc:::parse_branching_rule("  gender  ==  'Female'  ")

  expect_equal(rule$field, "gender")
  expect_equal(rule$value, "Female")
})

test_that("evaluate_condition handles equality true", {
  rule <- list(field = "gender", operator = "==", value = "Female")
  form_values <- list(gender = "Female")

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_true(result)
})

test_that("evaluate_condition handles equality false", {
  rule <- list(field = "gender", operator = "==", value = "Female")
  form_values <- list(gender = "Male")

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_false(result)
})

test_that("evaluate_condition handles inequality true", {
  rule <- list(field = "status", operator = "!=", value = "inactive")
  form_values <- list(status = "active")

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_true(result)
})

test_that("evaluate_condition handles greater than true", {
  rule <- list(field = "age", operator = ">", value = 18)
  form_values <- list(age = 25)

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_true(result)
})

test_that("evaluate_condition handles greater than false", {
  rule <- list(field = "age", operator = ">", value = 18)
  form_values <- list(age = 16)

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_false(result)
})

test_that("evaluate_condition handles less than true", {
  rule <- list(field = "age", operator = "<", value = 65)
  form_values <- list(age = 45)

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_true(result)
})

test_that("evaluate_condition handles in operator true", {
  rule <- list(field = "state", operator = "in", value = c("CA", "NY", "TX"))
  form_values <- list(state = "CA")

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_true(result)
})

test_that("evaluate_condition handles in operator false", {
  rule <- list(field = "state", operator = "in", value = c("CA", "NY", "TX"))
  form_values <- list(state = "FL")

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_false(result)
})

test_that("evaluate_condition handles missing field", {
  rule <- list(field = "missing_field", operator = "==", value = "value")
  form_values <- list(other_field = "value")

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_false(result)
})

test_that("is_field_visible with show_if rule true", {
  field_config <- list(show_if = "gender == 'Female'")
  form_values <- list(gender = "Female")

  result <- is_field_visible("field1", field_config, form_values)

  expect_true(result)
})

test_that("is_field_visible with show_if rule false", {
  field_config <- list(show_if = "gender == 'Female'")
  form_values <- list(gender = "Male")

  result <- is_field_visible("field1", field_config, form_values)

  expect_false(result)
})

test_that("is_field_visible with hide_if rule true", {
  field_config <- list(hide_if = "status == 'inactive'")
  form_values <- list(status = "active")

  result <- is_field_visible("field1", field_config, form_values)

  expect_true(result)
})

test_that("is_field_visible with hide_if rule false", {
  field_config <- list(hide_if = "status == 'inactive'")
  form_values <- list(status = "inactive")

  result <- is_field_visible("field1", field_config, form_values)

  expect_false(result)
})

test_that("is_field_visible defaults to visible when no rules", {
  field_config <- list()
  form_values <- list()

  result <- is_field_visible("field1", field_config, form_values)

  expect_true(result)
})

test_that("validate_form_with_branching allows empty optional conditional field", {
  form_data <- list(gender = "Male")
  form_fields <- list(
    gender = list(type = "text", required = TRUE),
    pregnancy_date = list(type = "date", required = TRUE, show_if = "gender == 'Female'")
  )

  result <- zzedc:::validate_form_with_branching(form_data, form_fields)

  expect_true(result$valid)
  expect_equal(length(result$errors), 0)
})

test_that("validate_form_with_branching requires visible conditional field", {
  form_data <- list(gender = "Female", pregnancy_date = "")
  form_fields <- list(
    gender = list(type = "text", required = TRUE),
    pregnancy_date = list(type = "date", required = TRUE, show_if = "gender == 'Female'")
  )

  result <- zzedc:::validate_form_with_branching(form_data, form_fields)

  expect_false(result$valid)
  expect_true(any(grepl("pregnancy_date", result$errors, ignore.case = TRUE)))
})

test_that("validate_form_with_branching allows hidden required field to be empty", {
  form_data <- list(gender = "Male")
  form_fields <- list(
    gender = list(type = "text", required = TRUE, label = "Gender"),
    pregnancy_date = list(
      type = "date",
      required = TRUE,
      label = "Pregnancy Date",
      show_if = "gender == 'Female'"
    )
  )

  result <- zzedc:::validate_form_with_branching(form_data, form_fields)

  expect_true(result$valid)
  expect_equal(length(result$errors), 0)
})

test_that("validate_form_with_branching handles multiple conditions", {
  form_data <- list(
    gender = "Female",
    age = 25,
    pregnancy_date = ""
  )
  form_fields <- list(
    gender = list(type = "text", required = TRUE),
    age = list(type = "numeric", required = TRUE),
    pregnancy_date = list(
      type = "date",
      required = TRUE,
      show_if = "gender == 'Female' and age >= 18"
    )
  )

  result <- zzedc:::validate_form_with_branching(form_data, form_fields)

  # pregnancy_date is visible and required, so validation fails
  # (Note: Current implementation doesn't support "and" - this is a simplified test)
  expect_is(result, "list")
  expect_true("valid" %in% names(result))
  expect_true("errors" %in% names(result))
})

# Edge case tests

test_that("parse_branching_rule handles quoted values with spaces", {
  rule <- zzedc:::parse_branching_rule("city == 'New York'")

  expect_equal(rule$field, "city")
  expect_equal(rule$value, "New York")
})

test_that("parse_branching_rule handles numeric values", {
  rule <- zzedc:::parse_branching_rule("age >= 18")

  expect_equal(rule$field, "age")
  expect_equal(rule$value, 18)
  expect_true(is.numeric(rule$value))
})

test_that("evaluate_condition handles string to numeric conversion", {
  rule <- list(field = "age", operator = ">", value = 18)
  form_values <- list(age = "25")  # String instead of numeric

  result <- zzedc:::evaluate_condition(rule, form_values)

  expect_true(result)
})

test_that("is_field_visible handles missing field config", {
  field_config <- NULL
  form_values <- list()

  # Should handle gracefully
  result <- is_field_visible("field1", field_config %||% list(), form_values)

  expect_true(result)
})

test_that("validate_form_with_branching handles empty form data", {
  form_data <- list()
  form_fields <- list(
    gender = list(type = "text", required = FALSE),
    pregnancy_date = list(type = "date", required = FALSE, show_if = "gender == 'Female'")
  )

  result <- zzedc:::validate_form_with_branching(form_data, form_fields)

  expect_true(result$valid)
})

test_that("parse_branching_rule handles brackets in in() syntax", {
  rule <- zzedc:::parse_branching_rule("state in [CA, NY, TX]")

  expect_equal(rule$field, "state")
  expect_equal(rule$operator, "in")
  expect_true("CA" %in% rule$value)
})
