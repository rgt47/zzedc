#' Randomization Admin UI
#'
#' Study-level randomization scheme configuration (not yet wired up
#' here -- see the plan's phase 3 for exposing scheme/covariate
#' choices) and the Phase 2 blinding grant/revoke panel: who
#' currently has unblinded access to this study's treatment
#' assignments, with Admin-only grant and revoke controls.
#'
#' @param id The namespace id for the module
#' @return UI elements
#' @keywords internal
randomization_admin_ui <- function(id) {
  ns <- NS(id)

  div(
    h4("Unblinded Access"),
    p(class = "text-muted",
      "Users granted unblinded access can see a subject's treatment ",
      "arm; everyone else sees only whether a subject has been ",
      "randomized. Granting and revoking is Admin-only."),
    div(id = ns("alert_area")),
    fluidRow(
      column(6,
        selectInput(ns("grant_user"), "User", choices = c("Loading..." = "")),
        actionButton(ns("grant_btn"), "Grant Unblinded Access",
                     class = "btn btn-outline-primary")
      ),
      column(6,
        selectInput(ns("revoke_user"), "Currently unblinded",
                    choices = c("None" = "")),
        actionButton(ns("revoke_btn"), "Revoke Access",
                     class = "btn btn-outline-danger")
      )
    ),
    hr(),
    tableOutput(ns("grants_table"))
  )
}


#' Randomization Admin Server
#'
#' @param id The namespace id for the module
#' @param db_pool Reactive expression or value returning database
#'   connection pool
#' @param user_session Reactive values with authenticated user info
#'   (`user_id`, `username`, `role`)
#' @return Invisible NULL
#' @keywords internal
randomization_admin_server <- function(id, db_pool = NULL, user_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    .db <- function() if (shiny::is.reactive(db_pool)) db_pool() else db_pool
    .actor_role <- function() {
      if (!is.null(user_session)) user_session$role else NULL
    }
    .actor_user_id <- function() {
      if (!is.null(user_session)) user_session$user_id else NULL
    }

    refresh <- reactiveVal(0)

    observe({
      conn <- .db()
      shiny::req(conn)
      users <- tryCatch(
        DBI::dbGetQuery(conn, "SELECT user_id, username FROM edc_users ORDER BY username"),
        error = function(e) data.frame(user_id = character(), username = character())
      )
      choices <- stats::setNames(users$user_id, users$username)
      updateSelectInput(session, "grant_user", choices = choices)
    })

    .current_grants <- reactive({
      refresh()
      conn <- .db()
      shiny::req(conn)
      zzedc::list_unblinding_grants(conn)
    })

    observe({
      grants <- .current_grants()
      choices <- if (nrow(grants) == 0) {
        c("None" = "")
      } else {
        stats::setNames(grants$user_id, grants$user_id)
      }
      updateSelectInput(session, "revoke_user", choices = choices)
    })

    output$grants_table <- renderTable({
      grants <- .current_grants()
      if (nrow(grants) == 0) {
        return(data.frame(Note = "No users currently have unblinded access."))
      }
      grants
    })

    observeEvent(input$grant_btn, {
      conn <- .db()
      shiny::req(conn, input$grant_user)
      result <- zzedc::grant_unblinded_access(
        conn, study_id = zzedc:::.current_study_id(conn),
        user_id = input$grant_user, granted_by = .actor_user_id(),
        actor_role = .actor_role()
      )
      if (isTRUE(result$success)) {
        shiny::showNotification("Unblinded access granted.", type = "message")
        refresh(refresh() + 1)
      } else {
        shiny::showNotification(paste("Could not grant access:", result$error),
                                 type = "error")
      }
    })

    observeEvent(input$revoke_user, {
      conn <- .db()
      shiny::req(conn, input$revoke_user)
      result <- zzedc::revoke_unblinded_access(
        conn, study_id = zzedc:::.current_study_id(conn),
        user_id = input$revoke_user, revoked_by = .actor_user_id(),
        actor_role = .actor_role()
      )
      if (isTRUE(result$success)) {
        shiny::showNotification("Unblinded access revoked.", type = "message")
        refresh(refresh() + 1)
      } else {
        shiny::showNotification(paste("Could not revoke access:", result$error),
                                 type = "error")
      }
    })

    invisible(NULL)
  })
}
