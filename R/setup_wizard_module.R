# Setup Wizard Module
#
# A 6-step wizard that creates a new ZZedc study:
# Basic Info > Admin Account > Security > Database > Team Members > Forms
#
# Run it with launch_setup_wizard(), or launch_zzedc(setup = TRUE).

#' Setup Wizard UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the wizard UI
#'
#' @examples
#' \dontrun{
#' # The wizard is normally run with launch_setup_wizard() or
#' # launch_zzedc(setup = TRUE); the example shows how to embed it.
#' if (interactive()) {
#'   ui <- bslib::page_fluid(shinyjs::useShinyjs(), setup_wizard_ui("wizard"))
#'   server <- function(input, output, session) {
#'     setup_wizard_server("wizard", base_path = tempfile("zzedc_"))
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
setup_wizard_ui <- function(id) {
  ns <- NS(id)

  info_tip <- function(text) {
    bslib::tooltip(
      bsicons::bs_icon("info-circle", class = "text-muted ms-1"),
      text
    )
  }

  backend_choice_names <- lapply(names(.backend_catalog), function(b) {
    entry <- .backend_catalog[[b]]
    tags$span(tags$strong(entry$label), " ", info_tip(entry$summary))
  })

  div(class = "setup-wizard-container",
    # Progress bar at the top
    div(class = "mb-4",
      div(class = "progress", style = "height: 25px;",
        div(id = ns("progress_bar"), class = "progress-bar",
            role = "progressbar", style = "width: 17%",
            "Step 1 of 6")
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
        actionButton(ns("step1_next"), "Next >", class = "btn btn-primary")
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
        tags$label("Password *", `for` = ns("admin_password")),
        passwordInput(ns("admin_password"), NULL,
                     placeholder = "Create a strong password"),
        div(id = ns("password_strength"), class = "small text-muted mt-1")
      ),

      div(class = "form-group",
        tags$label("Confirm Password *", `for` = ns("admin_password_confirm")),
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
        actionButton(ns("step2_prev"), "< Back", class = "btn btn-secondary"),
        actionButton(ns("step2_next"), "Next >", class = "btn btn-primary ms-2")
      )
    ),

    # Step 3: Security Configuration
    div(id = ns("step3_panel"), class = "wizard-step", style = "display:none;",
      h3("Step 3: Security Configuration", class = "text-primary mb-3"),
      p("Configure security settings for your system."),

      div(class = "form-group mb-3",
        tags$label(
          "Security profile *",
          info_tip(paste(
            "Decides what happens if the database cannot be shown to be",
            "encrypted. 'Regulated' refuses to start; choose it for",
            "identifiable or regulated data (21 CFR Part 11, HIPAA, an IRB",
            "that requires encryption)."
          ))
        ),
        selectInput(ns("security_profile"), NULL,
          choices = c(
            "Regulated: refuse unencrypted storage (recommended)" = "regulated",
            "Standard: allow unencrypted storage, with a warning" = "standard",
            "Development: synthetic or test data only" = "development"
          ),
          selected = "regulated")
      ),

      div(class = "alert alert-warning",
        strong("Security Salt: "),
        p("A unique security key has been generated for your system. ",
          "Store this securely - it's needed for password encryption."),
        div(class = "input-group mt-2",
          textInput(ns("security_salt"), NULL, placeholder = "Generating..."),
          actionButton(ns("copy_salt"), "Copy", class = "btn btn-outline-secondary")
        ),
        div(class = "form-check mt-3",
          tags$input(id = ns("confirm_salt"), type = "checkbox", class = "form-check-input"),
          tags$label("I have saved the security salt in a secure location",
               `for` = ns("confirm_salt"), class = "form-check-label")
        )
      ),

      div(class = "form-group mt-3",
        tags$label("Session Timeout (minutes) *"),
        numericInput(ns("session_timeout"), NULL, value = 30, min = 5, max = 1440)
      ),

      div(class = "form-group",
        tags$label(
          "Enforce HTTPS *",
          info_tip(paste(
            "Yes refuses any connection that is not HTTPS (the 'regulated'",
            "profile always does; connections to localhost are allowed).",
            "zzedc does not provide HTTPS itself: run it behind a web server",
            "or proxy that does."
          ))
        ),
        selectInput(ns("enforce_https"), NULL,
                   choices = c("No" = "no", "Yes (recommended)" = "yes"))
      ),

      div(class = "form-group",
        tags$label("Max Failed Login Attempts *"),
        numericInput(ns("max_login_attempts"), NULL, value = 3, min = 1, max = 10)
      ),

      div(class = "mt-4",
        actionButton(ns("step3_prev"), "< Back", class = "btn btn-secondary"),
        actionButton(ns("step3_next"), "Next >", class = "btn btn-primary ms-2")
      )
    ),

    # Step 4: Database
    div(id = ns("stepdb_panel"), class = "wizard-step", style = "display:none;",
      h3("Step 4: Database", class = "text-primary mb-3"),
      p(
        "Choose where study data will be stored. Hover over ",
        bsicons::bs_icon("info-circle", class = "text-muted"),
        " for a summary, or ",
        actionLink(ns("compare_backends"), "compare all options"),
        "."
      ),

      radioButtons(ns("db_backend"), "Database *",
        choiceNames = backend_choice_names,
        choiceValues = names(.backend_catalog),
        selected = "duckdb"),

      uiOutput(ns("db_fit")),

      conditionalPanel(ns = ns, condition = "input.db_backend == 'duckdb'",
        div(class = "alert alert-warning",
          strong("Database encryption key"),
          p("This key encrypts the study database. It is not stored in the ",
            "project: save it now in a password manager or secrets manager, ",
            "and set it as the environment variable ", code("DB_ENCRYPTION_KEY"),
            " before each launch. If it is lost, the data cannot be recovered."),
          div(class = "input-group mt-2",
            textInput(ns("db_key_display"), NULL, placeholder = "Generating..."),
            actionButton(ns("copy_db_key"), "Copy", class = "btn btn-outline-secondary")
          ),
          div(class = "form-check mt-3",
            tags$input(id = ns("confirm_db_key"), type = "checkbox", class = "form-check-input"),
            tags$label("I have saved the encryption key in a secure location",
                       `for` = ns("confirm_db_key"), class = "form-check-label")
          )
        ),
        checkboxInput(ns("install_extensions"),
          tagList(
            "Download DuckDB's extensions now",
            info_tip(paste(
              "DuckDB needs two extensions (httpfs, icu). Downloading them",
              "now, into the study's duckdb_extensions folder, lets the",
              "application run without internet access; the 'regulated'",
              "profile does not allow downloads while it runs."
            ))
          ),
          value = TRUE)
      ),

      conditionalPanel(ns = ns,
        condition = "input.db_backend == 'postgresql' || input.db_backend == 'mysql'",
        div(class = "card card-body mb-3",
          textInput(ns("db_host"), "Server host *", placeholder = "db.example.edu"),
          numericInput(ns("db_port"), "Port", value = 5432, min = 1, max = 65535),
          textInput(ns("db_name"), "Database name *", value = "zzedc"),
          textInput(ns("db_user"), "Database user *"),
          conditionalPanel(ns = ns, condition = "input.db_backend == 'postgresql'",
            selectInput(ns("pg_sslmode"),
              tagList("TLS mode", info_tip("verify-full encrypts the connection and checks the server's certificate.")),
              choices = c("verify-full", "verify-ca", "require", "prefer"))
          ),
          conditionalPanel(ns = ns, condition = "input.db_backend == 'mysql'",
            selectInput(ns("my_ssl_mode"),
              tagList("TLS mode", info_tip("VERIFY_IDENTITY encrypts the connection and checks the server's certificate.")),
              choices = c("VERIFY_IDENTITY", "VERIFY_CA", "REQUIRED", "PREFERRED"))
          ),
          uiOutput(ns("db_password_status"))
        )
      ),

      div(class = "mt-4",
        actionButton(ns("stepdb_prev"), "< Back", class = "btn btn-secondary"),
        actionButton(ns("stepdb_next"), "Next >", class = "btn btn-primary ms-2")
      )
    ),

    # Step 5: Team Members (Optional)
    div(id = ns("step4_panel"), class = "wizard-step", style = "display:none;",
      h3("Step 5: Team Members", class = "text-primary mb-3"),
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
        DT::DTOutput(ns("team_table"))
      ),

      div(class = "mt-4",
        actionButton(ns("step4_prev"), "< Back", class = "btn btn-secondary"),
        actionButton(ns("step4_next"), "Next >", class = "btn btn-primary ms-2")
      )
    ),

    # Step 6: Forms
    div(id = ns("step5_panel"), class = "wizard-step", style = "display:none;",
      h3("Step 6: Data Collection Forms", class = "text-primary mb-3"),
      p("The study is created with no data collection forms. After setup, ",
        "add them in one of these ways:"),
      tags$ul(
        tags$li("Import a data dictionary from a CSV file (",
                code("setup_zzedc_from_csv()"), ")"),
        tags$li("Import from Google Sheets (", code("setup_zzedc_from_gsheets()"),
                "; SQLite studies only for now)"),
        tags$li("Build forms in the application's CRF designer")
      ),
      p("See ", code("vignette('content-author-guide')"), " for each."),

      div(class = "mt-4",
        actionButton(ns("step5_prev"), "< Back", class = "btn btn-secondary"),
        actionButton(ns("step5_finish"), "Create Study", class = "btn btn-success ms-2")
      )
    ),

    # Success Panel
    div(id = ns("success_panel"), class = "wizard-step", style = "display:none;",
      div(class = "alert alert-success",
        h3("Study created", class = "alert-heading"),
        uiOutput(ns("setup_summary"))
      ),

      div(class = "mt-4",
        actionButton(ns("launch_app"), "Launch ZZedc", class = "btn btn-lg btn-success"),
        actionButton(ns("finish_setup"), "Close", class = "btn btn-secondary ms-2")
      )
    )
  )
}


