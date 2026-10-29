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

# When a study has imported real CRFs (setup_zzedc_from_gsheets() or
# the CSV path), crf_definitions/designer_fields hold the actual
# form/field definitions. Previously nothing in edc.R ever read
# these tables; the EDC tab only ever rendered the demo forms/*.R
# scaffold, regardless of what had been imported. This path takes
# priority over both the demo scaffold and the "forms not found"
# notice below, since real imported forms are always preferable to
# demo content when they exist. See R/edc_dynamic_forms.R.
.zzedc_crf_forms <- function() {
  if (!exists("db_pool", envir = globalenv())) return(NULL)
  tryCatch({
    forms <- zzedc:::get_active_crf_forms(get("db_pool", envir = globalenv()))
    if (nrow(forms) == 0) NULL else forms
  }, error = function(e) NULL)
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
          tags$code(.zzedc_work_dir()),
          ") and reload the app, or see the ",
          tags$em("Setup Wizard"),
          " under the Reports menu to scaffold them.")
      )
    )
  )
}

.zzedc_crf_dynamic_panel <- function(forms) {
  choices <- stats::setNames(as.character(forms$crf_id), forms$crf_name)
  fluidPage(
    fluidRow(
      column(2,
        wellPanel(
          tags$img(src = paste0(shiny::isolate(user_input$username),".jpg"),
                   width = "80px"),
          br(), br(), hr(),
          textOutput("usr"),
          hr(),
          selectInput("edc_crf_form", "Form", choices = choices)
        )
      ),
      column(7,
        uiOutput("edc_crf_fields"),
        actionButton("submitcrf", "Submit entry",
                     class = "btn btn-primary mt-3"),
        shinyjs::hidden(div(id = "crf_results",
                            class = "alert alert-success mt-3",
                            "Entry saved."))
      ),
      column(3,
        textOutput("crf_messages"),
        DT::dataTableOutput("crf_entries_table")
      )
    )
  )
}

output$ui <- renderUI({
  if (user_input$authenticated == FALSE) {
    fluidPage(uiOutput("uiLogin"))
  } else if (!is.null(.zzedc_crf_forms())) {
    .zzedc_crf_dynamic_panel(.zzedc_crf_forms())
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
output$crf_messages <- renderText({"Messages"})

output$edc_crf_fields <- renderUI({
  shiny::req(input$edc_crf_form)
  metadata <- zzedc:::get_crf_field_metadata(db_pool, as.integer(input$edc_crf_form))
  if (length(metadata) == 0) {
    return(div(class = "text-muted", "This form has no fields defined."))
  }
  shiny::tagList(renderPanel(names(metadata), metadata))
})

observeEvent(input$submitcrf, {
  shiny::req(input$edc_crf_form)
  crf_id <- as.integer(input$edc_crf_form)
  forms <- zzedc:::get_active_crf_forms(db_pool)
  crf_row <- forms[forms$crf_id == crf_id, , drop = FALSE]
  if (nrow(crf_row) == 0) return(invisible(NULL))

  metadata <- zzedc:::get_crf_field_metadata(db_pool, crf_id)
  field_codes <- names(metadata)
  field_data <- stats::setNames(lapply(field_codes, function(f) {
    v <- input[[f]]
    if (is.null(v)) NA_character_
    else if (inherits(v, "Date")) format(v)
    else as.character(v)
  }), field_codes)

  missing_required <- vapply(field_codes, function(f) {
    isTRUE(metadata[[f]]$required) &&
      (is.na(field_data[[f]]) || !nzchar(trimws(field_data[[f]])))
  }, logical(1))
  if (any(missing_required)) {
    missing_labels <- vapply(metadata[missing_required], function(m) m$label,
                              character(1))
    shiny::showNotification(
      paste("Missing required field(s):", paste(missing_labels, collapse = ", ")),
      type = "error", duration = 8
    )
    return(invisible(NULL))
  }

  # input$username is only the login form's own text box; the real
  # logged-in identity is set on the user_input reactiveValues by
  # auth.R at login (same source forms/save.R's saveData() already
  # reads for the demo-scaffold path -- see auth.R:76).
  username <- shiny::isolate(user_input$username)
  created_by <- if (!is.null(username) && nzchar(username)) {
    as.character(username)
  } else {
    "unknown"
  }

  result <- zzedc:::save_crf_entry(db_pool, crf_row$crf_code[1], field_data,
                                    created_by = created_by)
  if (isTRUE(result$success)) {
    shiny::showNotification(
      sprintf("Entry saved (%s, %s).", crf_row$crf_name[1], result$entry_id),
      type = "message", duration = 5
    )
    shinyjs::show("crf_results")
  } else {
    shiny::showNotification(
      paste("Database error saving entry:", result$error),
      type = "error", duration = 10
    )
  }
})

output$crf_entries_table <- DT::renderDataTable({
  shiny::req(input$edc_crf_form)
  forms <- zzedc:::get_active_crf_forms(db_pool)
  crf_row <- forms[forms$crf_id == as.integer(input$edc_crf_form), , drop = FALSE]
  if (nrow(crf_row) == 0) return(NULL)
  rows <- DBI::dbGetQuery(
    db_pool,
    "SELECT subject_id, created_date FROM data_entries WHERE form_name = ? ORDER BY created_date DESC",
    params = list(tolower(crf_row$crf_code[1]))
  )
  DT::datatable(rows, options = list(pageLength = 5), rownames = FALSE)
})

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
  # input$username is only the login form's own text box, not the
  # logged-in identity (set on user_input by auth.R at login); it
  # renders blank once the login modal closes. Confirmed empirically
  # testing the dynamic CRF panel's sidebar against the live app.
  username <- req(user_input$username, cancelOutput = TRUE)
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












 
      

    




