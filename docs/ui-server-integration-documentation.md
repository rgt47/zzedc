# ZZedc UI and Server Integration Documentation

## Overview

This document provides comprehensive documentation for the UI and server integration functions in ZZedc's Google Sheets integration system. These functions bridge the gap between the Google Sheets configuration and the dynamic Shiny application interface, enabling seamless form generation and management.

---

## Architecture Overview

The UI and server integration follows a modular architecture that dynamically adapts based on Google Sheets configuration:

```r
# Integration flow
Google Sheets Data → Form Loaders → UI Generation → Server Logic → User Interface

# Key components:
# 1. gsheets_ui_integration.R - Dynamic UI generation
# 2. gsheets_server_integration.R - Enhanced server logic
# 3. gsheets_form_loader.R - Form data processing
# 4. Traditional modules - Fallback functionality
```

---

## UI Integration Functions

### `create_enhanced_ui()`

**Purpose**: Creates a dynamic UI that integrates Google Sheets forms with traditional ZZedc components.

**Function Signature**:
```r
create_enhanced_ui()
```

**Returns**: Complete Shiny UI object with dynamic navigation tabs

**Behavior**:
1. Attempts to load Google Sheets forms via `integrate_gsheets_forms()`
2. Dynamically builds navigation tabs based on available forms
3. Falls back to traditional EDC interface if Google Sheets unavailable
4. Includes setup and management interfaces

**Example Usage**:
```r
# Generate dynamic UI
ui <- create_enhanced_ui()

# The function automatically:
# - Detects Google Sheets forms
# - Creates tabs for each form
# - Includes management interfaces
# - Provides fallback options
```

**Key Features**:
- **Dynamic Tab Generation**: Creates tabs based on forms_overview from Google Sheets
- **Conditional Loading**: Shows Google Sheets forms if available, traditional forms otherwise
- **Integrated Management**: Includes setup and configuration interfaces
- **Responsive Design**: Uses Bootstrap 5 with bslib theming

**Generated Navigation Structure**:
```r
# When Google Sheets forms are available:
nav_structure <- list(
  "Home" = "Welcome and dashboard",
  "Form_1" = "Dynamic Google Sheets form",
  "Form_2" = "Dynamic Google Sheets form",
  "..." = "Additional forms as defined",
  "Forms Overview" = "Form management interface",
  "Basic Reports" = "Standard reporting",
  "Quality Reports" = "Data quality analysis",
  "Statistical Reports" = "Advanced analytics",
  "Data Explorer" = "Interactive data browsing",
  "Export Data" = "Data export tools",
  "Setup" = "Configuration management"
)

# When Google Sheets forms are NOT available:
nav_structure_fallback <- list(
  "Home" = "Welcome and dashboard",
  "EDC Forms" = "Traditional ZZedc forms",
  "Basic Reports" = "Standard reporting",
  "..." = "Other standard tabs",
  "Setup" = "Configuration management"
)
```

### `create_forms_overview_ui(forms_data)`

**Purpose**: Generates a comprehensive overview interface for managing Google Sheets forms.

**Parameters**:
- `forms_data`: List containing forms_overview and form definitions from Google Sheets

**Returns**: TagList with complete forms overview UI

**Example Usage**:
```r
# Create forms overview
forms_ui <- create_forms_overview_ui(gsheets_integration$forms_data)

# Generates cards for each form showing:
# - Form display name and ID
# - Associated visits
# - Field counts
# - Management actions
```

**Generated Components**:
```r
forms_overview_components <- list(
  # Form cards grid
  form_cards = list(
    card_structure = "Bootstrap cards with form information",
    actions = c("Open Form", "Preview Form"),
    information = c("Form ID", "Visits", "Field count")
  ),

  # Management section
  management_tools = list(
    google_sheets_config = "Refresh and export options",
    system_status = "Database and setup verification",
    actions = c("Refresh from Google Sheets", "Export Configuration", "Verify Setup")
  )
)
```

### `create_setup_ui()`

**Purpose**: Creates comprehensive setup and configuration management interface.

**Returns**: TagList with complete setup management UI

**Features**:
- **Google Sheets Setup**: Input fields for sheet names and project configuration
- **Traditional Setup**: Fallback to R script-based setup
- **Database Import**: Import existing ZZedc databases
- **Documentation Links**: Quick access to help resources
- **Progress Tracking**: Visual feedback during setup operations

**Example Usage**:
```r
# Create setup interface
setup_ui <- create_setup_ui()

# Provides interfaces for:
# - Google Sheets configuration
# - Traditional R setup
# - Database imports
# - Help and documentation
```

