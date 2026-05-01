# Database-based authentication system using connection pool
authenticate_user <- function(username, password) {

  # Check if database pool exists
  if (!exists("db_pool")) {
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

# Login event handler
observeEvent(input$login_button, {
  
  # Validate input
  if (is.null(input$username) || input$username == "" || 
      is.null(input$password) || input$password == "") {
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
  
  output$uiLogin <- renderUI({ 
  
    composeLoginModal()
  })

composeLoginModal <- function(...){
  showModal(
    modalDialog(
        id        = "loginmodal", 
        size      = 's', 
        textInput('username', 'Login')
        , passwordInput('password', 'Password')
        , actionButton(
            inputId = 'login_button'
          , label   = 'Login'
          , class   = 'btn action-button btn-success'
          , icon    = icon('sign-in')
          ) #/ login-button
        ) #/ modal-contents
    )
     #/ modalDialog
   #/ showModal
}


  output$uiLoginenroll <- renderUI({ 
  
    composeLoginModalenroll()
  })

composeLoginModalenroll <- function(...){
  showModal(
    modalDialog(
        id        = "loginmodalenroll", 
        size      = 's', 
        textInput('usernameenroll', 'Login')
        , passwordInput('passwordenroll', 'Password')
        , actionButton(
            inputId = 'login_button_enroll'
          , label   = 'Login Enroll'
          , class   = 'btn action-button btn-success'
          , icon    = icon('sign-in')
          ) #/ login-button
        ) #/ modal-contents
    )
     #/ modalDialog
   #/ showModal
}
# Legacy credential handling removed for security
# All authentication now handled through database (edc_users table)
  
# set the number of failed attempts allowed before user is locked out

num_fails_to_lockout <- 3

# user_input reactive values now defined in global.R to avoid duplication
