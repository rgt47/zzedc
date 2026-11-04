#' Forced password-change gate UI
#'
#' Shown instead of the normal EDC panel when a session's
#' `user_input$must_change_password` is `TRUE` -- a user logging in
#' with a password someone else chose (initial account setup, an
#' admin password reset, or an admin directly setting a password)
#' must pick their own before using the app. See
#' [change_password_server()].
#'
#' @param id The module's namespace id.
#' @return A `shiny::fluidPage()`.
#' @keywords internal
change_password_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::fluidPage(
    shiny::fluidRow(
      shiny::column(
        width = 6, offset = 3,
        shiny::wellPanel(
          shiny::h4("Set a new password"),
          shiny::p(class = "text-muted",
            "Your account was set up with a password someone else ",
            "chose. Pick your own before continuing."),
          shiny::passwordInput(ns("new_password"), "New password"),
          shiny::passwordInput(ns("confirm_password"),
                                "Confirm new password"),
          shiny::uiOutput(ns("feedback")),
          shiny::actionButton(ns("submit"), "Set password",
                               class = "btn btn-primary mt-2")
        )
      )
    )
  )
}

#' Forced password-change gate server
#'
#' On a valid submission, hashes and stores the new password and
#' clears `must_change_password` on both the `edc_users` row and the
#' session's `user_input`, which is what lets `inst/app/edc.R`'s
#' `output$ui` fall through to the normal app on the next render.
#'
#' @param id The module's namespace id (must match
#'   [change_password_ui()]'s).
#' @param db_pool A DBI connection or pool.
#' @param user_input The session's authentication `reactiveValues`
#'   (see `inst/app/server.R`); must have `user_id` and
#'   `must_change_password` set.
#' @param salt The password-hashing salt, resolved by the caller the
#'   same way the login path resolves it (see `inst/app/auth.R`'s
#'   `authenticate_user()`) -- taken as a parameter rather than read
#'   from a `cfg` global, since this package function has no lexical
#'   access to the running app's session-level globals (the same
#'   reason `generate_gsheets_form_server()` takes `user_input` as a
#'   parameter instead of reading it directly).
#' @param min_length Minimum acceptable password length.
#' @return `NULL`, invisibly. Called for its side effect.
#' @keywords internal
change_password_server <- function(id, db_pool, user_input, salt,
                                    min_length = 8) {
  shiny::moduleServer(id, function(input, output, session) {
    output$feedback <- shiny::renderUI(NULL)

    shiny::observeEvent(input$submit, {
      new_pw <- input$new_password %||% ""
      confirm_pw <- input$confirm_password %||% ""

      problem <- if (!nzchar(new_pw)) {
        "Enter a new password."
      } else if (nchar(new_pw) < min_length) {
        sprintf("Password must be at least %d characters.", min_length)
      } else if (!identical(new_pw, confirm_pw)) {
        "Passwords do not match."
      } else {
        NULL
      }

      if (!is.null(problem)) {
        output$feedback <- shiny::renderUI(
          shiny::div(class = "alert alert-danger py-2 px-3 mt-2 mb-0",
                     problem)
        )
        return(invisible(NULL))
      }

      password_hash <- digest::digest(paste0(new_pw, salt), algo = "sha256")

      tryCatch({
        pool::dbExecute(
          db_pool,
          "UPDATE edc_users SET password_hash = ?, must_change_password = 0,
             modified_date = datetime('now') WHERE user_id = ?",
          params = list(password_hash, user_input$user_id)
        )
        user_input$must_change_password <- FALSE
      }, error = function(e) {
        output$feedback <- shiny::renderUI(
          shiny::div(class = "alert alert-danger py-2 px-3 mt-2 mb-0",
                     paste("Could not update password:",
                           conditionMessage(e)))
        )
      })
    })
  })
}
