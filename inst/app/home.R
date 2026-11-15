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
    
    # Quick-navigation tiles, one per top-nav section (every
    # nav_panel() in gsheets_ui_integration.R except Home itself, in
    # the same order they appear in the nav bar), styled to match
    # rgtlab.org's research-card tiles (zzedc:::.rgtlab_tile_styles(),
    # loaded once in the page's own <head> -- ui.R /
    # gsheets_ui_integration.R, not re-injected here): a navy/gold
    # icon circle, serif title, muted description. Each tile is a
    # clickable card (an <a class="action-button">, Shiny's own
    # convention for a link that fires a server-side input) that
    # switches the top navbar to that section's nav_panel value. One
    # tile per section, rather than a single combined "Reports" tile,
    # so a 12-item nav bar (Basic/Quality/Statistical Reports, Subject
    # Case Report, Setup, Compliance, Corrections, Validation Rules,
    # and Admin all previously reachable only from the crowded top
    # bar) is also reachable from Home -- each tile's icon matches its
    # nav_panel's own icon exactly, so the two stay recognizably paired.
    h5(class = "rgtlab-heading mb-3", "Quick Access"),
    bslib::layout_column_wrap(
      width = "200px",
      gap = "1rem",
      class = "mb-4",
      tags$a(
        id = "hometile_edc", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("clipboard-data", size = "1.1rem")),
        h6("EDC Forms"),
        tags$p(class = "rgtlab-desc", "Enter and manage study data")
      ),
      tags$a(
        id = "hometile_reports1", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("bar-chart", size = "1.1rem")),
        h6("Basic Reports"),
        tags$p(class = "rgtlab-desc", "Core summary tables")
      ),
      tags$a(
        id = "hometile_reports2", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("shield-check", size = "1.1rem")),
        h6("Quality Reports"),
        tags$p(class = "rgtlab-desc", "Data quality and completeness")
      ),
      tags$a(
        id = "hometile_reports3", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("graph-up", size = "1.1rem")),
        h6("Statistical Reports"),
        tags$p(class = "rgtlab-desc", "Analytics across the study")
      ),
      tags$a(
        id = "hometile_report5", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("person-lines-fill", size = "1.1rem")),
        h6("Subject Case Report"),
        tags$p(class = "rgtlab-desc", "One subject's full record")
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
      ),
      tags$a(
        id = "hometile_setup", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("gear", size = "1.1rem")),
        h6("Setup"),
        tags$p(class = "rgtlab-desc", "Forms and Google Sheets management")
      ),
      tags$a(
        id = "hometile_compliance", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("patch-check", size = "1.1rem")),
        h6("Compliance"),
        tags$p(class = "rgtlab-desc", "Electronic signatures and training")
      ),
      tags$a(
        id = "hometile_corrections", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("pencil-square", size = "1.1rem")),
        h6("Corrections"),
        tags$p(class = "rgtlab-desc", "Request, review, and apply")
      ),
      tags$a(
        id = "hometile_rules", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("check2-square", size = "1.1rem")),
        h6("Validation Rules"),
        tags$p(class = "rgtlab-desc", "Edit field-level checks")
      ),
      tags$a(
        id = "hometile_admin", class = "action-button rgtlab-tile text-center",
        href = "#",
        div(class = "rgtlab-ico mx-auto",
            bsicons::bs_icon("shield-lock", size = "1.1rem")),
        h6("Admin"),
        tags$p(class = "rgtlab-desc", "Users, backups, randomization, audit")
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
observeEvent(input$hometile_reports1, {
  bslib::nav_select("main_nav", selected = "reports1", session = session)
})
observeEvent(input$hometile_reports2, {
  bslib::nav_select("main_nav", selected = "reports2", session = session)
})
observeEvent(input$hometile_reports3, {
  bslib::nav_select("main_nav", selected = "reports3", session = session)
})
observeEvent(input$hometile_report5, {
  # nav_tabs[["reports5"]]'s own nav_panel(value = "report5") (singular)
  # is what main_nav actually switches on -- the list key and the
  # value deliberately differ in gsheets_ui_integration.R, so this
  # must match the value, not the key.
  bslib::nav_select("main_nav", selected = "report5", session = session)
})
observeEvent(input$hometile_data, {
  bslib::nav_select("main_nav", selected = "data", session = session)
})
observeEvent(input$hometile_export, {
  bslib::nav_select("main_nav", selected = "export", session = session)
})
observeEvent(input$hometile_setup, {
  bslib::nav_select("main_nav", selected = "setup", session = session)
})
observeEvent(input$hometile_compliance, {
  bslib::nav_select("main_nav", selected = "compliance", session = session)
})
observeEvent(input$hometile_corrections, {
  bslib::nav_select("main_nav", selected = "corrections", session = session)
})
observeEvent(input$hometile_rules, {
  bslib::nav_select("main_nav", selected = "rules", session = session)
})
observeEvent(input$hometile_admin, {
  bslib::nav_select("main_nav", selected = "admin", session = session)
})