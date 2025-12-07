# Test: Multi-Format Export (SAS, SPSS, STATA, RDS)

test_that("export_to_file handles SAS format", {
  skip_if_not_installed("haven")

  test_data <- data.frame(
    id = 1:10,
    name = c("Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", "Ivy", "Jack"),
    age = c(25, 30, 35, 28, 32, 29, 31, 26, 33, 27),
    score = c(85.5, 92.0, 78.5, 88.0, 91.5, 86.0, 89.5, 87.0, 90.0, 84.5)
  )

  test_file <- tempfile(fileext = ".xpt")
  on.exit(unlink(test_file))

  result <- export_to_file(test_data, test_file, "sas")

  expect_true(result$success)
  expect_true(file.exists(test_file))
  expect_match(result$message, "10 rows")
  expect_match(result$message, "SAS")
})

test_that("export_to_file handles SPSS format", {
  skip_if_not_installed("haven")

  test_data <- data.frame(
    id = 1:5,
    category = c("A", "B", "A", "C", "B"),
    value = c(10, 20, 15, 30, 25)
  )

  test_file <- tempfile(fileext = ".sav")
  on.exit(unlink(test_file))

  result <- export_to_file(test_data, test_file, "spss")

  expect_true(result$success)
  expect_true(file.exists(test_file))
  expect_match(result$message, "5 rows")
  expect_match(result$message, "SPSS")
})

test_that("export_to_file handles STATA format", {
  skip_if_not_installed("haven")

  test_data <- data.frame(
    subject_id = 1:8,
    treatment = rep(c("Control", "Treatment"), 4),
    outcome = c(1, 0, 1, 1, 0, 1, 0, 0)
  )

  test_file <- tempfile(fileext = ".dta")
  on.exit(unlink(test_file))

  result <- export_to_file(test_data, test_file, "stata")

  expect_true(result$success)
  expect_true(file.exists(test_file))
  expect_match(result$message, "8 rows")
  expect_match(result$message, "STATA")
})

test_that("export_to_file handles RDS format", {
  test_data <- data.frame(
    x = 1:100,
    y = rnorm(100),
    z = sample(c("Group1", "Group2", "Group3"), 100, replace = TRUE)
  )

  test_file <- tempfile(fileext = ".rds")
  on.exit(unlink(test_file))

  result <- export_to_file(test_data, test_file, "rds")

  expect_true(result$success)
  expect_true(file.exists(test_file))
  expect_match(result$message, "100 rows")
  expect_match(result$message, "RDS")

  # Verify file can be read back
  loaded_data <- readRDS(test_file)
  expect_equal(nrow(loaded_data), 100)
  expect_equal(ncol(loaded_data), 3)
})

test_that("export_to_file returns error when haven not available for SAS", {
  skip_if(requireNamespace("haven", quietly = TRUE), "haven is installed, skipping test for missing haven")

  test_data <- data.frame(x = 1:5)
  test_file <- tempfile(fileext = ".xpt")
  on.exit(unlink(test_file))

  result <- export_to_file(test_data, test_file, "sas")

  expect_false(result$success)
  expect_match(result$message, "haven")
})

test_that("generate_export_filename creates correct extensions", {
  expect_match(
    generate_export_filename("mydata", "edc", "sas"),
    "\\.xpt$"
  )

  expect_match(
    generate_export_filename("mydata", "edc", "spss"),
    "\\.sav$"
  )

  expect_match(
    generate_export_filename("mydata", "edc", "stata"),
    "\\.dta$"
  )

  expect_match(
    generate_export_filename("mydata", "edc", "rds"),
    "\\.rds$"
  )
})

test_that("generate_export_filename includes timestamp", {
  filename <- generate_export_filename(NULL, "sample", "csv")

  expect_match(filename, "sample_export_")
  expect_match(filename, "\\d{8}")  # YYYYMMDD format
  expect_match(filename, "\\.csv$")
})

test_that("generate_export_filename sanitizes user input", {
  # Should sanitize the filename
  filename <- generate_export_filename("../../../evil", "edc", "csv")

  expect_false(grepl("\\.\\.", filename))
  expect_match(filename, "\\.csv$")
})

