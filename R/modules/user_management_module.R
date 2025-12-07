#' User Management Module
#'
#' Provides UI for administrators to manage users without database access
#' Includes: add users, edit users, reset passwords, manage roles, deactivate users
#'
#' @export

#' User Management UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the user management UI
user_management_ui <- function(id) {
  ns <- NS(id)

  div(class = "user-management-container",
    # Header with action buttons
    div(class = "d-flex justify-content-between align-items-center mb-4",
      h3("User Management", class = "mb-0"),
      div(
        actionButton(ns("add_user_btn"), "Add User", class = "btn btn-success me-2",
                    icon = icon("plus")),
        actionButton(ns("refresh_btn"), "Refresh", class = "btn btn-secondary",
                    icon = icon("sync"))
      )
    ),

    # Users table
    div(class = "card",
      div(class = "card-body",
        DT::dataTableOutput(ns("users_table")),
        div(id = ns("table_info"), class = "mt-2 text-muted small")
      )
    ),

    # Add/Edit User Modal
    shinymodal::modalDialog(
      id = ns("user_modal"),
      title = "Add/Edit User",
      easyClose = FALSE,
      size = "lg",

      div(class = "form-group",
        label("Username *", `for` = ns("modal_username")),
        textInput(ns("modal_username"), NULL,
                 placeholder = "Username (no spaces)"),
        div(class = "form-text", "Unique login identifier")
      ),

      div(class = "form-group",
        label("Full Name *", `for` = ns("modal_fullname")),
        textInput(ns("modal_fullname"), NULL,
                 placeholder = "User's full name")
      ),

      div(class = "form-group",
        label("Email *", `for` = ns("modal_email")),
        textInput(ns("modal_email"), NULL,
                 placeholder = "user@institution.edu")
      ),

      div(class = "form-group",
        label("Role *", `for` = ns("modal_role")),
        selectInput(ns("modal_role"), NULL,
                   choices = c("Admin", "PI", "Coordinator", "Data Manager", "Monitor"))
      ),

      div(class = "form-group",
        label("Password *", `for` = ns("modal_password")),
        passwordInput(ns("modal_password"), NULL,
                     placeholder = "Password"),
        div(class = "form-text",
          "Leave blank to keep existing password (for edits)")
      ),

      div(class = "form-group",
        label("Confirm Password *", `for` = ns("modal_password_confirm")),
        passwordInput(ns("modal_password_confirm"), NULL,
                     placeholder = "Confirm password")
      ),

      div(class = "form-check mb-3",
        input(id = ns("modal_active"), type = "checkbox", class = "form-check-input", checked = TRUE),
        label("Active", `for` = ns("modal_active"), class = "form-check-label")
      ),

      # Modal footer
      div(class = "modal-footer",
        actionButton(ns("modal_cancel"), "Cancel", class = "btn btn-secondary"),
        actionButton(ns("modal_save"), "Save", class = "btn btn-primary")
      )
    ),

    # Reset Password Modal
    shinymodal::modalDialog(
      id = ns("reset_password_modal"),
      title = "Reset Password",
      easyClose = FALSE,

      p("Generate a temporary password for this user?"),

      div(class = "alert alert-info",
        strong("User will receive:"),
        tags$ul(
          tags$li("A temporary password via email"),
          tags$li("Instructions to change it on first login")
        )
      ),

      div(class = "modal-footer",
        actionButton(ns("reset_cancel"), "Cancel", class = "btn btn-secondary"),
        actionButton(ns("reset_confirm"), "Reset Password", class = "btn btn-warning")
      )
    ),

    # Deactivate User Modal
    shinymodal::modalDialog(
      id = ns("deactivate_modal"),
      title = "Deactivate User",
      easyClose = FALSE,

      div(class = "alert alert-warning",
        strong("Warning: "),
        "This user will no longer be able to login. This action can be reversed by editing the user later."
      ),

      p("Reason for deactivation:"),
      textAreaInput(ns("deactivate_reason"), NULL,
                   placeholder = "Optional: reason for deactivation",
                   rows = 3),

      div(class = "modal-footer",
        actionButton(ns("deactivate_cancel"), "Cancel", class = "btn btn-secondary"),
        actionButton(ns("deactivate_confirm"), "Deactivate", class = "btn btn-danger")
      )
    )
  )
}


