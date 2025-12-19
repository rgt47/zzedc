# Audit Trail Viewer Module
#
# Shiny module for viewing, searching, and analyzing audit trail data.
# Supports FDA 21 CFR Part 11 and GDPR Article 30 compliance requirements.

#' Audit Viewer UI
#'
#' Creates the UI for the audit trail viewer module.
#'
#' @param id Character: Module namespace ID
#'
#' @return Shiny UI elements
#'
#' @export
audit_viewer_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::fluidRow(
      shiny::column(
        width = 12,
        shiny::h3("Audit Trail Viewer"),
        shiny::p("Review system activity and compliance audit records.")
      )
    ),

    shiny::fluidRow(
      shiny::column(
        width = 3,
        shiny::wellPanel(
          shiny::h4("Search Filters"),

          shiny::dateRangeInput(
            ns("date_range"),
            "Date Range:",
            start = Sys.Date() - 30,
            end = Sys.Date()
          ),

          shiny::selectInput(
            ns("event_category"),
            "Event Category:",
            choices = c(
              "All" = "",
              "Data Operations" = "data",
              "Access Events" = "access",
              "Security Events" = "security",
              "System Events" = "system",
              "Configuration" = "config",
              "Signatures" = "signature",
              "Compliance" = "compliance"
            )
          ),

          shiny::selectInput(
            ns("event_type"),
            "Event Type:",
            choices = c("All" = "")
          ),

          shiny::textInput(
            ns("user_filter"),
            "User ID:",
            placeholder = "Filter by user..."
          ),

          shiny::textInput(
            ns("search_term"),
            "Search:",
            placeholder = "Search in operations..."
          ),

          shiny::actionButton(
            ns("search_btn"),
            "Search",
            class = "btn-primary",
            width = "100%"
          ),

          shiny::hr(),

          shiny::actionButton(
            ns("export_btn"),
            "Export Results",
            class = "btn-secondary",
            width = "100%"
          )
        )
      ),

      shiny::column(
        width = 9,
        shiny::tabsetPanel(
          id = ns("audit_tabs"),

          shiny::tabPanel(
            "Audit Log",
            shiny::br(),
            DT::dataTableOutput(ns("audit_table"))
          ),

          shiny::tabPanel(
            "Statistics",
            shiny::br(),
            shiny::fluidRow(
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("Total Events"),
                  shiny::textOutput(ns("total_events"))
                )
              ),
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("Security Events"),
                  shiny::textOutput(ns("security_events"))
                )
              ),
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("Events/Day (avg)"),
                  shiny::textOutput(ns("events_per_day"))
                )
              )
            ),
            shiny::hr(),
            shiny::fluidRow(
              shiny::column(
                width = 6,
                shiny::h5("Events by Type"),
                shiny::plotOutput(ns("events_by_type_plot"), height = "300px")
              ),
              shiny::column(
                width = 6,
                shiny::h5("Events by User"),
                shiny::plotOutput(ns("events_by_user_plot"), height = "300px")
              )
            )
          ),

          shiny::tabPanel(
            "Anomaly Detection",
            shiny::br(),
            shiny::fluidRow(
              shiny::column(
                width = 12,
                shiny::actionButton(
                  ns("run_anomaly_btn"),
                  "Run Anomaly Detection",
                  class = "btn-warning"
                )
              )
            ),
            shiny::br(),
            shiny::fluidRow(
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("Risk Level"),
                  shiny::textOutput(ns("risk_level"))
                )
              ),
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("Risk Score"),
                  shiny::textOutput(ns("risk_score"))
                )
              ),
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("Alerts"),
                  shiny::textOutput(ns("alert_count"))
                )
              )
            ),
            shiny::hr(),
            shiny::h5("Alert Details"),
            DT::dataTableOutput(ns("alerts_table"))
          ),

          shiny::tabPanel(
            "Integrity Check",
            shiny::br(),
            shiny::fluidRow(
              shiny::column(
                width = 12,
                shiny::actionButton(
                  ns("verify_integrity_btn"),
                  "Verify Integrity",
                  class = "btn-info"
                )
              )
            ),
            shiny::br(),
            shiny::verbatimTextOutput(ns("integrity_result"))
          )
        )
      )
    )
  )
}


