#' Data Correction Workflow UI Module
#'
#' Shiny module for FDA-compliant data correction workflow.
#' Provides interfaces for creating, reviewing, and applying corrections.

#' Data Correction UI
#'
#' @param id Module namespace ID
#'
#' @return Shiny UI elements
#'
#' @export
data_correction_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::fluidRow(
      shiny::column(12,
        shiny::h3("Data Correction Workflow"),
        shiny::p("FDA 21 CFR Part 11 compliant data correction system"),
        shiny::hr()
      )
    ),

    shiny::fluidRow(
      shiny::column(3,
        shiny::wellPanel(
          shiny::h4("Navigation"),
          shiny::radioButtons(
            ns("view_mode"),
            "View:",
            choices = c(
              "Create Request" = "create",
              "Pending Review" = "pending",
              "My Requests" = "my_requests",
              "All Corrections" = "all",
              "Statistics" = "stats"
            ),
            selected = "pending"
          ),
          shiny::hr(),
          shiny::h5("Quick Stats"),
          shiny::uiOutput(ns("quick_stats"))
        )
      ),

      shiny::column(9,
        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'create'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("Create Correction Request"),
            shiny::fluidRow(
              shiny::column(6,
                shiny::textInput(ns("table_name"), "Table Name", placeholder = "e.g., subjects"),
                shiny::textInput(ns("record_id"), "Record ID", placeholder = "e.g., S001"),
                shiny::textInput(ns("field_name"), "Field Name", placeholder = "e.g., age")
              ),
              shiny::column(6,
                shiny::textInput(ns("original_value"), "Original Value (read-only)"),
                shiny::textInput(ns("corrected_value"), "Corrected Value"),
                shiny::selectInput(
                  ns("correction_reason"),
                  "Reason for Correction",
                  choices = c(
                    "Select reason..." = "",
                    "Typographical Error" = "TYPO",
                    "Source Document Error" = "SOURCE_DOC_ERROR",
                    "Calculation Error" = "CALCULATION_ERROR",
                    "Transcription Error" = "TRANSCRIPTION_ERROR",
                    "Unit Error" = "UNIT_ERROR",
                    "Date/Time Error" = "DATE_ERROR",
                    "Protocol Clarification" = "PROTOCOL_CLARIFICATION",
                    "Query Response" = "QUERY_RESPONSE",
                    "Other" = "OTHER"
                  )
                )
              )
            ),
            shiny::fluidRow(
              shiny::column(12,
                shiny::textAreaInput(
                  ns("reason_details"),
                  "Reason Details (required if Other)",
                  rows = 3,
                  placeholder = "Provide detailed explanation..."
                )
              )
            ),
            shiny::fluidRow(
              shiny::column(6,
                shiny::textInput(ns("original_source_doc"),
                                  "Original Source Document Reference")
              ),
              shiny::column(6,
                shiny::textInput(ns("corrected_source_doc"),
                                  "Corrected Source Document Reference")
              )
            ),
            shiny::fluidRow(
              shiny::column(6,
                shiny::textInput(ns("site_id"), "Site ID (optional)"),
                shiny::textInput(ns("study_id"), "Study ID (optional)")
              ),
              shiny::column(6,
                shiny::textInput(ns("subject_id"), "Subject ID (optional)"),
                shiny::textInput(ns("visit_id"), "Visit ID (optional)")
              )
            ),
            shiny::hr(),
            shiny::actionButton(ns("submit_request"), "Submit Correction Request",
                                class = "btn-primary"),
            shiny::textOutput(ns("submit_message"))
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'pending'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("Pending Corrections for Review"),
            DT::DTOutput(ns("pending_table")),
            shiny::hr(),
            shiny::h5("Review Selected Request"),
            shiny::uiOutput(ns("review_panel"))
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'my_requests'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("My Correction Requests"),
            DT::DTOutput(ns("my_requests_table")),
            shiny::hr(),
            shiny::uiOutput(ns("request_details"))
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'all'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("All Corrections"),
            shiny::fluidRow(
              shiny::column(3,
                shiny::selectInput(ns("filter_status"), "Status",
                  choices = c("All" = "", "PENDING", "APPROVED",
                              "REJECTED", "APPLIED", "CANCELLED"))
              ),
              shiny::column(3,
                shiny::textInput(ns("filter_site"), "Site ID")
              ),
              shiny::column(3,
                shiny::dateInput(ns("filter_start"), "From Date",
                                  value = Sys.Date() - 30)
              ),
              shiny::column(3,
                shiny::dateInput(ns("filter_end"), "To Date",
                                  value = Sys.Date())
              )
            ),
            DT::DTOutput(ns("all_corrections_table"))
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'stats'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("Correction Statistics"),
            shiny::fluidRow(
              shiny::column(3,
                shiny::valueBoxOutput(ns("stat_total"), width = 12)
              ),
              shiny::column(3,
                shiny::valueBoxOutput(ns("stat_pending"), width = 12)
              ),
              shiny::column(3,
                shiny::valueBoxOutput(ns("stat_approved"), width = 12)
              ),
              shiny::column(3,
                shiny::valueBoxOutput(ns("stat_rejected"), width = 12)
              )
            ),
            shiny::hr(),
            shiny::fluidRow(
              shiny::column(6,
                shiny::h5("By Reason"),
                DT::DTOutput(ns("stats_by_reason"))
              ),
              shiny::column(6,
                shiny::h5("By Table"),
                DT::DTOutput(ns("stats_by_table"))
              )
            ),
            shiny::hr(),
            shiny::h5("Generate Report"),
            shiny::fluidRow(
              shiny::column(4,
                shiny::textInput(ns("report_org"), "Organization",
                                  value = "Clinical Research Organization")
              ),
              shiny::column(4,
                shiny::selectInput(ns("report_format"), "Format",
                  choices = c("Text" = "txt", "JSON" = "json"))
              ),
              shiny::column(4,
                shiny::br(),
                shiny::downloadButton(ns("download_report"), "Download Report")
              )
            )
          )
        )
      )
    )
  )
}


