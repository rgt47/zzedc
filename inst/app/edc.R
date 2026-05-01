output$ui <- renderUI({
  if (user_input$authenticated == FALSE) {
      fluidPage(uiOutput("uiLogin")
      )
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
source('forms/renderpanels.R', local=T)[[1]]
      
observeEvent(input$submitvislog, {
        panel = paste0("vis",input.viscode) 
#        browser() 
        hide("visvl", anim=TRUE, animType='slide', time=1)
        shinyjs::show(panel, anim=FALSE)
#          
        saveData(input$formvl)
         })
   
source('forms/save.R', local=T)[[1]]
      
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












 
      

    




