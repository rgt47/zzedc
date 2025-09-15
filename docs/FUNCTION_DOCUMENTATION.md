# ZZedc Google Sheets Integration - Function Documentation

## Overview

This document provides comprehensive documentation for all functions in the ZZedc Google Sheets integration system. Each function is documented with detailed descriptions, parameter explanations, return values, and multiple usage examples suitable for intermediate R users.

---

## Core Integration Functions (`gsheets_integration.R`)

### `setup_google_auth(token_file = "googlesheets_token.rds")`

**Description:**
Establishes authentication with Google Sheets using OAuth2 tokens. This function handles both initial authentication (prompting user login) and subsequent authentications using cached tokens.

**Parameters:**
- `token_file` (character): Path to store/retrieve the authentication token. Default is "googlesheets_token.rds"

**Return Value:**
- No return value (invisible NULL). Function called for side effects (authentication setup)

**Details:**
The function uses the `googlesheets4` package's authentication system. On first run, it will open a browser window for Google OAuth2 authentication. Subsequent runs use the cached token unless it has expired.

**Examples:**

```r
# Basic usage with default token file
setup_google_auth()

# Use custom token file location
setup_google_auth("/path/to/my/token.rds")

# Use in automated scripts (assumes token already exists)
setup_google_auth("automated_token.rds")
```

**Error Handling:**
- If token file doesn't exist, initiates new authentication
- If token is expired, prompts for re-authentication
- Network errors are passed through from googlesheets4

**See Also:** `gs4_auth()` from googlesheets4 package

---

### `read_auth_from_gsheets(sheet_name = GSHEETS_CONFIG$auth_sheet_name)`

**Description:**
Reads authentication data (users, roles, sites) from a Google Sheets document and validates the data structure. This function is the primary interface for loading user authentication information from Google Sheets.

**Parameters:**
- `sheet_name` (character): Name of the Google Sheets document containing authentication data

**Return Value:**
- `data.frame`: Cleaned and validated authentication data with columns:
  - `username`: User login name (character)
  - `password`: Plain text password (character) - will be hashed before storage
  - `full_name`: User's display name (character)
  - `email`: Email address (character)
  - `role`: User role (character)
  - `site_id`: Site identifier (numeric)
  - `active`: Active status (1 = active, 0 = inactive)
  - `created_date`: Account creation timestamp (POSIXct)
  - `last_login`: Last login timestamp (POSIXct, initially NA)

**Details:**
The function expects a Google Sheets document with a "users" tab containing the authentication data. It performs extensive validation including:
- Required column presence
- Data type validation
- Username uniqueness checking
- Default value assignment for missing fields

**Examples:**

```r
# Read from default authentication sheet
auth_data <- read_auth_from_gsheets("my_study_auth")

# Inspect the returned data
str(auth_data)
head(auth_data)

# Check for any issues
if (nrow(auth_data) == 0) {
  stop("No valid users found in authentication sheet")
}

# Example of valid Google Sheets structure:
# Tab name: users
# Columns: username | password | full_name | email | role | site_id | active
# Row 1:   admin   | admin123 | Admin User| admin@study.com | Admin | 1 | 1
# Row 2:   jsmith  | pass456  | John Smith| john@study.com  | User  | 1 | 1
```

**Required Google Sheets Structure:**
```
Tab: users (required)
Columns (required): username, password, full_name, role
Columns (optional): email, site_id, active

Tab: roles (optional)
Columns: role, description, permissions

Tab: sites (optional)
Columns: site_id, site_name, site_code, active
```

**Error Handling:**
- Throws error if sheet not found or inaccessible
- Throws error if required columns missing
- Warns about missing optional columns and uses defaults
- Filters out rows with missing critical data (username, password)

**Security Notes:**
- Passwords are stored in plain text in Google Sheets but immediately hashed
- Consider using Google Sheets permissions to restrict access
- Audit trail is maintained in Google Sheets revision history

