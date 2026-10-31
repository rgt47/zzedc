# Data Quality: real required/choice validation results across every
# stored entry, computed by re-running zzedc:::validate_crf_submission()
# (the same check the EDC tab's submit handler uses) against the data
# as actually saved. Replaces the previous demo cards, which showed
# a hardcoded "87% complete" / "12 errors" regardless of what, if
# anything, had been entered.
output$rep2 <- renderUI({
  fluidPage(
    div(class = "d-flex justify-content-between align-items-center mb-4",
      h2(tagList(bsicons::bs_icon("shield-check", class = "text-primary"),
                 " Data Quality Report"))
    ),
    fluidRow(
      column(4,
        bslib::value_box(
          title = "Total Entries",
          value = textOutput("rep2_total"),
          showcase = bsicons::bs_icon("database-fill"),
          theme = "primary"
        )
      ),
      column(4,
        bslib::value_box(
          title = "Entries With No Issues",
          value = textOutput("rep2_valid"),
          showcase = bsicons::bs_icon("check-circle-fill"),
          theme = "success"
        )
      ),
      column(4,
        bslib::value_box(
          title = "Flagged Fields",
          value = textOutput("rep2_flagged"),
          showcase = bsicons::bs_icon("exclamation-triangle-fill"),
          theme = "warning"
        )
      )
    ),
    uiOutput("rep2_unknown_form_note"),
    h4("Flagged Entries", class = "mt-4"),
    p(class = "text-muted small",
      paste("A \"required\" flag means a required field was blank at",
            "save time; an \"invalid_choice\" flag means a stored",
            "value is not one of the field's current options (for",
            "example if the field's choice list changed after the",
            "entry was saved).")),
    DT::DTOutput("rep2_flagged_table")
  )
})

.rep2_quality <- reactive({
  shiny::req(db_pool)
  zzedc:::compute_data_quality_summary(db_pool)
})

output$rep2_total <- renderText({ as.character(.rep2_quality()$total) })
output$rep2_valid <- renderText({ as.character(.rep2_quality()$n_valid) })
output$rep2_flagged <- renderText({
  q <- .rep2_quality()
  as.character(q$n_required_missing + q$n_invalid_choice)
})

output$rep2_unknown_form_note <- renderUI({
  q <- .rep2_quality()
  if (q$n_unknown_form == 0) return(NULL)
  div(class = "alert alert-secondary mt-3",
      sprintf(
        paste("%d additional entr%s exist for a form that is not",
              "currently defined (for example a leftover from",
              "before this study's forms were imported) and are",
              "excluded from the counts above."),
        q$n_unknown_form, if (q$n_unknown_form == 1) "y" else "ies"
      ))
})

output$rep2_flagged_table <- DT::renderDT({
  flagged <- .rep2_quality()$flagged
  names(flagged) <- c("Entry ID", "Subject ID", "Form", "Kind", "Message")
  DT::datatable(flagged, options = list(pageLength = 10), rownames = FALSE)
})
