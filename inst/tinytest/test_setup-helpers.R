library(tinytest)

# _setup.R is source()d into the global environment, where exit_file
# resolves to tinytest's exported stub, which only returns its message.
# A helper there that calls exit_file() is therefore a silent no-op:
# the skip() and skip_if_*() helpers it once defined never skipped
# anything, and code written after a skip() ran. Guard against that
# pattern returning.

if (!file.exists("_setup.R")) exit_file("_setup.R not found")

exprs <- parse("_setup.R", keep.source = FALSE)

calls_in <- function(x) {
  if (is.call(x)) {
    head <- if (is.symbol(x[[1]])) as.character(x[[1]]) else character()
    c(head, unlist(lapply(as.list(x)[-1], calls_in)))
  } else if (is.pairlist(x) || is.expression(x) || is.list(x)) {
    unlist(lapply(as.list(x), calls_in))
  } else {
    character()
  }
}

fn_bodies <- Filter(function(e) {
  is.call(e) && identical(e[[1]], as.name("<-")) &&
    is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))
}, as.list(exprs))
helper_names <- vapply(fn_bodies, function(e) as.character(e[[2]]), "")
uses_exit <- vapply(fn_bodies,
  function(e) "exit_file" %in% calls_in(e[[3]]), logical(1))

expect_true(length(fn_bodies) > 0, info = "_setup.R defines helpers")
expect_identical(helper_names[uses_exit], character(),
  info = "no _setup.R helper calls exit_file(), which is a no-op there")

source("_setup.R")
for (h in c("skip", "skip_if_not_installed", "skip_if_source_not_available",
            "skip_if_no_backend", "skip_if_not_ci")) {
  expect_false(exists(h, envir = globalenv(), inherits = FALSE),
    info = sprintf("no-op helper %s() is not defined", h))
}
