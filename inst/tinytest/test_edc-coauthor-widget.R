library(tinytest)

# Regression tests for R/edc_coauthor_widget.R, the pure string
# helpers backing the manuscripts form's co-author builder widget.

local({
  # format_author_name()
  expect_equal(
    zzedc:::format_author_name("Elaine", "R.", "Peskind", "first_middle_last"),
    "Elaine R. Peskind"
  )
  expect_equal(
    zzedc:::format_author_name("Elaine", "", "Peskind", "first_middle_last"),
    "Elaine Peskind",
    info = "a blank middle name leaves no stray double space"
  )
  expect_equal(
    zzedc:::format_author_name("Elaine", "R.", "Peskind", "last_first_middle"),
    "Peskind, Elaine R."
  )
  expect_equal(
    zzedc:::format_author_name("Elaine", "", "Peskind", "last_first_middle"),
    "Peskind, Elaine"
  )
  expect_equal(
    zzedc:::format_author_name("Elaine", "Rachel", "Peskind", "last_initials"),
    "Peskind, E.R."
  )
  expect_equal(
    zzedc:::format_author_name("Elaine", "", "Peskind", "last_initials"),
    "Peskind, E."
  )
  expect_equal(
    zzedc:::format_author_name("", "", "Meabon", "first_middle_last"),
    "Meabon",
    info = "a single-word name (no given name) is just the last name"
  )
  expect_equal(
    zzedc:::format_author_name("A", "B", "C", "bogus_format"),
    "A B C",
    info = "an unrecognized format string falls back to first_middle_last"
  )
})

local({
  # join_author_names()
  expect_equal(zzedc:::join_author_names(character(0)), "")
  expect_equal(zzedc:::join_author_names("Solo Author"), "Solo Author",
               info = "a single name is never followed by a delimiter")
  expect_equal(
    zzedc:::join_author_names(c("A", "B", "C"), "comma"), "A, B, C"
  )
  expect_equal(
    zzedc:::join_author_names(c("A", "B", "C"), "semicolon"), "A; B; C"
  )
  expect_equal(
    zzedc:::join_author_names(c("A", "B", "C"), "comma_and"), "A, B, and C"
  )
  expect_equal(
    zzedc:::join_author_names(c("A", "B"), "comma_and"), "A, and B",
    info = "comma_and still inserts the comma before 'and' with only two names"
  )
  expect_equal(
    zzedc:::join_author_names(c("A", "", "B"), "comma"), "A, B",
    info = "a blank name slot is dropped, not joined as an empty entry"
  )

  # Regression: vapply() over a named list of author rows (as the
  # EDC tab's coauthor_apply/coauthor_reformat observers do) returns
  # a NAMED character vector. The single-author fast path must drop
  # those names -- a named length-1 result previously survived all
  # the way to shiny::updateTextInput(), whose JSON serializer turns
  # a named vector into an object instead of a plain string,
  # rendering as the literal text "[object Object]" in the browser
  # (reproduced live: applying a one-author list wrote exactly that
  # into the Co-authors field).
  solo_named <- vapply(list(a = list(x = "Solo Author")), function(r) r$x, character(1))
  expect_true(!is.null(names(solo_named)), info = "vapply does produce a named result here")
  joined <- zzedc:::join_author_names(solo_named)
  expect_equal(joined, "Solo Author")
  expect_null(names(joined), info = "the join result itself must never carry a name")
})

local({
  # split_author_list()
  expect_equal(zzedc:::split_author_list(""), character(0))
  expect_equal(zzedc:::split_author_list("A, B, C", "comma"), c("A", "B", "C"))
  expect_equal(zzedc:::split_author_list("A; B; C", "semicolon"), c("A", "B", "C"))
  expect_equal(zzedc:::split_author_list("A, B, and C", "comma_and"), c("A", "B", "C"))
  expect_equal(zzedc:::split_author_list("A, and B", "comma_and"), c("A", "B"),
               info = "the two-name comma_and join also splits back cleanly")
  expect_equal(zzedc:::split_author_list("Solo Author", "comma"), "Solo Author")

  expect_equal(
    zzedc:::split_author_list("Doe, J.Q., and Smith, J.", "comma_and"),
    c("Doe", "J.Q.", "Smith", "J."),
    info = paste(
      "the ', and ' stripping itself works even when the trailing",
      "name has its own comma (previously the strip regex required",
      "a comma-free run to the string's end and silently failed to",
      "match at all here, leaving a literal 'and' masquerading as a",
      "fake author); the remaining over-split across each name's own",
      "internal comma is the same documented ambiguity as plain",
      "comma delimiting, not something comma_and can fix"
    )
  )

  # Documented limitation: "last_first_middle"/"last_initials" text
  # re-split on "comma" over-splits, since each name's own internal
  # comma is indistinguishable from the delimiter. Pinned here as
  # current behavior, not as "correct" -- the widget's own guidance
  # is to use "semicolon" for text in either of those two styles.
  expect_equal(
    zzedc:::split_author_list("Peskind, Elaine, Raskind, Murray", "comma"),
    c("Peskind", "Elaine", "Raskind", "Murray"),
    info = "known limitation: comma-delimited 'Last, First' text over-splits on its own internal commas"
  )
  expect_equal(
    zzedc:::split_author_list("Peskind, Elaine; Raskind, Murray", "semicolon"),
    c("Peskind, Elaine", "Raskind, Murray"),
    info = "semicolon delimiter avoids the over-split for 'Last, First' style text"
  )
})

local({
  # parse_author_name()
  expect_equal(
    zzedc:::parse_author_name("Elaine R. Peskind"),
    list(first = "Elaine", middle = "R.", last = "Peskind")
  )
  expect_equal(
    zzedc:::parse_author_name("Elaine Peskind"),
    list(first = "Elaine", middle = "", last = "Peskind"),
    info = "no middle part when there are only two words"
  )
  expect_equal(
    zzedc:::parse_author_name("Meabon"),
    list(first = "", middle = "", last = "Meabon"),
    info = "a single word is treated as the surname alone"
  )
  expect_equal(
    zzedc:::parse_author_name("Peskind, Elaine R."),
    list(first = "Elaine", middle = "R.", last = "Peskind"),
    info = "a comma signals 'Last, First Middle' order"
  )
  expect_equal(
    zzedc:::parse_author_name("Peskind, E.R."),
    list(first = "E.R.", middle = "", last = "Peskind"),
    info = "an initials-only given-name part is not split further"
  )
  expect_equal(
    zzedc:::parse_author_name(""),
    list(first = "", middle = "", last = "")
  )
  expect_equal(
    zzedc:::parse_author_name("  Elaine   R.   Peskind  "),
    list(first = "Elaine", middle = "R.", last = "Peskind"),
    info = "repeated/leading/trailing whitespace is collapsed"
  )
})

local({
  # Round trip: format -> join -> split -> parse should recover the
  # original parts for a well-behaved (non-comma-ambiguous) case.
  original <- list(first = "Elaine", middle = "R.", last = "Peskind")
  formatted <- zzedc:::format_author_name(
    original$first, original$middle, original$last, "first_middle_last"
  )
  joined <- zzedc:::join_author_names(c(formatted, "Murray A. Raskind"), "semicolon")
  split <- zzedc:::split_author_list(joined, "semicolon")
  expect_equal(length(split), 2)
  reparsed <- zzedc:::parse_author_name(split[1])
  expect_equal(reparsed, original)
})
