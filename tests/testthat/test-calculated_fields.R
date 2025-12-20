# Test Calculated/Derived Fields
# Feature #31

library(testthat)

setup_cf_test <- function() {
  Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_calculated_fie32!")
  initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
  init_audit_logging()
  init_calculated_fields()
}

cleanup_cf_test <- function() {
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) {
    try(unlink(db_path), silent = TRUE)
  }
}

test_that("init_calculated_fields creates tables", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("calculated_field_definitions" %in% tables)
  expect_true("calculation_history" %in% tables)
  expect_true("standard_formulas" %in% tables)
})

test_that("reference functions return values", {
  expect_true("BMI" %in% names(get_calculation_types()))
  expect_true("NUMBER" %in% names(get_result_types()))
})

test_that("load_standard_formulas loads formulas", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  result <- load_standard_formulas()
  expect_true(result$success)
  expect_true(result$formulas_loaded >= 5)
})

test_that("get_standard_formulas retrieves formulas", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  load_standard_formulas()
  result <- get_standard_formulas()
  expect_true(result$success)
  expect_true(result$count >= 5)
})

test_that("get_standard_formulas filters by category", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  load_standard_formulas()
  result <- get_standard_formulas(category = "ANTHROPOMETRIC")
  expect_true(result$success)
})

test_that("create_calculated_field creates field", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  result <- create_calculated_field(
    calc_code = "CALC_BMI",
    calc_name = "Calculate BMI",
    target_field_code = "BMI",
    calc_type = "BMI",
    formula = "WEIGHT / (HEIGHT/100)^2",
    source_fields = "WEIGHT,HEIGHT",
    created_by = "designer",
    result_type = "NUMBER",
    decimal_places = 1
  )

  expect_true(result$success)
  expect_true(!is.null(result$calc_id))
})

test_that("create_calculated_field validates inputs", {
  result <- create_calculated_field(
    calc_code = "",
    calc_name = "Test",
    target_field_code = "TARGET",
    calc_type = "BMI",
    formula = "A + B",
    source_fields = "A,B",
    created_by = "user"
  )
  expect_false(result$success)

  setup_cf_test()
  on.exit(cleanup_cf_test())

  result2 <- create_calculated_field(
    calc_code = "TEST",
    calc_name = "Test",
    target_field_code = "TARGET",
    calc_type = "INVALID",
    formula = "A + B",
    source_fields = "A,B",
    created_by = "user"
  )
  expect_false(result2$success)

  result3 <- create_calculated_field(
    calc_code = "TEST2",
    calc_name = "Test",
    target_field_code = "TARGET",
    calc_type = "BMI",
    formula = "A + B",
    source_fields = "A,B",
    created_by = "user",
    result_type = "INVALID"
  )
  expect_false(result3$success)
})

test_that("calculate_bmi calculates correctly", {
  result <- calculate_bmi(weight = 70, height = 175)
  expect_true(result$success)
  expect_equal(result$bmi, 22.86)
  expect_equal(result$category, "Normal weight")

  result_under <- calculate_bmi(weight = 50, height = 180)
  expect_equal(result_under$category, "Underweight")

  result_over <- calculate_bmi(weight = 85, height = 170)
  expect_equal(result_over$category, "Overweight")

  result_obese <- calculate_bmi(weight = 100, height = 165)
  expect_equal(result_obese$category, "Obese")
})

test_that("calculate_bmi handles errors", {
  result <- calculate_bmi(weight = NULL, height = 170)
  expect_false(result$success)

  result2 <- calculate_bmi(weight = -5, height = 170)
  expect_false(result2$success)
})

test_that("calculate_age calculates correctly", {
  birth <- as.Date("1990-06-15")
  ref <- as.Date("2025-06-15")

  result <- calculate_age(birth, ref)
  expect_true(result$success)
  expect_equal(result$age_years, 35)
})

test_that("calculate_age handles errors", {
  result <- calculate_age(NULL)
  expect_false(result$success)

  result2 <- calculate_age("2025-01-01", "2020-01-01")
  expect_false(result2$success)
})

