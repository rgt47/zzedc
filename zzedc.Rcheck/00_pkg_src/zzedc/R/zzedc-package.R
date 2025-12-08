#' ZZedc: Electronic Data Capture System for Clinical Trials
#'
#' @description
#' The zzedc package provides a comprehensive Shiny application for electronic
#' data capture (EDC) in clinical trials. It features secure authentication,
#' data entry forms, quality control reports, visualization tools, and export
#' capabilities, all built with modern bslib components.
#'
#' @details
#' ## Key Features
#' 
#' **Authentication & Security:**
#' - Role-based user authentication
#' - Encrypted data storage
#' - Audit trail capabilities
#' 
#' **Data Entry:**
#' - Customizable data entry forms
#' - Real-time validation
#' - Progress tracking
#' 
#' **Reporting:**
#' - Basic data summaries
#' - Data quality reports
#' - Statistical analysis reports
#' 
#' **Data Management:**
#' - Interactive data explorer
#' - Missing data analysis
#' - Data visualization tools
#' 
#' **Export & Integration:**
#' - Multiple export formats (CSV, Excel, JSON, PDF, HTML)
#' - Batch export capabilities
#' - Export templates and scheduling
#' 
#' ## Getting Started
#' 
#' To launch the EDC application:
#' ```r
#' library(zzedc)
#' launch_zzedc()
#' ```
#' 
#' The application will open in your default web browser with a modern,
#' responsive interface powered by Bootstrap 5.
#' 
#' ## Default Credentials
#' 
#' For testing purposes, the following credentials are available:
#' - Username: `ww`, Password: `pw`
#' - Username: `q`, Password: `pw`  
#' - Username: `w`, Password: `pw`
#' 
#' **Note:** Change these credentials before deploying to production.
#' 
#' @section Package Dependencies:
#' This package builds on several excellent R packages including shiny, bslib,
#' DT, ggplot2, plotly, and others to provide a comprehensive EDC solution.
#' 
#' @author Ronald G. Thomas
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom shiny runApp
## usethis namespace: end
NULL
