# Test Runner Script for ZZedc
# Comprehensive test execution and reporting

library(testthat)
library(here)

# Set up test environment
cat("🧪 ZZedc Test Suite\n")
cat("==================\n\n")

# Ensure we're in the right directory
if (!file.exists("DESCRIPTION")) {
  stop("Please run tests from the package root directory")
}

# Check that required test dependencies are available
required_packages <- c("testthat", "here", "yaml", "digest", "config", "pool")
missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

if (length(missing_packages) > 0) {
  cat("❌ Missing required test packages:", paste(missing_packages, collapse = ", "), "\n")
  cat("Please install with: install.packages(c(", paste0("'", missing_packages, "'", collapse = ", "), "))\n\n")
  stop("Missing dependencies")
}

# Set testing environment
Sys.setenv(R_CONFIG_ACTIVE = "testing")
cat("✅ Test environment set to 'testing'\n")

# Check for config file
if (!file.exists("config.yml")) {
  cat("⚠️  Warning: config.yml not found - some tests may fail\n")
}

# Check for module files
module_files <- c(
  "R/modules/auth_module.R",
  "R/modules/home_module.R",
  "R/modules/data_module.R"
)

missing_modules <- module_files[!file.exists(module_files)]
if (length(missing_modules) > 0) {
  cat("⚠️  Warning: Missing module files:", paste(missing_modules, collapse = ", "), "\n")
}

cat("\n📋 Running Test Categories:\n")
cat("==========================\n")

# Define test categories
test_categories <- list(
  "Setup & Infrastructure" = "test-setup.R",
  "Authentication Module" = "test-auth-module.R",
  "Home Module" = "test-home-module.R",
  "Data Module" = "test-data-module.R",
  "Database Pool" = "test-database-pool.R",
  "Configuration" = "test-config.R",
  "Integration Tests" = "test-integration.R"
)

# Run individual test categories
results <- list()

for (category in names(test_categories)) {
  cat(sprintf("🔄 %s...\n", category))

  test_file <- file.path("tests/testthat", test_categories[[category]])

  if (file.exists(test_file)) {
    tryCatch({
      result <- test_file(test_file, reporter = "minimal")
      results[[category]] <- result
      cat(sprintf("✅ %s completed\n", category))
    }, error = function(e) {
      cat(sprintf("❌ %s failed: %s\n", category, e$message))
      results[[category]] <- e
    })
  } else {
    cat(sprintf("⚠️  %s: File not found\n", category))
  }
}

cat("\n📊 Test Summary:\n")
cat("================\n")

# Summary results
total_tests <- 0
total_failures <- 0
total_errors <- 0

for (category in names(results)) {
  result <- results[[category]]

  if (inherits(result, "error")) {
    cat(sprintf("❌ %s: ERROR\n", category))
    total_errors <- total_errors + 1
  } else if (is.list(result) && "results" %in% names(result)) {
    passed <- sum(sapply(result$results, function(x) x$passed))
    failed <- sum(sapply(result$results, function(x) x$failed))
    total_tests <- total_tests + passed + failed
    total_failures <- total_failures + failed

    if (failed > 0) {
      cat(sprintf("⚠️  %s: %d passed, %d failed\n", category, passed, failed))
    } else {
      cat(sprintf("✅ %s: %d passed\n", category, passed))
    }
  }
}

cat("\n🎯 Overall Results:\n")
cat("===================\n")
cat(sprintf("Total Tests: %d\n", total_tests))
cat(sprintf("Passed: %d\n", total_tests - total_failures))
cat(sprintf("Failed: %d\n", total_failures))
cat(sprintf("Errors: %d\n", total_errors))

if (total_failures == 0 && total_errors == 0) {
  cat("🎉 All tests passed!\n")
  status <- "PASS"
} else {
  cat("💥 Some tests failed or had errors\n")
  status <- "FAIL"
}

# Generate test report
cat("\n📄 Generating Test Report...\n")

report_file <- file.path("tests", "test_report.txt")
report_content <- c(
  paste("ZZedc Test Report -", Sys.time()),
  "========================================",
  "",
  paste("Overall Status:", status),
  paste("Total Tests:", total_tests),
  paste("Passed:", total_tests - total_failures),
  paste("Failed:", total_failures),
  paste("Errors:", total_errors),
  "",
  "Test Categories:",
  "----------------"
)

for (category in names(results)) {
  result <- results[[category]]
  if (inherits(result, "error")) {
    report_content <- c(report_content, paste("❌", category, "- ERROR:", result$message))
  } else if (is.list(result) && "results" %in% names(result)) {
    passed <- sum(sapply(result$results, function(x) x$passed))
    failed <- sum(sapply(result$results, function(x) x$failed))
    report_content <- c(report_content, paste("✅", category, "-", passed, "passed,", failed, "failed"))
  } else {
    report_content <- c(report_content, paste("⚠️ ", category, "- No detailed results"))
  }
}

report_content <- c(report_content, "", "Test Environment:", paste("R_CONFIG_ACTIVE:", Sys.getenv("R_CONFIG_ACTIVE")))

writeLines(report_content, report_file)
cat(sprintf("📄 Test report saved to: %s\n", report_file))

# Reset environment
Sys.unsetenv("R_CONFIG_ACTIVE")

cat("\n✨ Test run completed!\n")

# Return status for CI/CD
if (status == "FAIL") {
  quit(status = 1)
}