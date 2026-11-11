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
    initialize_gsheets_server(input, output, session, user_input)
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
initialize_gsheets_server <- function(input, output, session, user_input) {

  gsheets_data <- get("gsheets_integration_data", envir = .GlobalEnv)

  # Initialize validation cache and load rules from database
  source("R/validation_cache.R", local = TRUE)
  setup_global_validation_cache()

  tryCatch({
    # The application's pool (global.R), not a direct RSQLite
    # connection to cfg$database$path: the pool follows the configured
    # backend and its encryption.
    result <- load_validation_rules_from_db(db_pool)
    if (result$count > 0) {
      message("Loaded ", result$count, " validation rules for real-time validation")
    }
  }, error = function(e) {
    warning("Could not load validation rules: ", e$message)
  })

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
  generate_gsheets_form_server(gsheets_data$forms_data, input, output, session,
                                user_input)

  # Forms overview outputs
  output$db_status <- renderText({
    tryCatch({
      tables <- DBI::dbListTables(db_pool)
      user_count <- 0
      if ("edc_users" %in% tables) {
        user_count <- DBI::dbGetQuery(db_pool, "SELECT COUNT(*) as count FROM edc_users WHERE active = 1")$count
      }
      paste("✅ Database connected (", db_config$db_backend, ")\n",
            "Tables:", length(tables), "\n",
            "Active users:", user_count)
    }, error = function(e) {
      paste("❌ Database not available:", e$message)
    })
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
    run_gsheets_import(input$refresh_sheet_id)
  })

  # Verify through the application's pool, so it works on every
  # backend. (It used to source the SQLite-only builders and check the
  # legacy edc_forms tables, which the current importer does not use.)
  observeEvent(input$verify_setup, {
    tryCatch({
      count <- function(sql) {
        tryCatch(DBI::dbGetQuery(db_pool, sql)[[1]][1], error = function(e) NA)
      }
      users <- count("SELECT COUNT(*) FROM edc_users WHERE active = 1")
      forms <- count("SELECT COUNT(*) FROM crf_definitions")
      ok <- isTRUE(users > 0) && isTRUE(forms > 0)
      shinyalert::shinyalert(
        if (ok) "Setup looks complete" else "Setup incomplete",
        paste0("Active users: ", users, "\nForms: ", forms,
               if (!ok) "\n\nImport users and forms from Google Sheets, or add them in the application." else ""),
        type = if (ok) "success" else "warning")
    }, error = function(e) {
      shinyalert::shinyalert("Error", paste("Verification failed:", e$message), type = "error")
    })
  })
}


