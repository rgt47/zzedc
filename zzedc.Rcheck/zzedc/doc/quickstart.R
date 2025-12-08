## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  eval = FALSE
)

## ----installation-------------------------------------------------------------
# # Install both packages (zzedc.validation is the validation core)
# install.packages("path/to/zzedc.validation_1.0.0.tar.gz", repos = NULL, type = "source")
# install.packages("path/to/zzedc_1.0.0.tar.gz", repos = NULL, type = "source")
# 
# # Load ZZedc
# library(zzedc)

## ----launch-------------------------------------------------------------------
# # Start the application
# launch_zzedc()
# 
# # Your browser opens automatically at http://localhost:3838

## ----data_validation----------------------------------------------------------
# # Validation rules implemented in ZZedc:
# validation_rules <- list(
#   "Age range validation" = "Verifies age values within acceptable ranges",
#   "Date sequence validation" = "Ensures visit dates follow enrollment chronology",
#   "Field completeness checks" = "Identifies missing required data",
#   "Data type validation" = "Confirms numeric fields contain appropriate values",
#   "Custom rule application" = "Implements study-specific validation logic"
# )

## ----report1------------------------------------------------------------------
# # Report 1 displays:
# # - Total enrolled subjects
# # - Enrollment distribution by site (when applicable)
# # - Subject status categorization
# # - Enrollment progression over time

## ----report2------------------------------------------------------------------
# # Report 2 identifies:
# # - Missing data patterns by field
# # - Validation error distribution
# # - Duplicate record detection
# # - Protocol deviation documentation

## ----report3------------------------------------------------------------------
# # Report 3 generates:
# # - Demographic summary statistics
# # - Baseline characteristic distributions
# # - Outcome variable summaries
# # - Safety event tabulations

## ----export_example-----------------------------------------------------------
# # In the Export tab, select format and download
# # Data exports include:
# # - Raw data with all variables
# # - Derived variables and scores
# # - Analysis datasets per protocol
# # - Regulatory submission formats

## ----setup_study--------------------------------------------------------------
# study_config <- list(
#   name = "Depression Treatment Trial v1.0",
#   protocol = "DEPR-2024-001",
#   pi = "Dr. Jane Smith",
#   sites = c("University Medical Center", "Community Health Clinic"),
#   target_enrollment = 50
# )

## ----analysis-----------------------------------------------------------------
# # One click exports analysis-ready dataset:
# # - 50 subjects across 2 sites
# # - All validated data + computed scores
# # - Ready for statistical software
# # - Includes audit trail for FDA compliance
# 
# analysis_data <- read.csv("depression_trial_export.csv")
# head(analysis_data)
# # All variables present, properly formatted, complete

## ----quality_monitoring-------------------------------------------------------
# # Automatic nightly QC checks:
# # - Flag missing data patterns
# # - Identify unusual values (outliers)
# # - Check cross-visit consistency
# # - Generate quality reports

## ----longitudinal-------------------------------------------------------------
# # Support for:
# # - Baseline + follow-up visits
# # - Weekly, monthly, or yearly data
# # - Cross-visit validation (e.g., visit dates in order)
# # - Longitudinal outcome calculations

## ----lab_integration----------------------------------------------------------
# # Automated lab result upload:
# # - Direct from lab information systems (HL7)
# # - Or manual entry with validation
# # - Automatic range checking vs reference values
# # - Integration with case report forms

## ----custom_validation--------------------------------------------------------
# # Create rules like:
# # "If treatment='Drug A' then dose required"
# # "If adverse event='serious' then hospitalization required"
# # "If visit_date > baseline + 365 days then flag"
# # "If blood_pressure > 180/110 then notify PI"

## ----e_signatures-------------------------------------------------------------
# # For regulatory submissions:
# # - Multi-factor authentication
# # - Audit trail of all e-signatures
# # - 21 CFR Part 11 compliance
# # - Acceptable to FDA for data lock

## ----final--------------------------------------------------------------------
# # You're ready. One command gets you started:
# launch_zzedc()
# 
# # Questions? Check the vignettes or email rgthomas@ucsd.edu

