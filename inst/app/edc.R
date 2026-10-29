# EDC tab requires three working-directory files:
#   forms/blfieldlist.R   - field list
#   forms/renderpanels.R  - panel renderer
#   forms/save.R          - save handler
# These are study-specific and ship with the user's project, not
# the package. When they are missing, render a friendly setup
# notice instead of failing with "cannot open the connection".
#
# shiny::runApp(appDir = ...) (called from launch_zzedc()) keeps the
# Shiny process's working directory set to the installed package's
# app directory for the app's whole lifetime, not the directory the
# user launched from. launch_zzedc() already works around this for
# config.yml/the database path via the ZZEDC_WORK_DIR env var (see
# inst/app/global.R's work_dir/db_path resolution) -- the forms/
# lookups below previously used bare relative paths and so always
# resolved against the wrong (package) directory, making a
# correctly-scaffolded forms/ directory invisible to the EDC tab.

.zzedc_work_dir <- function() {
  Sys.getenv("ZZEDC_WORK_DIR", unset = getwd())
}

.zzedc_forms_path <- function(file) {
  file.path(.zzedc_work_dir(), "forms", file)
}

.zzedc_forms_present <- function() {
  all(file.exists(.zzedc_forms_path(c(
    "blfieldlist.R",
    "renderpanels.R",
    "save.R"
  ))))
}

# blfieldlist is loaded once here (not inside output$ui's renderUI,
# where it previously lived only as a local variable) so that both
# the primary form below and forms/renderpanels.R's output$visvl
# (sourced at top level further down) can see it. Previously
# renderpanels.R referenced blfieldlist from a scope that never had
# it, which would have thrown "object 'blfieldlist' not found" the
# first time the Add Visit panel actually rendered.
if (.zzedc_forms_present()) {
  blfieldlist <- dget(.zzedc_forms_path("blfieldlist.R"))
}

# Tracks which visit is in view. Only one additional visit panel
# ("visvl", from forms/renderpanels.R) is currently scaffolded, so
# this toggles between the primary visit (1) and that one additional
# visit (2) rather than supporting arbitrary added visits.
viscode_rv <- shiny::reactiveVal(1L)

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
          tags$code(.zzedc_work_dir()),
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
        renderPanel(blfieldlist),
        actionButton("submitprimary", "Submit visit",
                     class = "btn btn-primary mt-3"),
        shinyjs::hidden(uiOutput("visvl"))
        ),
    column(3,
           textOutput("messages"),
           hidden(uiOutput("results")),
           tableOutput("val"))))}})

output$messages <- renderText({"Messages"})

# Source the form helpers only when they exist; otherwise the
# missing-forms panel above takes over the EDC tab cleanly.
if (.zzedc_forms_present()) {
  source(.zzedc_forms_path("renderpanels.R"), local=T)[[1]]
}

if (.zzedc_forms_present()) {
  source(.zzedc_forms_path("save.R"), local=T)[[1]]
}

observeEvent(input$submitprimary, {
        # Collects the primary visit form's own fields (blfieldlist's
        # unsuffixed ids), distinct from the "_v2"-suffixed additional-
        # visit panel handled by the submitvislog observer below.
        form_data <- stats::setNames(
          lapply(blfieldlist, function(f) input[[f]]),
          blfieldlist
        )
        saveData(form_data)
        shinyjs::show("results")
         })

observeEvent(input$submitvislog, {
        shinyjs::hide("visvl", anim=TRUE, animType='slide', time=1)
        # visvl_fields is defined alongside output$visvl in
        # forms/renderpanels.R: the additional-visit panel's own
        # field ids (distinct from blfieldlist's, so the two panels
        # don't collide on the same DOM ids when both are present).
        form_data <- stats::setNames(
          lapply(visvl_fields, function(f) input[[f]]),
          visvl_fields
        )
        saveData(form_data)
        shinyjs::show("results")
         })

observeEvent(input$submitanother, {
          viscode_rv(viscode_rv() + 1L)
          shinyjs::hide("results")
          shinyjs::show("visvl", anim=TRUE, animType='slide', time=1)
          shinyjs::disable("submitanother")
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
  paste("Visit:", viscode_rv())
})

output$form <- renderText({
  paste("Form:", if (viscode_rv() > 1) "Additional visit" else "Primary visit")
})
output$anoth <- renderText({"Enter an additional visit."})

output$results <- renderUI({
  div(class = "alert alert-success mt-3", "Visit saved.")
})












 
      

    




