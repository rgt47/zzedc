library(tinytest)

# Regression tests for .filter_gsheets_candidates(), the pure
# ranking/filtering core of detect_gsheets_candidates()
# (R/validation_gsheets_integration.R). detect_gsheets_candidates()
# itself needs a live Google Drive/Sheets connection (googledrive's
# own OAuth scope, separate from googlesheets4's), which this suite
# does not have; .filter_gsheets_candidates() takes a sheet_names_fn
# instead, the same dependency-injection shape
# .setup_zzedc_from_tables() already uses for read_tab, so its
# filtering and ordering logic can be tested without one.

local({
  files <- data.frame(
    id = c("sheet_a", "sheet_b", "sheet_c"),
    name = c("Promotion Review Tracker", "Unrelated Budget", "ADHD Trial Dictionary"),
    modified_time = c("2026-11-10T00:00:00Z", "2026-11-13T00:00:00Z", "2026-11-12T00:00:00Z"),
    stringsAsFactors = FALSE
  )

  tabs_by_id <- list(
    sheet_a = c("Study_Users", "Data_Dictionary", "validation_rules"),
    sheet_b = c("Sheet1", "Sheet2"),
    sheet_c = c("Study_Users", "Data_Dictionary")
  )
  sheet_names_fn <- function(id) tabs_by_id[[id]]

  res <- zzedc:::.filter_gsheets_candidates(
    files, c("Study_Users", "Data_Dictionary"), sheet_names_fn
  )

  expect_equal(nrow(res), 2,
               info = "only the two spreadsheets with both required tabs match")
  expect_false("sheet_b" %in% res$id,
               info = "a spreadsheet missing both required tabs is excluded")
  expect_equal(res$id, c("sheet_c", "sheet_a"),
               info = "matches are ordered most-recently-modified first")

  # No candidate has the required tabs.
  none <- zzedc:::.filter_gsheets_candidates(
    files, c("Study_Users", "Data_Dictionary"), function(id) character(0)
  )
  expect_equal(nrow(none), 0)
  expect_equal(names(none), c("id", "name", "modified_time"),
               info = "an empty result still has the documented columns")

  # No candidate spreadsheets found at all (files has zero rows).
  empty_files <- data.frame(id = character(0), name = character(0),
                             modified_time = character(0))
  empty_res <- zzedc:::.filter_gsheets_candidates(
    empty_files, c("Study_Users", "Data_Dictionary"), sheet_names_fn
  )
  expect_equal(nrow(empty_res), 0)

  # A spreadsheet with extra tabs beyond the required ones still matches.
  extra <- zzedc:::.filter_gsheets_candidates(
    files, c("Study_Users"), sheet_names_fn
  )
  expect_equal(sort(extra$id), c("sheet_a", "sheet_c"),
               info = "required_tabs need only be a subset of a sheet's tabs")
})
