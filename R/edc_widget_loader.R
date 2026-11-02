#' Generic loader for data-dictionary-attached custom field widgets
#'
#' A `designer_fields` row's `widget_file` (set from the
#' `Data_Dictionary` sheet's `widget` column -- see
#' [setup_zzedc_from_gsheets()]) names a widget, e.g.
#' `"coauthor_builder"`, to attach to that field: a small trigger UI
#' spliced in right after the field's own rendered block, backed by
#' a real Shiny module (so two attachments, even of the same widget
#' on different fields, never collide). The co-author builder
#' (`inst/app/widgets/coauthor_builder.R`) is the first such widget
#' and the reference implementation of this contract.
#'
#' A widget file must define exactly two functions when sourced:
#' `widget_ui(id)`, returning the trigger UI for a given Shiny
#' module namespace id, and `widget_server(id, db_pool,
#' parent_session, target_field)`, a [shiny::moduleServer()] call
#' setting up that widget instance's own observers/renderers.
#' `parent_session` is the EDC tab's own top-level session (not the
#' module's own child session) -- a widget writes into its
#' `target_field` (the field it's attached to) via
#' `shiny::updateTextInput(parent_session, target_field, ...)`,
#' since that field lives outside the module's namespace entirely.
#'
#' @name edc_widget_loader
#' @keywords internal
NULL


#' Resolve a data-dictionary widget name to its source file
#'
#' A `widget_file` value names a widget, not a path -- the actual
#' file always lives under this package's own `inst/app/widgets/`.
#' Treating the data dictionary's value as a bare name rather than a
#' path, and validating it strictly, rules out a sheet author (anyone
#' with edit access to the Google Sheet, not necessarily anyone with
#' access to this codebase) reaching a file outside that directory.
#'
#' @param name A widget name, e.g. `"coauthor_builder"`.
#' @return The widget file's path, or `NULL` if `name` is blank, is
#'   not a bare `[a-zA-Z0-9_]+` identifier, or no such file exists
#'   under `inst/app/widgets/`.
#' @keywords internal
resolve_widget_module <- function(name) {
  if (is.null(name) || !nzchar(trimws(name %||% ""))) return(NULL)
  if (!grepl("^[a-zA-Z0-9_]+$", name)) return(NULL)
  path <- system.file("app", "widgets", paste0(name, ".R"), package = "zzedc")
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  path
}


#' Source a widget file into a fresh, isolated environment
#'
#' Each widget gets its own environment (rather than being sourced
#' into the global/package namespace) so that two different widget
#' files can both define functions with the fixed names every widget
#' file is expected to define (`widget_ui()`/`widget_server()`)
#' without colliding with each other.
#'
#' @param path A widget file's path, as returned by
#'   [resolve_widget_module()].
#' @return An environment with `widget_ui` and `widget_server`
#'   functions, or `NULL` if the file doesn't define both as
#'   functions.
#' @keywords internal
load_widget_module <- function(path) {
  env <- new.env(parent = globalenv())
  sys.source(path, envir = env)
  if (!is.function(env$widget_ui) || !is.function(env$widget_server)) {
    return(NULL)
  }
  env
}


#' A stable Shiny module namespace id for one widget attachment
#'
#' Deterministic in `field_code` so the same id is used both when a
#' widget's server is registered (once, at session start, for every
#' attachment across every form -- see [all_widget_attachments()])
#' and when its trigger UI is spliced into whichever form is
#' currently being rendered.
#'
#' @param field_code The field the widget is attached to.
#' @return A single string.
#' @keywords internal
widget_module_id <- function(field_code) {
  paste0("widget_", field_code)
}


#' Every (form, field, widget) attachment across all forms
#'
#' Scans every form's field metadata for a non-blank `widget_file`,
#' so the EDC tab can register each attached widget's server-side
#' logic once per session, regardless of which form is currently
#' selected -- a widget's server-side observers must exist before
#' its field could ever be shown, since
#' [shiny::moduleServer()] can only be called once per namespace id,
#' not re-called every time a form is selected.
#'
#' @param conn A DBI connection (or pool object).
#' @return A data frame with columns `crf_id`, `crf_code`,
#'   `field_code`, `widget_file`; zero rows if no form has any
#'   widget-attached field.
#' @keywords internal
all_widget_attachments <- function(conn) {
  DBI::dbGetQuery(conn, "
    SELECT df.design_id AS crf_id, cd.crf_code, df.field_code, df.widget_file
    FROM designer_fields df
    JOIN crf_definitions cd ON cd.crf_id = df.design_id
    WHERE df.widget_file IS NOT NULL AND df.widget_file != ''
  ")
}
