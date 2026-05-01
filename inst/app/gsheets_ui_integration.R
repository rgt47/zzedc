# Google Sheets UI Integration for ZZedc
# Modifies the main UI to include Google Sheets forms dynamically

# Load the form loader
source("gsheets_form_loader.R")

#' Create enhanced UI that includes Google Sheets forms
create_enhanced_ui <- function() {

  # Try to load Google Sheets forms
  gsheets_integration <- integrate_gsheets_forms()

  # Build navigation tabs
  nav_tabs <- list()

  # 1. Always include Home tab
  nav_tabs[["home"]] <- bslib::nav_panel(
    title = "Home",
    icon = bsicons::bs_icon("house"),
    value = "home",
    source("home.R", local = TRUE)$value
  )

  # 2. Include Google Sheets forms if available
  if (!is.null(gsheets_integration) && gsheets_integration$has_gsheets_forms) {

    message("Adding Google Sheets forms to UI")

    # Add each Google Sheets form as a tab
    for (i in 1:nrow(gsheets_integration$forms_data$forms_overview)) {
      form_name <- gsheets_integration$forms_data$forms_overview$workingname[i]
      form_display_name <- gsheets_integration$forms_data$forms_overview$fullname[i]

      nav_tabs[[form_name]] <- bslib::nav_panel(
        title = form_display_name,
        icon = bsicons::bs_icon("clipboard-data"),
        value = form_name,
        uiOutput(paste0("gsheets_form_", form_name))
      )
    }

    # Add Forms Overview tab
    nav_tabs[["forms_overview"]] <- bslib::nav_panel(
      title = "Forms Overview",
      icon = bsicons::bs_icon("list-check"),
      value = "forms_overview",
      create_forms_overview_ui(gsheets_integration$forms_data)
    )

  } else {
    # 3. Include traditional EDC tab if no Google Sheets forms
    nav_tabs[["edc"]] <- bslib::nav_panel(
      title = "EDC Forms",
      icon = bsicons::bs_icon("clipboard-data"),
      value = "edc",
      source("edc.R", local = TRUE)$value
    )
  }

  # 4. Always include Reports tabs
  nav_tabs[["reports1"]] <- bslib::nav_panel(
    title = "Basic Reports",
    icon = bsicons::bs_icon("bar-chart"),
    value = "reports1",
    source("report1.R", local = TRUE)$value
  )

  nav_tabs[["reports2"]] <- bslib::nav_panel(
    title = "Quality Reports",
    icon = bsicons::bs_icon("shield-check"),
    value = "reports2",
    source("report2.R", local = TRUE)$value
  )

  nav_tabs[["reports3"]] <- bslib::nav_panel(
    title = "Statistical Reports",
    icon = bsicons::bs_icon("graph-up"),
    value = "reports3",
    source("report3.R", local = TRUE)$value
  )

  # 5. Always include Data Explorer and Export
  nav_tabs[["data"]] <- bslib::nav_panel(
    title = "Data Explorer",
    icon = bsicons::bs_icon("table"),
    value = "data",
    source("data.R", local = TRUE)$value
  )

  nav_tabs[["export"]] <- bslib::nav_panel(
    title = "Export Data",
    icon = bsicons::bs_icon("download"),
    value = "export",
    source("export.R", local = TRUE)$value
  )

  # 6. Add Setup tab for Google Sheets management
  nav_tabs[["setup"]] <- bslib::nav_panel(
    title = "Setup",
    icon = bsicons::bs_icon("gear"),
    value = "setup",
    create_setup_ui()
  )

  # Build the complete UI
  ui <- bslib::page_navbar(
    title = div(
      img(src="brain2.png", height="30px", style="margin-right: 10px;"),
      "ZZedc - Electronic Data Capture"
    ),
    theme = bslib::bs_theme(
      version = 5,
      bootswatch = "flatly",
      primary = "#2c3e50",
      secondary = "#95a5a6",
      success = "#27ae60",
      info = "#3498db",
      warning = "#f39c12",
      danger = "#e74c3c"
    ),
    window_title = "ZZedc Portal",
    id = "main_nav",

    shinyjs::useShinyjs(),
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "style.css"),
      tags$link(rel = "icon", href = "logo.png", type = "image/png")
    ),

    # Add all navigation tabs
    !!!nav_tabs,

    # Authentication modal placeholder
    uiOutput("uiLogin"),

    # Google Sheets integration data (hidden)
    if (!is.null(gsheets_integration)) {
      tags$script(paste0("
        window.gsheetsFormsAvailable = true;
        window.gsheetsFormsCount = ", nrow(gsheets_integration$forms_data$forms_overview), ";
      "))
    } else {
      tags$script("window.gsheetsFormsAvailable = false;")
    }
  )

  # Store integration data globally for server use
  if (!is.null(gsheets_integration)) {
    assign("gsheets_integration_data", gsheets_integration, envir = .GlobalEnv)
  }

  return(ui)
}

