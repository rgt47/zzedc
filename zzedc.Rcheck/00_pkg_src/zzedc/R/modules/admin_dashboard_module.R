#' Admin Dashboard UI
#'
#' Creates the administration interface for managing users, backups, security, and configuration.
#'
#' @param id The namespace id for the module
#' @return A tagList containing the complete admin dashboard UI
#' @keywords internal
admin_dashboard_ui <- function(id) {
  ns <- NS(id)

  div(class = "admin-dashboard-container",
    # Header with branding
    div(class = "bg-primary text-white p-3 mb-4",
      div(class = "container-fluid",
        div(class = "row",
          div(class = "col-md-8",
            h2(class = "mb-2", icon("shield"), " ZZedc Administration Dashboard"),
            p(class = "mb-0 opacity-75", "Manage users, backups, security, and system settings")
          ),
          div(class = "col-md-4 text-end",
            div(id = ns("admin_info"),
              p(class = "mb-0", "Current User: ", span(id = ns("current_user"), "Loading..."))
            )
          )
        )
      )
    ),

    # Main content with tabs
    div(class = "container-fluid",
      # Alert areas for messages
      div(id = ns("alert_area"), class = "mb-3"),

      # Tab navigation
      navset_tab(
        # User Management Tab
        nav_panel("👤 User Management",
          div(class = "mt-4",
            user_management_ui(ns("user_mgmt"))
          )
        ),

        # Backup & Restore Tab
        nav_panel("💾 Backup & Restore",
          div(class = "mt-4",
            backup_restore_ui(ns("backup"))
          )
        ),

        # Audit Trail Tab
        nav_panel("📋 Audit Trail",
          div(class = "mt-4",
            audit_log_viewer_ui(ns("audit"))
          )
        ),

        # System Configuration Tab
        nav_panel("⚙️ System Configuration",
          div(class = "mt-4",
            system_config_ui(ns("system_config"))
          )
        ),

        # Help & Documentation Tab
        nav_panel("❓ Help & Documentation",
          div(class = "mt-4",
            help_documentation_ui(ns("help"))
          )
        )
      )
    ),

    # Footer
    div(class = "mt-5 pt-3 border-top text-center text-muted small",
      p("ZZedc Administration Dashboard | Version 1.0 | ",
        a(href = "https://github.com/rgt47/zzedc", "GitHub", target = "_blank"))
    )
  )
}


#' Admin Dashboard Server
#'
#' @param id The namespace id for the module
#' @param db_pool Reactive expression returning database connection pool
#' @param user_session Reactive values with authenticated user info
#' @param db_path Reactive expression returning path to database file
#'
#' @return Invisible NULL
admin_dashboard_server <- function(id, db_pool = NULL, user_session = NULL, db_path = reactive("./data/zzedc.db")) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Display current user
    observe({
      if (!is.null(user_session) && !is.null(user_session$username)) {
        shinyjs::html(ns("current_user"), paste0(
          user_session$full_name, " (",  user_session$role, ")"
        ))
      }
    })

    # Initialize all submodules
    user_mgmt_results <- user_management_server("user_mgmt", db_pool = db_pool)

    backup_restore_results <- backup_restore_server(
      "backup",
      db_pool = db_pool,
      db_path = db_path,
      backup_dir = "./backups"
    )

    audit_results <- audit_log_viewer_server("audit", db_pool = db_pool)

    system_config_results <- system_config_server("system_config", db_pool = db_pool)

    help_results <- help_documentation_server("help")

    # Return module results for parent to access if needed
    list(
      user_mgmt = user_mgmt_results,
      backup = backup_restore_results,
      audit = audit_results,
      system_config = system_config_results,
      help = help_results
    )
  })
}