#' Whether a Backend Can Satisfy a Security Profile (internal)
#'
#' @param backend Backend name.
#' @param profile Security profile.
#' @return List with `ok` (logical) and `message`.
#' @keywords internal
.backend_fits_profile <- function(backend, profile) {
  if (profile != "regulated") {
    return(list(ok = TRUE, message = if (backend %in% c("sqlite", "postgresql", "mysql")) {
      paste0("Allowed under '", profile, "'. Encryption at rest: ",
             .backend_catalog[[backend]]$encryption)
    } else {
      "Encrypted at rest with your key."
    }))
  }
  if (backend == "sqlite" && !sqlite_cipher_available()) {
    return(list(ok = FALSE, message = paste(
      "The 'regulated' profile refuses SQLite here: this computer's RSQLite",
      "cannot encrypt it. Choose DuckDB, or go back and choose the",
      "'standard' profile if this study does not need encrypted storage."
    )))
  }
  if (backend %in% c("postgresql", "mysql")) {
    return(list(ok = FALSE, message = paste(
      "The 'regulated' profile does not yet accept server databases,",
      "because zzedc cannot check the server's encryption. Choose DuckDB,",
      "or go back and choose the 'standard' profile."
    )))
  }
  list(ok = TRUE, message = "Encrypted at rest with your key; accepted by the 'regulated' profile.")
}


