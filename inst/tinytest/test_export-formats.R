library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Test: Multi-Format Export (SAS, SPSS, STATA, RDS)

# Test: export_to_file handles SAS format
local({
    if (requireNamespace("haven", quietly = TRUE)) local({

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
})
# Test: export_to_file handles SPSS format
local({
    if (requireNamespace("haven", quietly = TRUE)) local({

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
})
# Test: export_to_file handles STATA format
local({
    if (requireNamespace("haven", quietly = TRUE)) local({

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
})
# Test: export_to_file handles RDS format
local({
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
# Test: export_to_file returns error when haven not available for SAS
local({
    if (!((requireNamespace("haven", quietly = TRUE)))) local({

    test_data <- data.frame(x = 1:5)
    test_file <- tempfile(fileext = ".xpt")
    on.exit(unlink(test_file))

    result <- export_to_file(test_data, test_file, "sas")

    expect_false(result$success)
    expect_match(result$message, "haven")

    })
})
# Test: generate_export_filename creates correct extensions
local({
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
# Test: generate_export_filename includes timestamp
local({
    filename <- generate_export_filename(NULL, "sample", "csv")

    expect_match(filename, "sample_export_")
    expect_match(filename, "\\d{8}")  # YYYYMMDD format
    expect_match(filename, "\\.csv$")

})
# Test: generate_export_filename sanitizes user input
local({
    # Should sanitize the filename
    filename <- generate_export_filename("../../../evil", "edc", "csv")

    expect_false(grepl("\\.\\.", filename))
    expect_match(filename, "\\.csv$")

})
# Test: prepare_export_data accepts new formats
local({
    # Test that prepare_export_data validates new formats
    expect_silent(
      prepare_export_data("sample", "sas")
    )

    expect_silent(
      prepare_export_data("sample", "spss")
    )

    expect_silent(
      prepare_export_data("sample", "stata")
    )

    expect_silent(
      prepare_export_data("sample", "rds")
    )

})
# Test: export_to_file requires data.frame for statistical formats
local({
    if (requireNamespace("haven", quietly = TRUE)) local({

    # List instead of data.frame should fail
    test_list <- list(x = 1:5, y = letters[1:5])
    test_file <- tempfile(fileext = ".sav")
    on.exit(unlink(test_file))

    result <- export_to_file(test_list, test_file, "spss")

    expect_false(result$success)
    expect_match(result$message, "data.frame")

    })
})
# Test: RDS export preserves data types
local({
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
# Test: RDS export handles large datasets efficiently
local({
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
# Test: export_to_file handles NULL data gracefully
local({
    result <- export_to_file(NULL, tempfile(), "csv")

    expect_false(result$success)
    expect_match(result$message, "No data")

})
# Test: export_to_file handles empty data.frame
local({
    empty_df <- data.frame()
    test_file <- tempfile(fileext = ".csv")
    on.exit(unlink(test_file))

    result <- export_to_file(empty_df, test_file, "csv")

    expect_true(result$success)
    expect_true(file.exists(test_file))

})
# Format-specific behavior tests

# Test: SAS export handles special characters in column names
local({
    if (requireNamespace("haven", quietly = TRUE)) local({

    test_data <- data.frame(
      `Special Name` = 1:3,
      `Another-One` = c("a", "b", "c")
    )

    test_file <- tempfile(fileext = ".xpt")
    on.exit(unlink(test_file))

    result <- export_to_file(test_data, test_file, "sas")

    # Should handle gracefully (haven will sanitize names)
    expect_equal(typeof(result), "list")
    expect_true("success" %in% names(result))

    })
})
# Test: SPSS export handles missing values
local({
    if (requireNamespace("haven", quietly = TRUE)) local({

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
})
# Test: STATA export creates valid format
local({
    if (requireNamespace("haven", quietly = TRUE)) local({

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
})