# Setup Choice Module
#
# The first page of launch_setup_wizard(): create the study in the
# browser wizard, or with commands in the R console.

#' Setup Choice UI
#'
#' @param id Namespace ID
#' @return UI elements for setup choice page
#'
#' @examples
#' \dontrun{
#' # Shown as the first page of launch_setup_wizard().
#' if (interactive()) {
#'   ui <- bslib::page_fluid(setup_choice_ui("choice"))
#'   server <- function(input, output, session) setup_choice_server("choice")
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
setup_choice_ui <- function(id) {
  ns <- NS(id)

  choice_card <- function(title, subtitle, points, button) {
    div(class = "col-md-6 mb-4",
      bslib::card(class = "h-100",
        bslib::card_body(class = "text-center",
          h3(class = "card-title", title),
          p(class = "text-muted", subtitle),
          tags$ul(class = "text-start small", lapply(points, tags$li)),
          button
        )
      )
    )
  }

  div(class = "setup-choice-container",
    div(class = "text-center mb-4",
      h2(class = "mb-2", "Create a new ZZedc study"),
      p(class = "text-muted", "Choose how you would like to set it up.")
    ),
    div(class = "row",
      choice_card(
        "Setup wizard",
        "Step-by-step, in this browser",
        c("Six steps: study, administrator, security, database, team, forms",
          "Explains each database option and checks it against the security profile",
          "Creates the database, config.yml, and a launch script"),
        actionButton(ns("choose_wizard"), "Start the setup wizard",
                     class = "btn btn-primary btn-lg")
      ),
      choice_card(
        "R console",
        "Commands, for scripted or repeatable setups",
        c("One command creates a study with default settings",
          "Scriptable: complete_wizard_setup() takes every wizard setting",
          "Suited to servers, containers, and automation"),
        actionButton(ns("choose_shell"), "Show the commands",
                     class = "btn btn-secondary btn-lg")
      )
    ),
    div(class = "mt-4 pt-3 border-top small text-muted",
      "Documentation: ", code("vignette('getting-started', package = 'zzedc')"),
      " and ", code("vignette('setup-wizard-guide', package = 'zzedc')"), "."
    )
  )
}


#' Setup Choice Server
#'
#' @param id Namespace ID
#' @param on_console Optional function called when the user, having read
#'   the console commands, chooses to close the setup page.
#' @return Reactive value: `NULL` until a choice is made, then
#'   `"wizard"` or `"shell"`.
#'
#' @examples
#' \dontrun{
#' if (interactive()) {
#'   ui <- bslib::page_fluid(setup_choice_ui("choice"))
#'   server <- function(input, output, session) setup_choice_server("choice")
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
setup_choice_server <- function(id, on_console = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    chosen_method <- reactiveVal(NULL)

    observeEvent(input$choose_wizard, {
      chosen_method("wizard")
    })

    observeEvent(input$choose_shell, {
      chosen_method("shell")
      showModal(modalDialog(
        title = "Creating a study from the R console",
        size = "l", easyClose = TRUE,
        p("In R, change to an empty directory for the study, then run one of:"),
        tags$pre(paste(
          "# Ask which database to use (compares the options first)",
          "zzedc::launch_zzedc()",
          "",
          "# Or name it: sqlite, duckdb, postgresql, or mysql",
          "zzedc::launch_zzedc(backend = \"duckdb\")",
          "",
          "# Compare the database options",
          "zzedc::describe_backends()",
          sep = "\n"
        )),
        p("For DuckDB, set ", code("DB_ENCRYPTION_KEY"), " first (",
          code("zzedc::generate_db_key()"), " makes one); an interactive ",
          "session offers to generate it for you."),
        p("For a fully scripted setup, pass every setting to ",
          code("zzedc::complete_wizard_setup()"), "; see ",
          code("vignette('setup-wizard-guide', package = 'zzedc')"), "."),
        footer = tagList(
          modalButton("Back"),
          if (is.function(on_console)) {
            actionButton(ns("close_for_console"), "Close this page", class = "btn btn-secondary")
          }
        )
      ))
    })

    observeEvent(input$close_for_console, {
      removeModal()
      if (is.function(on_console)) on_console()
    })

    chosen_method
  })
}


#' Show Setup Choice Page
#'
#' Conditionally render setup choice page if not configured
#'
#' @param configured Boolean - is system already configured?
#' @param id Namespace ID
#'
#' @return UI or NULL
#' @keywords internal
render_setup_choice <- function(configured = TRUE, id = "setup_choice") {
  if (configured) {
    return(NULL)
  }

  setup_choice_ui(id)
}
