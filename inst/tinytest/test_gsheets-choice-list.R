library(tinytest)

# Regression tests for the Data_Dictionary `validation` column's
# `in(...)` choice-list support in R/validation_gsheets_integration.R
# (parse_gsheets_choice_list(), beautify_choice_label()), added so
# setup_zzedc_from_gsheets() can populate designer_field_options for
# SELECT/RADIO/MULTISELECT fields on import instead of always
# leaving it empty. These two helpers are pure functions and do not
# need a database fixture or a live Google Sheet; the Stage 3 import
# loop that calls them is only exercised indirectly (it requires
# googlesheets4 and a live sheet, which this suite does not have).

local({
  # Basic bare-value lists, as used throughout the package's own
  # shipped example Data_Dictionary.csv sheets.
  expect_equal(
    zzedc:::parse_gsheets_choice_list("in(ideation,drafting,submitted)"),
    c("ideation", "drafting", "submitted")
  )
  expect_equal(
    zzedc:::parse_gsheets_choice_list("in(Fall,Winter,Spring,Summer)"),
    c("Fall", "Winter", "Spring", "Summer")
  )
  expect_equal(
    zzedc:::parse_gsheets_choice_list("in(1,2,4,6)"),
    c("1", "2", "4", "6"),
    info = "numeric-looking tokens come back as character, matching option_value's TEXT column"
  )

  # Whitespace tolerance and case-insensitivity of the `in` keyword.
  expect_equal(
    zzedc:::parse_gsheets_choice_list("in( Fall , Winter ,Spring)"),
    c("Fall", "Winter", "Spring")
  )
  expect_equal(
    zzedc:::parse_gsheets_choice_list("IN(a,b)"),
    c("a", "b")
  )
  expect_equal(
    zzedc:::parse_gsheets_choice_list("  in(a,b)  "),
    c("a", "b"),
    info = "leading/trailing whitespace around the whole cell is tolerated"
  )

  # Non-matching/empty/missing cells all return NULL rather than
  # erroring, since `validation` is an optional column and most rows
  # (non-choice-type fields) will not use this syntax at all.
  expect_null(zzedc:::parse_gsheets_choice_list(NA))
  expect_null(zzedc:::parse_gsheets_choice_list(""))
  expect_null(zzedc:::parse_gsheets_choice_list("   "))
  expect_null(zzedc:::parse_gsheets_choice_list("not a choice list"))
  expect_null(zzedc:::parse_gsheets_choice_list("required"),
              info = "a `validation` cell used for something else (not in(...)) is ignored, not an error")
  expect_null(zzedc:::parse_gsheets_choice_list(NULL),
              info = "a missing `validation` column reads as NULL via df$validation; must not error")
  expect_null(zzedc:::parse_gsheets_choice_list("in()"),
              info = "an empty choice list parses to no values, not a vector of one empty string")
})

local({
  expect_equal(zzedc:::beautify_choice_label("under_review"), "Under Review")
  expect_equal(zzedc:::beautify_choice_label("in_press"), "In Press")
  expect_equal(zzedc:::beautify_choice_label("drafting"), "Drafting")
  expect_equal(zzedc:::beautify_choice_label("Fall"), "Fall")
  expect_equal(zzedc:::beautify_choice_label("some-value"), "Some Value")
  expect_equal(
    zzedc:::beautify_choice_label("1"), "1",
    info = "a bare numeric token (e.g. a dose level) passes through unchanged"
  )
})
