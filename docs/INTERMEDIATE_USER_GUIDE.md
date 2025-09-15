# ZZedc User Guide for Intermediate R Users

## Introduction

This comprehensive guide is designed for intermediate R users who want to understand, customize, and extend ZZedc's Google Sheets integration system. Whether you're a biostatistician, data manager, or research programmer, this guide provides the knowledge and examples needed to effectively work with ZZedc.

### Prerequisites

This guide assumes you have:
- **Intermediate R knowledge**: Comfortable with data manipulation, functions, and package management
- **Basic Shiny understanding**: Familiar with reactive programming and UI/server concepts
- **Database basics**: Understanding of SQL and relational database concepts
- **Clinical research awareness**: General knowledge of clinical trial workflows

---

## Quick Start for Intermediate Users

### System Overview and Architecture

ZZedc with Google Sheets integration follows a modular architecture that separates concerns and provides flexibility for customization:

```r
# Core system components
zzedc_architecture <- list(

  # Data Layer
  data_sources = c(
    "Google Sheets (Configuration)",
    "SQLite Database (Runtime Data)",
    "Generated R Files (Form Definitions)"
  ),

  # Application Layer
  core_modules = c(
    "gsheets_integration.R - Google Sheets connectivity",
    "gsheets_auth_builder.R - Authentication system",
    "gsheets_dd_builder.R - Data dictionary processing",
    "gsheets_form_loader.R - Dynamic form loading",
    "gsheets_ui_integration.R - UI enhancement",
    "gsheets_server_integration.R - Server logic"
  ),

  # Presentation Layer
  user_interface = c(
    "Enhanced UI with dynamic forms",
    "Setup and configuration interfaces",
    "Traditional ZZedc components"
  )
)

# Understanding the data flow
data_flow_example <- function() {
  # 1. Google Sheets → Configuration Reading
  config_data <- read_auth_from_gsheets("my_study_auth")

  # 2. Configuration → Database Schema
  build_auth_tables(config_data, "data/study.db")

  # 3. Google Sheets → Form Generation
  dd_data <- read_dd_from_gsheets("my_study_dd")
  generate_form_files(dd_data, "forms_generated")

  # 4. Generated Forms → Dynamic UI
  forms_data <- load_gsheets_forms("forms_generated", "data/study.db")

  return(forms_data)
}
```

### Essential Setup Pattern

Every ZZedc Google Sheets project follows this standard setup pattern that you can adapt for your specific needs:

```r
# Standard setup pattern for intermediate users
setup_my_clinical_study <- function() {

  # 1. Environment preparation
  if (!require("pacman")) install.packages("pacman")
  pacman::p_load(googlesheets4, RSQLite, digest, shiny, DT)

  # 2. Load ZZedc Google Sheets system
  source("gsheets_integration.R")
  source("setup_from_gsheets.R")

  # 3. Configure your study parameters
  study_config <- list(
    auth_sheet = "MyStudy_Authentication",
    dd_sheet = "MyStudy_DataDictionary",
    project_name = "my_clinical_study",
    db_path = "data/my_study.db",
    salt = Sys.getenv("MY_STUDY_SALT", "default_salt_2024"),
    forms_dir = "forms_my_study"
  )

  # 4. Execute setup with error handling
  setup_success <- tryCatch({
    do.call(setup_zzedc_from_gsheets_complete, study_config)
  }, error = function(e) {
    message("Setup failed: ", e$message)
    message("Check Google Sheets access and structure")
    return(FALSE)
  })

  if (setup_success) {
    message("✅ Study setup completed successfully!")
    message("Launch with: source('launch_my_clinical_study.R')")
  }

  return(setup_success)
}

# Run your setup
setup_my_clinical_study()
```

---

## Working with Google Sheets Configuration

### Authentication Sheet Design

Understanding the authentication sheet structure allows you to design sophisticated user management:

```r
# Advanced authentication sheet design
create_advanced_auth_sheet <- function() {

  # Users tab - comprehensive user definition
  users_schema <- data.frame(
    # Required fields
    username = c("pi_jdoe", "coord_smith", "dm_wilson", "stat_jones"),
    password = c("SecurePass123!", "CoordPass456!", "DMPass789!", "StatPass012!"),
    full_name = c("Dr. Jane Doe", "Sarah Smith", "Mike Wilson", "Lisa Jones"),

    # Role-based access
    role = c("Principal_Investigator", "Study_Coordinator", "Data_Manager", "Biostatistician"),

    # Site assignment (for multi-site studies)
    site_id = c(1, 1, 1, 1),

    # Optional but useful fields
    email = c("jdoe@hospital.edu", "ssmith@hospital.edu", "mwilson@hospital.edu", "ljones@hospital.edu"),
    department = c("Cardiology", "Clinical Research", "Data Management", "Biostatistics"),
    phone = c("555-0101", "555-0102", "555-0103", "555-0104"),

    # Account management
    active = c(1, 1, 1, 1),
    start_date = as.Date(c("2024-01-15", "2024-01-20", "2024-02-01", "2024-02-15")),
    end_date = as.Date(c(NA, NA, NA, NA)),  # Leave blank for active users

    # Security settings
    force_password_change = c(0, 0, 0, 0),
    mfa_required = c(1, 0, 1, 0),

    stringsAsFactors = FALSE
  )

  # Roles tab - define permission structure
  roles_schema <- data.frame(
    role = c("Principal_Investigator", "Study_Coordinator", "Data_Manager", "Biostatistician", "Monitor"),
    description = c(
      "Full study oversight and data access",
      "Patient management and data entry",
      "Data quality and database management",
      "Statistical analysis and reporting",
      "Study monitoring and compliance"
    ),
    permissions = c("all", "read_write", "read_write_admin", "read_analyze", "read_only"),
    data_access_level = c("all_subjects", "site_subjects", "all_subjects", "deidentified", "all_subjects"),
    can_modify_users = c(1, 0, 1, 0, 0),
    can_export_data = c(1, 1, 1, 1, 0),
    stringsAsFactors = FALSE
  )

  # Sites tab - for multi-site coordination
  sites_schema <- data.frame(
    site_id = 1:3,
    site_name = c("University Hospital", "Community Medical Center", "Regional Clinic"),
    site_code = c("UH", "CMC", "RC"),
    principal_investigator = c("Dr. Jane Doe", "Dr. Robert Chen", "Dr. Maria Garcia"),
    address = c("123 University Ave", "456 Community St", "789 Regional Blvd"),
    phone = c("555-1000", "555-2000", "555-3000"),
    active = c(1, 1, 0),  # Third site not yet activated
    activation_date = as.Date(c("2024-01-15", "2024-02-01", NA)),
    stringsAsFactors = FALSE
  )

  return(list(
    users = users_schema,
    roles = roles_schema,
    sites = sites_schema
  ))
}

# Example of creating Google Sheets programmatically
create_auth_sheet_programmatically <- function(auth_data, sheet_name) {

  # Authenticate with Google Sheets
  gs4_auth()

  # Create new sheet
  new_sheet <- gs4_create(name = sheet_name)

  # Add each tab with data
  sheet_write(auth_data$users, ss = new_sheet, sheet = "users")
  sheet_write(auth_data$roles, ss = new_sheet, sheet = "roles")
  sheet_write(auth_data$sites, ss = new_sheet, sheet = "sites")

  message("Created authentication sheet: ", sheet_name)
  return(new_sheet$spreadsheet_id)
}
```

