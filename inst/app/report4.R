# Personal Statement: a data-grounded draft summary, in the general
# shape of a promotion self-assessment (research/publications,
# teaching, service), composed entirely from what is currently in
# data_entries via zzedc:::generate_personal_statement_draft(). Not a
# finished document -- see the caveat rendered at the bottom of the
# report itself.
output$rep4 <- renderUI({
  fluidPage(
    titlePanel("Personal Statement (Draft)"),
    p(class = "text-muted",
      paste("Generated from entries currently logged in the tracker.",
            "Regenerates automatically as you add data.")),
    div(class = "card",
      div(class = "card-body", uiOutput("rep4_body"))
    )
  )
})

output$rep4_body <- renderUI({
  shiny::req(db_pool)
  shiny::HTML(zzedc:::generate_personal_statement_draft(db_pool))
})
