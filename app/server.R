
server <- function(input, output, session) {

  # Check if enhanced server integration is available
  if (file.exists("gsheets_server_integration.R")) {
    # Use enhanced server if available
    tryCatch({
      source("gsheets_server_integration.R", local = TRUE)
      create_enhanced_server(input, output, session)
      return(NULL)  # Early return for enhanced mode
    }, error = function(e) {
      message("Enhanced server failed, falling back to traditional: ", e$message)
    })
  }

  # Traditional server implementation
  message("Using traditional server implementation")

  # Load module files with error handling
  module_files <- c('R/modules/auth_module.R', 'R/modules/home_module.R', 'R/modules/instrument_import_module.R', 'R/modules/quality_dashboard_module.R', 'R/modules/data_module.R')

  for (module_file in module_files) {
    if (file.exists(module_file)) {
      tryCatch({
        source(module_file, local = TRUE)
      }, error = function(e) {
        message("Warning: Could not load ", module_file, ": ", e$message)
      })
    }
  }

  # Legacy modules (to be converted)
  legacy_files <- c('edc.R', 'savedata.R', 'report1.R', 'report2.R', 'report3.R', 'export.R')

  for (legacy_file in legacy_files) {
    if (file.exists(legacy_file)) {
      tryCatch({
        source(legacy_file, local = TRUE)
      }, error = function(e) {
        message("Warning: Could not load ", legacy_file, ": ", e$message)
      })
    }
  }

  # Create reactive database connection
  db_conn <- reactive({
    if (!is.null(db_pool)) {
      db_pool
    } else {
      NULL
    }
  })

  # Initialize modules (if functions are available)
  tryCatch({
    if (exists("auth_server")) {
      auth_module <- auth_server("auth", user_input)
    }
    if (exists("home_server")) {
      home_server("home", db_conn)
    }
    if (exists("data_server")) {
      data_server("data")
    }
  }, error = function(e) {
    message("Warning: Could not initialize modules: ", e$message)
  })

  # Show login modal if authentication is available
  observe({
    if (exists("user_input") && !is.null(user_input$authenticated) && !user_input$authenticated) {
      if (exists("auth_module") && !is.null(auth_module) && exists("show_login_modal", auth_module)) {
        auth_module$show_login_modal()
      }
    }
  })

}