### Data Dictionary Sheet Design

The data dictionary is where you define your clinical forms. Here's how to design sophisticated form structures:

```r
# Advanced data dictionary design patterns
create_clinical_forms_dd <- function() {

  # Forms overview - defines the study structure
  forms_overview <- data.frame(
    workingname = c("eligibility", "demographics", "medical_history", "baseline_labs",
                   "ecg_reading", "adverse_events", "concomitant_meds", "study_completion"),
    fullname = c("Eligibility Assessment", "Demographics", "Medical History", "Baseline Laboratory",
                "ECG Reading", "Adverse Events", "Concomitant Medications", "Study Completion"),
    visits = c("screening", "baseline", "baseline", "baseline,week4,week12",
               "baseline,week12", "baseline,week4,week8,week12", "baseline,week4,week8,week12", "week12"),
    category = c("screening", "baseline", "baseline", "safety", "efficacy", "safety", "safety", "completion"),
    required = c(1, 1, 1, 1, 0, 0, 0, 1),
    stringsAsFactors = FALSE
  )

  # Example: Demographics form with advanced field types
  demographics_form <- data.frame(
    field = c("subject_id", "initials", "birth_date", "age", "age_units", "gender", "race",
             "ethnicity", "weight", "height", "bmi", "education_years", "insurance_type"),
    prompt = c("Subject ID", "Initials", "Date of Birth", "Age", "Age Units", "Gender", "Race",
              "Ethnicity", "Weight (kg)", "Height (cm)", "BMI", "Years of Education", "Insurance Type"),
    type = c("C", "C", "D", "N", "L", "L", "L", "L", "N", "N", "N", "N", "L"),
    layout = c("text", "text", "date", "numeric", "select", "radio", "select", "radio",
               "numeric", "numeric", "numeric", "numeric", "select"),
    req = c(1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0),

    # Advanced validation and options
    values = c("", "", "", "", "years:months", "Male:Female:Other",
              "White:Black:Asian:Native American:Pacific Islander:Other",
              "Hispanic:Non-Hispanic", "", "", "", "",
              "Private:Medicare:Medicaid:Uninsured:Other"),

    # Conditional display logic
    cond = c("", "", "", "", "age_units=='months'", "", "", "", "", "", "", "", ""),

    # Custom validation rules
    valid = c("nchar(subject_id)==8", "nchar(initials)==3", "birth_date <= today()",
             "age >= 18 && age <= 85", "", "", "", "", "weight > 30 && weight < 200",
             "height > 120 && height < 220", "", "education_years >= 0 && education_years <= 25", ""),

    # Custom validation messages
    validmsg = c("Subject ID must be 8 characters", "Enter 3 initials",
                "Birth date cannot be future", "Age must be 18-85 years", "", "", "", "",
                "Weight must be 30-200 kg", "Height must be 120-220 cm", "",
                "Education 0-25 years", ""),

    # Field order and sections
    section = c("identification", "identification", "demographics", "demographics", "demographics",
               "demographics", "demographics", "demographics", "physical", "physical", "physical",
               "background", "background"),
    field_order = 1:13,

    stringsAsFactors = FALSE
  )

  # Example: Adverse events form with complex logic
  adverse_events_form <- data.frame(
    field = c("ae_number", "ae_term", "ae_start_date", "ae_end_date", "ae_ongoing",
             "ae_severity", "ae_relationship", "ae_action_taken", "ae_outcome", "ae_serious",
             "sae_death", "sae_life_threatening", "sae_hospitalization", "sae_disability",
             "sae_congenital", "sae_other_important", "ae_narrative"),
    prompt = c("AE Number", "Adverse Event Term", "Start Date", "End Date", "Ongoing?",
              "Severity", "Relationship to Study Drug", "Action Taken", "Outcome", "Serious AE?",
              "Death", "Life Threatening", "Hospitalization", "Disability/Incapacity",
              "Congenital Anomaly", "Other Important Medical Event", "Narrative Description"),
    type = c("N", "C", "D", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "C"),
    layout = c("numeric", "text", "date", "date", "radio", "radio", "radio", "select", "select",
              "radio", "checkbox", "checkbox", "checkbox", "checkbox", "checkbox", "checkbox", "textarea"),
    req = c(1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1),

    values = c("", "", "", "", "Yes:No", "Mild:Moderate:Severe", "Unrelated:Unlikely:Possible:Probable:Definite",
              "None:Dose Reduced:Dose Interrupted:Drug Withdrawn:Other",
              "Recovered:Recovering:Not Recovered:Recovered with Sequelae:Fatal:Unknown",
              "Yes:No", "", "", "", "", "", "", ""),

    # Complex conditional logic for serious AE fields
    cond = c("", "", "", "ae_ongoing=='No'", "", "", "", "", "", "",
            "ae_serious=='Yes'", "ae_serious=='Yes'", "ae_serious=='Yes'", "ae_serious=='Yes'",
            "ae_serious=='Yes'", "ae_serious=='Yes'", ""),

    valid = c("ae_number > 0", "", "ae_start_date <= today()", "ae_end_date >= ae_start_date",
             "", "", "", "", "", "", "", "", "", "", "", "", "nchar(ae_narrative) >= 10"),

    validmsg = c("AE number must be positive", "", "Start date cannot be future",
                "End date must be after start date", "", "", "", "", "", "", "", "", "", "", "", "",
                "Narrative must be at least 10 characters"),

    stringsAsFactors = FALSE
  )

  return(list(
    forms_overview = forms_overview,
    demographics = demographics_form,
    adverse_events = adverse_events_form
  ))
}
```

---

## Customizing and Extending the System

### Custom Validation Rules

You can implement sophisticated validation logic beyond the built-in rules:

```r
# Advanced validation patterns
custom_validation_patterns <- list(

  # Date range validation
  date_range_validation = function(start_date_field, end_date_field, max_duration_days = NULL) {
    validation_rule <- paste0(
      start_date_field, " <= ", end_date_field,
      if (!is.null(max_duration_days)) {
        paste0(" && as.numeric(", end_date_field, " - ", start_date_field, ") <= ", max_duration_days)
      }
    )

    validation_message <- paste0(
      "End date must be after start date",
      if (!is.null(max_duration_days)) {
        paste0(" and within ", max_duration_days, " days")
      }
    )

    return(list(rule = validation_rule, message = validation_message))
  },

  # Cross-field consistency validation
  consistency_validation = function(field1, field2, relationship = "equal") {
    rule <- switch(relationship,
      "equal" = paste0(field1, " == ", field2),
      "greater" = paste0(field1, " > ", field2),
      "sum_to_100" = paste0(field1, " + ", field2, " == 100"),
      stop("Unknown relationship: ", relationship)
    )

    message <- switch(relationship,
      "equal" = paste(field1, "must equal", field2),
      "greater" = paste(field1, "must be greater than", field2),
      "sum_to_100" = paste(field1, "and", field2, "must sum to 100"),
      "Validation failed"
    )

    return(list(rule = rule, message = message))
  },

  # Medical reference range validation
  medical_range_validation = function(field, test_type) {
    # Define normal ranges for common lab tests
    normal_ranges <- list(
      "hemoglobin_male" = list(min = 13.5, max = 17.5, unit = "g/dL"),
      "hemoglobin_female" = list(min = 12.0, max = 15.5, unit = "g/dL"),
      "creatinine_male" = list(min = 0.7, max = 1.3, unit = "mg/dL"),
      "creatinine_female" = list(min = 0.6, max = 1.1, unit = "mg/dL"),
      "glucose_fasting" = list(min = 70, max = 100, unit = "mg/dL"),
      "systolic_bp" = list(min = 90, max = 180, unit = "mmHg"),
      "diastolic_bp" = list(min = 60, max = 110, unit = "mmHg")
    )

    range_info <- normal_ranges[[test_type]]
    if (is.null(range_info)) {
      stop("Unknown test type: ", test_type)
    }

    rule <- paste0(field, " >= ", range_info$min, " && ", field, " <= ", range_info$max)
    message <- paste0(field, " must be ", range_info$min, "-", range_info$max, " ", range_info$unit)

    return(list(rule = rule, message = message))
  }
)

# Example of implementing custom validation in Google Sheets
implement_custom_validation <- function() {

  # Example: ECG form with complex validation
  ecg_validation_example <- data.frame(
    field = c("heart_rate", "pr_interval", "qrs_duration", "qt_interval", "qtc_calculated"),

    # Use custom validation functions
    valid = c(
      # Heart rate: 40-200 bpm is physiologically reasonable
      "heart_rate >= 40 && heart_rate <= 200",

      # PR interval: 120-200 ms is normal
      "pr_interval >= 120 && pr_interval <= 300",

      # QRS duration: <120 ms is normal
      "qrs_duration >= 60 && qrs_duration <= 200",

      # QT interval: depends on heart rate, basic range check
      "qt_interval >= 300 && qt_interval <= 500",

      # QTc: calculated field, should be reasonable
      "qtc_calculated >= 350 && qtc_calculated <= 500"
    ),

    validmsg = c(
      "Heart rate must be 40-200 bpm",
      "PR interval must be 120-300 ms",
      "QRS duration must be 60-200 ms",
      "QT interval must be 300-500 ms",
      "QTc must be 350-500 ms"
    ),

    stringsAsFactors = FALSE
  )

  return(ecg_validation_example)
}
```

### Custom Form Layouts and UI Components

Advanced users can create custom form layouts and specialized UI components:

```r
# Custom form layout generators
custom_form_layouts <- list(

  # Create tabbed form layout for complex forms
  create_tabbed_form = function(form_definition, tab_field = "section") {

    # Group fields by section/tab
    form_tabs <- split(form_definition, form_definition[[tab_field]])

    # Generate tab structure
    tab_ui_code <- c("navlistPanel(")

    for (tab_name in names(form_tabs)) {
      tab_fields <- form_tabs[[tab_name]]

      tab_ui_code <- c(tab_ui_code, paste0('tabPanel("', tab_name, '",'))

      # Add fields for this tab
      for (i in 1:nrow(tab_fields)) {
        field_ui <- generate_field_ui(tab_fields[i, ])
        tab_ui_code <- c(tab_ui_code, paste0("  ", field_ui, ","))
      }

      # Remove trailing comma and close tab
      tab_ui_code[length(tab_ui_code)] <- gsub(",$", "", tab_ui_code[length(tab_ui_code)])
      tab_ui_code <- c(tab_ui_code, "),")
    }

    # Remove trailing comma and close navlistPanel
    tab_ui_code[length(tab_ui_code)] <- gsub(",$", "", tab_ui_code[length(tab_ui_code)])
    tab_ui_code <- c(tab_ui_code, ")")

    return(paste(tab_ui_code, collapse = "\n"))
  },

  # Create matrix input for repeated measures
  create_matrix_input = function(field_prefix, measures, timepoints) {

    matrix_code <- c(paste0("# Matrix input for ", field_prefix))
    matrix_code <- c(matrix_code, "fluidRow(")

    # Create header row
    header_row <- paste0("column(2, strong('Measure')),")
    for (tp in timepoints) {
      header_row <- paste0(header_row, " column(2, strong('", tp, "')),")
    }
    matrix_code <- c(matrix_code, header_row)
    matrix_code <- c(matrix_code, "),")

    # Create input rows
    for (measure in measures) {
      input_row <- paste0("fluidRow(")
      input_row <- paste0(input_row, "column(2, strong('", measure, "')),")

      for (tp in timepoints) {
        field_id <- paste(field_prefix, measure, tp, sep = "_")
        input_row <- paste0(input_row,
                           "column(2, numericInput('", field_id, "', '', value = NA)),")
      }

      input_row <- gsub(",$", "", input_row)  # Remove trailing comma
      input_row <- paste0(input_row, "),")
      matrix_code <- c(matrix_code, input_row)
    }

    matrix_code[length(matrix_code)] <- gsub(",$", "", matrix_code[length(matrix_code)])

    return(paste(matrix_code, collapse = "\n"))
  },

  # Create dynamic field groups
  create_dynamic_field_group = function(base_fields, max_repeats = 5) {

    dynamic_code <- c()
    dynamic_code <- c(dynamic_code, "uiOutput('dynamic_field_group'),")
    dynamic_code <- c(dynamic_code, "actionButton('add_field_group', 'Add Another', class = 'btn-success'),")
    dynamic_code <- c(dynamic_code, "actionButton('remove_field_group', 'Remove Last', class = 'btn-warning')")

    # Server logic for dynamic fields (this would go in server function)
    server_logic <- paste0("
    output$dynamic_field_group <- renderUI({
      n_groups <- reactiveVal(1)

      observeEvent(input$add_field_group, {
        if (n_groups() < ", max_repeats, ") {
          n_groups(n_groups() + 1)
        }
      })

      observeEvent(input$remove_field_group, {
        if (n_groups() > 1) {
          n_groups(n_groups() - 1)
        }
      })

      lapply(1:n_groups(), function(i) {
        wellPanel(
          h4(paste('Group', i)),
          # Generate fields for each group
        )
      })
    })")

    return(list(ui = paste(dynamic_code, collapse = "\n"), server = server_logic))
  }
)

# Example of custom field UI generation
generate_specialized_field_ui <- function(field_definition) {

  field_type <- field_definition$type
  field_layout <- field_definition$layout
  field_name <- field_definition$field
  field_prompt <- field_definition$prompt

  # Handle specialized field types
  if (field_layout == "date_range") {
    # Create date range input with start and end dates
    ui_code <- paste0(
      "dateRangeInput('", field_name, "', '", field_prompt, "',
       start = NULL, end = NULL, format = 'yyyy-mm-dd')"
    )

  } else if (field_layout == "slider_range") {
    # Create range slider
    ui_code <- paste0(
      "sliderInput('", field_name, "', '", field_prompt, "',
       min = 0, max = 100, value = c(25, 75))"
    )

  } else if (field_layout == "file_upload") {
    # Create file upload with restrictions
    ui_code <- paste0(
      "fileInput('", field_name, "', '", field_prompt, "',
       accept = c('.pdf', '.jpg', '.png'), multiple = FALSE)"
    )

  } else if (field_layout == "color_picker") {
    # Create color picker input
    ui_code <- paste0(
      "colourInput('", field_name, "', '", field_prompt, "',
       value = '#FFFFFF')"
    )

  } else {
    # Default to standard field generation
    ui_code <- generate_standard_field_ui(field_definition)
  }

  return(ui_code)
}
```