#' Create forms overview UI
create_forms_overview_ui <- function(forms_data) {

  # Create cards for each form
  form_cards <- list()

  for (i in 1:nrow(forms_data$forms_overview)) {
    form_name <- forms_data$forms_overview$workingname[i]
    form_display_name <- forms_data$forms_overview$fullname[i]
    form_visits <- forms_data$forms_overview$visits[i]

    # Get field count
    field_count <- length(forms_data$form_loaders[[form_name]])

    form_card <- bslib::card(
      bslib::card_header(
        class = "bg-primary text-white",
        h5(form_display_name, class = "mb-0")
      ),
      bslib::card_body(
        p(paste("Form ID:", form_name)),
        p(paste("Visits:", form_visits)),
        p(paste("Fields:", "Multiple")), # Would need to count from database
        hr(),
        div(
          actionButton(
            paste0("goto_", form_name),
            "Open Form",
            class = "btn btn-primary btn-sm",
            onclick = paste0("$('#main_nav').trigger('shown.bs.tab', '#", form_name, "');")
          ),
          actionButton(
            paste0("preview_", form_name),
            "Preview",
            class = "btn btn-outline-secondary btn-sm ms-2"
          )
        )
      )
    )

    form_cards[[i]] <- form_card
  }

  # Layout the cards
  tagList(
    div(class = "container-fluid",
      h2("Forms Overview"),
      p("This study includes the following data collection forms:"),

      # Forms grid
      div(class = "row",
        lapply(form_cards, function(card) {
          div(class = "col-md-6 col-lg-4 mb-3", card)
        })
      ),

      hr(),

      # Management section
      h3("Form Management"),
      p("Manage your Google Sheets forms and configuration:"),

      div(class = "row",
        div(class = "col-md-6",
          bslib::card(
            bslib::card_header("Google Sheets Configuration"),
            bslib::card_body(
              p("Current Google Sheets:"),
              tags$ul(
                tags$li("Authentication: Check Google Sheets"),
                tags$li("Data Dictionary: Check Google Sheets")
              ),
              actionButton("refresh_gsheets", "Refresh from Google Sheets", class = "btn btn-warning"),
              br(), br(),
              actionButton("export_config", "Export Configuration", class = "btn btn-info")
            )
          )
        ),
        div(class = "col-md-6",
          bslib::card(
            bslib::card_header("System Status"),
            bslib::card_body(
              p("Database Status:"),
              verbatimTextOutput("db_status"),
              br(),
              actionButton("verify_setup", "Verify Setup", class = "btn btn-success")
            )
          )
        )
      )
    )
  )
}

#' Create setup management UI
create_setup_ui <- function() {
  tagList(
    div(class = "container-fluid",
      h2("ZZedc Setup & Configuration"),

      # Setup options
      div(class = "row",
        div(class = "col-md-6",
          bslib::card(
            bslib::card_header(class = "bg-primary text-white", "Google Sheets Setup"),
            bslib::card_body(
              p("Configure ZZedc using Google Sheets for easy, non-technical setup."),

              h5("Authentication Sheet"),
              textInput("auth_sheet_name", "Sheet Name:", value = "zzedc_auth"),

              h5("Data Dictionary Sheet"),
              textInput("dd_sheet_name", "Sheet Name:", value = "zzedc_data_dictionary"),

              h5("Project Settings"),
              textInput("project_name", "Project Name:", value = "zzedc_project"),

              br(),
              actionButton("run_gsheets_setup", "Setup from Google Sheets",
                         class = "btn btn-primary btn-lg"),

              br(), br(),
              div(id = "setup_progress", style = "display: none;",
                h5("Setup Progress:"),
                div(class = "progress",
                  div(class = "progress-bar", role = "progressbar", style = "width: 0%")
                )
              )
            )
          )
        ),

        div(class = "col-md-6",
          bslib::card(
            bslib::card_header(class = "bg-info text-white", "Traditional Setup"),
            bslib::card_body(
              p("Use the original ZZedc setup method with R scripts."),

              actionButton("run_traditional_setup", "Run Traditional Setup",
                         class = "btn btn-info"),
              br(), br(),

              h5("Import Database"),
              p("Import from existing ZZedc database:"),
              fileInput("import_db", "Select Database File", accept = ".db"),
              actionButton("import_database", "Import Database", class = "btn btn-secondary")
            )
          )
        )
      ),

      br(),

      # Current configuration display
      div(class = "row",
        div(class = "col-12",
          bslib::card(
            bslib::card_header("Current Configuration"),
            bslib::card_body(
              verbatimTextOutput("current_config_display")
            )
          )
        )
      ),

      br(),

      # Help and documentation
      div(class = "row",
        div(class = "col-12",
          bslib::card(
            bslib::card_header("Documentation & Help"),
            bslib::card_body(
              h5("Quick Start Guide"),
              p("New to ZZedc? Follow these steps:"),
              tags$ol(
                tags$li("Create your Google Sheets with authentication and form definitions"),
                tags$li("Enter sheet names above and click 'Setup from Google Sheets'"),
                tags$li("Once setup completes, navigate to your forms to start data entry")
              ),

              h5("Resources"),
              tags$ul(
                tags$li(a("Google Sheets Setup Guide", href = "#", onclick = "alert('Open GSHEETS_SETUP_GUIDE.md')")),
                tags$li(a("ZZedc User Guide", href = "#", onclick = "alert('Open ZZEDC_USER_GUIDE.md')")),
                tags$li(a("Troubleshooting", href = "#", onclick = "alert('See documentation')")
                )
              )
            )
          )
        )
      )
    )
  )
}