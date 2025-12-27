# ZZedc User Guide: Electronic Data Capture for Clinical Trials

## Table of Contents
1. [Introduction](#introduction)
2. [Concept and Architecture](#concept-and-architecture)
3. [Core Features](#core-features)
4. [Installation and Setup](#installation-and-setup)
5. [Step-by-Step Tutorial: Small Clinical Trial Setup](#step-by-step-tutorial-small-clinical-trial-setup)
6. [Database Management](#database-management)
7. [User Management and Security](#user-management-and-security)
8. [Data Entry Workflows](#data-entry-workflows)
9. [Quality Control and Reporting](#quality-control-and-reporting)
10. [Data Export and Analysis](#data-export-and-analysis)
11. [Best Practices](#best-practices)
12. [Troubleshooting](#troubleshooting)

## Introduction

ZZedc is a comprehensive Electronic Data Capture (EDC) system designed specifically for clinical trials. Built with modern R/Shiny technology and Bootstrap 5 components, it provides a professional, secure, and user-friendly platform for managing clinical data from entry through analysis.

### Who Should Use ZZedc?

- **Principal Investigators** running clinical trials
- **Research Coordinators** managing data entry
- **Data Managers** ensuring quality and compliance
- **Biostatisticians** analyzing trial data
- **Academic Labs** conducting clinical research

### System Characteristics

- **Regulatory Compliance**: Supports GCP, HIPAA, and 21 CFR Part 11 compliance frameworks
- **Accessibility**: Open-source implementation without licensing restrictions
- **Customization**: Configurable forms and workflows adaptable to specific study requirements
- **Security**: Role-based access control with data encryption mechanisms
- **Responsive Design**: Compatible with desktop, tablet, and mobile devices

## Concept and Architecture

### EDC System Overview

Electronic Data Capture (EDC) systems replace traditional paper-based clinical trial data collection with secure, web-based data entry. ZZedc implements a complete EDC workflow:

```
Study Design → Form Creation → Data Entry → Quality Control → Analysis → Export
```

### Technical Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ZZedc EDC System                        │
├─────────────────────────────────────────────────────────────┤
│  Frontend (Shiny + Bootstrap 5)                            │
│  ├── Authentication & User Management                      │
│  ├── Data Entry Forms                                      │
│  ├── Real-time Validation                                  │
│  └── Reporting Dashboard                                    │
├─────────────────────────────────────────────────────────────┤
│  Backend (R + SQLite)                                      │
│  ├── Database Management                                   │
│  ├── Data Validation Logic                                 │
│  ├── Audit Trail                                          │
│  └── Export Functions                                      │
├─────────────────────────────────────────────────────────────┤
│  Data Layer                                                 │
│  ├── SQLite Database                                       │
│  ├── File Storage                                          │
│  └── Backup Systems                                        │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Study Setup**: Define forms, fields, and validation rules
2. **User Registration**: Create accounts with appropriate permissions
3. **Data Entry**: Researchers enter data through secure web forms
4. **Validation**: Real-time and batch validation ensures data quality
5. **Review**: Data managers review and query discrepancies
6. **Lock**: Complete data is locked for analysis
7. **Export**: Clean data exported for statistical analysis

## Core Features

### Home Dashboard
- **System Interface**: Landing page displaying system overview and status
- **Navigation**: Access to all system functions and modules
- **Status Indicators**: Real-time monitoring of system health and data metrics
- **Documentation**: Built-in resources and support documentation

### Electronic Data Capture (EDC)
- **Authentication**: Role-based user login and access control
- **Data Entry Forms**: Customizable forms adaptable to study requirements
- **Data Validation**: Automated validation with immediate feedback to users
- **Progress Tracking**: Visual indicators of data entry and study progress
- **Cross-Device Compatibility**: Interface functionality on desktop, tablet, and mobile platforms

### Reporting System
- **Basic Reports**: Data summaries and tabulations
- **Quality Control Reports**: Data completeness assessment and validation metrics
- **Statistical Reports**: Summary statistics with interactive data tables
- **Customizable Reports**: User-defined report configurations

### Data Explorer
- **Data Tables**: Sorting, filtering, and search functionality
- **Data Visualization**: Graphical representation of data distributions
- **Completeness Analysis**: Identification and tracking of incomplete records
- **Data Extraction**: Subset selection and export capabilities

### Export Center
- **Export Formats**: CSV, Excel, JSON, PDF, and HTML format support
- **Batch Processing**: Multiple dataset export operations
- **Export Configurations**: Predefined template configurations
- **Automated Export**: Scheduled export generation and delivery

## Installation and Setup

### System Requirements

- **R Version**: 4.0.0 or higher
- **Operating System**: Windows, macOS, or Linux
- **Memory**: Minimum 4GB RAM (8GB recommended)
- **Storage**: 1GB available space
- **Network**: Internet connection for package installation

### Quick Installation

```r
# Install required packages
install.packages(c("devtools", "shiny", "bslib", "DT", "RSQLite"))

# Install ZZedc (development version)
devtools::install_github("rythomas/zzedc")

# Launch the application
library(zzedc)
launch_zzedc()
```

### Manual Installation

1. **Clone the Repository**:
```bash
git clone https://github.com/rythomas/zzedc.git
cd zzedc
```

2. **Install Dependencies**:
```r
# In R console
source("R/launch_zzedc.R")
```

3. **Launch Application**:
```r
# Option 1: Use launcher function
launch_zzedc()

# Option 2: Use run script
source("run_app.R")

# Option 3: Standard shiny
shiny::runApp()
```

## Step-by-Step Tutorial: Small Clinical Trial Setup

### Scenario: MEMORY-001 Study

**Study Overview**: A small academic lab is conducting a 6-month cognitive enhancement trial with 50 participants. The study needs to track demographics, baseline assessments, monthly visits, and adverse events.

### Step 1: Initial System Setup

#### 1.1 Launch ZZedc

```r
# Start the application
library(zzedc)
launch_zzedc(port = 3838)
```

The application opens at `http://localhost:3838` with the modern Bootstrap 5 interface.

#### 1.2 First Login

- **URL**: Navigate to the EDC tab
- **Default Credentials**: 
  - Username: `ww`
  - Password: `pw`

⚠️ **Security Note**: Change default passwords immediately in production!

### Step 2: Database Setup

#### 2.1 Create SQLite Database Structure

Create a new file `setup_database.R` in your ZZedc directory:

```r
# setup_database.R - MEMORY-001 Study Database Setup

library(RSQLite)
library(DBI)

# Create database connection
db_path <- "data/memory001_study.db"
con <- dbConnect(SQLite(), db_path)

# Create study metadata table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS study_info (
    study_id TEXT PRIMARY KEY,
    study_name TEXT NOT NULL,
    pi_name TEXT,
    start_date DATE,
    end_date DATE,
    target_enrollment INTEGER,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)")

# Insert study information
dbExecute(con, "
INSERT OR REPLACE INTO study_info 
(study_id, study_name, pi_name, start_date, end_date, target_enrollment)
VALUES 
('MEMORY-001', 'Cognitive Enhancement Trial', 'Dr. Sarah Johnson', 
 '2024-01-15', '2024-12-31', 50)")

# Create subjects table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS subjects (
    subject_id TEXT PRIMARY KEY,
    study_id TEXT NOT NULL,
    site_id TEXT DEFAULT '001',
    enrollment_date DATE,
    randomization_group TEXT CHECK(randomization_group IN ('Active', 'Placebo')),
    status TEXT DEFAULT 'Enrolled' CHECK(status IN ('Screened', 'Enrolled', 'Completed', 'Withdrawn')),
    withdrawal_reason TEXT,
    created_by TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (study_id) REFERENCES study_info(study_id)
)")

# Create demographics form
dbExecute(con, "
CREATE TABLE IF NOT EXISTS demographics (
    record_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id TEXT NOT NULL,
    visit_name TEXT DEFAULT 'Baseline',
    age INTEGER CHECK(age >= 18 AND age <= 85),
    gender TEXT CHECK(gender IN ('Male', 'Female', 'Other', 'Prefer not to say')),
    race TEXT,
    ethnicity TEXT CHECK(ethnicity IN ('Hispanic or Latino', 'Not Hispanic or Latino', 'Unknown')),
    education_years INTEGER CHECK(education_years >= 0 AND education_years <= 25),
    handedness TEXT CHECK(handedness IN ('Right', 'Left', 'Ambidextrous')),
    height_cm REAL CHECK(height_cm >= 100 AND height_cm <= 250),
    weight_kg REAL CHECK(weight_kg >= 30 AND weight_kg <= 200),
    data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entry_user TEXT,
    form_status TEXT DEFAULT 'Incomplete' CHECK(form_status IN ('Incomplete', 'Complete', 'Verified')),
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
)")

# Create cognitive assessments table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS cognitive_assessments (
    record_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id TEXT NOT NULL,
    visit_name TEXT NOT NULL,
    visit_date DATE,
    mmse_total INTEGER CHECK(mmse_total >= 0 AND mmse_total <= 30),
    moca_total INTEGER CHECK(moca_total >= 0 AND moca_total <= 30),
    digit_span_forward INTEGER CHECK(digit_span_forward >= 0 AND digit_span_forward <= 9),
    digit_span_backward INTEGER CHECK(digit_span_backward >= 0 AND digit_span_backward <= 8),
    trail_making_a_time REAL CHECK(trail_making_a_time > 0),
    trail_making_b_time REAL CHECK(trail_making_b_time > 0),
    verbal_fluency_animals INTEGER CHECK(verbal_fluency_animals >= 0),
    assessment_notes TEXT,
    assessor_initials TEXT,
    data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entry_user TEXT,
    form_status TEXT DEFAULT 'Incomplete' CHECK(form_status IN ('Incomplete', 'Complete', 'Verified')),
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
)")

# Create visit schedule table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS visit_schedule (
    record_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id TEXT NOT NULL,
    visit_name TEXT NOT NULL,
    scheduled_date DATE,
    actual_date DATE,
    visit_window_start DATE,
    visit_window_end DATE,
    visit_status TEXT DEFAULT 'Scheduled' CHECK(visit_status IN ('Scheduled', 'Completed', 'Missed', 'Cancelled')),
    missed_reason TEXT,
    protocol_deviation BOOLEAN DEFAULT 0,
    deviation_description TEXT,
    data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entry_user TEXT,
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
)")

# Create adverse events table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS adverse_events (
    ae_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id TEXT NOT NULL,
    ae_term TEXT NOT NULL,
    ae_start_date DATE,
    ae_end_date DATE,
    ongoing BOOLEAN DEFAULT 0,
    severity TEXT CHECK(severity IN ('Mild', 'Moderate', 'Severe')),
    seriousness TEXT CHECK(seriousness IN ('Non-serious', 'Serious')),
    relationship TEXT CHECK(relationship IN ('Unrelated', 'Unlikely', 'Possible', 'Probable', 'Definite')),
    action_taken TEXT CHECK(action_taken IN ('None', 'Dose reduction', 'Dose interruption', 'Drug discontinued', 'Other')),
    outcome TEXT CHECK(outcome IN ('Resolved', 'Ongoing', 'Resolved with sequelae', 'Fatal')),
    reported_by TEXT,
    report_date DATE,
    data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entry_user TEXT,
    form_status TEXT DEFAULT 'Incomplete' CHECK(form_status IN ('Incomplete', 'Complete', 'Verified')),
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
)")

# Create data audit trail
dbExecute(con, "
CREATE TABLE IF NOT EXISTS audit_trail (
    audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    field_name TEXT,
    old_value TEXT,
    new_value TEXT,
    change_type TEXT CHECK(change_type IN ('INSERT', 'UPDATE', 'DELETE')),
    user_id TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reason TEXT
)")

# Create data validation rules
dbExecute(con, "
CREATE TABLE IF NOT EXISTS validation_rules (
    rule_id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    field_name TEXT NOT NULL,
    rule_type TEXT CHECK(rule_type IN ('range', 'required', 'format', 'logic')),
    rule_expression TEXT NOT NULL,
    error_message TEXT NOT NULL,
    severity TEXT DEFAULT 'Error' CHECK(severity IN ('Warning', 'Error')),
    active BOOLEAN DEFAULT 1
)")

# Insert sample validation rules
validation_rules <- data.frame(
  table_name = c("demographics", "demographics", "cognitive_assessments", "cognitive_assessments"),
  field_name = c("age", "weight_kg", "mmse_total", "visit_date"),
  rule_type = c("range", "range", "range", "required"),
  rule_expression = c("18 <= age <= 85", "30 <= weight_kg <= 200", "0 <= mmse_total <= 30", "NOT NULL"),
  error_message = c("Age must be between 18 and 85", "Weight must be between 30 and 200 kg", 
                   "MMSE score must be between 0 and 30", "Visit date is required"),
  severity = c("Error", "Error", "Error", "Error"),
  active = c(1, 1, 1, 1)
)

dbWriteTable(con, "validation_rules", validation_rules, append = TRUE, row.names = FALSE)

# Create users table for the EDC system
dbExecute(con, "
CREATE TABLE IF NOT EXISTS edc_users (
    user_id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name TEXT,
    email TEXT,
    role TEXT CHECK(role IN ('Admin', 'PI', 'Coordinator', 'Data Manager', 'Monitor')),
    site_id TEXT,
    active BOOLEAN DEFAULT 1,
    last_login TIMESTAMP,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT
)")

# Insert sample users (in production, use proper password hashing)
sample_users <- data.frame(
  user_id = c("admin", "pi_johnson", "coord_smith", "dm_brown"),
  username = c("admin", "sjohnson", "asmith", "mbrown"),
  password_hash = c("admin123", "password123", "coord123", "data123"), # Use proper hashing in production!
  full_name = c("System Administrator", "Dr. Sarah Johnson", "Alice Smith", "Mike Brown"),
  email = c("admin@memory001.org", "sjohnson@university.edu", "asmith@university.edu", "mbrown@university.edu"),
  role = c("Admin", "PI", "Coordinator", "Data Manager"),
  site_id = c("ALL", "001", "001", "001"),
  active = c(1, 1, 1, 1),
  created_by = c("SYSTEM", "admin", "admin", "admin")
)

dbWriteTable(con, "edc_users", sample_users, append = TRUE, row.names = FALSE)

# Close connection
dbDisconnect(con)

cat("✅ MEMORY-001 database setup complete!\n")
cat("📁 Database file: data/memory001_study.db\n")
cat("👥 Sample users created:\n")
cat("   - admin/admin123 (Administrator)\n")
cat("   - sjohnson/password123 (Principal Investigator)\n")
cat("   - asmith/coord123 (Research Coordinator)\n")
cat("   - mbrown/data123 (Data Manager)\n")
```

#### 2.2 Run Database Setup

```r
# Execute the database setup
source("setup_database.R")
```

### Step 3: Configure EDC Forms

#### 3.1 Create Custom Form Definitions

Create `forms/memory001_forms.R`:

```r
# forms/memory001_forms.R - Custom forms for MEMORY-001 Study

# Demographics form definition
demographics_form <- list(
  form_name = "demographics",
  form_title = "Demographics and Baseline Characteristics",
  fields = list(
    list(
      field_name = "subject_id",
      field_label = "Subject ID",
      field_type = "text",
      required = TRUE,
      validation = "^MEM-\\d{3}$",
      help_text = "Format: MEM-001 to MEM-050"
    ),
    list(
      field_name = "age",
      field_label = "Age (years)",
      field_type = "numeric",
      required = TRUE,
      min_value = 18,
      max_value = 85
    ),
    list(
      field_name = "gender",
      field_label = "Gender",
      field_type = "select",
      required = TRUE,
      choices = c("Male", "Female", "Other", "Prefer not to say")
    ),
    list(
      field_name = "race",
      field_label = "Race",
      field_type = "select",
      required = TRUE,
      choices = c("White", "Black or African American", "Asian", "American Indian or Alaska Native", 
                 "Native Hawaiian or Other Pacific Islander", "Other", "Multiple races")
    ),
    list(
      field_name = "ethnicity",
      field_label = "Ethnicity",
      field_type = "select",
      required = TRUE,
      choices = c("Hispanic or Latino", "Not Hispanic or Latino", "Unknown")
    ),
    list(
      field_name = "education_years",
      field_label = "Years of Education",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 25
    ),
    list(
      field_name = "height_cm",
      field_label = "Height (cm)",
      field_type = "numeric",
      required = TRUE,
      min_value = 100,
      max_value = 250
    ),
    list(
      field_name = "weight_kg",
      field_label = "Weight (kg)",
      field_type = "numeric",
      required = TRUE,
      min_value = 30,
      max_value = 200
    )
  )
)

# Cognitive assessment form
cognitive_form <- list(
  form_name = "cognitive_assessments",
  form_title = "Cognitive Assessment Battery",
  fields = list(
    list(
      field_name = "subject_id",
      field_label = "Subject ID",
      field_type = "text",
      required = TRUE
    ),
    list(
      field_name = "visit_name",
      field_label = "Visit",
      field_type = "select",
      required = TRUE,
      choices = c("Baseline", "Month 1", "Month 2", "Month 3", "Month 4", "Month 5", "Month 6")
    ),
    list(
      field_name = "visit_date",
      field_label = "Assessment Date",
      field_type = "date",
      required = TRUE
    ),
    list(
      field_name = "mmse_total",
      field_label = "MMSE Total Score",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 30,
      help_text = "Mini-Mental State Examination (0-30)"
    ),
    list(
      field_name = "moca_total",
      field_label = "MoCA Total Score",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 30,
      help_text = "Montreal Cognitive Assessment (0-30)"
    ),
    list(
      field_name = "digit_span_forward",
      field_label = "Digit Span Forward",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 9
    ),
    list(
      field_name = "digit_span_backward",
      field_label = "Digit Span Backward",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 8
    ),
    list(
      field_name = "trail_making_a_time",
      field_label = "Trail Making A Time (seconds)",
      field_type = "numeric",
      required = TRUE,
      min_value = 1
    ),
    list(
      field_name = "trail_making_b_time",
      field_label = "Trail Making B Time (seconds)",
      field_type = "numeric",
      required = TRUE,
      min_value = 1
    ),
    list(
      field_name = "verbal_fluency_animals",
      field_label = "Verbal Fluency - Animals",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      help_text = "Number of animals named in 1 minute"
    ),
    list(
      field_name = "assessor_initials",
      field_label = "Assessor Initials",
      field_type = "text",
      required = TRUE,
      validation = "^[A-Z]{2,3}$"
    )
  )
)

# Adverse event form
adverse_event_form <- list(
  form_name = "adverse_events",
  form_title = "Adverse Event Report",
  fields = list(
    list(
      field_name = "subject_id",
      field_label = "Subject ID",
      field_type = "text",
      required = TRUE
    ),
    list(
      field_name = "ae_term",
      field_label = "Adverse Event Term",
      field_type = "text",
      required = TRUE,
      help_text = "Describe the adverse event in medical terminology"
    ),
    list(
      field_name = "ae_start_date",
      field_label = "Start Date",
      field_type = "date",
      required = TRUE
    ),
    list(
      field_name = "ae_end_date",
      field_label = "End Date",
      field_type = "date",
      required = FALSE
    ),
    list(
      field_name = "ongoing",
      field_label = "Ongoing",
      field_type = "checkbox",
      required = FALSE
    ),
    list(
      field_name = "severity",
      field_label = "Severity",
      field_type = "select",
      required = TRUE,
      choices = c("Mild", "Moderate", "Severe")
    ),
    list(
      field_name = "seriousness",
      field_label = "Seriousness",
      field_type = "select",
      required = TRUE,
      choices = c("Non-serious", "Serious")
    ),
    list(
      field_name = "relationship",
      field_label = "Relationship to Study Drug",
      field_type = "select",
      required = TRUE,
      choices = c("Unrelated", "Unlikely", "Possible", "Probable", "Definite")
    ),
    list(
      field_name = "action_taken",
      field_label = "Action Taken",
      field_type = "select",
      required = TRUE,
      choices = c("None", "Dose reduction", "Dose interruption", "Drug discontinued", "Other")
    ),
    list(
      field_name = "outcome",
      field_label = "Outcome",
      field_type = "select",
      required = TRUE,
      choices = c("Resolved", "Ongoing", "Resolved with sequelae", "Fatal")
    )
  )
)

# Save form definitions
save(demographics_form, cognitive_form, adverse_event_form, 
     file = "forms/memory001_form_definitions.RData")

cat("✅ Form definitions created for MEMORY-001 study\n")
```

#### 3.2 Create Dynamic Form Renderer

Update `forms/renderpanels.R` to handle the custom forms:

```r
# Enhanced form renderer for MEMORY-001 study
source("forms/memory001_forms.R")

renderDynamicForm <- function(form_definition) {
  
  form_fields <- lapply(form_definition$fields, function(field) {
    
    # Generate input based on field type
    input_element <- switch(field$field_type,
      "text" = textInput(
        inputId = field$field_name,
        label = if(field$required) requ(field$field_label) else field$field_label,
        placeholder = field$help_text %||% ""
      ),
      
      "numeric" = numericInput(
        inputId = field$field_name,
        label = if(field$required) requ(field$field_label) else field$field_label,
        value = NULL,
        min = field$min_value %||% NA,
        max = field$max_value %||% NA
      ),
      
      "date" = dateInput(
        inputId = field$field_name,
        label = if(field$required) requ(field$field_label) else field$field_label,
        value = NULL,
        format = "yyyy-mm-dd"
      ),
      
      "select" = selectInput(
        inputId = field$field_name,
        label = if(field$required) requ(field$field_label) else field$field_label,
        choices = c("" = "", field$choices),
        selected = ""
      ),
      
      "checkbox" = checkboxInput(
        inputId = field$field_name,
        label = field$field_label,
        value = FALSE
      ),
      
      "textarea" = textAreaInput(
        inputId = field$field_name,
        label = if(field$required) requ(field$field_label) else field$field_label,
        placeholder = field$help_text %||% ""
      )
    )
    
    # Add help text if provided
    if (!is.null(field$help_text) && field$field_type != "text") {
      tagList(
        input_element,
        helpText(field$help_text)
      )
    } else {
      input_element
    }
  })
  
  # Wrap in a form container
  bslib::card(
    bslib::card_header(
      tagList(bsicons::bs_icon("clipboard-data"), form_definition$form_title)
    ),
    bslib::card_body(
      form_fields,
      hr(),
      div(class = "text-end",
        bslib::input_action_button("save_form", "Save Form", 
                                 class = "btn-success me-2",
                                 icon = bsicons::bs_icon("check-circle")),
        bslib::input_action_button("validate_form", "Validate", 
                                 class = "btn-warning",
                                 icon = bsicons::bs_icon("shield-check"))
      )
    )
  )
}

# Helper function for required field marking
requ <- function(label) {
  tagList(span("*", class = "req_star"), label)
}

# Null coalescing operator
`%||%` <- function(x, y) if (is.null(x)) y else x
```

### Step 4: Subject Enrollment and Data Entry

#### 4.1 Create Subject Enrollment Function

Create `scripts/enroll_subjects.R`:

```r
# scripts/enroll_subjects.R - Subject enrollment for MEMORY-001

library(RSQLite)
library(DBI)

enroll_subject <- function(subject_id, randomization_group = NULL, enrollment_date = Sys.Date()) {
  
  # Connect to database
  con <- dbConnect(SQLite(), "data/memory001_study.db")
  
  # Check if subject already exists
  existing <- dbGetQuery(con, "SELECT subject_id FROM subjects WHERE subject_id = ?", 
                        params = list(subject_id))
  
  if (nrow(existing) > 0) {
    dbDisconnect(con)
    stop("Subject ", subject_id, " already enrolled!")
  }
  
  # Random assignment if not specified
  if (is.null(randomization_group)) {
    randomization_group <- sample(c("Active", "Placebo"), 1)
  }
  
  # Insert new subject
  dbExecute(con, "
    INSERT INTO subjects (subject_id, study_id, enrollment_date, randomization_group, status, created_by)
    VALUES (?, 'MEMORY-001', ?, ?, 'Enrolled', 'system')",
    params = list(subject_id, enrollment_date, randomization_group))
  
  # Create visit schedule
  visit_dates <- seq(from = as.Date(enrollment_date), by = "month", length.out = 7)
  visit_names <- c("Baseline", "Month 1", "Month 2", "Month 3", "Month 4", "Month 5", "Month 6")
  
  for (i in 1:length(visit_names)) {
    # Calculate visit window (±7 days)
    window_start <- visit_dates[i] - 7
    window_end <- visit_dates[i] + 7
    
    dbExecute(con, "
      INSERT INTO visit_schedule (subject_id, visit_name, scheduled_date, visit_window_start, visit_window_end)
      VALUES (?, ?, ?, ?, ?)",
      params = list(subject_id, visit_names[i], visit_dates[i], window_start, window_end))
  }
  
  dbDisconnect(con)
  
  cat("✅ Subject", subject_id, "enrolled successfully\n")
  cat("🎯 Randomized to:", randomization_group, "\n")
  cat("📅 Enrollment date:", enrollment_date, "\n")
  
  return(list(
    subject_id = subject_id,
    randomization_group = randomization_group,
    enrollment_date = enrollment_date,
    visit_schedule = data.frame(
      visit = visit_names,
      scheduled_date = visit_dates,
      window_start = visit_dates - 7,
      window_end = visit_dates + 7
    )
  ))
}

# Batch enrollment function
enroll_batch_subjects <- function(n_subjects = 10, start_date = Sys.Date()) {
  
  enrolled_subjects <- list()
  
  for (i in 1:n_subjects) {
    subject_id <- sprintf("MEM-%03d", i)
    enrollment_date <- start_date + sample(0:30, 1)  # Spread enrollment over 30 days
    
    tryCatch({
      result <- enroll_subject(subject_id, enrollment_date = enrollment_date)
      enrolled_subjects[[i]] <- result
    }, error = function(e) {
      cat("❌ Error enrolling", subject_id, ":", e$message, "\n")
    })
  }
  
  cat("\n📊 Enrollment Summary:\n")
  cat("Total subjects enrolled:", length(enrolled_subjects), "\n")
  
  # Randomization balance
  groups <- sapply(enrolled_subjects, function(x) x$randomization_group)
  table_groups <- table(groups)
  cat("Randomization balance:\n")
  print(table_groups)
  
  return(enrolled_subjects)
}

# Example usage:
# enroll_subject("MEM-001")
# enroll_batch_subjects(n_subjects = 20)
```

#### 4.2 Enroll Sample Subjects

```r
# Enroll sample subjects for testing
source("scripts/enroll_subjects.R")

# Enroll 20 subjects for the pilot
sample_enrollment <- enroll_batch_subjects(n_subjects = 20, start_date = as.Date("2024-01-15"))
```

### Step 5: Data Entry Workflow

#### 5.1 Login to EDC System

1. Navigate to the **EDC** tab
2. Login with coordinator credentials:
   - Username: `asmith`
   - Password: `coord123`

#### 5.2 Enter Demographics Data

Example data entry for subject MEM-001:

```r
# This would be entered through the web interface, but here's the data structure:
demographics_data <- list(
  subject_id = "MEM-001",
  age = 67,
  gender = "Female",
  race = "White",
  ethnicity = "Not Hispanic or Latino",
  education_years = 16,
  handedness = "Right",
  height_cm = 165,
  weight_kg = 68,
  visit_name = "Baseline"
)
```

#### 5.3 Enter Cognitive Assessment Data

```r
cognitive_data <- list(
  subject_id = "MEM-001",
  visit_name = "Baseline",
  visit_date = "2024-01-20",
  mmse_total = 28,
  moca_total = 26,
  digit_span_forward = 6,
  digit_span_backward = 4,
  trail_making_a_time = 32.5,
  trail_making_b_time = 78.2,
  verbal_fluency_animals = 18,
  assessor_initials = "AS"
)
```

### Step 6: Quality Control and Monitoring

#### 6.1 Create Data Quality Reports

Create `reports/quality_control.R`:

```r
# reports/quality_control.R - Quality control reports for MEMORY-001

library(RSQLite)
library(DBI)
library(dplyr)
library(ggplot2)

generate_quality_report <- function(db_path = "data/memory001_study.db") {
  
  con <- dbConnect(SQLite(), db_path)
  
  # Overall study metrics
  study_metrics <- list()
  
  # Enrollment metrics
  subjects <- dbGetQuery(con, "SELECT * FROM subjects")
  study_metrics$total_enrolled <- nrow(subjects)
  study_metrics$randomization_balance <- table(subjects$randomization_group)
  
  # Form completion rates
  demographics <- dbGetQuery(con, "SELECT subject_id, form_status FROM demographics")
  cognitive <- dbGetQuery(con, "SELECT subject_id, visit_name, form_status FROM cognitive_assessments")
  
  # Demographics completion
  demo_complete <- demographics %>%
    summarise(
      total_subjects = n(),
      complete_forms = sum(form_status == "Complete"),
      completion_rate = round(complete_forms / total_subjects * 100, 1)
    )
  
  # Cognitive assessment completion by visit
  cog_complete <- cognitive %>%
    group_by(visit_name) %>%
    summarise(
      total_assessments = n(),
      complete_assessments = sum(form_status == "Complete"),
      completion_rate = round(complete_assessments / total_assessments * 100, 1)
    )
  
  # Data quality issues
  quality_issues <- list()
  
  # Missing required fields
  missing_demo <- dbGetQuery(con, "
    SELECT subject_id, 
           CASE WHEN age IS NULL THEN 'age' END as missing_age,
           CASE WHEN gender IS NULL THEN 'gender' END as missing_gender,
           CASE WHEN height_cm IS NULL THEN 'height' END as missing_height,
           CASE WHEN weight_kg IS NULL THEN 'weight' END as missing_weight
    FROM demographics 
    WHERE age IS NULL OR gender IS NULL OR height_cm IS NULL OR weight_kg IS NULL")
  
  # Out of range values
  range_issues <- dbGetQuery(con, "
    SELECT subject_id, 'demographics' as table_name, 'age' as field_name, age as value, 'Age out of range' as issue
    FROM demographics 
    WHERE age < 18 OR age > 85
    UNION ALL
    SELECT subject_id, 'cognitive_assessments', 'mmse_total', mmse_total, 'MMSE score out of range'
    FROM cognitive_assessments 
    WHERE mmse_total < 0 OR mmse_total > 30")
  
  # Visit schedule adherence
  visit_adherence <- dbGetQuery(con, "
    SELECT vs.subject_id, vs.visit_name, vs.scheduled_date, vs.actual_date,
           CASE 
             WHEN vs.actual_date IS NULL THEN 'Missing'
             WHEN vs.actual_date < vs.visit_window_start OR vs.actual_date > vs.visit_window_end THEN 'Outside window'
             ELSE 'On schedule'
           END as adherence_status
    FROM visit_schedule vs")
  
  dbDisconnect(con)
  
  # Create quality report
  report <- list(
    study_metrics = study_metrics,
    demographics_completion = demo_complete,
    cognitive_completion = cog_complete,
    missing_data = missing_demo,
    range_issues = range_issues,
    visit_adherence = visit_adherence,
    generated_date = Sys.time()
  )
  
  return(report)
}

# Generate and display quality report
create_quality_dashboard <- function() {
  
  report <- generate_quality_report()
  
  cat("📊 MEMORY-001 Study Quality Report\n")
  cat("==================================\n")
  cat("Generated:", format(report$generated_date, "%Y-%m-%d %H:%M"), "\n\n")
  
  cat("📈 Study Metrics:\n")
  cat("Total Enrolled:", report$study_metrics$total_enrolled, "\n")
  cat("Randomization Balance:\n")
  print(report$study_metrics$randomization_balance)
  
  cat("\n📋 Form Completion Rates:\n")
  cat("Demographics:", report$demographics_completion$completion_rate, "%\n")
  
  cat("\nCognitive Assessments by Visit:\n")
  print(report$cognitive_completion)
  
  if (nrow(report$missing_data) > 0) {
    cat("\n⚠️  Missing Required Data:\n")
    print(report$missing_data)
  }
  
  if (nrow(report$range_issues) > 0) {
    cat("\n❌ Data Range Issues:\n")
    print(report$range_issues)
  }
  
  cat("\n📅 Visit Adherence Summary:\n")
  adherence_summary <- table(report$visit_adherence$adherence_status)
  print(adherence_summary)
  
  return(report)
}

# Usage:
# quality_report <- create_quality_dashboard()
```

#### 6.2 Run Quality Control Report

```r
source("reports/quality_control.R")
quality_report <- create_quality_dashboard()
```

### Step 7: Statistical Analysis and Reports

#### 7.1 Create Analysis Functions

Create `analysis/memory001_analysis.R`:

```r
# analysis/memory001_analysis.R - Statistical analysis for MEMORY-001

library(RSQLite)
library(DBI)
library(dplyr)
library(ggplot2)
library(broom)

# Load and prepare data for analysis
prepare_analysis_dataset <- function(db_path = "data/memory001_study.db") {
  
  con <- dbConnect(SQLite(), db_path)
  
  # Get all data
  subjects <- dbGetQuery(con, "SELECT * FROM subjects")
  demographics <- dbGetQuery(con, "SELECT * FROM demographics")
  cognitive <- dbGetQuery(con, "SELECT * FROM cognitive_assessments")
  
  dbDisconnect(con)
  
  # Merge datasets
  baseline_cognitive <- cognitive %>%
    filter(visit_name == "Baseline") %>%
    select(-visit_name, -visit_date)
  
  analysis_data <- subjects %>%
    left_join(demographics, by = "subject_id") %>%
    left_join(baseline_cognitive, by = "subject_id") %>%
    filter(status == "Enrolled")
  
  # Create derived variables
  analysis_data <- analysis_data %>%
    mutate(
      bmi = weight_kg / (height_cm/100)^2,
      age_group = cut(age, breaks = c(0, 65, 75, 100), 
                     labels = c("18-64", "65-74", "75+")),
      education_level = cut(education_years, breaks = c(0, 12, 16, 25),
                           labels = c("High school or less", "Some college", "College or more")),
      cognitive_composite = (mmse_total/30 + moca_total/30) / 2
    )
  
  return(analysis_data)
}

# Baseline characteristics table
create_baseline_table <- function(data) {
  
  baseline_stats <- data %>%
    group_by(randomization_group) %>%
    summarise(
      n = n(),
      age_mean_sd = sprintf("%.1f (%.1f)", mean(age, na.rm = TRUE), sd(age, na.rm = TRUE)),
      female_n_pct = sprintf("%d (%.1f%%)", 
                            sum(gender == "Female", na.rm = TRUE),
                            mean(gender == "Female", na.rm = TRUE) * 100),
      education_mean_sd = sprintf("%.1f (%.1f)", 
                                 mean(education_years, na.rm = TRUE), 
                                 sd(education_years, na.rm = TRUE)),
      mmse_mean_sd = sprintf("%.1f (%.1f)", 
                            mean(mmse_total, na.rm = TRUE), 
                            sd(mmse_total, na.rm = TRUE)),
      moca_mean_sd = sprintf("%.1f (%.1f)", 
                            mean(moca_total, na.rm = TRUE), 
                            sd(moca_total, na.rm = TRUE))
    )
  
  # Overall statistics
  overall_stats <- data %>%
    summarise(
      randomization_group = "Overall",
      n = n(),
      age_mean_sd = sprintf("%.1f (%.1f)", mean(age, na.rm = TRUE), sd(age, na.rm = TRUE)),
      female_n_pct = sprintf("%d (%.1f%%)", 
                            sum(gender == "Female", na.rm = TRUE),
                            mean(gender == "Female", na.rm = TRUE) * 100),
      education_mean_sd = sprintf("%.1f (%.1f)", 
                                 mean(education_years, na.rm = TRUE), 
                                 sd(education_years, na.rm = TRUE)),
      mmse_mean_sd = sprintf("%.1f (%.1f)", 
                            mean(mmse_total, na.rm = TRUE), 
                            sd(mmse_total, na.rm = TRUE)),
      moca_mean_sd = sprintf("%.1f (%.1f)", 
                            mean(moca_total, na.rm = TRUE), 
                            sd(moca_total, na.rm = TRUE))
    )
  
  baseline_table <- bind_rows(baseline_stats, overall_stats)
  
  return(baseline_table)
}

# Randomization balance tests
test_randomization_balance <- function(data) {
  
  balance_tests <- list()
  
  # Age
  balance_tests$age <- t.test(age ~ randomization_group, data = data)
  
  # Gender
  gender_table <- table(data$randomization_group, data$gender)
  balance_tests$gender <- chisq.test(gender_table)
  
  # Education
  balance_tests$education <- t.test(education_years ~ randomization_group, data = data)
  
  # Baseline MMSE
  balance_tests$mmse <- t.test(mmse_total ~ randomization_group, data = data)
  
  # Baseline MoCA
  balance_tests$moca <- t.test(moca_total ~ randomization_group, data = data)
  
  return(balance_tests)
}

# Create summary report
generate_analysis_report <- function() {
  
  cat("📊 MEMORY-001 Statistical Analysis Report\n")
  cat("=========================================\n")
  cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n\n")
  
  # Load data
  data <- prepare_analysis_dataset()
  
  cat("📈 Study Overview:\n")
  cat("Total subjects with data:", nrow(data), "\n")
  cat("Active group:", sum(data$randomization_group == "Active"), "\n")
  cat("Placebo group:", sum(data$randomization_group == "Placebo"), "\n\n")
  
  # Baseline characteristics
  cat("📋 Baseline Characteristics:\n")
  baseline_table <- create_baseline_table(data)
  print(baseline_table)
  
  cat("\n🎯 Randomization Balance Tests:\n")
  balance_tests <- test_randomization_balance(data)
  
  cat("Age: p =", round(balance_tests$age$p.value, 3), "\n")
  cat("Gender: p =", round(balance_tests$gender$p.value, 3), "\n")
  cat("Education: p =", round(balance_tests$education$p.value, 3), "\n")
  cat("Baseline MMSE: p =", round(balance_tests$mmse$p.value, 3), "\n")
  cat("Baseline MoCA: p =", round(balance_tests$moca$p.value, 3), "\n")
  
  return(list(
    data = data,
    baseline_table = baseline_table,
    balance_tests = balance_tests
  ))
}

# Usage:
# analysis_results <- generate_analysis_report()
```

#### 7.2 Generate Analysis Report

```r
source("analysis/memory001_analysis.R")
analysis_results <- generate_analysis_report()
```

### Step 8: Data Export and Lock

#### 8.1 Create Export Functions

Create `scripts/data_export.R`:

```r
# scripts/data_export.R - Data export functions for MEMORY-001

library(RSQLite)
library(DBI)
library(openxlsx)
library(jsonlite)

# Export all study data
export_study_data <- function(db_path = "data/memory001_study.db", 
                             export_format = "csv", 
                             output_dir = "exports") {
  
  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Connect to database
  con <- dbConnect(SQLite(), db_path)
  
  # Get all tables
  tables <- c("subjects", "demographics", "cognitive_assessments", 
              "visit_schedule", "adverse_events", "audit_trail")
  
  export_files <- list()
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  
  if (export_format == "csv") {
    
    for (table in tables) {
      data <- dbGetQuery(con, paste("SELECT * FROM", table))
      filename <- file.path(output_dir, paste0(table, "_", timestamp, ".csv"))
      write.csv(data, filename, row.names = FALSE)
      export_files[[table]] <- filename
      cat("✅ Exported", table, "to", filename, "\n")
    }
    
  } else if (export_format == "excel") {
    
    filename <- file.path(output_dir, paste0("memory001_study_", timestamp, ".xlsx"))
    wb <- createWorkbook()
    
    for (table in tables) {
      data <- dbGetQuery(con, paste("SELECT * FROM", table))
      addWorksheet(wb, table)
      writeData(wb, table, data)
    }
    
    saveWorkbook(wb, filename, overwrite = TRUE)
    export_files[["excel_file"]] <- filename
    cat("✅ Exported all tables to", filename, "\n")
    
  } else if (export_format == "json") {
    
    study_data <- list()
    for (table in tables) {
      study_data[[table]] <- dbGetQuery(con, paste("SELECT * FROM", table))
    }
    
    filename <- file.path(output_dir, paste0("memory001_study_", timestamp, ".json"))
    write_json(study_data, filename, pretty = TRUE)
    export_files[["json_file"]] <- filename
    cat("✅ Exported all data to", filename, "\n")
    
  }
  
  dbDisconnect(con)
  
  # Create export manifest
  manifest <- list(
    study_id = "MEMORY-001",
    export_timestamp = Sys.time(),
    export_format = export_format,
    files = export_files,
    exported_by = Sys.info()["user"]
  )
  
  manifest_file <- file.path(output_dir, paste0("export_manifest_", timestamp, ".json"))
  write_json(manifest, manifest_file, pretty = TRUE)
  
  cat("\n📦 Export complete!\n")
  cat("📁 Export directory:", output_dir, "\n")
  cat("📄 Manifest file:", manifest_file, "\n")
  
  return(manifest)
}

# Create analysis-ready dataset
create_analysis_dataset <- function(db_path = "data/memory001_study.db", 
                                   output_dir = "exports") {
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  con <- dbConnect(SQLite(), db_path)
  
  # Create wide-format dataset for analysis
  analysis_query <- "
  SELECT 
    s.subject_id,
    s.randomization_group,
    s.enrollment_date,
    s.status as subject_status,
    
    -- Demographics
    d.age,
    d.gender,
    d.race,
    d.ethnicity,
    d.education_years,
    d.height_cm,
    d.weight_kg,
    ROUND(d.weight_kg / POWER(d.height_cm/100.0, 2), 1) as bmi,
    
    -- Baseline cognitive scores
    cb.mmse_total as baseline_mmse,
    cb.moca_total as baseline_moca,
    cb.digit_span_forward as baseline_ds_forward,
    cb.digit_span_backward as baseline_ds_backward,
    cb.trail_making_a_time as baseline_tmt_a,
    cb.trail_making_b_time as baseline_tmt_b,
    cb.verbal_fluency_animals as baseline_vf_animals,
    
    -- Month 6 cognitive scores (if available)
    c6.mmse_total as month6_mmse,
    c6.moca_total as month6_moca,
    c6.digit_span_forward as month6_ds_forward,
    c6.digit_span_backward as month6_ds_backward,
    c6.trail_making_a_time as month6_tmt_a,
    c6.trail_making_b_time as month6_tmt_b,
    c6.verbal_fluency_animals as month6_vf_animals,
    
    -- Derived change scores
    c6.mmse_total - cb.mmse_total as mmse_change,
    c6.moca_total - cb.moca_total as moca_change
    
  FROM subjects s
  LEFT JOIN demographics d ON s.subject_id = d.subject_id
  LEFT JOIN cognitive_assessments cb ON s.subject_id = cb.subject_id AND cb.visit_name = 'Baseline'
  LEFT JOIN cognitive_assessments c6 ON s.subject_id = c6.subject_id AND c6.visit_name = 'Month 6'
  WHERE s.status = 'Enrolled'
  ORDER BY s.subject_id
  "
  
  analysis_data <- dbGetQuery(con, analysis_query)
  dbDisconnect(con)
  
  # Save analysis dataset
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  filename <- file.path(output_dir, paste0("memory001_analysis_dataset_", timestamp, ".csv"))
  write.csv(analysis_data, filename, row.names = FALSE)
  
  cat("✅ Analysis dataset created:", filename, "\n")
  cat("📊 Subjects included:", nrow(analysis_data), "\n")
  cat("📈 Variables included:", ncol(analysis_data), "\n")
  
  return(analysis_data)
}

# Lock database for analysis
lock_database <- function(db_path = "data/memory001_study.db") {
  
  con <- dbConnect(SQLite(), db_path)
  
  # Create database lock record
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS database_locks (
      lock_id INTEGER PRIMARY KEY AUTOINCREMENT,
      lock_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      locked_by TEXT,
      lock_reason TEXT,
      unlock_timestamp TIMESTAMP NULL
    )")
  
  # Insert lock record
  dbExecute(con, "
    INSERT INTO database_locks (locked_by, lock_reason)
    VALUES (?, 'Final analysis lock')",
    params = list(Sys.info()["user"]))
  
  dbDisconnect(con)
  
  cat("🔒 Database locked for final analysis\n")
  cat("📅 Lock timestamp:", Sys.time(), "\n")
  cat("👤 Locked by:", Sys.info()["user"], "\n")
}

# Usage examples:
# export_study_data(export_format = "csv")
# export_study_data(export_format = "excel")
# analysis_data <- create_analysis_dataset()
# lock_database()
```

#### 8.2 Perform Final Data Export

```r
source("scripts/data_export.R")

# Export all data in multiple formats
csv_export <- export_study_data(export_format = "csv")
excel_export <- export_study_data(export_format = "excel")

# Create analysis-ready dataset
analysis_data <- create_analysis_dataset()

# Lock database for final analysis
lock_database()
```

## Database Management

### Database Schema

The MEMORY-001 study uses a relational database design with the following key tables:

- **study_info**: Study metadata and configuration
- **subjects**: Subject enrollment and randomization
- **demographics**: Baseline demographic data
- **cognitive_assessments**: Cognitive test scores by visit
- **visit_schedule**: Planned and actual visit dates
- **adverse_events**: Safety reporting
- **audit_trail**: Complete change history
- **validation_rules**: Data validation configuration
- **edc_users**: System user management

### Data Integrity

ZZedc ensures data integrity through:

1. **Database Constraints**: Foreign keys, check constraints, and required fields
2. **Real-time Validation**: Client-side and server-side validation
3. **Audit Trail**: Complete history of all data changes
4. **User Authentication**: Role-based access control
5. **Data Backups**: Automated backup procedures

### Backup and Recovery

```r
# Create backup
backup_database <- function(db_path = "data/memory001_study.db") {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  backup_path <- paste0("backups/memory001_backup_", timestamp, ".db")
  
  if (!dir.exists("backups")) {
    dir.create("backups", recursive = TRUE)
  }
  
  file.copy(db_path, backup_path)
  cat("✅ Database backed up to:", backup_path, "\n")
}

# Schedule daily backups (cron job example)
# 0 2 * * * /usr/bin/Rscript /path/to/backup_script.R
```

## User Management and Security

### User Roles

ZZedc supports the following user roles:

1. **Administrator**: Full system access, user management
2. **Principal Investigator**: Study oversight, data review
3. **Research Coordinator**: Data entry, subject management
4. **Data Manager**: Data quality, validation, export
5. **Monitor**: Read-only access for monitoring

### Security Features

- **Password Encryption**: Secure password hashing
- **Session Management**: Automatic timeout and session security
- **Audit Trail**: Complete activity logging
- **Access Control**: Role-based permissions
- **Data Encryption**: Encrypted data storage

### Password Management

```r
# Create secure password hash
library(digest)

create_user <- function(username, password, full_name, email, role) {
  # Hash password securely
  password_hash <- digest(paste0(password, "salt_string"), algo = "sha256")
  
  # Insert into database (pseudo-code)
  # dbExecute(con, "INSERT INTO edc_users ...")
}
```

## Data Entry Workflows

### Standard Operating Procedures

#### Subject Enrollment
1. Verify eligibility criteria
2. Obtain informed consent
3. Assign subject ID
4. Complete enrollment form
5. Randomize to treatment group
6. Schedule baseline visit

#### Data Entry
1. Login to EDC system
2. Select subject and visit
3. Complete required forms
4. Validate data entry
5. Save and submit forms
6. Review for completeness

#### Quality Control
1. Real-time validation during entry
2. Daily data review by coordinator
3. Weekly quality reports
4. Monthly data management review
5. Query resolution process

### Form Validation Rules

ZZedc implements multiple validation levels:

```r
# Example validation rules
validation_examples <- list(
  # Range validation
  age = list(min = 18, max = 85, message = "Age must be between 18 and 85"),
  
  # Format validation
  subject_id = list(pattern = "^MEM-\\d{3}$", message = "Format: MEM-001"),
  
  # Logic validation
  end_date = list(condition = "end_date >= start_date", message = "End date must be after start date"),
  
  # Required field validation
  consent_date = list(required = TRUE, message = "Consent date is required")
)
```

## Quality Control and Reporting

### Automated Quality Checks

ZZedc performs continuous quality monitoring:

1. **Completeness**: Missing required fields
2. **Consistency**: Logical data relationships
3. **Accuracy**: Range and format validation
4. **Timeliness**: Visit window compliance

### Quality Metrics

Key metrics tracked include:

- **Data Completeness Rate**: % of required fields completed
- **Query Rate**: Number of data queries per 100 fields
- **Visit Compliance**: % of visits within protocol windows
- **Form Lock Rate**: % of forms locked and verified

### Report Types

#### Basic Reports
- Enrollment summary
- Visit completion status
- Form completion rates
- Subject disposition

#### Quality Reports
- Missing data summary
- Range violations
- Logic check failures
- Audit trail summaries

#### Statistical Reports
- Baseline characteristics table
- Randomization balance tests
- Efficacy analysis summaries
- Safety summaries

## Data Export and Analysis

### Export Formats

ZZedc supports multiple export formats:

1. **CSV**: Comma-separated values for statistical software
2. **Excel**: Multi-sheet workbooks with formatting
3. **JSON**: Structured data for web applications
4. **SAS**: Direct export to SAS datasets
5. **SPSS**: SPSS-compatible format

### Analysis Integration

```r
# Example: Export for R analysis
export_for_r <- function() {
  analysis_data <- create_analysis_dataset()
  
  # Create R script for analysis
  r_script <- '
  # MEMORY-001 Analysis Script
  # Generated automatically by ZZedc
  
  library(dplyr)
  library(ggplot2)
  library(tableone)
  
  # Load data
  data <- read.csv("memory001_analysis_dataset.csv")
  
  # Create baseline characteristics table
  baseline_vars <- c("age", "gender", "education_years", "baseline_mmse", "baseline_moca")
  baseline_table <- CreateTableOne(vars = baseline_vars, 
                                  strata = "randomization_group", 
                                  data = data)
  
  # Primary efficacy analysis
  primary_model <- lm(mmse_change ~ randomization_group + baseline_mmse + age, data = data)
  summary(primary_model)
  '
  
  writeLines(r_script, "exports/analysis_script.R")
  cat("✅ R analysis script created\n")
}
```

## Best Practices

### Study Setup
1. **Plan Database Schema**: Design tables before data collection
2. **Define Validation Rules**: Implement comprehensive validation
3. **Test System**: Thoroughly test before go-live
4. **Train Users**: Provide comprehensive training
5. **Document Procedures**: Maintain detailed SOPs

### Data Management
1. **Regular Backups**: Daily automated backups
2. **Quality Reviews**: Weekly data quality reports
3. **Query Management**: Prompt query resolution
4. **Version Control**: Track all system changes
5. **Access Control**: Implement least privilege principle

### Compliance
1. **Audit Trail**: Maintain complete audit trail
2. **Validation**: Validate all system components
3. **Documentation**: Document all procedures
4. **Security**: Implement robust security measures
5. **Backup**: Maintain validated backup procedures

### Performance
1. **Database Optimization**: Regular database maintenance
2. **Response Time**: Monitor system performance
3. **Scalability**: Plan for study growth
4. **Resource Management**: Monitor system resources
5. **User Experience**: Optimize for usability

## Troubleshooting

### Common Issues

#### Database Connection Errors
```r
# Check database connectivity
test_db_connection <- function(db_path = "data/memory001_study.db") {
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    result <- dbGetQuery(con, "SELECT COUNT(*) as count FROM subjects")
    dbDisconnect(con)
    cat("✅ Database connection successful\n")
    cat("📊 Total subjects:", result$count, "\n")
  }, error = function(e) {
    cat("❌ Database connection failed:", e$message, "\n")
  })
}
```

#### Performance Issues
```r
# Database maintenance
optimize_database <- function(db_path = "data/memory001_study.db") {
  con <- dbConnect(SQLite(), db_path)
  
  # Analyze database statistics
  dbExecute(con, "ANALYZE")
  
  # Vacuum database to reclaim space
  dbExecute(con, "VACUUM")
  
  # Update table statistics
  dbExecute(con, "PRAGMA optimize")
  
  dbDisconnect(con)
  cat("✅ Database optimized\n")
}
```

#### User Access Issues
```r
# Reset user password
reset_user_password <- function(username, new_password) {
  password_hash <- digest(paste0(new_password, "salt_string"), algo = "sha256")
  
  con <- dbConnect(SQLite(), "data/memory001_study.db")
  
  dbExecute(con, "UPDATE edc_users SET password_hash = ? WHERE username = ?",
           params = list(password_hash, username))
  
  dbDisconnect(con)
  cat("✅ Password reset for user:", username, "\n")
}
```

### Support Resources

1. **Documentation**: Complete user guides and technical documentation
2. **Training**: Video tutorials and hands-on training sessions
3. **Support**: Email and phone support during business hours
4. **Community**: User forums and community support
5. **Updates**: Regular system updates and bug fixes

### System Monitoring

```r
# System health check
system_health_check <- function() {
  
  checks <- list()
  
  # Database check
  checks$database <- tryCatch({
    test_db_connection()
    "OK"
  }, error = function(e) paste("ERROR:", e$message))
  
  # Disk space check
  checks$disk_space <- if (file.exists("data/memory001_study.db")) {
    size_mb <- file.info("data/memory001_study.db")$size / 1024 / 1024
    paste(round(size_mb, 1), "MB")
  } else {
    "Database file not found"
  }
  
  # User session check
  checks$active_sessions <- "Monitoring not implemented"
  
  cat("🏥 System Health Check\n")
  cat("=====================\n")
  cat("Database status:", checks$database, "\n")
  cat("Database size:", checks$disk_space, "\n")
  cat("Active sessions:", checks$active_sessions, "\n")
  cat("Check time:", Sys.time(), "\n")
  
  return(checks)
}

# Schedule regular health checks
# system_health_check()
```

## Conclusion

ZZedc provides a comprehensive, secure, and user-friendly platform for electronic data capture in clinical trials. This guide has walked through setting up a complete EDC system for a small clinical trial, from initial database design through final data export and analysis.

Key benefits of using ZZedc include:

- **Cost-effective**: Open-source alternative to expensive commercial EDC systems
- **Flexible**: Highly customizable to meet specific study requirements
- **Compliant**: Built with regulatory compliance in mind
- **Modern**: Uses state-of-the-art web technologies for optimal user experience
- **Scalable**: Can grow from small pilot studies to large multi-site trials

For additional support and advanced configurations, refer to the complete ZZedc documentation or contact the development team.

---

*This guide was created for ZZedc version 1.0.0. For the latest documentation and updates, visit the project repository.*