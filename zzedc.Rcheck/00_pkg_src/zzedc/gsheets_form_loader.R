# Google Sheets Form Loader for ZZedc
# Integrates generated forms from Google Sheets into the main ZZedc application

#' Load forms generated from Google Sheets into ZZedc
#' @param forms_dir Directory containing generated form files
#' @param db_path Path to database file
load_gsheets_forms <- function(forms_dir = "forms_generated", db_path = NULL) {

  if (is.null(db_path)) {
    # Try to get from config
    if (exists("cfg")) {
      db_path <- cfg$database$path
    } else {
      db_path <- "data/zzedc_gsheets.db"
    }
  }

  message("Loading Google Sheets forms from: ", forms_dir)

  # Check if forms directory exists
  if (!dir.exists(forms_dir)) {
    stop("Forms directory not found: ", forms_dir)
  }

  # Load form definitions from database
  con <- RSQLite::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(RSQLite::dbDisconnect(con))

  tryCatch({
    # Get forms overview
    forms_overview <- RSQLite::dbGetQuery(con, "SELECT * FROM edc_forms")

    if (nrow(forms_overview) == 0) {
      stop("No forms found in database. Run Google Sheets setup first.")
    }

    # Load validation rules if they exist
    validation_file <- file.path(forms_dir, "validation_rules.R")
    if (file.exists(validation_file)) {
      source(validation_file, local = TRUE)
      message("Loaded validation rules")
    }

    # Create form loading functions for each form
    form_loaders <- list()

    for (i in 1:nrow(forms_overview)) {
      form_name <- forms_overview$workingname[i]
      form_display_name <- forms_overview$fullname[i]
      form_file <- file.path(forms_dir, paste0(form_name, "_form.R"))

      if (file.exists(form_file)) {
        # Source the form file
        source(form_file, local = TRUE)

        # Create form loader function
        form_function_name <- paste0(form_name, "_form")
        if (exists(form_function_name)) {
          form_loaders[[form_name]] <- get(form_function_name)
          message("Loaded form: ", form_display_name, " (", form_name, ")")
        }
      } else {
        warning("Form file not found: ", form_file)
      }
    }

    # Return forms information
    return(list(
      forms_overview = forms_overview,
      form_loaders = form_loaders,
      validation_rules = if(exists("validation_rules")) validation_rules else list()
    ))

  }, error = function(e) {
    stop("Error loading Google Sheets forms: ", e$message)
  })
}

#' Generate dynamic UI for Google Sheets forms
#' @param form_name Name of the form to generate
#' @param forms_data Forms data from load_gsheets_forms()
generate_form_ui <- function(form_name, forms_data) {

  if (!form_name %in% names(forms_data$form_loaders)) {
    stop("Form not found: ", form_name)
  }

  form_loader <- forms_data$form_loaders[[form_name]]
  form_info <- forms_data$forms_overview[forms_data$forms_overview$workingname == form_name, ]

  # Generate the UI
  form_ui <- tagList(
    h3(form_info$fullname),
    hr(),
    form_loader(),  # Call the form generation function
    br(),
    actionButton(
      paste0("submit_", form_name),
      "Submit Form",
      class = "btn-primary",
      icon = icon("save")
    )
  )

  return(form_ui)
}

#' Create tabs for all Google Sheets forms
#' @param forms_data Forms data from load_gsheets_forms()
create_gsheets_form_tabs <- function(forms_data) {

  form_tabs <- list()

  for (i in 1:nrow(forms_data$forms_overview)) {
    form_name <- forms_data$forms_overview$workingname[i]
    form_display_name <- forms_data$forms_overview$fullname[i]

    # Create tab for this form
    form_tab <- tabPanel(
      title = form_display_name,
      value = paste0("tab_", form_name),
      fluidRow(
        column(12,
          generate_form_ui(form_name, forms_data)
        )
      )
    )

    form_tabs[[form_name]] <- form_tab
  }

  return(form_tabs)
}