#' Data Correction Server
#'
#' @param id Module namespace ID
#' @param current_user Reactive: Current user ID
#' @param user_role Reactive: Current user role
#' @param db_path Character: Database path
#'
#' @return Module server
#'
#' @export
data_correction_server <- function(id, current_user, user_role, db_path = NULL) {
  shiny::moduleServer(id, function(input, output, session) {

    rv <- shiny::reactiveValues(
      refresh_trigger = 0,
      selected_request = NULL
    )

    output$quick_stats <- shiny::renderUI({
      rv$refresh_trigger
      stats <- tryCatch({
        get_correction_statistics(db_path = db_path)
      }, error = function(e) {
        list(summary = list(total_requests = 0, pending = 0,
                            approval_rate = 0))
      })

      shiny::tagList(
        shiny::p(shiny::strong("Total:"), stats$summary$total_requests),
        shiny::p(shiny::strong("Pending:"), stats$summary$pending),
        shiny::p(shiny::strong("Approval Rate:"),
                  paste0(stats$summary$approval_rate, "%"))
      )
    })

    shiny::observeEvent(input$submit_request, {
      user <- if (shiny::is.reactive(current_user)) current_user() else current_user

      if (is.null(user) || user == "") {
        output$submit_message <- shiny::renderText("Error: Not logged in")
        return()
      }

      if (input$table_name == "" || input$record_id == "" ||
          input$field_name == "" || input$corrected_value == "" ||
          input$correction_reason == "") {
        output$submit_message <- shiny::renderText(
          "Error: Please fill in all required fields")
        return()
      }

      result <- create_correction_request(
        table_name = input$table_name,
        record_id = input$record_id,
        field_name = input$field_name,
        original_value = input$original_value,
        corrected_value = input$corrected_value,
        correction_reason = input$correction_reason,
        reason_details = input$reason_details,
        requested_by = user,
        original_source_doc = input$original_source_doc,
        corrected_source_doc = input$corrected_source_doc,
        site_id = input$site_id,
        study_id = input$study_id,
        subject_id = input$subject_id,
        visit_id = input$visit_id,
        db_path = db_path
      )

      if (result$success) {
        output$submit_message <- shiny::renderText(
          paste("Request #", result$request_id, "created successfully"))
        rv$refresh_trigger <- rv$refresh_trigger + 1

        shiny::updateTextInput(session, "table_name", value = "")
        shiny::updateTextInput(session, "record_id", value = "")
        shiny::updateTextInput(session, "field_name", value = "")
        shiny::updateTextInput(session, "original_value", value = "")
        shiny::updateTextInput(session, "corrected_value", value = "")
        shiny::updateSelectInput(session, "correction_reason", selected = "")
        shiny::updateTextAreaInput(session, "reason_details", value = "")
      } else {
        output$submit_message <- shiny::renderText(
          paste("Error:", result$error))
      }
    })

    pending_data <- shiny::reactive({
      rv$refresh_trigger
      tryCatch({
        get_pending_corrections(db_path = db_path)
      }, error = function(e) data.frame())
    })

    output$pending_table <- DT::renderDT({
      data <- pending_data()
      if (nrow(data) == 0) {
        return(DT::datatable(data.frame(Message = "No pending corrections")))
      }

      display_cols <- c("request_id", "table_name", "field_name",
                        "original_value", "corrected_value",
                        "correction_reason", "requested_by", "requested_at")
      display_data <- data[, intersect(display_cols, names(data)), drop = FALSE]

      DT::datatable(
        display_data,
        selection = "single",
        options = list(pageLength = 10, scrollX = TRUE)
      )
    })

    shiny::observeEvent(input$pending_table_rows_selected, {
      data <- pending_data()
      if (!is.null(input$pending_table_rows_selected) && nrow(data) > 0) {
        rv$selected_request <- data$request_id[input$pending_table_rows_selected]
      }
    })

    output$review_panel <- shiny::renderUI({
      if (is.null(rv$selected_request)) {
        return(shiny::p("Select a request to review"))
      }

      ns <- session$ns

      req_data <- tryCatch({
        get_correction_request(rv$selected_request, db_path = db_path)
      }, error = function(e) list(success = FALSE))

      if (!req_data$success) {
        return(shiny::p("Error loading request"))
      }

      r <- req_data$request

      shiny::tagList(
        shiny::h5(paste("Request #", r$request_id)),
        shiny::fluidRow(
          shiny::column(6,
            shiny::p(shiny::strong("Table:"), r$table_name),
            shiny::p(shiny::strong("Record:"), r$record_id),
            shiny::p(shiny::strong("Field:"), r$field_name)
          ),
          shiny::column(6,
            shiny::p(shiny::strong("Original:"), r$original_value),
            shiny::p(shiny::strong("Corrected:"), r$corrected_value),
            shiny::p(shiny::strong("Reason:"), r$correction_reason)
          )
        ),
        shiny::p(shiny::strong("Details:"), r$reason_details),
        shiny::p(shiny::strong("Requested by:"), r$requested_by,
                  "at", r$requested_at),
        shiny::hr(),
        shiny::textAreaInput(ns("review_comments"), "Review Comments", rows = 2),
        shiny::actionButton(ns("approve_btn"), "Approve", class = "btn-success"),
        shiny::actionButton(ns("reject_btn"), "Reject", class = "btn-danger"),
        shiny::actionButton(ns("apply_btn"), "Apply Correction", class = "btn-primary")
      )
    })

    shiny::observeEvent(input$approve_btn, {
      user <- if (shiny::is.reactive(current_user)) current_user() else current_user

      result <- approve_correction(
        request_id = rv$selected_request,
        reviewed_by = user,
        review_comments = input$review_comments,
        db_path = db_path
      )

      if (result$success) {
        shiny::showNotification("Correction approved", type = "message")
        rv$refresh_trigger <- rv$refresh_trigger + 1
        rv$selected_request <- NULL
      } else {
        shiny::showNotification(paste("Error:", result$error), type = "error")
      }
    })

    shiny::observeEvent(input$reject_btn, {
      user <- if (shiny::is.reactive(current_user)) current_user() else current_user

      if (nchar(input$review_comments) < 10) {
        shiny::showNotification(
          "Rejection reason required (min 10 characters)", type = "error")
        return()
      }

      result <- reject_correction(
        request_id = rv$selected_request,
        reviewed_by = user,
        review_comments = input$review_comments,
        db_path = db_path
      )

      if (result$success) {
        shiny::showNotification("Correction rejected", type = "warning")
        rv$refresh_trigger <- rv$refresh_trigger + 1
        rv$selected_request <- NULL
      } else {
        shiny::showNotification(paste("Error:", result$error), type = "error")
      }
    })

    shiny::observeEvent(input$apply_btn, {
      user <- if (shiny::is.reactive(current_user)) current_user() else current_user

      result <- apply_correction(
        request_id = rv$selected_request,
        applied_by = user,
        db_path = db_path
      )

      if (result$success) {
        shiny::showNotification("Correction applied successfully", type = "message")
        rv$refresh_trigger <- rv$refresh_trigger + 1
        rv$selected_request <- NULL
      } else {
        shiny::showNotification(paste("Error:", result$error), type = "error")
      }
    })

    output$my_requests_table <- DT::renderDT({
      rv$refresh_trigger
      user <- if (shiny::is.reactive(current_user)) current_user() else current_user

      tryCatch({
        conn <- connect_encrypted_db(db_path = db_path)
        on.exit(DBI::dbDisconnect(conn), add = TRUE)

        data <- DBI::dbGetQuery(conn, "
          SELECT request_id, table_name, field_name, status,
                 corrected_value, correction_reason, requested_at
          FROM correction_requests
          WHERE requested_by = ?
          ORDER BY requested_at DESC
        ", list(user))

        DT::datatable(data, selection = "single",
                      options = list(pageLength = 10))
      }, error = function(e) {
        DT::datatable(data.frame(Message = "Error loading requests"))
      })
    })

    output$all_corrections_table <- DT::renderDT({
      rv$refresh_trigger

      tryCatch({
        conn <- connect_encrypted_db(db_path = db_path)
        on.exit(DBI::dbDisconnect(conn), add = TRUE)

        query <- "SELECT * FROM correction_requests WHERE 1=1"
        params <- list()

        if (input$filter_status != "") {
          query <- paste(query, "AND status = ?")
          params <- c(params, list(input$filter_status))
        }

        if (input$filter_site != "") {
          query <- paste(query, "AND site_id = ?")
          params <- c(params, list(input$filter_site))
        }

        query <- paste(query, "AND requested_at >= ? AND requested_at <= ?")
        params <- c(params, list(
          as.character(input$filter_start),
          as.character(input$filter_end + 1)
        ))

        query <- paste(query, "ORDER BY requested_at DESC")

        data <- if (length(params) > 0) {
          DBI::dbGetQuery(conn, query, params)
        } else {
          DBI::dbGetQuery(conn, query)
        }

        display_cols <- c("request_id", "table_name", "field_name", "status",
                          "correction_reason", "requested_by", "requested_at",
                          "reviewed_by", "reviewed_at")

        DT::datatable(
          data[, intersect(display_cols, names(data)), drop = FALSE],
          options = list(pageLength = 15, scrollX = TRUE)
        )
      }, error = function(e) {
        DT::datatable(data.frame(Message = "Error loading corrections"))
      })
    })

    stats_data <- shiny::reactive({
      rv$refresh_trigger
      tryCatch({
        get_correction_statistics(db_path = db_path)
      }, error = function(e) {
        list(success = FALSE, summary = list(
          total_requests = 0, pending = 0, approved = 0, rejected = 0
        ), by_reason = data.frame(), by_table = data.frame())
      })
    })

    output$stat_total <- shinydashboard::renderValueBox({
      stats <- stats_data()
      shinydashboard::valueBox(
        stats$summary$total_requests,
        "Total Requests",
        icon = shiny::icon("file-alt"),
        color = "blue"
      )
    })

    output$stat_pending <- shinydashboard::renderValueBox({
      stats <- stats_data()
      shinydashboard::valueBox(
        stats$summary$pending,
        "Pending",
        icon = shiny::icon("clock"),
        color = "yellow"
      )
    })

    output$stat_approved <- shinydashboard::renderValueBox({
      stats <- stats_data()
      shinydashboard::valueBox(
        stats$summary$approved + stats$summary$applied,
        "Approved/Applied",
        icon = shiny::icon("check"),
        color = "green"
      )
    })

    output$stat_rejected <- shinydashboard::renderValueBox({
      stats <- stats_data()
      shinydashboard::valueBox(
        stats$summary$rejected,
        "Rejected",
        icon = shiny::icon("times"),
        color = "red"
      )
    })

    output$stats_by_reason <- DT::renderDT({
      stats <- stats_data()
      DT::datatable(
        stats$by_reason,
        options = list(pageLength = 10, dom = 't')
      )
    })

    output$stats_by_table <- DT::renderDT({
      stats <- stats_data()
      DT::datatable(
        stats$by_table,
        options = list(pageLength = 10, dom = 't')
      )
    })

    output$download_report <- shiny::downloadHandler(
      filename = function() {
        paste0("correction_report_", Sys.Date(), ".",
               input$report_format)
      },
      content = function(file) {
        generate_correction_report(
          output_file = file,
          format = input$report_format,
          organization = input$report_org,
          prepared_by = if (shiny::is.reactive(current_user)) {
            current_user()
          } else {
            current_user
          },
          db_path = db_path
        )
      }
    )
  })
}
