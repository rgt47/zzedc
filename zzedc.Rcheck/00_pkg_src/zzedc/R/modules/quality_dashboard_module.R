# Data Quality Dashboard Module
#
# Provides real-time data quality metrics and visualizations
# for study data monitoring and QC.

#' Quality Dashboard Module UI
#'
#' @param id Namespace ID for the module
#'
#' @return A tagList containing the quality dashboard UI
#'
#' @keywords internal
quality_dashboard_ui <- function(id) {
  ns <- NS(id)

  div(
    # Quality Dashboard Title
    div(
      class = "mb-4",
      h2(icon("chart-bar"), " Data Quality Dashboard", class = "mb-3"),
      p("Real-time monitoring of study data quality and completeness",
        class = "text-muted")
    ),

    # Key Metrics Cards
    fluidRow(
      column(3,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("file-earmark-check"), " Total Records")
          ),
          bslib::card_body(
            div(
              class = "text-center",
              div(
                id = ns("metric_total"),
                class = "display-4 text-primary fw-bold",
                "0"
              ),
              p("records in database", class = "text-muted small")
            )
          )
        )
      ),

      column(3,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("check-circle-fill"), " Complete Records")
          ),
          bslib::card_body(
            div(
              class = "text-center",
              div(
                id = ns("metric_complete"),
                class = "display-4 text-success fw-bold",
                "0"
              ),
              p("100% complete forms", class = "text-muted small")
            )
          )
        )
      ),

      column(3,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("exclamation-circle"), " % Incomplete")
          ),
          bslib::card_body(
            div(
              class = "text-center",
              div(
                id = ns("metric_incomplete_pct"),
                class = "display-4 text-warning fw-bold",
                "0%"
              ),
              p("with missing data", class = "text-muted small")
            )
          )
        )
      ),

      column(3,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("flag-fill"), " Flagged Issues")
          ),
          bslib::card_body(
            div(
              class = "text-center",
              div(
                id = ns("metric_flagged"),
                class = "display-4 text-danger fw-bold",
                "0"
              ),
              p("requiring review", class = "text-muted small")
            )
          )
        )
      )
    ),

    # Charts and Detailed View
    fluidRow(
      column(6,
        bslib::card(
          bslib::card_header("Completeness by Form"),
          bslib::card_body(
            plotly::plotlyOutput(ns("completeness_chart"), height = "400px")
          )
        )
      ),

      column(6,
        bslib::card(
          bslib::card_header("Data Entry Timeline"),
          bslib::card_body(
            plotly::plotlyOutput(ns("timeline_chart"), height = "400px")
          )
        )
      )
    ),

    # Missing Data Table
    fluidRow(
      column(12,
        bslib::card(
          bslib::card_header("Missing Data Summary"),
          bslib::card_body(
            div(
              class = "table-responsive",
              DT::dataTableOutput(ns("missing_data_table"))
            )
          )
        )
      )
    ),

    # QC Flags and Issues
    fluidRow(
      column(12,
        bslib::card(
          bslib::card_header("Quality Control Flags"),
          bslib::card_body(
            div(
              id = ns("qc_flags_container"),
              p("Loading QC status...", class = "text-muted")
            )
          )
        )
      )
    )
  )
}

