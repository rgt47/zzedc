# ZZedc Google Sheets Setup Guide

## Overview

This guide explains how to configure ZZedc using Google Sheets to define user authentication and data dictionary structure. This approach allows non-technical users to configure clinical trial forms and user access through familiar Google Sheets interface.

## Quick Start

1. **Create your Google Sheets** (see templates below)
2. **Run setup script**: `source("setup_from_gsheets.R"); setup_zzedc_from_gsheets_complete()`
3. **Launch application**: Use the generated launch script

## Required Google Sheets

### 1. Authentication Sheet (`zzedc_auth`)

This sheet defines users, roles, and sites for your EDC system.

#### Tab: `users`
| Column | Description | Required | Example |
|--------|-------------|----------|---------|
| username | Login username | Yes | jsmith |
| password | Plain text password | Yes | mypassword123 |
| full_name | User's full name | Yes | John Smith |
| email | Email address | No | jsmith@example.com |
| role | User role | Yes | PI |
| site_id | Site identifier | No | 1 |
| active | 1=active, 0=inactive | No | 1 |

**Example users tab:**
```
username    password     full_name      email              role         site_id  active
admin       admin123     System Admin   admin@trial.com    Admin        1        1
jsmith      password123  John Smith     jsmith@trial.com   PI           1        1
mwilson     coord456     Mary Wilson    mwilson@trial.com  Coordinator  1        1
```

#### Tab: `roles` (optional)
| Column | Description | Example |
|--------|-------------|---------|
| role | Role name | Admin |
| description | Role description | Full system access |
| permissions | Permission level | all |

**Example roles tab:**
```
role          description                permissions
Admin         Full system access         all
PI            Principal Investigator     read_write
Coordinator   Research Coordinator       read_write
Data Manager  Data Manager              read_write
User          Standard User             read_only
```

#### Tab: `sites` (optional)
| Column | Description | Example |
|--------|-------------|---------|
| site_id | Numeric site ID | 1 |
| site_name | Site name | Main Hospital |
| site_code | Site code | MH |
| active | 1=active, 0=inactive | 1 |

**Example sites tab:**
```
site_id  site_name        site_code  active
1        Main Hospital    MH         1
2        Regional Clinic  RC         1
```

### 2. Data Dictionary Sheet (`zzedc_data_dictionary`)

This sheet defines the forms and fields for data collection.

#### Tab: `forms_overview`
| Column | Description | Required | Example |
|--------|-------------|----------|---------|
| workingname | Internal form name | Yes | demographics |
| fullname | Display name | Yes | Demographics Form |
| visits | Comma-separated visit codes | Yes | baseline,month3,month6 |

**Example forms_overview tab:**
```
workingname    fullname           visits
demographics   Demographics       baseline
vitals         Vital Signs        baseline,month3,month6
adverse_events Adverse Events     baseline,month3,month6
```

#### Tab: `form_[formname]` (one for each form)

For each form in `forms_overview`, create a tab named `form_` + `workingname`.

| Column | Description | Required | Example |
|--------|-------------|----------|---------|
| field | Field name (variable name) | Yes | age |
| prompt | Field label/prompt | Yes | Age (years) |
| type | Data type (C/N/D/L) | Yes | N |
| layout | Input type | Yes | numeric |
| req | Required (1/0) | No | 1 |
| values | Options for select/radio | No | yes,no |
| cond | Conditional display | No | gender=female |
| valid | Validation rule | No | age >= 18 |
| validmsg | Validation message | No | Age must be 18 or older |

**Data Types:**
- `C` = Character/Text
- `N` = Numeric
- `D` = Date
- `L` = Logical (Yes/No)

**Layout Types:**
- `text` = Text input
- `textarea` = Text area
- `numeric` = Numeric input
- `date` = Date picker
- `radio` = Radio buttons
- `select` = Dropdown select
- `checkbox` = Checkbox

**Example form_demographics tab:**
```
field     prompt        type  layout   req  values     cond  valid      validmsg
subject_id Subject ID    C     text     1
age       Age (years)   N     numeric  1              age>=18 Age must be 18+
gender    Gender        L     radio    1    male,female
dob       Date of Birth D     date     1
```

