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
    app_title <- if (exists("cfg", inherits = TRUE)) {
      get("cfg", inherits = TRUE)$app$name %||% "ZZedc - Electronic Data Capture"
    } else {
      "ZZedc - Electronic Data Capture"
    }
    ui_content <- bslib::page_navbar(
  title = div(
    img(src="brain2.png", height="30px", style="margin-right: 10px;"),
    app_title
  ),
  # Palette/fonts match rgtlab.org (the maintainer's lab site,
  # source ~/prj/web/rgtlab/custom.scss): UCSD navy/gold identity,
  # Newsreader serif headings, Public Sans body text, cream
  # background. Same tokens as the enhanced UI's theme
  # (gsheets_ui_integration.R) so this fallback path looks identical
  # if it's ever the one that loads.
  theme = bslib::bs_theme(
    version = 5,
    primary   = "#182B49",
    secondary = "#00629B",
    success   = "#2e7d32",
    info      = "#0277bd",
    warning   = "#ef6c00",
    danger    = "#c62828",
    bg        = "#FBFAF6",
    fg        = "#1c2733",
    base_font    = bslib::font_google("Public Sans"),
    heading_font = bslib::font_google("Newsreader"),
    "navbar-bg" = "#FBFAF6",
    "card-border-color"  = "#e3e0d6",
    "card-cap-bg"        = "#ffffff",
    "card-bg"            = "#ffffff",
    "border-radius"      = "4px",
    "border-radius-sm"   = "4px",
    "border-radius-lg"   = "4px"
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
    zzedc:::.rgtlab_tile_styles(),
    zzedc:::.rgtlab_chrome_styles(),
    # Inline UX polish: cards, headers, value boxes, DT tables,
    # accordion typography. Mirrors the zzpower aesthetic so the
    # two apps feel like siblings, retinted to the rgtlab palette
    # above (zzedc:::.rgtlab_chrome_styles() handles the navbar
    # itself; this covers this fallback UI's other components).
    tags$style(HTML(paste(
      ".card {",
      "  border: 1px solid #e3e0d6 !important;",
      "  box-shadow: 0 1px 2px rgba(24, 43, 73, 0.04);",
      "  border-radius: 4px;",
      "}",
      ".card-header {",
      "  background: #ffffff !important;",
      "  border-bottom: 1px solid #f3f1ea !important;",
      "  font-weight: 600;",
      "  letter-spacing: 0.01em;",
      "}",
      ".bslib-value-box {",
      "  border-radius: 4px !important;",
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
      "  background: #F3F1EA;",
      "  border-bottom: 2px solid #d8d4c6 !important;",
      "  font-weight: 600;",
      "  font-size: 0.82rem;",
      "  letter-spacing: 0.03em;",
      "  text-transform: uppercase;",
      "  color: #182B49;",
      "}",
      "table.dataTable tbody td {",
      "  border-top: 1px solid #f3f1ea !important;",
      "  padding: 0.6rem 0.75rem !important;",
      "}",
      "table.dataTable tbody td.dt-right {",
      "  font-variant-numeric: tabular-nums;",
      "  color: #1c2733;",
      "}",
      ".accordion-button {",
      "  font-weight: 600;",
      "  font-size: 0.95rem;",
      "  letter-spacing: 0.01em;",
      "}",
      ".btn { border-radius: 4px; font-weight: 500; }",
      ".btn-sm { font-size: 0.82rem; padding: 0.3rem 0.65rem; }",
      # Re-skin shiny::wellPanel (Bootstrap .well) which several
      # legacy tabs (Export, Report 3) still use. Default well is a
      # grey 1990s box; we render it as a clean white card to match
      # bslib::card and avoid a visual style clash.
      ".well {",
      "  background: #ffffff !important;",
      "  border: 1px solid #e3e0d6 !important;",
      "  border-radius: 4px !important;",
      "  box-shadow: 0 1px 2px rgba(24, 43, 73, 0.04);",
      "  padding: 1.25rem !important;",
      "  margin-bottom: 1rem;",
      "}",
      ".well h3, .well h4, .well h5 {",
      "  font-weight: 600;",
      "  color: #182B49;",
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
      "  color: #7A5000;",
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
      title = tagList(safe_icon("file-text"), "Activity Summary"),
      value = "report1",
      uiOutput("rep1")
    ),

    bslib::nav_panel(
      title = tagList(safe_icon("shield-check"), "Data Quality"),
      value = "report2",
      uiOutput("rep2")
    ),

    bslib::nav_panel(
      title = tagList(safe_icon("graph-up"), "Domain Breakdown"),
      value = "report3",
      uiOutput("htable")
    ),

    bslib::nav_panel(
      title = tagList(safe_icon("file-person"), "Personal Statement"),
      value = "report4",
      uiOutput("rep4")
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

  # Compliance (electronic signatures, training records) and Admin
  # (user management, backup/restore, audit trail, system config)
  # tabs. Mirrors the same two tabs added to gsheets_ui_integration.R's
  # create_enhanced_ui() -- this traditional UI block is what actually
  # renders whenever that enhanced path fails, which it currently
  # always does, every request (a separate, pre-existing bug in
  # home.R unrelated to these tabs: `source("home.R", local = TRUE)`
  # assigns to a top-level `output$hometab` that does not exist at
  # UI-generation time, so create_enhanced_ui() throws and ui.R falls
  # back to this block). The server-side mounting in
  # initialize_traditional_server() runs unconditionally either way,
  # so these tabs are functional regardless of which UI path wins.
  bslib::nav_panel(
    title = tagList(safe_icon("patch-check-fill"), "Compliance"),
    value = "compliance",
    safe_module_ui("cfr_compliance_ui", "compliance", "Compliance module not available")
  ),

  bslib::nav_panel(
    title = tagList(safe_icon("shield-lock-fill"), "Admin"),
    value = "admin",
    safe_module_ui("admin_dashboard_ui", "admin", "Admin dashboard not available")
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