#' Audit Viewer Server
#'
#' Server logic for the audit trail viewer module.
#'
#' @param id Character: Module namespace ID
#' @param db_path Reactive: Database path
#'
#' @return Module server function
#'
#' @export
audit_viewer_server <- function(id, db_path = shiny::reactive(NULL)) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    event_types <- get_audit_event_types()

    shiny::observeEvent(input$event_category, {
      category <- input$event_category

      if (category == "") {
        choices <- c("All" = "")
      } else if (category %in% names(event_types)) {
        type_list <- event_types[[category]]
        choices <- c("All" = "", stats::setNames(type_list, type_list))
      } else {
        choices <- c("All" = "")
      }

      shiny::updateSelectInput(session, "event_type", choices = choices)
    })

    audit_data <- shiny::reactiveVal(data.frame())
    stats_data <- shiny::reactiveVal(list())
    anomaly_data <- shiny::reactiveVal(list())

    shiny::observeEvent(input$search_btn, {
      event_types_filter <- if (input$event_type != "") {
        input$event_type
      } else if (input$event_category != "" &&
                 input$event_category %in% names(event_types)) {
        event_types[[input$event_category]]
      } else {
        NULL
      }

      users_filter <- if (input$user_filter != "") {
        input$user_filter
      } else {
        NULL
      }

      search <- if (input$search_term != "") {
        input$search_term
      } else {
        NULL
      }

      results <- search_audit_trail(
        search_term = search,
        event_types = event_types_filter,
        users = users_filter,
        date_from = input$date_range[1],
        date_to = input$date_range[2],
        limit = 1000,
        db_path = db_path()
      )

      audit_data(results)

      days <- as.numeric(difftime(input$date_range[2], input$date_range[1],
                                  units = "days")) + 1

      stats <- list(
        total_events = nrow(results),
        events_per_day = round(nrow(results) / max(days, 1), 1),
        security_events = sum(results$event_type %in%
                                c("LOGIN_FAILED", "LOCKOUT", "PASSWORD_CHANGE",
                                  "ROLE_CHANGE")),
        events_by_type = if (nrow(results) > 0) {
          table(results$event_type)
        } else {
          table(character(0))
        },
        events_by_user = if (nrow(results) > 0 && "user_id" %in% names(results)) {
          head(sort(table(results$user_id), decreasing = TRUE), 10)
        } else {
          table(character(0))
        }
      )

      stats_data(stats)
    })

    output$audit_table <- DT::renderDataTable({
      data <- audit_data()

      if (nrow(data) == 0) {
        return(DT::datatable(
          data.frame(Message = "No records found. Click Search to load data."),
          options = list(dom = 't')
        ))
      }

      display_cols <- c("timestamp", "user_id", "event_type", "table_name",
                        "operation")
      display_cols <- intersect(display_cols, names(data))

      DT::datatable(
        data[, display_cols, drop = FALSE],
        options = list(
          pageLength = 25,
          scrollX = TRUE,
          order = list(list(0, 'desc'))
        ),
        selection = 'single',
        rownames = FALSE
      )
    })

    output$total_events <- shiny::renderText({
      stats <- stats_data()
      if (length(stats) == 0) "---" else format(stats$total_events, big.mark = ",")
    })

    output$security_events <- shiny::renderText({
      stats <- stats_data()
      if (length(stats) == 0) "---" else format(stats$security_events, big.mark = ",")
    })

    output$events_per_day <- shiny::renderText({
      stats <- stats_data()
      if (length(stats) == 0) "---" else stats$events_per_day
    })

    output$events_by_type_plot <- shiny::renderPlot({
      stats <- stats_data()

      if (length(stats) == 0 || length(stats$events_by_type) == 0) {
        plot.new()
        text(0.5, 0.5, "No data available", cex = 1.5)
        return()
      }

      type_data <- as.data.frame(stats$events_by_type)
      names(type_data) <- c("Event_Type", "Count")

      if (nrow(type_data) > 10) {
        type_data <- type_data[order(type_data$Count, decreasing = TRUE), ]
        type_data <- type_data[1:10, ]
      }

      graphics::barplot(
        type_data$Count,
        names.arg = type_data$Event_Type,
        las = 2,
        col = "steelblue",
        main = "Top Event Types",
        ylab = "Count",
        cex.names = 0.7
      )
    })

    output$events_by_user_plot <- shiny::renderPlot({
      stats <- stats_data()

      if (length(stats) == 0 || length(stats$events_by_user) == 0) {
        plot.new()
        text(0.5, 0.5, "No data available", cex = 1.5)
        return()
      }

      user_data <- as.data.frame(stats$events_by_user)
      names(user_data) <- c("User", "Count")

      graphics::barplot(
        user_data$Count,
        names.arg = user_data$User,
        las = 2,
        col = "darkgreen",
        main = "Top Users by Activity",
        ylab = "Count",
        cex.names = 0.7
      )
    })

    shiny::observeEvent(input$run_anomaly_btn, {
      result <- detect_audit_anomalies(
        lookback_hours = 24,
        db_path = db_path()
      )
      anomaly_data(result)
    })

    output$risk_level <- shiny::renderText({
      data <- anomaly_data()
      if (length(data) == 0) "---" else data$risk_level
    })

    output$risk_score <- shiny::renderText({
      data <- anomaly_data()
      if (length(data) == 0) "---" else data$risk_score
    })

    output$alert_count <- shiny::renderText({
      data <- anomaly_data()
      if (length(data) == 0) "---" else length(data$alerts)
    })

    output$alerts_table <- DT::renderDataTable({
      data <- anomaly_data()

      if (length(data) == 0 || length(data$alerts) == 0) {
        return(DT::datatable(
          data.frame(Message = "No alerts. Run anomaly detection to scan."),
          options = list(dom = 't')
        ))
      }

      alerts_df <- do.call(rbind, lapply(data$alerts, function(a) {
        data.frame(
          Type = a$type,
          Severity = a$severity,
          Message = a$message,
          Count = a$count,
          stringsAsFactors = FALSE
        )
      }))

      DT::datatable(
        alerts_df,
        options = list(pageLength = 10),
        rownames = FALSE
      )
    })

    shiny::observeEvent(input$verify_integrity_btn, {
      result <- verify_audit_integrity(db_path = db_path())

      output$integrity_result <- shiny::renderPrint({
        cat("Audit Trail Integrity Verification\n")
        cat("===================================\n\n")
        cat("Status:", ifelse(result$valid, "VALID", "FAILED"), "\n")
        cat("Records Checked:", result$records_checked, "\n")
        cat("Errors Found:", result$errors_found, "\n\n")
        cat("Message:", result$message, "\n")
      })
    })

    shiny::observeEvent(input$export_btn, {
      data <- audit_data()

      if (nrow(data) == 0) {
        shiny::showNotification(
          "No data to export. Please run a search first.",
          type = "warning"
        )
        return()
      }

      timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
      filename <- paste0("audit_export_", timestamp, ".csv")

      utils::write.csv(data, filename, row.names = FALSE)

      shiny::showNotification(
        paste("Exported to:", filename),
        type = "message"
      )
    })
  })
}
