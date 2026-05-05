# EDC tab requires three working-directory files:
#   forms/blfieldlist.R   - field list
#   forms/renderpanels.R  - panel renderer
#   forms/save.R          - save handler
# These are study-specific and ship with the user's project, not
# the package. When they are missing, render a friendly setup
# notice instead of failing with "cannot open the connection".

.zzedc_forms_present <- function() {
  all(file.exists(c(
    "forms/blfieldlist.R",
    "forms/renderpanels.R",
    "forms/save.R"
  )))
}

.zzedc_forms_missing_panel <- function() {
  fluidPage(
    div(
      class = "card mt-4",
      style = paste0(
        "max-width: 720px; margin: 2rem auto; ",
        "border-left: 4px solid #b45309 !important;"
      ),
      div(
        class = "card-body",
        h4(class = "mb-3",
           tags$span(style = "color: #b45309;",
                     bsicons::bs_icon("exclamation-triangle-fill")),
           " EDC form configuration not found"),
        p(class = "text-muted",
          "The EDC tab needs three study-specific files in your ",
          "working directory:"),
        tags$ul(
          tags$li(tags$code("forms/blfieldlist.R"),
                  " - the list of fields for each visit"),
          tags$li(tags$code("forms/renderpanels.R"),
                  " - the panel renderer"),
          tags$li(tags$code("forms/save.R"),
                  " - the save handler")
        ),
        p(class = "small text-muted mb-0",
          "These files are part of your protocol setup. Copy ",
          "them into ", tags$code("forms/"),
          " under your launch directory (currently ",
          tags$code(getwd()),
          ") and reload the app, or see the ",
          tags$em("Setup Wizard"),
          " under the Reports menu to scaffold them.")
      )
    )
  )
}

output$ui <- renderUI({
  if (user_input$authenticated == FALSE) {
    fluidPage(uiOutput("uiLogin"))
  } else if (!.zzedc_forms_present()) {
    .zzedc_forms_missing_panel()
  } else {
    fluidPage(
    fluidRow(
      column(2,
    wellPanel(
    tags$img(src = paste0(input$username,".jpg"), width = "80px"),
    br(), br(), hr(),
    textOutput("usr"),
    textOutput("studyid"),
    textOutput("visit"),
    textOutput("form")),
    br(), br(), hr(),
    textOutput("anoth"),
   actionButton("submitanother","Add Visit", class="btn-info" )
 ),
    column(7,
        {
          blfieldlist <- dget('forms/blfieldlist.R')
          renderPanel(blfieldlist)
        }
        ),
    column(3,
           textOutput("messages"),
           hidden(uiOutput("results")),
           tableOutput("val"))))}})

output$messages <- renderText({"Messages"})

# Source the form helpers only when they exist; otherwise the
# missing-forms panel above takes over the EDC tab cleanly.
if (.zzedc_forms_present()) {
  source('forms/renderpanels.R', local=T)[[1]]
}

observeEvent(input$submitvislog, {
        panel = paste0("vis",input.viscode)
#        browser()
        hide("visvl", anim=TRUE, animType='slide', time=1)
        shinyjs::show(panel, anim=FALSE)
#
        saveData(input$formvl)
         })

if (.zzedc_forms_present()) {
  source('forms/save.R', local=T)[[1]]
}

observeEvent(input$submitanother, {
          panel = paste0("vis",input$viscode)
          hide(panel)
          hide("results")
          shinyjs::show("visvl")
        })


output$studyid <- renderText({
  sid <- input$sid
  paste("Study ID:", if (length(sid) > 0) as.character(sid) else "None")
})

output$usr <- renderText({
  username <- req(input$username, cancelOutput = TRUE)
  as.character(username[1])
})

output$visit <- renderText({
  viscode <- input$viscode
  paste("Visit:", if (length(viscode) > 0) as.character(viscode) else "None")
})

output$form <- renderText({
  viscode <- input$viscode
  form_val <- if (length(viscode) > 0) input[[paste0("form", viscode)]] else NULL
  paste("Form:", if (length(form_val) > 0) as.character(form_val) else "None")
})
output$anoth <- renderText({"Enter an additional visit."})












 
      

    




