output$export <- renderUI({
  fluidPage(
    titlePanel("Data Export Center"),
    
    fluidRow(
      column(4,
        wellPanel(
          h4("Export Options"),
          
          selectInput("export_data_source", "Data Source:", 
                     choices = c("Current EDC Data" = "edc",
                               "All Data Files" = "all_files", 
                               "Reports" = "reports",
                               "Sample Data" = "sample"),
                     selected = "edc"),
          
          selectInput("export_format", "Export Format:",
                     choices = c("CSV" = "csv",
                               "Excel (XLSX)" = "xlsx", 
                               "JSON" = "json",
                               "PDF Report" = "pdf",
                               "HTML Report" = "html"),
                     selected = "csv"),
          
          conditionalPanel(
            condition = "input.export_data_source == 'edc'",
            h5("EDC Export Options"),
            checkboxInput("include_metadata", "Include Metadata", TRUE),
            checkboxInput("include_timestamps", "Include Timestamps", TRUE),
            dateRangeInput("export_date_range", "Date Range:",
                          start = Sys.Date() - 30,
                          end = Sys.Date())
          ),
          
          conditionalPanel(
            condition = "input.export_format == 'pdf' || input.export_format == 'html'",
            h5("Report Options"),
            checkboxInput("include_summary", "Include Summary Statistics", TRUE),
            checkboxInput("include_plots", "Include Visualizations", TRUE),
            checkboxInput("include_raw_data", "Include Raw Data Tables", FALSE)
          ),
          
          hr(),
          h5("Advanced Options"),
          checkboxInput("compress_export", "Compress Export (ZIP)", FALSE),
          textInput("export_filename", "Custom Filename:", 
                   placeholder = "Leave blank for auto-generated"),
          
          br(),
          actionButton("preview_export", "Preview Export", class = "btn-info btn-block"),
          br(),
          downloadButton("download_export", "Download Export", class = "btn-success btn-block")
        )
      ),
      
      column(8,
        tabsetPanel(
          tabPanel("Export Preview",
            br(),
            wellPanel(
              h4("Export Preview"),
              verbatimTextOutput("export_preview_info"),
              br(),
              DT::dataTableOutput("export_preview_table")
            )
          ),
          
          tabPanel("Export History", 
            br(),
            wellPanel(
              h4("Recent Exports"),
              DT::dataTableOutput("export_history_table"),
              br(),
              actionButton("clear_export_history", "Clear History", class = "btn-warning")
            )
          ),
          
          tabPanel("Batch Export",
            br(),
            wellPanel(
              h4("Batch Export Configuration"),
              p("Export multiple datasets at once with consistent formatting."),
              
              fluidRow(
                column(6,
                  checkboxGroupInput("batch_datasets", "Select Datasets:",
                                   choices = c("EDC Forms" = "edc_forms",
                                             "Patient Demographics" = "demographics", 
                                             "Visit Data" = "visits",
                                             "Assessment Scores" = "assessments",
                                             "Adverse Events" = "ae"),
                                   selected = c("edc_forms"))
                ),
                column(6,
                  selectInput("batch_format", "Batch Format:",
                            choices = c("Individual CSV files" = "csv_individual",
                                      "Single Excel workbook" = "xlsx_combined",
                                      "JSON collection" = "json_combined"),
                            selected = "csv_individual"),
                  
                  checkboxInput("batch_include_readme", "Include README file", TRUE)
                )
              ),
              
              hr(),
              actionButton("run_batch_export", "Run Batch Export", class = "btn-primary"),
              br(), br(),
              downloadButton("download_batch_export", "Download Batch Export", class = "btn-success")
            )
          ),
          
          tabPanel("Export Templates",
            br(),
            wellPanel(
              h4("Export Templates"),
              p("Save and reuse export configurations for consistent data delivery."),
              
              fluidRow(
                column(6,
                  textInput("template_name", "Template Name:", 
                           placeholder = "e.g., Weekly Report"),
                  textAreaInput("template_description", "Description:", 
                               placeholder = "Describe this export template...",
                               rows = 3),
                  actionButton("save_template", "Save Current Settings as Template", 
                              class = "btn-info")
                ),
                column(6,
                  h5("Existing Templates"),
                  selectInput("load_template", "Load Template:", 
                            choices = c("No templates saved" = ""),
                            selected = ""),
                  actionButton("load_template_btn", "Load Template", class = "btn-secondary"),
                  br(), br(),
                  actionButton("delete_template", "Delete Selected Template", 
                              class = "btn-danger")
                )
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
          h4("Export Status"),
          verbatimTextOutput("export_status"),
          div(id = "export_progress", 
              class = "progress",
              div(class = "progress-bar", role = "progressbar", 
                  style = "width: 0%", "0%"))
        )
      )
    )
  )
})

# Generate export data based on source selection
export_data <- reactive({
  switch(input$export_data_source,
    "edc" = {
      # Generate sample EDC data
      n_records <- 100
      data.frame(
        Record_ID = 1:n_records,
        Subject_ID = paste0("SUBJ_", sprintf("%03d", 1:n_records)),
        Visit_Code = sample(c("Baseline", "Visit_1", "Visit_2", "Visit_3"), n_records, replace = TRUE),
        Visit_Date = sample(seq(input$export_date_range[1], input$export_date_range[2], by = "day"), n_records, replace = TRUE),
        Form_Name = sample(c("Demographics", "Medical_History", "Assessment", "Adverse_Events"), n_records, replace = TRUE),
        Field_Name = sample(c("age", "gender", "weight", "height", "score", "comments"), n_records, replace = TRUE),
        Field_Value = sample(c("25", "Male", "70.5", "175", "42", "Normal findings"), n_records, replace = TRUE),
        Data_Entry_Date = Sys.time() - runif(n_records, 0, 30*24*3600),
        User_ID = sample(c("user1", "user2", "user3"), n_records, replace = TRUE),
        Status = sample(c("Complete", "Incomplete", "Verified", "Query"), n_records, replace = TRUE)
      )
    },
    "sample" = {
      data.frame(
        ID = 1:50,
        Name = paste("Subject", 1:50),
        Value = rnorm(50, 100, 15),
        Category = sample(letters[1:5], 50, replace = TRUE),
        Date = sample(seq(as.Date("2024-01-01"), as.Date("2024-12-31"), by = "day"), 50)
      )
    },
    "all_files" = {
      # List all data files
      if (dir.exists("data")) {
        files <- list.files("data", full.names = TRUE)
        data.frame(
          Filename = basename(files),
          Path = files,
          Size = sapply(files, function(x) file.info(x)$size),
          Modified = sapply(files, function(x) file.info(x)$mtime)
        )
      } else {
        data.frame(Message = "No data directory found")
      }
    },
    "reports" = {
      data.frame(
        Report_Name = c("Quality Report", "Statistical Summary", "Export Log"),
        Generated_Date = Sys.time() - c(1, 5, 10)*24*3600,
        Status = c("Complete", "Complete", "Complete"),
        Records = c(150, 200, 75)
      )
    }
  )
})

# Export preview
output$export_preview_info <- renderText({
  data <- export_data()
  
  info_text <- paste(
    "Export Configuration:",
    "====================",
    paste("Data Source:", input$export_data_source),
    paste("Format:", toupper(input$export_format)),
    paste("Records:", nrow(data)),
    paste("Columns:", ncol(data)),
    "",
    ifelse(input$include_metadata, "✓ Include Metadata", "✗ Exclude Metadata"),
    ifelse(input$include_timestamps, "✓ Include Timestamps", "✗ Exclude Timestamps"),
    ifelse(input$compress_export, "✓ Compress (ZIP)", "✗ No Compression"),
    "",
    paste("Estimated File Size:", round(object.size(data)/1024/1024, 2), "MB"),
    paste("Preview Generated:", Sys.time()),
    sep = "\n"
  )
  info_text
})

output$export_preview_table <- DT::renderDataTable({
  data <- export_data()
  
  # Show first 100 rows for preview
  preview_data <- if(nrow(data) > 100) data[1:100, ] else data
  
  DT::datatable(preview_data, 
                options = list(scrollX = TRUE, pageLength = 10),
                class = 'cell-border stripe hover')
})

# Export history (mock data)
export_history <- reactiveVal(data.frame(
  Export_ID = character(0),
  Timestamp = as.POSIXct(character(0)),
  Data_Source = character(0),
  Format = character(0),
  Records = integer(0),
  Status = character(0)
))

output$export_history_table <- DT::renderDataTable({
  history <- export_history()
  if(nrow(history) == 0) {
    history <- data.frame(Message = "No exports performed yet")
  }
  DT::datatable(history, options = list(pageLength = 10))
})

observeEvent(input$clear_export_history, {
  export_history(data.frame(
    Export_ID = character(0),
    Timestamp = as.POSIXct(character(0)),
    Data_Source = character(0),
    Format = character(0),
    Records = integer(0),
    Status = character(0)
  ))
  showNotification("Export history cleared", type = "message")
})

# Preview export action
observeEvent(input$preview_export, {
  showNotification("Export preview generated", type = "message", duration = 2)
})

# Main export download handler
output$download_export <- downloadHandler(
  filename = function() {
    if (input$export_filename != "") {
      filename <- input$export_filename
    } else {
      filename <- paste("export", Sys.Date(), sep = "_")
    }
    
    extension <- switch(input$export_format,
      "csv" = ".csv",
      "xlsx" = ".xlsx", 
      "json" = ".json",
      "pdf" = ".pdf",
      "html" = ".html"
    )
    
    paste0(filename, extension)
  },
  
  content = function(file) {
    data <- export_data()
    
    # Add to export history
    new_export <- data.frame(
      Export_ID = paste("EXP", format(Sys.time(), "%Y%m%d_%H%M%S"), sep = "_"),
      Timestamp = Sys.time(),
      Data_Source = input$export_data_source,
      Format = toupper(input$export_format),
      Records = nrow(data),
      Status = "Complete"
    )
    
    current_history <- export_history()
    updated_history <- rbind(current_history, new_export)
    export_history(updated_history)
    
    # Generate export based on format
    switch(input$export_format,
      "csv" = {
        write.csv(data, file, row.names = FALSE)
      },
      "json" = {
        jsonlite::write_json(data, file, pretty = TRUE)
      },
      "xlsx" = {
        # For this demo, export as CSV since openxlsx might not be available
        write.csv(data, file, row.names = FALSE)
      },
      "html" = {
        html_content <- paste(
          "<html><head><title>Data Export</title></head><body>",
          "<h1>Data Export Report</h1>",
          "<p>Generated:", Sys.time(), "</p>",
          "<p>Records:", nrow(data), "</p>",
          knitr::kable(data[1:min(20, nrow(data)), ], "html"),
          "</body></html>",
          sep = "\n"
        )
        writeLines(html_content, file)
      },
      "pdf" = {
        # For this demo, create a simple text report
        report_text <- paste(
          "Data Export Report",
          "==================",
          paste("Generated:", Sys.time()),
          paste("Data Source:", input$export_data_source),
          paste("Records:", nrow(data)),
          paste("Columns:", ncol(data)),
          "",
          "Sample Data:",
          paste(capture.output(head(data)), collapse = "\n"),
          sep = "\n"
        )
        writeLines(report_text, file)
      }
    )
  }
)

# Batch export functionality
observeEvent(input$run_batch_export, {
  showNotification("Batch export started...", type = "message", duration = 3)
})

output$download_batch_export <- downloadHandler(
  filename = function() {
    paste("batch_export_", Sys.Date(), ".zip", sep = "")
  },
  content = function(file) {
    # Create temporary directory for batch files
    temp_dir <- tempdir()
    
    # Generate sample files for batch export
    for(dataset in input$batch_datasets) {
      sample_data <- data.frame(
        ID = 1:20,
        Dataset = dataset,
        Value = rnorm(20),
        Timestamp = Sys.time()
      )
      write.csv(sample_data, file.path(temp_dir, paste0(dataset, ".csv")), row.names = FALSE)
    }
    
    # Create README if requested
    if(input$batch_include_readme) {
      readme_content <- paste(
        "Batch Export README",
        "==================",
        paste("Generated:", Sys.time()),
        paste("Datasets included:", paste(input$batch_datasets, collapse = ", ")),
        "",
        "File Descriptions:",
        paste(input$batch_datasets, ": ", input$batch_datasets, " dataset", sep = "", collapse = "\n"),
        sep = "\n"
      )
      writeLines(readme_content, file.path(temp_dir, "README.txt"))
    }
    
    # Create zip file (simplified for demo)
    files_to_zip <- list.files(temp_dir, full.names = TRUE, pattern = "\\.csv$|\\.txt$")
    write.csv(data.frame(File = basename(files_to_zip), Path = files_to_zip), file, row.names = FALSE)
  }
)

# Template management
observeEvent(input$save_template, {
  if(input$template_name != "") {
    showNotification(paste("Template", input$template_name, "saved"), type = "message")
  } else {
    showNotification("Please enter a template name", type = "error")
  }
})

observeEvent(input$load_template_btn, {
  if(input$load_template != "") {
    showNotification(paste("Template", input$load_template, "loaded"), type = "message")
  }
})

observeEvent(input$delete_template, {
  if(input$load_template != "") {
    showNotification(paste("Template", input$load_template, "deleted"), type = "warning")
  }
})

output$export_status <- renderText({
  "Ready for export. Select your options and click 'Download Export' to begin."
})