#### Tab: `visits` (optional)
| Column | Description | Example |
|--------|-------------|---------|
| visit_code | Visit identifier | baseline |
| visit_name | Visit display name | Baseline Visit |
| visit_order | Visit sequence | 1 |
| active | 1=active, 0=inactive | 1 |

#### Tab: `field_types` (optional)
| Column | Description | Example |
|--------|-------------|---------|
| type_code | Type code (C/N/D/L) | N |
| type_name | Type name | Numeric |
| description | Type description | Numeric field |

#### Tab: `validation` (optional)
| Column | Description | Example |
|--------|-------------|---------|
| field | Field name | age |
| rule | Validation rule | input$age >= 18 |
| message | Error message | Age must be 18 or older |

## Setup Process

### Step 1: Create Google Sheets

1. Create a new Google Sheet for authentication data
2. Name it `zzedc_auth` (or your preferred name)
3. Create tabs: `users`, `roles`, `sites`
4. Fill in your data following the templates above

5. Create a new Google Sheet for data dictionary
6. Name it `zzedc_data_dictionary` (or your preferred name)
7. Create tabs: `forms_overview`, `form_[name]` for each form, `visits`
8. Fill in your form definitions

### Step 2: Share Sheets with Your Google Account

Make sure the Google Sheets are accessible to the Google account you'll use for authentication.

### Step 3: Run Setup Script

```r
# Load the setup script
source("setup_from_gsheets.R")

# Run setup with your sheet names
setup_zzedc_from_gsheets_complete(
  auth_sheet_name = "zzedc_auth",
  dd_sheet_name = "zzedc_data_dictionary",
  project_name = "my_clinical_trial"
)
```

### Step 4: Launch Application

```r
# Use generated launch script
source("launch_my_clinical_trial.R")
```

## Advanced Configuration

### Custom Database Location
```r
setup_zzedc_from_gsheets_complete(
  auth_sheet_name = "my_auth",
  dd_sheet_name = "my_dd",
  db_path = "custom/location/database.db"
)
```

### Custom Password Salt
```r
setup_zzedc_from_gsheets_complete(
  auth_sheet_name = "my_auth",
  dd_sheet_name = "my_dd",
  salt = "my_custom_salt_string"
)
```

### Backup Existing Database
The setup script automatically backs up existing databases before creating new ones.

## Validation Rules

### Simple Validation
```
field: age
valid: age >= 18
validmsg: Age must be 18 or older
```

### Complex Validation
```
field: weight
valid: weight > 0 && weight < 500
validmsg: Weight must be between 0 and 500 kg
```

### Conditional Fields
```
field: pregnancy_test
cond: gender=female
```

## Troubleshooting

### Common Issues

1. **"Sheet not found" error**
   - Check sheet names match exactly
   - Ensure sheets are shared with your Google account

2. **Authentication failures**
   - Run `gs4_auth()` manually to re-authenticate
   - Check token file permissions

3. **Missing columns**
   - Verify required columns exist in your sheets
   - Check column names match exactly (case sensitive)

4. **Database errors**
   - Check file permissions in data directory
   - Verify SQLite is installed

### Getting Help

- Check the generated log files in `logs/`
- Run the test script: `source("test_my_project.R")`
- Verify database structure: Use SQLite browser

## Best Practices

1. **Use descriptive field names** - Make them valid R variable names
2. **Test with small data first** - Validate your setup before full deployment
3. **Backup regularly** - Keep copies of your Google Sheets
4. **Document validation rules** - Use clear, understandable validation messages
5. **Plan your visits** - Define all visits upfront in the data dictionary

## Example Templates

See the `templates/` directory for complete example Google Sheets that you can copy and modify.

## Integration with Existing ZZedc

This Google Sheets system integrates seamlessly with existing ZZedc installations. The generated database structure is compatible with all ZZedc features including:

- User authentication and role management
- Form rendering and validation
- Data export capabilities
- Reporting functions
- Quality control features

The Google Sheets approach simply provides an alternative way to configure the system without editing R code directly.