---

### `read_dd_from_gsheets(sheet_name = GSHEETS_CONFIG$dd_sheet_name)`

**Description:**
Reads data dictionary information from Google Sheets and constructs form definitions for the EDC system. This function processes the forms overview and individual form definitions to create a complete data dictionary structure.

**Parameters:**
- `sheet_name` (character): Name of the Google Sheets document containing data dictionary

**Return Value:**
- `list`: Complex list structure containing:
  - `forms_overview`: Data frame with form metadata
  - `form_definitions`: Named list of data frames, one per form
  - `visits`: Data frame defining study visits (if available)
  - `field_types`: Data frame defining field types (if available)
  - `validation_rules`: Data frame with validation rules (if available)
  - `form_errors`: List of any errors encountered reading forms

**Details:**
The function reads multiple tabs from the Google Sheets document:
1. "forms_overview": Lists all forms and their associated visits
2. "form_[name]": Individual tabs for each form definition
3. Optional tabs: "visits", "field_types", "validation"

**Examples:**

```r
# Read data dictionary from Google Sheets
dd_data <- read_dd_from_gsheets("my_study_dictionary")

# Explore the structure
names(dd_data)
# [1] "forms_overview"   "form_definitions" "visits"
# [4] "field_types"      "validation_rules" "form_errors"

# Check forms overview
print(dd_data$forms_overview)
#   workingname     fullname              visits
# 1 demographics   Demographics          baseline
# 2 medical_hist   Medical History       baseline
# 3 symptoms       Symptom Assessment    baseline,week4,week12

# Examine a specific form definition
demographics_form <- dd_data$form_definitions[["demographics"]]
print(demographics_form)
#   field    prompt          type layout req values
# 1 age      Age (years)     N    numeric 1
# 2 gender   Gender          L    radio   1  Male,Female
# 3 education Years of Ed.   N    numeric 0

# Check for any form reading errors
if (length(dd_data$form_errors) > 0) {
  warning("Form reading errors:", dd_data$form_errors)
}

# Access field types if available
if (!is.null(dd_data$field_types)) {
  print(dd_data$field_types)
  #   type_code type_name   description
  # 1 C         Character   Text field
  # 2 N         Numeric     Numeric field
  # 3 D         Date        Date field
  # 4 L         Logical     Yes/No field
}
```

**Required Google Sheets Structure:**

```
Tab: forms_overview (required)
Columns: workingname, fullname, visits

Tab: form_[workingname] (one per form, required)
Columns: field, prompt, type, layout
Optional: req, values, cond, valid, validmsg

Example form_demographics tab:
field     | prompt        | type | layout  | req | values
age       | Age (years)   | N    | numeric | 1   |
gender    | Gender        | L    | radio   | 1   | Male,Female
education | Education     | N    | numeric | 0   |
```

**Error Handling:**
- Continues processing if individual form tabs are missing
- Validates form overview structure before processing forms
- Records form-specific errors in `form_errors` element
- Uses sensible defaults for missing optional tabs

**Field Type Specifications:**
- `C`: Character/text fields
- `N`: Numeric fields
- `D`: Date fields
- `L`: Logical/boolean fields (typically radio buttons)

**Layout Options:**
- `text`: Single-line text input
- `textarea`: Multi-line text input
- `numeric`: Numeric input with validation
- `date`: Date picker
- `radio`: Radio button selection
- `select`: Dropdown selection
- `checkbox`: Checkbox input

---

### `hash_password(password, salt = "zzedc_default_salt")`

**Description:**
Securely hashes passwords using SHA-256 algorithm with salt. This function is used to convert plain text passwords into secure hashes for database storage.

**Parameters:**
- `password` (character): Plain text password to hash
- `salt` (character): Salt value to add security. Default is "zzedc_default_salt"

**Return Value:**
- `character`: 64-character SHA-256 hash string

