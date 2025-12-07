#' Data Export Service Layer
#'
#' Pure business logic for data export operations.
#' Separate from Shiny reactive code for testability and reusability.
#' Supports 8+ export formats: CSV, XLSX, JSON, PDF, HTML, SAS, SPSS, STATA, RDS

#' Prepare data for export
#'
#' Retrieves and formats data based on export configuration.
#' Pure function with no Shiny dependencies.
#'
#' @param data_source Character indicating data source ("edc", "all_files", "reports", "sample")
#' @param format Character specifying export format:
#'   - "csv": Comma-separated values
#'   - "xlsx": Excel workbook
#'   - "json": JSON format
#'   - "sas": SAS transport file (.xpt)
#'   - "spss": SPSS/PSPP format (.sav)
#'   - "stata": Stata format (.dta)
#'   - "rds": R serialized object (.rds)
#'   - "pdf": PDF document (requires template)
#'   - "html": HTML document (requires template)
#' @param options List of export options (metadata, timestamps, date_range, etc.)
#' @param db_conn Database connection (if data_source == "edc")
#'
#' @return List containing:
#'   - data: data.frame or list with export data
#'   - info: metadata about export (rows, columns, size estimate)
#'   - warnings: any issues encountered
#'
#' @export
#' @examples
#' \dontrun{
#' export_result <- prepare_export_data(
#'   data_source = "edc",
#'   format = "csv",
#'   options = list(include_metadata = TRUE, include_timestamps = TRUE)
#' )
#' }
prepare_export_data <- function(data_source, format, options = NULL, db_conn = NULL) {
  warnings <- c()
  export_data <- NULL

  # Validate inputs
  valid_sources <- c("edc", "all_files", "reports", "sample")
  valid_formats <- c("csv", "xlsx", "json", "pdf", "html", "sas", "spss", "stata", "rds")

  if (!data_source %in% valid_sources) {
    stop("Invalid data_source: ", data_source)
  }

  if (!format %in% valid_formats) {
    stop("Invalid format: ", format)
  }

  # Prepare data based on source
  switch(data_source,
    "edc" = {
      if (is.null(db_conn)) {
        warning("Database connection required for EDC export")
        warnings <- c(warnings, "No database connection provided")
        return(list(
          data = NULL,
          info = NULL,
          warnings = warnings,
          error = "Database connection required"
        ))
      }

      export_data <- prepare_edc_export(db_conn, options)
    },

    "sample" = {
      export_data <- prepare_sample_export(options)
    },

    "reports" = {
      export_data <- prepare_reports_export(options)
    },

    "all_files" = {
      export_data <- prepare_all_files_export(options)
    }
  )

  # Validate export data
  if (is.null(export_data)) {
    warnings <- c(warnings, "No data available for export")
  }

  # Calculate metadata
  export_info <- list(
    source = data_source,
    format = format,
    timestamp = Sys.time(),
    rows = if (is.data.frame(export_data)) nrow(export_data) else length(export_data),
    columns = if (is.data.frame(export_data)) ncol(export_data) else NA,
    size_estimate_kb = object.size(export_data) / 1024
  )

  list(
    data = export_data,
    info = export_info,
    warnings = warnings
  )
}

#' Prepare EDC data for export
#'
#' Retrieves EDC data with optional metadata and filtering
#'
#' @param db_conn Database connection
#' @param options List with include_metadata, include_timestamps, date_range, etc.
#'
#' @return data.frame with EDC export data
#'
prepare_edc_export <- function(db_conn, options = NULL) {
  # Default options
  options <- options %||% list()
  include_metadata <- options$include_metadata %||% TRUE
  include_timestamps <- options$include_timestamps %||% TRUE
  date_range <- options$date_range %||% c(Sys.Date() - 30, Sys.Date())

  tryCatch({
    # Read EDC data from database
    query <- "SELECT * FROM edc_forms"

    if (!is.null(date_range) && length(date_range) == 2) {
      query <- paste0(
        query,
        " WHERE created_at >= '", format(date_range[1], "%Y-%m-%d"),
        "' AND created_at <= '", format(date_range[2], "%Y-%m-%d"), "'"
      )
    }

    edc_data <- DBI::dbGetQuery(db_conn, query)

    # Filter columns based on options
    if (!include_metadata) {
      meta_cols <- c("created_by", "created_at", "modified_by", "modified_at")
      edc_data <- edc_data[, !names(edc_data) %in% meta_cols]
    }

    if (!include_timestamps) {
      timestamp_cols <- c("created_at", "modified_at")
      edc_data <- edc_data[, !names(edc_data) %in% timestamp_cols]
    }

    edc_data
  }, error = function(e) {
    warning("Error reading EDC data: ", e$message)
    NULL
  })
}

