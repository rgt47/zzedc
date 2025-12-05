# Home Module
# UI and Server functions for the home dashboard

#' Home Module UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the home dashboard UI
home_ui <- function(id) {
  ns <- NS(id)

  tagList(
    # Hero section
    bslib::card(
      class = "bg-primary text-white mb-4",
      bslib::card_body(
        div(class = "text-center py-4",
          h1(class = "display-4",
             tagList(bsicons::bs_icon("clipboard2-data-fill", size = "2em"),
                    " Welcome to ZZedc Portal")),
          h4(class = "lead", "Electronic Data Capture for Clinical Trials"),
          p("FPFV is planned for 11/2018 • Secure, compliant, and user-friendly"),
          actionButton(ns("intro_video"), "Watch Introductory Video",
                      class = "btn btn-light btn-lg mt-3",
                      icon = icon("play-circle"))
        )
      )
    ),

    # Feature cards
    fluidRow(
      column(6,
        bslib::card(
          full_screen = FALSE,
          bslib::card_header(
            tagList(bsicons::bs_icon("compass", class = "text-primary"), " Getting Started")
          ),
          bslib::card_body(
            h5("How to Use the Application"),
            p("Navigate through the portal using the tabs above:"),
            tags$ul(
              tags$li(strong("EDC:"), " Enter and manage study data"),
              tags$li(strong("Reports:"), " Generate study reports and analytics"),
              tags$li(strong("Data Explorer:"), " Visualize and analyze your data"),
              tags$li(strong("Export:"), " Download data in various formats")
            ),
            actionButton(ns("quick_start"), "Quick Start Guide",
                        class = "btn btn-primary btn-sm")
          )
        )
      ),

      column(6,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("envelope", class = "text-success"), " Contact & Support")
          ),
          bslib::card_body(
            h5("Need Help?"),
            p("Our team is here to support your research:"),
            div(class = "d-grid gap-2",
              tags$a(href = "mailto:rgthomas47@gmail.com",
                    class = "btn btn-outline-success btn-sm",
                    tagList(bsicons::bs_icon("envelope"), " Email Support")),
              tags$a(href = "#", class = "btn btn-outline-info btn-sm",
                    tagList(bsicons::bs_icon("telephone"), " Phone Support")),
              tags$a(href = "#", class = "btn btn-outline-warning btn-sm",
                    tagList(bsicons::bs_icon("chat-dots"), " Live Chat"))
            )
          )
        )
      )
    ),

    # Instrument Import Card
    fluidRow(
      column(12,
        instrument_import_ui("instrument_import")
      )
    ),

    # Additional info cards
    fluidRow(
      column(6,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("file-earmark-text", class = "text-info"), " Documentation")
          ),
          bslib::card_body(
            h5("Study Resources"),
            p("Access important study documents and protocols:"),
            div(class = "list-group list-group-flush",
              tags$a(href = "#", class = "list-group-item list-group-item-action",
                    tagList(bsicons::bs_icon("file-pdf"), " Study Protocol")),
              tags$a(href = "#", class = "list-group-item list-group-item-action",
                    tagList(bsicons::bs_icon("file-text"), " Operations Manual")),
              tags$a(href = "#", class = "list-group-item list-group-item-action",
                    tagList(bsicons::bs_icon("shield-check"), " Data Management Plan"))
            )
          )
        )
      ),

      column(6,
        bslib::card(
          bslib::card_header(
            tagList(bsicons::bs_icon("shield-lock", class = "text-danger"), " Security & Compliance")
          ),
          bslib::card_body(
            h5("Data Protection"),
            p("Your data is protected with enterprise-grade security:"),
            div(class = "row text-center",
              div(class = "col-4",
                bsicons::bs_icon("shield-fill-check", size = "2em", class = "text-success"),
                br(), tags$small("Encrypted")
              ),
              div(class = "col-4",
                bsicons::bs_icon("key-fill", size = "2em", class = "text-warning"),
                br(), tags$small("Authenticated")
              ),
              div(class = "col-4",
                bsicons::bs_icon("file-lock", size = "2em", class = "text-info"),
                br(), tags$small("HIPAA Compliant")
              )
            )
          )
        )
      )
    ),

    # Status bar
    div(class = "mt-4 p-3 bg-light rounded",
      div(class = "row text-center",
        div(class = "col-md-3",
          h4(class = "text-primary", "24/7"),
          tags$small("System Uptime")
        ),
        div(class = "col-md-3",
          h4(class = "text-success", "256-bit"),
          tags$small("SSL Encryption")
        ),
        div(class = "col-md-3",
          h4(class = "text-info", "ISO 27001"),
          tags$small("Certified")
        ),
        div(class = "col-md-3",
          h4(class = "text-warning", "GCP"),
          tags$small("Compliant")
        )
      )
    )
  )
}

#' Home Module Server
#'
#' @param id The namespace id for the module
#' @param db_conn Reactive database connection
#' @return Server function for home module
home_server <- function(id, db_conn = NULL) {
  moduleServer(id, function(input, output, session) {

    # Initialize instrument import module if database connection provided
    if (!is.null(db_conn)) {
      instrument_import_server("instrument_import", db_conn)
    }

    # Quick Start Guide event handler
    observeEvent(input$quick_start, {
      showModal(
        modalDialog(
          title = tagList(icon("rocket"), " ZZedc Quick Start Guide"),
          size = "l",
          easyClose = TRUE,
          footer = modalButton("Got it!"),

          div(
            h4("🚀 Getting Started with ZZedc"),

            tags$div(class = "mb-3",
              h5("Step 1: Authentication"),
              p("Use the test credentials: ", tags$code("test/test"), " for easy access")
            ),

            tags$div(class = "mb-3",
              h5("Step 2: Navigate the Portal"),
              tags$ul(
                tags$li(strong("EDC Tab:"), " Enter and manage clinical data"),
                tags$li(strong("Reports Tab:"), " Generate comprehensive reports"),
                tags$li(strong("Data Explorer:"), " Analyze and visualize data"),
                tags$li(strong("Export Tab:"), " Download data in multiple formats")
              )
            ),

            tags$div(class = "mb-3",
              h5("Step 3: Data Entry"),
              p("In the EDC tab, you can:"),
              tags$ul(
                tags$li("Enter subject data using validated forms"),
                tags$li("Track visit schedules and completion"),
                tags$li("Review data quality metrics")
              )
            ),

            tags$div(class = "mb-3",
              h5("Step 4: Generate Reports"),
              p("Use the Reports menu for:"),
              tags$ul(
                tags$li("Basic data summaries"),
                tags$li("Quality control reports"),
                tags$li("Statistical analysis")
              )
            ),

            tags$hr(),
            p(class = "text-muted", "💡 For detailed documentation, see ZZEDC_USER_GUIDE.md")
          )
        )
      )
    })

    # Intro video event handler
    observeEvent(input$intro_video, {
      showModal(
        modalDialog(
          title = "Introduction Video",
          size = "m",
          easyClose = TRUE,
          footer = modalButton("Close"),
          div(class = "text-center",
            p("📹 Introductory video coming soon!"),
            p("This will contain a guided tour of ZZedc features and workflow.")
          )
        )
      )
    })
  })
}