**Details:**
The function concatenates the password with the salt, then applies SHA-256 hashing. Using a salt prevents rainbow table attacks and adds security even if the database is compromised.

**Examples:**

```r
# Basic password hashing
hashed <- hash_password("mypassword123")
print(hashed)
# [1] "a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890"

# Using custom salt
custom_hash <- hash_password("mypassword123", "my_custom_salt_2024")
print(custom_hash)

# Verify same password + salt produces same hash
hash1 <- hash_password("test123", "salt1")
hash2 <- hash_password("test123", "salt1")
identical(hash1, hash2)  # TRUE

# Different salts produce different hashes
hash3 <- hash_password("test123", "salt2")
identical(hash1, hash3)  # FALSE

# Use in authentication workflow
user_password <- "user_input_password"
stored_hash <- "hash_from_database"
input_hash <- hash_password(user_password, "production_salt")
authenticated <- identical(input_hash, stored_hash)
```

**Security Considerations:**
- Always use the same salt for all passwords in a system
- Store salt securely (environment variables, config files)
- Never log or display hashed passwords
- Consider using bcrypt for even stronger hashing in production

**Performance Notes:**
- SHA-256 is fast but consider bcrypt for high-security applications
- Hashing is CPU-intensive; avoid in tight loops
- Cache authentication results when appropriate

---

### `setup_zzedc_from_gsheets_complete(...)`

**Description:**
Master orchestration function that performs complete ZZedc setup from Google Sheets configuration. This is the main entry point for setting up an entire EDC system from Google Sheets.

**Parameters:**
- `auth_sheet_name` (character): Name of authentication Google Sheet. Default: "zzedc_auth"
- `dd_sheet_name` (character): Name of data dictionary Google Sheet. Default: "zzedc_data_dictionary"
- `project_name` (character): Name for the project/study. Default: "zzedc_project"
- `db_path` (character): Path to SQLite database file. Default: NULL (auto-generated)
- `salt` (character): Salt for password hashing. Default: "zzedc_default_salt"
- `token_file` (character): Path to Google Sheets token. Default: "googlesheets_token.rds"
- `forms_dir` (character): Directory for generated forms. Default: "forms_generated"
- `backup_existing` (logical): Whether to backup existing database. Default: TRUE

**Return Value:**
- `logical`: TRUE if setup completed successfully, FALSE otherwise

**Details:**
This function orchestrates the complete setup process:
1. Sets up Google Sheets authentication
2. Validates access to required sheets
3. Builds authentication system from Google Sheets
4. Builds data dictionary and forms from Google Sheets
5. Generates configuration files
6. Creates launch scripts
7. Performs final system validation

**Examples:**

```r
# Basic setup with default parameters
success <- setup_zzedc_from_gsheets_complete()

# Setup for specific clinical trial
success <- setup_zzedc_from_gsheets_complete(
  auth_sheet_name = "ADHD_Trial_Auth",
  dd_sheet_name = "ADHD_Trial_DataDict",
  project_name = "ADHD_Clinical_Trial"
)

# Advanced setup with custom parameters
success <- setup_zzedc_from_gsheets_complete(
  auth_sheet_name = "my_study_users",
  dd_sheet_name = "my_study_forms",
  project_name = "longitudinal_study_2024",
  db_path = "data/custom_location/study.db",
  salt = Sys.getenv("STUDY_PASSWORD_SALT"),
  forms_dir = "generated_forms",
  backup_existing = TRUE
)

if (success) {
  message("Setup completed successfully!")
  message("Launch your study with: source('launch_longitudinal_study_2024.R')")
} else {
  stop("Setup failed. Check console messages for details.")
}

# Setup with error handling
tryCatch({
  success <- setup_zzedc_from_gsheets_complete(
    auth_sheet_name = "my_auth_sheet",
    dd_sheet_name = "my_dd_sheet",
    project_name = "my_study"
  )

  if (!success) {
    stop("Setup validation failed")
  }

}, error = function(e) {
  message("Setup error: ", e$message)
  message("Common issues:")
  message("1. Google Sheets not found or not accessible")
  message("2. Internet connection problems")
  message("3. Invalid sheet structure")
  message("4. File permission issues")
})
```