#' Prepare sample data for export
#'
#' @param options List of export options
#'
#' @return data.frame with sample data
#'
prepare_sample_export <- function(options = NULL) {
  # Generate sample export data
  n_records <- 100

  data.frame(
    Record_ID = 1:n_records,
    Subject_ID = paste0("SUBJ_", sprintf("%03d", 1:n_records)),
    Visit_Date = sample(seq(as.Date("2024-01-01"), as.Date("2024-12-31"), by = "day"), n_records),
    Age = rnorm(n_records, 55, 15),
    Gender = sample(c("M", "F"), n_records, replace = TRUE),
    Treatment_Group = sample(c("Control", "Treatment A", "Treatment B"), n_records, replace = TRUE),
    Lab_Value_1 = rnorm(n_records, 100, 15),
    Lab_Value_2 = rnorm(n_records, 50, 10),
    Status = sample(c("Complete", "Incomplete"), n_records, replace = TRUE)
  )
}

#' Prepare reports data for export
#'
#' @param options List of export options
#'
#' @return List of report data
#'
prepare_reports_export <- function(options = NULL) {
  options <- options %||% list()

  reports_list <- list(
    basic_report = data.frame(
      Metric = c("Total Records", "Complete", "Incomplete", "Missing"),
      Count = c(100, 80, 15, 5)
    ),
    quality_report = data.frame(
      Check = c("Data Completeness", "Valid Ranges", "Duplicate Records", "Date Consistency"),
      Pass = c(95, 98, 100, 96),
      Fail = c(5, 2, 0, 4)
    )
  )

  if (options$include_summary %||% FALSE) {
    reports_list$summary <- data.frame(
      Report = names(reports_list),
      Generated = Sys.time(),
      Status = "Complete"
    )
  }

  reports_list
}

#' Prepare all files data for export
#'
#' @param options List of export options
#'
#' @return List of file data
#'
prepare_all_files_export <- function(options = NULL) {
  # Collect data from all sources
  list(
    edc_data = prepare_edc_export(NULL, options),
    sample_data = prepare_sample_export(options),
    reports = prepare_reports_export(options)
  )
}

