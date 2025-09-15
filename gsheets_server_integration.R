# Google Sheets Server Integration for ZZedc
# Enhances the main server logic to handle Google Sheets forms

#' Create enhanced server logic that includes Google Sheets integration
#' @param input Shiny input object
#' @param output Shiny output object
#' @param session Shiny session object
create_enhanced_server <- function(input, output, session) {

  # Load authentication logic (always needed)
  source("auth.R", local = TRUE)

  # Check if Google Sheets integration is available
  if (exists("gsheets_integration_data")) {
    message("Initializing Google Sheets server integration")
    initialize_gsheets_server(input, output, session)
  } else {
    message("No Google Sheets integration found, using traditional forms")
  }

  # Initialize traditional modules
  initialize_traditional_server(input, output, session)

  # Initialize setup management
  initialize_setup_server(input, output, session)

  # Session management
  session$onSessionEnded(function() {
    message("Session ended for user: ", user_input$username %||% "unknown")
  })
}

#' Initialize Google Sheets server logic
initialize_gsheets_server <- function(input, output, session) {

  gsheets_data <- get("gsheets_integration_data", envir = .GlobalEnv)

  # Generate form UIs
  for (i in 1:nrow(gsheets_data$forms_data$forms_overview)) {
    form_name <- gsheets_data$forms_data$forms_overview$workingname[i]

    # Create closure to capture form_name
    local({
      local_form_name <- form_name

      output[[paste0("gsheets_form_", local_form_name)]] <- renderUI({
        if (!user_input$authenticated) {
          div(class = "alert alert-warning",
            h4("Authentication Required"),
            p("Please log in to access forms.")
          )
        } else {
          generate_form_ui(local_form_name, gsheets_data$forms_data)
        }
      })
    })
  }

  # Generate form server logic (save handlers)
  generate_gsheets_form_server(gsheets_data$forms_data, input, output, session)

  # Forms overview outputs
  output$db_status <- renderText({
    if (file.exists(cfg$database$path)) {
      con <- RSQLite::dbConnect(RSQLite::SQLite(), cfg$database$path)
      tables <- RSQLite::dbListTables(con)
      user_count <- 0
      if ("edc_users" %in% tables) {
        user_count <- RSQLite::dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users WHERE active = 1")$count
      }
      RSQLite::dbDisconnect(con)

      paste("✅ Database connected\n",
            "Tables:", length(tables), "\n",
            "Active users:", user_count)
    } else {
      "❌ Database not found"
    }
  })

  # Form management handlers
  observeEvent(input$refresh_gsheets, {
    showModal(modalDialog(
      title = "Refresh from Google Sheets",
      "This will reload configuration from Google Sheets. Continue?",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_refresh", "Refresh", class = "btn-warning")
      )
    ))
  })

  observeEvent(input$confirm_refresh, {
    removeModal()

    withProgress(message = "Refreshing from Google Sheets...", {
      tryCatch({
        # Re-run the Google Sheets setup
        source("setup_from_gsheets.R")

        # Get current project name from config or default
        project_name <- "zzedc_project" # Would get from current config

        incProgress(0.5, detail = "Reading Google Sheets...")

        success <- setup_zzedc_from_gsheets_complete(
          project_name = project_name
        )

        incProgress(1.0, detail = "Complete!")

        if (success) {
          shinyalert::shinyalert("Success",
            "Configuration refreshed from Google Sheets! Please restart the application to see changes.",
            type = "success")
        } else {
          shinyalert::shinyalert("Error",
            "Failed to refresh from Google Sheets. Check the console for details.",
            type = "error")
        }

      }, error = function(e) {
        shinyalert::shinyalert("Error",
          paste("Refresh failed:", e$message),
          type = "error")
      })
    })
  })

  observeEvent(input$verify_setup, {
    withProgress(message = "Verifying setup...", {
      tryCatch({
        source("gsheets_auth_builder.R")
        source("gsheets_dd_builder.R")

        incProgress(0.3, detail = "Checking authentication...")
        auth_ok <- verify_auth_system(cfg$database$path)

        incProgress(0.6, detail = "Checking data dictionary...")
        dd_ok <- verify_dd_system(cfg$database$path)

        incProgress(1.0, detail = "Complete!")

        if (auth_ok && dd_ok) {
          shinyalert::shinyalert("Success",
            "✅ Setup verification passed! System is ready.",
            type = "success")
        } else {
          shinyalert::shinyalert("Warning",
            "⚠️ Setup verification found issues. Check console for details.",
            type = "warning")
        }

      }, error = function(e) {
        shinyalert::shinyalert("Error",
          paste("Verification failed:", e$message),
          type = "error")
      })
    })
  })
}

#' Initialize traditional server modules
initialize_traditional_server <- function(input, output, session) {

  # Only load traditional modules if Google Sheets forms are not available
  if (!exists("gsheets_integration_data")) {
    # Load traditional EDC forms
    if (file.exists("edc.R")) {
      source("edc.R", local = TRUE)
    }
  }

  # Always load reports (they work with any database structure)
  if (file.exists("report1.R")) {
    source("report1.R", local = TRUE)
  }
  if (file.exists("report2.R")) {
    source("report2.R", local = TRUE)
  }
  if (file.exists("report3.R")) {
    source("report3.R", local = TRUE)
  }

  # Always load data explorer and export
  if (file.exists("data.R")) {
    source("data.R", local = TRUE)
  }
  if (file.exists("export.R")) {
    source("export.R", local = TRUE)
  }

  # Load home module
  if (file.exists("home.R")) {
    source("home.R", local = TRUE)
  }
}

