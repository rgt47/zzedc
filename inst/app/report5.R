# Subject case report: every entry, audit event, and signature for one
# subject, written by generate_subject_case_report() (R/subject_case_report.R).
# The report generator records the read in the audit trail under the
# requesting user, so the download is refused without a login.
output$rep5 <- renderUI({
  zzedc:::.zzedc_tab_or_login(user_input, function() {
    fluidPage(
      titlePanel("Subject Case Report"),
      p(class = "text-muted",
        "A complete chronological record for one subject: data entries,",
        "audit events, and electronic signatures."),
      fluidRow(
        column(4, uiOutput("rep5_subject_picker")),
        column(4, radioButtons("rep5_format", "Format",
                               choices = c("Text" = "txt", "JSON" = "json"),
                               inline = TRUE)),
        column(4, br(), downloadButton("rep5_download", "Download report"))
      )
    )
  })
})

output$rep5_subject_picker <- renderUI({
  shiny::req(isTRUE(user_input$authenticated))
  subjects <- tryCatch({
    conn <- zzedc::connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    DBI::dbGetQuery(
      conn,
      "SELECT DISTINCT subject_id FROM data_entries ORDER BY subject_id"
    )$subject_id
  }, error = function(e) character(0))
  selectInput("rep5_subject", "Subject", choices = subjects)
})

output$rep5_download <- downloadHandler(
  filename = function() {
    paste0(gsub("[^A-Za-z0-9_-]", "_", input$rep5_subject %||% "subject"),
           "_case_report.", input$rep5_format %||% "txt")
  },
  content = function(file) {
    if (!isTRUE(user_input$authenticated)) {
      writeLines("Not authenticated.", file)
      return(invisible(NULL))
    }
    res <- zzedc::generate_subject_case_report(
      subject_id  = input$rep5_subject,
      output_file = file,
      format      = input$rep5_format %||% "txt",
      prepared_by = user_input$username %||% "unknown",
      db_path     = db_path
    )
    if (!isTRUE(res$success)) {
      writeLines(paste("Report could not be generated:", res$error), file)
    }
  }
)
