# Export Center: real export of this study's data_entries, via
# zzedc:::flatten_crf_entries_for_export() (one form, wide) and
# zzedc:::flatten_all_entries_for_explorer() (all forms, long).
# Replaces the previous demo scaffold, whose export options (Patient
# Demographics, Adverse Events, batch export, templates, export
# history) referred to nothing that exists in this application's
# schema and, for CSV/Excel, silently generated random numbers
# instead of exporting anything real.
output$export <- renderUI({
  fluidPage(
    titlePanel("Data Export Center"),
    fluidRow(
      column(4,
        wellPanel(
          h4("Export Options"),
          uiOutput("export_form_select"),
          selectInput("export_format", "Format:",
                      choices = c("CSV" = "csv", "Excel (XLSX)" = "xlsx"),
                      selected = "csv"),
          dateRangeInput("export_date_range", "Date Range:",
                         start = Sys.Date() - 365, end = Sys.Date()),
          p(class = "small text-muted",
            paste("Choosing one form exports its fields as columns.",
                  "\"All forms (combined)\" exports every entry in one",
                  "table, with each entry's field values collapsed into",
                  "one readable column, since different forms have",
                  "different fields.")),
          downloadButton("download_export", "Download Export",
                         class = "btn-success")
        )
      ),
      column(8,
        wellPanel(
          h4("Preview"),
          verbatimTextOutput("export_preview_info"),
          br(),
          DT::DTOutput("export_preview_table")
        )
      )
    )
  )
})

output$export_form_select <- renderUI({
  shiny::req(db_pool)
  forms <- zzedc:::get_active_crf_forms(db_pool)
  choices <- c("All forms (combined)" = "__all__",
               stats::setNames(forms$crf_code, forms$crf_name))
  selectInput("export_form", "Form:", choices = choices)
})

export_data <- reactive({
  shiny::req(db_pool, input$export_form, input$export_date_range)
  if (input$export_form == "__all__") {
    all_entries <- zzedc:::flatten_all_entries_for_explorer(db_pool)
    all_entries[
      as.Date(all_entries$created_date) >= input$export_date_range[1] &
        as.Date(all_entries$created_date) <= input$export_date_range[2],
    ]
  } else {
    zzedc:::flatten_crf_entries_for_export(
      db_pool, input$export_form,
      start_date = input$export_date_range[1],
      end_date = input$export_date_range[2]
    )
  }
})

output$export_preview_info <- renderText({
  data <- export_data()
  paste(
    paste("Form:", if (input$export_form == "__all__") "All forms (combined)"
          else input$export_form),
    paste("Rows:", nrow(data)),
    paste("Columns:", ncol(data)),
    sep = "\n"
  )
})

output$export_preview_table <- DT::renderDT({
  data <- export_data()
  preview <- if (nrow(data) > 100) data[seq_len(100), ] else data
  DT::datatable(preview, options = list(scrollX = TRUE, pageLength = 10))
})

output$download_export <- downloadHandler(
  filename = function() {
    form_part <- if (input$export_form == "__all__") "all_forms"
                 else tolower(input$export_form)
    ext <- if (input$export_format == "xlsx") ".xlsx" else ".csv"
    paste0("zzedc_export_", form_part, "_", Sys.Date(), ext)
  },
  content = function(file) {
    data <- export_data()
    if (input$export_format == "xlsx") {
      writexl::write_xlsx(data, file)
    } else {
      utils::write.csv(data, file, row.names = FALSE)
    }
  }
)
