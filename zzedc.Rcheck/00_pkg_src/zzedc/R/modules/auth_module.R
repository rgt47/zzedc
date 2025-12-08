# Authentication Module
# UI and Server functions for user authentication

#' Authentication Module UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the login modal UI
auth_ui <- function(id) {
  ns <- NS(id)

  # Return empty div - modal will be shown programmatically
  div(id = ns("auth_container"))
}

#' Authentication Module Server
#'
#' @param id The namespace id for the module
#' @param user_input Reactive values object to store authentication state
#' @return Server function for authentication module
auth_server <- function(id, user_input) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Show login modal when needed
    show_login_modal <- function() {
      showModal(
        modalDialog(
          id = "loginmodal",
          size = "s",
          easyClose = FALSE,
          footer = NULL,

          div(class = "text-center mb-3",
            img(src = "brain2.png", height = "50px"),
            h4("ZZedc Login", class = "mt-2")
          ),

          textInput(ns("username"), "Username",
                   placeholder = "Enter your username"),

          passwordInput(ns("password"), "Password",
                       placeholder = "Enter your password"),

          div(class = "d-grid mt-3",
            actionButton(ns("login_button"), "Login",
                        class = "btn btn-primary btn-block",
                        icon = icon("sign-in-alt"))
          ),

          div(class = "text-center mt-3",
            tags$small(class = "text-muted",
                      "Test credentials: test/test")
          )
        )
      )
    }

    # Login event handler
    observeEvent(input$login_button, {

      # Validate input
      req(input$username, input$password)

      if (input$username == "" || input$password == "") {
        shinyalert("Login Error", "Please enter both username and password", type = "error")
        return()
      }

      # Authenticate user
      auth_result <- authenticate_user(input$username, input$password)

      if (auth_result$success) {
        # Store user session info
        user_input$authenticated <- TRUE
        user_input$user_id <- auth_result$user_id
        user_input$username <- auth_result$username
        user_input$full_name <- auth_result$full_name
        user_input$role <- auth_result$role
        user_input$site_id <- auth_result$site_id

        removeModal()

        shinyalert("Welcome!",
                   paste("Welcome", auth_result$full_name, "- Role:", auth_result$role),
                   type = "success", timer = 3000)
      } else {
        shinyalert("Login Failed", auth_result$message, type = "error")
      }
    })

    # Return functions that can be called from main server
    list(
      show_login_modal = show_login_modal
    )
  })
}

#' Database-based authentication system using connection pool
#'
#' @param username User's login name
#' @param password User's password
#' @return List with success status and user info
authenticate_user <- function(username, password) {

  # Check if database pool exists
  if (!exists("db_pool", envir = .GlobalEnv)) {
    return(list(success = FALSE, message = "Database pool not initialized. Please restart application."))
  }

  tryCatch({
    # Get user record using pool
    user_query <- "SELECT * FROM edc_users WHERE username = ? AND active = 1"
    user_record <- pool::dbGetQuery(db_pool, user_query, params = list(username))

    if (nrow(user_record) == 0) {
      return(list(success = FALSE, message = "Invalid username or account inactive"))
    }

    # Verify password using configuration
    salt <- Sys.getenv(cfg$auth$salt_env_var)
    if (salt == "") {
      salt <- cfg$auth$default_salt
    }
    password_hash <- digest(paste0(password, salt), algo = "sha256")

    if (user_record$password_hash == password_hash) {
      # Update last login using pool
      pool::dbExecute(db_pool, "UPDATE edc_users SET last_login = ? WHERE user_id = ?",
                     params = list(Sys.time(), user_record$user_id))

      return(list(
        success = TRUE,
        user_id = user_record$user_id,
        username = user_record$username,
        full_name = user_record$full_name,
        role = user_record$role,
        site_id = user_record$site_id
      ))
    } else {
      return(list(success = FALSE, message = "Invalid password"))
    }

  }, error = function(e) {
    return(list(success = FALSE, message = paste("Database error:", e$message)))
  })
}
