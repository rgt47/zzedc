# Activity Summary: real entry counts per form, read from
# data_entries via zzedc:::summarize_entries_by_form(). Replaces the
# previous demo histogram of rnorm() draws, which had no connection
# to this application's data.
output$rep1 <- renderUI({
  zzedc:::.zzedc_tab_or_login(user_input, function() {
    fluidPage(
      titlePanel("Activity Summary"),
      p("Entries currently logged in each form, across all time."),
      DT::DTOutput("rep1_table")
    )
  })
})

output$rep1_table <- DT::renderDT({
  shiny::req(isTRUE(user_input$authenticated))
  shiny::req(db_pool)
  summary_df <- zzedc:::summarize_entries_by_form(db_pool)

  # A non-zero Entries count is a button opening the drill-through
  # modal (inst/app/report_drilldown.R) listing that form's entries;
  # a zero count is left as plain text -- nothing to list.
  summary_df$n_entries <- vapply(seq_len(nrow(summary_df)), function(i) {
    n <- summary_df$n_entries[i]
    if (n == 0) return(as.character(n))
    paste0(
      '<button class="btn btn-link p-0" onclick="Shiny.setInputValue(',
      '\'report_drill\', {form: \'', summary_df$crf_code[i],
      '\'}, {priority: \'event\'})">', n, '</button>'
    )
  }, character(1))

  names(summary_df) <- c("Form Code", "Form", "Entries",
                          "First Entry", "Last Entry")
  DT::datatable(summary_df, options = list(
                  pageLength = 10,
                  columnDefs = list(
                    list(targets = 2, searchable = FALSE, orderable = FALSE)
                  )
                ), rownames = FALSE, escape = FALSE)
})
