output$rep2 <- renderUI({
  tagList(
    # Header with breadcrumb
    div(class = "d-flex justify-content-between align-items-center mb-4",
      div(
        h2(tagList(bsicons::bs_icon("shield-check", class = "text-primary"), " Data Quality Report")),
        nav(class = "breadcrumb-container",
          tags$ol(class = "breadcrumb",
            tags$li(class = "breadcrumb-item", tags$a(href = "#", "Reports")),
            tags$li(class = "breadcrumb-item active", "Quality Summary")
          )
        )
      ),
      div(class = "btn-group",
        actionButton("refresh_rep2", "Refresh Data", 
                    class = "btn btn-outline-primary",
                    icon = icon("refresh")),
        downloadButton("download_rep2", "Download Report", 
                      class = "btn-success",
                      icon = icon("download"))
      )
    ),
    
    # Status cards row
    fluidRow(
      column(4,
        bslib::value_box(
          title = "Data Completeness",
          value = "87%",
          showcase = bsicons::bs_icon("check-circle-fill"),
          theme = "success",
          p("of records are complete")
        )
      ),
      column(4,
        bslib::value_box(
          title = "Validation Errors",
          value = "12",
          showcase = bsicons::bs_icon("exclamation-triangle-fill"),
          theme = "warning", 
          p("require attention")
        )
      ),
      column(4,
        bslib::value_box(
          title = "Last Updated",
          value = textOutput("last_updated_rep2"),
          showcase = bsicons::bs_icon("clock-fill"),
          theme = "info",
          p("system refresh")
        )
      )
    ),
    
    # Main content cards
    fluidRow(
      column(6,
        bslib::card(
          full_screen = TRUE,
          bslib::card_header(
            tagList(bsicons::bs_icon("database", class = "text-primary"), " Data Collection Status")
          ),
          bslib::card_body(
            verbatimTextOutput("data_status_rep2")
          )
        )
      ),
      column(6,
        bslib::card(
          full_screen = TRUE,
          bslib::card_header(
            tagList(bsicons::bs_icon("list-check", class = "text-success"), " Validation Summary")
          ),
          bslib::card_body(
            DT::dataTableOutput("validation_summary_rep2")
          )
        )
      )
    ),
    
    # Quality metrics chart
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        tagList(bsicons::bs_icon("graph-up", class = "text-info"), " Data Quality Metrics"),
        class = "d-flex justify-content-between align-items-center"
      ),
      bslib::card_body(
        plotlyOutput("quality_plot_rep2", height = "400px")
      )
    ),
    
    # Additional insights
    fluidRow(
      column(6,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("lightbulb", class = "text-warning"), " Quality Insights")
          ),
          bslib::card_body(
            tags$ul(
              tags$li("Most complete forms: Demographics (98%)"),
              tags$li("Forms needing attention: Adverse Events (76%)"), 
              tags$li("Peak data entry: Tuesday-Thursday"),
              tags$li("Quality score trend: ↗ Improving")
            )
          )
        )
      ),
      column(6,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("gear", class = "text-secondary"), " Report Actions")
          ),
          bslib::card_body(
            div(class = "d-grid gap-2",
              actionButton("detailed_view", "View Detailed Breakdown",
                          class = "btn btn-outline-primary"),
              actionButton("export_issues", "Export Issue List", 
                          class = "btn btn-outline-warning"),
              actionButton("schedule_report", "Schedule Reports",
                          class = "btn btn-outline-info")
            )
          )
        )
      )
    )
  )
})

output$last_updated_rep2 <- renderText({
  format(Sys.time(), "%H:%M")
})

output$data_status_rep2 <- renderText({
  # Check if data directory exists and count files
  if (dir.exists("data")) {
    file_count <- length(list.files("data", pattern = "\\.csv$"))
    paste("Data files found:", file_count, "\nLast updated:", Sys.time())
  } else {
    "No data directory found"
  }
})

output$validation_summary_rep2 <- DT::renderDataTable({
  # Create a simple validation summary
  data.frame(
    Metric = c("Complete Records", "Missing Values", "Validation Errors", "Total Entries"),
    Count = c("87", "13", "12", "100"),
    Percentage = c("87%", "13%", "12%", "100%"),
    Status = c("Good", "Acceptable", "Needs Review", "Total")
  )
}, options = list(dom = 't', pageLength = 10), rownames = FALSE)

output$quality_plot_rep2 <- renderPlotly({
  # Create a simple quality metrics plot
  sample_data <- data.frame(
    Category = c("Complete", "Incomplete", "Pending", "Errors"),
    Count = c(75, 15, 8, 2)
  )
  
  p <- ggplot(sample_data, aes(x = Category, y = Count, fill = Category)) +
    geom_bar(stat = "identity") +
    theme_minimal() +
    labs(title = "Data Quality Overview", x = "Category", y = "Count") +
    scale_fill_brewer(palette = "Set3")
  
  ggplotly(p)
})

observeEvent(input$refresh_rep2, {
  # Refresh logic would go here
  showNotification("Report refreshed", type = "message")
})

output$download_rep2 <- downloadHandler(
  filename = function() {
    paste("quality_report_", Sys.Date(), ".csv", sep = "")
  },
  content = function(file) {
    # Generate sample report data
    report_data <- data.frame(
      Timestamp = Sys.time(),
      Report_Type = "Data Quality",
      Status = "Generated"
    )
    write.csv(report_data, file, row.names = FALSE)
  }
)