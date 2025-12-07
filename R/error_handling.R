#' @keywords internal
NULL

#' Handle errors with logging and user notification
#'
#' Wraps expression evaluation with error handling, logging, and user feedback.
#'
#' @param expr Expression to evaluate
#' @param error_title Character - title for user error message
#' @param show_user Logical - show error modal to user?
#' @param log_file Character - file to log errors (optional)
#' @param return_value Value to return if error occurs (default: NULL)
#'
#' @return Result of expr if successful, return_value if error
#' @export
#' @examples
#' \dontrun{
#' result <- handle_error({
#'   authenticate_user(username, password)
#' }, error_title = "Authentication Failed")
#' }
handle_error <- function(
  expr,
  error_title = "Error",
  show_user = TRUE,
  log_file = NULL,
  return_value = NULL) {

  tryCatch({
    expr
  }, error = function(e) {
    error_msg <- conditionMessage(e)

    # Log error for debugging
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    log_entry <- sprintf("[%s] ERROR - %s: %s\n", timestamp, error_title, error_msg)

    if (!is.null(log_file)) {
      tryCatch({
        cat(log_entry, file = log_file, append = TRUE)
      }, error = function(e2) {
        warning("Could not write to log file: ", log_file)
      })
    }

    # Show user-friendly message if needed
    if (show_user) {
      # Don't show technical details to user
      user_message <- if (error_title == "Error") {
        "An unexpected error occurred. Please contact support."
      } else {
        paste("Error:", error_title)
      }

      shinyalert::shinyalert(
        title = error_title,
        text = user_message,
        type = "error"
      )
    }

    # Return default value
    invisible(return_value)
  })
}

#' Validate and notify
#'
#' Checks a condition and shows notification if false.
#'
#' @param condition Logical - condition to check
#' @param message Character - message to show if condition is FALSE
#' @param type Character - notification type ("message", "warning", "error")
#'
#' @return Invisibly returns the condition
#' @export
notify_if_invalid <- function(condition, message, type = "warning") {
  if (!condition) {
    shinyalert::shinyalert(
      title = stringr::str_to_title(type),
      text = message,
      type = type
    )
  }
  invisible(condition)
}

#' Safe reactive expression evaluation
#'
#' Wraps reactive expression with error handling
#' to prevent app crashes from reactive errors.
#'
#' @param expr Expression to evaluate reactively
#' @param on_error Function to call on error (or value to return)
#' @param on_empty Function or value for empty results
#'
#' @return Reactive expression result or error value
#' @export
safe_reactive <- function(expr, on_error = NULL, on_empty = NULL) {
  reactive({
    tryCatch({
      result <- expr()

      # Check if result is empty
      if (length(result) == 0) {
        if (is.function(on_empty)) {
          on_empty()
        } else {
          on_empty
        }
      } else {
        result
      }
    }, error = function(e) {
      if (is.function(on_error)) {
        on_error(e)
      } else {
        on_error
      }
    })
  })
}

#' Create standardized error response
#'
#' Returns a consistent error response structure.
#'
#' @param message Character - error message
#' @param code Character - error code (optional)
#'
#' @return List with success=FALSE and message
#' @export
error_response <- function(message, code = NULL) {
  list(
    success = FALSE,
    message = message,
    code = code,
    timestamp = Sys.time()
  )
}

#' Create standardized success response
#'
#' Returns a consistent success response structure.
#'
#' @param message Character - success message
#' @param data List - data to return
#'
#' @return List with success=TRUE and message
#' @export
success_response <- function(message = "Success", data = NULL) {
  list(
    success = TRUE,
    message = message,
    data = data,
    timestamp = Sys.time()
  )
}
