library(tinytest)

# Helpers (see test_enhanced-field-types.R's own comment on this
# pattern).
if (file.exists("_setup.R")) source("_setup.R")

# Part C: renderPanel() gains `columns`, `tooltip_mode`, and
# `extra_tags` arguments. These tests cover the three behaviors the
# plan (soft-orbiting-acorn.md, Part C) calls out explicitly:
# (1) the no-new-args call stays byte-identical to the pre-Part-C
#     markup (the regression guard against breaking every existing
#     caller: inst/app/edc.R's two renderPanel() call sites, the
#     correction module's single-field call, and every test in
#     test_enhanced-field-types.R);
# (2) `columns > 1` actually produces fluidRow()/column() grouping
#     from field_row/field_width, instead of the flat stack
#     get_crf_field_metadata()'s row/column/width values were
#     previously fetched-and-ignored by;
# (3) `tooltip_mode = "expanded"` adds the visible help-text element
#     without removing the existing hover icon.

# (1) Regression guard: calling renderPanel() with no new arguments
# at all must produce byte-identical HTML to calling it with the new
# arguments left at their defaults, for both the field-metadata path
# and the plain-fields fallback path.
local({
  metadata <- list(
    age = list(type = "numeric", label = "Age", min = 0, max = 120, value = 25),
    visit_date = list(type = "date", label = "Visit Date", value = as.Date("2025-01-15")),
    notes = list(type = "notes", label = "Notes", help = "Free text")
  )

  old_call <- renderPanel(names(metadata), metadata)
  new_call_defaults <- renderPanel(names(metadata), metadata,
                                    columns = 1, tooltip_mode = "minimal",
                                    extra_tags = NULL)

  expect_identical(
    as.character(shiny::tagList(old_call)),
    as.character(shiny::tagList(new_call_defaults)),
    info = "columns=1/tooltip_mode=minimal/extra_tags=NULL must be byte-identical to omitting all three"
  )

  # The plain-fields (no field_metadata) fallback is explicitly
  # documented as unaffected by either new argument.
  expect_identical(
    as.character(shiny::tagList(renderPanel(c("f1", "f2")))),
    as.character(shiny::tagList(renderPanel(c("f1", "f2"), columns = 3,
                                             tooltip_mode = "expanded"))),
    info = "columns/tooltip_mode have no effect when field_metadata is NULL"
  )
})

# (2) columns > 1: fixture mirrors get_crf_field_metadata()'s shape
# (field_row/field_column/field_width now included, see
# R/edc_dynamic_forms.R) -- two fields sharing field_row 1 (50/50
# width), one field alone on field_row 2.
local({
  metadata <- list(
    a = list(type = "text", label = "A", field_row = 1L, field_column = 1L, field_width = 50L),
    b = list(type = "text", label = "B", field_row = 1L, field_column = 2L, field_width = 50L),
    c = list(type = "numeric", label = "C", field_row = 2L, field_column = 1L, field_width = 100L)
  )

  result <- renderPanel(names(metadata), metadata, columns = 2)

  expect_equal(length(result), 2,
               info = "two visual rows: {a, b} share field_row 1, c is alone on field_row 2")

  row1_html <- as.character(result[[1]])
  expect_true(grepl('class="row"', row1_html), info = "row 1 is a fluidRow()")
  expect_equal(lengths(regmatches(row1_html, gregexpr('col-sm-[0-9]+', row1_html))), 2,
               info = "row 1 has two column() children")
  expect_true(grepl("col-sm-6", row1_html),
              info = "50/50 width normalizes to 6/12 + 6/12")
  expect_true(grepl('id="a"', row1_html) && grepl('id="b"', row1_html))

  row2_html <- as.character(result[[2]])
  expect_true(grepl('class="row"', row2_html), info = "row 2 is its own fluidRow()")
  expect_true(grepl("col-sm-12", row2_html),
              info = "a single full-width (100) field alone in its chunk gets the full 12 columns")
  expect_true(grepl('id="c"', row2_html))

  # A design-row with more fields than the viewer's column cap is
  # split into consecutive sub-chunks of at most `columns` fields,
  # not just left overflowing one fluidRow().
  metadata3 <- list(
    x = list(type = "text", label = "X", field_row = 1L, field_width = 100L),
    y = list(type = "text", label = "Y", field_row = 1L, field_width = 100L),
    z = list(type = "text", label = "Z", field_row = 1L, field_width = 100L)
  )
  result3 <- renderPanel(names(metadata3), metadata3, columns = 2)
  expect_equal(length(result3), 2,
               info = "3 fields on one design row, columns=2 cap -> chunks of 2 and 1")
  expect_equal(
    lengths(regmatches(as.character(result3[[1]]),
                        gregexpr('col-sm-[0-9]+', as.character(result3[[1]])))),
    2
  )
  expect_equal(
    lengths(regmatches(as.character(result3[[2]]),
                        gregexpr('col-sm-[0-9]+', as.character(result3[[2]])))),
    1
  )

  # A form where every field already has its own distinct field_row
  # (as some imports annotate every field, see renderPanel()'s own
  # roxygen) still renders one field per visual row regardless of
  # `columns` -- the cap only ever reduces fields-per-row, it never
  # combines fields the form's own author put on separate rows.
  metadata_one_per_row <- list(
    p = list(type = "text", label = "P", field_row = 1L, field_width = 100L),
    q = list(type = "text", label = "Q", field_row = 2L, field_width = 100L)
  )
  result_opr <- renderPanel(names(metadata_one_per_row), metadata_one_per_row, columns = 3)
  expect_equal(length(result_opr), 2,
               info = "one field per design row stays one field per visual row even with columns=3")
})