#' Import from Google Sheets into the running study (any backend)
#'
#' The application's Google Sheets actions used to source
#' setup_from_gsheets.R from the application directory, which does not
#' contain it, and the legacy builders it used rebuilt SQLite tables.
#' They now call the package's importer against this study's own
#' database (global.R's db_config), adding new users, forms, and rules
#' and leaving existing ones unchanged.
run_gsheets_import <- function(sheet_id) {
  if (is.null(sheet_id) || !nzchar(trimws(sheet_id))) {
    shinyalert::shinyalert("Google Sheets ID needed",
      "Enter the workbook's ID or URL first.", type = "error")
    return(invisible(NULL))
  }
  withProgress(message = "Importing from Google Sheets...", value = 0.3, {
    res <- tryCatch(
      zzedc::setup_zzedc_from_gsheets(
        sheet_id = trimws(sheet_id),
        adapter_config = db_config,
        create_database = FALSE,
        imported_by = user_input$username %||% "gsheets_import",
        salt = zzedc::resolve_auth_salt(cfg)
      ),
      error = function(e) list(success = FALSE, error = conditionMessage(e))
    )
  })
  if (!is.null(res$error) && is.null(res$users)) {
    shinyalert::shinyalert("Import failed", res$error, type = "error")
    return(invisible(res))
  }
  summary <- paste0(
    "Users: ", res$users$imported %||% 0, " added, ", res$users$skipped %||% 0,
    " already present\n",
    "Forms: ", res$forms$imported_forms %||% 0, " added (",
    res$forms$imported_fields %||% 0, " fields), ", res$forms$skipped %||% 0,
    " already present\n",
    "Validation rules: ", res$validation_rules$imported %||% 0, " imported",
    if (!isTRUE(res$success)) "\n\nSome items failed; see the R console for details." else
      "\n\nReload the page to see new forms."
  )
  if (!isTRUE(res$success)) print(res$errors)
  shinyalert::shinyalert(
    if (isTRUE(res$success)) "Import complete" else "Import finished with errors",
    summary, type = if (isTRUE(res$success)) "success" else "warning")
  invisible(res)
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
  if (file.exists("report4.R")) {
    source("report4.R", local = TRUE)
  }

  # Data Explorer is a real Shiny module (R/data_module.R), not a flat
  # script like the files above -- previously nothing here ever
  # called data_server(), so its outputs (data-*) were never bound to
  # anything despite data_ui() rendering a working-looking control
  # panel. (The `if (file.exists("data.R"))` this replaced always
  # evaluated FALSE: no such file was ever shipped.)
  data_server_fn <- tryCatch(
    utils::getFromNamespace("data_server", "zzedc"),
    error = function(e) NULL
  )
  if (!is.null(data_server_fn)) {
    data_server_fn("data")
  }

  # Same reasoning and the same getFromNamespace() pattern as
  # data_server above: cfr_compliance_server() and
  # admin_dashboard_server() were never called anywhere in inst/app/,
  # so the Compliance and Admin tabs this file's companion
  # gsheets_ui_integration.R now renders would otherwise show a
  # working-looking UI with no reactive logic behind any of it --
  # including both electronic-signature observeEvent handlers,
  # which were themselves still stubs until this same change (see
  # R/cfr_compliance_module.R).
  #
  # user_input is this session's reactiveValues login state (defined
  # in server.R, in scope here via lexical scoping since this file is
  # sourced with local = TRUE into server()'s own environment -- the
  # same way initialize_gsheets_server() above already relies on it).
  # Both user_id and user_session are passed as the forms each
  # module's own code already expects: cfr_compliance_server() calls
  # user_id() as a function, so it needs a live reactive, not a
  # snapshot taken before login happens; admin_dashboard_server()
  # reads user_session$role directly as a reactiveValues object.
  cfr_compliance_server_fn <- tryCatch(
    utils::getFromNamespace("cfr_compliance_server", "zzedc"),
    error = function(e) NULL
  )
  if (!is.null(cfr_compliance_server_fn)) {
    cfr_compliance_server_fn("compliance", user_id = reactive(user_input$user_id))
  }

  admin_dashboard_server_fn <- tryCatch(
    utils::getFromNamespace("admin_dashboard_server", "zzedc"),
    error = function(e) NULL
  )
  if (!is.null(admin_dashboard_server_fn)) {
    # db_path and db_adapter come from global.R. Without db_path the
    # module defaulted to "./data/zzedc.db" relative to the app
    # directory, so the Backup tab copied a file that was not the
    # study database (or did not exist).
    admin_dashboard_server_fn("admin", db_pool = db_pool, user_session = user_input,
                              db_path = reactive(db_path),
                              db_adapter = db_adapter)
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

    # Database info, from the database the application actually opened
    # (global.R's db_config/db_path/db_pool).
    if (exists("db_config")) {
      config_info <- c(config_info, paste("Database backend:", db_config$db_backend))
      if (!is.na(db_path)) {
        config_info <- c(config_info, paste("Database:", db_path))
        config_info <- c(config_info, paste("Database exists:", file.exists(db_path)))
      }
      tables <- tryCatch(DBI::dbListTables(db_pool), error = function(e) character(0))
      config_info <- c(config_info, paste("Database tables:", length(tables)))
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

  # Google Sheets import into this study. It used to source
  # setup_from_gsheets.R from the application directory, which does
  # not contain that file, so it failed every time; see
  # run_gsheets_import().
  observeEvent(input$run_gsheets_setup, {
    run_gsheets_import(input$gsheets_sheet_id)
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