### Database Customization and Queries

Intermediate users often need to perform custom database operations:

```r
# Advanced database operations
advanced_db_operations <- list(

  # Create custom database views for analysis
  create_analysis_views = function(db_connection) {

    # View for subject enrollment status
    enrollment_view_sql <- "
    CREATE VIEW v_subject_enrollment AS
    SELECT
      s.subject_id,
      s.site_id,
      s.randomization_date,
      s.treatment_group,
      COUNT(DISTINCT v.visit_code) as completed_visits,
      MAX(v.visit_date) as last_visit_date,
      CASE
        WHEN s.study_status = 'completed' THEN 'Completed'
        WHEN s.study_status = 'withdrawn' THEN 'Withdrawn'
        WHEN DATE('now') > DATE(s.randomization_date, '+84 days') AND COUNT(DISTINCT v.visit_code) < 4 THEN 'At Risk'
        ELSE 'Active'
      END as enrollment_status
    FROM subjects s
    LEFT JOIN visits v ON s.subject_id = v.subject_id
    GROUP BY s.subject_id, s.site_id, s.randomization_date, s.treatment_group"

    DBI::dbExecute(db_connection, enrollment_view_sql)

    # View for data quality metrics
    quality_view_sql <- "
    CREATE VIEW v_data_quality AS
    SELECT
      f.form_name,
      COUNT(*) as total_records,
      SUM(CASE WHEN f.completion_status = 'complete' THEN 1 ELSE 0 END) as complete_records,
      SUM(CASE WHEN f.has_queries = 1 THEN 1 ELSE 0 END) as records_with_queries,
      AVG(f.data_quality_score) as avg_quality_score,
      COUNT(DISTINCT f.subject_id) as subjects_with_data
    FROM form_status f
    GROUP BY f.form_name"

    DBI::dbExecute(db_connection, quality_view_sql)

    message("Created analysis views successfully")
  },

  # Custom data extraction with complex joins
  extract_analysis_dataset = function(db_connection, forms_to_include, visit_subset = NULL) {

    # Build dynamic query based on requested forms
    base_query <- "
    SELECT
      s.subject_id,
      s.site_id,
      s.treatment_group,
      s.randomization_date"

    from_clause <- "FROM subjects s"
    where_conditions <- c("s.active = 1")

    for (form_name in forms_to_include) {
      table_name <- paste0("data_", form_name)
      alias <- substr(form_name, 1, 3)  # Create short alias

      # Add fields from this form (you'd customize this based on actual fields)
      form_fields <- get_form_fields(db_connection, form_name)
      for (field in form_fields) {
        base_query <- paste0(base_query, ",\n  ", alias, ".", field)
      }

      # Add join
      from_clause <- paste0(from_clause,
                           "\nLEFT JOIN ", table_name, " ", alias,
                           " ON s.subject_id = ", alias, ".subject_id")

      # Add visit filter if specified
      if (!is.null(visit_subset)) {
        where_conditions <- c(where_conditions,
                             paste0(alias, ".visit_code IN ('",
                                   paste(visit_subset, collapse = "','"), "')"))
      }
    }

    # Combine query parts
    full_query <- paste(base_query, from_clause)
    if (length(where_conditions) > 0) {
      full_query <- paste(full_query, "WHERE", paste(where_conditions, collapse = " AND "))
    }

    # Execute query
    result_data <- DBI::dbGetQuery(db_connection, full_query)

    return(result_data)
  },

  # Data quality assessment functions
  assess_data_completeness = function(db_connection, form_name) {

    # Get form definition
    form_fields <- get_form_fields(db_connection, form_name)
    required_fields <- get_required_fields(db_connection, form_name)

    # Calculate completeness for each field
    completeness_results <- list()

    for (field in form_fields) {
      completeness_query <- paste0("
        SELECT
          '", field, "' as field_name,
          COUNT(*) as total_records,
          COUNT(", field, ") as non_null_records,
          COUNT(CASE WHEN ", field, " != '' THEN 1 END) as non_empty_records,
          ROUND(100.0 * COUNT(", field, ") / COUNT(*), 2) as completeness_pct
        FROM data_", form_name)

      field_completeness <- DBI::dbGetQuery(db_connection, completeness_query)
      completeness_results[[field]] <- field_completeness
    }

    # Combine results
    completeness_df <- do.call(rbind, completeness_results)

    # Add required field indicator
    completeness_df$required <- completeness_df$field_name %in% required_fields

    return(completeness_df)
  }
)

# Example: Custom data export function
create_custom_export <- function(db_path, export_spec) {

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con))

  # Export specification example:
  # export_spec <- list(
  #   forms = c("demographics", "adverse_events"),
  #   visits = c("baseline", "week12"),
  #   subjects = NULL,  # NULL = all subjects
  #   format = "wide",  # "wide" or "long"
  #   deidentify = TRUE,
  #   output_file = "study_data_export.csv"
  # )

  if (export_spec$format == "wide") {
    # Wide format: one row per subject
    export_data <- advanced_db_operations$extract_analysis_dataset(
      con, export_spec$forms, export_spec$visits
    )
  } else {
    # Long format: one row per visit per subject
    export_data <- extract_long_format_data(con, export_spec)
  }

  # Apply deidentification if requested
  if (export_spec$deidentify) {
    export_data <- deidentify_export_data(export_data)
  }

  # Write to file
  write.csv(export_data, export_spec$output_file, row.names = FALSE, na = "")

  message("Export completed: ", export_spec$output_file)
  message("Records exported: ", nrow(export_data))

  return(export_data)
}
```

---

## Integration with Statistical Analysis

### Preparing Data for Analysis

Intermediate users often need to prepare clinical trial data for statistical analysis:

```r
# Statistical analysis preparation tools
statistical_analysis_prep <- list(

  # Create analysis-ready datasets
  prepare_efficacy_dataset = function(db_path, primary_endpoint, analysis_visits) {

    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(con))

    # Extract primary endpoint data
    efficacy_query <- paste0("
      SELECT
        s.subject_id,
        s.treatment_group,
        s.randomization_date,
        s.site_id,
        ", primary_endpoint, "_baseline.visit_date as baseline_date,
        ", primary_endpoint, "_baseline.", primary_endpoint, " as baseline_value")

    # Add follow-up visits
    for (visit in analysis_visits) {
      efficacy_query <- paste0(efficacy_query, ",\n        ",
                              primary_endpoint, "_", visit, ".visit_date as ", visit, "_date,\n        ",
                              primary_endpoint, "_", visit, ".", primary_endpoint, " as ", visit, "_value")
    }

    efficacy_query <- paste0(efficacy_query, "
      FROM subjects s
      LEFT JOIN data_", primary_endpoint, " ", primary_endpoint, "_baseline
        ON s.subject_id = ", primary_endpoint, "_baseline.subject_id
        AND ", primary_endpoint, "_baseline.visit_code = 'baseline'")

    # Add joins for follow-up visits
    for (visit in analysis_visits) {
      efficacy_query <- paste0(efficacy_query, "
      LEFT JOIN data_", primary_endpoint, " ", primary_endpoint, "_", visit, "
        ON s.subject_id = ", primary_endpoint, "_", visit, ".subject_id
        AND ", primary_endpoint, "_", visit, ".visit_code = '", visit, "'")
    }

    efficacy_data <- DBI::dbGetQuery(con, efficacy_query)

    # Calculate change scores
    for (visit in analysis_visits) {
      baseline_col <- "baseline_value"
      visit_col <- paste0(visit, "_value")
      change_col <- paste0("change_", visit)

      efficacy_data[[change_col]] <- efficacy_data[[visit_col]] - efficacy_data[[baseline_col]]
    }

    # Add analysis flags
    efficacy_data$itt_population <- !is.na(efficacy_data$baseline_value)
    efficacy_data$pp_population <- efficacy_data$itt_population &
                                   !is.na(efficacy_data[[paste0(analysis_visits[length(analysis_visits)], "_value")]])

    return(efficacy_data)
  },

  # Create safety dataset with exposure calculations
  prepare_safety_dataset = function(db_path) {

    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(con))

    # Get subject exposure data
    exposure_query <- "
      SELECT
        s.subject_id,
        s.treatment_group,
        s.randomization_date,
        s.study_completion_date,
        CASE
          WHEN s.study_completion_date IS NOT NULL
          THEN julianday(s.study_completion_date) - julianday(s.randomization_date)
          ELSE julianday('now') - julianday(s.randomization_date)
        END as exposure_days,
        s.study_status
      FROM subjects s
      WHERE s.randomized = 1"

    safety_dataset <- DBI::dbGetQuery(con, exposure_query)

    # Add adverse event counts
    ae_summary_query <- "
      SELECT
        subject_id,
        COUNT(*) as total_aes,
        SUM(CASE WHEN ae_serious = 'Yes' THEN 1 ELSE 0 END) as serious_aes,
        SUM(CASE WHEN ae_severity = 'Severe' THEN 1 ELSE 0 END) as severe_aes,
        SUM(CASE WHEN ae_relationship IN ('Probable', 'Definite') THEN 1 ELSE 0 END) as related_aes
      FROM data_adverse_events
      GROUP BY subject_id"

    ae_summary <- DBI::dbGetQuery(con, ae_summary_query)

    # Merge safety and AE data
    safety_dataset <- merge(safety_dataset, ae_summary, by = "subject_id", all.x = TRUE)

    # Replace NA with 0 for AE counts
    ae_columns <- c("total_aes", "serious_aes", "severe_aes", "related_aes")
    safety_dataset[ae_columns] <- lapply(safety_dataset[ae_columns], function(x) ifelse(is.na(x), 0, x))

    # Calculate exposure-adjusted rates (per 100 patient-years)
    safety_dataset$exposure_years <- safety_dataset$exposure_days / 365.25
    safety_dataset$ae_rate_per_100py <- (safety_dataset$total_aes / safety_dataset$exposure_years) * 100

    return(safety_dataset)
  },

  # Generate CONSORT flow diagram data
  generate_consort_data = function(db_path) {

    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(con))

    consort_data <- list()

    # Screening numbers
    consort_data$screened <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM data_screening")$n

    # Screening failures by reason
    screen_fail_query <- "
      SELECT
        CASE
          WHEN inclusion_age = 'No' THEN 'Age criteria'
          WHEN inclusion_consent = 'No' THEN 'Consent issues'
          WHEN exclusion_pregnancy = 'Yes' THEN 'Pregnancy'
          WHEN exclusion_medication = 'Yes' THEN 'Concomitant medications'
          ELSE 'Other'
        END as failure_reason,
        COUNT(*) as n
      FROM data_screening
      WHERE overall_eligible = 'Not Eligible'
      GROUP BY failure_reason"

    consort_data$screen_failures <- DBI::dbGetQuery(con, screen_fail_query)

    # Randomization numbers
    consort_data$randomized <- DBI::dbGetQuery(con,
      "SELECT COUNT(*) as n FROM subjects WHERE randomized = 1")$n

    # Randomization by treatment group
    consort_data$randomized_by_group <- DBI::dbGetQuery(con,
      "SELECT treatment_group, COUNT(*) as n FROM subjects WHERE randomized = 1 GROUP BY treatment_group")

    # Completion and discontinuation
    consort_data$completed <- DBI::dbGetQuery(con,
      "SELECT treatment_group, COUNT(*) as n FROM subjects WHERE study_status = 'completed' GROUP BY treatment_group")

    consort_data$discontinued <- DBI::dbGetQuery(con,
      "SELECT treatment_group, discontinuation_reason, COUNT(*) as n
       FROM subjects WHERE study_status = 'withdrawn'
       GROUP BY treatment_group, discontinuation_reason")

    return(consort_data)
  }
)

# Example: Automated statistical analysis pipeline
run_primary_analysis <- function(db_path, analysis_config) {

  # Load required packages
  required_packages <- c("dplyr", "ggplot2", "broom", "emmeans")
  missing_packages <- setdiff(required_packages, rownames(installed.packages()))
  if (length(missing_packages) > 0) {
    install.packages(missing_packages)
  }
  sapply(required_packages, library, character.only = TRUE)

  # Prepare efficacy dataset
  efficacy_data <- statistical_analysis_prep$prepare_efficacy_dataset(
    db_path,
    analysis_config$primary_endpoint,
    analysis_config$analysis_visits
  )

  # Primary efficacy analysis
  primary_visit <- analysis_config$analysis_visits[length(analysis_config$analysis_visits)]
  change_variable <- paste0("change_", primary_visit)

  # ANCOVA model
  model_formula <- as.formula(paste(change_variable, "~ treatment_group + baseline_value + site_id"))
  primary_model <- lm(model_formula, data = efficacy_data, subset = itt_population)

  # Extract results
  model_summary <- broom::tidy(primary_model)
  treatment_effect <- model_summary[model_summary$term == "treatment_groupActive", ]

  # Generate results summary
  results_summary <- list(
    primary_analysis = list(
      endpoint = analysis_config$primary_endpoint,
      visit = primary_visit,
      model = "ANCOVA",
      treatment_effect = treatment_effect$estimate,
      standard_error = treatment_effect$std.error,
      p_value = treatment_effect$p.value,
      ci_lower = treatment_effect$estimate - 1.96 * treatment_effect$std.error,
      ci_upper = treatment_effect$estimate + 1.96 * treatment_effect$std.error
    ),
    sample_size = list(
      itt = sum(efficacy_data$itt_population, na.rm = TRUE),
      pp = sum(efficacy_data$pp_population, na.rm = TRUE)
    ),
    model_diagnostics = list(
      residuals_normal = shapiro.test(residuals(primary_model))$p.value > 0.05,
      r_squared = summary(primary_model)$r.squared
    )
  )

  return(results_summary)
}
```

