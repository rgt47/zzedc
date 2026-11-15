#' Randomization Admin UI
#'
#' Four panels: study-level scheme setup (scheme, covariate fields,
#' seed, arm labels -- Admin-only, and refused once the config is
#' locked, i.e. after the first subject is randomized), the Phase 2
#' blinding grant/revoke panel (who currently has unblinded access to
#' this study's treatment assignments, Admin-only), balance
#' diagnostics (`zzalloc::allocation_imbalance()` on the realized
#' allocation, visible only to an unblinded viewer since it reveals
#' per-arm counts), and the Phase 4 emergency unblind panel (a
#' one-time, reason-mandatory reveal of a single subject's arm,
#' Admin/PI-only, that never grants standing access).
#'
#' @param id The namespace id for the module
#' @return UI elements
#' @keywords internal
randomization_admin_ui <- function(id) {
  ns <- NS(id)

  div(
    h4("Scheme Setup"),
    p(class = "text-muted",
      "Choosing a scheme and seed is Admin-only, and is refused once ",
      "the first subject has been randomized for this study. ",
      "Covariate fields are only used by stratified_block, ",
      "pocock_simon, hu_hu, and msb -- pick discrete CRF fields ",
      "(a small number of categories), not continuous measurements."),
    uiOutput(ns("current_config_display")),
    fluidRow(
      column(4,
        selectInput(ns("scheme"), "Scheme",
                    choices = setdiff(zzalloc::allocation_schemes(), "cara"))
      ),
      column(4,
        numericInput(ns("rng_seed"), "RNG Seed", value = 1L, min = 1L, step = 1L)
      ),
      column(4,
        selectizeInput(ns("covariate_fields"), "Covariate Fields (if applicable)",
                        choices = NULL, multiple = TRUE)
      )
    ),
    fluidRow(
      column(6, textInput(ns("arm0_label"), "Arm 0 Label", value = "Control")),
      column(6, textInput(ns("arm1_label"), "Arm 1 Label", value = "Treatment"))
    ),
    actionButton(ns("save_config_btn"), "Save Scheme Configuration",
                 class = "btn btn-outline-primary"),
    hr(),

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
    tableOutput(ns("grants_table")),
    hr(),

    h4("Balance Diagnostics"),
    uiOutput(ns("imbalance_display")),
    hr(),

    h4("Emergency Unblind"),
    p(class = "text-muted",
      "Reveals one subject's treatment arm immediately, for a",
      "situation (e.g. a serious adverse event) where someone needs",
      "to know right now. This is a one-time disclosure, not standing",
      "access: it does not change this or any user's blinding status",
      "for the rest of the study, and is logged with the reason given.",
      "Admin or PI only."),
    fluidRow(
      column(4, textInput(ns("unblind_subject_id"), "Subject ID")),
      column(8, textAreaInput(ns("unblind_reason"), "Reason (required, min. 10 characters)",
                               rows = 2))
    ),
    actionButton(ns("unblind_btn"), "Emergency Unblind",
                 class = "btn btn-outline-danger"),
    uiOutput(ns("unblind_result"))
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
    config_refresh <- reactiveVal(0)

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

    # Covariate field choices: every distinct field_code across this
    # study's CRF forms, not filtered by type -- zzalloc's own
    # check_covariates() is the authority on what is actually usable
    # (discrete, non-missing), and will raise a clear error at
    # randomize_next_subject() time if a chosen field turns out to be
    # continuous. Filtering here on designer_fields.field_type would
    # risk excluding a genuinely discrete numeric-coded field (e.g. a
    # 0/1 flag stored as "numeric") on a type label alone.
    observe({
      conn <- .db()
      shiny::req(conn)
      fields <- tryCatch(
        DBI::dbGetQuery(conn,
          "SELECT DISTINCT field_code FROM designer_fields ORDER BY field_code"),
        error = function(e) data.frame(field_code = character())
      )
      updateSelectizeInput(session, "covariate_fields", choices = fields$field_code)
    })

    .current_config <- reactive({
      config_refresh()
      conn <- .db()
      shiny::req(conn)
      zzedc::get_randomization_config(conn)
    })

    output$current_config_display <- renderUI({
      cfg <- .current_config()
      if (is.null(cfg)) {
        return(tags$p(class = "text-muted", "No scheme configured yet."))
      }
      tags$p(
        tags$strong("Current: "), cfg$scheme,
        " (seed ", cfg$rng_seed, ", status: ", cfg$status, ")",
        if (length(cfg$covariate_fields) > 0) {
          paste0(" -- covariates: ", paste(cfg$covariate_fields, collapse = ", "))
        } else {
          ""
        }
      )
    })

    observeEvent(input$save_config_btn, {
      conn <- .db()
      shiny::req(conn, input$scheme)
      labels <- c("0" = input$arm0_label, "1" = input$arm1_label)
      result <- zzedc::set_randomization_config(
        conn, scheme = input$scheme, rng_seed = input$rng_seed,
        covariate_fields = if (length(input$covariate_fields) > 0) {
          input$covariate_fields
        } else {
          NULL
        },
        created_by = .actor_user_id(), actor_role = .actor_role()
      )
      if (isTRUE(result$success)) {
        zzedc::set_treatment_arm_labels(conn, labels)
        shiny::showNotification("Randomization scheme saved.", type = "message")
        config_refresh(config_refresh() + 1)
      } else {
        shiny::showNotification(paste("Could not save scheme:", result$error),
                                 type = "error")
      }
    })

    output$imbalance_display <- renderUI({
      refresh()
      conn <- .db()
      shiny::req(conn)
      if (!zzedc::is_unblinded(conn, .current_study_id(conn), .actor_user_id())) {
        return(tags$p(class = "text-muted",
                       "Unblind to view balance diagnostics."))
      }
      imb <- zzedc::get_study_imbalance(conn)
      if (is.null(imb)) {
        return(tags$p(class = "text-muted", "No subjects randomized yet."))
      }
      tagList(
        tags$p(tags$strong("Overall (arm 1 - arm 0): "), imb$overall),
        if (!is.null(imb$marginal)) {
          tagList(
            tags$p(tags$strong("Max marginal imbalance: "), imb$max_marginal),
            tags$pre(paste(utils::capture.output(print(imb$marginal)), collapse = "\n"))
          )
        }
      )
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
        conn, study_id = .current_study_id(conn),
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

    observeEvent(input$revoke_btn, {
      conn <- .db()
      shiny::req(conn, input$revoke_user)
      result <- zzedc::revoke_unblinded_access(
        conn, study_id = .current_study_id(conn),
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

    # One-time display only -- never written anywhere other than the
    # EMERGENCY_UNBLIND audit event itself (emergency_unblind_subject()
    # does not touch study_unblinding_grants), and cleared whenever the
    # subject id field changes so a stale reveal can't linger on screen
    # after the viewer moves on to a different subject.
    unblind_result <- reactiveVal(NULL)
    observeEvent(input$unblind_subject_id, unblind_result(NULL))

    observeEvent(input$unblind_btn, {
      conn <- .db()
      shiny::req(conn, input$unblind_subject_id)
      result <- zzedc::emergency_unblind_subject(
        conn, subject_id = input$unblind_subject_id,
        requested_by = .actor_user_id(), reason = input$unblind_reason,
        study_id = .current_study_id(conn), actor_role = .actor_role()
      )
      if (isTRUE(result$success)) {
        unblind_result(paste0(
          "Subject '", input$unblind_subject_id, "' is on arm: ",
          result$arm_label %||% paste0("Arm ", result$arm_code)
        ))
      } else {
        unblind_result(NULL)
        shiny::showNotification(paste("Could not unblind:", result$error),
                                 type = "error")
      }
    })

    output$unblind_result <- renderUI({
      val <- unblind_result()
      shiny::req(val)
      tags$div(class = "alert alert-warning mt-2", val)
    })

    invisible(NULL)
  })
}
