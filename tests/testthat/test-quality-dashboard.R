# Test: Quality Dashboard Module

test_that("quality_dashboard_ui returns UI structure", {
  ui <- quality_dashboard_ui("test")

  expect_is(ui, "shiny.tag")
})

test_that("quality_dashboard_ui includes key metric cards", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  expect_true(grepl("Total Records", html))
  expect_true(grepl("Complete Records", html))
  expect_true(grepl("% Incomplete", html))
  expect_true(grepl("Flagged Issues", html))
})

test_that("quality_dashboard_ui includes charts", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  expect_true(grepl("Completeness by Form", html))
  expect_true(grepl("Data Entry Timeline", html))
  expect_true(grepl("Missing Data Summary", html))
})

test_that("quality_dashboard_ui includes QC flags section", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  expect_true(grepl("Quality Control Flags", html))
})

# Integration tests would require a mock database connection
# These are deferred pending development of database mocking utilities

test_that("quality_dashboard_ui has proper namespacing", {
  ui <- quality_dashboard_ui("dashboard")
  html <- as.character(ui)

  # Check that namespace ID is properly applied
  expect_true(grepl("dashboard", html))
})

test_that("quality_dashboard_ui metric cards use appropriate styling", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  # Check for Bootstrap styling
  expect_true(grepl("text-primary", html))  # Total Records
  expect_true(grepl("text-success", html))  # Complete Records
  expect_true(grepl("text-warning", html))  # % Incomplete
  expect_true(grepl("text-danger", html))   # Flagged Issues
})

# Edge case tests

test_that("quality_dashboard_ui renders with empty namespace", {
  ui <- quality_dashboard_ui("")

  expect_is(ui, "shiny.tag")
})

test_that("quality_dashboard_ui includes responsive design", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  # Check for responsive grid classes
  expect_true(grepl("fluidRow|column", html))
})

test_that("quality_dashboard_ui includes help text", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  expect_true(grepl("Real-time monitoring", html))
  expect_true(grepl("text-muted", html))
})

# Structure validation tests

test_that("quality_dashboard_ui has correct card structure", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  # Should have multiple cards
  expect_true(grepl("card-header", html, ignore.case = TRUE))
  expect_true(grepl("card-body", html, ignore.case = TRUE))
})

test_that("quality_dashboard_ui includes table output", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  expect_true(grepl("dataTableOutput|DataTable", html))
})

test_that("quality_dashboard_ui includes plotly charts", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  expect_true(grepl("plotlyOutput", html))
})

# Accessibility tests

test_that("quality_dashboard_ui includes descriptive headings", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  expect_true(grepl("<h2|<h3|<h4|<h5", html))
})

test_that("quality_dashboard_ui includes icon references", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  # Should use bsicons for accessibility
  expect_true(grepl("bs_icon|bsicons", html))
})

# Color coding tests

test_that("quality_dashboard_ui uses color coding for status", {
  ui <- quality_dashboard_ui("test")
  html <- as.character(ui)

  # Should use alert classes for different statuses
  expect_true(grepl("alert-success|alert-warning|alert-danger", html))
})
