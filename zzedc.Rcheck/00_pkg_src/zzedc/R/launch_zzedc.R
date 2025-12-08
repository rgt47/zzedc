#' Launch the ZZedc Shiny Application
#'
#' This function launches the interactive 'Shiny' application for electronic
#' data capture (EDC) in clinical trials.
#'
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}
#' @param launch.browser Logical, whether to launch the app in browser. 
#'   Default is \code{TRUE}.
#' @param host Character string of IP address to listen on. Default is "127.0.0.1".
#' @param port Integer specifying the port to listen on. Default is \code{NULL}
#'   (random port).
#'
#' @return No return value, launches the Shiny application
#' 
#' @details 
#' The application provides comprehensive electronic data capture for clinical 
#' trials with the following features:
#' \itemize{
#'   \item Secure user authentication with role-based access
#'   \item Data entry forms with validation and quality control
#'   \item Comprehensive reporting system (basic, quality, statistical)
#'   \item Advanced data exploration and visualization tools
#'   \item Flexible export capabilities with multiple formats
#'   \item Modern responsive design using Bootstrap 5 via bslib
#' }
#'
#' @examples
#' \dontrun{
#' # Launch the application
#' launch_zzedc()
#' 
#' # Launch on specific port
#' launch_zzedc(port = 3838)
#' 
#' # Launch without opening browser
#' launch_zzedc(launch.browser = FALSE)
#' }
#'
#' @export
#' @importFrom shiny runApp
launch_zzedc <- function(..., launch.browser = TRUE, host = "127.0.0.1", port = NULL) {
  
  # Ensure required directories exist
  if (!dir.exists("data")) {
    dir.create("data", showWarnings = FALSE)
  }
  
  if (!dir.exists("credentials")) {
    dir.create("credentials", showWarnings = FALSE) 
  }
  
  # Package loading handled in global.R when app starts
  
  # Run the app from the current directory
  shiny::runApp(
    appDir = ".",
    launch.browser = launch.browser,
    host = host,
    port = port,
    ...
  )
}
