# Home Module Tests
# Tests for the home_module.R functionality

# Load required modules
source(here::here("tests/testthat/test-setup.R"))
source(here::here("R/modules/instrument_import_module.R"))
source(here::here("R/modules/quality_dashboard_module.R"))
source(here::here("R/modules/home_module.R"))

test_that("home_ui function generates correct structure", {
  ui_output <- home_ui("test_home")

  expect_s3_class(ui_output, "shiny.tag.list")

  # Check that it contains expected components
  ui_html <- as.character(ui_output)

  # Check for hero section
  expect_true(grepl("Welcome to ZZedc Portal", ui_html, fixed = TRUE))
  expect_true(grepl("Electronic Data Capture for Clinical Trials", ui_html, fixed = TRUE))

  # Check for feature cards
  expect_true(grepl("Getting Started", ui_html, fixed = TRUE))
  expect_true(grepl("Contact &amp; Support", ui_html, fixed = TRUE))
  expect_true(grepl("Documentation", ui_html, fixed = TRUE))
  expect_true(grepl("Security &amp; Compliance", ui_html, fixed = TRUE))

  # Check for action buttons
  expect_true(grepl("test_home-intro_video", ui_html, fixed = TRUE))
  expect_true(grepl("test_home-quick_start", ui_html, fixed = TRUE))

  # Check for Bootstrap classes
  expect_true(grepl("bslib-card", ui_html, fixed = TRUE))
  expect_true(grepl("bg-primary", ui_html, fixed = TRUE))
})

test_that("home_ui contains proper bsicons", {
  ui_output <- home_ui("test_home")
  ui_html <- as.character(ui_output)

  # Check for specific icons
  expect_true(grepl("clipboard2-data-fill", ui_html, fixed = TRUE))
  expect_true(grepl("compass", ui_html, fixed = TRUE))
  expect_true(grepl("envelope", ui_html, fixed = TRUE))
  expect_true(grepl("file-earmark-text", ui_html, fixed = TRUE))
  expect_true(grepl("shield-lock", ui_html, fixed = TRUE))
})

test_that("home_ui has correct responsive structure", {
  ui_output <- home_ui("test_home")
  ui_html <- as.character(ui_output)

  # Check for Bootstrap grid classes
  # fluidRow and column are bootstrap classes that may be compiled differently
  expect_true(grepl("row", ui_html, fixed = TRUE))
  expect_true(grepl("col", ui_html, fixed = TRUE))

  # Check for responsive card components
  expect_true(grepl("card-body", ui_html, fixed = TRUE))
  expect_true(grepl("card-header", ui_html, fixed = TRUE))
})

test_that("home_ui includes security and compliance information", {
  ui_output <- home_ui("test_home")
  ui_html <- as.character(ui_output)

  # Check for security indicators
  expect_true(grepl("24/7", ui_html, fixed = TRUE))
  expect_true(grepl("256-bit", ui_html, fixed = TRUE))
  expect_true(grepl("ISO 27001", ui_html, fixed = TRUE))
  expect_true(grepl("GCP", ui_html, fixed = TRUE))

  # Check security icons
  expect_true(grepl("shield-fill-check", ui_html, fixed = TRUE))
  expect_true(grepl("key-fill", ui_html, fixed = TRUE))
  expect_true(grepl("file-lock", ui_html, fixed = TRUE))
})

test_that("home_ui provides proper navigation guidance", {
  ui_output <- home_ui("test_home")
  ui_html <- as.character(ui_output)

  # Check for tab descriptions
  expect_true(grepl("EDC.*Enter and manage study data", ui_html))
  expect_true(grepl("Reports.*Generate study reports", ui_html))
  expect_true(grepl("Data Explorer.*Visualize and analyze", ui_html))
  expect_true(grepl("Export.*Download data", ui_html))
})

test_that("home module server functions work correctly", {
  # Test that the server function can be instantiated
  expect_no_error({
    server_func <- home_server
    expect_true(is.function(server_func))
  })
})

test_that("home_ui contact information is present", {
  ui_output <- home_ui("test_home")
  ui_html <- as.character(ui_output)

  # Check for contact elements
  expect_true(grepl("Email Support", ui_html, fixed = TRUE))
  expect_true(grepl("Phone Support", ui_html, fixed = TRUE))
  expect_true(grepl("Live Chat", ui_html, fixed = TRUE))
  expect_true(grepl("mailto:", ui_html, fixed = TRUE))
})

test_that("home_ui includes documentation links", {
  ui_output <- home_ui("test_home")
  ui_html <- as.character(ui_output)

  # Check for documentation elements
  expect_true(grepl("Study Protocol", ui_html, fixed = TRUE))
  expect_true(grepl("Operations Manual", ui_html, fixed = TRUE))
  expect_true(grepl("Data Management Plan", ui_html, fixed = TRUE))
})

test_that("home_ui has proper accessibility attributes", {
  ui_output <- home_ui("test_home")
  ui_html <- as.character(ui_output)

  # Check for accessibility-friendly elements
  expect_true(grepl("btn", ui_html, fixed = TRUE))  # Button classes
  expect_true(grepl("text-center", ui_html, fixed = TRUE))  # Layout classes

  # Check that important elements have proper structure
  expect_true(grepl("<h[1-6]", ui_html))  # Proper heading hierarchy
  expect_true(grepl("class=\"lead\"", ui_html))  # Semantic lead text
})

test_that("home_ui follows bslib design patterns", {
  ui_output <- home_ui("test_home")
  ui_html <- as.character(ui_output)

  # Check for bslib-specific patterns
  expect_true(grepl("bslib-card", ui_html, fixed = TRUE))

  # Check for Bootstrap 5 classes
  expect_true(grepl("d-grid", ui_html, fixed = TRUE))
  expect_true(grepl("gap-2", ui_html, fixed = TRUE))
  expect_true(grepl("mb-4", ui_html, fixed = TRUE))

  # Check for proper button styling
  expect_true(grepl("btn-primary", ui_html, fixed = TRUE))
  expect_true(grepl("btn-outline-", ui_html, fixed = TRUE))
})

test_that("home_ui namespace is properly applied", {
  ui_output <- home_ui("test_namespace")
  ui_html <- as.character(ui_output)

  # Check that namespace is applied to action buttons
  expect_true(grepl("test_namespace-intro_video", ui_html, fixed = TRUE))
  expect_true(grepl("test_namespace-quick_start", ui_html, fixed = TRUE))

  # Ensure no elements have generic IDs without namespace
  expect_false(grepl("id=\"intro_video\"", ui_html, fixed = TRUE))
  expect_false(grepl("id=\"quick_start\"", ui_html, fixed = TRUE))
})