---

## Troubleshooting and Best Practices

### Common Issues and Solutions

```r
# Troubleshooting toolkit for intermediate users
troubleshooting_toolkit <- list(

  # Diagnose Google Sheets connection issues
  diagnose_gsheets_issues = function(sheet_name) {

    cat("🔍 Diagnosing Google Sheets connection...\n")

    # Check authentication
    tryCatch({
      gs4_user()
      cat("✅ Google Sheets authentication: OK\n")
    }, error = function(e) {
      cat("❌ Google Sheets authentication: FAILED\n")
      cat("   Try running: gs4_auth()\n")
      return(FALSE)
    })

    # Check sheet access
    tryCatch({
      sheet_info <- gs4_get(sheet_name)
      cat("✅ Sheet access: OK\n")
      cat("   Sheet ID:", sheet_info$spreadsheet_id, "\n")
    }, error = function(e) {
      cat("❌ Sheet access: FAILED\n")
      cat("   Error:", e$message, "\n")
      cat("   Check sheet name and permissions\n")
      return(FALSE)
    })

    # Check sheet structure
    tryCatch({
      sheet_names <- sheet_names(sheet_name)
      cat("✅ Sheet structure: OK\n")
      cat("   Available tabs:", paste(sheet_names, collapse = ", "), "\n")

      # Check for required tabs
      required_tabs <- c("users", "roles", "sites")  # Adjust based on sheet type
      missing_tabs <- setdiff(required_tabs, sheet_names)
      if (length(missing_tabs) > 0) {
        cat("⚠️  Missing recommended tabs:", paste(missing_tabs, collapse = ", "), "\n")
      }

    }, error = function(e) {
      cat("❌ Sheet structure check: FAILED\n")
      cat("   Error:", e$message, "\n")
      return(FALSE)
    })

    return(TRUE)
  },

  # Validate data dictionary structure
  validate_data_dictionary = function(dd_data) {

    cat("🔍 Validating data dictionary structure...\n")
    validation_results <- list()

    # Check forms overview
    if (!"forms_overview" %in% names(dd_data)) {
      validation_results$forms_overview <- "MISSING - forms_overview not found"
    } else {
      fo <- dd_data$forms_overview
      required_cols <- c("workingname", "fullname", "visits")
      missing_cols <- setdiff(required_cols, names(fo))

      if (length(missing_cols) > 0) {
        validation_results$forms_overview <- paste("MISSING COLUMNS:", paste(missing_cols, collapse = ", "))
      } else {
        validation_results$forms_overview <- "OK"
      }
    }

    # Check form definitions
    form_issues <- c()
    if ("form_definitions" %in% names(dd_data)) {
      for (form_name in names(dd_data$form_definitions)) {
        form_def <- dd_data$form_definitions[[form_name]]

        # Check required columns
        required_form_cols <- c("field", "prompt", "type", "layout")
        missing_form_cols <- setdiff(required_form_cols, names(form_def))

        if (length(missing_form_cols) > 0) {
          form_issues <- c(form_issues, paste0(form_name, ": missing ", paste(missing_form_cols, collapse = ", ")))
        }

        # Check for empty fields
        if (any(is.na(form_def$field) | form_def$field == "")) {
          form_issues <- c(form_issues, paste0(form_name, ": contains empty field names"))
        }

        # Check for duplicate field names
        if (any(duplicated(form_def$field))) {
          form_issues <- c(form_issues, paste0(form_name, ": contains duplicate field names"))
        }
      }
    } else {
      form_issues <- c("No form definitions found")
    }

    validation_results$form_definitions <- if (length(form_issues) == 0) "OK" else form_issues

    # Print results
    for (component in names(validation_results)) {
      result <- validation_results[[component]]
      if (result == "OK") {
        cat("✅", component, ": OK\n")
      } else {
        cat("❌", component, ":\n")
        if (is.character(result) && length(result) > 1) {
          for (issue in result) {
            cat("   -", issue, "\n")
          }
        } else {
          cat("   ", result, "\n")
        }
      }
    }

    return(validation_results)
  },

  # Database integrity checker
  check_database_integrity = function(db_path) {

    cat("🔍 Checking database integrity...\n")

    if (!file.exists(db_path)) {
      cat("❌ Database file not found:", db_path, "\n")
      return(FALSE)
    }

    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(con))

    integrity_results <- list()

    # Check required tables
    tables <- DBI::dbListTables(con)
    required_tables <- c("edc_users", "edc_forms", "edc_fields")
    missing_tables <- setdiff(required_tables, tables)

    if (length(missing_tables) > 0) {
      integrity_results$tables <- paste("Missing tables:", paste(missing_tables, collapse = ", "))
    } else {
      integrity_results$tables <- "OK"
    }

    # Check user data
    tryCatch({
      users <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM edc_users WHERE active = 1")
      if (users$n == 0) {
        integrity_results$users <- "No active users found"
      } else {
        integrity_results$users <- paste("OK -", users$n, "active users")
      }
    }, error = function(e) {
      integrity_results$users <- paste("Error:", e$message)
    })

    # Check form data
    tryCatch({
      forms <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM edc_forms")
      if (forms$n == 0) {
        integrity_results$forms <- "No forms defined"
      } else {
        integrity_results$forms <- paste("OK -", forms$n, "forms defined")
      }
    }, error = function(e) {
      integrity_results$forms <- paste("Error:", e$message)
    })

    # Print results
    for (component in names(integrity_results)) {
      result <- integrity_results[[component]]
      if (grepl("^OK", result)) {
        cat("✅", component, ":", result, "\n")
      } else {
        cat("❌", component, ":", result, "\n")
      }
    }

    return(integrity_results)
  },

  # Performance optimization suggestions
  optimize_performance = function(db_path) {

    cat("🚀 Analyzing performance optimization opportunities...\n")

    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(DBI::dbDisconnect(con))

    optimizations <- list()

    # Check for missing indexes
    tables_with_subject_id <- DBI::dbGetQuery(con, "
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND sql LIKE '%subject_id%'")$name

    for (table in tables_with_subject_id) {
      index_exists <- DBI::dbGetQuery(con, paste0("
        SELECT COUNT(*) as n FROM sqlite_master
        WHERE type = 'index' AND tbl_name = '", table, "'
        AND sql LIKE '%subject_id%'"))$n > 0

      if (!index_exists) {
        optimizations$missing_indexes <- c(optimizations$missing_indexes,
                                         paste0("CREATE INDEX idx_", table, "_subject_id ON ", table, "(subject_id)"))
      }
    }

    # Check database size and suggest cleanup
    db_size <- file.size(db_path) / 1024 / 1024  # MB
    optimizations$database_size <- paste0("Current size: ", round(db_size, 2), " MB")

    if (db_size > 100) {
      optimizations$size_suggestions <- c(
        "Consider archiving old audit logs",
        "Implement data retention policies",
        "Use VACUUM to reclaim space"
      )
    }

    # Suggest connection pooling for high-load scenarios
    optimizations$connection_pooling <- "Consider using pool::dbPool() for multi-user environments"

    # Print recommendations
    if (length(optimizations$missing_indexes) > 0) {
      cat("📊 Missing indexes found. Run these commands:\n")
      for (index_sql in optimizations$missing_indexes) {
        cat("   ", index_sql, "\n")
      }
    }

    cat("💾", optimizations$database_size, "\n")

    if ("size_suggestions" %in% names(optimizations)) {
      cat("💡 Size optimization suggestions:\n")
      for (suggestion in optimizations$size_suggestions) {
        cat("   -", suggestion, "\n")
      }
    }

    return(optimizations)
  }
)

# Usage examples for troubleshooting
run_troubleshooting_check <- function() {
  cat("=== ZZedc System Health Check ===\n\n")

  # Check Google Sheets access
  troubleshooting_toolkit$diagnose_gsheets_issues("your_sheet_name")
  cat("\n")

  # Check database integrity
  troubleshooting_toolkit$check_database_integrity("data/your_study.db")
  cat("\n")

  # Performance check
  troubleshooting_toolkit$optimize_performance("data/your_study.db")
}
```

