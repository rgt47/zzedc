library(tinytest)

# Regression tests for R/edc_widget_loader.R, the generic loader for
# data-dictionary-attached custom field widgets (e.g. the co-author
# builder).

local({
  # resolve_widget_module()
  path <- zzedc:::resolve_widget_module("coauthor_builder")
  expect_true(is.character(path) && file.exists(path),
              info = "the package's own shipped widget resolves to a real file")
  expect_true(grepl("widgets", path, fixed = TRUE))

  expect_null(zzedc:::resolve_widget_module(NULL))
  expect_null(zzedc:::resolve_widget_module(""))
  expect_null(zzedc:::resolve_widget_module("   "))
  expect_null(zzedc:::resolve_widget_module("nonexistent_widget_xyz"),
              info = "a syntactically valid but unshipped name resolves to nothing")

  # Path-traversal / injection attempts: a widget name is a bare
  # identifier, never a path. Each of these must be rejected outright
  # by the name-validation regex, not passed through to file.exists().
  expect_null(zzedc:::resolve_widget_module("../../etc/passwd"))
  expect_null(zzedc:::resolve_widget_module("foo/bar"))
  expect_null(zzedc:::resolve_widget_module("foo.R"))
  expect_null(zzedc:::resolve_widget_module("foo bar"))
  expect_null(zzedc:::resolve_widget_module("foo;rm -rf"))
})

local({
  # load_widget_module()
  path <- zzedc:::resolve_widget_module("coauthor_builder")
  mod <- zzedc:::load_widget_module(path)
  expect_true(is.environment(mod))
  expect_true(is.function(mod$widget_ui))
  expect_true(is.function(mod$widget_server))

  # Sourced into its own environment, not the global/package one --
  # these names must not leak out.
  expect_false(exists("widget_ui", envir = globalenv(), inherits = FALSE))
})

local({
  # load_widget_module() on a file that doesn't define the required
  # contract: NULL, not a half-usable environment or an error.
  bad_file <- tempfile(fileext = ".R")
  writeLines("not_the_right_function_name <- function() NULL", bad_file)
  expect_null(zzedc:::load_widget_module(bad_file))
})

local({
  # widget_module_id()
  expect_equal(zzedc:::widget_module_id("co_authors"), "widget_co_authors")
  expect_true(
    zzedc:::widget_module_id("co_authors") != zzedc:::widget_module_id("notes"),
    info = "distinct fields never collide on the same module id"
  )
})

if (requireNamespace("RSQLite", quietly = TRUE)) {

  .make_widget_fixture <- function() {
    db_path <- tempfile(fileext = ".db")
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    DBI::dbExecute(conn, "
      CREATE TABLE crf_definitions (
        crf_id INTEGER PRIMARY KEY AUTOINCREMENT,
        crf_code TEXT UNIQUE NOT NULL,
        crf_name TEXT NOT NULL,
        created_by TEXT NOT NULL
      )
    ")
    DBI::dbExecute(conn, "
      CREATE TABLE designer_fields (
        field_id INTEGER PRIMARY KEY AUTOINCREMENT,
        design_id INTEGER NOT NULL,
        field_code TEXT NOT NULL,
        field_label TEXT NOT NULL,
        field_type TEXT NOT NULL,
        field_row INTEGER DEFAULT 1,
        field_column INTEGER DEFAULT 1,
        is_required INTEGER DEFAULT 0,
        placeholder TEXT,
        help_text TEXT,
        default_value TEXT,
        widget_file TEXT,
        help_detail TEXT
      )
    ")
    DBI::dbExecute(conn,
      "INSERT INTO crf_definitions (crf_code, crf_name, created_by) VALUES (?, ?, ?)",
      params = list("MANUSCRIPTS", "MANUSCRIPTS Form", "test"))
    DBI::dbExecute(conn,
      "INSERT INTO crf_definitions (crf_code, crf_name, created_by) VALUES (?, ?, ?)",
      params = list("COURSES", "COURSES Form", "test"))
    DBI::dbExecute(conn, "
      INSERT INTO designer_fields
        (design_id, field_code, field_label, field_type, widget_file)
      VALUES
        (1, 'tracking_id', 'Tracking ID', 'TEXT', NULL),
        (1, 'co_authors', 'Co-authors', 'TEXT', 'coauthor_builder'),
        (2, 'student_count', 'Student Count', 'NUMBER', '')
    ")
    conn
  }

  local({
    conn <- .make_widget_fixture()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    attachments <- zzedc:::all_widget_attachments(conn)
    expect_equal(nrow(attachments), 1,
                 info = "a NULL or blank widget_file is never an attachment")
    expect_equal(attachments$field_code[1], "co_authors")
    expect_equal(attachments$crf_code[1], "MANUSCRIPTS")
    expect_equal(attachments$widget_file[1], "coauthor_builder")
  })

} else {
  exit_file("RSQLite not installed")
}
