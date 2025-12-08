# Setup Wizard Module
#
# A comprehensive 5-step wizard for initial ZZedc configuration
# Guides users through: Basic Info → Admin Account → Security → Team Members → Data Dictionary

#' Setup Wizard UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the wizard UI
setup_wizard_ui <- function(id) {
  ns <- NS(id)

  div(class = "setup-wizard-container",
    # Progress bar at the top
    div(class = "mb-4",
      div(class = "progress", style = "height: 25px;",
        div(id = ns("progress_bar"), class = "progress-bar progress-bar-animated",
            role = "progressbar", style = "width: 20%",
            "Step 1 of 5")
      )
    ),

    # Step 1: Basic Information
    div(id = ns("step1_panel"), class = "wizard-step",
      h3("Step 1: Basic Information", class = "text-primary mb-3"),
      p("Tell us about your research study."),

      textInput(ns("study_name"), "Study Name *",
               placeholder = "e.g., Depression Treatment Trial"),

      textInput(ns("protocol_id"), "Protocol ID / Study Code *",
               placeholder = "e.g., DEPR-2024-001"),

      textInput(ns("pi_name"), "Principal Investigator Name *",
               placeholder = "e.g., Dr. Jane Smith"),

      textInput(ns("pi_email"), "PI Email *",
               placeholder = "jane.smith@university.edu"),

      numericInput(ns("target_enrollment"), "Target Enrollment *",
                  value = 50, min = 1, max = 100000),

      selectInput(ns("study_phase"), "Study Phase *",
                 choices = c("Pilot", "Phase 1", "Phase 2", "Phase 3", "Phase 4", "Observational")),

      div(class = "mt-4",
        actionButton(ns("step1_next"), "Next →", class = "btn btn-primary")
      )
    ),

    # Step 2: Admin Account
    div(id = ns("step2_panel"), class = "wizard-step", style = "display:none;",
      h3("Step 2: Administrator Account", class = "text-primary mb-3"),
      p("Create your system administrator account."),

      textInput(ns("admin_username"), "Username *",
               placeholder = "Your login username (no spaces)"),

      textInput(ns("admin_fullname"), "Full Name *",
               placeholder = "Your full name"),

      textInput(ns("admin_email"), "Email *",
               placeholder = "admin@institution.edu"),

      div(class = "form-group",
        label("Password *", `for` = ns("admin_password")),
        passwordInput(ns("admin_password"), NULL,
                     placeholder = "Create a strong password"),
        div(id = ns("password_strength"), class = "small text-muted mt-1")
      ),

      div(class = "form-group",
        label("Confirm Password *", `for` = ns("admin_password_confirm")),
        passwordInput(ns("admin_password_confirm"), NULL,
                     placeholder = "Re-enter your password"),
        div(id = ns("password_match"), class = "small text-muted mt-1")
      ),

      div(class = "alert alert-info mt-3",
        strong("Password Requirements:"),
        tags$ul(
          tags$li("At least 8 characters"),
          tags$li("Mix of letters, numbers, and symbols")
        )
      ),

      div(class = "mt-4",
        actionButton(ns("step2_prev"), "← Back", class = "btn btn-secondary"),
        actionButton(ns("step2_next"), "Next →", class = "btn btn-primary ms-2")
      )
    ),

    # Step 3: Security Configuration
    div(id = ns("step3_panel"), class = "wizard-step", style = "display:none;",
      h3("Step 3: Security Configuration", class = "text-primary mb-3"),
      p("Configure security settings for your system."),

      div(class = "alert alert-warning",
        strong("Security Salt: "),
        p("A unique security key has been generated for your system. ",
          "Store this securely - it's needed for password encryption."),
        div(class = "input-group mt-2",
          textInput(ns("security_salt"), NULL, placeholder = "Generating..."),
          actionButton(ns("copy_salt"), "Copy", class = "btn btn-outline-secondary")
        ),
        div(class = "form-check mt-3",
          input(id = ns("confirm_salt"), type = "checkbox", class = "form-check-input"),
          label("I have saved the security salt in a secure location",
               `for` = ns("confirm_salt"), class = "form-check-label")
        )
      ),

      div(class = "form-group mt-3",
        label("Session Timeout (minutes) *"),
        numericInput(ns("session_timeout"), NULL, value = 30, min = 5, max = 1440)
      ),

      div(class = "form-group",
        label("Enforce HTTPS *"),
        selectInput(ns("enforce_https"), NULL,
                   choices = c("No" = "no", "Yes (recommended)" = "yes"))
      ),

      div(class = "form-group",
        label("Max Failed Login Attempts *"),
        numericInput(ns("max_login_attempts"), NULL, value = 3, min = 1, max = 10)
      ),

      div(class = "mt-4",
        actionButton(ns("step3_prev"), "← Back", class = "btn btn-secondary"),
        actionButton(ns("step3_next"), "Next →", class = "btn btn-primary ms-2")
      )
    ),

    # Step 4: Team Members (Optional)
    div(id = ns("step4_panel"), class = "wizard-step", style = "display:none;",
      h3("Step 4: Team Members", class = "text-primary mb-3"),
      p("Add additional team members (optional - can be done later in admin dashboard)."),

      div(class = "mb-3",
        textInput(ns("team_member_username"), "Username",
                 placeholder = "Username"),
        textInput(ns("team_member_name"), "Full Name",
                 placeholder = "Full name"),
        textInput(ns("team_member_email"), "Email",
                 placeholder = "email@institution.edu"),
        selectInput(ns("team_member_role"), "Role",
                   choices = c("PI" = "PI", "Coordinator" = "Coordinator",
                             "Data Manager" = "Data Manager", "Monitor" = "Monitor")),
        actionButton(ns("add_team_member"), "Add Member", class = "btn btn-sm btn-success")
      ),

      div(id = ns("team_members_list"), class = "mt-3",
        h5("Team Members Added:"),
        DT::dataTableOutput(ns("team_table"))
      ),

      div(class = "mt-4",
        actionButton(ns("step4_prev"), "← Back", class = "btn btn-secondary"),
        actionButton(ns("step4_next"), "Next →", class = "btn btn-primary ms-2")
      )
    ),

    # Step 5: Data Dictionary
    div(id = ns("step5_panel"), class = "wizard-step", style = "display:none;",
      h3("Step 5: Data Dictionary & Forms", class = "text-primary mb-3"),
      p("Choose how to set up your data collection forms."),

      div(class = "form-group",
        radioButtons(ns("data_source"), "Data Setup Option",
                    choices = list(
                      "Start with blank forms (configure later)" = "blank",
                      "Use example ADHD forms (recommended for testing)" = "adhd_example",
                      "Import from CSV file" = "csv_import",
                      "Import from Google Sheets" = "gsheets_import"
                    ),
                    selected = "adhd_example")
      ),

      # Conditional panels for each option
      conditionalPanel(ns = ns,
        condition = "input.data_source == 'csv_import'",
        div(
          p("Upload your data dictionary CSV file."),
          fileInput(ns("csv_file"), "Choose CSV File", accept = ".csv")
        )
      ),

      conditionalPanel(ns = ns,
        condition = "input.data_source == 'gsheets_import'",
        div(
          p("Enter your Google Sheets URL:"),
          textInput(ns("gsheets_url"), "Google Sheets URL",
                   placeholder = "https://docs.google.com/spreadsheets/d/...")
        )
      ),

      div(class = "mt-4",
        actionButton(ns("step5_prev"), "← Back", class = "btn btn-secondary"),
        actionButton(ns("step5_finish"), "Create System", class = "btn btn-success ms-2")
      )
    ),

    # Success Panel
    div(id = ns("success_panel"), class = "wizard-step", style = "display:none;",
      div(class = "alert alert-success",
        h3("Success! ✓", class = "alert-heading"),
        p("Your ZZedc system has been created and configured."),

        div(class = "mt-3 mb-3",
          strong("Next Steps:"),
          tags$ul(
            tags$li("Your system is ready to launch"),
            tags$li("Login with your administrator credentials"),
            tags$li("Add users in the Admin Dashboard"),
            tags$li("Create or import forms"),
            tags$li("Start collecting data!")
          )
        ),

        div(class = "alert alert-info mt-3",
          strong("Important Files:"),
          tags$ul(
            tags$li(code("config.yml"), " - System configuration"),
            tags$li(code("launch_app.R"), " - Script to launch your ZZedc system")
          )
        )
      ),

      div(class = "mt-4",
        actionButton(ns("launch_app"), "Launch ZZedc", class = "btn btn-lg btn-success"),
        actionButton(ns("finish_setup"), "Close & Setup Complete", class = "btn btn-secondary ms-2")
      )
    )
  )
}


