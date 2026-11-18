# Domain Breakdown: real counts of stored values for every
# choice-type field (Status, Role, Scope, ...) across all forms, via
# zzedc:::summarize_choice_field_values(). Replaces the previous demo
# "Statistical Report" tab, which offered filters over fictional
# categories ("Patient Demographics", "Visit Data", "Assessment
# Scores") not present in this application's schema.
output$htable <- renderUI({
  zzedc:::.zzedc_tab_or_login(user_input, function() {
    fluidPage(
      titlePanel("Domain Breakdown"),
      p("Counts of entered values for each form's choice-type fields",
        "(Status, Role, Scope, and similar)."),
      fluidRow(
        column(4,
          wellPanel(
            h4("Filter"),
            uiOutput("rep3_form_filter")
          )
        ),
        column(8,
          DT::DTOutput("rep3_table")
        )
      )
    )
  })
})

.rep3_breakdown <- reactive({
  # Gates both rep3_form_filter and rep3_table at once.
  shiny::req(isTRUE(user_input$authenticated))
  shiny::req(db_pool)
  zzedc:::summarize_choice_field_values(db_pool)
})

output$rep3_form_filter <- renderUI({
  forms <- sort(unique(.rep3_breakdown()$crf_code))
  selectInput("rep3_form", "Form:", choices = c("All forms", forms))
})

output$rep3_table <- DT::renderDT({
  tab <- .rep3_breakdown()
  if (!is.null(input$rep3_form) && input$rep3_form != "All forms") {
    tab <- tab[tab$crf_code == input$rep3_form, ]
  }

  # Each count opens the drill-through modal filtered to this form
  # AND this field's raw stored value (option_value, not
  # option_label -- entries store the raw value).
  count_col <- vapply(seq_len(nrow(tab)), function(i) {
    paste0(
      '<button class="btn btn-link p-0" onclick="Shiny.setInputValue(',
      '\'report_drill\', {form: \'', tab$crf_code[i],
      '\', field: \'', tab$field_code[i],
      '\', value: \'', tab$option_value[i],
      '\'}, {priority: \'event\'})">', tab$n[i], '</button>'
    )
  }, character(1))

  display <- tab[, c("crf_code", "field_code", "field_label", "option_label")]
  display$Count <- count_col
  names(display) <- c("Form", "Field Code", "Field", "Option", "Count")
  DT::datatable(display, options = list(
                  pageLength = 15,
                  columnDefs = list(
                    list(targets = 4, searchable = FALSE, orderable = FALSE)
                  )
                ), rownames = FALSE, escape = FALSE)
})