#' Setup Wizard Server
#'
#' @param id The namespace id for the module
#' @param base_path Directory in which the study is created (a value or a
#'   reactive).
#' @param on_launch Optional function called by the "Launch ZZedc" button
#'   after the study is created (for example `function() shiny::stopApp("launch")`).
#'   The database key (DuckDB) and security salt are set as environment
#'   variables for the current R session first, so an immediate launch can
#'   open the study.
#' @param on_close Optional function called by the "Close" button.
#' @return List of reactives: `setup_complete`, `system_config`,
#'   `current_step`, `result` (from `complete_wizard_setup()`).
#'
#' @examples
#' \dontrun{
#' if (interactive()) {
#'   ui <- bslib::page_fluid(shinyjs::useShinyjs(), setup_wizard_ui("wizard"))
#'   server <- function(input, output, session) {
#'     setup_wizard_server("wizard", base_path = tempfile("zzedc_"))
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
setup_wizard_server <- function(id, base_path = getwd(), on_launch = NULL,
                                on_close = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    resolve_base <- function() if (is.reactive(base_path)) base_path() else base_path

    # Panels in display order; the ids of steps after the new Database
    # step keep their historical names.
    step_panels <- c("step1_panel", "step2_panel", "step3_panel",
                     "stepdb_panel", "step4_panel", "step5_panel")

    wizard_state <- reactiveValues(
      current_step = 1,
      total_steps = length(step_panels),
      setup_complete = FALSE,
      result = NULL,
      team_members = data.frame(username = character(),
                               full_name = character(),
                               email = character(),
                               role = character(),
                               stringsAsFactors = FALSE),
      system_config = list()
    )

    # Cryptographically random values (sample() is not).
    security_salt <- substr(generate_db_key(), 1, 32)
    db_key <- generate_db_key()

    update_progress <- function() {
      progress_pct <- round((wizard_state$current_step / wizard_state$total_steps) * 100)
      shinyjs::runjs(sprintf(
        "document.getElementById('%s').style.width = '%d%%';
         document.getElementById('%s').textContent = 'Step %d of %d';",
        ns("progress_bar"), progress_pct,
        ns("progress_bar"), wizard_state$current_step, wizard_state$total_steps
      ))
    }

    show_step <- function(step_num) {
      for (panel in step_panels) {
        shinyjs::hide(panel)
      }
      shinyjs::show(step_panels[step_num])
      wizard_state$current_step <- step_num
      update_progress()
    }

    validation_error <- function(errors) {
      shinyalert("Validation Error",
                 paste("Please fix these errors:\n", paste("- ", errors, collapse = "\n")),
                 type = "error")
    }

    copy_to_clipboard <- function(input_id, what) {
      shinyjs::runjs(paste0(
        "navigator.clipboard.writeText(document.getElementById('", ns(input_id), "').value);"
      ))
      showNotification(paste(what, "copied to the clipboard."), type = "message", duration = 3)
    }

    # Step 1: Basic Information
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
      } else if (!grepl("^[^@]+@[^@]+\\.[^@]+$", input$pi_email)) {
        errors <- c(errors, "PI Email is invalid")
      }
      if (length(errors) > 0) return(validation_error(errors))

      wizard_state$system_config$study_name <- input$study_name
      wizard_state$system_config$protocol_id <- input$protocol_id
      wizard_state$system_config$pi_name <- input$pi_name
      wizard_state$system_config$pi_email <- input$pi_email
      wizard_state$system_config$target_enrollment <- input$target_enrollment
      wizard_state$system_config$study_phase <- input$study_phase
      show_step(2)
    })

    # Step 2: Admin Account
    observeEvent(input$step2_next, {
      errors <- character()
      if (is.null(input$admin_username) || input$admin_username == "") {
        errors <- c(errors, "Username is required")
      } else if (grepl(" ", input$admin_username)) {
        errors <- c(errors, "Username cannot contain spaces")
      }
      if (is.null(input$admin_fullname) || input$admin_fullname == "") {
        errors <- c(errors, "Full Name is required")
      }
      if (is.null(input$admin_email) || input$admin_email == "") {
        errors <- c(errors, "Email is required")
      } else if (!grepl("^[^@]+@[^@]+\\.[^@]+$", input$admin_email)) {
        errors <- c(errors, "Email is invalid")
      }
      if (is.null(input$admin_password) || nchar(input$admin_password) < 8) {
        errors <- c(errors, "Password must be at least 8 characters")
      }
      if (!identical(input$admin_password, input$admin_password_confirm)) {
        errors <- c(errors, "Passwords do not match")
      }
      if (length(errors) > 0) return(validation_error(errors))

      wizard_state$system_config$admin_username <- input$admin_username
      wizard_state$system_config$admin_fullname <- input$admin_fullname
      wizard_state$system_config$admin_email <- input$admin_email
      wizard_state$system_config$admin_password <- input$admin_password
      show_step(3)
    })
    observeEvent(input$step2_prev, show_step(1))

    # Step 3: Security
    observe({
      updateTextInput(session, "security_salt", value = security_salt)
      updateTextInput(session, "db_key_display", value = db_key)
    })
    observeEvent(input$copy_salt, copy_to_clipboard("security_salt", "Security salt"))
    observeEvent(input$copy_db_key, copy_to_clipboard("db_key_display", "Encryption key"))

    observeEvent(input$step3_next, {
      if (!isTRUE(input$confirm_salt)) {
        shinyalert("Confirmation Required",
                   "Please confirm that you have saved the security salt.",
                   type = "error")
        return()
      }
      wizard_state$system_config$security_salt <- security_salt
      wizard_state$system_config$security_profile <- input$security_profile
      wizard_state$system_config$session_timeout <- input$session_timeout
      wizard_state$system_config$enforce_https <- input$enforce_https
      wizard_state$system_config$max_login_attempts <- input$max_login_attempts
      show_step(4)
    })
    observeEvent(input$step3_prev, show_step(2))

    # Step 4: Database
    observeEvent(input$compare_backends, {
      d <- describe_backends()
      showModal(modalDialog(
        title = "Comparing the database options",
        size = "l", easyClose = TRUE,
        tags$table(class = "table table-sm",
          tags$thead(tags$tr(
            tags$th("Database"), tags$th("Use for"),
            tags$th("Encryption at rest"), tags$th("'Regulated' profile")
          )),
          tags$tbody(lapply(seq_len(nrow(d)), function(i) tags$tr(
            tags$td(tags$strong(d$label[i])), tags$td(d$use_when[i]),
            tags$td(d$encryption_at_rest[i]), tags$td(d$regulated[i])
          )))
        ),
        footer = modalButton("Close")
      ))
    })

    observeEvent(input$db_backend, {
      if (input$db_backend %in% c("postgresql", "mysql")) {
        updateNumericInput(session, "db_port",
                           value = if (input$db_backend == "postgresql") 5432 else 3306)
      }
    }, ignoreInit = TRUE)

    output$db_fit <- renderUI({
      req(input$db_backend)
      fit <- .backend_fits_profile(input$db_backend, input$security_profile %||% "regulated")
      div(class = paste("alert", if (fit$ok) "alert-success" else "alert-danger"),
          fit$message)
    })

    output$db_password_status <- renderUI({
      set <- nzchar(Sys.getenv("ZZEDC_DB_PASSWORD"))
      div(class = paste("small", if (set) "text-success" else "text-danger"),
          if (set) {
            "The database password will be read from ZZEDC_DB_PASSWORD (set in this session)."
          } else {
            paste("Set the database password as the environment variable",
                  "ZZEDC_DB_PASSWORD before creating the study; it is not",
                  "entered here or written to the project.")
          })
    })

    observeEvent(input$stepdb_next, {
      backend <- input$db_backend
      fit <- .backend_fits_profile(backend, input$security_profile %||% "regulated")
      errors <- character()
      if (!fit$ok) errors <- c(errors, fit$message)
      if (backend == "duckdb" && !isTRUE(input$confirm_db_key)) {
        errors <- c(errors, "Confirm that you have saved the encryption key")
      }
      if (backend %in% c("postgresql", "mysql")) {
        if (!nzchar(input$db_host %||% "")) errors <- c(errors, "Server host is required")
        if (!nzchar(input$db_name %||% "")) errors <- c(errors, "Database name is required")
        if (!nzchar(input$db_user %||% "")) errors <- c(errors, "Database user is required")
        if (!nzchar(Sys.getenv("ZZEDC_DB_PASSWORD"))) {
          errors <- c(errors, "Set ZZEDC_DB_PASSWORD in the environment first")
        }
      }
      if (length(errors) > 0) return(validation_error(errors))

      wizard_state$system_config$db_backend <- backend
      wizard_state$system_config$db_encryption_key <- if (backend == "duckdb") db_key
      wizard_state$system_config$install_extensions <- isTRUE(input$install_extensions)
      wizard_state$system_config$db_settings <- if (backend %in% c("postgresql", "mysql")) {
        list(host = input$db_host, port = as.integer(input$db_port),
             name = input$db_name, user = input$db_user,
             ssl = if (backend == "postgresql") input$pg_sslmode else input$my_ssl_mode)
      }
      show_step(5)
    })
    observeEvent(input$stepdb_prev, show_step(3))

    # Step 5: Team Members
    observeEvent(input$add_team_member, {
      if (input$team_member_username == "" ||
          input$team_member_name == "" ||
          input$team_member_email == "") {
        shinyalert("Incomplete", "Please fill in all team member fields", type = "warning")
        return()
      }
      wizard_state$team_members <- rbind(wizard_state$team_members, data.frame(
        username = input$team_member_username,
        full_name = input$team_member_name,
        email = input$team_member_email,
        role = input$team_member_role,
        stringsAsFactors = FALSE
      ))
      updateTextInput(session, "team_member_username", value = "")
      updateTextInput(session, "team_member_name", value = "")
      updateTextInput(session, "team_member_email", value = "")
    })

    output$team_table <- DT::renderDT({
      DT::datatable(wizard_state$team_members,
                    options = list(pageLength = 5, dom = "t"),
                    selection = "none")
    })

    observeEvent(input$step4_next, {
      wizard_state$system_config$team_members <- wizard_state$team_members
      show_step(6)
    })
    observeEvent(input$step4_prev, show_step(4))

    # Step 6: Create the study
    observeEvent(input$step5_finish, {
      target <- resolve_base()
      if (file.exists(file.path(target, "config.yml"))) {
        shinyalert("Study already exists",
                   paste("A config.yml already exists in", target,
                         "- the wizard does not overwrite an existing study."),
                   type = "error")
        return()
      }

      result <- withProgress(message = "Creating the study...", value = 0.5, {
        tryCatch(
          complete_wizard_setup(wizard_state$system_config, base_path = target),
          error = function(e) list(overall_success = FALSE,
                                   steps = list(setup = list(success = FALSE, message = conditionMessage(e))))
        )
      })
      wizard_state$result <- result

      if (!isTRUE(result$overall_success)) {
        failed <- Filter(function(s) !isTRUE(s$success), result$steps)
        shinyalert("Setup failed",
                   paste(vapply(failed, function(s) s$message %||% "unknown error", ""),
                         collapse = "\n"),
                   type = "error")
        return()
      }

      for (panel in step_panels) shinyjs::hide(panel)
      shinyjs::show("success_panel")
      wizard_state$setup_complete <- TRUE
    })
    observeEvent(input$step5_prev, show_step(5))

    output$setup_summary <- renderUI({
      result <- wizard_state$result
      req(result)
      backend <- wizard_state$system_config$db_backend %||% "sqlite"
      tagList(
        tags$pre(result$summary),
        if (backend == "duckdb") {
          div(class = "alert alert-warning mt-2",
              "Each time you launch this study, ", code("DB_ENCRYPTION_KEY"),
              " must be set to the encryption key you saved in Step 4.")
        },
        p("Log in with the administrator account you created in Step 2.")
      )
    })

    observeEvent(input$launch_app, {
      if (is.function(on_launch)) {
        Sys.setenv(ZZEDC_SALT = security_salt)
        if (identical(wizard_state$system_config$db_backend, "duckdb")) {
          Sys.setenv(DB_ENCRYPTION_KEY = db_key)
        }
        on_launch()
      } else {
        shinyalert("Ready",
                   paste("Start the study with its launch script, launch_app.R,",
                         "in", resolve_base()),
                   type = "success")
      }
    })

    observeEvent(input$finish_setup, {
      if (is.function(on_close)) on_close()
    })

    list(
      setup_complete = reactive(wizard_state$setup_complete),
      system_config = reactive(wizard_state$system_config),
      current_step = reactive(wizard_state$current_step),
      result = reactive(wizard_state$result)
    )
  })
}


