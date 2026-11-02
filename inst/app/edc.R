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
          # No per-user avatar images are shipped or uploaded
          # anywhere in this app; a `<img src="<username>.jpg">`
          # here always 404s and shows a broken-image icon. A
          # generic person icon needs no such file.
          bsicons::bs_icon("person-circle", size = "4rem"),
          br(), br(), hr(),
          textOutput("usr"),
          hr(),
          # The narrow column(2) width wraps longer form names
          # (e.g. "GRANT_REVIEWS Form", "JOURNAL_REVIEWS Form")
          # across two lines in both the closed control and the
          # open dropdown, since selectInput()'s selectize.js
          # replacement renders as styled divs rather than a native
          # <select> that just truncates. A smaller font keeps every
          # current form name on one line; the dropdown is also
          # allowed to size to its content instead of matching the
          # (narrow) control width.
          tags$style(shiny::HTML(
            "#edc_crf_form + .selectize-control .selectize-input,",
            "#edc_crf_form + .selectize-control .selectize-input > div,",
            "#edc_crf_form + .selectize-control .selectize-dropdown-content .option {",
            "  white-space: nowrap;",
            "  font-size: 0.8rem;",
            "}",
            "#edc_crf_form + .selectize-control .selectize-dropdown {",
            "  width: auto !important;",
            "  min-width: 100%;",
            "}"
          )),
          selectInput("edc_crf_form", "Form", choices = choices)
        )
      ),
      column(7,
        uiOutput("edc_crf_fields"),
        # Live, non-blocking flags: re-renders on every keystroke/
        # selection change via the crf_live_field_data() reactive
        # below, but never disables the fields or the submit button.
        uiOutput("edc_crf_field_flags"),
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
    bsicons::bs_icon("person-circle", size = "4rem"),
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

# The active form's crf_code (e.g. "MANUSCRIPTS"), re-looked-up
# whenever the form selector changes. Shared by the prefill, the
# live-flags reactive, and the submit handler so all three agree on
# which form's tracking-ID convention (if any) applies.
crf_current_code <- reactive({
  shiny::req(input$edc_crf_form)
  forms <- zzedc:::get_active_crf_forms(db_pool)
  row <- forms[forms$crf_id == as.integer(input$edc_crf_form), , drop = FALSE]
  if (nrow(row) == 0) NULL else row$crf_code[1]
})

# Custom field widgets (see R/edc_widget_loader.R for the contract):
# every (form, field, widget) attachment across ALL forms is
# resolved and its server-side logic registered ONCE here, at
# session start, regardless of which form the user has selected --
# shiny::moduleServer() can only be called once per namespace id,
# not re-called every time a field's form becomes active. Each
# widget's trigger UI is instead spliced in reactively, per field,
# in output$edc_crf_fields below, only when that field's form is the
# one currently being rendered.
widget_triggers <- local({
  attachments <- zzedc:::all_widget_attachments(db_pool)
  triggers <- list()
  if (nrow(attachments) > 0) {
    for (i in seq_len(nrow(attachments))) {
      row <- attachments[i, ]
      widget_path <- zzedc:::resolve_widget_module(row$widget_file)
      if (is.null(widget_path)) next
      mod <- zzedc:::load_widget_module(widget_path)
      if (is.null(mod)) next

      mod_id <- zzedc:::widget_module_id(row$field_code)
      mod$widget_server(mod_id, db_pool, session, row$field_code)
      triggers[[row$field_code]] <- mod$widget_ui(mod_id)
    }
  }
  triggers
})

output$edc_crf_fields <- renderUI({
  shiny::req(input$edc_crf_form)
  metadata <- zzedc:::get_crf_field_metadata(db_pool, as.integer(input$edc_crf_form))
  if (length(metadata) == 0) {
    return(div(class = "text-muted", "This form has no fields defined."))
  }
  # tracking_id has no stored per-form default; for manuscripts it
  # is instead pre-filled with the next free PUB-<year>-<n> ID so a
  # fresh form never opens on a blank, easy-to-mistype field. The
  # format rule itself is on the field's hover tooltip only (see the
  # edc_crf_field_flags output below), not permanent on-page text --
  # kept out of the way until someone actually wants it.
  if (!is.null(zzedc:::tracking_id_prefix_for_form(crf_current_code())) &&
        "tracking_id" %in% names(metadata)) {
    metadata$tracking_id$value <- zzedc:::next_manuscript_tracking_id(db_pool)
  }

  field_tags <- renderPanel(names(metadata), metadata)

  # Splice each attached field's trigger UI (built once, above) in
  # right after that field's own rendered block -- working from the
  # end of the field list backwards so each splice's position isn't
  # thrown off by an earlier one.
  widget_fields <- intersect(names(metadata), names(widget_triggers))
  for (fc in rev(widget_fields)) {
    idx <- which(names(metadata) == fc)
    field_tags <- append(field_tags, list(widget_triggers[[fc]]), after = idx)
  }

  shiny::tagList(field_tags)
})

# The current form's field metadata, re-fetched whenever the form
# selector changes. Shared by the live-flags reactive below and the
# submit handler so both build field_data/validate the same way.
crf_field_metadata <- reactive({
  shiny::req(input$edc_crf_form)
  zzedc:::get_crf_field_metadata(db_pool, as.integer(input$edc_crf_form))
})

# Reads every current input value for the active form's fields. This
# reactive re-evaluates on every keystroke/selection change in any of
# those inputs, which is what drives the live flags panel below; it
# is also called (via shiny::isolate()) from the submit handler so
# the two never build field_data two different ways.
crf_live_field_data <- reactive({
  metadata <- crf_field_metadata()
  field_codes <- names(metadata)
  stats::setNames(lapply(field_codes, function(f) {
    v <- input[[f]]
    if (is.null(v)) NA_character_
    else if (inherits(v, "Date")) format(v)
    else as.character(v)
  }), field_codes)
})

# Non-blocking: flags an invalid entry (e.g. a value outside the
# field's defined choice set, or a tracking_id that breaks its
# form's PUB-YYYY-N convention or duplicates another entry's) as
# soon as it is made, but never disables the field or the submit
# button. Required-but-blank fields are deliberately not flagged
# here -- a field simply not filled in yet while the form is in
# progress is not an invalid entry; that check still runs, and
# blocks saving, at submit time below. Rendered in red (not the
# calmer warning yellow used elsewhere) since every flag here is a
# real error, not just an in-progress reminder.
output$edc_crf_field_flags <- renderUI({
  metadata <- crf_field_metadata()
  if (length(metadata) == 0) return(NULL)
  crf_code <- crf_current_code()
  field_data <- crf_live_field_data()

  result <- zzedc:::validate_crf_submission(field_data, metadata, crf_code = crf_code)
  live_errors <- Filter(function(e) e$kind != "required", result$errors)
  if (isTRUE(zzedc:::tracking_id_already_used(db_pool, crf_code, field_data$tracking_id))) {
    live_errors$tracking_id <- list(
      kind = "duplicate",
      message = sprintf('Tracking ID "%s" is already in use', field_data$tracking_id)
    )
  }
  # Every cross-field/range rule authored in this form's data
  # dictionary (dsl_validation_rules, imported from the study's
  # Google Sheet) -- e.g. "acceptance date must be on or after
  # submission date". Supersedes an earlier, manuscripts-only,
  # hand-rolled version of just the one date-order rule: this runs
  # whatever rules the sheet actually defines, for every form, not
  # one hardcoded case.
  live_errors <- utils::modifyList(
    live_errors, zzedc:::validate_dsl_rules(db_pool, crf_code, field_data)
  )

  # Hover tooltip on tracking_id: the field's title attribute is
  # kept in sync with the live error's own message once there is
  # one, as a cue right where the cursor already is, reverting to
  # the format hint once the error clears. Runs every keystroke
  # regardless of whether there are any errors to show, since the
  # title must revert once an error clears. jsonlite::toJSON()
  # quotes/escapes the title safely for embedding in the script --
  # the error message it can carry includes the user's own
  # just-typed tracking_id value, so this is untrusted text, not
  # just the fixed hint string.
  hint <- zzedc:::tracking_id_format_hint(crf_code)
  title_script <- if (!is.null(hint)) {
    tooltip_text <- if (!is.null(live_errors$tracking_id)) {
      live_errors$tracking_id$message
    } else {
      hint
    }
    tags$script(shiny::HTML(sprintf(
      "(function(el) { if (el) el.title = %s; })(document.getElementById('tracking_id'));",
      jsonlite::toJSON(tooltip_text, auto_unbox = TRUE)
    )))
  } else {
    NULL
  }

  if (length(live_errors) == 0) return(title_script)

  # renderPanel() gives both a field's wrapper div AND its actual
  # <input>/<textarea>/<select> the field_code as their id, so a
  # plain "#id" selector matches both and draws two nested outlines.
  # Scoping to the control tags themselves (not the wrapper div)
  # keeps just the one, on the control -- except shiny::dateInput()
  # is the one type that puts its id ONLY on its own wrapper div
  # (confirmed by reading shiny::dateInput()'s source: the id goes
  # on tags$div(...), its inner tags$input() has none), so that one
  # div also needs a scoped rule, via its own "shiny-date-input"
  # class rather than its id alone -- renderPanel()'s outer wrapper
  # div (which does share the id) has no such class, so this still
  # can't double up on a date field either.
  outline_css <- paste(
    sprintf(
      paste(
        "input#%1$s, textarea#%1$s, select#%1$s, div.shiny-date-input#%1$s",
        "{ outline: 2px solid #dc3545; outline-offset: 2px; border-radius: 4px; }"
      ),
      names(live_errors)
    ),
    collapse = "\n"
  )
  messages <- vapply(live_errors, function(e) e$message, character(1))

  shiny::tagList(
    title_script,
    tags$style(shiny::HTML(outline_css)),
    div(class = "alert alert-danger py-2 px-3 mt-2 mb-0",
        style = "font-size: 0.85em;",
        tags$ul(class = "mb-0 ps-3", lapply(messages, tags$li)))
  )
})

# Bumped on every successful save so crf_entries_table (below) picks
# up the new row immediately; the table otherwise only reacts to the
# form selector, not to data_entries changing underneath it.
crf_entries_refresh <- reactiveVal(0)

observeEvent(input$submitcrf, {
  shiny::req(input$edc_crf_form)
  crf_id <- as.integer(input$edc_crf_form)
  forms <- zzedc:::get_active_crf_forms(db_pool)
  crf_row <- forms[forms$crf_id == crf_id, , drop = FALSE]
  if (nrow(crf_row) == 0) return(invisible(NULL))

  metadata <- shiny::isolate(crf_field_metadata())
  field_data <- shiny::isolate(crf_live_field_data())
  crf_code <- crf_row$crf_code[1]

  check <- zzedc:::validate_crf_submission(field_data, metadata, crf_code = crf_code)
  if (isTRUE(zzedc:::tracking_id_already_used(db_pool, crf_code, field_data$tracking_id))) {
    check$errors$tracking_id <- list(
      kind = "duplicate",
      message = sprintf('Tracking ID "%s" is already in use', field_data$tracking_id)
    )
  }
  # Every active rule from this form's data dictionary
  # (dsl_validation_rules) -- the same check the live flags above
  # already run, applied once more as the actual gate: a cross-field
  # rule could in principle pass live (both dates filled in validly)
  # and only fail here if the two reactives raced, so this is not
  # purely redundant with the live view.
  check$errors <- utils::modifyList(
    check$errors, zzedc:::validate_dsl_rules(db_pool, crf_code, field_data)
  )
  check$valid <- length(check$errors) == 0
  if (!check$valid) {
    messages <- vapply(check$errors, function(e) e$message, character(1))
    shiny::showNotification(
      paste(messages, collapse = "; "),
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
    crf_entries_refresh(crf_entries_refresh() + 1)
    # The just-saved tracking_id is now taken, so a plain blank
    # reset would invite the next entry to collide with it; recompute
    # the next free id (same convention used to prefill the form
    # originally) instead, for forms that have one.
    if (!is.null(zzedc:::tracking_id_prefix_for_form(crf_code)) &&
          "tracking_id" %in% names(metadata)) {
      metadata$tracking_id$value <- zzedc:::next_manuscript_tracking_id(db_pool)
    }
    zzedc:::reset_crf_field_inputs(session, metadata)
  } else {
    shiny::showNotification(
      paste("Database error saving entry:", result$error),
      type = "error", duration = 10
    )
  }
})

output$crf_entries_table <- DT::renderDataTable({
  shiny::req(input$edc_crf_form)
  crf_entries_refresh()
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












 
      

    