#' User Management Server
#'
#' @param id The namespace id for the module
#' @param db_pool Reactive expression returning database connection pool
#'
#' @return List of reactive expressions and functions
user_management_server <- function(id, db_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reactive values for state management
    user_state <- reactiveValues(
      users = data.frame(),
      edit_user_id = NULL,
      modal_mode = "add",  # "add" or "edit"
      selected_username = NULL
    )

    # Load users from database
    load_users <- function() {
      tryCatch({
        if (is.null(db_pool)) {
          # Return empty data for testing
          return(data.frame(
            user_id = character(),
            username = character(),
            full_name = character(),
            email = character(),
            role = character(),
            active = logical(),
            last_login = character(),
            stringsAsFactors = FALSE
          ))
        }

        # Query users from database
        query <- "
          SELECT user_id, username, full_name, email, role, active, last_login
          FROM edc_users
          ORDER BY username
        "
        users <- pool::dbGetQuery(db_pool, query)

        # Format last_login
        if (nrow(users) > 0) {
          users$last_login <- format(
            as.POSIXct(users$last_login, origin = "1970-01-01"),
            "%Y-%m-%d %H:%M"
          )
        }

        user_state$users <- users
        return(users)

      }, error = function(e) {
        shinyalert("Database Error", paste("Error loading users:", e$message), type = "error")
        return(data.frame())
      })
    }

    # Initial load
    user_state$users <- load_users()

    # Display users table
    output$users_table <- DT::renderDataTable({
      users <- user_state$users

      if (nrow(users) == 0) {
        return(DT::datatable(
          data.frame(Message = "No users found"),
          options = list(dom = 't', searching = FALSE, paging = FALSE)
        ))
      }

      # Create action buttons
      action_buttons <- sapply(1:nrow(users), function(i) {
        user_id <- users$user_id[i]
        paste0(
          '<div class="btn-group btn-group-sm" role="group">
            <button class="btn btn-info btn-sm" onclick="Shiny.setInputValue(\'', ns("edit_user"), '\', \'', user_id, '\', {priority: \'event\'})">Edit</button>
            <button class="btn btn-warning btn-sm" onclick="Shiny.setInputValue(\'', ns("reset_password"), '\', \'', user_id, '\', {priority: \'event\'})">Reset Pwd</button>
            <button class="btn btn-danger btn-sm" onclick="Shiny.setInputValue(\'', ns("deactivate_user"), '\', \'', user_id, '\', {priority: \'event\'})">Deactivate</button>
          </div>'
        )
      })

      display_data <- users[, c("username", "full_name", "email", "role", "active", "last_login")]
      display_data$Actions <- action_buttons

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          pageLength = 10,
          columnDefs = list(
            list(targets = 5, searchable = FALSE, orderable = FALSE, width = "200px")
          )
        )
      )
    })

    # Update table info
    observe({
      count <- nrow(user_state$users)
      active <- sum(user_state$users$active, na.rm = TRUE)
      inactive <- count - active
      info_text <- sprintf(
        "Total users: %d | Active: %d | Inactive: %d",
        count, active, inactive
      )
      shinyjs::html(ns("table_info"), info_text)
    })

    # Add user button
    observeEvent(input$add_user_btn, {
      user_state$modal_mode <- "add"
      user_state$edit_user_id <- NULL

      # Clear form
      updateTextInput(session, "modal_username", value = "")
      updateTextInput(session, "modal_fullname", value = "")
      updateTextInput(session, "modal_email", value = "")
      updateSelectInput(session, "modal_role", selected = "Coordinator")
      updatePasswordInput(session, "modal_password", value = "")
      updatePasswordInput(session, "modal_password_confirm", value = "")
      updateCheckboxInput(session, "modal_active", value = TRUE)

      shinyjs::show("user_modal")
    })

    # Edit user button
    observeEvent(input$edit_user, {
      user_id <- input$edit_user
      user_row <- user_state$users[user_state$users$user_id == user_id, ]

      if (nrow(user_row) == 0) {
        shinyalert("Error", "User not found", type = "error")
        return()
      }

      user_state$modal_mode <- "edit"
      user_state$edit_user_id <- user_id

      # Populate form
      updateTextInput(session, "modal_username", value = user_row$username[1])
      updateTextInput(session, "modal_fullname", value = user_row$full_name[1])
      updateTextInput(session, "modal_email", value = user_row$email[1])
      updateSelectInput(session, "modal_role", selected = user_row$role[1])
      updatePasswordInput(session, "modal_password", value = "")
      updatePasswordInput(session, "modal_password_confirm", value = "")
      updateCheckboxInput(session, "modal_active", value = as.logical(user_row$active[1]))

      shinyjs::show("user_modal")
    })

    # Save user
    observeEvent(input$modal_save, {
      # Validate inputs
      errors <- character()

      if (input$modal_username == "") {
        errors <- c(errors, "Username is required")
      }
      if (grepl(" ", input$modal_username)) {
        errors <- c(errors, "Username cannot contain spaces")
      }
      if (input$modal_fullname == "") {
        errors <- c(errors, "Full Name is required")
      }
      if (input$modal_email == "") {
        errors <- c(errors, "Email is required")
      }
      if (!grepl("^[^@]+@[^@]+\\.[^@]+$", input$modal_email)) {
        errors <- c(errors, "Email format is invalid")
      }

      # Check password for new users
      if (user_state$modal_mode == "add") {
        if (input$modal_password == "") {
          errors <- c(errors, "Password is required for new users")
        }
        if (nchar(input$modal_password) < 8) {
          errors <- c(errors, "Password must be at least 8 characters")
        }
      }

      if (input$modal_password != "" && input$modal_password != input$modal_password_confirm) {
        errors <- c(errors, "Passwords do not match")
      }

      if (length(errors) > 0) {
        shinyalert("Validation Error",
                  paste("Please fix these errors:\n", paste("- ", errors, collapse = "\n")),
                  type = "error")
        return()
      }

      # Save to database
      save_user_to_db(
        db_pool = db_pool,
        user_id = user_state$edit_user_id,
        username = input$modal_username,
        full_name = input$modal_fullname,
        email = input$modal_email,
        role = input$modal_role,
        password = input$modal_password,
        active = input$modal_active,
        mode = user_state$modal_mode
      )

      # Reload users and close modal
      user_state$users <- load_users()
      shinyjs::hide("user_modal")

      message_type <- if (user_state$modal_mode == "add") "User added" else "User updated"
      shinyalert("Success", message_type, type = "success", timer = 2000)
    })

    # Cancel modal
    observeEvent(input$modal_cancel, {
      shinyjs::hide("user_modal")
    })

    # Reset password button
    observeEvent(input$reset_password, {
      user_id <- input$reset_password
      user_row <- user_state$users[user_state$users$user_id == user_id, ]
      user_state$selected_username <- user_row$username[1]

      shinyjs::show("reset_password_modal")
    })

    # Confirm reset password
    observeEvent(input$reset_confirm, {
      # Generate temporary password
      temp_password <- paste0(sample(c(letters, LETTERS, 0:9), 12, replace = TRUE), collapse = "")

      # Update in database
      salt <- Sys.getenv("ZZEDC_SALT")
      if (salt == "") salt <- "default_salt"
      password_hash <- digest::digest(paste0(temp_password, salt), algo = "sha256")

      tryCatch({
        if (!is.null(db_pool)) {
          pool::dbExecute(db_pool,
            "UPDATE edc_users SET password_hash = ? WHERE user_id = ?",
            params = list(password_hash, user_state$edit_user_id)
          )
        }

        shinyalert("Success",
                  paste("Temporary password generated:\n\n", temp_password, "\n\nShare this with the user."),
                  type = "success")
      }, error = function(e) {
        shinyalert("Error", paste("Failed to reset password:", e$message), type = "error")
      })

      shinyjs::hide("reset_password_modal")
    })

    # Cancel reset
    observeEvent(input$reset_cancel, {
      shinyjs::hide("reset_password_modal")
    })

    # Deactivate button
    observeEvent(input$deactivate_user, {
      user_id <- input$deactivate_user
      user_state$edit_user_id <- user_id

      shinyjs::show("deactivate_modal")
    })

    # Confirm deactivate
    observeEvent(input$deactivate_confirm, {
      tryCatch({
        if (!is.null(db_pool)) {
          pool::dbExecute(db_pool,
            "UPDATE edc_users SET active = 0 WHERE user_id = ?",
            params = list(user_state$edit_user_id)
          )
        }

        # Reload users
        user_state$users <- load_users()
        shinyjs::hide("deactivate_modal")

        shinyalert("Success", "User deactivated", type = "success", timer = 2000)
      }, error = function(e) {
        shinyalert("Error", paste("Failed to deactivate user:", e$message), type = "error")
      })
    })

    # Cancel deactivate
    observeEvent(input$deactivate_cancel, {
      shinyjs::hide("deactivate_modal")
    })

    # Refresh button
    observeEvent(input$refresh_btn, {
      user_state$users <- load_users()
      shinyalert("Refreshed", "User list updated", type = "success", timer = 1500)
    })

    # Return reactive values
    list(
      users = reactive(user_state$users)
    )
  })
}


