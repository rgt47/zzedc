# Database-based authentication system using connection pool
#
# §11.300 password-lockout note (2026-11-09): this function used to
# have no concept of failed-attempt counting at all, despite
# num_fails_to_lockout being declared below (see its own comment) and
# never read anywhere. failed_login_attempts/locked_at are migrated
# into edc_users by ensure_edc_users_table() (R/db_users.R); a
# database that predates this feature gets them added automatically
# the next time launch_zzedc() runs, the same way must_change_password
# was migrated in.
authenticate_user <- function(username, password) {

  # Check if database pool exists
  if (!exists("db_pool")) {
    return(list(success = FALSE, message = "Database pool not initialized. Please restart application."))
  }

  max_failed_attempts <- if (!is.null(cfg$auth$max_failed_attempts)) {
    as.integer(cfg$auth$max_failed_attempts)
  } else {
    3L
  }
  lockout_duration_minutes <- if (!is.null(cfg$auth$lockout_duration_minutes)) {
    as.numeric(cfg$auth$lockout_duration_minutes)
  } else {
    15
  }

  tryCatch({
    # Get user record using pool
    user_query <- "SELECT * FROM edc_users WHERE username = ? AND active = 1"
    user_record <- pool::dbGetQuery(db_pool, user_query, params = list(username))

    if (nrow(user_record) == 0) {
      return(list(success = FALSE, message = "Invalid username or account inactive"))
    }

    user_id <- user_record$user_id[1]

    # failed_login_attempts/locked_at are NULL (not absent) on a
    # database migrated by ensure_edc_users_table() before any failed
    # attempt has ever been recorded; NA-coerce defensively so a freshly
    # migrated row is treated as "0 failures, not locked" rather than
    # erroring on NA comparisons below.
    failed_attempts <- suppressWarnings(as.integer(user_record$failed_login_attempts[1]))
    if (is.na(failed_attempts)) failed_attempts <- 0L
    locked_at_raw <- user_record$locked_at[1]

    if (!is.null(locked_at_raw) && !is.na(locked_at_raw) && nzchar(as.character(locked_at_raw))) {
      locked_at_time <- as.POSIXct(locked_at_raw, tz = "UTC")
      unlock_time <- locked_at_time + lockout_duration_minutes * 60
      if (Sys.time() < unlock_time) {
        remaining_min <- ceiling(as.numeric(difftime(unlock_time, Sys.time(), units = "mins")))
        return(list(
          success = FALSE,
          message = paste0(
            "Account locked after ", max_failed_attempts,
            " failed login attempts. Try again in ", remaining_min,
            " minute(s), or contact an administrator to unlock it."
          )
        ))
      }

      # Lockout window has elapsed: auto-unlock before continuing, so a
      # correct password on this very attempt is not rejected merely
      # because the row still says "locked" from before the window
      # closed.
      pool::dbExecute(db_pool, "
        UPDATE edc_users SET failed_login_attempts = 0, locked_at = NULL
        WHERE user_id = ?
      ", params = list(user_id))
      failed_attempts <- 0L
      tryCatch(
        log_security_event(
          event_type = "UNLOCK", user_id = username,
          description = "Account automatically unlocked after lockout period expired"
        ),
        error = function(e) NULL
      )
    }

    # Verify password using configuration.
    # cfg$auth$salt_env_var is absent from config.yml files scaffolded
    # by launch_zzedc() (only default_salt is written), and
    # Sys.getenv(NULL) returns every environment variable on the
    # machine rather than "" or erroring, which made the salt == ""
    # check below throw "the condition has length > 1" on every
    # login attempt against a freshly-scaffolded config.
    salt_env_var <- cfg$auth$salt_env_var
    salt <- if (is.character(salt_env_var) && length(salt_env_var) == 1 &&
                  nzchar(salt_env_var)) {
      Sys.getenv(salt_env_var)
    } else {
      ""
    }
    if (salt == "") {
      salt <- cfg$auth$default_salt
    }
    password_hash <- digest(paste0(password, salt), algo = "sha256")

    if (user_record$password_hash == password_hash) {
      # Update last login using pool, and clear any failure count --
      # a successful login is the normal way failed_login_attempts
      # resets, same as locked_at above.
      pool::dbExecute(db_pool, "
        UPDATE edc_users
        SET last_login = ?, failed_login_attempts = 0, locked_at = NULL
        WHERE user_id = ?
      ", params = list(Sys.time(), user_id))

      return(list(
        success = TRUE,
        user_id = user_record$user_id,
        username = user_record$username,
        full_name = user_record$full_name,
        role = user_record$role,
        site_id = user_record$site_id,
        # NULL (not FALSE) on a database that predates this column
        # and has not yet been migrated by ensure_edc_users_table();
        # isTRUE() downstream treats that the same as FALSE.
        must_change_password = isTRUE(as.logical(user_record$must_change_password))
      ))
    } else {
      new_failed_attempts <- failed_attempts + 1L
      now_locked <- new_failed_attempts >= max_failed_attempts

      if (now_locked) {
        pool::dbExecute(db_pool, "
          UPDATE edc_users SET failed_login_attempts = ?, locked_at = ?
          WHERE user_id = ?
        ", params = list(new_failed_attempts,
                          format(Sys.time(), tz = "UTC", "%Y-%m-%d %H:%M:%S"),
                          user_id))
      } else {
        pool::dbExecute(db_pool, "
          UPDATE edc_users SET failed_login_attempts = ? WHERE user_id = ?
        ", params = list(new_failed_attempts, user_id))
      }

      tryCatch(
        log_failed_login(username = username, reason = "invalid_password",
                          attempt_count = new_failed_attempts),
        error = function(e) NULL
      )

      if (now_locked) {
        tryCatch(
          log_account_lockout(
            username = username,
            reason = paste(new_failed_attempts, "failed attempts"),
            duration_minutes = lockout_duration_minutes
          ),
          error = function(e) NULL
        )
        return(list(
          success = FALSE,
          message = paste0(
            "Account locked after ", new_failed_attempts,
            " failed login attempts. Try again in ", lockout_duration_minutes,
            " minute(s), or contact an administrator to unlock it."
          )
        ))
      }

      return(list(success = FALSE, message = "Invalid password"))
    }

  }, error = function(e) {
    return(list(success = FALSE, message = paste("Database error:", e$message)))
  })
}

#' Manually unlock a locked user account (admin "loss management" path)
#'
#' The counterpart to authenticate_user()'s automatic, time-based
#' unlock: resets failed_login_attempts/locked_at immediately rather
#' than waiting for lockout_duration_minutes to elapse, for an admin
#' who has verified the account holder's identity out of band.
#'
#' @param username The locked account's username.
#' @param unlocked_by The admin performing the unlock, for the audit
#'   trail entry.
#' @return List with `success` and, on failure, `message`.
unlock_user_account <- function(username, unlocked_by) {
  if (!exists("db_pool")) {
    return(list(success = FALSE, message = "Database pool not initialized."))
  }

  tryCatch({
    user_record <- pool::dbGetQuery(
      db_pool, "SELECT user_id FROM edc_users WHERE username = ?",
      params = list(username)
    )
    if (nrow(user_record) == 0) {
      return(list(success = FALSE, message = "No such user"))
    }

    pool::dbExecute(db_pool, "
      UPDATE edc_users SET failed_login_attempts = 0, locked_at = NULL
      WHERE user_id = ?
    ", params = list(user_record$user_id[1]))

    tryCatch(
      log_security_event(
        event_type = "UNLOCK", user_id = username,
        description = paste("Account manually unlocked by", unlocked_by)
      ),
      error = function(e) NULL
    )

    list(success = TRUE)
  }, error = function(e) {
    list(success = FALSE, message = paste("Database error:", e$message))
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
    user_input$must_change_password <- isTRUE(auth_result$must_change_password)

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

# The failed-attempts-before-lockout threshold and the lockout
# duration are now both read from cfg$auth$max_failed_attempts /
# cfg$auth$lockout_duration_minutes inside authenticate_user() itself
# (§11.300, 2026-11-09) -- this file used to declare
# num_fails_to_lockout <- 3 here and never read it anywhere; that dead
# constant has been removed now that the feature it named is actually
# implemented.

# user_input reactive values now defined per-session in server.R
# (not global.R -- see global.R's comment on why), before this file
# is sourced
