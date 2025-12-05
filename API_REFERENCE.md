# ZZedc v1.1 API Reference Guide

## Complete API Documentation for Developers

This guide provides detailed documentation of all public functions in ZZedc v1.1. Each function includes purpose, parameters, return values, and code examples.

---

## Table of Contents

### Feature #1: Instruments Library
- [list_available_instruments()](#list_available_instruments)
- [load_instrument_template()](#load_instrument_template)
- [import_instrument()](#import_instrument)
- [get_instrument_field()](#get_instrument_field)
- [validate_instrument_csv()](#validate_instrument_csv)

### Feature #2: Enhanced Field Types & Validation
- [renderPanel()](#renderpanel)
- [validate_form()](#validate_form)
- [setup_form_validation()](#setup_form_validation)
- [validate_field_value()](#validate_field_value)

### Feature #3: Quality Dashboard
- [quality_dashboard_ui()](#quality_dashboard_ui)
- [quality_dashboard_server()](#quality_dashboard_server)

### Feature #4: Branching Logic
- [is_field_visible()](#is_field_visible)

### Feature #5: Multi-Format Export
- [prepare_export_data()](#prepare_export_data)
- [export_to_file()](#export_to_file)
- [generate_export_filename()](#generate_export_filename)
- [log_export_event()](#log_export_event)

### Utilities & Helpers
- [launch_zzedc()](#launch_zzedc)
- [validate_filename()](#validate_filename)
- [log_audit_event()](#log_audit_event)
- [init_audit_log()](#init_audit_log)

---

## Feature #1: Instruments Library

### list_available_instruments()

**Description**: Get a list of all available pre-built instruments

**Usage**:
```r
instruments <- list_available_instruments()
```

**Parameters**: None

**Returns**: List with three elements:
- `names`: Character vector of instrument codes
- `labels`: Human-readable instrument names
- `item_counts`: Number of items in each instrument
- `descriptions`: Purpose of each instrument

**Examples**:
```r
# Get all instruments
all_instruments <- list_available_instruments()

# Display available instruments
print(all_instruments$labels)
# [1] "Patient Health Questionnaire (PHQ-9)"
# [2] "Generalized Anxiety Disorder (GAD-7)"
# [3] "Depression Anxiety Stress Scale (DASS-21)"
# [4] "Short Form Health Survey (SF-36)"
# [5] "AUDIT-C Alcohol Use Disorder"
# [6] "STOP-BANG Sleep Apnea"

# Get item count for PHQ-9
phq9_items <- all_instruments$item_counts[1]
# [1] 9
```

**See Also**:
- `load_instrument_template()` - Load the actual instrument
- `import_instrument()` - Import into database

---

### load_instrument_template()

**Description**: Load a specific instrument template as a data frame

**Usage**:
```r
instrument <- load_instrument_template(instrument_name)
```

**Parameters**:
- `instrument_name` (character): Name or code of instrument (e.g., "phq9", "gad7")

**Returns**: Data frame with columns:
- `field_name`: Unique field identifier
- `field_label`: Display label
- `field_type`: Input type (select, text, numeric, etc.)
- `validation_rules`: JSON with validation constraints
- `description`: Help text
- `required`: Whether field is required
- And any additional metadata columns

**Examples**:
```r
# Load PHQ-9 instrument
phq9 <- load_instrument_template("phq9")

# View first few fields
head(phq9)
# field_name           field_label field_type validation_rules required
# phq9_q1              Little interest or pleasure select {...} TRUE
# phq9_q2              Feeling down or depressed  select {...} TRUE
# ...

# Count number of questions
nrow(phq9)  # [1] 9

# View specific question
phq9[1, "field_label"]
# [1] "Little interest or pleasure in doing things?"

# Check answer options for first question
phq9[1, "validation_rules"]
# {"choices": ["0 - Not at all", "1 - Several days", "2 - More than half", "3 - Nearly every day"]}
```

**Validation Rules**: JSON format with question-specific options
```r
# Example: Multiple choice question
# {"choices": ["Option A", "Option B", "Option C"]}

# Example: Numeric with range
# {"type": "numeric", "min": 0, "max": 100, "step": 1}

# Example: Date validation
# {"type": "date", "min": "1900-01-01", "max": "2024-12-31"}
```

**See Also**:
- `validate_instrument_csv()` - Validate instrument CSV
- `import_instrument()` - Import into database

---

### import_instrument()

**Description**: Import an instrument into the database as a new form

**Usage**:
```r
result <- import_instrument(instrument_name, form_name, form_description, db_conn)
```

**Parameters**:
- `instrument_name` (character): Name of instrument (e.g., "phq9")
- `form_name` (character): Name for form in database
- `form_description` (character): Optional description
- `db_conn` (database connection): Active database connection

**Returns**: List with elements:
- `success` (logical): TRUE if import successful
- `message` (character): Confirmation or error message
- `form_id` (integer): ID of newly created form (if successful)

**Examples**:
```r
library(RSQLite)
db_conn <- dbConnect(SQLite(), "data/study.db")

# Import PHQ-9 as baseline screening form
result <- import_instrument("phq9",
                           form_name = "Baseline PHQ-9",
                           form_description = "Depression screening at baseline visit",
                           db_conn = db_conn)

if (result$success) {
  cat("Form imported! ID:", result$form_id)
  # Form imported! ID: 42
} else {
  cat("Error:", result$message)
}

# Import GAD-7 with minimal parameters
result2 <- import_instrument("gad7", "Screening GAD-7", "", db_conn)

dbDisconnect(db_conn)
```

**Error Handling**:
```r
result <- import_instrument("nonexistent", "Form", "", db_conn)
# Error: 'nonexistent' instrument not found

result <- import_instrument("phq9", "Duplicate", "", db_conn)
# If form name already exists:
# List with success=FALSE, message="Form name already exists"
```

**See Also**:
- `list_available_instruments()` - List available instruments
- `load_instrument_template()` - Load template before import

---

### get_instrument_field()

**Description**: Get a specific field from an instrument

**Usage**:
```r
field <- get_instrument_field(instrument_name, field_name)
```

**Parameters**:
- `instrument_name` (character): Instrument code (e.g., "phq9")
- `field_name` (character): Name of field to retrieve

**Returns**: List containing:
- `field_name`: Name of field
- `field_label`: Display label
- `field_type`: Type of input
- `validation_rules`: Validation constraints
- `description`: Help text
- `required`: Whether required

**Examples**:
```r
# Get first PHQ-9 question
field <- get_instrument_field("phq9", "phq9_q1")

# View the label
field$field_label
# [1] "Little interest or pleasure in doing things?"

# View validation/answer choices
field$validation_rules
# {"choices": ["0 - Not at all", "1 - Several days", "2 - More than half", "3 - Nearly every day"]}

# Check if it's required
field$required
# [1] TRUE

# Use in form rendering
metadata <- list()
metadata[[field$field_name]] <- list(
  type = field$field_type,
  label = field$field_label,
  required = field$required
)
```

**Error Handling**:
```r
# Field doesn't exist
get_instrument_field("phq9", "nonexistent_field")
# Returns NULL or error message
```

**See Also**:
- `load_instrument_template()` - Load entire instrument
- `list_available_instruments()` - Find instrument codes

---

### validate_instrument_csv()

**Description**: Validate that an instrument CSV has correct format

**Usage**:
```r
validation <- validate_instrument_csv(filepath)
```

**Parameters**:
- `filepath` (character): Path to CSV file

**Returns**: List with elements:
- `valid` (logical): TRUE if CSV is valid
- `errors` (character vector): Any validation errors found
- `warnings` (character vector): Any warnings
- `missing_columns` (character vector): Required columns that are missing

**Required Columns**:
- `field_name`: Unique identifier
- `field_label`: Display name
- `field_type`: Input type
- `required`: TRUE/FALSE

**Optional Columns**:
- `validation_rules`: JSON validation rules
- `description`: Help text
- `choices`: Answer options (for select fields)

**Examples**:
```r
# Validate a custom instrument CSV
validation <- validate_instrument_csv("my_instrument.csv")

if (validation$valid) {
  cat("CSV is valid!")
} else {
  cat("Errors found:\n")
  print(validation$errors)
  cat("\nMissing columns:\n")
  print(validation$missing_columns)
}

# Example valid result
# $valid
# [1] TRUE
#
# $errors
# character(0)
#
# $warnings
# [1] "field_type 'textarea' not in standard types - may not render correctly"
```

**CSV Format Example**:
```csv
field_name,field_label,field_type,required,validation_rules,description
q1,"What is your age?",numeric,TRUE,"{""min"": 18, ""max"": 120}",Age in years
q2,"Select your gender",select,TRUE,"{""choices"": [""M"", ""F"", ""Other""]}",Gender
q3,"Notes",textarea,FALSE,"","Additional comments"
```

**See Also**:
- `load_instrument_template()` - Load validated instrument
- `import_instrument()` - Import into database

---

## Feature #2: Enhanced Field Types & Validation

### renderPanel()

**Description**: Render form input fields based on metadata

**Usage**:
```r
fields <- renderPanel(fields, field_metadata)
```

**Parameters**:
- `fields` (character vector): Names of fields to render
- `field_metadata` (list): Configuration for each field

**Returns**: List of Shiny input controls (one per field)

**Supported Field Types**:
- `text`: Text input
- `email`: Email input
- `numeric`: Number input with optional range
- `date`: Date picker
- `datetime`: Date + time picker
- `time`: Time picker
- `select`: Dropdown selection
- `radio`: Radio button group
- `checkbox`: Single checkbox
- `checkbox_group`: Multiple checkboxes
- `textarea`: Multi-line text
- `notes`: Notes field (6 rows)
- `slider`: Numeric slider
- `file`: File upload
- `signature`: Signature capture

**Field Configuration Options**:
```r
list(
  field_name = list(
    type = "text",              # Required: field type
    label = "Display Label",     # Optional: label
    required = TRUE,             # Optional: is required?
    value = "default",           # Optional: default value
    placeholder = "Enter...",    # Optional: placeholder text
    help = "Help text",          # Optional: help text

    # Type-specific options:
    min = 0,                     # numeric, slider, date
    max = 100,                   # numeric, slider, date
    step = 1,                    # numeric, slider
    choices = c("A", "B"),       # select, radio, checkbox_group
    multiple = FALSE,            # select
    inline = FALSE,              # radio, checkbox_group
    rows = 4,                    # textarea, notes
    cols = 50,                   # textarea, notes
    accept = ".pdf,.doc",        # file
    width = "100%",              # file, signature
    height = "200px",            # signature

    # Branching logic:
    show_if = "gender == 'Female'",  # Show if condition
    hide_if = "age < 18"             # Hide if condition
  )
)
```

**Examples**:
```r
# Simple text and email fields
metadata <- list(
  name = list(type = "text", label = "Full Name", required = TRUE),
  email = list(type = "email", label = "Email Address")
)
renderPanel(c("name", "email"), metadata)

# Advanced example with multiple types
metadata <- list(
  pain = list(
    type = "slider",
    label = "Pain Level",
    min = 0,
    max = 10,
    value = 5
  ),
  symptoms = list(
    type = "checkbox_group",
    label = "Symptoms (select all)",
    choices = c("Pain", "Fever", "Cough", "Nausea"),
    required = TRUE
  ),
  notes = list(
    type = "textarea",
    label = "Additional Notes",
    rows = 6,
    placeholder = "Enter clinical observations..."
  ),
  lab_results = list(
    type = "file",
    label = "Upload Lab Results",
    accept = ".pdf,.jpg",
    required = FALSE
  )
)

renderPanel(names(metadata), metadata)

# With branching logic
metadata <- list(
  gender = list(
    type = "select",
    label = "Gender",
    choices = c("Male", "Female", "Other")
  ),
  pregnancy_date = list(
    type = "date",
    label = "Pregnancy Due Date",
    show_if = "gender == 'Female'",  # Only show for females
    required = TRUE
  )
)
renderPanel(names(metadata), metadata)
```

**In Shiny Context**:
```r
library(shiny)
library(zzedc)

ui <- fluidPage(
  h1("Clinical Form"),
  renderPanel(c("age", "pain", "symptoms"), metadata),
  actionButton("submit", "Submit")
)

server <- function(input, output, session) {
  # Access field values via input$field_name
  observeEvent(input$submit, {
    form_data <- list(
      age = input$age,
      pain = input$pain,
      symptoms = input$symptoms
    )
    cat("Submitted:", toJSON(form_data))
  })
}

shinyApp(ui, server)
```

**See Also**:
- `validate_form()` - Validate form submission
- `setup_form_validation()` - Setup validation

---

### validate_form()

**Description**: Validate all fields in a form

**Usage**:
```r
result <- validate_form(form_data, form_fields)
```

**Parameters**:
- `form_data` (list): Form values (e.g., `input` list)
- `form_fields` (list): Field definitions with validation rules

**Returns**: List with elements:
- `valid` (logical): TRUE if all validations pass
- `errors` (character vector): Description of each error
- `invalid_fields` (character vector): Names of invalid fields

**Examples**:
```r
form_fields <- list(
  email = list(type = "email", required = TRUE),
  age = list(type = "numeric", required = TRUE, min = 18, max = 120),
  consent = list(type = "checkbox", required = TRUE)
)

# Valid submission
form_data <- list(email = "john@example.com", age = 30, consent = TRUE)
result <- validate_form(form_data, form_fields)
# result$valid = TRUE
# result$errors = character(0)

# Invalid submission (age too low)
form_data <- list(email = "jane@example.com", age = 16, consent = TRUE)
result <- validate_form(form_data, form_fields)
# result$valid = FALSE
# result$errors = "age must be between 18 and 120"
# result$invalid_fields = "age"

# Missing required field
form_data <- list(email = "", age = 30, consent = TRUE)
result <- validate_form(form_data, form_fields)
# result$valid = FALSE
# result$errors = "email is required"
```

**Validation Rules**:
```
- required = TRUE: Field must not be empty
- type = "email": Must be valid email format
- type = "numeric": Must be a number
- min/max: Numeric range validation
- type = "date": Must be valid date
- choices: Value must be in allowed list
```

**See Also**:
- `validate_field_value()` - Validate single field
- `setup_form_validation()` - Setup auto-validation
- `renderPanel()` - Render form fields

---

### setup_form_validation()

**Description**: Setup automatic form validation with error display

**Usage**:
```r
setup_form_validation(input, output, session, form_fields)
```

**Parameters**:
- `input` (Shiny input object): Reactive input values
- `output` (Shiny output object): Reactive outputs
- `session` (Shiny session): Session object
- `form_fields` (list): Field definitions with validation rules

**Returns**: None (sets up observers)

**Side Effects**: Creates reactive validation that:
- Validates on form submission
- Displays error messages
- Highlights invalid fields
- Prevents submission if invalid

**Shiny Integration**:
```r
library(shiny)
library(zzedc)

ui <- fluidPage(
  h1("Registration Form"),
  textInput("name", "Name", placeholder = "Enter your name"),
  emailInput("email", "Email", placeholder = "user@example.com"),
  numericInput("age", "Age", value = 30),
  uiOutput("validation_errors"),
  actionButton("submit", "Submit")
)

server <- function(input, output, session) {
  form_fields <- list(
    name = list(type = "text", required = TRUE),
    email = list(type = "email", required = TRUE),
    age = list(type = "numeric", required = TRUE, min = 18, max = 120)
  )

  # Setup automatic validation
  setup_form_validation(input, output, session, form_fields)

  observeEvent(input$submit, {
    # Validation already done by setup_form_validation
    cat("Form submitted!")
  })
}

shinyApp(ui, server)
```

**See Also**:
- `validate_form()` - Manual validation
- `create_error_display()` - Display error messages
- `renderPanel()` - Render fields

---

### validate_field_value()

**Description**: Validate a single field value

**Usage**:
```r
result <- validate_field_value(field_name, value, field_config)
```

**Parameters**:
- `field_name` (character): Name of field
- `value` (any): Value to validate
- `field_config` (list): Field configuration with validation rules

**Returns**: List with elements:
- `valid` (logical): TRUE if valid
- `message` (character): Error message if invalid

**Examples**:
```r
# Validate email
result <- validate_field_value(
  "email",
  "invalid.email",
  list(type = "email", required = TRUE)
)
# result$valid = FALSE
# result$message = "email must be valid email format"

# Validate numeric range
result <- validate_field_value(
  "age",
  150,
  list(type = "numeric", min = 0, max = 120)
)
# result$valid = FALSE
# result$message = "age must be between 0 and 120"

# Validate required field
result <- validate_field_value(
  "name",
  "",
  list(type = "text", required = TRUE)
)
# result$valid = FALSE
# result$message = "name is required"

# Valid value
result <- validate_field_value(
  "age",
  30,
  list(type = "numeric", min = 0, max = 120)
)
# result$valid = TRUE
# result$message = ""
```

**See Also**:
- `validate_form()` - Validate entire form
- `setup_form_validation()` - Setup auto-validation

---

## Feature #3: Quality Dashboard

### quality_dashboard_ui()

**Description**: Create UI for quality dashboard

**Usage**:
```r
quality_dashboard_ui(id)
```

**Parameters**:
- `id` (character): Shiny module namespace ID

**Returns**: Shiny UI element containing:
- 4 metric cards (total, complete, incomplete %, issues)
- 3 interactive charts
- QC flags and recommendations

**Example**:
```r
library(shiny)
library(zzedc)

ui <- fluidPage(
  h1("Study Dashboard"),
  quality_dashboard_ui("dashboard")
)

server <- function(input, output, session) {
  # Module server called separately
}

shinyApp(ui, server)
```

**See Also**:
- `quality_dashboard_server()` - Server-side logic
- Module usage in ZZedc main app

---

### quality_dashboard_server()

**Description**: Server-side logic for quality dashboard

**Usage**:
```r
quality_dashboard_server(id, db_conn, refresh_interval = 60000)
```

**Parameters**:
- `id` (character): Module namespace ID (must match UI)
- `db_conn` (database connection): Active database connection
- `refresh_interval` (numeric): Milliseconds between updates (default: 60000 = 60 seconds)

**Returns**: Reactive list with dashboard metrics

**Example**:
```r
server <- function(input, output, session) {
  db_conn <- dbConnect(SQLite(), "data/study.db")

  # Initialize dashboard with 30-second refresh
  metrics <- quality_dashboard_server("dashboard", db_conn, refresh_interval = 30000)

  onStop(function() {
    dbDisconnect(db_conn)
  })
}
```

**Returned Metrics** (in reactive list):
- `total_records`: Total participants
- `complete_records`: Completed participants
- `incomplete_pct`: Percentage incomplete
- `flagged_issues`: Number of issues detected
- `form_completeness`: Per-form completion %
- `timeline_data`: Enrollment over time
- `missing_summary`: Fields with most missing data

**See Also**:
- `quality_dashboard_ui()` - Create UI
- Module usage in home_module.R

---

## Feature #4: Branching Logic

### is_field_visible()

**Description**: Determine if field should be visible based on form values

**Usage**:
```r
visible <- is_field_visible(field_name, field_config, form_values)
```

**Parameters**:
- `field_name` (character): Name of field to check
- `field_config` (list): Field configuration with show_if/hide_if rules
- `form_values` (list): Current form values

**Returns**: Logical, TRUE if field should be visible

**Examples**:
```r
field_config <- list(
  show_if = "gender == 'Female'"
)
form_values <- list(gender = "Female")

is_field_visible("pregnancy_date", field_config, form_values)
# [1] TRUE

form_values <- list(gender = "Male")
is_field_visible("pregnancy_date", field_config, form_values)
# [1] FALSE

# Field with no visibility rules is always visible
field_config <- list()  # No show_if or hide_if
is_field_visible("name", field_config, form_values)
# [1] TRUE
```

**Condition Operators**:
- `==`: Equals
- `!=`: Not equals
- `<`: Less than
- `>`: Greater than
- `<=`: Less than or equal
- `>=`: Greater than or equal
- `in`: Value in list

**Examples with Different Operators**:
```r
# Check if age > 18
field_config <- list(show_if = "age > 18")
is_field_visible("field", field_config, list(age = 25))  # TRUE

# Check if status != "inactive"
field_config <- list(show_if = "status != 'inactive'")
is_field_visible("field", field_config, list(status = "active"))  # TRUE

# Check if state in list
field_config <- list(show_if = "state in ('CA', 'NY', 'TX')")
is_field_visible("field", field_config, list(state = "CA"))  # TRUE
```

**See Also**:
- Branching logic documentation in USER_TRAINING_GUIDES.md
- `validate_form_with_branching()` - Validation with branching

---

## Feature #5: Multi-Format Export

### prepare_export_data()

**Description**: Prepare data for export (retrieve and format)

**Usage**:
```r
export_prep <- prepare_export_data(data_source, format, options = NULL, db_conn = NULL)
```

**Parameters**:
- `data_source` (character): Data source - "edc", "sample", "reports", "all_files"
- `format` (character): Export format - "csv", "xlsx", "json", "sas", "spss", "stata", "rds", "pdf", "html"
- `options` (list, optional): Configuration options
- `db_conn` (database connection, optional): Required for "edc" source

**Returns**: List with elements:
- `data`: Data frame or list with export data
- `info`: Metadata about export
- `warnings`: Any issues encountered

**Options**:
```r
options = list(
  include_metadata = TRUE,        # Include who/when entered
  include_timestamps = TRUE,      # Include entry timestamps
  date_range = c("2024-01-01", "2024-12-31"),  # Date range
  include_summary = FALSE         # For reports source
)
```

**Examples**:
```r
library(RSQLite)
db_conn <- dbConnect(SQLite(), "data/study.db")

# Export EDC data with metadata and timestamps
result <- prepare_export_data(
  "edc",
  "csv",
  options = list(
    include_metadata = TRUE,
    include_timestamps = TRUE,
    date_range = c("2024-01-01", Sys.Date())
  ),
  db_conn = db_conn
)

cat("Exporting", nrow(result$data), "records\n")
cat("Columns:", ncol(result$data), "\n")
head(result$data)

# Export sample data (for testing)
sample_result <- prepare_export_data("sample", "csv")

dbDisconnect(db_conn)
```

**See Also**:
- `export_to_file()` - Write data to file
- `generate_export_filename()` - Create safe filename

---

### export_to_file()

**Description**: Export data to specified file format

**Usage**:
```r
result <- export_to_file(data, filepath, format, options = NULL)
```

**Parameters**:
- `data` (data.frame): Data to export
- `filepath` (character): Path where to save file
- `format` (character): Export format
- `options` (list, optional): Format-specific options

**Supported Formats**:
- CSV, XLSX, JSON, SAS, SPSS, STATA, RDS, PDF, HTML

**Returns**: List with elements:
- `success` (logical): TRUE if export successful
- `filepath` (character): Path to exported file
- `message` (character): Status message

**Examples**:
```r
# Create sample data
data <- data.frame(
  id = 1:100,
  name = paste0("Patient_", 1:100),
  age = sample(18:80, 100),
  score = rnorm(100, mean = 50, sd = 15)
)

# Export to CSV
result <- export_to_file(data, "export/data.csv", "csv")
if (result$success) {
  cat("Exported:", result$filepath, "\n")
}

# Export to Excel
result <- export_to_file(data, "export/data.xlsx", "xlsx")

# Export to R RDS format
result <- export_to_file(data, "export/data.rds", "rds")

# Export to SAS (requires haven package)
result <- export_to_file(data, "export/data.xpt", "sas")
if (!result$success) {
  cat("Error:", result$message, "\n")  # May need haven installed
}

# Export to SPSS
result <- export_to_file(data, "export/data.sav", "spss")

# Export to Stata
result <- export_to_file(data, "export/data.dta", "stata")
```

**Format-Specific Behavior**:
```r
# CSV: Simple text format, universal compatibility
export_to_file(data, "file.csv", "csv")

# XLSX: Excel format with formatting support
export_to_file(data, "file.xlsx", "xlsx")

# RDS: R binary format, preserves types, compressed
export_to_file(data, "file.rds", "rds")

# SAS: SAS transport format (.xpt), needs haven
export_to_file(data, "file.xpt", "sas")

# SPSS: SPSS data format (.sav), needs haven
export_to_file(data, "file.sav", "spss")

# Stata: Stata format (.dta), needs haven
export_to_file(data, "file.dta", "stata")
```

**Error Handling**:
```r
# Missing package
result <- export_to_file(data, "file.sav", "spss")
if (!result$success && grepl("haven", result$message)) {
  cat("Install haven package: install.packages('haven')\n")
}

# Invalid data type
list_data <- list(a = 1:10, b = letters[1:10])
result <- export_to_file(list_data, "file.csv", "csv")
# May fail because CSV requires data.frame
```

**See Also**:
- `prepare_export_data()` - Prepare data first
- `generate_export_filename()` - Create safe filename

---

### generate_export_filename()

**Description**: Generate safe, timestamped export filename

**Usage**:
```r
filename <- generate_export_filename(base_name, data_source, format)
```

**Parameters**:
- `base_name` (character): Base filename (optional)
- `data_source` (character): Data source identifier
- `format` (character): Export format

**Returns**: Character string with safe filename including timestamp

**Examples**:
```r
# Auto-generate filename
filename <- generate_export_filename(NULL, "edc", "csv")
# Result: "edc_export_20241205.csv"

# Custom base name
filename <- generate_export_filename("mydata", "edc", "xlsx")
# Result: "mydata_edc_20241205.xlsx"

# Different formats
generate_export_filename("study", "reports", "pdf")
# Result: "study_reports_20241205.pdf"

generate_export_filename("trial", "edc", "rds")
# Result: "trial_edc_20241205.rds"

generate_export_filename("analysis", "edc", "sas")
# Result: "analysis_edc_20241205.xpt"  # Note: .xpt for SAS
```

**Filename Format**: `{base_name}_{data_source}_{YYYYMMDD}.{extension}`

**Extension Mapping**:
```r
csv  → .csv
xlsx → .xlsx
json → .json
pdf  → .pdf
html → .html
rds  → .rds
sas  → .xpt        # SAS transport format
spss → .sav        # SPSS format
stata → .dta       # Stata format
```

**Safety Features**:
- Removes special characters from base_name
- Prevents directory traversal (../ not allowed)
- Adds timestamp to prevent overwriting
- Uses standard extensions

**See Also**:
- `export_to_file()` - Export data to file
- `prepare_export_data()` - Prepare data

---

### log_export_event()

**Description**: Log data export to audit trail

**Usage**:
```r
log_export_event(user_id, data_source, format, rows, audit_log)
```

**Parameters**:
- `user_id` (character): ID of user performing export
- `data_source` (character): Source of exported data
- `format` (character): Export format
- `rows` (numeric): Number of rows exported
- `audit_log` (reactiveVal): Audit log from init_audit_log()

**Returns**: None (updates audit log)

**Examples**:
```r
audit_log <- init_audit_log()

log_export_event(
  user_id = "researcher@example.com",
  data_source = "edc",
  format = "csv",
  rows = 150,
  audit_log = audit_log
)

# View audit log
log_data <- query_audit_log(audit_log)
tail(log_data)
# Shows export event with timestamp
```

**See Also**:
- `init_audit_log()` - Initialize audit log
- `log_audit_event()` - General audit logging

---

## Utilities & Helpers

### launch_zzedc()

**Description**: Launch the ZZedc application

**Usage**:
```r
launch_zzedc(port = 3838, ...)
```

**Parameters**:
- `port` (numeric): Port to run app on (default: 3838)
- `...`: Additional arguments to shinyApp()

**Returns**: None (starts Shiny app)

**Examples**:
```r
# Default launch
library(zzedc)
launch_zzedc()

# Custom port
launch_zzedc(port = 8080)

# With additional Shiny options
launch_zzedc(
  port = 3838,
  launch.browser = TRUE,
  host = "0.0.0.0"
)
```

**See Also**:
- ZZedc User Training Guide
- RELEASE_NOTES_v1.1.md

---

### validate_filename()

**Description**: Sanitize filename to prevent security issues

**Usage**:
```r
safe_name <- validate_filename(filename)
```

**Parameters**:
- `filename` (character): Filename to sanitize

**Returns**: Character string with safe filename

**Examples**:
```r
# Removes special characters
validate_filename("../../../etc/passwd")
# Result: "etcpasswd"

validate_filename("My Study Data (v2).csv")
# Result: "My_Study_Data_v2.csv"

# Prevents directory traversal
validate_filename("../malicious/path.csv")
# Result: "maliciouspath.csv"
```

**See Also**:
- `generate_export_filename()` - Create export filenames

---

### log_audit_event()

**Description**: Log event to audit trail for compliance

**Usage**:
```r
log_audit_event(user_id, action, resource, details = NULL, status = "success")
```

**Parameters**:
- `user_id` (character): User ID
- `action` (character): Action performed (e.g., "LOGIN", "DATA_EXPORT", "FORM_SUBMIT")
- `resource` (character): Resource affected (e.g., form name, data field)
- `details` (character, optional): Additional details
- `status` (character): "success" or "failed"

**Returns**: None (updates audit log)

**Examples**:
```r
audit_log <- init_audit_log()

# Log login
log_audit_event(
  user_id = "jsmith@example.com",
  action = "LOGIN",
  resource = "system",
  status = "success",
  audit_log = audit_log
)

# Log form submission
log_audit_event(
  user_id = "coordinator@example.com",
  action = "FORM_SUBMIT",
  resource = "PHQ-9 Screening",
  details = "Subject ID: STUDY-001",
  status = "success",
  audit_log = audit_log
)

# Log failed access
log_audit_event(
  user_id = "unknown",
  action = "LOGIN",
  resource = "system",
  details = "Invalid password",
  status = "failed",
  audit_log = audit_log
)
```

**See Also**:
- `init_audit_log()` - Initialize audit log
- `query_audit_log()` - Query audit records

---

### init_audit_log()

**Description**: Initialize audit logging system

**Usage**:
```r
audit_log <- init_audit_log()
```

**Parameters**: None

**Returns**: reactiveVal containing audit log data

**Examples**:
```r
# Initialize in Shiny server
server <- function(input, output, session) {
  audit_log <- init_audit_log()

  # Use in other functions
  log_audit_event("user@example.com", "LOGIN", "system", audit_log = audit_log)

  # Query audit log
  log_data <- reactive({
    query_audit_log(audit_log)
  })
}

shinyApp(ui, server)
```

**See Also**:
- `log_audit_event()` - Add events to log
- `query_audit_log()` - Query audit records

---

## Function Index (Alphabetical)

| Function | Module | Purpose |
|----------|--------|---------|
| create_error_display() | Validation | Display validation errors |
| create_paginated_reactive() | Pagination | Create paginated data |
| export_audit_log() | Audit | Export audit trail |
| export_to_file() | Export | Save data to file |
| generate_export_filename() | Export | Create safe filename |
| get_instrument_field() | Instruments | Get single field |
| get_page_summary() | Pagination | Get page statistics |
| handle_error() | Error Handling | Handle errors gracefully |
| import_instrument() | Instruments | Import into database |
| init_audit_log() | Audit | Initialize audit log |
| init_session_timeout() | Security | Setup session timeout |
| is_field_visible() | Branching | Check field visibility |
| launch_zzedc() | Main | Launch application |
| list_available_instruments() | Instruments | List all instruments |
| load_instrument_template() | Instruments | Load instrument CSV |
| log_audit_event() | Audit | Log event |
| log_export_event() | Export | Log export |
| notify_if_invalid() | Validation | Show validation errors |
| paginate_data() | Pagination | Paginate large datasets |
| prepare_export_data() | Export | Prepare data for export |
| quality_dashboard_server() | Dashboard | Dashboard logic |
| quality_dashboard_ui() | Dashboard | Dashboard UI |
| query_audit_log() | Audit | Query audit records |
| renderPanel() | Forms | Render form fields |
| safe_reactive() | Reactive | Safe reactive wrapper |
| save_validated_form() | Forms | Save validated form |
| setup_form_validation() | Validation | Setup auto-validation |
| setup_pagination_observers() | Pagination | Setup pagination |
| success_response() | Responses | Return success |
| update_session_activity() | Security | Update session time |
| validate_field_value() | Validation | Validate single field |
| validate_filename() | Security | Sanitize filename |
| validate_form() | Validation | Validate entire form |
| validate_instrument_csv() | Instruments | Validate CSV |
| validate_numeric_range() | Validation | Validate number range |
| validate_table_name() | Security | Sanitize table name |
| validate_user_image() | Security | Validate image file |

---

## Getting Help

### Roxygen2 Documentation

For detailed, auto-generated documentation:
```r
# In R console
help(export_to_file)
?renderPanel
```

### Looking at Examples

Check tests for usage examples:
```bash
grep -n "export_to_file" tests/testthat/*.R
grep -n "renderPanel" tests/testthat/*.R
```

### Function Source Code

View function implementation:
```r
library(zzedc)
zzedc:::import_instrument  # View source code
```

---

## Version Information

- **API Reference Version**: 1.0
- **ZZedc Version**: 1.1
- **Generated**: December 2025
- **Last Updated**: December 2025

---

## License

ZZedc is licensed under GPL-3. All functions are open source and available for modification and distribution.