#' Save User to Database
#'
#' Internal helper function for saving user data
#'
#' @param db_pool Database connection pool
#' @param user_id User ID for editing (NULL for new users)
#' @param username User's login name
#' @param full_name User's full name
#' @param email User's email
#' @param role User's role
#' @param password Password (optional for edits)
#' @param active Whether user is active
#' @param mode Either "add" or "edit"
save_user_to_db <- function(db_pool, user_id, username, full_name, email, role, password, active, mode) {

  if (is.null(db_pool)) {
    return(invisible(NULL))
  }

  tryCatch({
    if (mode == "add") {
      # Generate user ID and hash password
      salt <- Sys.getenv("ZZEDC_SALT")
      if (salt == "") salt <- "default_salt"
      password_hash <- digest::digest(paste0(password, salt), algo = "sha256")

      new_user_id <- paste0("USER_", as.integer(Sys.time()))

      pool::dbExecute(db_pool, "
        INSERT INTO edc_users
        (user_id, username, password_hash, full_name, email, role, active, created_date, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
      ", params = list(new_user_id, username, password_hash, full_name, email, role, active, "admin_ui"))

    } else if (mode == "edit") {
      # Update existing user
      if (password != "") {
        # Update password
        salt <- Sys.getenv("ZZEDC_SALT")
        if (salt == "") salt <- "default_salt"
        password_hash <- digest::digest(paste0(password, salt), algo = "sha256")

        pool::dbExecute(db_pool, "
          UPDATE edc_users
          SET full_name = ?, email = ?, role = ?, active = ?, password_hash = ?, modified_date = datetime('now')
          WHERE user_id = ?
        ", params = list(full_name, email, role, active, password_hash, user_id))
      } else {
        # No password change
        pool::dbExecute(db_pool, "
          UPDATE edc_users
          SET full_name = ?, email = ?, role = ?, active = ?, modified_date = datetime('now')
          WHERE user_id = ?
        ", params = list(full_name, email, role, active, user_id))
      }
    }

  }, error = function(e) {
    stop(paste("Database error:", e$message))
  })
}
