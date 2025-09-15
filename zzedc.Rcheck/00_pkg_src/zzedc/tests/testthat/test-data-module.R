# Data Module Tests
# Tests for the data_module.R functionality

# Load required packages for testing
library(plotly, warn.conflicts = FALSE)

# Load required modules
source(here::here("R/modules/data_module.R"))
source(here::here("tests/testthat/test-setup.R"))

test_that("data_ui function generates correct structure", {
  ui_output <- data_ui("test_data")

  expect_s3_class(ui_output, "shiny.tag.list")

  # Check that it contains expected components
  ui_html <- as.character(ui_output)

  # Test for key UI elements
  expect_true(grepl("Data Explorer", ui_html, fixed = TRUE))
  expect_true(grepl("data_source", ui_html, fixed = TRUE))
  expect_true(grepl("Choose Data Source", ui_html, fixed = TRUE))
})

test_that("data_ui has proper namespacing", {
  ui_output <- data_ui("test_data")
  ui_html <- as.character(ui_output)

  # Check for namespaced IDs
  expect_true(grepl("test_data-data_source", ui_html, fixed = TRUE))
})

test_that("data_ui includes conditional panels", {
  ui_output <- data_ui("test_data")
  ui_html <- as.character(ui_output)

  # Check for conditional panels (rendered as data-display-if)
  expect_true(grepl("data-display-if", ui_html, fixed = TRUE))
  expect_true(grepl("Local Files", ui_html, fixed = TRUE))
  expect_true(grepl("Database", ui_html, fixed = TRUE))
  expect_true(grepl("Sample Data", ui_html, fixed = TRUE))
})

test_that("data_ui includes visualization controls", {
  ui_output <- data_ui("test_data")
  ui_html <- as.character(ui_output)

  # Check for plot type controls
  expect_true(grepl("Plot Type", ui_html, fixed = TRUE))
})

test_that("data_ui includes action buttons and downloads", {
  ui_output <- data_ui("test_data")
  ui_html <- as.character(ui_output)

  # Check for download buttons
  expect_true(grepl("Export Current View", ui_html, fixed = TRUE))
  expect_true(grepl("Export Summary Report", ui_html, fixed = TRUE))
})

test_that("data module server can be instantiated", {
  # Simple test that the server function can be created
  expect_no_error({
    server_func <- data_server
    expect_true(is.function(server_func))
  })
})

# Simplified tests that don't require full Shiny reactive context
test_that("data module handles basic functionality", {
  # Test that we can source and call the module functions
  expect_true(exists("data_ui"))
  expect_true(exists("data_server"))
  expect_true(is.function(data_ui))
  expect_true(is.function(data_server))
})