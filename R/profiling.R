#' Performance Profiling Module
#'
#' Provides lightweight profiling hooks for identifying performance bottlenecks.
#' Can be enabled/disabled at runtime without code changes.
#'
#' @description
#' This module tracks execution time and call frequency for key operations:
#' - Database queries and connections
#' - Validation rule execution
#' - JSON parsing/serialization
#' - Shiny reactive computations
#'
#' @details
#' Profiling is disabled by default. Enable with:
#' ```r
#' profiling_enable()
#' ```
#'
#' View results with:
#' ```r
#' profiling_report()
#' ```
#'
#' @keywords internal
#' @name profiling
NULL

# Profiling state stored in package environment
.profiling_env <- new.env(parent = emptyenv())
.profiling_env$enabled <- FALSE
.profiling_env$data <- list()
.profiling_env$start_time <- NULL


#' Enable Profiling
#'
#' Enables performance profiling and resets collected data.
#'
#' @param categories Character vector of categories to profile.
#'   Default profiles all categories.
#'
#' @return Invisible TRUE
#'
#' @examples
#' \dontrun{
#'   profiling_enable()
#'   # ... run operations ...
#'   profiling_report()
#' }
#'
#' @export
profiling_enable <- function(categories = NULL) {
.profiling_env$enabled <- TRUE
  .profiling_env$data <- list()
  .profiling_env$start_time <- Sys.time()
  .profiling_env$categories <- categories

  message("Profiling enabled at ", format(.profiling_env$start_time))
  invisible(TRUE)
}


#' Disable Profiling
#'
#' Disables profiling. Collected data is retained until next enable.
#'
#' @return Invisible FALSE
#'
#'
#' @examples
#' # Turn the profiling subsystem off (e.g., before deploying
#' # to production).
#' profiling_disable()
#' @export
profiling_disable <- function() {
  .profiling_env$enabled <- FALSE
  message("Profiling disabled. Use profiling_report() to view results.")
  invisible(FALSE)
}


#' Check if Profiling is Enabled
#'
#' @return Logical TRUE if profiling is currently enabled
#'
#' @keywords internal
#' @export
profiling_is_enabled <- function() {
  .profiling_env$enabled
}


#' Record a Profiling Event
#'
#' Records timing data for a single operation. Called internally by
#' profiled functions.
#'
#' @param category Category name (e.g., "db", "validation", "json")
#' @param operation Specific operation name
#' @param duration_ms Duration in milliseconds
#' @param metadata Optional list of additional context
#'
#' @return Invisible NULL
#'
#' @keywords internal
profiling_record <- function(category, operation, duration_ms,
                             metadata = NULL) {
  if (!.profiling_env$enabled) {
    return(invisible(NULL))
  }

  # Check category filter
  if (!is.null(.profiling_env$categories)) {
    if (!(category %in% .profiling_env$categories)) {
      return(invisible(NULL))
    }
  }

  event <- list(
    timestamp = Sys.time(),
    category = category,
    operation = operation,
    duration_ms = duration_ms,
    metadata = metadata
  )

  .profiling_env$data <- c(.profiling_env$data, list(event))

  invisible(NULL)
}


#' Profile a Code Block
#'
#' Wraps code execution with timing measurement.
#'
#' @param category Category name
#' @param operation Operation name
#' @param expr Expression to evaluate
#' @param metadata Optional metadata list
#'
#' @return Result of evaluating expr
#'
#' @examples
#' \dontrun{
#'   result <- with_profiling("db", "query_subjects", {
#'     DBI::dbGetQuery(conn, "SELECT * FROM subjects")
#'   })
#' }
#'
#' @keywords internal
#' @export
with_profiling <- function(category, operation, expr, metadata = NULL) {
  if (!.profiling_env$enabled) {
    return(expr)
  }

  start <- Sys.time()
  result <- tryCatch(
    expr,
    error = function(e) {
      duration_ms <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
      profiling_record(category, operation, duration_ms,
                       c(metadata, list(error = e$message)))
      stop(e)
    }
  )
  end <- Sys.time()

  duration_ms <- as.numeric(difftime(end, start, units = "secs")) * 1000
  profiling_record(category, operation, duration_ms, metadata)

  result
}


