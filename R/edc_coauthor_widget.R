#' Co-author name formatting/splitting helpers for the EDC tab
#'
#' Pure string helpers backing the manuscripts form's co-author
#' builder widget (`inst/app/edc.R`): formatting one name into a
#' chosen style, joining several into one delimited string,
#' splitting that string back apart, and a best-effort parse of one
#' name string back into first/middle/last parts. None of these
#' touch the database or a Shiny session, so they are unit-testable
#' directly.
#'
#' @name coauthor_widget
#' @keywords internal
NULL


#' Format one author's name in a chosen style
#'
#' @param first,middle,last Name parts; `middle` and any blank parts
#'   are dropped rather than leaving stray whitespace.
#' @param format One of `"first_middle_last"`, `"last_first_middle"`,
#'   `"last_initials"`. Any other value falls back to
#'   `"first_middle_last"`.
#' @return A single formatted name string (`""` if every part is
#'   blank).
#' @keywords internal
format_author_name <- function(first, middle = "", last = "", format = "first_middle_last") {
  first <- trimws(first %||% "")
  middle <- trimws(middle %||% "")
  last <- trimws(last %||% "")

  initials_of <- function(...) {
    parts <- Filter(nzchar, c(...))
    if (length(parts) == 0) return("")
    paste0(toupper(substring(parts, 1, 1)), ".", collapse = "")
  }

  switch(
    format,
    "last_first_middle" = {
      given <- paste(Filter(nzchar, c(first, middle)), collapse = " ")
      if (nzchar(last) && nzchar(given)) sprintf("%s, %s", last, given)
      else paste0(last, given)
    },
    "last_initials" = {
      ini <- initials_of(first, middle)
      if (nzchar(last) && nzchar(ini)) sprintf("%s, %s", last, ini)
      else paste0(last, ini)
    },
    # "first_middle_last" and any unrecognized value
    paste(Filter(nzchar, c(first, middle, last)), collapse = " ")
  )
}


#' Join formatted author names with a chosen delimiter
#'
#' @param names Character vector of already-formatted names, in order.
#' @param delimiter One of `"comma"`, `"semicolon"`, `"comma_and"`.
#'   Any other value behaves like `"comma"`. May be named (e.g. from
#'   `vapply()` over a named list of author rows) or not -- any
#'   names are dropped immediately so the single-author fast path
#'   below can never return a *named* length-1 vector. That
#'   distinction matters downstream: `shiny::updateTextInput()`
#'   JSON-serializes a named vector as an object rather than a
#'   plain string, which renders client-side as the literal text
#'   "\[object Object\]" instead of the name.
#' @return A single joined string; `""` for an empty/all-blank `names`.
#' @keywords internal
join_author_names <- function(names, delimiter = "comma") {
  names <- unname(names %||% character(0))
  names <- Filter(nzchar, trimws(names))
  if (length(names) == 0) return("")
  if (length(names) == 1) return(names)
  switch(
    delimiter,
    "semicolon" = paste(names, collapse = "; "),
    "comma_and" = paste0(
      paste(names[-length(names)], collapse = ", "), ", and ", names[length(names)]
    ),
    paste(names, collapse = ", ")
  )
}


#' Split a joined author-list string back into individual name strings
#'
#' A best-effort inverse of [join_author_names()] -- it assumes the
#' text was actually joined with `delimiter`, which this function
#' has no way to verify. For `"comma_and"`, the literal " and"
#' immediately before the last item is stripped first (it is not
#' itself part of a name) so the rest can split on commas normally.
#'
#' This is fundamentally ambiguous for text whose individual names
#' themselves contain a comma (e.g. `"last_first_middle"`- or
#' `"last_initials"`-formatted text split on `"comma"`): each name's
#' own internal comma looks identical to the delimiter between
#' names, so such text will be split into more, shorter fragments
#' than there are actual authors. Use `"semicolon"` as the delimiter
#' for text in either of those two styles to avoid this.
#'
#' @param text The joined string, as currently typed in the
#'   co_authors field.
#' @param delimiter One of `"comma"`, `"semicolon"`, `"comma_and"`.
#' @return Character vector of individual, trimmed name fragments;
#'   `character(0)` for blank `text`.
#' @keywords internal
split_author_list <- function(text, delimiter = "comma") {
  text <- trimws(text %||% "")
  if (!nzchar(text)) return(character(0))

  if (identical(delimiter, "comma_and")) {
    # join_author_names()'s "comma_and" join inserts the literal
    # substring ", and " exactly once, right before the last name,
    # regardless of what that last name itself looks like -- so
    # this strips it unconditionally rather than also requiring
    # (and failing to find, when the last name has its own comma,
    # e.g. "Last, Initials" style) a comma-free run to the end of
    # the string.
    text <- sub(", and ", ", ", text, fixed = TRUE)
  }
  sep <- if (identical(delimiter, "semicolon")) ";" else ","
  parts <- strsplit(text, sep, fixed = TRUE)[[1]]
  trimws(parts)
}


#' Best-effort parse of one name string into first/middle/last parts
#'
#' Two shapes are recognized: `"Last, First Middle"` (a comma is
#' present -- this also matches `"Last, Initials"` text, which ends
#' up with the initials string as the parsed `first` and an empty
#' `middle`, not split further) and `"First [Middle] Last"` (no
#' comma -- the first word is `first`, the last word is `last`,
#' anything between is `middle`). A single word with no comma is
#' treated as `last` alone.
#'
#' This is a heuristic over free text, not a real name parser: it
#' does not special-case suffixes (`"Jr."`, `"III"`), multi-word
#' surnames (`"van der Berg"`), or a single given name with no
#' surname. Reviewing (and editing, or removing and re-adding) the
#' parsed rows before applying them is expected for anything other
#' than simple Western given-name-then-surname text.
#'
#' @param name_str One name, already split out of a joined list
#'   (e.g. by [split_author_list()]).
#' @return `list(first=, middle=, last=)`, each a (possibly empty)
#'   string.
#' @keywords internal
parse_author_name <- function(name_str) {
  name_str <- trimws(name_str %||% "")
  if (!nzchar(name_str)) return(list(first = "", middle = "", last = ""))

  if (grepl(",", name_str, fixed = TRUE)) {
    parts <- strsplit(name_str, ",", fixed = TRUE)[[1]]
    last <- trimws(parts[1])
    given <- trimws(paste(parts[-1], collapse = ","))
    given_parts <- Filter(nzchar, strsplit(given, "\\s+")[[1]])
    if (length(given_parts) == 0) {
      return(list(first = "", middle = "", last = last))
    }
    return(list(
      first = given_parts[1],
      middle = paste(given_parts[-1], collapse = " "),
      last = last
    ))
  }

  words <- Filter(nzchar, strsplit(name_str, "\\s+")[[1]])
  if (length(words) == 0) return(list(first = "", middle = "", last = ""))
  if (length(words) == 1) return(list(first = "", middle = "", last = words[1]))
  list(
    first = words[1],
    middle = paste(words[-c(1, length(words))], collapse = " "),
    last = words[length(words)]
  )
}
