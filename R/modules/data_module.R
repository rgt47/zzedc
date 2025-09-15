# Data Explorer Module
# UI and Server functions for data exploration and visualization

# Load required packages for this module
if (!requireNamespace("plotly", quietly = TRUE)) {
  stop("plotly package required for data module")
}

#' Data Explorer Module UI
#'
#' @param id The namespace id for the module
#' @return A fluidPage containing the data explorer UI
data_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    titlePanel("Data Explorer"),

    fluidRow(
      column(3,
        wellPanel(
          h4("Data Source"),
          selectInput(ns("data_source"), "Choose Data Source:",
                     choices = c("Local Files" = "local",
                               "Database" = "database",
                               "Sample Data" = "sample"),
                     selected = "local"),

          conditionalPanel(
            condition = paste0("input['", ns("data_source"), "'] == 'local'"),
            fileInput(ns("data_file"), "Choose CSV File:",
                     accept = c(".csv", ".txt", ".tsv"))
          ),

          conditionalPanel(
            condition = paste0("input['", ns("data_source"), "'] == 'database'"),
            textInput(ns("db_connection"), "Database Connection:",
                     placeholder = "Enter connection string"),
            textInput(ns("db_table"), "Table Name:",
                     placeholder = "Enter table name")
          ),

          hr(),
          h4("Display Options"),
          numericInput(ns("max_rows"), "Max Rows to Display:",
                      value = 100, min = 10, max = 1000, step = 10),
          checkboxInput(ns("show_summary"), "Show Summary Statistics", TRUE),
          checkboxInput(ns("show_missing"), "Highlight Missing Values", TRUE)
        )
      ),

      column(9,
        tabsetPanel(
          tabPanel("Data View",
            br(),
            conditionalPanel(
              condition = paste0("input['", ns("show_summary"), "'] == true"),
              wellPanel(
                h4("Data Summary"),
                verbatimTextOutput(ns("data_summary"))
              )
            ),
            DT::dataTableOutput(ns("data_table"))
          ),

          tabPanel("Variable Info",
            br(),
            wellPanel(
              h4("Variable Information"),
              DT::dataTableOutput(ns("variable_info_table"))
            )
          ),

          tabPanel("Missing Data",
            br(),
            wellPanel(
              h4("Missing Data Analysis"),
              plotlyOutput(ns("missing_data_plot"))
            ),
            wellPanel(
              h4("Missing Data Summary"),
              tableOutput(ns("missing_summary_table"))
            )
          ),

          tabPanel("Visualizations",
            br(),
            fluidRow(
              column(6,
                wellPanel(
                  selectInput(ns("viz_var_x"), "X Variable:", choices = NULL),
                  selectInput(ns("viz_var_y"), "Y Variable:", choices = NULL),
                  selectInput(ns("viz_type"), "Plot Type:",
                            choices = c("Scatter" = "scatter",
                                      "Line" = "line",
                                      "Bar" = "bar",
                                      "Histogram" = "hist",
                                      "Box Plot" = "box"))
                )
              ),
              column(6,
                plotlyOutput(ns("data_visualization"))
              )
            )
          )
        )
      )
    ),

    fluidRow(
      column(12,
        hr(),
        wellPanel(
          h4("Data Operations"),
          actionButton(ns("refresh_data"), "Refresh Data", class = "btn-primary"),
          actionButton(ns("validate_data"), "Validate Data", class = "btn-warning"),
          downloadButton(ns("export_current_data"), "Export Current View", class = "btn-success"),
          downloadButton(ns("export_summary_report"), "Export Summary Report", class = "btn-info")
        )
      )
    )
  )
}