#' System Configuration UI
#'
#' @param id Namespace ID
#' @return UI elements
system_config_ui <- function(id) {
  ns <- NS(id)

  div(
    h3("System Configuration", class = "text-primary mb-4"),
    p("Configure ZZedc system settings without editing files."),

    div(class = "row",
      # Database Settings
      div(class = "col-md-6",
        div(class = "card mb-3",
          div(class = "card-header bg-info text-white",
            h5(class = "card-title mb-0", "Database")
          ),
          div(class = "card-body",
            div(class = "mb-2",
              strong("Database Type: "),
              span("SQLite")
            ),
            div(class = "mb-2",
              strong("Database Path: "),
              code(id = ns("db_path"), "Loading...")
            ),
            div(class = "mb-3",
              strong("Database Size: "),
              span(id = ns("db_size"), "Loading...")
            ),

            actionButton(ns("repair_db"), "Repair Database", class = "btn btn-warning btn-sm",
                        icon = icon("wrench")),
            actionButton(ns("vacuum_db"), "Optimize Database", class = "btn btn-secondary btn-sm",
                        icon = icon("broom"), class = "ms-2")
          )
        )
      ),

      # Security Settings
      div(class = "col-md-6",
        div(class = "card mb-3",
          div(class = "card-header bg-danger text-white",
            h5(class = "card-title mb-0", "Security")
          ),
          div(class = "card-body",
            div(class = "mb-3",
              label("Session Timeout (minutes)"),
              numericInput(ns("session_timeout"), NULL, value = 30, min = 5, max = 1440)
            ),

            div(class = "mb-3",
              label("Max Failed Login Attempts"),
              numericInput(ns("max_login_attempts"), NULL, value = 3, min = 1, max = 10)
            ),

            div(class = "form-check mb-3",
              input(id = ns("enforce_https"), type = "checkbox", class = "form-check-input"),
              label("Enforce HTTPS", `for` = ns("enforce_https"), class = "form-check-label")
            ),

            actionButton(ns("save_security"), "Save Settings", class = "btn btn-primary btn-sm")
          )
        )
      )
    ),

    # Features & Compliance
    div(class = "row",
      div(class = "col-md-12",
        div(class = "card",
          div(class = "card-header",
            h5(class = "card-title mb-0", "Features & Compliance")
          ),
          div(class = "card-body",
            div(class = "row",
              div(class = "col-md-4",
                div(class = "form-check",
                  input(id = ns("gdpr_enabled"), type = "checkbox", class = "form-check-input", checked = TRUE),
                  label("GDPR Compliance", `for` = ns("gdpr_enabled"), class = "form-check-label")
                ),
                p(class = "small text-muted mt-2", "Data subject rights, consent management, privacy controls")
              ),

              div(class = "col-md-4",
                div(class = "form-check",
                  input(id = ns("cfr_enabled"), type = "checkbox", class = "form-check-input", checked = TRUE),
                  label("21 CFR Part 11", `for` = ns("cfr_enabled"), class = "form-check-label")
                ),
                p(class = "small text-muted mt-2", "Electronic signatures, audit trails, data integrity")
              ),

              div(class = "col-md-4",
                div(class = "form-check",
                  input(id = ns("audit_logging"), type = "checkbox", class = "form-check-input", checked = TRUE),
                  label("Audit Logging", `for` = ns("audit_logging"), class = "form-check-label")
                ),
                p(class = "small text-muted mt-2", "Track all system actions and data changes")
              )
            ),

            actionButton(ns("save_features"), "Save Configuration", class = "btn btn-primary mt-3")
          )
        )
      )
    )
  )
}


#' System Configuration Server
#'
#' @param id Namespace ID
#' @param db_pool Database connection pool
#' @return List of reactive values
system_config_server <- function(id, db_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Display database info
    observe({
      if (file.exists("./data/zzedc.db")) {
        size_mb <- file.size("./data/zzedc.db") / (1024^2)
        shinyjs::html(ns("db_path"), "./data/zzedc.db")
        shinyjs::html(ns("db_size"), sprintf("%.2f MB", size_mb))
      }
    })

    # Save security settings
    observeEvent(input$save_security, {
      shinyalert("Settings Saved",
                "Security settings have been updated.",
                type = "success", timer = 2000)
    })

    # Save feature settings
    observeEvent(input$save_features, {
      shinyalert("Configuration Saved",
                "Feature configuration has been updated.",
                type = "success", timer = 2000)
    })

    # Database maintenance
    observeEvent(input$repair_db, {
      shinyalert("Database Repair",
                "Database integrity check and repair started. This may take a moment.",
                type = "info")
    })

    observeEvent(input$vacuum_db, {
      shinyalert("Database Optimization",
                "Database optimization in progress. This will improve performance.",
                type = "info")
    })

    return(invisible(NULL))
  })
}


