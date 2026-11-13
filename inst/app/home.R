output$hometab <- renderUI({
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
          actionButton("intro_video", "Watch Introductory Video", 
                      class = "btn btn-light btn-lg mt-3",
                      icon = icon("play-circle"))
        )
      )
    ),
    
    # Quick-navigation tiles, one per major section, styled to match
    # rgtlab.org's research-card tiles (zzedc:::.rgtlab_tile_styles(),
    # loaded once in the page's own <head> -- ui.R /
    # gsheets_ui_integration.R, not re-injected here): a navy/gold
    # icon circle, serif title, muted description. Each tile is a
    # clickable card (an <a class="action-button">, Shiny's own
    # convention for a link that fires a server-side input) that
    # switches the top navbar to that section's nav_panel value.
    h5(class = "rgtlab-heading mb-3", "Quick Access"),
    bslib::layout_column_wrap(
      width = "200px",
      gap = "1rem",
      class = "mb-4",
      tags$a(
        id = "hometile_edc", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("clipboard2-pulse", size = "1.1rem")),
        h6("EDC Forms"),
        tags$p(class = "rgtlab-desc", "Enter and manage study data")
      ),
      tags$a(
        id = "hometile_reports", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("bar-chart-line", size = "1.1rem")),
        h6("Reports"),
        tags$p(class = "rgtlab-desc", "Study reports and analytics")
      ),
      tags$a(
        id = "hometile_data", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("table", size = "1.1rem")),
        h6("Data Explorer"),
        tags$p(class = "rgtlab-desc", "Visualize and analyze your data")
      ),
      tags$a(
        id = "hometile_export", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("download", size = "1.1rem")),
        h6("Export"),
        tags$p(class = "rgtlab-desc", "Download data in various formats")
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
            p("Click a tile above, or use the tabs in the navigation bar."),
            actionButton("quick_start", "Quick Start Guide",
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
})

# Quick-access tiles switch the main navbar to the matching section.
# `session` is available here: home.R is sourced inside the running
# server() call (local = TRUE), the same as every other output$<id>
# assignment in this file.
observeEvent(input$hometile_edc, {
  bslib::nav_select("main_nav", selected = "edc", session = session)
})
observeEvent(input$hometile_reports, {
  bslib::nav_select("main_nav", selected = "reports1", session = session)
})
observeEvent(input$hometile_data, {
  bslib::nav_select("main_nav", selected = "data", session = session)
})
observeEvent(input$hometile_export, {
  bslib::nav_select("main_nav", selected = "export", session = session)
})