### Best Practices for Intermediate Users

```r
# Best practices compilation
best_practices <- list(

  # Project organization
  project_structure = list(
    recommended_structure = "
    my_clinical_study/
    ├── data/                    # Database files
    │   ├── study.db
    │   └── backups/
    ├── forms_generated/         # Auto-generated forms
    ├── scripts/                 # Custom analysis scripts
    │   ├── setup_study.R
    │   ├── analysis_primary.R
    │   └── reports/
    ├── documentation/           # Study documentation
    │   ├── protocol.pdf
    │   ├── sap.pdf
    │   └── data_dictionary.xlsx
    ├── config/                  # Configuration files
    │   ├── config.yml
    │   └── environment.R
    └── README.md               # Project overview
    ",

    setup_recommendations = c(
      "Use version control (git) for all R scripts",
      "Keep Google Sheets and database files backed up regularly",
      "Document custom functions and modifications",
      "Use relative paths in scripts for portability",
      "Implement error handling in custom functions"
    )
  ),

  # Code organization principles
  coding_standards = list(
    function_design = c(
      "Write small, focused functions that do one thing well",
      "Use descriptive function and variable names",
      "Include parameter validation and error handling",
      "Document functions with roxygen2 comments",
      "Return consistent data structures"
    ),

    example_function_template = "
    #' Brief function description
    #'
    #' Longer description of what the function does, its purpose,
    #' and any important details about its behavior.
    #'
    #' @param param1 Description of first parameter
    #' @param param2 Description of second parameter
    #' @return Description of what the function returns
    #' @examples
    #' \\dontrun{
    #' result <- my_function(param1 = 'value', param2 = 42)
    #' }
    #' @export
    my_function <- function(param1, param2 = NULL) {

      # Parameter validation
      if (!is.character(param1)) {
        stop('param1 must be a character string')
      }

      # Function logic
      tryCatch({
        # Main function code here
        result <- perform_operation(param1, param2)

        return(result)

      }, error = function(e) {
        stop('Function failed: ', e$message)
      })
    }
    "
  ),

  # Security and compliance
  security_practices = list(
    data_protection = c(
      "Never store passwords in plain text in scripts",
      "Use environment variables for sensitive configuration",
      "Implement proper access controls and user permissions",
      "Regularly backup database files with encryption",
      "Audit user access and data modifications"
    ),

    google_sheets_security = c(
      "Use specific Google account for study access",
      "Implement sheet-level permissions appropriately",
      "Regularly review sheet access and sharing settings",
      "Use service accounts for automated processes",
      "Monitor sheet modification history"
    )
  ),

  # Performance optimization
  performance_tips = list(
    database_optimization = c(
      "Create indexes on frequently queried fields",
      "Use parameterized queries to prevent SQL injection",
      "Implement connection pooling for multi-user systems",
      "Regular database maintenance (VACUUM, ANALYZE)",
      "Archive old data to keep active database size manageable"
    ),

    r_code_optimization = c(
      "Use vectorized operations instead of loops when possible",
      "Cache expensive computations using memoization",
      "Use data.table or dplyr for efficient data manipulation",
      "Profile code to identify bottlenecks",
      "Implement lazy loading for large datasets"
    )
  )
)
```

---

## Advanced Examples and Use Cases

### Complete Clinical Trial Setup Example

Here's a complete example showing how an intermediate R user would set up a clinical trial from scratch:

```r
# Complete clinical trial setup example
# EXAMPLE: Hypertension Drug Trial
setup_hypertension_trial <- function() {

  # 1. Load required packages and functions
  source("setup_from_gsheets.R")

  # 2. Define study parameters
  study_config <- list(
    study_name = "Hypertension_RCT_2024",
    auth_sheet = "HTN_Trial_Users",
    dd_sheet = "HTN_Trial_Dictionary",
    sample_size = 200,
    study_duration = "12 weeks",
    primary_endpoint = "systolic_bp"
  )

  # 3. Create authentication structure
  auth_structure <- create_hypertension_auth_structure()

  # 4. Create data dictionary structure
  dd_structure <- create_hypertension_dd_structure()

  # 5. Set up Google Sheets (this would create actual sheets)
  # create_google_sheets_from_structure(auth_structure, dd_structure, study_config)

  # 6. Run ZZedc setup
  setup_success <- setup_zzedc_from_gsheets_complete(
    auth_sheet_name = study_config$auth_sheet,
    dd_sheet_name = study_config$dd_sheet,
    project_name = study_config$study_name,
    db_path = paste0("data/", study_config$study_name, ".db"),
    salt = Sys.getenv("HTN_TRIAL_SALT", "htn_trial_2024_salt")
  )

  if (setup_success) {
    cat("✅ Hypertension trial setup completed successfully!\n")
    cat("📊 Ready for", study_config$sample_size, "subjects\n")
    cat("🎯 Primary endpoint:", study_config$primary_endpoint, "\n")
    cat("📅 Duration:", study_config$study_duration, "\n")
  }

  return(setup_success)
}

# Helper function: Create authentication structure
create_hypertension_auth_structure <- function() {
  list(
    users = data.frame(
      username = c("pi_smith", "coord_jones", "nurse_wilson", "dm_davis", "monitor_brown"),
      password = c("HTN_PI_2024!", "Coord_HTN!", "Nurse123!", "DM_HTN_24!", "Monitor_24!"),
      full_name = c("Dr. John Smith", "Sarah Jones", "Mary Wilson", "Robert Davis", "Linda Brown"),
      role = c("Principal_Investigator", "Study_Coordinator", "Research_Nurse", "Data_Manager", "Monitor"),
      email = c("jsmith@hospital.edu", "sjones@hospital.edu", "mwilson@hospital.edu",
               "rdavis@hospital.edu", "lbrown@cro.com"),
      site_id = c(1, 1, 1, 1, 1),
      active = c(1, 1, 1, 1, 1),
      stringsAsFactors = FALSE
    ),

    roles = data.frame(
      role = c("Principal_Investigator", "Study_Coordinator", "Research_Nurse", "Data_Manager", "Monitor"),
      description = c("PI oversight", "Patient management", "Clinical procedures", "Data management", "Monitoring"),
      permissions = c("all", "read_write", "read_write", "read_write_admin", "read_only"),
      stringsAsFactors = FALSE
    ),

    sites = data.frame(
      site_id = 1,
      site_name = "University Cardiology Center",
      site_code = "UCC",
      active = 1,
      stringsAsFactors = FALSE
    )
  )
}

# Helper function: Create data dictionary structure
create_hypertension_dd_structure <- function() {

  forms_overview <- data.frame(
    workingname = c("screening", "demographics", "medical_history", "baseline_vitals",
                   "week4_vitals", "week8_vitals", "week12_vitals", "adverse_events",
                   "concomitant_meds", "study_completion"),
    fullname = c("Screening", "Demographics", "Medical History", "Baseline Vitals",
                "Week 4 Vitals", "Week 8 Vitals", "Week 12 Vitals", "Adverse Events",
                "Concomitant Medications", "Study Completion"),
    visits = c("screening", "baseline", "baseline", "baseline", "week4", "week8", "week12",
              "baseline,week4,week8,week12", "baseline,week4,week8,week12", "week12"),
    stringsAsFactors = FALSE
  )

  # Screening form
  screening_form <- data.frame(
    field = c("subject_id", "screening_date", "age", "systolic_bp_screen", "diastolic_bp_screen",
             "inclusion_hypertension", "inclusion_age", "exclusion_pregnancy", "exclusion_mi",
             "eligible", "randomization_group"),
    prompt = c("Subject ID", "Screening Date", "Age (years)", "Screening SBP (mmHg)", "Screening DBP (mmHg)",
              "Hypertension diagnosis confirmed?", "Age 18-75 years?", "Currently pregnant?",
              "MI within 6 months?", "Overall Eligible?", "Randomization Group"),
    type = c("C", "D", "N", "N", "N", "L", "L", "L", "L", "L", "L"),
    layout = c("text", "date", "numeric", "numeric", "numeric", "radio", "radio", "radio",
              "radio", "radio", "radio"),
    req = c(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0),
    values = c("", "", "", "", "", "Yes:No", "Yes:No", "Yes:No", "Yes:No", "Eligible:Not Eligible",
              "Drug:Placebo"),
    cond = c("", "", "", "", "", "", "", "gender=='Female'", "", "", "eligible=='Eligible'"),
    valid = c("nchar(subject_id)==6", "", "age>=18 && age<=75", "systolic_bp_screen>=140 && systolic_bp_screen<=200",
             "diastolic_bp_screen>=90 && diastolic_bp_screen<=110", "", "", "", "", "", ""),
    validmsg = c("Subject ID must be 6 digits", "", "Age 18-75 years", "SBP must be 140-200 mmHg",
                "DBP must be 90-110 mmHg", "", "", "", "", "", ""),
    stringsAsFactors = FALSE
  )

  # Vitals form (reused across visits)
  vitals_form <- data.frame(
    field = c("visit_date", "systolic_bp_1", "diastolic_bp_1", "systolic_bp_2", "diastolic_bp_2",
             "systolic_bp_3", "diastolic_bp_3", "heart_rate", "weight", "height", "bmi",
             "bp_medication_compliance", "side_effects_present"),
    prompt = c("Visit Date", "SBP Reading 1", "DBP Reading 1", "SBP Reading 2", "DBP Reading 2",
              "SBP Reading 3", "DBP Reading 3", "Heart Rate", "Weight (kg)", "Height (cm)", "BMI",
              "Medication Compliance", "Side Effects Present?"),
    type = c("D", "N", "N", "N", "N", "N", "N", "N", "N", "N", "N", "L", "L"),
    layout = c("date", rep("numeric", 9), "radio", "radio"),
    req = c(1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0, 1, 1),
    values = c("", "", "", "", "", "", "", "", "", "", "", "Excellent:Good:Fair:Poor", "Yes:No"),
    valid = c("", "systolic_bp_1>=80 && systolic_bp_1<=250", "diastolic_bp_1>=40 && diastolic_bp_1<=150",
             "systolic_bp_2>=80 && systolic_bp_2<=250", "diastolic_bp_2>=40 && diastolic_bp_2<=150",
             "", "", "heart_rate>=40 && heart_rate<=120", "weight>=40 && weight<=200",
             "height>=140 && height<=220", "", "", ""),
    validmsg = c("", "SBP 80-250 mmHg", "DBP 40-150 mmHg", "SBP 80-250 mmHg", "DBP 40-150 mmHg",
                "", "", "HR 40-120 bpm", "Weight 40-200 kg", "Height 140-220 cm", "", "", ""),
    stringsAsFactors = FALSE
  )

  return(list(
    forms_overview = forms_overview,
    screening = screening_form,
    baseline_vitals = vitals_form,
    week4_vitals = vitals_form,
    week8_vitals = vitals_form,
    week12_vitals = vitals_form
  ))
}

# Run the complete setup
# setup_hypertension_trial()
```

This comprehensive guide provides intermediate R users with the knowledge and tools needed to effectively work with ZZedc's Google Sheets integration, customize the system for their specific needs, and implement best practices for clinical trial data management.

---

## Conclusion

ZZedc with Google Sheets integration provides a powerful, flexible platform for clinical trial data management that can be customized and extended by intermediate R users. The modular architecture, comprehensive documentation, and extensive examples in this guide provide the foundation for implementing sophisticated clinical research workflows while maintaining the highest standards of data quality and regulatory compliance.

For additional support, consult the function documentation, security guide, and auditability documentation included with the ZZedc system.