#' Quality Dashboard Module Server
#'
#' @param id Namespace ID for the module
#' @param db_conn Reactive database connection
#' @param refresh_interval Interval in milliseconds to refresh dashboard (default: 30000)
#'
#' @keywords internal
quality_dashboard_server <- function(id, db_conn, refresh_interval = 30000) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reactive data - refreshes periodically
    quality_data <- reactive({
      invalidateLater(refresh_interval, session)

      tryCatch({
        conn <- db_conn()
        if (is.null(conn)) return(NULL)

        # Get total records
        total_records <- DBI::dbGetQuery(
          conn,
          "SELECT COUNT(DISTINCT subject_id) as count FROM form_submissions"
        )$count %||% 0

        # Get complete records (all required fields filled)
        complete_records <- DBI::dbGetQuery(
          conn,
          "SELECT COUNT(DISTINCT subject_id) as count FROM form_submissions
           WHERE status = 'complete'"
        )$count %||% 0

        # Get incomplete records
        incomplete_records <- total_records - complete_records

        # Get flagged records
        flagged_records <- DBI::dbGetQuery(
          conn,
          "SELECT COUNT(DISTINCT subject_id) as count FROM form_submissions
           WHERE status = 'flagged' OR status = 'query'"
        )$count %||% 0

        # Get form completeness
        form_completeness <- DBI::dbGetQuery(
          conn,
          "SELECT form_name,
                  COUNT(*) as total,
                  SUM(CASE WHEN status = 'complete' THEN 1 ELSE 0 END) as complete
           FROM form_submissions
           GROUP BY form_name
           ORDER BY form_name"
        )

        # Get data entry timeline (last 30 days)
        timeline_data <- DBI::dbGetQuery(
          conn,
          "SELECT DATE(submission_date) as entry_date,
                  COUNT(*) as entries
           FROM form_submissions
           WHERE submission_date >= date('now', '-30 days')
           GROUP BY DATE(submission_date)
           ORDER BY entry_date"
        )

        # Get missing data summary
        missing_summary <- DBI::dbGetQuery(
          conn,
          "SELECT field_name,
                  COUNT(*) as total_fields,
                  SUM(CASE WHEN field_value IS NULL OR field_value = '' THEN 1 ELSE 0 END) as missing
           FROM form_field_values
           WHERE required = 1
           GROUP BY field_name
           HAVING missing > 0
           ORDER BY missing DESC
           LIMIT 20"
        )

        list(
          total_records = total_records,
          complete_records = complete_records,
          incomplete_records = incomplete_records,
          incomplete_pct = if (total_records > 0) {
            round(100 * incomplete_records / total_records, 1)
          } else {
            0
          },
          flagged_records = flagged_records,
          form_completeness = form_completeness,
          timeline_data = timeline_data,
          missing_summary = missing_summary
        )
      }, error = function(e) {
        warning("Quality dashboard error: ", e$message)
        NULL
      })
    })

    # Update key metrics
    observe({
      data <- quality_data()
      if (!is.null(data)) {
        # Update metric cards
        output$metric_total <- renderText(
          formatC(data$total_records, big.mark = ",", format = "d")
        )
        output$metric_complete <- renderText(
          formatC(data$complete_records, big.mark = ",", format = "d")
        )
        output$metric_incomplete_pct <- renderText(
          paste0(data$incomplete_pct, "%")
        )
        output$metric_flagged <- renderText(
          formatC(data$flagged_records, big.mark = ",", format = "d")
        )
      }
    })

    # Completeness by form chart
    output$completeness_chart <- plotly::renderPlotly({
      data <- quality_data()
      if (is.null(data) || nrow(data$form_completeness) == 0) {
        plotly::plot_ly(type = "bar") %>%
          plotly::layout(title = "No data available")
      } else {
        df <- data$form_completeness
        df$completeness_pct <- round(100 * df$complete / df$total, 1)

        plotly::plot_ly(df, x = ~form_name, y = ~completeness_pct,
          type = "bar",
          marker = list(
            color = ~ifelse(completeness_pct >= 80, "green", "orange")
          ),
          hovertemplate = "%{x}<br>Completeness: %{y}%<extra></extra>"
        ) %>%
          plotly::layout(
            title = "Form Completeness (%)",
            xaxis = list(title = "Form"),
            yaxis = list(title = "Completeness (%)", range = c(0, 100)),
            showlegend = FALSE,
            margin = list(b = 80),
            hovermode = "closest"
          )
      }
    })

    # Data entry timeline chart
    output$timeline_chart <- plotly::renderPlotly({
      data <- quality_data()
      if (is.null(data) || nrow(data$timeline_data) == 0) {
        plotly::plot_ly(type = "scatter") %>%
          plotly::layout(title = "No data available")
      } else {
        df <- data$timeline_data
        df$entry_date <- as.Date(df$entry_date)

        plotly::plot_ly(df, x = ~entry_date, y = ~entries,
          type = "scatter",
          mode = "lines+markers",
          line = list(color = "rgba(0, 100, 200, 0.8)", width = 2),
          marker = list(color = "rgba(0, 100, 200, 1)", size = 6),
          hovertemplate = "%{x|%Y-%m-%d}<br>Entries: %{y}<extra></extra>"
        ) %>%
          plotly::layout(
            title = "Data Entry Timeline (Last 30 Days)",
            xaxis = list(title = "Date"),
            yaxis = list(title = "Number of Entries"),
            showlegend = FALSE,
            hovermode = "closest"
          )
      }
    })

    # Missing data table
    output$missing_data_table <- DT::renderDataTable({
      data <- quality_data()
      if (is.null(data) || nrow(data$missing_summary) == 0) {
        data.frame(
          Field = character(0),
          Total = integer(0),
          Missing = integer(0),
          `Missing %` = numeric(0)
        )
      } else {
        df <- data$missing_summary
        df$missing_pct <- round(100 * df$missing / df$total_fields, 1)

        df_display <- data.frame(
          Field = df$field_name,
          Total = df$total_fields,
          Missing = df$missing,
          Missing_Pct = paste0(df$missing_pct, "%"),
          stringsAsFactors = FALSE
        )

        DT::datatable(
          df_display,
          options = list(
            pageLength = 10,
            dom = "ftp",
            columnDefs = list(
              list(targets = 0, className = "text-left"),
              list(targets = 1:3, className = "text-right")
            )
          ),
          rownames = FALSE,
          selection = "none"
        ) %>%
          DT::formatStyle(
            "Missing_Pct",
            background = DT::styleInterval(
              c(50, 80),
              c("white", "lightyellow", "lightsalmon")
            )
          )
      }
    })

    # QC Flags
    output$qc_flags_container <- renderUI({
      data <- quality_data()
      if (is.null(data)) {
        p("Unable to load QC status", class = "text-danger")
      } else {
        flagStatus <- if (data$flagged_records == 0) {
          div(
            class = "alert alert-success",
            icon("check-circle-fill"),
            " No quality flags - all data on track!"
          )
        } else {
          div(
            class = "alert alert-warning",
            icon("exclamation-triangle"),
            sprintf(" %d records flagged for review",
              data$flagged_records)
          )
        }

        # Summary statistics
        summary_stats <- div(
          class = "row mt-3",
          div(
            class = "col-md-6",
            h5("Data Entry Stats"),
            tags$ul(
              tags$li(
                sprintf("Enrollment Rate: %d subjects",
                  data$total_records)
              ),
              tags$li(
                sprintf("Completion Rate: %.1f%%",
                  if (data$total_records > 0) {
                    100 * data$complete_records / data$total_records
                  } else {
                    0
                  })
              ),
              tags$li(
                sprintf("Data Quality Score: %.1f%%",
                  100 - data$incomplete_pct)
              )
            )
          ),
          div(
            class = "col-md-6",
            h5("Recommended Actions"),
            tags$ul(
              if (data$incomplete_pct > 20) {
                tags$li("Follow up on incomplete records")
              },
              if (data$flagged_records > 0) {
                tags$li("Review flagged records for discrepancies")
              },
              if (data$incomplete_pct <= 10) {
                tags$li("Continue current data entry pace")
              }
            )
          )
        )

        tagList(flagStatus, summary_stats)
      }
    })

    # Return reactive for parent access
    list(
      quality_data = quality_data
    )
  })
}
