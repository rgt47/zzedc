# Unified UI with intelligent mode selection
# Automatically chooses between enhanced (Google Sheets) and traditional modes

# Check if enhanced UI integration is available
if (file.exists("gsheets_ui_integration.R")) {
  # Try to use enhanced UI
  tryCatch({
    source("gsheets_ui_integration.R")
    ui_content <- create_enhanced_ui()
  }, error = function(e) {
    message("Enhanced UI failed, falling back to traditional: ", e$message)
    ui_content <- NULL
  })
}

# If enhanced UI didn't load, use traditional UI
if (!exists("ui_content") || is.null(ui_content)) {
  message("Using traditional UI implementation")

  # Load module files with error handling
  module_files <- c('R/modules/auth_module.R', 'R/modules/home_module.R', 'R/modules/data_module.R')

  for (module_file in module_files) {
    if (file.exists(module_file)) {
      tryCatch({
        source(module_file)
      }, error = function(e) {
        message("Warning: Could not load ", module_file, ": ", e$message)
      })
    }
  }

  # Helper function for safe icon creation
  safe_icon <- function(icon_name) {
    if (requireNamespace("bsicons", quietly = TRUE)) {
      bsicons::bs_icon(icon_name)
    } else {
      span(class = "placeholder-icon", "[", icon_name, "]")
    }
  }

  # Helper function for safe module UI
  safe_module_ui <- function(ui_function, id, fallback_content = "Module not available") {
    if (exists(ui_function) && is.function(get(ui_function))) {
      get(ui_function)(id)
    } else {
      div(class = "alert alert-warning", fallback_content)
    }
  }

  # Traditional UI implementation
  if (requireNamespace("bslib", quietly = TRUE)) {
    ui_content <- bslib::page_navbar(
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
  
  # ShinyJS initialization (if available)
  if (requireNamespace("shinyjs", quietly = TRUE)) {
    shinyjs::useShinyjs()
  } else {
    tags$script("console.log('shinyjs not available');")
  },
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "style.css"),
    tags$link(rel = "icon", href = "logo.png", type = "image/png")
  ),

  # Home Tab
  bslib::nav_panel(
    title = tagList(safe_icon("house-fill"), "Home"),
    value = "home",
    safe_module_ui("home_ui", "home", "Home module not available")
  ),

  # EDC Tab
  bslib::nav_panel(
    title = tagList(safe_icon("pencil-fill"), "EDC"),
    value = "edc",
    uiOutput("ui")
  ),

  # Reports Tab with Dropdown
  bslib::nav_menu(
    title = tagList(safe_icon("bar-chart-fill"), "Reports"),

    bslib::nav_panel(
      title = tagList(safe_icon("file-text"), "Basic Report"),
      value = "report1",
      uiOutput("rep1")
    ),

    bslib::nav_panel(
      title = tagList(safe_icon("shield-check"), "Quality Report"),
      value = "report2",
      uiOutput("rep2")
    ),

    bslib::nav_panel(
      title = tagList(safe_icon("graph-up"), "Statistical Report"),
      value = "report3",
      uiOutput("htable")
    )
  ),

  # Data Tab
  bslib::nav_panel(
    title = tagList(safe_icon("database-fill"), "Data Explorer"),
    value = "data",
    safe_module_ui("data_ui", "data", "Data Explorer module not available")
  ),

  # Export Tab
  bslib::nav_panel(
    title = tagList(safe_icon("download"), "Export"),
    value = "export",
    uiOutput("export")
  ),

  # Settings/Admin (future)
  bslib::nav_spacer(),

  bslib::nav_menu(
    title = tagList(safe_icon("gear-fill")),
    align = "right",

    bslib::nav_panel("Settings", div(class="p-4", h4("Settings"), p("Settings coming soon..."))),
    bslib::nav_panel("Help", div(class="p-4", h4("Help"), p("Help documentation"))),
    bslib::nav_panel("About", div(class="p-4", h4("About"), p("ZZedc v1.0")))
  )
)
} else {
  # Fallback UI when bslib is not available
  ui_content <- fluidPage(
    titlePanel("ZZedc - Electronic Data Capture"),
    h3("Basic Mode - Advanced UI packages not available"),
    p("Please install bslib package for full functionality"),
    tabsetPanel(
      tabPanel("Home", "Home content"),
      tabPanel("EDC", uiOutput("ui")),
      tabPanel("Reports", "Reports content"),
      tabPanel("Data", "Data content"),
      tabPanel("Export", uiOutput("export"))
    )
  )
  }
}

# Return the UI content (whether enhanced or traditional)
ui_content
    


 

   # end of shiny