---

## Server Integration Functions

### `create_enhanced_server(input, output, session)`

**Purpose**: Creates enhanced server logic that handles both Google Sheets and traditional forms.

**Parameters**:
- `input`: Shiny input object
- `output`: Shiny output object
- `session`: Shiny session object

**Behavior**:
1. Loads authentication logic (always required)
2. Checks for Google Sheets integration availability
3. Initializes appropriate server modules
4. Sets up session management

**Example Usage**:
```r
# In server.R
server <- function(input, output, session) {
  create_enhanced_server(input, output, session)
}

# The function automatically:
# - Detects integration type
# - Loads appropriate modules
# - Sets up authentication
# - Manages user sessions
```

### `initialize_gsheets_server(input, output, session)`

**Purpose**: Initializes server logic specifically for Google Sheets forms integration.

**Parameters**:
- `input`: Shiny input object
- `output`: Shiny output object
- `session`: Shiny session object

**Key Operations**:
1. **Dynamic Form UI Generation**: Creates render functions for each Google Sheets form
2. **Form Server Logic**: Sets up save handlers and validation
3. **Database Status Monitoring**: Real-time database connectivity checks
4. **Google Sheets Management**: Refresh and verification handlers

**Example Implementation**:
```r
# Form UI generation (automatic)
for (form_name in available_forms) {
  output[[paste0("gsheets_form_", form_name)]] <- renderUI({
    if (!user_input$authenticated) {
      authentication_required_message()
    } else {
      generate_form_ui(form_name, gsheets_data$forms_data)
    }
  })
}

# Management handlers
observeEvent(input$refresh_gsheets, {
  # Reload configuration from Google Sheets
  refresh_configuration()
})

observeEvent(input$verify_setup, {
  # Verify system integrity
  run_system_verification()
})
```

**Generated Outputs**:
```r
server_outputs <- list(
  # Dynamic form UIs
  "gsheets_form_[form_name]" = "Rendered form interface",

  # System status
  "db_status" = "Database connectivity and statistics",

  # Configuration display
  "current_config_display" = "Current system configuration"
)
```

### `initialize_traditional_server(input, output, session)`

**Purpose**: Initializes traditional ZZedc server modules when Google Sheets integration is unavailable.

**Parameters**:
- `input`: Shiny input object
- `output`: Shiny output object
- `session`: Shiny session object

**Loading Strategy**:
```r
# Conditional loading based on integration availability
if (!exists("gsheets_integration_data")) {
  # Load traditional EDC forms
  source("edc.R", local = TRUE)
}

# Always load core modules (compatible with both systems)
always_loaded <- c("report1.R", "report2.R", "report3.R", "data.R", "export.R", "home.R")
```

### `initialize_setup_server(input, output, session)`

**Purpose**: Handles setup and configuration management server logic.

**Key Event Handlers**:

#### Google Sheets Setup Handler
```r
observeEvent(input$run_gsheets_setup, {
  # Validation
  validate_input_fields()

  # Progress tracking
  show_progress_interface()

  # Setup execution
  withProgress({
    success <- setup_zzedc_from_gsheets_complete(
      auth_sheet_name = input$auth_sheet_name,
      dd_sheet_name = input$dd_sheet_name,
      project_name = input$project_name
    )

    display_setup_results(success)
  })
})
```

#### Traditional Setup Handler
```r
observeEvent(input$run_traditional_setup, {
  withProgress({
    if (file.exists("setup_database.R")) {
      source("setup_database.R")
      show_success_message()
    } else {
      show_error_message("setup_database.R not found!")
    }
  })
})
```

#### Database Import Handler
```r
observeEvent(input$import_database, {
  req(input$import_db)

  # File validation
  validate_database_file(input$import_db)

  # Import process
  withProgress({
    import_database_file(input$import_db)
  })
})
```

---

## Form Generation Process

### Dynamic Form UI Creation

The system generates form UIs dynamically based on Google Sheets configuration:

```r
# Form generation pipeline
generate_form_ui <- function(form_name, forms_data) {

  # 1. Get form definition
  form_definition <- forms_data$form_definitions[[form_name]]

  # 2. Generate field UIs
  field_uis <- lapply(1:nrow(form_definition), function(i) {
    field_data <- form_definition[i, ]
    generate_field_ui(field_data)
  })

  # 3. Apply layout and styling
  form_ui <- create_form_layout(field_uis, form_name)

  # 4. Add validation and conditional logic
  add_client_side_logic(form_ui, form_definition)

  return(form_ui)
}
```

