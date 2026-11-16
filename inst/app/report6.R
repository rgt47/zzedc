# Manuscripts Report: tracking ID, title, and status for every
# manuscript entry, read via zzedc:::flatten_crf_entries_for_export()
# (the same helper the Export tab uses), not a new query.
output$rep6 <- renderUI({
  fluidPage(
    titlePanel("Manuscripts"),
    p("Every manuscript entry currently logged, with its status."),
    DT::DTOutput("rep6_table")
  )
})

output$rep6_table <- DT::renderDT({
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

  DT::datatable(display, options = list(pageLength = 10), rownames = FALSE)
})
