# Clinical Trial CSV Template Files
## Ready-to-Use Data Definitions for ZZedc Implementation

This directory contains CSV template files that demonstrate how to define clinical trial data elements for ZZedc implementation, using an ADHD clinical trial as a practical example. **These templates can be easily adapted for any therapeutic area or study design** - simply modify the form definitions for your specific research needs.

---

## 📁 File Structure

### Authentication & Configuration Files
- **`users.csv`** - User accounts and roles for the trial team
- **`roles.csv`** - Role definitions and permissions
- **`sites.csv`** - Study site information
- **`forms_overview.csv`** - Overview of all clinical forms

### Clinical Form Templates (ADHD Example)
- **`form_screening.csv`** - Screening and enrollment template (adaptable for any study)
- **`form_demographics.csv`** - Standard participant demographics (universal)
- **`form_medical_history.csv`** - Medical history template (customizable)
- **`form_adhd_rating.csv`** - **Example**: ADHD Rating Scale - *replace with your study's primary endpoint*
- **`form_side_effects.csv`** - Safety monitoring template (adaptable for any treatment)
- **`form_vital_signs.csv`** - Standard vital signs (universal)
- **`form_medication_compliance.csv`** - Treatment adherence template (any therapy)
- **`form_adverse_events.csv`** - Standard AE reporting (regulatory requirement)
- **`form_study_completion.csv`** - Study completion template (universal)

### Utility Files
- **`load_adhd_trial_data.R`** - **Generic** R script to load and work with all CSV files (works for any study)
- **`README.md`** - This documentation file

---

## 🚀 Quick Start

### Option 1: Use with R (Any Study Type)
```r
# Load the data loader script
source("adhd_trial_csv_files/load_adhd_trial_data.R")

# Load all CSV template files
study_data <- load_adhd_trial_csvs()  # Works for any study - just example name

# View summary
summary_data <- summarize_adhd_data(study_data)
print(summary_data)

# Access specific data
users <- study_data$users  # User accounts (adapt for your team)
primary_endpoint <- study_data$form_adhd_rating  # Replace with your endpoint
```

### Option 2: Use with Google Sheets (Any Study)
```r
# Export templates for Google Sheets
source("adhd_trial_csv_files/load_adhd_trial_data.R")
study_data <- load_adhd_trial_csvs()
export_for_google_sheets(study_data, "google_sheets_export")

# Then upload the exported files to Google Sheets and customize for your study
```

### Option 3: Use Individual CSV Templates
```r
# Load and customize specific files for your study
users <- read.csv("adhd_trial_csv_files/users.csv")  # Adapt for your team
screening_form <- read.csv("adhd_trial_csv_files/form_screening.csv")  # Universal template
```

---

## 📋 Data Dictionary Format

All form definition CSV files follow this standard format:

| Column | Description | Example |
|--------|-------------|---------|
| `field` | Field name/variable name | subject_id |
| `prompt` | Display text for users | Subject ID |
| `type` | Data type (C=Character, N=Numeric, D=Date, L=List) | C |
| `layout` | UI element type | text |
| `req` | Required field (1=Yes, 0=No) | 1 |
| `values` | Options for select/radio fields | Male:Female:Other |
| `cond` | Conditional display logic | gender=='Female' |
| `valid` | Validation rules | length(subject_id) == 7 |
| `validmsg` | Validation error message | Subject ID must be 7 characters |

---

## 👥 User Accounts Defined

The trial includes these pre-configured user accounts:

| Username | Role | Full Name | Responsibilities |
|----------|------|-----------|------------------|
| `drschen` | PI | Dr. Sarah Chen | Principal Investigator, oversight |
| `alex_r` | Admin | Alex Rodriguez | Technical lead, database admin |
| `maria_s` | Coordinator | Maria Santos | Data collection, patient management |
| `backup_admin` | Admin | Backup Admin | Emergency access (inactive) |

**Note**: Change passwords before production use!

---

## 📝 Clinical Forms Overview

### Screening & Enrollment
- **Fields**: 13 fields including eligibility criteria and randomization
- **Validation**: Age limits, consent requirements, pregnancy screening
- **Purpose**: Determine study eligibility and assign treatment group

### Demographics
- **Fields**: 10 fields covering race, education, employment, contacts
- **Validation**: Education years (6-25), phone number format
- **Purpose**: Baseline participant characteristics

### Medical History
- **Fields**: 11 fields including prior treatments and comorbidities
- **Validation**: Age at diagnosis, medication allergies
- **Purpose**: Safety screening and baseline medical status

### ADHD Rating Scale
- **Fields**: 24 fields (18 symptom items + totals + metadata)
- **Validation**: Each item scored 0-3, calculated totals
- **Purpose**: Primary efficacy endpoint measurement

### Side Effects Checklist
- **Fields**: 15 fields covering common ADHD medication side effects
- **Validation**: Severity rating (None/Mild/Moderate/Severe)
- **Purpose**: Safety monitoring and tolerability assessment

### Vital Signs
- **Fields**: 10 fields including height, weight, BP, heart rate
- **Validation**: Physiologically reasonable ranges
- **Purpose**: Safety monitoring and baseline health

### Medication Compliance
- **Fields**: 11 fields tracking adherence and pill counts
- **Validation**: Logical pill count calculations
- **Purpose**: Treatment adherence assessment