### Field Type Mapping

The system supports comprehensive field type mapping:

```r
field_type_mapping <- list(
  # Basic input types
  "text" = "textInput()",
  "numeric" = "numericInput()",
  "date" = "dateInput()",

  # Selection types
  "radio" = "radioButtons()",
  "select" = "selectInput()",
  "checkbox" = "checkboxGroupInput()",

  # Advanced types
  "textarea" = "textAreaInput()",
  "file" = "fileInput()",

  # Custom types (from advanced examples)
  "date_range" = "dateRangeInput()",
  "slider_range" = "sliderInput()",
  "color_picker" = "colourInput()"
)
```

---

## Event Handling and Reactivity

### Form Data Management

```r
# Form save handlers are generated dynamically
generate_form_save_handlers <- function(forms_data, input, output, session) {

  for (form_name in names(forms_data$form_definitions)) {

    # Create save handler for this form
    save_button_id <- paste0("save_", form_name)

    observeEvent(input[[save_button_id]], {

      # 1. Collect form data
      form_data <- collect_form_data(form_name, input)

      # 2. Validate data
      validation_results <- validate_form_data(form_data, form_name)

      # 3. Save to database if valid
      if (validation_results$valid) {
        save_success <- save_form_to_database(form_data, form_name)
        show_save_feedback(save_success)
      } else {
        show_validation_errors(validation_results$errors)
      }
    })
  }
}
```

### Real-time Validation

```r
# Client-side validation setup
add_client_side_validation <- function(form_ui, form_definition) {

  validation_rules <- list()

  for (i in 1:nrow(form_definition)) {
    field <- form_definition[i, ]

    if (!is.na(field$valid) && field$valid != "") {
      validation_rules[[field$field]] <- list(
        rule = field$valid,
        message = field$validmsg %||% "Validation failed"
      )
    }
  }

  # Add JavaScript validation
  validation_js <- generate_validation_javascript(validation_rules)
  form_ui <- tagList(form_ui, tags$script(validation_js))

  return(form_ui)
}
```

---

## Configuration Management

### System Configuration Display

```r
# Real-time configuration monitoring
output$current_config_display <- renderText({
  config_info <- c()

  # Database information
  if (exists("cfg") && !is.null(cfg$database$path)) {
    config_info <- append_database_info(config_info, cfg$database$path)
  }

  # Google Sheets integration status
  if (exists("gsheets_integration_data")) {
    config_info <- append_gsheets_info(config_info)
  } else {
    config_info <- c(config_info, "Google Sheets Integration: ❌ NOT ACTIVE")
  }

  # Generated forms information
  config_info <- append_forms_info(config_info)

  paste(config_info, collapse = "\n")
})
```

### Progress Tracking

```r
# Setup progress management
manage_setup_progress <- function(steps, total_steps) {

  # UI progress bar updates
  update_progress_bar <- function(current_step) {
    percentage <- (current_step / total_steps) * 100
    shinyjs::runjs(paste0(
      "$('#setup_progress .progress-bar').css('width', '", percentage, "%');"
    ))
  }

  # Step-by-step progress with user feedback
  for (i in 1:length(steps)) {
    incProgress(1/total_steps, detail = steps[i])
    update_progress_bar(i)

    # Execute step logic here
    execute_setup_step(steps[i])
  }
}
```

---

## Error Handling and User Feedback

### Comprehensive Error Management

```r
# Standardized error handling
handle_setup_error <- function(error, operation_type) {

  error_messages <- list(
    "gsheets_auth" = "Google Sheets authentication failed. Check your credentials and permissions.",
    "gsheets_read" = "Could not read Google Sheets. Verify sheet names and access permissions.",
    "database_create" = "Database creation failed. Check file permissions and disk space.",
    "forms_generate" = "Form generation failed. Check data dictionary format.",
    "general" = paste("Operation failed:", error$message)
  )

  user_message <- error_messages[[operation_type]] %||% error_messages[["general"]]

  shinyalert::shinyalert(
    title = "Setup Error",
    text = paste(user_message,
                "\n\nTechnical details:", error$message,
                "\n\nCheck the R console for detailed error information."),
    type = "error",
    size = "m"
  )
}
```

### Success Feedback

