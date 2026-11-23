library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# Test: Quality Dashboard Module UI
#
# This file used to hold 15 empty blocks that each called a skip()
# helper which was a silent no-op, so nothing here ever ran. These are
# structural checks of the rendered UI (ids, output bindings, the
# UI/server output contract); the server is not exercised.

ui <- zzedc:::quality_dashboard_ui("qd")
html <- as.character(htmltools::renderTags(ui)$html)

expect_inherits(ui, "shiny.tag", info = "UI builds without error")

ids <- regmatches(html, gregexpr('id="[^"]+"', html))[[1]]
ids <- sub('^id="(.*)"$', "\\1", ids)
expect_true(length(ids) > 0, info = "UI has element ids")
expect_true(all(startsWith(ids, "qd-")),
  info = "every element id is namespaced by the module id")

# Each output the server assigns must exist in the UI with a Shiny
# output binding; an element with the right id but no binding class
# is never filled in by the server.
server_src <- paste(deparse(zzedc:::quality_dashboard_server), collapse = "\n")
server_outputs <- unique(sub("^output\\$", "",
  regmatches(server_src, gregexpr("output\\$[A-Za-z_]+", server_src))[[1]]))
expect_true(length(server_outputs) >= 8,
  info = "server output names were found")

has_binding <- function(out_id, cls) {
  pattern <- sprintf('<[^>]*id="qd-%s"[^>]*class="[^"]*%s', out_id, cls)
  pattern2 <- sprintf('<[^>]*class="[^"]*%s[^"]*"[^>]*id="qd-%s"', cls, out_id)
  grepl(pattern, html) || grepl(pattern2, html)
}
binding_class <- "(shiny-(text|html|plot|report|bound)-output|plotly|datatables)"
for (o in server_outputs) {
  expect_true(paste0("qd-", o) %in% ids,
    info = sprintf("server output '%s' has a UI element", o))
  expect_true(has_binding(o, binding_class),
    info = sprintf("UI element for '%s' has an output binding", o))
}

expect_true(grepl("Loading QC status", html, fixed = TRUE),
  info = "QC flags placeholder shown until the server renders")
for (h in c("Completeness by Form", "Data Entry Timeline",
            "Missing Data Summary", "Quality Control Flags")) {
  expect_true(grepl(h, html, fixed = TRUE),
    info = sprintf("card header '%s' present", h))
}
