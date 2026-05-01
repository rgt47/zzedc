
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

  # Module functions are provided by the zzedc package namespace
  # No need to source files - they're loaded via library(zzedc)

  # Helper to get function from zzedc namespace
  get_module_fn <- function(fn_name) {
    tryCatch(
      utils::getFromNamespace(fn_name, "zzedc"),
      error = function(e) NULL
    )
  }

  # Create reactive database connection
  db_conn <- reactive({
    if (!is.null(db_pool)) {
      db_pool
    } else {
      NULL
    }
  })

  # Initialize modules from zzedc package namespace
  tryCatch({
    auth_server_fn <- get_module_fn("auth_server")
    if (!is.null(auth_server_fn)) {
      auth_module <- auth_server_fn("auth", user_input)
    }

    home_server_fn <- get_module_fn("home_server")
    if (!is.null(home_server_fn)) {
      home_server_fn("home", db_conn)
    }

    data_server_fn <- get_module_fn("data_server")
    if (!is.null(data_server_fn)) {
      data_server_fn("data")
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
