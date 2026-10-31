# Activity Summary: real entry counts per form, read from
# data_entries via zzedc:::summarize_entries_by_form(). Replaces the
# previous demo histogram of rnorm() draws, which had no connection
# to this application's data.
output$rep1 <- renderUI({
  fluidPage(
    titlePanel("Activity Summary"),
    p("Entries currently logged in each form, across all time."),
    DT::DTOutput("rep1_table")
  )
})

output$rep1_table <- DT::renderDT({
  shiny::req(db_pool)
  summary_df <- zzedc:::summarize_entries_by_form(db_pool)
  names(summary_df) <- c("Form Code", "Form", "Entries",
                          "First Entry", "Last Entry")
  DT::datatable(summary_df, options = list(pageLength = 10), rownames = FALSE)
})
