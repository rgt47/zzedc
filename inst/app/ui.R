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

  # Module functions are provided by the zzedc package namespace
  # No need to source files - they're loaded via library(zzedc)

  # Helper function for safe icon creation
  safe_icon <- function(icon_name) {
    if (requireNamespace("bsicons", quietly = TRUE)) {
      bsicons::bs_icon(icon_name)
    } else {
      span(class = "placeholder-icon", "[", icon_name, "]")
    }
  }

  # Helper function for safe module UI - uses zzedc package namespace

  safe_module_ui <- function(ui_function, id, fallback_content = "Module not available") {
    # Try to get function from zzedc package namespace
    fn <- tryCatch(
      utils::getFromNamespace(ui_function, "zzedc"),
      error = function(e) NULL
    )
    if (!is.null(fn) && is.function(fn)) {
      fn(id)
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
  # Contemporary slate palette (replaces the heavy bootswatch
  # "flatly" navy). Inter for body and headings; warm off-white
  # background; rounded corners on cards.
  theme = bslib::bs_theme(
    version = 5,
    primary   = "#334155",
    secondary = "#64748b",
    success   = "#15803d",
    info      = "#0891b2",
    warning   = "#b45309",
    danger    = "#b91c1c",
    bg        = "#fafaf9",
    fg        = "#1e293b",
    base_font    = bslib::font_google("Inter"),
    heading_font = bslib::font_google("Inter"),
    "navbar-bg" = "#1e293b",
    "card-border-color"  = "#e2e8f0",
    "card-cap-bg"        = "#ffffff",
    "card-bg"            = "#ffffff",
    "border-radius"      = "10px",
    "border-radius-sm"   = "8px",
    "border-radius-lg"   = "14px"
  ),
  window_title = "ZZedc Portal",
  id = "main_nav",

  # ShinyJS initialization (if available)
  if (requireNamespace("shinyjs", quietly = TRUE)) {
    shinyjs::useShinyjs()
  } else {
    tags$script("console.log('shinyjs not available');")
  },

  # Busy indicators: keep the global progress pulse, suppress
  # per-output spinners. Spinner overlays redraw cards on every
  # input change and produce a layout jump on tile-based pages
  # (e.g. quality dashboard). The pulse alone is enough.
  shiny::useBusyIndicators(spinners = FALSE),

  tags$head(
    tags$link(rel = "icon", href = "logo.png", type = "image/png"),
    # Inline UX polish: cards, headers, value boxes, DT tables,
    # accordion typography. Mirrors the zzpower aesthetic so the
    # two apps feel like siblings.
    tags$style(HTML(paste(
      "body { background: #fafaf9; color: #1e293b; }",
      ".card {",
      "  border: 1px solid #e2e8f0 !important;",
      "  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);",
      "  border-radius: 12px;",
      "}",
      ".card-header {",
      "  background: #ffffff !important;",
      "  border-bottom: 1px solid #f1f5f9 !important;",
      "  font-weight: 600;",
      "  letter-spacing: 0.01em;",
      "}",
      ".bslib-value-box {",
      "  border-radius: 12px !important;",
      "}",
      ".bslib-value-box .value-box-title {",
      "  font-weight: 500;",
      "  font-size: 0.85rem;",
      "  letter-spacing: 0.02em;",
      "  opacity: 0.95;",
      "}",
      ".bslib-value-box .value-box-value {",
      "  font-weight: 700;",
      "  font-size: 1.7rem;",
      "  letter-spacing: -0.01em;",
      "}",
      "table.dataTable { font-size: 0.92rem; border-spacing: 0 !important; }",
      "table.dataTable thead th {",
      "  background: #f8fafc;",
      "  border-bottom: 2px solid #cbd5e1 !important;",
      "  font-weight: 600;",
      "  font-size: 0.82rem;",
      "  letter-spacing: 0.03em;",
      "  text-transform: uppercase;",
      "  color: #475569;",
      "}",
      "table.dataTable tbody td {",
      "  border-top: 1px solid #f1f5f9 !important;",
      "  padding: 0.6rem 0.75rem !important;",
      "}",
      "table.dataTable tbody td.dt-right {",
      "  font-variant-numeric: tabular-nums;",
      "  color: #334155;",
      "}",
      ".accordion-button {",
      "  font-weight: 600;",
      "  font-size: 0.95rem;",
      "  letter-spacing: 0.01em;",
      "}",
      ".btn { border-radius: 8px; font-weight: 500; }",
      ".btn-sm { font-size: 0.82rem; padding: 0.3rem 0.65rem; }",
      ".navbar-brand { font-weight: 600; letter-spacing: -0.01em; }",
      # Re-skin shiny::wellPanel (Bootstrap .well) which several
      # legacy tabs (Export, Report 3) still use. Default well is a
      # grey 1990s box; we render it as a clean white card to match
      # bslib::card and avoid a visual style clash.
      ".well {",
      "  background: #ffffff !important;",
      "  border: 1px solid #e2e8f0 !important;",
      "  border-radius: 12px !important;",
      "  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);",
      "  padding: 1.25rem !important;",
      "  margin-bottom: 1rem;",
      "}",
      ".well h3, .well h4, .well h5 {",
      "  font-weight: 600;",
      "  color: #0f172a;",
      "}",
      # Title-panel headers (legacy fluidPage(titlePanel(...))):
      # tighten spacing and weight so they sit visually closer to
      # bslib::card_header titles.
      ".navbar + .container-fluid > h2, ",
      ".navbar + .container-fluid > h3 { ",
      "  font-weight: 700; ",
      "  letter-spacing: -0.01em; ",
      "  margin-top: 1rem; ",
      "}",
      # Section labels (used in cards/panels for small caps headers)
      ".zzedc-section-label {",
      "  font-size: 0.78rem;",
      "  font-weight: 600;",
      "  text-transform: uppercase;",
      "  letter-spacing: 0.07em;",
      "  color: #64748b;",
      "  margin: 1.25rem 0 0.5rem 0;",
      "}",
      "",
      sep = "\n"
    )))
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