```r
# User success notifications
show_setup_success <- function(operation_type, details = NULL) {

  success_messages <- list(
    "gsheets_setup" = "✅ Google Sheets setup completed successfully!",
    "traditional_setup" = "✅ Traditional setup completed successfully!",
    "database_import" = "✅ Database imported successfully!",
    "verification" = "✅ System verification passed!"
  )

  base_message <- success_messages[[operation_type]]
  full_message <- if (!is.null(details)) {
    paste(base_message, "\n\n", details)
  } else {
    base_message
  }

  shinyalert::shinyalert(
    title = "Success",
    text = full_message,
    type = "success"
  )
}
```

---

## Integration with Authentication System

### User Authentication Flow

```r
# Authentication integration
integrate_authentication <- function(ui_element) {

  # Wrap UI elements with authentication checks
  authenticated_ui <- div(
    # Authentication status check
    conditionalPanel(
      condition = "input.authenticated == false",
      div(class = "alert alert-warning",
        h4("Authentication Required"),
        p("Please log in to access this feature."),
        actionButton("show_login", "Login", class = "btn-primary")
      )
    ),

    # Actual UI (shown when authenticated)
    conditionalPanel(
      condition = "input.authenticated == true",
      ui_element
    )
  )

  return(authenticated_ui)
}
```

### Role-Based Access Control

```r
# Role-based UI modification
apply_role_permissions <- function(ui_element, required_role) {

  # Check user role and modify UI accordingly
  role_based_ui <- div(
    conditionalPanel(
      condition = paste0("input.user_role == '", required_role, "' || input.user_role == 'Admin'"),
      ui_element
    ),

    # Access denied message for insufficient permissions
    conditionalPanel(
      condition = paste0("input.authenticated == true && input.user_role != '", required_role, "' && input.user_role != 'Admin'"),
      div(class = "alert alert-danger",
        h4("Access Denied"),
        p(paste("This feature requires", required_role, "role or higher."))
      )
    )
  )

  return(role_based_ui)
}
```

---

## Performance Optimization

### Lazy Loading

```r
# Lazy loading of form UIs for better performance
implement_lazy_loading <- function() {

  # Only render forms when tabs are activated
  observeEvent(input$main_nav, {

    active_tab <- input$main_nav

    # Check if this is a form tab
    if (startsWith(active_tab, "gsheets_form_")) {
      form_name <- sub("gsheets_form_", "", active_tab)

      # Render form only when needed
      if (is.null(input[[paste0(form_name, "_rendered")]])) {
        render_form_ui(form_name)
        updateCheckboxInput(session, paste0(form_name, "_rendered"), value = TRUE)
      }
    }
  })
}
```

### Caching Strategy

```r
# Cache form definitions and UIs for performance
cache_manager <- list(

  # Cache form UIs
  form_ui_cache = new.env(),

  # Cache form data
  form_data_cache = new.env(),

  # Get or create cached UI
  get_cached_ui = function(form_name, generator_function) {

    cache_key <- paste0("ui_", form_name)

    if (exists(cache_key, envir = cache_manager$form_ui_cache)) {
      return(get(cache_key, envir = cache_manager$form_ui_cache))
    } else {
      ui <- generator_function(form_name)
      assign(cache_key, ui, envir = cache_manager$form_ui_cache)
      return(ui)
    }
  },

  # Clear cache when configuration changes
  clear_cache = function() {
    rm(list = ls(cache_manager$form_ui_cache), envir = cache_manager$form_ui_cache)
    rm(list = ls(cache_manager$form_data_cache), envir = cache_manager$form_data_cache)
  }
)
```

---

## Testing and Validation

### UI Testing Functions

```r
# Test UI generation
test_ui_generation <- function(test_forms_data) {

  tryCatch({
    # Test main UI creation
    test_ui <- create_enhanced_ui()
    if (is.null(test_ui)) stop("UI creation failed")

    # Test forms overview UI
    overview_ui <- create_forms_overview_ui(test_forms_data)
    if (is.null(overview_ui)) stop("Forms overview UI creation failed")

    # Test setup UI
    setup_ui <- create_setup_ui()
    if (is.null(setup_ui)) stop("Setup UI creation failed")

    message("✅ All UI tests passed")
    return(TRUE)

  }, error = function(e) {
    message("❌ UI test failed: ", e$message)
    return(FALSE)
  })
}
```

### Server Logic Validation

```r
# Test server initialization
test_server_integration <- function() {

  # Create mock session objects
  mock_input <- list()
  mock_output <- list()
  mock_session <- list()

  tryCatch({
    # Test server creation
    create_enhanced_server(mock_input, mock_output, mock_session)

    message("✅ Server integration test passed")
    return(TRUE)

  }, error = function(e) {
    message("❌ Server integration test failed: ", e$message)
    return(FALSE)
  })
}
```