#' Initialize setup management server
initialize_setup_server <- function(input, output, session) {

  # Current configuration display
  output$current_config_display <- renderText({
    config_info <- c()

    # Database info
    if (exists("cfg") && !is.null(cfg$database$path)) {
      db_path <- cfg$database$path
      config_info <- c(config_info, paste("Database:", db_path))
      config_info <- c(config_info, paste("Database exists:", file.exists(db_path)))

      if (file.exists(db_path)) {
        con <- RSQLite::dbConnect(RSQLite::SQLite(), db_path)
        tables <- RSQLite::dbListTables(con)
        RSQLite::dbDisconnect(con)
        config_info <- c(config_info, paste("Database tables:", length(tables)))
      }
    }

    # Google Sheets integration status
    if (exists("gsheets_integration_data")) {
      gsheets_data <- get("gsheets_integration_data", envir = .GlobalEnv)
      config_info <- c(config_info, "")
      config_info <- c(config_info, "Google Sheets Integration: ✅ ACTIVE")
      config_info <- c(config_info, paste("Forms available:", nrow(gsheets_data$forms_data$forms_overview)))
    } else {
      config_info <- c(config_info, "")
      config_info <- c(config_info, "Google Sheets Integration: ❌ NOT ACTIVE")
    }

    # Forms directory
    if (dir.exists("forms_generated")) {
      form_files <- list.files("forms_generated", pattern = "\\.R$")
      config_info <- c(config_info, paste("Generated form files:", length(form_files)))
    }

    paste(config_info, collapse = "\n")
  })

  # Google Sheets setup handler
  observeEvent(input$run_gsheets_setup, {

    auth_sheet <- input$auth_sheet_name
    dd_sheet <- input$dd_sheet_name
    project <- input$project_name

    if (auth_sheet == "" || dd_sheet == "" || project == "") {
      shinyalert::shinyalert("Error", "Please fill in all required fields.", type = "error")
      return()
    }

    # Show progress
    shinyjs::show("setup_progress")
    shinyjs::html("setup_progress .progress-bar", "")
    shinyjs::runjs("$('#setup_progress .progress-bar').css('width', '0%');")

    withProgress(message = "Setting up from Google Sheets...", {

      tryCatch({
        source("setup_from_gsheets.R")

        incProgress(0.2, detail = "Authenticating with Google...")
        shinyjs::runjs("$('#setup_progress .progress-bar').css('width', '20%');")

        incProgress(0.4, detail = "Reading authentication data...")
        shinyjs::runjs("$('#setup_progress .progress-bar').css('width', '40%');")

        incProgress(0.6, detail = "Reading data dictionary...")
        shinyjs::runjs("$('#setup_progress .progress-bar').css('width', '60%');")

        incProgress(0.8, detail = "Building database...")
        shinyjs::runjs("$('#setup_progress .progress-bar').css('width', '80%');")

        success <- setup_zzedc_from_gsheets_complete(
          auth_sheet_name = auth_sheet,
          dd_sheet_name = dd_sheet,
          project_name = project
        )

        incProgress(1.0, detail = "Complete!")
        shinyjs::runjs("$('#setup_progress .progress-bar').css('width', '100%');")

        if (success) {
          shinyalert::shinyalert("Success",
            paste("✅ Setup completed successfully!",
                  "\n\nPlease restart the application to see your new forms.",
                  "\nUse the generated launch script: launch_", gsub("[^A-Za-z0-9]", "_", project), ".R"),
            type = "success")
        } else {
          shinyalert::shinyalert("Error",
            "❌ Setup failed. Check the R console for detailed error messages.",
            type = "error")
        }

      }, error = function(e) {
        shinyalert::shinyalert("Error",
          paste("Setup failed:", e$message,
                "\n\nCommon issues:",
                "\n• Google Sheets not found or not accessible",
                "\n• Internet connection problems",
                "\n• Google authentication expired"),
          type = "error")
      })
    })

    shinyjs::hide("setup_progress")
  })

  # Traditional setup handler
  observeEvent(input$run_traditional_setup, {
    withProgress(message = "Running traditional setup...", {
      tryCatch({
        if (file.exists("setup_database.R")) {
          source("setup_database.R")
          shinyalert::shinyalert("Success",
            "Traditional setup completed! Please restart the application.",
            type = "success")
        } else {
          shinyalert::shinyalert("Error",
            "setup_database.R not found!",
            type = "error")
        }
      }, error = function(e) {
        shinyalert::shinyalert("Error",
          paste("Traditional setup failed:", e$message),
          type = "error")
      })
    })
  })

  # Database import handler
  observeEvent(input$import_database, {
    req(input$import_db)

    file_path <- input$import_db$datapath
    file_name <- input$import_db$name

    if (!grepl("\\.db$", file_name)) {
      shinyalert::shinyalert("Error", "Please select a .db file", type = "error")
      return()
    }

    withProgress(message = "Importing database...", {
      tryCatch({
        # Copy to data directory
        new_path <- file.path("data", paste0("imported_", Sys.Date(), "_", file_name))

        if (!dir.exists("data")) {
          dir.create("data")
        }

        file.copy(file_path, new_path)

        shinyalert::shinyalert("Success",
          paste("Database imported to:", new_path,
                "\n\nUpdate your config.yml to use this database."),
          type = "success")

      }, error = function(e) {
        shinyalert::shinyalert("Error",
          paste("Import failed:", e$message),
          type = "error")
      })
    })
  })
}

#' Helper function for null coalescing
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (is.character(x) && x == "")) y else x
}