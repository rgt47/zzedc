#' Subject Sites Admin UI
#'
#' Review screen for the site recorded on each subject
#' ([subject_enrollment]): lists subjects, by default those with no
#' site (typically subjects recorded by [migrate_add_subject_sites()]),
#' and records a site or a transfer with a required reason through
#' [transfer_subject_site()]. Sites are registered here too
#' ([add_site()]).
#'
#' @param id The namespace id for the module.
#' @return UI elements.
#' @keywords internal
subject_sites_admin_ui <- function(id) {
  ns <- NS(id)
  div(
    h4("Subject Sites"),
    p(class = "text-muted",
      "Each subject's site is recorded at their first data entry and ",
      "changed only here, with a reason, in the audit trail. Subjects ",
      "recorded without a site (for example, those entered before ",
      "sites were recorded) are listed first for review."),
    checkboxInput(ns("only_unset"), "Show only subjects without a site",
                  value = TRUE),
    DT::DTOutput(ns("subjects_table")),
    hr(),
    h5("Record a site or a transfer"),
    fluidRow(
      column(3, selectInput(ns("subject"), "Subject", choices = NULL)),
      column(3, selectInput(ns("site"), "Site", choices = NULL)),
      column(4, textInput(ns("reason"), "Reason (required)")),
      column(2, div(class = "mt-4",
        actionButton(ns("record_btn"), "Record site",
                     class = "btn btn-primary")))
    ),
    hr(),
    h5("Register a site"),
    fluidRow(
      column(3, textInput(ns("new_site_id"), "Site ID")),
      column(5, textInput(ns("new_site_name"), "Site name")),
      column(2, div(class = "mt-4",
        actionButton(ns("add_site_btn"), "Add site",
                     class = "btn btn-outline-secondary")))
    )
  )
}


#' Subject Sites Admin Server
#'
#' @param id The namespace id for the module.
#' @param db_pool Database connection or pool (or a reactive returning
#'   one).
#' @param user_session Reactive values with the authenticated user
#'   (`authenticated`, `user_id`, `username`, `role`). Nothing is shown
#'   unless a user is signed in. Recording a site or a transfer needs
#'   the `Admin` or `PI` role; registering a site needs `Admin`. A
#'   denied action is recorded as an `ACCESS`/`DENIED` audit event.
#' @return Invisible `NULL`.
#' @keywords internal
subject_sites_admin_server <- function(id, db_pool = NULL,
                                       user_session = NULL) {
  moduleServer(id, function(input, output, session) {
    .db <- function() if (shiny::is.reactive(db_pool)) db_pool() else db_pool
    .username <- function() {
      if (!is.null(user_session)) user_session$username else NULL
    }
    guard <- .module_access_guard(user_session = user_session,
                                  session = session)
    refresh <- reactiveVal(0)

    subjects <- reactive({
      guard$require()
      refresh()
      conn <- .db()
      shiny::req(conn)
      out <- tryCatch(subject_sites(conn), error = function(e) NULL)
      shiny::req(out)
      if (isTRUE(input$only_unset)) out <- out[is.na(out$site_id), , drop = FALSE]
      # One read record per retrieval, holding subject identifiers and
      # counts, never field values (R/audit_reads.R).
      shiny::isolate(log_record_read(
        conn, "subject_sites_review", data = out, table_name = "subjects",
        user_id = .username(), filters = list(only_unset = isTRUE(input$only_unset))))
      out
    })

    sites <- reactive({
      guard$require()
      refresh()
      conn <- .db()
      shiny::req(conn)
      tryCatch(DBI::dbGetQuery(conn,
        "SELECT site_id, site_name FROM sites WHERE active = 1 ORDER BY site_id"),
        error = function(e) data.frame(site_id = character(0),
                                       site_name = character(0)))
    })

    output$subjects_table <- DT::renderDT({
      d <- subjects()
      d$site_id[is.na(d$site_id)] <- "(not recorded)"
      DT::datatable(d, rownames = FALSE, selection = "single",
                    colnames = c("Subject", "Site", "Enrolled", "Status"),
                    options = list(pageLength = 10))
    })

    observe({
      d <- subjects()
      shiny::freezeReactiveValue(input, "subject")
      updateSelectInput(session, "subject", choices = d$subject_id)
    })
    observeEvent(input$subjects_table_rows_selected, {
      d <- subjects()
      i <- input$subjects_table_rows_selected
      if (length(i) == 1) {
        updateSelectInput(session, "subject", selected = d$subject_id[i])
      }
    })
    observe({
      s <- sites()
      labels <- .site_labels(s$site_id, s$site_name)
      shiny::freezeReactiveValue(input, "site")
      updateSelectInput(session, "site",
                        choices = stats::setNames(s$site_id, labels))
    })

    observeEvent(input$record_btn, {
      guard$require_action("record a subject's site", roles = c("Admin", "PI"))
      conn <- .db()
      shiny::req(conn, input$subject, input$site)
      r <- transfer_subject_site(conn, input$subject, input$site,
                                 reason = input$reason,
                                 user_id = .username())
      if (isTRUE(r$success)) {
        shiny::showNotification(
          sprintf("Subject %s: site %s.", input$subject,
                  if (is.na(r$from_site_id)) paste("set to", r$site_id)
                  else paste("changed from", r$from_site_id, "to", r$site_id)),
          type = "message")
        updateTextInput(session, "reason", value = "")
        refresh(refresh() + 1)
      } else {
        shiny::showNotification(paste("Not recorded:", r$error),
                                type = "error", duration = 8)
      }
    })

    observeEvent(input$add_site_btn, {
      guard$require_action("register a site", roles = c("Admin"))
      conn <- .db()
      shiny::req(conn)
      r <- add_site(conn, trimws(input$new_site_id %||% ""),
                    site_name = if (nzchar(trimws(input$new_site_name %||% ""))) {
                      trimws(input$new_site_name)
                    } else {
                      trimws(input$new_site_id %||% "")
                    },
                    user_id = .username())
      if (isTRUE(r$success)) {
        shiny::showNotification(paste("Site", input$new_site_id, "registered."),
                                type = "message")
        updateTextInput(session, "new_site_id", value = "")
        updateTextInput(session, "new_site_name", value = "")
        refresh(refresh() + 1)
      } else {
        shiny::showNotification(paste("Not registered:", r$error),
                                type = "error", duration = 8)
      }
    })

    invisible(NULL)
  })
}