#' Create a New Study with the Setup Wizard
#'
#' Opens the setup wizard in a web browser. It asks for the study's
#' details, an administrator account, the security profile, and the
#' database (with a comparison of the options), then creates the study
#' in `base_path`: the database, `config.yml`, and a launch script.
#'
#' @param base_path Directory in which to create the study. It must not
#'   already contain a `config.yml`.
#' @param launch.browser,host,port Passed to `shiny::runApp()`.
#' @param show_choice Logical. `TRUE` (default) first shows a page
#'   offering the wizard or the R console commands; `FALSE` opens the
#'   wizard directly (as `launch_zzedc(setup = TRUE)` does, the caller
#'   having already chosen it).
#'
#' @return Invisibly, `"launch"` if the user chose "Launch ZZedc" when the
#'   wizard finished, `"created"` if they closed it after creating the
#'   study, `"console"` if they chose the console commands and closed the
#'   page, or `NULL` if the browser was closed first.
#'
#' @examples
#' \dontrun{
#'   dir.create("~/studies/my_study", recursive = TRUE)
#'   setwd("~/studies/my_study")
#'   launch_setup_wizard()
#' }
#' @export
launch_setup_wizard <- function(base_path = getwd(), launch.browser = TRUE,
                                host = "127.0.0.1", port = NULL,
                                show_choice = TRUE) {
  if (file.exists(file.path(base_path, "config.yml"))) {
    stop("This directory already contains a study (config.yml): ", base_path,
         ". Run the wizard in a new, empty directory.", call. = FALSE)
  }
  dir.create(base_path, recursive = TRUE, showWarnings = FALSE)
  base_path <- normalizePath(base_path, winslash = "/")

  ui <- bslib::page_fluid(
    theme = bslib::bs_theme(version = 5),
    shinyjs::useShinyjs(),
    div(class = "container my-4", style = "max-width: 860px;",
      p(class = "text-muted", "The study will be created in ", code(base_path)),
      div(id = "choice_screen", style = if (!show_choice) "display:none;",
          setup_choice_ui("choice")),
      div(id = "wizard_screen", style = if (show_choice) "display:none;",
          h2("Create a new ZZedc study"),
          setup_wizard_ui("wizard"))
    )
  )
  server <- function(input, output, session) {
    chosen <- setup_choice_server(
      "choice", on_console = function() shiny::stopApp("console")
    )
    observeEvent(chosen(), {
      if (identical(chosen(), "wizard")) {
        shinyjs::hide("choice_screen")
        shinyjs::show("wizard_screen")
      }
    })
    setup_wizard_server(
      "wizard", base_path = base_path,
      on_launch = function() shiny::stopApp("launch"),
      on_close = function() shiny::stopApp("created")
    )
    session$onSessionEnded(function() shiny::stopApp(NULL))
  }

  outcome <- shiny::runApp(shiny::shinyApp(ui, server),
                           launch.browser = launch.browser,
                           host = host, port = port)
  invisible(outcome)
}