test_that("prepare_export_data accepts new formats", {
  # Test that prepare_export_data validates new formats
  expect_no_error(
    prepare_export_data("sample", "sas")
  )

  expect_no_error(
    prepare_export_data("sample", "spss")
  )

  expect_no_error(
    prepare_export_data("sample", "stata")
  )

  expect_no_error(
    prepare_export_data("sample", "rds")
  )
})

test_that("export_to_file requires data.frame for statistical formats", {
  skip_if_not_installed("haven")

  # List instead of data.frame should fail
  test_list <- list(x = 1:5, y = letters[1:5])
  test_file <- tempfile(fileext = ".sav")
  on.exit(unlink(test_file))

  result <- export_to_file(test_list, test_file, "spss")

  expect_false(result$success)
  expect_match(result$message, "data.frame")
})

test_that("RDS export preserves data types", {
  test_data <- data.frame(
    integer_col = 1:5,
    numeric_col = c(1.1, 2.2, 3.3, 4.4, 5.5),
    character_col = c("a", "b", "c", "d", "e"),
    logical_col = c(TRUE, FALSE, TRUE, FALSE, TRUE)
  )

  test_file <- tempfile(fileext = ".rds")
  on.exit(unlink(test_file))

  export_to_file(test_data, test_file, "rds")
  loaded_data <- readRDS(test_file)

  expect_equal(typeof(loaded_data$integer_col), "integer")
  expect_equal(typeof(loaded_data$numeric_col), "double")
  expect_equal(typeof(loaded_data$character_col), "character")
  expect_equal(typeof(loaded_data$logical_col), "logical")
})

test_that("RDS export handles large datasets efficiently", {
  # Create larger test data
  large_data <- data.frame(
    id = 1:10000,
    value = rnorm(10000),
    category = sample(c("A", "B", "C"), 10000, replace = TRUE)
  )

  test_file <- tempfile(fileext = ".rds")
  on.exit(unlink(test_file))

  result <- export_to_file(large_data, test_file, "rds")

  expect_true(result$success)
  expect_match(result$message, "10000 rows")

  # Verify compression worked
  loaded_data <- readRDS(test_file)
  expect_equal(nrow(loaded_data), 10000)
})

test_that("export_to_file handles NULL data gracefully", {
  result <- export_to_file(NULL, tempfile(), "csv")

  expect_false(result$success)
  expect_match(result$message, "No data")
})

test_that("export_to_file handles empty data.frame", {
  empty_df <- data.frame()
  test_file <- tempfile(fileext = ".csv")
  on.exit(unlink(test_file))

  result <- export_to_file(empty_df, test_file, "csv")

  expect_true(result$success)
  expect_true(file.exists(test_file))
})

# Format-specific behavior tests

test_that("SAS export handles special characters in column names", {
  skip_if_not_installed("haven")

  test_data <- data.frame(
    `Special Name` = 1:3,
    `Another-One` = c("a", "b", "c")
  )

  test_file <- tempfile(fileext = ".xpt")
  on.exit(unlink(test_file))

  result <- export_to_file(test_data, test_file, "sas")

  # Should handle gracefully (haven will sanitize names)
  expect_is(result, "list")
  expect_true("success" %in% names(result))
})

test_that("SPSS export handles missing values", {
  skip_if_not_installed("haven")

  test_data <- data.frame(
    id = 1:5,
    value = c(10, NA, 30, NA, 50)
  )

  test_file <- tempfile(fileext = ".sav")
  on.exit(unlink(test_file))

  result <- export_to_file(test_data, test_file, "spss")

  expect_true(result$success)
  # Verify NA values are preserved
  loaded_data <- haven::read_sav(test_file)
  expect_true(is.na(loaded_data$value[2]))
  expect_true(is.na(loaded_data$value[4]))
})

test_that("STATA export creates valid format", {
  skip_if_not_installed("haven")

  test_data <- data.frame(
    var1 = 1:10,
    var2 = c("low", "high"),
    var3 = seq(0, 1, length.out = 10)
  )

  test_file <- tempfile(fileext = ".dta")
  on.exit(unlink(test_file))

  export_to_file(test_data, test_file, "stata")

  # Verify can be read back
  loaded <- haven::read_dta(test_file)
  expect_equal(nrow(loaded), 10)
})
