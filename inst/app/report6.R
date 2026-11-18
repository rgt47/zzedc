# Manuscripts Report: tracking ID, title, and status for every
# manuscript entry, read via zzedc:::flatten_crf_entries_for_export()
# (the same helper the Export tab uses), not a new query.
output$rep6 <- renderUI({
  zzedc:::.zzedc_tab_or_login(user_input, function() {
    fluidPage(
      titlePanel("Manuscripts"),
      p("Every manuscript entry currently logged, with its status."),
      DT::DTOutput("rep6_table")
    )
  })
})

output$rep6_table <- DT::renderDT({
  shiny::req(isTRUE(user_input$authenticated))
  shiny::req(db_pool)
  manuscripts <- zzedc:::flatten_crf_entries_for_export(db_pool, "manuscripts")

  cols <- c("tracking_id", "title", "target_journal", "status",
            "submission_date", "acceptance_date", "publication_date", "doi")
  cols <- intersect(cols, names(manuscripts))
  display <- manuscripts[, cols, drop = FALSE]
  names(display) <- c("Tracking ID", "Title", "Target Journal", "Status",
                       "Submission Date", "Acceptance Date",
                       "Publication Date", "DOI")[match(cols, c(
                         "tracking_id", "title", "target_journal", "status",
                         "submission_date", "acceptance_date",
                         "publication_date", "doi"))]

  # Every manuscript row is already individually listed here (unlike
  # the other reports, there is no aggregate count to drill into), so
  # each row's own Review button goes straight to starting a
  # correction request on it -- same report_drill_edit handler as
  # the drill-through modal's row buttons
  # (inst/app/report_drilldown.R). flatten_crf_entries_for_export()
  # does not carry entry_id (it also backs the CSV export, which
  # should not gain an internal id column), so it is read here
  # separately, in the same form/order, for this column alone.
  entries <- zzedc:::get_data_entries(db_pool, crf_code = "manuscripts")
  if (nrow(entries) == nrow(display)) {
    display$Review <- vapply(entries$entry_id, function(eid) {
      paste0(
        '<button class="btn btn-outline-secondary btn-sm" ',
        'onclick="Shiny.setInputValue(\'report_drill_edit\', \'', eid,
        '\', {priority: \'event\'})">Review</button>'
      )
    }, character(1))
  }

  DT::datatable(display, escape = FALSE, rownames = FALSE,
                 options = list(pageLength = 10))
})
