#' Setup Choice Module
#'
#' When ZZedc is launched for the first time (not configured),
#' show user two options: Setup Wizard (visual) or Shell Prompt (CLI)
#'
#' @keywords internal
#' @export

#' Setup Choice UI
#'
#' @param id Namespace ID
#' @return UI elements for setup choice page
setup_choice_ui <- function(id) {
  ns <- NS(id)

  div(class = "setup-choice-container",
    # Full screen background
    div(class = "setup-choice-background",
      style = "
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        padding: 20px;
      ",

      # Main container
      div(class = "setup-choice-main",
        style = "
          background: white;
          border-radius: 8px;
          box-shadow: 0 10px 40px rgba(0,0,0,0.2);
          max-width: 900px;
          width: 100%;
          padding: 40px;
        ",

        # Header
        div(class = "text-center mb-4",
          div(style = "font-size: 48px; margin-bottom: 20px;",
            "🔧"
          ),
          h1(class = "mb-2", "Welcome to ZZedc"),
          p(class = "text-muted", "Choose your setup method to get started")
        ),

        # Two-column choice
        div(class = "row mt-5",
          # Option 1: Setup Wizard
          div(class = "col-md-6 mb-4",
            div(class = "card h-100 border-0 shadow-sm hover-card",
              style = "
                transition: all 0.3s ease;
                cursor: pointer;
                border-top: 4px solid #667eea !important;
              ",
              onmouseover = "this.style.transform='translateY(-5px)'; this.style.boxShadow='0 15px 40px rgba(102,126,234,0.3)';",
              onmouseout = "this.style.transform='translateY(0)'; this.style.boxShadow='0 5px 15px rgba(0,0,0,0.08)';",

              div(class = "card-body text-center",
                div(style = "font-size: 64px; margin-bottom: 20px;",
                  "🎯"
                ),
                h3(class = "card-title", "Setup Wizard"),
                p(class = "card-text text-muted",
                  "Visual, step-by-step configuration"
                ),
                p(class = "card-text small",
                  tags$ul(
                    tags$li("Perfect for non-technical users"),
                    tags$li("5 simple steps"),
                    tags$li("All configuration in web browser")
                  )
                ),
                actionButton(ns("choose_wizard"), "Start Setup Wizard",
                           class = "btn btn-primary btn-lg",
                           icon = icon("chevron-right"))
              )
            )
          ),

          # Option 2: Shell Prompt
          div(class = "col-md-6 mb-4",
            div(class = "card h-100 border-0 shadow-sm hover-card",
              style = "
                transition: all 0.3s ease;
                cursor: pointer;
                border-top: 4px solid #764ba2 !important;
              ",
              onmouseover = "this.style.transform='translateY(-5px)'; this.style.boxShadow='0 15px 40px rgba(118,75,162,0.3)';",
              onmouseout = "this.style.transform='translateY(0)'; this.style.boxShadow='0 5px 15px rgba(0,0,0,0.08)';",

              div(class = "card-body text-center",
                div(style = "font-size: 64px; margin-bottom: 20px;",
                  "⌨️"
                ),
                h3(class = "card-title", "Shell Prompt"),
                p(class = "card-text text-muted",
                  "Command-line configuration"
                ),
                p(class = "card-text small",
                  tags$ul(
                    tags$li("For experienced users/DevOps"),
                    tags$li("Config file based"),
                    tags$li("Fully automated setup")
                  )
                ),
                actionButton(ns("choose_shell"), "Show Shell Instructions",
                           class = "btn btn-secondary btn-lg",
                           icon = icon("terminal"))
              )
            )
          )
        ),

        # Documentation footer
        div(class = "mt-5 pt-4 border-top",
          div(class = "row",
            div(class = "col-md-6",
              h5("📖 Documentation"),
              tags$ul(class = "small",
                tags$li(a(href = "#", "Solo Researcher Quick Start")),
                tags$li(a(href = "#", "AWS/DevOps Setup Guide")),
                tags$li(a(href = "#", "Configuration Reference"))
              )
            ),
            div(class = "col-md-6",
              h5("❓ Questions?"),
              p(class = "small",
                "Email: ", a(href = "mailto:support@example.com", "support@example.com"),
                br(),
                "GitHub: ", a(href = "https://github.com/rgt47/zzedc", "github.com/rgt47/zzedc")
              )
            )
          )
        )
      )
    )
  )
}


#' Setup Choice Server
#'
#' @param id Namespace ID
#' @return Reactive value indicating chosen method
setup_choice_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    chosen_method <- reactiveVal(NULL)

    # User chooses Setup Wizard
    observeEvent(input$choose_wizard, {
      chosen_method("wizard")
      shinyalert(
        "Setup Wizard",
        "The visual setup wizard will now appear.\nClick OK to begin.",
        type = "info",
        closeOnClickOutside = FALSE
      )
    })

    # User chooses Shell Prompt
    observeEvent(input$choose_shell, {
      chosen_method("shell")
      shell_instructions <- "
# ZZedc Shell Setup Instructions
# =============================

## Option 1: Interactive Mode (Recommended for Beginners)

Run this command in your R console:
$ zzedc::init()

This will guide you through a series of questions:
- Study name
- Protocol ID
- PI information
- Admin credentials
- Security settings

Follow the prompts and your project will be created.


## Option 2: Config File Mode (For DevOps/AWS)

1. Copy the config template:
   $ cp inst/templates/zzedc_config_template.yml zzedc_config.yml

2. Edit the config file with your settings:
   $ vim zzedc_config.yml

3. Run setup with the config:
   $ Rscript -e \"zzedc::init(mode='config', config_file='zzedc_config.yml')\"

4. Set the ZZEDC_SALT environment variable:
   $ export ZZEDC_SALT='[salt_from_setup]'

5. Launch ZZedc:
   $ Rscript inst/templates/launch_app.R


## Troubleshooting

If you see 'function not found', ensure zzedc is installed:
  install.packages('zzedc')
  library(zzedc)

If database creation fails, check that you have write permissions
in the current directory.

For more help, see the documentation or contact support.
      "

      shinyalert(
        "Shell Setup Instructions",
        shell_instructions,
        type = "info",
        closeOnClickOutside = FALSE,
        html = TRUE
      )
    })

    return(chosen_method)
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