# (3) tooltip_mode = "expanded": the visible help-text element is
# added IN ADDITION TO the hover icon, never instead of it.
local({
  metadata <- list(
    comment = list(type = "text", label = "Comment", help = "A short explanation")
  )

  minimal_html <- as.character(shiny::tagList(renderPanel("comment", metadata)))
  expanded_html <- as.character(shiny::tagList(
    renderPanel("comment", metadata, tooltip_mode = "expanded")
  ))

  expect_true(grepl("field-hint-icon", minimal_html),
              info = "minimal mode has the hover icon")
  expect_false(grepl("field-help-expanded", minimal_html),
               info = "minimal mode has no always-visible help text")

  expect_true(grepl("field-hint-icon", expanded_html),
              info = "expanded mode still has the hover icon (additive, not a replacement)")
  expect_true(grepl("field-help-expanded", expanded_html),
              info = "expanded mode adds the always-visible help text")
  expect_true(grepl("A short explanation", expanded_html))

  # A field with no help text gets no expanded element, in either mode.
  no_help <- list(blank = list(type = "text", label = "Blank"))
  expanded_no_help <- as.character(shiny::tagList(
    renderPanel("blank", no_help, tooltip_mode = "expanded")
  ))
  expect_false(grepl("field-help-expanded", expanded_no_help),
               info = "no help text means no expanded element even in expanded mode")
})

# extra_tags: placed with the named field, not spliced in by
# position -- this is what keeps inst/app/edc.R's custom-widget
# trigger UI attached to the right field once columns > 1 regroups
# renderPanel()'s return value into fluidRow()s (a positional splice
# would otherwise land on the wrong field, or not match the returned
# list's new shape at all).
local({
  metadata <- list(
    a = list(type = "text", label = "A", field_row = 1L, field_width = 50L),
    b = list(type = "text", label = "B", field_row = 1L, field_width = 50L)
  )
  extra <- list(b = shiny::tags$div(id = "b_extra_widget", "widget trigger"))

  flat <- renderPanel(names(metadata), metadata, extra_tags = extra)
  expect_equal(length(flat), 2,
               info = "extra_tags does not change the flat list's length (columns=1)")
  expect_true(grepl("b_extra_widget", as.character(flat[[2]])))
  expect_false(grepl("b_extra_widget", as.character(flat[[1]])),
               info = "extra_tags for field b is not attached to field a")

  grouped <- renderPanel(names(metadata), metadata, columns = 2, extra_tags = extra)
  expect_true(grepl("b_extra_widget", as.character(grouped[[1]])),
              info = "extra_tags still lands on field b even once columns>1 groups fields into fluidRow()")
})