**Prerequisites:**
- Google Sheets created with proper structure
- Google account authentication set up
- Write permissions to local directory
- Internet connection for Google Sheets access

**Generated Files:**
- Database file (SQLite)
- Form generation files in `forms_dir`
- Launch script: `launch_[project_name].R`
- Test script: `test_[project_name].R`
- Updated `config.yml`

**Process Flow:**
1. **Authentication**: Connects to Google Sheets
2. **Validation**: Verifies sheet structure and accessibility
3. **Database Creation**: Builds SQLite database with proper schema
4. **Form Generation**: Creates Shiny UI forms from sheet definitions
5. **Configuration**: Updates system configuration files
6. **Verification**: Performs final system checks

---

## Authentication Builder Functions (`gsheets_auth_builder.R`)

### `build_advanced_auth_system(...)`

**Description:**
Builds a comprehensive authentication system with role-based access control, site management, and security features from Google Sheets configuration.

**Parameters:**
- `auth_sheet_name` (character): Name of authentication Google Sheet
- `db_path` (character): Path to SQLite database file
- `salt` (character): Salt for password hashing
- `validate_roles` (logical): Whether to validate role assignments against role definitions

**Return Value:**
- No return value (called for side effects - database creation)

**Details:**
Creates a multi-table authentication system including:
- User accounts with hashed passwords
- Role definitions and permissions
- Site/location management
- Audit trails and login tracking

**Examples:**

```r
# Basic authentication system setup
build_advanced_auth_system(
  auth_sheet_name = "my_study_auth",
  db_path = "data/study.db",
  salt = "my_secure_salt_2024"
)

# With role validation enabled
build_advanced_auth_system(
  auth_sheet_name = "clinical_trial_users",
  db_path = "data/clinical_trial.db",
  salt = Sys.getenv("CLINICAL_TRIAL_SALT"),
  validate_roles = TRUE
)

# Check the results
con <- RSQLite::dbConnect(RSQLite::SQLite(), "data/study.db")

# View created tables
RSQLite::dbListTables(con)
# [1] "edc_users" "edc_roles" "edc_sites"

# Check user accounts (passwords are hashed)
users <- RSQLite::dbGetQuery(con, "SELECT username, full_name, role, active FROM edc_users")
print(users)

# Check roles
roles <- RSQLite::dbGetQuery(con, "SELECT * FROM edc_roles")
print(roles)

RSQLite::dbDisconnect(con)
```

**Database Schema Created:**
```sql
-- Users table
CREATE TABLE edc_users (
  user_id INTEGER PRIMARY KEY,
  username TEXT UNIQUE,
  password_hash TEXT,
  full_name TEXT,
  email TEXT,
  role TEXT,
  site_id INTEGER,
  active INTEGER,
  created_date TEXT,
  last_login TEXT,
  login_attempts INTEGER,
  locked INTEGER
);

-- Roles table
CREATE TABLE edc_roles (
  role TEXT PRIMARY KEY,
  description TEXT,
  permissions TEXT
);

-- Sites table
CREATE TABLE edc_sites (
  site_id INTEGER PRIMARY KEY,
  site_name TEXT,
  site_code TEXT,
  active INTEGER
);
```

---

### `verify_auth_system(db_path, salt)`

**Description:**
Verifies that the authentication system was set up correctly and can perform login operations.

**Parameters:**
- `db_path` (character): Path to SQLite database file
- `salt` (character): Salt used for password hashing

**Return Value:**
- `logical`: TRUE if verification passed, FALSE otherwise

**Examples:**

```r
# Verify authentication system
verification_passed <- verify_auth_system("data/study.db", "my_salt")

if (verification_passed) {
  message("✅ Authentication system working correctly")
} else {
  warning("❌ Authentication system has issues")
}
```

