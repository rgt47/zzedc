library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Tests for the studies registry (R/lab_registry.R), the data behind
# the lab landing page (launch_lab()).

if (!exists("register_study")) exit_file("lab registry functions not available")

# .registry_path() reads HOME; redirect it to a scratch directory for
# the duration of this file so these tests never touch the real
# ~/.zzedc/studies.yml.
old_home <- Sys.getenv("HOME")
scratch_home <- tempfile("zzedc_registry_test_")
dir.create(scratch_home)
Sys.setenv(HOME = scratch_home)

make_fake_study <- function(name) {
  path <- file.path(scratch_home, name)
  dir.create(path, recursive = TRUE)
  writeLines(c(
    "default:",
    "  database:",
    "    backend: sqlite",
    "    path: data/zzedc.db",
    "  study:",
    paste0("    name: '", name, "'")
  ), file.path(path, "config.yml"))
  path
}

# list_studies() on a fresh HOME (no registry file yet) is empty, not
# an error.
expect_equal(nrow(list_studies()), 0L,
             info = "no registry file yet means zero rows, not an error")

# register_study() refuses a directory with no config.yml.
no_config_dir <- file.path(scratch_home, "no-config-here")
dir.create(no_config_dir)
res_no_config <- register_study(no_config_dir)
expect_false(res_no_config$success)
expect_true(grepl("No config.yml", res_no_config$error))

# Register two real (fixture) studies.
promo_path <- make_fake_study("Promotion Tracker")
res_promo <- register_study(promo_path, name = "Promotion Review Tracker")
expect_true(res_promo$success)
expect_equal(res_promo$id, "promotion-review-tracker")

adhd_path <- make_fake_study("ADHD Trial")
res_adhd <- register_study(adhd_path, name = "ADHD Trial")
expect_true(res_adhd$success)

rows <- list_studies()
expect_equal(nrow(rows), 2L)
expect_true(all(c("promotion-review-tracker", "adhd-trial") %in% rows$id))
expect_true(all(rows$exists), info = "both fixture paths exist on disk")
expect_true(all(rows$backend == "sqlite"))

# Re-registering the same path updates rather than duplicates.
res_promo_again <- register_study(promo_path, name = "Promotion Review Tracker")
expect_true(res_promo_again$success)
expect_equal(res_promo_again$id, "promotion-review-tracker")
expect_equal(nrow(list_studies()), 2L,
             info = "re-registering an existing path does not create a duplicate row")

# Name read from config.yml when name = NULL.
anon_path <- file.path(scratch_home, "anon-study")
dir.create(anon_path)
writeLines(c(
  "default:", "  database:", "    backend: duckdb", "    path: data/x.duckdb",
  "  study:", "    name: 'From Config File'"
), file.path(anon_path, "config.yml"))
res_anon <- register_study(anon_path)
expect_true(res_anon$success)
anon_row <- list_studies()[list_studies()$id == res_anon$id, ]
expect_equal(anon_row$name[1], "From Config File")

# A study with no study: block in its config.yml falls back to the
# directory's basename.
plain_path <- file.path(scratch_home, "plain-basename-study")
dir.create(plain_path)
writeLines(c("default:", "  database:", "    backend: sqlite", "    path: data/x.db"),
           file.path(plain_path, "config.yml"))
res_plain <- register_study(plain_path)
expect_true(res_plain$success)
plain_row <- list_studies()[list_studies()$id == res_plain$id, ]
expect_equal(plain_row$name[1], "plain-basename-study")

# unregister_study() removes the row and does not touch the directory.
expect_equal(nrow(list_studies()), 4L)
unreg_res <- unregister_study(res_adhd$id)
expect_true(unreg_res$success)
expect_equal(nrow(list_studies()), 3L)
expect_true(dir.exists(adhd_path), info = "unregistering never deletes the study's own directory")
expect_true(file.exists(file.path(adhd_path, "config.yml")))

# unregister_study() on an unknown id fails informatively rather than
# silently no-op-ing.
unreg_missing <- unregister_study("no-such-id")
expect_false(unreg_missing$success)

# A registered study whose directory has since been deleted reports
# exists == FALSE, not an error.
unlink(plain_path, recursive = TRUE)
stale_row <- list_studies()[list_studies()$id == res_plain$id, ]
expect_false(stale_row$exists[1])

# UI-construction smoke test for the landing page: building the tile
# grid (populated and empty) must not error, the same check already
# applied to create_enhanced_ui() elsewhere in this test suite.
if (exists(".studies_grid") && requireNamespace("bslib", quietly = TRUE)) {
  grid <- tryCatch(.studies_grid(list_studies()), error = function(e) e)
  expect_false(inherits(grid, "error"), info = "building the populated tile grid does not error")

  empty_grid <- tryCatch(.studies_grid(list_studies()[0, ]), error = function(e) e)
  expect_false(inherits(empty_grid, "error"), info = "building the empty tile grid does not error")

  ui <- tryCatch(.lab_ui(), error = function(e) e)
  expect_false(inherits(ui, "error"), info = "building the landing page's UI does not error")
}

# Restore HOME and clean up.
Sys.setenv(HOME = old_home)
unlink(scratch_home, recursive = TRUE)
