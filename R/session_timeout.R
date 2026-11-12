#' @keywords internal
NULL

#' Initialize session timeout tracking
#'
#' Creates reactive values to track user activity and session state.
#'
#' @return List containing reactive objects for session management
#' @keywords internal
init_session_timeout <- function() {
  list(
    last_activity = reactiveVal(Sys.time()),
    session_active = reactiveVal(TRUE),
    timeout_warning_shown = reactiveVal(FALSE)
  )
}

#' Enable session timeout monitoring
#'
#' Should be called in server() function to activate timeout checking.
#' Monitors user inactivity and logs out after configured timeout period.
#'
#' @param session Shiny session object
#' @param user_input reactiveValues object containing user session state
#' @param timeout_config List with timeout_minutes (from config$auth$session_timeout_minutes)
#' @param on_timeout_callback Function to call when timeout occurs (default: logs out user)
#'
#' @keywords internal
enable_session_timeout <- function(session, user_input, timeout_config, on_timeout_callback = NULL) {
  timeout_minutes <- timeout_config$session_timeout_minutes %||% 30

  # Create session tracking
  session_tracker <- init_session_timeout()

  # Update activity on any input. This read `input`, which is not in
  # this function's scope; the session's own input is used instead.
  observe({
    reactive_inputs <- reactiveValuesToList(session$input)

    # Update last activity time
    session_tracker$last_activity(Sys.time())
    session_tracker$timeout_warning_shown(FALSE)  # Reset warning
  })

  # Check for timeout periodically (every minute)
  observe({
    invalidateLater(60000)  # Check every 60 seconds

    if (!user_input$authenticated) {
      return()  # Don't check if not authenticated
    }

    time_since_activity <- as.numeric(difftime(Sys.time(), session_tracker$last_activity(), units = "mins"))

    # Show warning at 80% of timeout
    warning_threshold <- timeout_minutes * 0.8
    if (time_since_activity > warning_threshold && !session_tracker$timeout_warning_shown()) {
      session_tracker$timeout_warning_shown(TRUE)

      shinyalert::shinyalert(
        title = "Session Timeout Warning",
        text = sprintf(
          "Your session will expire in %d minutes due to inactivity. Click OK to continue your session.",
          as.integer(timeout_minutes - time_since_activity)
        ),
        type = "warning",
        closeOnEsc = FALSE,
        closeOnClickOutside = FALSE
      )

      # Showing the warning is not user activity. It used to reset the
      # activity clock here, so every warning postponed the timeout and
      # an unattended session never expired; activity is now recorded
      # only by the input observer above.
      return()
    }

    # Force logout on timeout
    if (time_since_activity > timeout_minutes && user_input$authenticated) {
      session_tracker$session_active(FALSE)

      # Call custom callback or default logout
      if (!is.null(on_timeout_callback)) {
        on_timeout_callback()
      } else {
        # Default timeout behavior: record the automatic logoff, then
        # clear the session's identity.
        ctx <- session_audit_context(session)
        tryCatch(
          log_security_event(
            event_type = "LOGOUT", user_id = user_input$username,
            description = sprintf("Automatic logoff after %s minutes of inactivity", timeout_minutes),
            severity = "info", ip_address = ctx$ip_address, session_id = ctx$session_id
          ),
          error = function(e) message("Could not record automatic logoff: ", conditionMessage(e))
        )
        user_input$authenticated <- FALSE
        user_input$username <- NULL
        user_input$user_id <- NULL
        user_input$full_name <- NULL
        user_input$role <- NULL

        shinyalert::shinyalert(
          title = "Session Expired",
          text = "Your session has expired due to inactivity. Please log in again.",
          type = "error",
          closeOnEsc = FALSE,
          closeOnClickOutside = FALSE
        )
      }
    }
  })

  invisible(session_tracker)
}

#' Manual session activity update
#'
#' Explicitly update last activity time. Useful when activity isn't
#' captured through normal input changes.
#'
#' @param session_tracker Object returned from init_session_timeout()
#'
#' @keywords internal
update_session_activity <- function(session_tracker) {
  session_tracker$last_activity(Sys.time())
}