test_that("calculate_date_diff calculates correctly", {
  result <- calculate_date_diff("2025-01-01", "2025-01-31", "days")
  expect_true(result$success)
  expect_equal(result$difference, 30)

  result_weeks <- calculate_date_diff("2025-01-01", "2025-01-15", "weeks")
  expect_true(result_weeks$success)
  expect_equal(result_weeks$difference, 2)
})

test_that("calculate_date_diff handles errors", {
  result <- calculate_date_diff(NULL, "2025-01-01")
  expect_false(result$success)
})

test_that("calculate_bsa calculates correctly", {
  result <- calculate_bsa(weight = 70, height = 175, formula = "DUBOIS")
  expect_true(result$success)
  expect_true(result$bsa > 1.5 && result$bsa < 2.5)

  result_most <- calculate_bsa(weight = 70, height = 175, formula = "MOSTELLER")
  expect_true(result_most$success)
})

test_that("calculate_bsa handles errors", {
  result <- calculate_bsa(NULL, 175)
  expect_false(result$success)
})

test_that("calculate_score_sum sums correctly", {
  result <- calculate_score_sum(c(1, 2, 3, 4, 5))
  expect_true(result$success)
  expect_equal(result$sum, 15)
  expect_equal(result$count, 5)
  expect_equal(result$mean, 3)
})

test_that("calculate_score_sum handles NA", {
  result_ignore <- calculate_score_sum(c(1, 2, NA, 4), na_handling = "ignore")
  expect_true(result_ignore$success)
  expect_equal(result_ignore$sum, 7)
  expect_equal(result_ignore$count, 3)

  result_zero <- calculate_score_sum(c(1, 2, NA, 4), na_handling = "zero")
  expect_true(result_zero$success)
  expect_equal(result_zero$sum, 7)

  result_error <- calculate_score_sum(c(1, 2, NA), na_handling = "error")
  expect_false(result_error$success)
})

test_that("calculate_score_sum handles empty", {
  result <- calculate_score_sum(c())
  expect_false(result$success)
})

test_that("record_calculation records", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  calc <- create_calculated_field(
    calc_code = "REC_TEST",
    calc_name = "Record Test",
    target_field_code = "RESULT",
    calc_type = "ARITHMETIC",
    formula = "A + B",
    source_fields = "A,B",
    created_by = "designer"
  )

  result <- record_calculation(
    calc_id = calc$calc_id,
    input_values = "A=5,B=3",
    calculated_value = 8,
    calculated_by = "system",
    subject_id = "SUBJ-001"
  )

  expect_true(result$success)
})

test_that("get_calculated_fields retrieves fields", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  create_calculated_field(
    calc_code = "GET_TEST",
    calc_name = "Get Test",
    target_field_code = "RESULT",
    calc_type = "PERCENTAGE",
    formula = "(A/B)*100",
    source_fields = "A,B",
    created_by = "designer"
  )

  result <- get_calculated_fields()
  expect_true(result$success)
  expect_true(result$count >= 1)
})

test_that("get_calculation_history retrieves history", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  calc <- create_calculated_field(
    calc_code = "HIST_TEST",
    calc_name = "History Test",
    target_field_code = "RESULT",
    calc_type = "SCORE_SUM",
    formula = "SUM(A,B,C)",
    source_fields = "A,B,C",
    created_by = "designer"
  )

  record_calculation(calc$calc_id, "A=1,B=2,C=3", 6, "system")
  record_calculation(calc$calc_id, "A=2,B=3,C=4", 9, "system")

  result <- get_calculation_history(calc$calc_id)
  expect_true(result$success)
  expect_equal(result$count, 2)
})

test_that("get_calculated_fields_statistics returns stats", {
  setup_cf_test()
  on.exit(cleanup_cf_test())

  result <- get_calculated_fields_statistics()
  expect_true(result$success)
  expect_true("statistics" %in% names(result))
  expect_true("by_type" %in% names(result))
})
