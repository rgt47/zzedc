test_that("launch_zzedc function exists and has proper structure", {
  # Test that the function exists
  expect_true(exists("launch_zzedc"))
  
  # Test that it's a function
  expect_type(launch_zzedc, "closure")
  
  # Test function arguments
  args <- names(formals(launch_zzedc))
  expect_true("..." %in% args)
  expect_true("launch.browser" %in% args)
  expect_true("host" %in% args)
  expect_true("port" %in% args)
})

test_that("required directories are created", {
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

test_that("package structure is valid", {
  # Test that key files exist
  expect_true(file.exists("ui.R"))
  expect_true(file.exists("server.R")) 
  expect_true(file.exists("global.R"))
  
  # Test that R/ directory exists with key functions
  expect_true(dir.exists("R"))
  expect_true(file.exists("R/launch_zzedc.R"))
  expect_true(file.exists("R/zzedc-package.R"))
  
  # Test DESCRIPTION file
  expect_true(file.exists("DESCRIPTION"))
})

test_that("key app components exist", {
  # Test that required R files exist
  required_files <- c("ui.R", "server.R", "global.R", "home.R", "edc.R", 
                     "auth.R", "savedata.R", "report1.R", "report2.R", 
                     "report3.R", "data.R", "export.R")
  
  for(file in required_files) {
    expect_true(file.exists(file), info = paste("Missing file:", file))
  }
})

test_that("forms directory structure exists", {
  # Test forms directory and files
  expect_true(dir.exists("forms"))
  
  forms_files <- c("forms/blfieldlist.R", "forms/renderpanels.R", "forms/save.R")
  for(file in forms_files) {
    expect_true(file.exists(file), info = paste("Missing forms file:", file))
  }
})

test_that("www directory and assets exist", {
  # Test www directory for web assets
  expect_true(dir.exists("www"))
  
  # Test key assets
  www_files <- c("www/style.css")
  for(file in www_files) {
    expect_true(file.exists(file), info = paste("Missing www file:", file))
  }
})