#' Profiling Wrappers for Common Operations
#'
#' Provides profiled versions of common operations that may be bottlenecks.
#' These functions wrap standard library calls with timing instrumentation.
#'
#' @keywords internal
#' @name profiling_wrappers
NULL


#' Profiled JSON Parse
#'
#' Wrapper around jsonlite::fromJSON with profiling instrumentation.
#'
#' @param txt JSON string or file path
#' @param ... Additional arguments passed to jsonlite::fromJSON
#'
#' @return Parsed R object
#'
#' @examples
#' \dontrun{
#'   profiling_enable()
#'   data <- profiled_json_parse('{"name": "test", "value": 123}')
#'   profiling_report()
#' }
#'
#' @keywords internal
#' @export
profiled_json_parse <- function(txt, ...) {
  size <- if (is.character(txt)) nchar(txt[1]) else NA

  with_profiling("json", "parse", {
    jsonlite::fromJSON(txt, ...)
  }, metadata = list(size_chars = size))
}


#' Profiled JSON Serialize
#'
#' Wrapper around jsonlite::toJSON with profiling instrumentation.
#'
#' @param x R object to serialize
#' @param ... Additional arguments passed to jsonlite::toJSON
#'
#' @return JSON string
#'
#' @keywords internal
#' @export
profiled_json_serialize <- function(x, ...) {
  with_profiling("json", "serialize", {
    jsonlite::toJSON(x, ...)
  }, metadata = list(class = class(x)[1]))
}


#' Profiled Data Table Read
#'
#' Wrapper around data.table::fread with profiling instrumentation.
#'
#' @param input File path or URL
#' @param ... Additional arguments passed to data.table::fread
#'
#' @return data.table object
#'
#' @keywords internal
#' @export
profiled_fread <- function(input, ...) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("data.table package required")
  }

  with_profiling("io", "fread", {
    data.table::fread(input, ...)
  }, metadata = list(input = basename(as.character(input))))
}


#' Profiled Data Table Write
#'
#' Wrapper around data.table::fwrite with profiling instrumentation.
#'
#' @param x data.table or data.frame to write
#' @param file Output file path
#' @param ... Additional arguments passed to data.table::fwrite
#'
#' @return Invisible NULL
#'
#' @keywords internal
#' @export
profiled_fwrite <- function(x, file, ...) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("data.table package required")
  }

  with_profiling("io", "fwrite", {
    data.table::fwrite(x, file, ...)
  }, metadata = list(rows = nrow(x), cols = ncol(x), file = basename(file)))
}


#' Profiled HTTP Request
#'
#' Wrapper around httr requests with profiling instrumentation.
#'
#' @param method HTTP method ("GET", "POST", etc.)
#' @param url Request URL
#' @param ... Additional arguments passed to httr verb function
#'
#' @return httr response object
#'
#' @keywords internal
#' @export
profiled_http <- function(method, url, ...) {
  if (!requireNamespace("httr", quietly = TRUE)) {
    stop("httr package required")
  }

  verb_fn <- switch(
    toupper(method),
    GET = httr::GET,
    POST = httr::POST,
    PUT = httr::PUT,
    DELETE = httr::DELETE,
    PATCH = httr::PATCH,
    stop("Unknown HTTP method: ", method)
  )

  # Extract host for profiling label
  host <- tryCatch(
    httr::parse_url(url)$hostname,
    error = function(e) "unknown"
  )

  with_profiling("http", paste0(method, ":", host), {
    verb_fn(url, ...)
  }, metadata = list(url = url))
}


#' Profiled Google Sheets Read
#'
#' Wrapper around googlesheets4::read_sheet with profiling instrumentation.
#'
#' @param ss Spreadsheet identifier
#' @param sheet Sheet name or index
#' @param ... Additional arguments passed to read_sheet
#'
#' @return tibble with sheet data
#'
#' @keywords internal
#' @export
profiled_gsheet_read <- function(ss, sheet = NULL, ...) {
  if (!requireNamespace("googlesheets4", quietly = TRUE)) {
    stop("googlesheets4 package required")
  }

  sheet_label <- if (is.null(sheet)) "default" else as.character(sheet)

  with_profiling("gsheets", paste0("read:", sheet_label), {
    googlesheets4::read_sheet(ss, sheet = sheet, ...)
  }, metadata = list(sheet = sheet_label))
}


#' Profiled Google Sheets Write
#'
#' Wrapper around googlesheets4 write operations with profiling.
#'
#' @param data Data frame to write
#' @param ss Spreadsheet identifier
#' @param sheet Sheet name
#' @param ... Additional arguments
#'
#' @return Result from write operation
#'
#' @keywords internal
#' @export
profiled_gsheet_write <- function(data, ss, sheet = NULL, ...) {
  if (!requireNamespace("googlesheets4", quietly = TRUE)) {
    stop("googlesheets4 package required")
  }

  sheet_label <- if (is.null(sheet)) "default" else as.character(sheet)

  with_profiling("gsheets", paste0("write:", sheet_label), {
    googlesheets4::sheet_write(data, ss, sheet = sheet, ...)
  }, metadata = list(sheet = sheet_label, rows = nrow(data)))
}


#' Create Profiled Function Wrapper
#'
#' Factory function to create a profiled version of any function.
#'
#' @param fn Function to wrap
#' @param category Profiling category
#' @param operation Operation name
#'
#' @return Wrapped function with profiling
#'
#' @examples
#' \dontrun{
#'   profiled_mean <- make_profiled(mean, "stats", "mean")
#'   result <- profiled_mean(1:1000000)
#' }
#'
#' @keywords internal
#' @export
make_profiled <- function(fn, category, operation) {
  force(fn)
  force(category)
  force(operation)

  function(...) {
    with_profiling(category, operation, {
      fn(...)
    })
  }
}


#' Profile a Shiny Reactive Expression
#'
#' Wraps a Shiny reactive expression with profiling.
#'
#' @param expr Reactive expression
#' @param label Label for profiling
#'
#' @return Profiled reactive expression
#'
#' @examples
#' \dontrun{
#'   filtered_data <- profiled_reactive("filter_subjects", reactive({
#'     subjects |> filter(status == "Active")
#'   }))
#' }
#'
#' @keywords internal
#' @export
profiled_reactive <- function(label, expr) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("shiny package required")
  }

  shiny::reactive({
    with_profiling("shiny", paste0("reactive:", label), {
      expr()
    })
  })
}


#' Profile a Shiny Observer
#'
#' Wraps a Shiny observer with profiling.
#'
#' @param label Label for profiling
#' @param expr Observer expression
#' @param ... Additional arguments passed to observe
#'
#' @return Observer object
#'
#' @keywords internal
#' @export
profiled_observe <- function(label, expr, ...) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("shiny package required")
  }

  shiny::observe({
    with_profiling("shiny", paste0("observe:", label), {
      expr
    })
  }, ...)
}