---

## Usage Examples

### Basic Integration Setup

```r
# Example: Complete application setup
setup_integrated_application <- function() {

  # 1. Create the integrated UI
  ui <- create_enhanced_ui()

  # 2. Define server logic
  server <- function(input, output, session) {
    create_enhanced_server(input, output, session)
  }

  # 3. Launch application
  shinyApp(ui = ui, server = server)
}
```

### Custom Form Integration

```r
# Example: Add custom form to existing integration
add_custom_form <- function(form_definition, form_name) {

  # 1. Validate form definition
  validate_form_structure(form_definition)

  # 2. Add to integration data
  if (exists("gsheets_integration_data")) {
    gsheets_data <- get("gsheets_integration_data", envir = .GlobalEnv)

    # Add custom form
    gsheets_data$forms_data$form_definitions[[form_name]] <- form_definition

    # Update forms overview
    new_overview_row <- data.frame(
      workingname = form_name,
      fullname = paste("Custom", form_name),
      visits = "baseline",
      stringsAsFactors = FALSE
    )

    gsheets_data$forms_data$forms_overview <- rbind(
      gsheets_data$forms_data$forms_overview,
      new_overview_row
    )

    # Update global data
    assign("gsheets_integration_data", gsheets_data, envir = .GlobalEnv)

    message("✅ Custom form added: ", form_name)
  } else {
    message("❌ Google Sheets integration not available")
  }
}
```

---

## Troubleshooting Guide

### Common Integration Issues

#### 1. Google Sheets Authentication Problems
```r
# Diagnosis
diagnose_gsheets_auth <- function() {
  tryCatch({
    gs4_user()
    message("✅ Google Sheets authentication OK")
  }, error = function(e) {
    message("❌ Authentication failed: ", e$message)
    message("Solution: Run gs4_auth() and follow authentication prompts")
  })
}
```

#### 2. Form UI Generation Failures
```r
# Diagnosis
diagnose_form_ui_issues <- function(form_name) {

  issues <- list()

  # Check if integration data exists
  if (!exists("gsheets_integration_data")) {
    issues <- append(issues, "Google Sheets integration data not found")
  }

  # Check form definition
  if (exists("gsheets_integration_data")) {
    gsheets_data <- get("gsheets_integration_data", envir = .GlobalEnv)
    if (!form_name %in% names(gsheets_data$forms_data$form_definitions)) {
      issues <- append(issues, paste("Form definition not found:", form_name))
    }
  }

  # Report issues
  if (length(issues) > 0) {
    message("❌ Form UI issues found:")
    for (issue in issues) {
      message("   - ", issue)
    }
  } else {
    message("✅ No form UI issues detected")
  }

  return(length(issues) == 0)
}
```

#### 3. Server Integration Problems
```r
# Diagnosis
diagnose_server_integration <- function() {

  checks <- list(
    "auth.R exists" = file.exists("auth.R"),
    "gsheets_integration_data available" = exists("gsheets_integration_data"),
    "database connection" = test_database_connection(),
    "required packages loaded" = test_required_packages()
  )

  message("🔍 Server integration diagnosis:")
  for (check_name in names(checks)) {
    status <- if (checks[[check_name]]) "✅" else "❌"
    message(paste(status, check_name))
  }

  return(all(unlist(checks)))
}
```

---

## Best Practices

### UI Development Guidelines

1. **Modular Design**: Keep UI components small and focused
2. **Progressive Enhancement**: Provide fallbacks for missing functionality
3. **User Feedback**: Always provide clear feedback for user actions
4. **Performance**: Use lazy loading and caching where appropriate
5. **Accessibility**: Follow web accessibility standards

### Server Logic Best Practices

1. **Error Handling**: Implement comprehensive error handling with user-friendly messages
2. **Input Validation**: Always validate user inputs before processing
3. **Resource Management**: Properly manage database connections and file handles
4. **Security**: Implement proper authentication and authorization checks
5. **Logging**: Log important events for debugging and auditing

### Integration Maintenance

1. **Version Control**: Track changes to integration code
2. **Testing**: Regularly test integration functionality
3. **Documentation**: Keep documentation updated with code changes
4. **Monitoring**: Monitor system performance and user feedback
5. **Updates**: Keep dependencies and packages updated

---

This documentation provides comprehensive coverage of ZZedc's UI and server integration functions, enabling developers to understand, customize, and extend the system's dynamic interface capabilities while maintaining high standards of usability and performance.