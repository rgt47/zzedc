output$rep1 <- renderUI({
    fluidPage(
sidebarLayout(
  sidebarPanel(
  uiOutput("obs2")),
  mainPanel(
plotOutput(outputId = "distPlot"))))
})      
         

  

  output$obs2 <- renderUI({
    sliderInput("numobs", "Number of observations:", 
                min = 1, max = 1000, value = 500)
  })


  output$distPlot <- renderPlot({
    numobs <- if(!is.null(input$numobs) && is.numeric(input$numobs)) input$numobs else 500
    hist(rnorm(numobs), main = "Sample Distribution")
  })