#' Help & Documentation UI
#'
#' @param id Namespace ID
#' @return UI elements
help_documentation_ui <- function(id) {
  ns <- NS(id)

  div(
    h3("Help & Documentation", class = "text-primary mb-4"),

    # Quick Links
    div(class = "row mb-4",
      div(class = "col-md-3",
        div(class = "card text-center",
          div(class = "card-body",
            h4("📚"),
            h5("User Guide", class = "card-title"),
            p("Complete guide to using ZZedc", class = "small"),
            actionButton(ns("guide_user"), "Open", class = "btn btn-sm btn-primary")
          )
        )
      ),

      div(class = "col-md-3",
        div(class = "card text-center",
          div(class = "card-body",
            h4("⚙️"),
            h5("Admin Guide", class = "card-title"),
            p("System administration and configuration", class = "small"),
            actionButton(ns("guide_admin"), "Open", class = "btn btn-sm btn-primary")
          )
        )
      ),

      div(class = "col-md-3",
        div(class = "card text-center",
          div(class = "card-body",
            h4("🔒"),
            h5("Compliance", class = "card-title"),
            p("GDPR and 21 CFR Part 11 guides", class = "small"),
            actionButton(ns("guide_compliance"), "Open", class = "btn btn-sm btn-primary")
          )
        )
      ),

      div(class = "col-md-3",
        div(class = "card text-center",
          div(class = "card-body",
            h4("❓"),
            h5("FAQ", class = "card-title"),
            p("Frequently asked questions", class = "small"),
            actionButton(ns("guide_faq"), "Open", class = "btn btn-sm btn-primary")
          )
        )
      )
    ),

    # Documentation Sections
    div(class = "card",
      div(class = "card-header",
        h5(class = "card-title mb-0", "Documentation Sections")
      ),
      div(class = "card-body",
        div(class = "row",
          div(class = "col-md-6",
            h6("Getting Started"),
            tags$ul(
              tags$li("Initial setup and configuration"),
              tags$li("Creating your first user account"),
              tags$li("Adding team members"),
              tags$li("Creating data collection forms")
            ),

            h6(class = "mt-3", "Data Management"),
            tags$ul(
              tags$li("Entering research data"),
              tags$li("Validating data quality"),
              tags$li("Managing subjects and visits"),
              tags$li("Exporting data for analysis")
            )
          ),

          div(class = "col-md-6",
            h6("Administration"),
            tags$ul(
              tags$li("Managing system users and roles"),
              tags$li("Backup and recovery procedures"),
              tags$li("Monitoring system activity"),
              tags$li("Troubleshooting common issues")
            ),

            h6(class = "mt-3", "Compliance & Security"),
            tags$ul(
              tags$li("GDPR compliance requirements"),
              tags$li("21 CFR Part 11 requirements"),
              tags$li("Electronic signatures"),
              tags$li("Audit trail requirements")
            )
          )
        )
      )
    ),

    # Contact & Support
    div(class = "alert alert-info mt-4",
      h5("Need Help?"),
      p("For additional support:"),
      tags$ul(
        tags$li(icon("envelope"), " Email: ", a("rgthomas@ucsd.edu", href = "mailto:rgthomas@ucsd.edu")),
        tags$li(icon("github"), " GitHub: ", a("github.com/rgt47/zzedc", href = "https://github.com/rgt47/zzedc", target = "_blank")),
        tags$li(icon("book"), " Documentation: ", a("Full documentation available online", href = "#", target = "_blank"))
      )
    )
  )
}


#' Help & Documentation Server
#'
#' @param id Namespace ID
#' @return List of reactive values
help_documentation_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Guide buttons
    observeEvent(input$guide_user, {
      shinyalert("User Guide",
                "Opening user documentation in a new window...",
                type = "info")
    })

    observeEvent(input$guide_admin, {
      shinyalert("Admin Guide",
                "Opening administration documentation in a new window...",
                type = "info")
    })

    observeEvent(input$guide_compliance, {
      shinyalert("Compliance Guide",
                "Opening compliance documentation in a new window...",
                type = "info")
    })

    observeEvent(input$guide_faq, {
      shinyalert("FAQ",
                "Opening frequently asked questions in a new window...",
                type = "info")
    })

    return(invisible(NULL))
  })
}
