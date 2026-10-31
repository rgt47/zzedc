# Domain Breakdown: real counts of stored values for every
# choice-type field (Status, Role, Scope, ...) across all forms, via
# zzedc:::summarize_choice_field_values(). Replaces the previous demo
# "Statistical Report" tab, which offered filters over fictional
# categories ("Patient Demographics", "Visit Data", "Assessment
# Scores") not present in this application's schema.
output$htable <- renderUI({
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

.rep3_breakdown <- reactive({
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
  names(tab) <- c("Form", "Field Code", "Field", "Option", "Count")
  DT::datatable(tab, options = list(pageLength = 15), rownames = FALSE)
})