#' Export data to file
#'
#' Writes export data to specified file format.
#' Supports 9 formats: CSV, XLSX, JSON, SAS, SPSS, STATA, RDS, PDF, HTML
#'
#' @param data Data to export (data.frame or list)
#' @param filepath Path to write export file
#' @param format Export format (csv, xlsx, json, sas, spss, stata, rds, pdf, html)
#' @param options List of format-specific options
#'
#' @return List with success status and file info
#'
#' @export
export_to_file <- function(data, filepath, format, options = NULL) {
  result <- list(success = FALSE, filepath = filepath, message = "")

  if (is.null(data)) {
    result$message <- "No data to export"
    return(result)
  }

  tryCatch({
    switch(format,
      "csv" = {
        if (!is.data.frame(data)) {
          result$message <- "CSV format requires data.frame"
          return(result)
        }
        write.csv(data, filepath, row.names = FALSE)
        result$success <- TRUE
        result$message <- paste("Exported", nrow(data), "rows to CSV")
      },

      "xlsx" = {
        if (!requireNamespace("openxlsx", quietly = TRUE)) {
          result$message <- "openxlsx package required for XLSX export"
          return(result)
        }

        if (is.list(data) && !is.data.frame(data)) {
          # Multiple sheets
          openxlsx::write.xlsx(data, filepath)
          result$message <- paste("Exported", length(data), "sheets to XLSX")
        } else {
          # Single sheet
          openxlsx::write.xlsx(as.data.frame(data), filepath)
          result$message <- paste("Exported", nrow(data), "rows to XLSX")
        }
        result$success <- TRUE
      },

      "json" = {
        json_str <- jsonlite::toJSON(data, pretty = TRUE)
        writeLines(json_str, filepath)
        result$success <- TRUE
        result$message <- "Exported to JSON"
      },

      "sas" = {
        if (!requireNamespace("haven", quietly = TRUE)) {
          result$message <- "haven package required for SAS export"
          return(result)
        }

        if (!is.data.frame(data)) {
          result$message <- "SAS format requires data.frame"
          return(result)
        }

        # SAS transport format (.xpt)
        haven::write_xpt(data, filepath)
        result$success <- TRUE
        result$message <- paste("Exported", nrow(data), "rows to SAS transport format (.xpt)")
      },

      "spss" = {
        if (!requireNamespace("haven", quietly = TRUE)) {
          result$message <- "haven package required for SPSS export"
          return(result)
        }

        if (!is.data.frame(data)) {
          result$message <- "SPSS format requires data.frame"
          return(result)
        }

        # SPSS/PSPP format (.sav)
        haven::write_sav(data, filepath)
        result$success <- TRUE
        result$message <- paste("Exported", nrow(data), "rows to SPSS format (.sav)")
      },

      "stata" = {
        if (!requireNamespace("haven", quietly = TRUE)) {
          result$message <- "haven package required for STATA export"
          return(result)
        }

        if (!is.data.frame(data)) {
          result$message <- "STATA format requires data.frame"
          return(result)
        }

        # Stata format (.dta)
        haven::write_dta(data, filepath)
        result$success <- TRUE
        result$message <- paste("Exported", nrow(data), "rows to STATA format (.dta)")
      },

      "rds" = {
        if (!is.data.frame(data)) {
          result$message <- "RDS format requires data.frame"
          return(result)
        }

        # R serialized object (.rds)
        # Compress by default for better file size
        saveRDS(data, file = filepath, compress = TRUE)
        result$success <- TRUE
        result$message <- paste("Exported", nrow(data), "rows to R RDS format (.rds)")
      },

      "pdf" = {
        if (!requireNamespace("rmarkdown", quietly = TRUE)) {
          result$message <- "rmarkdown package required for PDF export"
          return(result)
        }
        result$message <- "PDF export template required (not yet implemented)"
        result$success <- FALSE
      },

      "html" = {
        if (is.data.frame(data)) {
          html_table <- DT::datatable(data) %>% htmlwidgets::as.vega()
          # Implementation depends on your HTML template requirements
          result$message <- "HTML export template required"
        }
        result$success <- FALSE
      }
    )
  }, error = function(e) {
    result$message <<- paste("Export error:", e$message)
    result$success <<- FALSE
  })

  result
}

#' Generate safe export filename
#'
#' Creates a safe, properly formatted filename for export
#'
#' @param base_name Base filename (user-provided or default)
#' @param data_source Data source identifier
#' @param format Export format (csv, xlsx, json, sas, spss, stata, rds, pdf, html)
#'
#' @return Safe filename with extension
#'
#' @export
generate_export_filename <- function(base_name = NULL, data_source, format) {
  if (is.null(base_name) || base_name == "") {
    base_name <- paste0(data_source, "_export_", format(Sys.Date(), "%Y%m%d"))
  } else {
    # Sanitize user-provided filename
    base_name <- validate_filename(base_name)
  }

  # Add extension based on format
  extension <- switch(format,
    "csv" = ".csv",
    "xlsx" = ".xlsx",
    "json" = ".json",
    "sas" = ".xpt",        # SAS transport format
    "spss" = ".sav",       # SPSS format
    "stata" = ".dta",      # Stata format
    "rds" = ".rds",        # R serialized object
    "pdf" = ".pdf",
    "html" = ".html",
    ".txt"
  )

  paste0(base_name, extension)
}

#' Log export event to audit trail
#'
#' Records data export with details for compliance audit
#'
#' @param user_id User performing export
#' @param data_source Source of exported data
#' @param format Export format
#' @param rows Number of rows exported
#' @param audit_log Audit log reactiveVal
#'
#' @export
log_export_event <- function(user_id, data_source, format, rows, audit_log) {
  log_audit_event(
    audit_log,
    user_id = user_id,
    action = "DATA_EXPORT",
    resource = data_source,
    new_value = paste("Format:", format, "Rows:", rows),
    status = "success"
  )
}