---

## Data Dictionary Builder Functions (`gsheets_dd_builder.R`)

### `build_advanced_dd_system(...)`

**Description:**
Builds comprehensive data dictionary system including form definitions, validation rules, and data storage tables from Google Sheets configuration.

**Parameters:**
- `dd_sheet_name` (character): Name of data dictionary Google Sheet
- `db_path` (character): Path to SQLite database file
- `forms_dir` (character): Directory to store generated form files

**Examples:**

```r
# Build data dictionary system
build_advanced_dd_system(
  dd_sheet_name = "my_study_dictionary",
  db_path = "data/study.db",
  forms_dir = "forms_generated"
)

# Check generated files
list.files("forms_generated")
# [1] "demographics_form.R"    "symptoms_form.R"       "validation_rules.R"

# Check database tables
con <- RSQLite::dbConnect(RSQLite::SQLite(), "data/study.db")
RSQLite::dbListTables(con)
# Includes: edc_forms, edc_fields, data_demographics, data_symptoms, etc.
RSQLite::dbDisconnect(con)
```

---

### `generate_form_files(dd_data, forms_dir)`

**Description:**
Generates Shiny UI form files from data dictionary definitions. Creates R files containing form generation functions.

**Parameters:**
- `dd_data` (list): Data dictionary data from `read_enhanced_dd_data()`
- `forms_dir` (character): Directory to store generated form files

**Examples:**

```r
# Read data dictionary first
dd_data <- read_enhanced_dd_data("my_study_dd")

# Generate form files
generate_form_files(dd_data, "forms_generated")

# Examine generated file
cat(readLines("forms_generated/demographics_form.R")[1:10])
# Shows generated Shiny UI code
```

---

## Integration and Helper Functions

### `load_gsheets_forms(forms_dir, db_path)`

**Description:**
Loads generated Google Sheets forms into the ZZedc application for dynamic form rendering.

**Parameters:**
- `forms_dir` (character): Directory containing generated form files
- `db_path` (character): Path to database with form definitions

**Return Value:**
- `list`: Contains forms overview, form loaders, and validation rules

**Examples:**

```r
# Load forms for use in Shiny app
forms_data <- load_gsheets_forms("forms_generated", "data/study.db")

# Check what was loaded
names(forms_data)
# [1] "forms_overview" "form_loaders"   "validation_rules"

# See available forms
print(forms_data$forms_overview$fullname)
# [1] "Demographics Form"     "Medical History"      "Symptom Assessment"
```

---

## Configuration and Setup Functions

### `create_enhanced_ui()`

**Description:**
Creates enhanced Shiny UI that dynamically includes Google Sheets forms alongside traditional ZZedc functionality.

**Return Value:**
- Shiny UI object with integrated Google Sheets forms

**Examples:**

```r
# Create enhanced UI (used internally)
ui <- create_enhanced_ui()

# UI automatically detects and includes Google Sheets forms
# Falls back to traditional forms if no Google Sheets configuration found
```

---

### `create_enhanced_server(input, output, session)`

**Description:**
Creates enhanced Shiny server function with Google Sheets integration, form handling, and traditional ZZedc functionality.

**Parameters:**
- Standard Shiny server parameters

**Examples:**

```r
# Create enhanced server (used in server.R)
server <- function(input, output, session) {
  create_enhanced_server(input, output, session)
}
```

---

## Utility and Helper Functions

### `%||%` (Null Coalescing Operator)

**Description:**
Helper operator that returns the right-hand side value if the left-hand side is NULL, empty, or missing.

**Usage:**
```r
x %||% y  # Returns y if x is NULL/empty, otherwise returns x
```

**Examples:**

