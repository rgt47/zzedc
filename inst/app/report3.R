output$htable <- renderUI({
  fluidPage(
    titlePanel("Report 3: Statistical Summary & HTML Table"),
    
    fluidRow(
      column(4,
        wellPanel(
          h4("Filter Options"),
          selectInput("table_var_rep3", "Select Variable:", 
                     choices = c("All Variables" = "all", 
                               "Patient Demographics" = "demo",
                               "Visit Data" = "visit",
                               "Assessment Scores" = "scores"),
                     selected = "all"),
          dateRangeInput("date_range_rep3", "Date Range:",
                        start = Sys.Date() - 30,
                        end = Sys.Date()),
          checkboxInput("include_incomplete_rep3", "Include Incomplete Records", TRUE)
        )
      ),
      column(8,
        wellPanel(
          h4("Data Summary"),
          DT::dataTableOutput("summary_table_rep3")
        )
      )
    ),
    
    fluidRow(
      column(12,
        wellPanel(
          h4("Detailed Statistics"),
          verbatimTextOutput("detailed_stats_rep3")
        )
      )
    ),
    
    fluidRow(
      column(6,
        wellPanel(
          h4("Distribution Plot"),
          plotlyOutput("distribution_plot_rep3")
        )
      ),
      column(6,
        wellPanel(
          h4("Trend Analysis"),
          plotlyOutput("trend_plot_rep3")
        )
      )
    ),
    
    fluidRow(
      column(12,
        hr(),
        actionButton("generate_report_rep3", "Generate Full Report", class = "btn-primary"),
        downloadButton("export_html_rep3", "Export as HTML", class = "btn-info"),
        downloadButton("export_excel_rep3", "Export as Excel", class = "btn-success")
      )
    )
  )
})

output$summary_table_rep3 <- DT::renderDataTable({
  # Generate sample data for the table
  sample_data <- data.frame(
    ID = 1:20,
    Subject_ID = paste0("SUBJ_", sprintf("%03d", 1:20)),
    Visit_Date = seq(from = as.Date("2024-01-01"), by = "week", length.out = 20),
    Status = sample(c("Complete", "Incomplete", "Pending"), 20, replace = TRUE),
    Score = round(rnorm(20, 75, 15), 1),
    Notes = sample(c("Normal", "Follow-up needed", "Review required", ""), 20, replace = TRUE)
  )
  
  # Filter based on user inputs
  if (input$table_var_rep3 != "all") {
    # Apply filtering logic here
  }
  
  DT::datatable(sample_data, 
                options = list(pageLength = 10, scrollX = TRUE),
                class = 'cell-border stripe hover')
})

output$detailed_stats_rep3 <- renderText({
  stats_text <- paste(
    "Summary Statistics:",
    "==================",
    "Total Records: 20",
    "Complete Records: 14 (70%)",
    "Incomplete Records: 4 (20%)", 
    "Pending Records: 2 (10%)",
    "",
    "Score Statistics:",
    "Mean Score: 75.2",
    "Median Score: 76.1", 
    "Standard Deviation: 14.8",
    "Min Score: 45.3",
    "Max Score: 98.7",
    "",
    paste("Last Updated:", Sys.time()),
    sep = "\n"
  )
  stats_text
})

output$distribution_plot_rep3 <- renderPlotly({
  # Generate sample distribution data
  scores <- rnorm(100, 75, 15)
  
  p <- ggplot(data.frame(scores = scores), aes(x = scores)) +
    geom_histogram(bins = 20, fill = "lightblue", color = "darkblue", alpha = 0.7) +
    geom_density(aes(y = ..count..), color = "red", size = 1) +
    theme_minimal() +
    labs(title = "Score Distribution", x = "Score", y = "Frequency")
  
  ggplotly(p)
})

output$trend_plot_rep3 <- renderPlotly({
  # Generate sample trend data
  dates <- seq(from = as.Date("2024-01-01"), by = "week", length.out = 20)
  values <- cumsum(rnorm(20, 2, 5)) + 50
  
  trend_data <- data.frame(Date = dates, Value = values)
  
  p <- ggplot(trend_data, aes(x = Date, y = Value)) +
    geom_line(color = "blue", size = 1) +
    geom_point(color = "darkblue", size = 2) +
    geom_smooth(method = "loess", color = "red", se = TRUE, alpha = 0.3) +
    theme_minimal() +
    labs(title = "Trend Over Time", x = "Date", y = "Value")
  
  ggplotly(p)
})

observeEvent(input$generate_report_rep3, {
  showNotification("Generating comprehensive report...", type = "message", duration = 3)
})

output$export_html_rep3 <- downloadHandler(
  filename = function() {
    paste("statistical_report_", Sys.Date(), ".html", sep = "")
  },
  content = function(file) {
    # Create HTML content
    html_content <- paste(
      "<html><head><title>Statistical Report</title></head>",
      "<body>",
      "<h1>Statistical Summary Report</h1>",
      "<p>Generated on:", Sys.time(), "</p>",
      "<h2>Summary Statistics</h2>",
      "<p>This report contains statistical analysis of the data.</p>",
      "</body></html>",
      sep = "\n"
    )
    writeLines(html_content, file)
  }
)

output$export_excel_rep3 <- downloadHandler(
  filename = function() {
    paste("statistical_data_", Sys.Date(), ".csv", sep = "")
  },
  content = function(file) {
    # Generate sample export data
    export_data <- data.frame(
      Subject_ID = paste0("SUBJ_", sprintf("%03d", 1:20)),
      Visit_Date = seq(from = as.Date("2024-01-01"), by = "week", length.out = 20),
      Score = round(rnorm(20, 75, 15), 1),
      Status = sample(c("Complete", "Incomplete", "Pending"), 20, replace = TRUE)
    )
    write.csv(export_data, file, row.names = FALSE)
  }
)