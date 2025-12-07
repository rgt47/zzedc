# Test: Instrument Library Functions

# Helper function to create temporary test directory
create_test_instruments_dir <- function() {
  temp_dir <- tempdir()
  inst_dir <- file.path(temp_dir, "test_instruments")
  if (!dir.exists(inst_dir)) dir.create(inst_dir)
  inst_dir
}

# Helper to create a valid test CSV
create_test_instrument_csv <- function(filepath, n_fields = 5) {
  test_data <- data.frame(
    field_name = paste0("field_", 1:n_fields),
    field_label = paste0("Field ", 1:n_fields),
    field_type = rep("text", n_fields),
    validation_rules = rep("", n_fields),
    description = rep("Test field", n_fields),
    required = rep(FALSE, n_fields),
    stringsAsFactors = FALSE
  )
  write.csv(test_data, filepath, row.names = FALSE)
}

test_that("list_available_instruments returns empty when no instruments", {
  empty_dir <- tempdir()
  result <- list_available_instruments(empty_dir)

  expect_is(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true(all(c("name", "full_name", "items", "description") %in% names(result)))
})

test_that("list_available_instruments finds available instruments", {
  temp_dir <- create_test_instruments_dir()
  create_test_instrument_csv(file.path(temp_dir, "test_instrument.csv"), n_fields = 3)

  result <- list_available_instruments(temp_dir)

  expect_is(result, "data.frame")
  expect_equal(nrow(result), 1)
  expect_equal(result$name[1], "test_instrument")
  expect_equal(result$items[1], 3)
})

test_that("list_available_instruments returns metadata for known instruments", {
  temp_dir <- create_test_instruments_dir()
  create_test_instrument_csv(file.path(temp_dir, "phq9.csv"), n_fields = 9)

  result <- list_available_instruments(temp_dir)

  # Check that result contains expected data
  expect_true(nrow(result) >= 1, "Should return at least one instrument")
  expect_true(any(grepl("phq", result$full_name, ignore.case = TRUE)),
              "Should contain PHQ instrument in results")
})

test_that("load_instrument_template loads valid CSV", {
  temp_dir <- create_test_instruments_dir()
  create_test_instrument_csv(file.path(temp_dir, "test.csv"), n_fields = 5)

  result <- load_instrument_template("test", temp_dir)

  expect_is(result, "data.frame")
  expect_equal(nrow(result), 5)
  expect_true(all(c("field_name", "field_label", "field_type") %in% names(result)))
})

test_that("load_instrument_template adds missing columns with defaults", {
  temp_dir <- create_test_instruments_dir()

  # Create CSV with only required columns
  minimal_data <- data.frame(
    field_name = c("field_1", "field_2"),
    field_label = c("Label 1", "Label 2"),
    field_type = c("text", "select"),
    stringsAsFactors = FALSE
  )
  filepath <- file.path(temp_dir, "minimal.csv")
  write.csv(minimal_data, filepath, row.names = FALSE)

  result <- load_instrument_template("minimal", temp_dir)

  expect_true(all(c("validation_rules", "description", "required") %in% names(result)))
  expect_equal(result$validation_rules[1], "")
  expect_equal(result$description[1], "")
  expect_false(result$required[1])
})

test_that("load_instrument_template errors on missing file", {
  temp_dir <- create_test_instruments_dir()

  expect_error(
    load_instrument_template("nonexistent", temp_dir),
    "not found"
  )
})

test_that("load_instrument_template errors on missing required columns", {
  temp_dir <- create_test_instruments_dir()

  # Create CSV missing required column
  bad_data <- data.frame(
    field_name = c("field_1"),
    field_label = c("Label 1"),
    stringsAsFactors = FALSE
  )
  filepath <- file.path(temp_dir, "bad.csv")
  write.csv(bad_data, filepath, row.names = FALSE)

  expect_error(
    load_instrument_template("bad", temp_dir),
    "missing columns"
  )
})

test_that("load_instrument_template validates field names", {
  temp_dir <- create_test_instruments_dir()

  # Create CSV with invalid field names
  bad_data <- data.frame(
    field_name = c("123_invalid", "field-dash"),
    field_label = c("Label 1", "Label 2"),
    field_type = c("text", "text"),
    stringsAsFactors = FALSE
  )
  filepath <- file.path(temp_dir, "bad_names.csv")
  write.csv(bad_data, filepath, row.names = FALSE)

  expect_error(
    load_instrument_template("bad_names", temp_dir),
    "Invalid field names"
  )
})

test_that("load_instrument_template warns on unrecognized field types", {
  temp_dir <- create_test_instruments_dir()

  # Create CSV with invalid field type
  data_with_bad_type <- data.frame(
    field_name = c("field_1"),
    field_label = c("Label 1"),
    field_type = c("unknown_type"),
    stringsAsFactors = FALSE
  )
  filepath <- file.path(temp_dir, "bad_type.csv")
  write.csv(data_with_bad_type, filepath, row.names = FALSE)

  expect_warning(
    load_instrument_template("bad_type", temp_dir),
    "Unrecognized field types"
  )
})

test_that("validate_instrument_csv validates file existence", {
  result <- validate_instrument_csv("/nonexistent/file.csv")

  expect_false(result$valid)
  expect_true(any(grepl("does not exist", result$errors)))
})

test_that("validate_instrument_csv validates CSV structure", {
  temp_dir <- create_test_instruments_dir()

  # Create invalid CSV (missing required columns)
  bad_data <- data.frame(
    field_name = c("field_1"),
    stringsAsFactors = FALSE
  )
  filepath <- file.path(temp_dir, "invalid.csv")
  write.csv(bad_data, filepath, row.names = FALSE)

  result <- validate_instrument_csv(filepath)

  expect_false(result$valid)
  expect_true(any(grepl("Missing required columns", result$errors)))
})

test_that("validate_instrument_csv detects duplicate field names", {
  temp_dir <- create_test_instruments_dir()

  dup_data <- data.frame(
    field_name = c("field_1", "field_1", "field_2"),
    field_label = c("Label 1", "Label 1b", "Label 2"),
    field_type = c("text", "text", "text"),
    stringsAsFactors = FALSE
  )
  filepath <- file.path(temp_dir, "duplicates.csv")
  write.csv(dup_data, filepath, row.names = FALSE)

  result <- validate_instrument_csv(filepath)

  expect_false(result$valid)
  expect_true(any(grepl("Duplicate", result$errors)))
})

test_that("validate_instrument_csv counts fields correctly", {
  temp_dir <- create_test_instruments_dir()
  create_test_instrument_csv(file.path(temp_dir, "valid.csv"), n_fields = 7)

  result <- validate_instrument_csv(file.path(temp_dir, "valid.csv"))

  expect_true(result$valid)
  expect_equal(result$field_count, 7)
  expect_equal(length(result$errors), 0)
})

test_that("get_instrument_field returns field by name", {
  temp_dir <- create_test_instruments_dir()
  create_test_instrument_csv(file.path(temp_dir, "test.csv"), n_fields = 3)

  result <- get_instrument_field("test", "field_2", temp_dir)

  expect_is(result, "list")
  expect_equal(result$field_name, "field_2")
  expect_equal(result$field_label, "Field 2")
})

test_that("get_instrument_field returns NULL if field not found", {
  temp_dir <- create_test_instruments_dir()
  create_test_instrument_csv(file.path(temp_dir, "test.csv"), n_fields = 3)

  result <- get_instrument_field("test", "nonexistent", temp_dir)

  expect_null(result)
})

# Note: import_instrument requires database connection, so we test the validation
# and error handling but mock the database calls in integration tests

test_that("import_instrument returns error without database connection", {
  temp_dir <- create_test_instruments_dir()
  create_test_instrument_csv(file.path(temp_dir, "test.csv"), n_fields = 3)

  result <- import_instrument(
    instrument_name = "test",
    form_name = "test_form",
    db_conn = NULL,
    instruments_dir = temp_dir
  )

  expect_false(result$success)
  expect_true(any(grepl("connection required", result$message, ignore.case = TRUE)))
})

test_that("import_instrument validates instrument exists", {
  temp_dir <- create_test_instruments_dir()

  # import_instrument throws an error when instrument doesn't exist
  # Test that it properly raises an error
  expect_error(
    import_instrument(
      instrument_name = "nonexistent",
      form_name = "test_form",
      db_conn = list(),  # Mock non-NULL connection
      instruments_dir = temp_dir
    ),
    "Instrument not found"
  )
})

# Edge case tests

test_that("list_available_instruments handles missing directory gracefully", {
  result <- list_available_instruments("/nonexistent/directory/")

  expect_is(result, "data.frame")
  expect_equal(nrow(result), 0)
})

test_that("load_instrument_template handles special characters in descriptions", {
  temp_dir <- create_test_instruments_dir()

  data_special <- data.frame(
    field_name = c("field_1"),
    field_label = c("Label \"with\" quotes"),
    field_type = c("text"),
    stringsAsFactors = FALSE
  )
  filepath <- file.path(temp_dir, "special.csv")
  write.csv(data_special, filepath, row.names = FALSE)

  # Should load without error
  result <- load_instrument_template("special", temp_dir)
  expect_is(result, "data.frame")
})

test_that("validate_instrument_csv warns on non-CSV extension", {
  temp_file <- tempfile(fileext = ".txt")
  write.csv(data.frame(a = 1), temp_file)

  result <- validate_instrument_csv(temp_file)

  expect_true(any(grepl("should be .csv", result$warnings)))
})

# Integration test for field types
test_that("load_instrument_template recognizes all valid field types", {
  temp_dir <- create_test_instruments_dir()

  valid_types <- c("text", "numeric", "date", "email", "select", "checkbox", "textarea",
                   "radio", "slider", "time", "datetime", "signature", "file")

  type_data <- data.frame(
    field_name = paste0("field_", 1:length(valid_types)),
    field_label = paste0("Label ", 1:length(valid_types)),
    field_type = valid_types,
    stringsAsFactors = FALSE
  )
  filepath <- file.path(temp_dir, "all_types.csv")
  write.csv(type_data, filepath, row.names = FALSE)

  result <- load_instrument_template("all_types", temp_dir)

  expect_equal(nrow(result), length(valid_types))
  expect_warning(result, NA)  # Should not generate warnings
})