```r
# Basic usage
NULL %||% "default"          # "default"
"" %||% "default"            # "default"
"value" %||% "default"       # "value"

# In function parameters
get_config_value <- function(key, default = NULL) {
  value <- Sys.getenv(key)
  value %||% default
}

# Usage in forms
subject_id <- input$subject_id %||% "SUBJ001"
visit_code <- input$visit_code %||% "baseline"
```

---

## Error Handling Patterns

### Common Error Patterns and Solutions

```r
# 1. Google Sheets Access Errors
tryCatch({
  auth_data <- read_auth_from_gsheets("my_sheet")
}, error = function(e) {
  if (grepl("not found", e$message)) {
    stop("Google Sheet not found. Check sheet name and permissions.")
  } else if (grepl("authentication", e$message)) {
    stop("Google authentication failed. Run gs4_auth() manually.")
  } else {
    stop("Unknown Google Sheets error: ", e$message)
  }
})

# 2. Database Connection Errors
safe_db_operation <- function(db_path, query) {
  tryCatch({
    con <- RSQLite::dbConnect(RSQLite::SQLite(), db_path)
    on.exit(RSQLite::dbDisconnect(con))

    result <- RSQLite::dbGetQuery(con, query)
    return(result)

  }, error = function(e) {
    message("Database error: ", e$message)
    return(NULL)
  })
}

# 3. Validation Errors
validate_form_data <- function(form_data, form_definition) {
  errors <- c()

  for (field in form_definition$field[form_definition$req == 1]) {
    if (is.null(form_data[[field]]) || form_data[[field]] == "") {
      errors <- c(errors, paste("Field", field, "is required"))
    }
  }

  if (length(errors) > 0) {
    stop("Validation errors:\n", paste(errors, collapse = "\n"))
  }
}
```

---

## Performance Considerations

### Best Practices for Large Studies

```r
# 1. Use database connection pooling
db_pool <- pool::dbPool(
  drv = RSQLite::SQLite(),
  dbname = "data/large_study.db",
  minSize = 2,
  maxSize = 10
)

# 2. Batch database operations
batch_insert <- function(data, table_name, batch_size = 100) {
  for (i in seq(1, nrow(data), batch_size)) {
    end_idx <- min(i + batch_size - 1, nrow(data))
    batch_data <- data[i:end_idx, ]

    RSQLite::dbWriteTable(con, table_name, batch_data, append = TRUE)
  }
}

# 3. Optimize Google Sheets reads
# Read all sheets at once rather than individual reads
all_sheets_data <- gs4_find() %>%
  filter(name %in% c("auth_sheet", "dd_sheet")) %>%
  pull(id) %>%
  map(read_sheet)
```

---

## Testing and Debugging

### Testing Functions

```r
# Test Google Sheets connectivity
test_gsheets_connection <- function(sheet_name) {
  tryCatch({
    sheet_info <- gs4_get(sheet_name)
    message("✅ Successfully connected to: ", sheet_info$name)
    return(TRUE)
  }, error = function(e) {
    message("❌ Failed to connect: ", e$message)
    return(FALSE)
  })
}

# Test database integrity
test_database_integrity <- function(db_path) {
  con <- RSQLite::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(RSQLite::dbDisconnect(con))

  # Check required tables exist
  tables <- RSQLite::dbListTables(con)
  required_tables <- c("edc_users", "edc_forms", "edc_fields")

  missing <- setdiff(required_tables, tables)
  if (length(missing) > 0) {
    stop("Missing required tables: ", paste(missing, collapse = ", "))
  }

  message("✅ Database integrity check passed")
}

# Debug form generation
debug_form_generation <- function(form_name, dd_data) {
  form_def <- dd_data$form_definitions[[form_name]]

  message("Form: ", form_name)
  message("Fields: ", nrow(form_def))

  for (i in 1:nrow(form_def)) {
    field <- form_def[i, ]
    message("  ", field$field, " (", field$type, ") - ", field$prompt)
  }
}
```

This comprehensive documentation provides intermediate R users with detailed understanding of each function, including parameters, return values, usage examples, and best practices.