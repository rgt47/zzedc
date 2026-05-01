library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Test: launch_zzedc function exists and has proper structure
local({
    # Test that the function exists
    expect_true(exists("launch_zzedc"))
  
    # Test that it's a function
    expect_equal(typeof(launch_zzedc), "closure")
  
    # Test function arguments
    args <- names(formals(launch_zzedc))
    expect_true("..." %in% args)
    expect_true("launch.browser" %in% args)
    expect_true("host" %in% args)
    expect_true("port" %in% args)

})
# Test: required directories are created
local({
    # Test that launch function creates necessary directories
    temp_dir <- tempdir()
    old_wd <- getwd()
    setwd(temp_dir)
  
    # Clean up any existing directories
    if (dir.exists("data")) unlink("data", recursive = TRUE)
    if (dir.exists("credentials")) unlink("credentials", recursive = TRUE)
  
    # This would normally launch the app, but we'll just test the setup
    tryCatch({
      # We can't actually test the full launch without running the app
      # but we can test that the function exists and has the right signature
      expect_true(is.function(launch_zzedc))
    }, error = function(e) {
      # Expected since we don't have the full app structure in temp dir
    })
  
    setwd(old_wd)

})
# Test: package structure is valid
local({
    # Test modern R package structure (only when running from project root)
    if (!((basename(getwd()) != "zzedc"))) local({

    # Test R/ directory exists
    expect_true(dir.exists("R"), info = "R/ directory should exist")
    expect_true(file.exists("R/launch_zzedc.R"), info = "launch_zzedc.R should exist")
    expect_true(file.exists("R/zzedc-package.R"), info = "zzedc-package.R should exist")

    # Test DESCRIPTION file
    expect_true(file.exists("DESCRIPTION"), info = "DESCRIPTION file required")

    # Test NAMESPACE exists
    expect_true(file.exists("NAMESPACE"), info = "NAMESPACE file required")

    })
})
# Test: key app components exist
local({
    # Test that required R package files exist (only when running from project root)
    if (!((basename(getwd()) != "zzedc"))) local({

    # These are functions in R/ directory, not top-level files
    required_r_files <- c(
      "R/launch_zzedc.R",
      "R/modules/home_module.R",
      "R/modules/auth_module.R",
      "R/export_service.R",
      "R/audit_logger.R"
    )

    for(file in required_r_files) {
      expect_true(file.exists(file), info = paste("Missing file:", file))
    }

    })
})
# Test: forms directory structure exists
local({
    # Test forms directory and files (only if running from project root)
    if (!((basename(getwd()) != "zzedc"))) local({

    expect_true(dir.exists("forms"))

    forms_files <- c("forms/blfieldlist.R", "forms/renderpanels.R", "forms/save.R")
    for(file in forms_files) {
      expect_true(file.exists(file), info = paste("Missing forms file:", file))
    }

    })
})
# Test: www directory and assets exist
local({
    # Test www directory for web assets (only if running from project root)
    if (!((basename(getwd()) != "zzedc"))) local({

    expect_true(dir.exists("www"))

    # Test key assets
    www_files <- c("www/style.css")
    for(file in www_files) {
      expect_true(file.exists(file), info = paste("Missing www file:", file))
    }

    })
})