#' Integration function to add Google Sheets forms to existing ZZedc UI
#' This function modifies the main UI to include Google Sheets forms
integrate_gsheets_forms <- function() {

  # Check if we have Google Sheets forms
  forms_dir <- "forms_generated"
  if (!dir.exists(forms_dir)) {
    message("No Google Sheets forms found. Use traditional ZZedc forms.")
    return(NULL)
  }

  # Try to load Google Sheets forms
  tryCatch({
    forms_data <- load_gsheets_forms(forms_dir)

    if (length(forms_data$form_loaders) == 0) {
      message("No form loaders available. Use traditional ZZedc forms.")
      return(NULL)
    }

    message("Integrating ", length(forms_data$form_loaders), " Google Sheets forms")

    # Create form tabs
    form_tabs <- create_gsheets_form_tabs(forms_data)

    # Return integration data
    return(list(
      forms_data = forms_data,
      form_tabs = form_tabs,
      has_gsheets_forms = TRUE
    ))

  }, error = function(e) {
    message("Could not load Google Sheets forms: ", e$message)
    return(NULL)
  })
}

#' Generate server logic for Google Sheets forms
#' @param forms_data Forms data from load_gsheets_forms()
#' @param input Shiny input object
#' @param output Shiny output object
#' @param session Shiny session object
generate_gsheets_form_server <- function(forms_data, input, output, session) {

  # Load validation cache at startup
  source("R/validation_cache.R", local = TRUE)

  # Generate submit handlers for each form
  for (i in 1:nrow(forms_data$forms_overview)) {
    form_name <- forms_data$forms_overview$workingname[i]
    submit_button_id <- paste0("submit_", form_name)

    # Create submit handler for this form
    local({
      local_form_name <- form_name
      local_form_display <- forms_data$forms_overview$fullname[i]

      observeEvent(input[[submit_button_id]], {

        # Get form fields from database
        con <- RSQLite::dbConnect(RSQLite::SQLite(), cfg$database$path)
        on.exit(RSQLite::dbDisconnect(con))

        form_fields <- RSQLite::dbGetQuery(con,
          "SELECT field FROM edc_fields WHERE form_name = ?",
          params = list(local_form_name)
        )

        # Collect form data
        form_data <- list()
        for (field in form_fields$field) {
          if (!is.null(input[[field]])) {
            form_data[[field]] <- input[[field]]
          }
        }

        # Add metadata
        form_data$subject_id <- input$subject_id %||% "SUBJ001"
        form_data$visit_code <- input$visit_code %||% "baseline"
        form_data$entry_date <- Sys.time()
        form_data$entry_user <- user_input$user_id %||% 1
        form_data$form_status <- "complete"

        # Validate form data before saving
        validation_result <- validate_form(form_data)

        # If validation failed, show errors and stop
        if (!validation_result$valid) {
          error_messages <- paste(
            names(validation_result$errors),
            unlist(validation_result$errors),
            sep = ": ",
            collapse = "\n"
          )

          shinyalert::shinyalert(
            "Validation Errors",
            paste("Please fix the following errors:\n\n", error_messages),
            type = "error"
          )
          return()
        }

        # Save to database
        table_name <- paste0("data_", local_form_name)

        tryCatch({
          # Insert data
          field_names <- names(form_data)
          field_values <- unlist(form_data)

          placeholders <- paste(rep("?", length(field_values)), collapse = ", ")
          insert_sql <- paste0("INSERT INTO ", table_name, " (",
                              paste(field_names, collapse = ", "),
                              ") VALUES (", placeholders, ")")

          RSQLite::dbExecute(con, insert_sql, params = as.list(field_values))

          # Show success message
          shinyalert::shinyalert(
            "Success",
            paste("Form", local_form_display, "saved successfully!"),
            type = "success"
          )

          # Clear form (optional)
          # for (field in form_fields$field) {
          #   updateTextInput(session, field, value = "")
          # }

        }, error = function(e) {
          shinyalert::shinyalert(
            "Error",
            paste("Failed to save form:", e$message),
            type = "error"
          )
        })
      })
    })
  }
}

#' Helper function - null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (is.character(x) && x == "")) y else x
}