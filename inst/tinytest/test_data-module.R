library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Data Module Tests
# Tests for the data_module.R functionality

# Test: data_ui function generates correct structure
local({
    if (exists("data_ui")) local({
    ui_output <- data_ui("test_data")

    expect_true(inherits(ui_output, "shiny.tag.list"))

    # Check that it contains expected components
    ui_html <- as.character(ui_output)

    # Test for key UI elements
    expect_true(grepl("Data Explorer", ui_html, fixed = TRUE))
    expect_true(grepl("data_source", ui_html, fixed = TRUE))
    expect_true(grepl("Choose Data Source", ui_html, fixed = TRUE))

    })
})
# Test: data_ui has proper namespacing
local({
    if (exists("data_ui")) local({
    ui_output <- data_ui("test_data")
    ui_html <- as.character(ui_output)

    # Check for namespaced IDs
    expect_true(grepl("test_data-data_source", ui_html, fixed = TRUE))

    })
})
# Test: data_ui includes conditional panels
local({
    if (exists("data_ui")) local({
    ui_output <- data_ui("test_data")
    ui_html <- as.character(ui_output)

    # Check for conditional panels (rendered as data-display-if)
    expect_true(grepl("data-display-if", ui_html, fixed = TRUE))
    expect_true(grepl("Local Files", ui_html, fixed = TRUE))
    expect_true(grepl("Database", ui_html, fixed = TRUE))
    expect_true(grepl("Sample Data", ui_html, fixed = TRUE))

    })
})
# Test: data_ui includes visualization controls
local({
    if (exists("data_ui")) local({
    ui_output <- data_ui("test_data")
    ui_html <- as.character(ui_output)

    # Check for plot type controls
    expect_true(grepl("Plot Type", ui_html, fixed = TRUE))

    })
})
# Test: data_ui includes action buttons and downloads
local({
    if (exists("data_ui")) local({
    ui_output <- data_ui("test_data")
    ui_html <- as.character(ui_output)

    # Check for download buttons
    expect_true(grepl("Export Current View", ui_html, fixed = TRUE))
    expect_true(grepl("Export Summary Report", ui_html, fixed = TRUE))

    })
})
# Test: data module server can be instantiated
local({
    if (exists("data_server")) local({
    # Simple test that the server function can be created
    expect_silent({
      server_func <- data_server
      expect_true(is.function(server_func))
    })

    })
})
# Simplified tests that don't require full Shiny reactive context
# Test: data module handles basic functionality
local({
    if (exists("data_ui")) local({
    # Test that the module functions exist
    expect_true(exists("data_ui"))
    expect_true(exists("data_server"))
    expect_true(is.function(data_ui))
    expect_true(is.function(data_server))

    })
})