#' Create a Profiling Timer
#'
#' Returns a function that, when called, records elapsed time since creation.
#' Useful for profiling across function boundaries.
#'
#' @param category Category name
#' @param operation Operation name
#' @param metadata Optional metadata list
#'
#' @return Function that stops the timer and records the event
#'
#' @examples
#' \dontrun{
#'   stop_timer <- profiling_start("validation", "check_all_rules")
#'   # ... do work ...
#'   stop_timer()  # Records elapsed time
#' }
#'
#' @keywords internal
#' @export
profiling_start <- function(category, operation, metadata = NULL) {
  if (!.profiling_env$enabled) {
    return(function(...) invisible(NULL))
  }

  start <- Sys.time()

  function(extra_metadata = NULL) {
    duration_ms <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
    combined_metadata <- c(metadata, extra_metadata)
    profiling_record(category, operation, duration_ms, combined_metadata)
    invisible(duration_ms)
  }
}


#' Get Raw Profiling Data
#'
#' Returns the raw list of profiling events.
#'
#' @return List of profiling event records
#'
#' @keywords internal
#' @export
profiling_data <- function() {
  .profiling_env$data
}


#' Generate Profiling Report
#'
#' Generates a summary report of profiling data.
#'
#' @param format Output format: "text" (default), "data.frame", or "list"
#' @param top_n Number of slowest operations to highlight (default 10)
#'
#' @return Formatted report (printed for "text", returned for others)
#'
#' @examples
#' \dontrun{
#'   profiling_enable()
#'   # ... run operations ...
#'   profiling_report()
#'
#'   # Get as data frame for further analysis
#'   df <- profiling_report(format = "data.frame")
#' }
#'
#' @export
profiling_report <- function(format = "text", top_n = 10) {
  data <- .profiling_env$data

  if (length(data) == 0) {
    if (format == "text") {
      message("No profiling data collected.")
      return(invisible(NULL))
    }
    return(data.frame())
  }

  # Convert to data frame
  df <- do.call(rbind, lapply(data, function(e) {
    data.frame(
      timestamp = e$timestamp,
      category = e$category,
      operation = e$operation,
      duration_ms = e$duration_ms,
      stringsAsFactors = FALSE
    )
  }))

  # Calculate summaries by category
  category_summary <- aggregate(
    duration_ms ~ category,
    data = df,
    FUN = function(x) {
      c(count = length(x),
        total_ms = sum(x),
        mean_ms = mean(x),
        max_ms = max(x),
        min_ms = min(x))
    }
  )
  category_summary <- do.call(data.frame, category_summary)
  names(category_summary) <- c("category", "count", "total_ms", "mean_ms",
                                "max_ms", "min_ms")

  # Calculate summaries by operation
  operation_summary <- aggregate(
    duration_ms ~ category + operation,
    data = df,
    FUN = function(x) {
      c(count = length(x),
        total_ms = sum(x),
        mean_ms = mean(x),
        max_ms = max(x))
    }
  )
  operation_summary <- do.call(data.frame, operation_summary)
  names(operation_summary) <- c("category", "operation", "count", "total_ms",
                                 "mean_ms", "max_ms")
  operation_summary <- operation_summary[order(-operation_summary$total_ms), ]

  if (format == "data.frame") {
    return(df)
  }

  if (format == "list") {
    return(list(
      events = df,
      by_category = category_summary,
      by_operation = operation_summary,
      start_time = .profiling_env$start_time,
      total_events = nrow(df),
      total_duration_ms = sum(df$duration_ms)
    ))
  }

  # Text format
  elapsed <- difftime(Sys.time(), .profiling_env$start_time, units = "secs")

  cat("\n")
  cat("=============================================================\n")
  cat("                   PROFILING REPORT\n")
  cat("=============================================================\n")
  cat(sprintf("Session start: %s\n", format(.profiling_env$start_time)))
  cat(sprintf("Elapsed time:  %.2f seconds\n", as.numeric(elapsed)))
  cat(sprintf("Total events:
  %d\n", nrow(df)))
  cat(sprintf("Total tracked: %.2f ms\n", sum(df$duration_ms)))
  cat("\n")

  cat("-------------------------------------------------------------\n")
  cat("SUMMARY BY CATEGORY\n")
  cat("-------------------------------------------------------------\n")
  cat(sprintf("%-15s %8s %12s %10s %10s\n",
              "Category", "Count", "Total (ms)", "Mean (ms)", "Max (ms)"))
  cat("-------------------------------------------------------------\n")
  for (i in seq_len(nrow(category_summary))) {
    row <- category_summary[i, ]
    cat(sprintf("%-15s %8d %12.2f %10.2f %10.2f\n",
                row$category, row$count, row$total_ms, row$mean_ms, row$max_ms))
  }
  cat("\n")

  cat("-------------------------------------------------------------\n")
  cat(sprintf("TOP %d OPERATIONS BY TOTAL TIME\n", min(top_n, nrow(operation_summary))))
  cat("-------------------------------------------------------------\n")
  cat(sprintf("%-12s %-25s %6s %10s %8s\n",
              "Category", "Operation", "Count", "Total", "Mean"))
  cat("-------------------------------------------------------------\n")
  top_ops <- head(operation_summary, top_n)
  for (i in seq_len(nrow(top_ops))) {
    row <- top_ops[i, ]
    op_name <- if (nchar(row$operation) > 25) {
      paste0(substr(row$operation, 1, 22), "...")
    } else {
      row$operation
    }
    cat(sprintf("%-12s %-25s %6d %10.2f %8.2f\n",
                row$category, op_name, row$count, row$total_ms, row$mean_ms))
  }
  cat("\n")

  # Identify potential bottlenecks
  cat("-------------------------------------------------------------\n")
  cat("POTENTIAL BOTTLENECKS\n")
  cat("-------------------------------------------------------------\n")

  # Operations with high max time (>100ms)
  slow_ops <- operation_summary[operation_summary$max_ms > 100, ]
  if (nrow(slow_ops) > 0) {
    cat("Slow operations (max > 100ms):\n")
    for (i in seq_len(min(5, nrow(slow_ops)))) {
      row <- slow_ops[i, ]
      cat(sprintf("  - %s/%s: max %.2f ms\n",
                  row$category, row$operation, row$max_ms))
    }
    cat("\n")
  }

  # High frequency operations (>100 calls)
  freq_ops <- operation_summary[operation_summary$count > 100, ]
  if (nrow(freq_ops) > 0) {
    cat("High frequency operations (>100 calls):\n")
    for (i in seq_len(min(5, nrow(freq_ops)))) {
      row <- freq_ops[i, ]
      cat(sprintf("  - %s/%s: %d calls, total %.2f ms\n",
                  row$category, row$operation, row$count, row$total_ms))
    }
    cat("\n")
  }

  cat("=============================================================\n")

  invisible(list(
    by_category = category_summary,
    by_operation = operation_summary
  ))
}


#' Reset Profiling Data
#'
#' Clears all collected profiling data without disabling profiling.
#'
#' @return Invisible NULL
#'
#' @keywords internal
#' @export
profiling_reset <- function() {
  .profiling_env$data <- list()
  .profiling_env$start_time <- Sys.time()
  message("Profiling data reset at ", format(.profiling_env$start_time))
  invisible(NULL)
}


#' Export Profiling Data to File
#'
#' Saves profiling data to a file for later analysis.
#'
#' @param file_path Path to output file (.rds or .csv)
#' @param format File format: "rds" (default) or "csv"
#'
#' @return Invisible file path
#'
#'
#' @examples
#' \dontrun{
#' # Emit collected profiling samples to a file for later analysis
#' # (e.g., with the `profvis` package).
#' profiling_export(output_path = tempfile(fileext = ".rds"))
#' }
#' @export
profiling_export <- function(file_path = NULL, format = "rds") {
  if (is.null(file_path)) {
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    ext <- if (format == "csv") ".csv" else ".rds"
    file_path <- paste0("profiling_", timestamp, ext)
  }

  report <- profiling_report(format = "list")

  if (format == "csv") {
    write.csv(report$events, file_path, row.names = FALSE)
  } else {
    saveRDS(report, file_path)
  }

  message("Profiling data exported to: ", file_path)
  invisible(file_path)
}