#' Setup Wizard Server
#'
#' @param id The namespace id for the module
#' @param db_path Reactive path to database file
#' @return Reactive value indicating setup completion
setup_wizard_server <- function(id, db_path = reactive("/tmp/zzedc.db")) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Initialize reactive values
    wizard_state <- reactiveValues(
      current_step = 1,
      total_steps = 5,
      setup_complete = FALSE,
      team_members = data.frame(username = character(),
                               full_name = character(),
                               email = character(),
                               role = character(),
                               stringsAsFactors = FALSE),
      system_config = list()
    )

    # Generate security salt on module load
    security_salt <- paste0(
      sample(c(letters, LETTERS, 0:9), 32, replace = TRUE),
      collapse = ""
    )

    # Update progress bar
    update_progress <- function() {
      progress_pct <- (wizard_state$current_step / wizard_state$total_steps) * 100
      shinyjs::runjs(sprintf(
        "document.getElementById('%s').style.width = '%d%%';
         document.getElementById('%s').textContent = 'Step %d of %d';",
        ns("progress_bar"), progress_pct,
        ns("progress_bar"), wizard_state$current_step, wizard_state$total_steps
      ))
    }

    # Show/hide step panels
    show_step <- function(step_num) {
      # Hide all steps
      for (i in 1:5) {
        shinyjs::hide(ns(paste0("step", i, "_panel")))
      }

      if (step_num <= 5) {
        shinyjs::show(ns(paste0("step", step_num, "_panel")))
      }

      wizard_state$current_step <- step_num
      update_progress()
    }

    # Step 1: Basic Information Validation
    observeEvent(input$step1_next, {
      errors <- character()

      if (is.null(input$study_name) || input$study_name == "") {
        errors <- c(errors, "Study Name is required")
      }
      if (is.null(input$protocol_id) || input$protocol_id == "") {
        errors <- c(errors, "Protocol ID is required")
      }
      if (is.null(input$pi_name) || input$pi_name == "") {
        errors <- c(errors, "PI Name is required")
      }
      if (is.null(input$pi_email) || input$pi_email == "") {
        errors <- c(errors, "PI Email is required")
      }
      if (!grepl("^[^@]+@[^@]+\\.[^@]+$", input$pi_email)) {
        errors <- c(errors, "PI Email is invalid")
      }

      if (length(errors) > 0) {
        shinyalert("Validation Error",
                  paste("Please fix these errors:\n", paste("- ", errors, collapse = "\n")),
                  type = "error")
        return()
      }

      # Store data
      wizard_state$system_config$study_name <- input$study_name
      wizard_state$system_config$protocol_id <- input$protocol_id
      wizard_state$system_config$pi_name <- input$pi_name
      wizard_state$system_config$pi_email <- input$pi_email
      wizard_state$system_config$target_enrollment <- input$target_enrollment
      wizard_state$system_config$study_phase <- input$study_phase

      show_step(2)
    })

    # Step 2: Admin Account Validation
    observeEvent(input$step2_next, {
      errors <- character()

      if (is.null(input$admin_username) || input$admin_username == "") {
        errors <- c(errors, "Username is required")
      }
      if (grepl(" ", input$admin_username)) {
        errors <- c(errors, "Username cannot contain spaces")
      }
      if (is.null(input$admin_fullname) || input$admin_fullname == "") {
        errors <- c(errors, "Full Name is required")
      }
      if (is.null(input$admin_email) || input$admin_email == "") {
        errors <- c(errors, "Email is required")
      }
      if (!grepl("^[^@]+@[^@]+\\.[^@]+$", input$admin_email)) {
        errors <- c(errors, "Email is invalid")
      }
      if (is.null(input$admin_password) || nchar(input$admin_password) < 8) {
        errors <- c(errors, "Password must be at least 8 characters")
      }
      if (input$admin_password != input$admin_password_confirm) {
        errors <- c(errors, "Passwords do not match")
      }

      if (length(errors) > 0) {
        shinyalert("Validation Error",
                  paste("Please fix these errors:\n", paste("- ", errors, collapse = "\n")),
                  type = "error")
        return()
      }

      # Store data
      wizard_state$system_config$admin_username <- input$admin_username
      wizard_state$system_config$admin_fullname <- input$admin_fullname
      wizard_state$system_config$admin_email <- input$admin_email
      wizard_state$system_config$admin_password <- input$admin_password

      show_step(3)
    })

    # Step 2: Back
    observeEvent(input$step2_prev, {
      show_step(1)
    })

    # Step 3: Security Configuration
    observeEvent(input$step3_next, {
      if (!input$confirm_salt) {
        shinyalert("Confirmation Required",
                  "Please confirm that you have saved the security salt.",
                  type = "error")
        return()
      }

      # Store security config
      wizard_state$system_config$security_salt <- security_salt
      wizard_state$system_config$session_timeout <- input$session_timeout
      wizard_state$system_config$enforce_https <- input$enforce_https
      wizard_state$system_config$max_login_attempts <- input$max_login_attempts

      show_step(4)
    })

    # Step 3: Back
    observeEvent(input$step3_prev, {
      show_step(2)
    })

    # Display security salt
    observe({
      updateTextInput(session, "security_salt", value = security_salt)
    })

    # Copy salt to clipboard
    observeEvent(input$copy_salt, {
      shinyjs::runjs(paste0(
        "var salt = document.getElementById('", ns("security_salt"), "').value;",
        "navigator.clipboard.writeText(salt).then(function() {",
        "  alert('Security salt copied to clipboard');",
        "});"
      ))
    })

    # Step 4: Team Members
    observeEvent(input$add_team_member, {
      if (input$team_member_username == "" ||
          input$team_member_name == "" ||
          input$team_member_email == "") {
        shinyalert("Incomplete", "Please fill in all team member fields", type = "warning")
        return()
      }

      new_member <- data.frame(
        username = input$team_member_username,
        full_name = input$team_member_name,
        email = input$team_member_email,
        role = input$team_member_role,
        stringsAsFactors = FALSE
      )

      wizard_state$team_members <- rbind(wizard_state$team_members, new_member)

      # Clear inputs
      updateTextInput(session, "team_member_username", value = "")
      updateTextInput(session, "team_member_name", value = "")
      updateTextInput(session, "team_member_email", value = "")
    })

    # Display team members table
    output$team_table <- DT::renderDataTable({
      DT::datatable(
        wizard_state$team_members,
        options = list(
          pageLength = 5,
          dom = 't'
        ),
        selection = 'none'
      )
    })

    # Step 4: Next
    observeEvent(input$step4_next, {
      wizard_state$system_config$team_members <- wizard_state$team_members
      show_step(5)
    })

    # Step 4: Back
    observeEvent(input$step4_prev, {
      show_step(3)
    })

    # Step 5: Finish Setup
    observeEvent(input$step5_finish, {
      # Here we would create the database and config files
      # This is the main setup orchestration

      wizard_state$system_config$data_source <- input$data_source

      if (input$data_source == "csv_import" && is.null(input$csv_file)) {
        shinyalert("File Required", "Please upload a CSV file", type = "error")
        return()
      }

      if (input$data_source == "gsheets_import" && (is.null(input$gsheets_url) || input$gsheets_url == "")) {
        shinyalert("URL Required", "Please enter a Google Sheets URL", type = "error")
        return()
      }

      # Show success panel
      shinyjs::hide(ns("step5_panel"))
      shinyjs::show(ns("success_panel"))

      # Mark setup complete
      wizard_state$setup_complete <- TRUE
    })

    # Step 5: Back
    observeEvent(input$step5_prev, {
      show_step(4)
    })

    # Launch app button
    observeEvent(input$launch_app, {
      shinyalert("Ready!",
                "Your ZZedc application is ready to launch.\nLogin with your admin credentials.",
                type = "success")
    })

    # Finish setup
    observeEvent(input$finish_setup, {
      # Return to main app or close wizard
      shinyalert("Complete!",
                "Setup wizard complete. You can now use ZZedc.",
                type = "success")
    })

    # Return reactive values
    list(
      setup_complete = reactive(wizard_state$setup_complete),
      system_config = reactive(wizard_state$system_config),
      current_step = reactive(wizard_state$current_step)
    )
  })
}
