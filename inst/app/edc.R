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
    # Styling for renderPanel()'s per-field hint/error icon (see
    # R/renderpanels.R's `<field>__hint_icon` span). Injected inline
    # here, not via www/style.css, since that file is .Rbuildignore'd
    # out of the installed package (confirmed: a live deployment's
    # request for /style.css 404s) and so never actually reaches a
    # running app -- the same inline-tags$style() pattern already
    # used a few lines down for #edc_crf_form's selectize sizing.
    tags$style(shiny::HTML(
      # 320px caps the wrapper at shiny's own default input width
      # (.shiny-input-container is 300px; confirmed via the rendered
      # DOM) plus a little clearance for the icon -- otherwise the
      # wrapper div stretches to the full (much wider) column, and
      # an icon pinned to *its* right edge lands far past the actual
      # input box instead of beside it. A field type whose own
      # widget renders wider than 300px (e.g. a long textarea) will
      # still have the icon sit at 320px rather than past its true
      # right edge; no worse than not having a cap at all, and the
      # common text/numeric/select/date fields are the common case.
      ".form-field-wrapper { position: relative; max-width: 320px;",
      "  padding-right: 22px; }",
      ".field-hint-icon { position: absolute; top: 2px; right: 2px;",
      "  cursor: help; color: #6c757d; }",
      ".field-hint-icon__error { display: none; color: #dc3545; }",
      ".field-hint-icon--error .field-hint-icon__info { display: none; }",
      ".field-hint-icon--error .field-hint-icon__error { display: inline; }",
      # Custom tooltip bubble, not a native `title` attribute: a
      # browser's own hover-tooltip delay is an OS/browser default
      # (Chrome is roughly 800ms) with no CSS/JS hook to shorten it.
      # Reading content live off `data-tooltip` (kept in sync by the
      # live-flags script below) gets a tooltip whose appear delay
      # IS controllable -- set to 400ms here, half that ~800ms
      # baseline, per request. `:not([data-tooltip=\"\"])` keeps a
      # field with nothing to say from popping an empty bubble.
      ".field-hint-icon:not([data-tooltip='']) { position: absolute; }",
      ".field-hint-icon:not([data-tooltip=''])::after {",
      "  content: attr(data-tooltip); position: absolute; top: 100%;",
      "  right: 0; margin-top: 4px; background: #1f2937; color: #fff;",
      "  padding: 4px 8px; border-radius: 4px; font-size: 0.78rem;",
      "  line-height: 1.3; white-space: normal; width: max-content;",
      "  max-width: 260px; opacity: 0; visibility: hidden;",
      "  transition: opacity 0.1s ease; pointer-events: none; z-index: 1000;",
      "}",
      ".field-hint-icon:not([data-tooltip='']):hover::after {",
      "  opacity: 1; visibility: visible; transition-delay: 0.4s;",
      "}",
      # Click-to-pin, in addition to hover: a tap on a touch device
      # has no hover state at all, so hover-only would leave the
      # tooltip unreachable there. Shown with no delay (0s) once
      # pinned, since a click is a deliberate request to see it now.
      ".field-hint-icon--pinned:not([data-tooltip=''])::after {",
      "  opacity: 1; visibility: visible; transition-delay: 0s;",
      "}"
    )),
    # One-time, document-level click handler (event delegation, not
    # a per-icon listener: the field list can be re-rendered on form
    # switch, and delegation keeps working for icons that don't
    # exist yet at the time this script runs). Clicking a hint icon
    # toggles its tooltip pinned open; clicking anything else, or a
    # second click on the same icon, closes whichever one is pinned.
    # Only one is ever pinned at a time. An icon with
    # data-has-detail="true" (R/renderpanels.R) instead asks the
    # server to open a modal with its full-page help_detail content
    # (see the field_help_detail_click observer below) -- the detail
    # text itself was never sent to the browser, so the click can
    # only request it, not toggle a pin it doesn't have.
    tags$script(shiny::HTML(
      "document.addEventListener('click', function(e) {",
      "  var icon = e.target.closest('.field-hint-icon');",
      "  document.querySelectorAll('.field-hint-icon--pinned').forEach(function(el) {",
      "    if (el !== icon) el.classList.remove('field-hint-icon--pinned');",
      "  });",
      "  if (icon && icon.getAttribute('data-has-detail') === 'true') {",
      "    var fieldCode = icon.id.replace(/__hint_icon$/, '');",
      "    Shiny.setInputValue('field_help_detail_click', fieldCode, {priority: 'event'});",
      "    e.stopPropagation();",
      "  } else if (icon) {",
      "    icon.classList.toggle('field-hint-icon--pinned');",
      "    e.stopPropagation();",
      "  }",
      "});"
    )),
    fluidRow(
      column(2,
        wellPanel(
          # No photo is collected or stored for any user (see
          # R/user_avatar.R) -- an initials circle, colored
          # deterministically per user, replaces the old generic
          # bsicons::bs_icon("person-circle") placeholder.
          zzedc:::user_avatar_tag(user_input$full_name, user_input$username),
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
        # Only meaningful on the Screening form -- rendered server-side
        # (output$randomize_subject_btn_ui below) so it only appears
        # there, instead of on every form with a "this doesn't apply
        # here" toast as its only gate.
        uiOutput("randomize_subject_btn_ui", inline = TRUE),
        uiOutput("crf_draft_banner"),
        # Double-data-entry banner/button gating (see
        # output$dde_form_banner and output$savedraftcrf_ui below):
        # "Save and Finish Later" is a second route to a complete row
        # that would skip DDE's group-linking and item-level diff
        # entirely (db_update_incomplete_data_entry(is_complete = TRUE)
        # never runs through save_crf_entry()'s DDE path), so it is
        # replaced by a server-rendered control that hides itself for
        # any form with at least one require_double_entry field,
        # rather than a static actionButton.
        uiOutput("dde_form_banner"),
        # Shown only when this entry would enroll a new subject whose
        # site cannot be decided otherwise (output$enroll_site_ui).
        uiOutput("enroll_site_ui"),
        actionButton("submitcrf", "Submit entry",
                     class = "btn btn-primary mt-3"),
        uiOutput("savedraftcrf_ui"),
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
  } else if (isTRUE(user_input$must_change_password)) {
    # Blocks both the dynamic CRF panel and the demo-forms-scaffold
    # branch below until the user replaces a password someone else
    # chose for them (initial setup, an admin reset, or an admin
    # directly setting one) -- see R/change_password_module.R and
    # the change_password_server() call below.
    zzedc:::change_password_ui("change_password")
  } else if (!is.null(.zzedc_crf_forms())) {
    .zzedc_crf_dynamic_panel(.zzedc_crf_forms())
  } else if (!.zzedc_forms_present()) {
    .zzedc_forms_missing_panel()
  } else {
    fluidPage(
    fluidRow(
      column(2,
    wellPanel(
    zzedc:::user_avatar_tag(user_input$full_name, user_input$username),
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

# The same salt rule login uses (zzedc::resolve_auth_salt()): a changed
# password must be hashed exactly the way login will verify it, or the
# user would be locked out by their own password change.
.edc_auth_salt <- zzedc::resolve_auth_salt(cfg)

zzedc:::change_password_server(
  "change_password", db_pool, user_input, salt = .edc_auth_salt,
  min_length = if (!is.null(cfg$security$password_min_length)) {
    cfg$security$password_min_length
  } else {
    8
  }
)

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

# Tracks which crf_id output$edc_crf_fields last actually rendered,
# so that reactive can tell a same-form re-render (a Display
# preference change below, or the post-Randomize randomize_refresh()
# bump above) apart from a real form switch or the very first
# render. Only the former should have its on-screen values snapshotted
# and restored (see output$edc_crf_fields below) -- restoring onto a
# genuine form switch would carry one form's leftover input values
# onto an unrelated form's fields, and restoring on first render
# would overwrite this function's own tracking_id/randomization_group
# prefills with nothing.
last_rendered_crf_id <- shiny::reactiveVal(NULL)

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

  # Treatment arm is never user-entered (see R/randomization_module.R):
  # randomization_group is a readonly_display field (R/renderpanels.R)
  # showing whatever randomize_next_subject() has already recorded
  # for this subject_id. Only randomize_refresh() (bumped after a
  # successful Randomize click) should invalidate this -- reading
  # input$subject_id directly, without isolate(), would make this
  # entire renderUI (which also renders the subject_id field itself)
  # re-run on every keystroke there, wiping out whatever the user had
  # just typed before each character could register.
  #
  # The arm itself is only ever shown to a viewer unblinded for this
  # study (zzedc::is_unblinded(), R/authorization.R); a blinded
  # viewer sees only whether randomization has happened, never which
  # arm. get_subject_arm() always returns the real arm -- the gate is
  # applied here, at display time, same as randomize_next_subject().
  if ("randomization_group" %in% names(metadata)) {
    randomize_refresh()
    current_subject_id <- shiny::isolate(input$subject_id)
    arm <- if (!is.null(current_subject_id) && nzchar(current_subject_id)) {
      zzedc::get_subject_arm(db_pool, current_subject_id)
    } else {
      NULL
    }
    unblinded <- zzedc::is_unblinded(
      db_pool, zzedc:::.current_study_id(db_pool),
      shiny::isolate(user_input$user_id)
    )
    metadata$randomization_group$value <- if (is.null(arm)) {
      "Not yet randomized"
    } else if (unblinded) {
      arm$arm_label %||% paste0("Arm ", arm$arm_code)
    } else {
      "Randomized"
    }
  }

  # Part C Display preferences: a session-local setting, read live
  # (not isolate()d) so this renderUI does re-run when the viewer
  # changes either one in the Display popover. See the snapshot/
  # restore block below for why that re-run does not lose whatever
  # the viewer had already typed into this same form.
  display_cols <- display_settings$columns %||% 1L
  display_tmode <- display_settings$tooltip_mode %||% "minimal"

  # This renderUI also re-runs for a Display-preference change or a
  # post-Randomize randomize_refresh() bump, both of which keep the
  # same form on screen -- not just for an actual form switch. A
  # same-form re-run would otherwise silently wipe every value the
  # viewer had already entered (and, for a resumed "Save and Finish
  # Later" draft, risk saving blanks over it on the next save -- see
  # crf_draft() below). Snapshot every field's current value here,
  # before this function's own return value replaces the on-screen
  # inputs, and restore it once the new DOM exists (session$onFlushed,
  # same ordering fill_crf_field_inputs() already needs for the
  # "Continue" draft-resume handler below).
  this_crf_id <- as.integer(input$edc_crf_form)
  prev_crf_id <- shiny::isolate(last_rendered_crf_id())
  same_form_rerender <- !is.null(prev_crf_id) && identical(prev_crf_id, this_crf_id)
  restore_values <- if (same_form_rerender) {
    stats::setNames(
      lapply(names(metadata), function(f) shiny::isolate(input[[f]])),
      names(metadata)
    )
  } else {
    NULL
  }
  resuming_draft <- same_form_rerender && !is.null(shiny::isolate(crf_draft()))

  # Extra per-field UI (custom widgets attached in the Setup
  # designer, `widget_triggers` built once above) is now placed by
  # renderPanel() itself, keyed by field name, rather than spliced in
  # afterwards by position: a positional splice into renderPanel()'s
  # return value is only correct when that list is still one element
  # per field, which `columns > 1` no longer guarantees (it returns
  # one fluidRow() per visual row instead).
  field_tags <- renderPanel(
    names(metadata), metadata,
    columns = display_cols, tooltip_mode = display_tmode,
    extra_tags = widget_triggers
  )

  last_rendered_crf_id(this_crf_id)

  if (!is.null(restore_values)) {
    session$onFlushed(function() {
      zzedc:::fill_crf_field_inputs(session, metadata, restore_values)
      # Re-apply the resumed-draft lock the "Continue" handler below
      # set on the old (now replaced) tracking_id input -- restoring
      # its stored value is not enough on its own, since this is a
      # fresh DOM element that starts enabled again.
      if (resuming_draft &&
          !is.null(zzedc:::crf_subject_key_field(names(metadata)))) {
        shinyjs::disable(zzedc:::crf_subject_key_field(names(metadata)))
      }
    }, once = TRUE)
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

# Field codes on the current form flagged require_double_entry = TRUE
# (R/double_data_entry.R). character(0) for an ordinary, single-keyed
# form -- every DDE-specific branch below is skipped entirely in that
# case, so an unflagged form's submit path is byte-for-byte what it
# was before this feature.
crf_dde_flagged <- reactive({
  zzedc:::flagged_dde_fields(crf_field_metadata())
})

# "Save and Finish Later" would bypass DDE's group-linking and
# item-level diff (see the comment at its call site in the UI above),
# so it is hidden entirely for a flagged form rather than merely
# discouraged -- the savedraftcrf observeEvent below also refuses the
# action server-side, belt-and-suspenders against a crafted
# Shiny.setInputValue('savedraftcrf', 1) bypassing this hidden button.
# A subject's first entry enrolls them at a site (R/subject_sites.R).
# The site is asked for only when the subject ID is new, the user has
# no site, and the study has several: zzedc:::.enrollment_site_choices()
# returns NULL in every other case, and the drop-down is not shown.
output$enroll_site_ui <- renderUI({
  field_data <- crf_live_field_data()
  username <- user_input$username
  choices <- tryCatch(
    zzedc:::.enrollment_site_choices(
      db_pool, zzedc:::crf_subject_key(field_data), username),
    error = function(e) NULL)
  if (is.null(choices)) return(NULL)
  labels <- ifelse(is.na(choices$site_name) | !nzchar(choices$site_name),
                   choices$site_id,
                   paste0(choices$site_name, " (", choices$site_id, ")"))
  selectInput("enroll_site", "Site for this new subject",
              choices = c("Choose a site" = "",
                          stats::setNames(choices$site_id, labels)))
})

output$savedraftcrf_ui <- renderUI({
  if (length(crf_dde_flagged()) > 0) return(NULL)
  actionButton("savedraftcrf", "Save and Finish Later",
               class = "btn btn-outline-secondary mt-3")
})

output$dde_form_banner <- renderUI({
  flagged <- crf_dde_flagged()
  if (length(flagged) == 0) return(NULL)
  div(class = "alert alert-info py-2 px-3 mt-2",
      sprintf(
        paste("This form requires double data entry on %d field(s). It must",
              "be submitted in full (no \"Save and Finish Later\") twice, by",
              "two different users, for the same Subject ID; any difference",
              "on a flagged field is caught immediately on the second",
              "submission."),
        length(flagged)
      ))
})

# Fired by the click handler in .zzedc_crf_dynamic_panel() (above)
# when a field's hint icon has data-has-detail="true". Looks up that
# field's full-page help_detail (never sent to the browser until
# now, unlike the short data-tooltip text) and shows it in a modal.
# shiny::tags$div()'s text content is escaped automatically, so
# sheet-authored help_detail renders as plain text even if it
# happens to contain characters that look like markup -- it is
# someone's data-dictionary prose, not trusted HTML.
observeEvent(input$field_help_detail_click, {
  metadata <- crf_field_metadata()
  field <- metadata[[input$field_help_detail_click]]
  shiny::req(field, field$help_detail)
  shiny::showModal(shiny::modalDialog(
    title = field$label,
    tags$div(style = "white-space: pre-wrap;", field$help_detail),
    easyClose = TRUE,
    size = "l"
  ))
})

# Reads every current input value for the active form's fields. This
# reactive re-evaluates on every keystroke/selection change in any of
# those inputs, which is what drives the live flags panel below; it
# is also called (via shiny::isolate()) from the submit handler so
# the two never build field_data two different ways.
# Bumped on every failed submit attempt so the live-flags panel
# below re-evaluates even when the rejected field's own input value
# hasn't changed (e.g. a duplicate tracking_id: the field was
# prefilled with an ID that was still free when the form opened, but
# another session claimed it before this submit). Without this, the
# duplicate is caught by the submit-time gate and reported only via
# the transient showNotification() toast -- the tracking_id field
# itself stays unmarked, since nothing invalidated
# crf_live_field_data() to re-run tracking_id_already_used() against
# the now-current database state.
# Bumped after a successful Randomize click so output$edc_crf_fields
# (which reads the subject's current arm every time it renders, see
# above) re-fetches rather than showing a stale "Not yet randomized".
randomize_refresh <- shiny::reactiveVal(0)

output$randomize_subject_btn_ui <- renderUI({
  shiny::req(identical(crf_current_code(), "SCREENING"))
  actionButton("randomize_subject_btn", "Randomize Subject",
               class = "btn btn-outline-primary mt-3 mb-2")
})

observeEvent(input$randomize_subject_btn, {
  # Defect 3: same gap as submitcrf above -- this handler had no
  # authentication check of its own, relying entirely on the button
  # not being rendered to an unauthenticated session, which does not
  # stop a crafted Shiny.setInputValue('randomize_subject_btn', 1).
  zzedc::require_authenticated_action(user_input, session, db_path, "randomize a subject")
  # The button only renders on Screening (output$randomize_subject_btn_ui
  # above); this guard is just defense against a stale click landing
  # after the form selector has already switched away from it.
  if (!identical(crf_current_code(), "SCREENING")) {
    shiny::showNotification(
      "Randomization is only available on the Screening form.",
      type = "warning"
    )
    return(invisible(NULL))
  }
  if (is.null(input$subject_id) || !nzchar(input$subject_id)) {
    shiny::showNotification("Enter a Subject ID first.", type = "error")
    return(invisible(NULL))
  }
  if (!identical(input$eligible, "Eligible")) {
    shiny::showNotification(
      "Set Overall Eligibility to \"Eligible\" before randomizing.",
      type = "error"
    )
    return(invisible(NULL))
  }
  result <- zzedc::randomize_next_subject(
    db_pool, subject_id = input$subject_id,
    randomized_by = shiny::isolate(user_input$username) %||% user_input$user_id
  )
  if (isTRUE(result$success)) {
    shiny::showNotification("Subject randomized.", type = "message")
    randomize_refresh(randomize_refresh() + 1)
  } else {
    shiny::showNotification(
      paste("Could not randomize:", result$error), type = "error"
    )
  }
})

crf_submit_attempt <- shiny::reactiveVal(0)

# Set TRUE the first time a submit is rejected on the current form,
# and back to FALSE once that form is successfully saved or the form
# selector changes. Lets the live-flags reactive below switch from
# "don't flag blank required fields, the user hasn't tried to submit
# yet" to "flag them too" after a rejected submit -- the standard
# validate-on-submit-then-live-validate pattern, so a user fixing up
# a rejected entry gets the same inline icon/outline feedback on a
# still-blank required field as on every other kind of error, instead
# of only ever seeing that one via the submit-time toast.
crf_submit_attempted <- shiny::reactiveVal(FALSE)

# NULL when the form currently on screen is a fresh, unsaved entry;
# otherwise list(entry_id=, data=) for an open ("Save and Finish
# Later", is_complete = 0) draft the "Continue" action
# (input$edc_continue_draft below) has loaded for editing. Both
# submitcrf and savedraftcrf below route to
# db_update_incomplete_data_entry() against this entry_id, instead
# of save_crf_entry()'s insert path, whenever this is set -- a second
# save of the same draft is a true update of its one row, never a
# second data_entries row.
crf_draft <- shiny::reactiveVal(NULL)

# NULL except while a second double-data-entry submission has an
# unresolved discrepancy on at least one flagged field and the
# resolution modal (.zzedc_dde_discrepancy_modal() below) is on
# screen: list(group_id=, first_entry_id=, field_data=, first_values=,
# discrepancies=, metadata=, crf_code=, created_by=, ip_address=,
# session_id=). The confirm handler (input$dde_confirm_resolution,
# below) reads this, applies the chosen resolutions, and performs the
# actual insert -- the submit handler itself never inserts a
# discrepant second entry directly.
dde_pending <- shiny::reactiveVal(NULL)

# Builds the resolution modal: one three-way radio choice per
# discrepant flagged field, showing both entries' values -- the first
# point in this entire flow that entry #1's value for a field is ever
# shown to the second enterer, and only for a field already known (by
# the save-time diff) to disagree. Not dismissable by clicking outside
# it (easyClose = FALSE): the design's blinding requirement is that
# entry #2 was keyed with no access to entry #1's values, which a
# cancel-and-silently-rekey-while-now-aware-of-the-mismatch escape
# hatch would partially defeat; the modal itself is also the audit
# trail's own record that this discrepancy was shown and resolved, not
# quietly reloaded away.
.zzedc_dde_discrepancy_modal <- function(discrepancies, metadata) {
  rows <- lapply(names(discrepancies), function(field) {
    label <- metadata[[field]]$label %||% field
    d <- discrepancies[[field]]
    ns_id <- paste0("dde_resolve_", field)
    shiny::wellPanel(
      tags$strong(label),
      tags$p(sprintf("Entry #1: \"%s\"  |  Entry #2 (yours): \"%s\"",
                     d$version_a_value, d$version_b_value)),
      shiny::radioButtons(
        ns_id, NULL,
        choices = c(
          "Keep my (entry #2) value" = "keep_second",
          "Revert to entry #1's value" = "revert_first",
          "Leave both and flag for reconciliation review" = "flag_for_review"
        ),
        selected = "flag_for_review"
      )
    )
  })
  shiny::modalDialog(
    title = "Double-data-entry discrepancy",
    tags$p(paste(
      "The following field(s) flagged for double data entry differ",
      "between the first and second (this) submission. Your entry has",
      "already been saved, flagged for reconciliation review by",
      "default; choose how to resolve each one now, or close this",
      "dialog to leave it flagged for later."
    )),
    shiny::tagList(rows),
    footer = shiny::actionButton("dde_confirm_resolution", "Confirm and Save",
                                 class = "btn-primary"),
    easyClose = FALSE
  )
}

# Shared by the ordinary submit path and the DDE confirm-resolution
# handler below: the UI side effects of a successful/failed save used
# to be inline at the end of observeEvent(input$submitcrf, ...); both
# call sites need the identical behavior, so this is the one place it
# is written.
.zzedc_finish_submit <- function(result, crf_row, metadata, crf_code) {
  if (isTRUE(result$success)) {
    shiny::showNotification(
      sprintf("Entry saved (%s, %s).", crf_row$crf_name[1], result$entry_id),
      type = "message", duration = 5
    )
    shinyjs::show("crf_results")
    crf_entries_refresh(crf_entries_refresh() + 1)
    crf_submit_attempted(FALSE)
    crf_draft(NULL)
    shinyjs::enable("tracking_id")
    shinyjs::enable("subject_id")
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
}

output$crf_draft_banner <- renderUI({
  draft <- crf_draft()
  if (is.null(draft)) return(NULL)
  div(class = "alert alert-info py-2 px-3 mt-2",
      sprintf("Resuming incomplete entry %s. Submitting will mark it complete.",
              draft$entry_id))
})

# Switching forms starts a fresh entry on a different CRF; a rejected
# submit on the previous form shouldn't carry over and flag that
# form's blank required fields before anyone has tried to submit it.
# A loaded draft is form-specific too (Continue only ever appears for
# the currently selected form's own entries, see crf_entries_table
# below) -- switching forms always abandons it rather than carrying
# a stale entry_id onto an unrelated form's fields.
observeEvent(input$edc_crf_form, {
  crf_submit_attempted(FALSE)
  crf_draft(NULL)
  shinyjs::enable("tracking_id")
  shinyjs::enable("subject_id")
}, ignoreInit = TRUE)

crf_live_field_data <- reactive({
  metadata <- crf_field_metadata()
  field_codes <- names(metadata)
  stats::setNames(lapply(field_codes, function(f) {
    v <- input[[f]]
    if (is.null(v)) NA_character_
    else if (inherits(v, "Date")) format(v)
    # fileInput()'s input[[f]] is a data frame (name/size/type/
    # datapath), not a scalar -- as.character(v) below would coerce
    # and concatenate all four columns into one garbled string. Only
    # the original filename is meaningful here (for the required
    # check and this live view); the submit handler
    # (observeEvent(input$submitcrf, ...)) reads input[[f]]$datapath
    # itself to actually persist the upload via persist_crf_upload().
    else if (metadata[[f]]$type == "file") {
      if (is.data.frame(v) && nrow(v) > 0) v$name[1] else NA_character_
    }
    else as.character(v)
  }), field_codes)
})

# Non-blocking: flags an invalid entry (e.g. a value outside the
# field's defined choice set, or a tracking_id that breaks its
# form's PUB-YYYY-N convention or duplicates another entry's) as
# soon as it is made, but never disables the field or the submit
# button. Required-but-blank fields are not flagged here until a
# submit has actually been rejected once (crf_submit_attempted()) --
# a field simply not filled in yet, on a form nobody has tried to
# submit, is not an invalid entry. After a rejected submit, a still-
# blank required field gets the same live icon/outline feedback as
# every other error kind, updating as the user fixes it. Rendered in
# red (not the calmer warning yellow used elsewhere) since every flag
# here is a real error, not just an in-progress reminder.
output$edc_crf_field_flags <- renderUI({
  crf_submit_attempt()
  metadata <- crf_field_metadata()
  if (length(metadata) == 0) return(NULL)
  crf_code <- crf_current_code()
  field_data <- crf_live_field_data()

  result <- zzedc:::validate_crf_submission(field_data, metadata, crf_code = crf_code)
  live_errors <- if (isTRUE(crf_submit_attempted())) {
    result$errors
  } else {
    Filter(function(e) e$kind != "required", result$errors)
  }
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

  # Every field's hover icon (renderPanel()'s always-present
  # `<field>__hint_icon` span, R/renderpanels.R) is kept in sync here
  # -- its title attribute and its info/error visual state -- rather
  # than being re-rendered, since this reactive reruns on every
  # keystroke and swapping DOM nodes that often would steal focus
  # off whatever the user is still typing into. Normally shows the
  # field's own help text (tracking_id gets the richer
  # tracking_id_format_hint() instead, since that already existed
  # and says more than the plain CSV description); once a field has
  # a live error, swaps to that error's message plus
  # field_error_resolution_hint()'s kind-specific advice on how to
  # fix it. Sets `data-tooltip` (the CSS tooltip in this panel's
  # style block reads that attribute, not `title` -- see its comment
  # on why) rather than the element's `title`. jsonlite::toJSON()
  # quotes/escapes the text safely for embedding in the script -- it
  # can include the user's own just-typed value, so this is
  # untrusted text, not just a fixed hint string.
  icon_updates <- vapply(names(metadata), function(f) {
    err <- live_errors[[f]]
    has_error <- !is.null(err)
    tooltip <- if (has_error) {
      advice <- zzedc:::field_error_resolution_hint(err$kind)
      if (nzchar(advice)) paste0(err$message, ". ", advice) else err$message
    } else if (f == "tracking_id" && !is.null(zzedc:::tracking_id_format_hint(crf_code))) {
      zzedc:::tracking_id_format_hint(crf_code)
    } else {
      field_help <- metadata[[f]]$help
      if (is.null(field_help)) "" else field_help
    }
    sprintf(
      paste(
        "(function(el) { if (!el) return;",
        "el.setAttribute('data-tooltip', %s);",
        "el.classList.toggle('field-hint-icon--error', %s); })",
        "(document.getElementById(%s));"
      ),
      jsonlite::toJSON(tooltip, auto_unbox = TRUE),
      if (has_error) "true" else "false",
      jsonlite::toJSON(paste0(f, "__hint_icon"), auto_unbox = TRUE)
    )
  }, character(1))
  title_script <- tags$script(shiny::HTML(paste(icon_updates, collapse = "\n")))

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

# Shared by both the full-submit and "Save and Finish Later" handlers
# below: persists a newly chosen upload exactly as the submit handler
# always has, but when no new file was chosen this save and a draft
# is being resumed, carries that draft's already-stored path forward
# instead of overwriting it with NA. crf_live_field_data() has no way
# to tell "no new upload this time" apart from "clear the existing
# upload" on its own (a fileInput() has no way to express the latter
# at all), so without this a resumed draft's file field would be
# silently wiped out by any save that didn't re-attach the file.
.zzedc_resolve_file_fields <- function(field_data, metadata, input, draft,
                                       db_path, crf_code) {
  for (f in names(metadata)) {
    if (metadata[[f]]$type != "file") next
    upload <- input[[f]]
    if (is.data.frame(upload) && nrow(upload) > 0) {
      field_data[[f]] <- zzedc:::persist_crf_upload(
        tmp_path = upload$datapath[1], original_name = upload$name[1],
        db_path = db_path, crf_code = crf_code,
        tracking_id = zzedc:::crf_subject_key(field_data) %||% "unknown",
        field_code = f
      )
    } else if (!is.null(draft) && length(draft$data[[f]]) > 0) {
      field_data[[f]] <- as.character(unlist(draft$data[[f]]))[1]
    }
  }
  field_data
}

observeEvent(input$submitcrf, {
  # Defect 3 (zzedc-modernization-whitepaper-2026-11-13.md, Section
  # 2.2): output$ui's authenticated switch only decides what renders;
  # this handler had no check of its own, so a crafted
  # Shiny.setInputValue('submitcrf', 1) from an unauthenticated
  # session would still write a real entry. Must come before any
  # other code in this block: everything below writes to the study
  # database.
  zzedc::require_authenticated_action(user_input, session, db_path, "submit a CRF entry")
  shiny::req(input$edc_crf_form)
  crf_id <- as.integer(input$edc_crf_form)
  forms <- zzedc:::get_active_crf_forms(db_pool)
  crf_row <- forms[forms$crf_id == crf_id, , drop = FALSE]
  if (nrow(crf_row) == 0) return(invisible(NULL))

  metadata <- shiny::isolate(crf_field_metadata())
  field_data <- shiny::isolate(crf_live_field_data())
  crf_code <- crf_row$crf_code[1]
  draft <- shiny::isolate(crf_draft())

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
    crf_submit_attempted(TRUE)
    crf_submit_attempt(crf_submit_attempt() + 1)
    return(invisible(NULL))
  }

  # field_data's "file"-type values are just the uploaded filename
  # (see crf_live_field_data() above) -- not a path save_crf_entry()
  # could do anything with later, since fileInput()'s real datapath
  # is a temp file this session will delete. Copies any newly chosen
  # upload to permanent storage, and carries a resumed draft's
  # already-stored path forward when nothing new was chosen this
  # time (see .zzedc_resolve_file_fields() above).
  field_data <- .zzedc_resolve_file_fields(field_data, metadata, input, draft,
                                           db_path, crf_code)

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

  audit_ctx <- zzedc::session_audit_context(session)
  flagged <- zzedc:::flagged_dde_fields(metadata)

  # Enrollment site: required only when output$enroll_site_ui asked
  # for it; enroll_site is NULL otherwise, so a stale drop-down value
  # never overrides the user's own site.
  enroll_site <- if (is.null(draft)) {
    zzedc:::.enrollment_site_from_form(
      db_pool, zzedc:::crf_subject_key(field_data), created_by,
      shiny::isolate(input$enroll_site))
  } else {
    list(error = NULL, site_id = NULL)
  }
  if (!is.null(enroll_site$error)) {
    shiny::showNotification(enroll_site$error, type = "error", duration = 8)
    return(invisible(NULL))
  }

  # The one bypass db_update_incomplete_data_entry() otherwise opens:
  # completing an already-open draft never goes through
  # save_crf_entry()'s DDE group-linking/diff at all. Forms with a
  # flagged field no longer offer "Save and Finish Later" (see
  # output$savedraftcrf_ui above), so no *new* draft can start down
  # this path; this refuses only a pre-existing one from before a
  # field was flagged.
  if (!is.null(draft) && length(flagged) > 0) {
    shiny::showNotification(
      paste("This form now requires double data entry and no longer",
            "supports resuming a draft. Contact an administrator to",
            "resolve entry", draft$entry_id, "."),
      type = "error", duration = 10
    )
    return(invisible(NULL))
  }

  if (length(flagged) == 0) {
    # A resumed draft (crf_draft() set, via the "Continue" action on
    # crf_entries_table) is a true update of that same data_entries
    # row, marking it complete -- never a second INSERT. A fresh entry
    # (no draft loaded) keeps the original insert-only path.
    result <- if (!is.null(draft)) {
      zzedc:::db_update_incomplete_data_entry(
        db_pool, entry_id = draft$entry_id, data = field_data,
        is_complete = TRUE, modified_by = created_by,
        ip_address = audit_ctx$ip_address, session_id = audit_ctx$session_id
      )
    } else {
      zzedc:::save_crf_entry(db_pool, crf_row$crf_code[1], field_data,
                              created_by = created_by, is_complete = TRUE,
                              ip_address = audit_ctx$ip_address,
                              session_id = audit_ctx$session_id,
                              site_id = enroll_site$site_id)
    }
    .zzedc_finish_submit(result, crf_row, metadata, crf_code)
    return(invisible(NULL))
  }

  # Double-data-entry path. A blank/missing Subject ID would otherwise
  # fall back to save_crf_entry()'s own auto-generated, always-unique
  # subject_id (a timestamp) -- which would mean the two entries could
  # never actually pair at all, since each submission gets its own
  # subject_id and is silently treated as "the first entry" of its own
  # never-to-be-completed group. A flagged form depends on subject_id
  # being the one thing the two enterers key identically, so this is
  # refused outright rather than silently skipping DDE.
  # The subject is the form's tracking_id or subject_id field
  # (zzedc:::crf_subject_key(), which also treats NA and blank as
  # missing).
  subject_id <- zzedc:::crf_subject_key(field_data)
  if (is.null(subject_id)) {
    shiny::showNotification(
      "This form requires double data entry, which pairs the two entries by Subject ID; enter a Subject ID before submitting.",
      type = "error", duration = 10
    )
    crf_submit_attempted(TRUE)
    crf_submit_attempt(crf_submit_attempt() + 1)
    return(invisible(NULL))
  }

  # Decide, via the blind probe (dde_decide_role() ->
  # db_get_dde_first_entry(), which never selects data_json), whether
  # this submission is the first or second entry for this
  # subject_id/form_name.
  decision <- zzedc:::dde_decide_role(db_pool, subject_id, tolower(crf_code), created_by)

  if (isTRUE(decision$blocked_same_user)) {
    shiny::showNotification(
      paste("The second entry of a double-data-entry form must be made",
            "by a different user than the first entry."),
      type = "error", duration = 10
    )
    return(invisible(NULL))
  }

  if (isTRUE(decision$already_paired)) {
    shiny::showNotification(
      paste("Subject", subject_id, "already has both double-data-entry",
            "submissions for this form; a third submission is not accepted."),
      type = "error", duration = 10
    )
    return(invisible(NULL))
  }

  if (identical(decision$role, "first")) {
    result <- zzedc:::save_crf_entry(
      db_pool, crf_row$crf_code[1], field_data, created_by = created_by,
      is_complete = TRUE, dde_group_id = decision$group_id,
      ip_address = audit_ctx$ip_address, session_id = audit_ctx$session_id,
      site_id = enroll_site$site_id
    )
    .zzedc_finish_submit(result, crf_row, metadata, crf_code)
    return(invisible(NULL))
  }

  # Second entry: the one place this session's save path reads the
  # first entry's data_json (dde_check_discrepancies() ->
  # db_get_dde_first_entry_values()), restricted to only the flagged
  # fields -- a mismatch on any other field is never checked.
  chk <- zzedc:::dde_check_discrepancies(db_pool, decision$first_entry_id,
                                        field_data, flagged)
  if (length(chk$discrepancies) == 0) {
    result <- zzedc:::save_crf_entry(
      db_pool, crf_row$crf_code[1], field_data, created_by = created_by,
      is_complete = TRUE, dde_group_id = decision$group_id,
      ip_address = audit_ctx$ip_address, session_id = audit_ctx$session_id
    )
    .zzedc_finish_submit(result, crf_row, metadata, crf_code)
    return(invisible(NULL))
  }

  # A flagged field actually disagrees. Save the second entry right
  # now -- every discrepant field defaulted to "flag_for_review" via
  # apply_dde_resolutions() with no resolutions supplied -- *before*
  # showing the three-way resolution prompt, rather than holding it in
  # a reactiveVal until the modal is confirmed. Found on review:
  # holding it unsaved meant dismissing the modal (e.g. a browser
  # reload) lost the second entry and its audit trail with no record
  # entry #1's value was ever shown, and because nothing had been
  # saved yet, dde_decide_role()'s already_paired guard could never
  # fire on a reload-then-resubmit -- defeating the blind-entry design
  # with no trace. input$dde_confirm_resolution below only *upgrades*
  # this already-saved row via update_second_entry_for_dde_resolution();
  # it never inserts a second time.
  defaulted <- zzedc:::apply_dde_resolutions(
    field_data, chk$first_values, chk$discrepancies, resolutions = list()
  )
  result <- zzedc:::save_crf_entry(
    db_pool, crf_row$crf_code[1], defaulted$field_data, created_by = created_by,
    is_complete = TRUE, dde_group_id = decision$group_id,
    audit_extra = list(dde_resolution = defaulted$resolution_detail,
                       dde_first_entry_id = decision$first_entry_id,
                       dde_pending_review_fields = defaulted$pending_fields),
    ip_address = audit_ctx$ip_address, session_id = audit_ctx$session_id
  )
  if (!isTRUE(result$success)) {
    shiny::showNotification(
      paste("Database error saving entry:", result$error),
      type = "error", duration = 10
    )
    return(invisible(NULL))
  }
  .zzedc_finish_submit(result, crf_row, metadata, crf_code)
  dde_pending(list(
    group_id = decision$group_id, first_entry_id = decision$first_entry_id,
    second_entry_id = result$entry_id,
    field_data = field_data, first_values = chk$first_values,
    discrepancies = chk$discrepancies, metadata = metadata,
    crf_row = crf_row, crf_code = crf_code, created_by = created_by,
    ip_address = audit_ctx$ip_address, session_id = audit_ctx$session_id
  ))
  shiny::showModal(.zzedc_dde_discrepancy_modal(chk$discrepancies, metadata))
})

observeEvent(input$dde_confirm_resolution, {
  zzedc::require_authenticated_action(user_input, session, db_path,
                                      "resolve a double-data-entry discrepancy")
  pending <- dde_pending()
  shiny::req(pending)

  resolutions <- stats::setNames(
    lapply(names(pending$discrepancies), function(f) input[[paste0("dde_resolve_", f)]]),
    names(pending$discrepancies)
  )
  applied <- zzedc:::apply_dde_resolutions(
    pending$field_data, pending$first_values, pending$discrepancies, resolutions
  )

  # The second entry was already saved (with every discrepant field
  # defaulted to "flag_for_review") when the modal was first shown --
  # see the submitcrf handler. This only *upgrades* that row to the
  # enterer's actual choices; it never inserts a second row.
  update_err <- tryCatch({
    zzedc:::update_second_entry_for_dde_resolution(
      db_pool, pending$second_entry_id, applied,
      modified_by = pending$created_by,
      ip_address = pending$ip_address, session_id = pending$session_id
    )
    NULL
  }, error = function(e) e)
  result <- if (is.null(update_err)) {
    list(success = TRUE, entry_id = pending$second_entry_id)
  } else {
    list(success = FALSE, error = conditionMessage(update_err))
  }

  if (isTRUE(result$success)) {
    # Keeps the first (canonical) entry in agreement with every
    # "keep_second" field decided just now -- without this, the
    # canonical record would still show the first enterer's value for
    # a field the second enterer's was deliberately kept for, and it
    # would never stop showing up in the reconciliation queue (see
    # update_first_entry_for_dde_resolution()'s own docs).
    tryCatch(
      zzedc:::update_first_entry_for_dde_resolution(
        db_pool, pending$first_entry_id, applied$resolution_detail,
        modified_by = pending$created_by,
        ip_address = pending$ip_address, session_id = pending$session_id
      ),
      error = function(e) {
        shiny::showNotification(
          paste("The second entry was saved, but the first entry could not be",
                "updated for the resolved discrepancy; it will appear in the",
                "reconciliation queue:", conditionMessage(e)),
          type = "error", duration = 12
        )
      }
    )

    # If nothing is left open (no "flag_for_review" field, and the
    # "keep_second" update above succeeded), this group is fully
    # resolved right now -- mark the non-canonical (second) entry
    # superseded immediately, the same bookkeeping
    # close_dde_group_if_resolved() otherwise only runs after a queued
    # DDE_DISCREPANCY correction is applied. A group with a "flag_for_review"
    # field is deliberately left unresolved here (close_dde_group_if_resolved()
    # itself re-checks list_dde_discrepancies(), so this is a safe,
    # redundant call either way).
    tryCatch(
      zzedc:::close_dde_group_if_resolved(db_pool, pending$group_id),
      error = function(e) NULL
    )
  }

  shiny::removeModal()
  dde_pending(NULL)
  # The entry itself was already saved (and the form already reset,
  # via .zzedc_finish_submit()) when the modal was first shown; this
  # only reports whether the chosen resolution could be recorded.
  if (isTRUE(result$success)) {
    if (length(applied$pending_fields) > 0) {
      shiny::showNotification(
        paste("Flagged for reconciliation review:",
              paste(applied$pending_fields, collapse = ", ")),
        type = "warning", duration = 8
      )
    } else {
      shiny::showNotification("Discrepancy resolution recorded.",
                               type = "message", duration = 5)
    }
  } else {
    shiny::showNotification(
      paste("The entry itself was saved, but its discrepancy resolution could",
            "not be recorded; it will remain flagged in the reconciliation",
            "queue:", result$error),
      type = "error", duration = 12
    )
  }
})

observeEvent(input$savedraftcrf, {
  # Same unauthenticated-click defense as submitcrf above (Defect 3) --
  # this is a second action that writes to the study database and
  # needs the same guard.
  zzedc::require_authenticated_action(user_input, session, db_path, "save a draft CRF entry")
  shiny::req(input$edc_crf_form)
  crf_id <- as.integer(input$edc_crf_form)
  forms <- zzedc:::get_active_crf_forms(db_pool)
  crf_row <- forms[forms$crf_id == crf_id, , drop = FALSE]
  if (nrow(crf_row) == 0) return(invisible(NULL))

  metadata <- shiny::isolate(crf_field_metadata())
  field_data <- shiny::isolate(crf_live_field_data())
  crf_code <- crf_row$crf_code[1]
  draft <- shiny::isolate(crf_draft())

  # Server-side belt-and-suspenders: output$savedraftcrf_ui above
  # never renders this button for a form with a flagged field, but
  # that only stops the normal UI, not a crafted
  # Shiny.setInputValue('savedraftcrf', 1) -- and a drafted,
  # incomplete row would bypass DDE's group-linking/diff entirely if
  # ever completed (see the submitcrf handler's matching check).
  if (length(zzedc:::flagged_dde_fields(metadata)) > 0) {
    shiny::showNotification(
      "This form requires double data entry; it must be submitted in full, not saved as a draft.",
      type = "error", duration = 8
    )
    return(invisible(NULL))
  }

  # "Save and Finish Later" accepts whatever subset of fields is
  # filled in -- required-ness is deliberately not checked here (that
  # is the whole point of an incomplete-save path); a value that IS
  # present still has to be the right type/format/choice, so those
  # non-"required" errors are kept. Tracking-ID uniqueness and this
  # form's cross-field DSL rules (both checked at full Submit time,
  # above) are record-completeness checks that do not apply to a
  # deliberately incomplete record, so neither runs here at all --
  # documented as a deliberate scope limit in NEWS.md, not an
  # oversight.
  check <- zzedc:::validate_crf_submission(field_data, metadata, crf_code = crf_code)
  check$errors <- Filter(function(e) e$kind != "required", check$errors)
  if (length(check$errors) > 0) {
    messages <- vapply(check$errors, function(e) e$message, character(1))
    shiny::showNotification(
      paste(messages, collapse = "; "),
      type = "error", duration = 8
    )
    # Deliberately does NOT set crf_submit_attempted(TRUE): that flag
    # turns on live flagging of blank *required* fields, which a
    # draft rejected only for a format/choice error on some other
    # field must not start doing.
    return(invisible(NULL))
  }

  field_data <- .zzedc_resolve_file_fields(field_data, metadata, input, draft,
                                           db_path, crf_code)

  username <- shiny::isolate(user_input$username)
  created_by <- if (!is.null(username) && nzchar(username)) {
    as.character(username)
  } else {
    "unknown"
  }

  audit_ctx <- zzedc::session_audit_context(session)
  # A new draft is the subject's first entry, so it enrolls them; the
  # site rule is the same as at submission.
  enroll_site <- if (is.null(draft)) {
    zzedc:::.enrollment_site_from_form(
      db_pool, zzedc:::crf_subject_key(field_data), created_by,
      shiny::isolate(input$enroll_site))
  } else {
    list(error = NULL, site_id = NULL)
  }
  if (!is.null(enroll_site$error)) {
    shiny::showNotification(enroll_site$error, type = "error", duration = 8)
    return(invisible(NULL))
  }
  result <- if (!is.null(draft)) {
    zzedc:::db_update_incomplete_data_entry(
      db_pool, entry_id = draft$entry_id, data = field_data,
      is_complete = FALSE, modified_by = created_by,
      ip_address = audit_ctx$ip_address, session_id = audit_ctx$session_id
    )
  } else {
    zzedc:::save_crf_entry(db_pool, crf_row$crf_code[1], field_data,
                            created_by = created_by, is_complete = FALSE,
                            ip_address = audit_ctx$ip_address,
                            session_id = audit_ctx$session_id,
                            site_id = enroll_site$site_id)
  }

  if (isTRUE(result$success)) {
    shiny::showNotification(
      sprintf("Draft saved (%s, %s). Resume it later from the entries list.",
              crf_row$crf_name[1], result$entry_id),
      type = "message", duration = 6
    )
    crf_entries_refresh(crf_entries_refresh() + 1)
    # Keeps editing the same row on any further save (another draft
    # save, or the eventual Submit) instead of starting a second row --
    # matters just as much for a brand-new draft's first save (which
    # had no entry_id to resume until just now) as for a second save
    # of an already-resumed one.
    crf_draft(list(entry_id = result$entry_id, data = field_data))
    if (!is.null(zzedc:::crf_subject_key_field(names(metadata)))) {
      shinyjs::disable(zzedc:::crf_subject_key_field(names(metadata)))
    }
  } else {
    shiny::showNotification(
      paste("Database error saving draft:", result$error),
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
    "SELECT entry_id, subject_id, created_date, is_complete FROM data_entries WHERE form_name = ? ORDER BY created_date DESC",
    params = list(tolower(crf_row$crf_code[1]))
  )
  audit_ctx <- zzedc::session_audit_context(session)
  zzedc::log_record_read(db_pool, "edc_entries_list", data = rows,
                         filters = list(form = crf_row$crf_code[1]),
                         user_id = user_input$user_id,
                         ip_address = audit_ctx$ip_address,
                         session_id = audit_ctx$session_id)

  # Status column: an open ("Save and Finish Later", is_complete = 0)
  # draft is shown here, clearly labeled, rather than left looking
  # like every other finished row.
  display_rows <- rows[, c("subject_id", "created_date")]
  display_rows$Status <- ifelse(rows$is_complete == 1, "Complete", "Incomplete")

  # One action button per row: a settled (is_complete = 1) row gets
  # "Request Correction" -- the entry point into the Corrections
  # tab's CRF-aware field picker, so fixing an already-submitted
  # value never requires typing an entry_id by hand. An open draft
  # has no settled value yet to correct (create_correction_request()
  # refuses it, R/data_correction.R), so it instead gets "Continue",
  # which resumes it right here on this same form rather than
  # switching tabs. Same onclick/Shiny.setInputValue convention as
  # the row actions in R/user_management_module.R.
  display_rows$Actions <- vapply(seq_len(nrow(rows)), function(i) {
    eid <- rows$entry_id[i]
    if (rows$is_complete[i] == 1) {
      paste0(
        '<button class="btn btn-outline-secondary btn-sm" ',
        'onclick="Shiny.setInputValue(\'edc_request_correction\', \'', eid,
        '\', {priority: \'event\'})">Request Correction</button>'
      )
    } else {
      paste0(
        '<button class="btn btn-outline-primary btn-sm" ',
        'onclick="Shiny.setInputValue(\'edc_continue_draft\', \'', eid,
        '\', {priority: \'event\'})">Continue</button>'
      )
    }
  }, character(1))

  DT::datatable(display_rows, escape = FALSE, rownames = FALSE,
                 options = list(
                   pageLength = 5,
                   # Column indices are 0-based and count the new
                   # Status column added above: 0 subject_id,
                   # 1 created_date, 2 Status, 3 Actions.
                   columnDefs = list(
                     list(targets = 3, searchable = FALSE, orderable = FALSE)
                   )
                 ))
})

# Hand off to the Corrections tab's CRF-aware "Create Request" view,
# pre-filled with this entry (see R/data_correction_module.R's
# pending_entry_id parameter and the shared reactiveVal created in
# inst/app/gsheets_server_integration.R's initialize_traditional_server()).
shiny::observeEvent(input$edc_request_correction, {
  rv_pending_correction_entry(input$edc_request_correction)
  bslib::nav_select("main_nav", selected = "corrections", session = session)
})

# Resumes an open ("Save and Finish Later") draft right here on the
# EDC tab, rather than switching tabs: crf_entries_table (above) only
# ever shows a "Continue" button for a row belonging to the
# currently selected form, so this form's own inputs (not a
# different form's) are already on screen -- fill_crf_field_inputs()
# can use shiny::update*Input() directly instead of re-rendering.
# input$edc_continue_draft is client-settable like any Shiny input,
# so this re-checks everything the button's own visibility already
# implied (authenticated, the entry exists, is still is_complete =
# 0, and belongs to the form currently on screen) rather than
# trusting the click alone.
shiny::observeEvent(input$edc_continue_draft, {
  zzedc::require_authenticated_action(user_input, session, db_path, "resume a draft CRF entry")
  shiny::req(input$edc_crf_form)
  entry_id <- input$edc_continue_draft

  crf_id <- as.integer(input$edc_crf_form)
  forms <- zzedc:::get_active_crf_forms(db_pool)
  crf_row <- forms[forms$crf_id == crf_id, , drop = FALSE]
  if (nrow(crf_row) == 0) return(invisible(NULL))

  row <- DBI::dbGetQuery(
    db_pool,
    "SELECT entry_id, form_name, data_json, is_complete FROM data_entries WHERE entry_id = ?",
    params = list(entry_id)
  )
  if (nrow(row) == 0 || isTRUE(as.logical(as.integer(row$is_complete[1]))) ||
        !identical(tolower(row$form_name[1]), tolower(crf_row$crf_code[1]))) {
    shiny::showNotification(
      "That draft is no longer available to resume (it may have since been completed, or belongs to a different form).",
      type = "warning"
    )
    return(invisible(NULL))
  }

  values <- jsonlite::fromJSON(row$data_json[1] %||% "{}", simplifyVector = FALSE)
  metadata <- shiny::isolate(crf_field_metadata())
  zzedc:::fill_crf_field_inputs(session, metadata, values)

  # The draft's subject_id/tracking_id is fixed at the entry_id it
  # was originally saved under (db_update_incomplete_data_entry()
  # never touches that column); disabling the input here prevents a
  # resumed draft's data_json from recording a different tracking_id
  # than the row's own subject_id actually is.
  if (!is.null(zzedc:::crf_subject_key_field(names(metadata)))) {
    shinyjs::disable(zzedc:::crf_subject_key_field(names(metadata)))
  }

  crf_submit_attempted(FALSE)
  crf_draft(list(entry_id = entry_id, data = values))
  shiny::showNotification(sprintf("Resuming draft entry %s.", entry_id), type = "message")
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












 
      

    




