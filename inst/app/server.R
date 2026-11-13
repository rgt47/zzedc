
server <- function(input, output, session) {

  # HTTPS (security.https_only, or the 'regulated' profile). A session
  # that did not arrive over HTTPS gets a notice and nothing else: no
  # module starts, so no login form or data is served over it.
  if (zzedc::https_required(cfg)) {
    https <- zzedc::session_https_status(session)
    if (!https$ok) {
      message("Refused session: HTTPS is required (", https$reason, ")")
      shiny::showModal(shiny::modalDialog(
        title = "A secure (HTTPS) connection is required",
        "This study can only be used over HTTPS. Use the study's https:// ",
        "address, or ask the study's technical lead.",
        footer = NULL, easyClose = FALSE
      ))
      return(invisible(NULL))
    }
  }

  # Per-session authentication state. Previously created once in
  # global.R, which runs once per R process and so was the same
  # single reactiveValues object shared by every concurrent browser
  # session -- one user's login was visible, unauthenticated, to
  # every other open session. Creating it here, as a local binding
  # of this per-session server() call, means everything sourced
  # below (directly or transitively, all with local = TRUE: auth.R,
  # edc.R, gsheets_server_integration.R, gsheets_form_loader.R) picks
  # up THIS session's user_input via lexical scoping instead of
  # falling through to a shared global one.
  user_session <- shiny::reactiveValues(
    authenticated = FALSE,
    authentication_timestamp = NULL,
    user_id = NULL,
    username = NULL,
    full_name = NULL,
    role = NULL,
    site_id = NULL,
    must_change_password = FALSE,
    last_activity = Sys.time(),
    session_start = Sys.time()
  )
  user_input <- user_session

  # If enhanced server integration is present and loads successfully,
  # use it and short-circuit. The previous `return(NULL)` was inside
  # a `tryCatch` body and so returned only from the tryCatch, not
  # from this function; both paths then ran. Capture the success of
  # the enhanced load and return from `server` explicitly.
  enhanced_loaded <- FALSE
  if (file.exists("gsheets_server_integration.R")) {
    enhanced_loaded <- tryCatch({
      source("gsheets_server_integration.R", local = TRUE)
      create_enhanced_server(input, output, session)
      TRUE
    }, error = function(e) {
      message("Enhanced server failed, falling back to traditional: ",
              e$message)
      FALSE
    })
  }
  if (enhanced_loaded) return(invisible(NULL))

  # The fallback below logs in through the package's auth_server(),
  # which has no lockout and records nothing in the audit trail. Under
  # the 'regulated' profile it is not served.
  if (zzedc::get_security_profile() == "regulated") {
    message("Refused session: the main server failed to load and the ",
            "fallback login is not audited")
    shiny::showModal(shiny::modalDialog(
      title = "The application could not start correctly",
      "Contact the study's technical lead (see the application log).",
      footer = NULL, easyClose = FALSE
    ))
    return(invisible(NULL))
  }

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
      data_server_fn("data", user_id = reactive(user_input$user_id))
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