### Adverse Events
- **Fields**: 17 fields for comprehensive AE reporting
- **Validation**: Date logic, severity assessments
- **Purpose**: Safety monitoring and regulatory reporting

### Study Completion
- **Fields**: 12 fields documenting study end
- **Validation**: Completion status, protocol deviations
- **Purpose**: Final study status and data quality

---

## 🔧 Technical Implementation

### For ZZedc Google Sheets Integration
1. **Upload Authentication CSV** to Google Sheets as "ADHD_Trial_Auth"
2. **Create separate tabs** for users, roles, sites
3. **Upload Data Dictionary CSV** as "ADHD_Trial_DataDict"
4. **Create separate tabs** for each form definition
5. **Use ZZedc setup script**:
   ```r
   source("setup_from_gsheets.R")
   setup_zzedc_from_gsheets_complete(
     auth_sheet_name = "ADHD_Trial_Auth",
     dd_sheet_name = "ADHD_Trial_DataDict",
     project_name = "ADHD_Clinical_Trial"
   )
   ```

### For Direct R Implementation
```r
# Load data
source("adhd_trial_csv_files/load_adhd_trial_data.R")
adhd_data <- load_adhd_trial_csvs()

# Validate structure
validation_results <- validate_adhd_data(adhd_data)

# Create ZZedc database from CSV data
# (Custom implementation needed)
create_zzedc_database_from_csv(adhd_data)
```

### For Other EDC Systems
- Import CSV files into your preferred EDC system
- Map field types and validations to system capabilities
- Configure user roles and permissions
- Set up visit schedules and form associations

---

## 📊 Data Quality Features

### Validation Rules Implemented
- **Subject ID Format**: Exactly 7 characters (ADHD001, etc.)
- **Date Validation**: No future dates, logical date sequences
- **Numeric Ranges**: Age 18-65, vital signs within normal ranges
- **Required Fields**: Critical data elements marked as required
- **Conditional Logic**: Pregnancy questions only for females
- **Data Type Checking**: Appropriate data types for each field

### Quality Control Checks
- **Cross-field Validation**: End dates after start dates
- **Range Checking**: Physiological and logical limits
- **Completeness Tracking**: Required vs. optional fields
- **Consistency Rules**: Related fields must be consistent

---

## 🎯 Study Design Features

### Randomization Support
- **Stratification**: Ready for randomization group assignment
- **Blinding**: Supports double-blind design
- **Treatment Groups**: Active vs. Placebo

### Visit Schedule
- **Screening**: Initial eligibility assessment
- **Baseline**: Demographics, medical history, baseline ADHD rating
- **Week 4, 8, 12**: Follow-up visits with efficacy and safety assessments
- **Completion**: Final study status and outcomes

### Safety Monitoring
- **Adverse Event Tracking**: Comprehensive AE reporting
- **Side Effects Monitoring**: Systematic side effect assessment
- **Vital Signs**: Regular safety parameter monitoring
- **Compliance Tracking**: Medication adherence monitoring

---

## 📚 Additional Resources

### Related Documentation
- **`ADHD_TRIAL_WORKFLOW.md`** - Complete workflow guide
- **`ZZEDC_USER_GUIDE.md`** - ZZedc system documentation
- **`GSHEETS_SETUP_GUIDE.md`** - Google Sheets integration guide

### Validation and Testing
```r
# Run complete validation
source("adhd_trial_csv_files/load_adhd_trial_data.R")
demo_adhd_data_usage()
```

### Customization
- **Modify CSV files** to match your specific study requirements
- **Add additional forms** by creating new form_[name].csv files
- **Adjust validation rules** by editing the `valid` and `validmsg` columns
- **Update user accounts** in users.csv for your team

---

## 🔒 Security Considerations

### Before Production Use
1. **Change all passwords** in users.csv
2. **Update email addresses** to real addresses
3. **Review user permissions** and roles
4. **Configure secure authentication** methods
5. **Implement data encryption** for sensitive data

### Data Protection
- All forms include validation rules to prevent invalid data entry
- Subject IDs follow consistent format for anonymization
- Personal identifiers can be easily separated from clinical data
- Audit trail support through ZZedc system

---

## ✅ Validation Checklist

### Before Implementation
- [ ] All CSV files load without errors
- [ ] User accounts configured for your team
- [ ] Form definitions match study protocol
- [ ] Validation rules appropriate for your data
- [ ] Visit schedule matches protocol timeline

### After Setup
- [ ] Test all user login credentials
- [ ] Verify form display and validation
- [ ] Test data entry workflows
- [ ] Confirm report generation
- [ ] Validate data export functionality

---

## 📞 Support and Questions

For questions about using these CSV files:
1. **Review the documentation** in `ADHD_TRIAL_WORKFLOW.md`
2. **Check the R script** `load_adhd_trial_data.R` for examples
3. **Run the demo function** `demo_adhd_data_usage()` for guided usage
4. **Consult ZZedc documentation** for system-specific questions

This CSV template package provides everything needed to implement **any clinical trial** data capture system using ZZedc or other EDC platforms. **The ADHD example serves as a comprehensive template that can be adapted for any therapeutic area, study design, or research question.**