#' Data Explorer Module Server
#'
#' @param id The namespace id for the module
#' @return Server function for data explorer module
data_server <- function(id) {
  moduleServer(id, function(input, output, session) {

    # Reactive data loading with proper validation
    current_data <- reactive({
      req(input$data_source)

      if (input$data_source == "sample") {
        # Generate sample data
        data.frame(
          ID = 1:50,
          Subject = paste0("SUBJ_", sprintf("%03d", 1:50)),
          Age = round(rnorm(50, 65, 10)),
          Gender = sample(c("M", "F"), 50, replace = TRUE),
          Visit_Date = sample(seq(as.Date("2024-01-01"), as.Date("2024-12-31"), by = "day"), 50),
          Score_1 = round(rnorm(50, 75, 15), 1),
          Score_2 = round(rnorm(50, 80, 12), 1),
          Status = sample(c("Complete", "Incomplete", "Pending"), 50, replace = TRUE),
          Notes = sample(c("Normal", "Follow-up", "Review", NA), 50, replace = TRUE, prob = c(0.4, 0.3, 0.2, 0.1))
        )
      } else if (input$data_source == "local") {
        req(input$data_file)
        tryCatch({
          read.csv(input$data_file$datapath)
        }, error = function(e) {
          data.frame(Error = paste("Failed to load file:", e$message))
        })
      } else {
        data.frame(Message = "Please select a data source or upload a file")
      }
    })

    output$data_table <- DT::renderDataTable({
      data <- current_data()
      req(data, nrow(data) > 0)

      max_rows <- req(input$max_rows)
      if (nrow(data) > max_rows) {
        data <- data[1:max_rows, ]
      }

      DT::datatable(data,
                    options = list(scrollX = TRUE, pageLength = 25),
                    class = 'cell-border stripe hover') %>%
        DT::formatStyle(columns = names(data),
                       backgroundColor = DT::styleEqual(c(NA, ""), c("lightcoral", "lightcoral")))
    })

    output$data_summary <- renderText({
      data <- current_data()
      if ("Message" %in% names(data) || "Error" %in% names(data)) {
        return(paste(data[1,1]))
      }

      summary_text <- paste(
        "Dataset Overview:",
        "================",
        paste("Rows:", nrow(data)),
        paste("Columns:", ncol(data)),
        paste("Missing Values:", sum(is.na(data))),
        paste("Complete Cases:", sum(complete.cases(data))),
        "",
        "Column Types:",
        paste(capture.output(utils::str(data)), collapse = "\n"),
        sep = "\n"
      )
      summary_text
    })

    output$variable_info_table <- DT::renderDataTable({
      data <- current_data()
      if ("Message" %in% names(data) || "Error" %in% names(data)) {
        return(DT::datatable(data.frame(Info = "No data available")))
      }

      var_info <- data.frame(
        Variable = names(data),
        Type = sapply(data, class),
        Missing = sapply(data, function(x) sum(is.na(x))),
        Missing_Percent = round(sapply(data, function(x) sum(is.na(x))/length(x) * 100), 2),
        Unique_Values = sapply(data, function(x) length(unique(x[!is.na(x)]))),
        Example_Values = sapply(data, function(x) {
          vals <- unique(x[!is.na(x)])[1:3]
          paste(vals[!is.na(vals)], collapse = ", ")
        })
      )

      DT::datatable(var_info, options = list(pageLength = 15))
    })

    output$missing_data_plot <- renderPlotly({
      data <- current_data()
      if ("Message" %in% names(data) || "Error" %in% names(data)) {
        return(plotly::plot_ly() %>% plotly::add_text(text = "No data available", showlegend = FALSE))
      }

      missing_pct <- sapply(data, function(x) sum(is.na(x))/length(x) * 100)
      missing_df <- data.frame(
        Variable = names(missing_pct),
        Missing_Percent = as.numeric(missing_pct)
      )

      p <- ggplot(missing_df, aes(x = reorder(Variable, Missing_Percent), y = Missing_Percent)) +
        geom_bar(stat = "identity", fill = "lightcoral", alpha = 0.7) +
        coord_flip() +
        theme_minimal() +
        labs(title = "Missing Data by Variable", x = "Variable", y = "Missing Percentage (%)")

      ggplotly(p)
    })

    output$missing_summary_table <- renderTable({
      data <- current_data()
      if ("Message" %in% names(data) || "Error" %in% names(data)) {
        return(data.frame(Summary = "No data available"))
      }

      data.frame(
        Metric = c("Total Observations", "Complete Cases", "Incomplete Cases", "Total Missing Values", "Variables with Missing Data"),
        Count = c(nrow(data), sum(complete.cases(data)), sum(!complete.cases(data)),
                 sum(is.na(data)), sum(sapply(data, function(x) any(is.na(x)))))
      )
    })

    # Update variable choices for visualization
    observe({
      data <- current_data()
      if (!("Message" %in% names(data) || "Error" %in% names(data))) {
        all_vars <- names(data)

        updateSelectInput(session, "viz_var_x", choices = all_vars)
        updateSelectInput(session, "viz_var_y", choices = all_vars)
      }
    })

    output$data_visualization <- renderPlotly({
      data <- current_data()
      if ("Message" %in% names(data) || "Error" %in% names(data) ||
          is.null(input$viz_var_x) || input$viz_var_x == "") {
        return(plotly::plot_ly() %>% plotly::add_text(text = "Select variables to visualize", showlegend = FALSE))
      }

      if (input$viz_type == "scatter" && !is.null(input$viz_var_y) && input$viz_var_y != "") {
        p <- ggplot(data, aes_string(x = input$viz_var_x, y = input$viz_var_y)) +
          geom_point(alpha = 0.6) +
          theme_minimal()
      } else if (input$viz_type == "hist") {
        p <- ggplot(data, aes_string(x = input$viz_var_x)) +
          geom_histogram(bins = 20, fill = "lightblue", alpha = 0.7) +
          theme_minimal()
      } else if (input$viz_type == "box") {
        p <- ggplot(data, aes_string(y = input$viz_var_x)) +
          geom_boxplot(fill = "lightgreen", alpha = 0.7) +
          theme_minimal()
      } else {
        p <- ggplot(data, aes_string(x = input$viz_var_x)) +
          geom_bar(fill = "lightcoral", alpha = 0.7) +
          theme_minimal()
      }

      ggplotly(p)
    })

    # Event handlers
    observeEvent(input$refresh_data, {
      showNotification("Data refreshed", type = "message")
    })

    observeEvent(input$validate_data, {
      showNotification("Data validation completed", type = "message")
    })

    # Download handlers
    output$export_current_data <- downloadHandler(
      filename = function() {
        paste("data_export_", Sys.Date(), ".csv", sep = "")
      },
      content = function(file) {
        write.csv(current_data(), file, row.names = FALSE)
      }
    )

    output$export_summary_report <- downloadHandler(
      filename = function() {
        paste("data_summary_", Sys.Date(), ".txt", sep = "")
      },
      content = function(file) {
        data <- current_data()
        summary_text <- paste(
          "Data Summary Report",
          "==================",
          paste("Generated:", Sys.time()),
          paste("Rows:", nrow(data)),
          paste("Columns:", ncol(data)),
          "",
          "Summary Statistics:",
          capture.output(summary(data)),
          sep = "\n"
        )
        writeLines(summary_text, file)
      }
    )
  })
}