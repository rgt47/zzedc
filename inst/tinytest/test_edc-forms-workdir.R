library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Regression tests for inst/app/edc.R's forms/ path resolution.
#
# shiny::runApp(appDir = ...) (called from launch_zzedc()) keeps the
# Shiny process's working directory set to the installed package's
# app directory for the whole app lifetime, not the directory the
# user launched from. edc.R's forms/ lookups previously used bare
# relative paths ("forms/blfieldlist.R"), which resolved against
# that wrong directory, so a correctly-scaffolded forms/ directory
# in the user's project was silently invisible to the EDC tab (it
# always showed the "forms not found" panel, or worse). The fix
# mirrors the existing ZZEDC_WORK_DIR pattern already used by
# inst/app/global.R for the database path.

.load_edc_helpers <- function() {
  app_dir <- system.file("app", package = "zzedc")
  lines <- readLines(file.path(app_dir, "edc.R"))
  end <- grep("^output\\$ui", lines)[1] - 1
  env <- new.env(parent = globalenv())
  eval(parse(text = lines[1:end]), envir = env)
  env
}

local({
  # Simulate the real deployment: a study directory with forms/,
  # ZZEDC_WORK_DIR pointing at it, and the process cwd pointing
  # somewhere else entirely (standing in for the installed app dir).
  study_dir <- tempfile("zzedc-study-")
  dir.create(file.path(study_dir, "forms"), recursive = TRUE)
  writeLines("c('a', 'b')", file.path(study_dir, "forms", "blfieldlist.R"))
  writeLines("NULL", file.path(study_dir, "forms", "renderpanels.R"))
  writeLines("NULL", file.path(study_dir, "forms", "save.R"))

  elsewhere_dir <- tempfile("zzedc-elsewhere-")
  dir.create(elsewhere_dir)

  old_wd <- getwd()
  withr::local_envvar(c(ZZEDC_WORK_DIR = study_dir))
  setwd(elsewhere_dir)
  on.exit(setwd(old_wd), add = TRUE)

  env <- .load_edc_helpers()

  expect_equal(env$.zzedc_work_dir(), study_dir,
               info = "ZZEDC_WORK_DIR must override getwd() for forms/ resolution")
  expect_true(env$.zzedc_forms_present(),
              info = "forms/ files in ZZEDC_WORK_DIR must be found even when cwd differs")
  expect_equal(env$.zzedc_forms_path("blfieldlist.R"),
               file.path(study_dir, "forms", "blfieldlist.R"))
})

local({
  # Without ZZEDC_WORK_DIR set, falls back to getwd() (the
  # interactive/pkgload::load_all() development case).
  study_dir <- tempfile("zzedc-study-")
  dir.create(file.path(study_dir, "forms"), recursive = TRUE)
  writeLines("c('a')", file.path(study_dir, "forms", "blfieldlist.R"))
  writeLines("NULL", file.path(study_dir, "forms", "renderpanels.R"))
  writeLines("NULL", file.path(study_dir, "forms", "save.R"))

  old_wd <- getwd()
  withr::local_envvar(c(ZZEDC_WORK_DIR = NA))
  setwd(study_dir)
  on.exit(setwd(old_wd), add = TRUE)

  env <- .load_edc_helpers()

  expect_equal(env$.zzedc_work_dir(), getwd())
  expect_true(env$.zzedc_forms_present())
})

local({
  # A directory with no forms/ at all correctly reports absent,
  # regardless of ZZEDC_WORK_DIR resolution working correctly.
  empty_dir <- tempfile("zzedc-empty-")
  dir.create(empty_dir)

  old_wd <- getwd()
  withr::local_envvar(c(ZZEDC_WORK_DIR = empty_dir))
  setwd(tempdir())
  on.exit(setwd(old_wd), add = TRUE)

  env <- .load_edc_helpers()

  expect_false(env$.zzedc_forms_present())
})
