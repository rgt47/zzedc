## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  eval = FALSE
)

## ----installation-------------------------------------------------------------
# # Install ZZedc packages
# # Note: zzedc.validation is a required dependency
# install.packages("path/to/zzedc.validation_1.0.0.tar.gz", repos = NULL, type = "source")
# install.packages("path/to/zzedc_1.0.0.tar.gz", repos = NULL, type = "source")
# 
# # Load the package
# library(zzedc)

## ----launch-------------------------------------------------------------------
# # Launch the application
# launch_zzedc()
# 
# # Or with custom settings
# launch_zzedc(
#   host = "127.0.0.1",
#   port = 3838,
#   launch.browser = TRUE
# )

## ----study_setup--------------------------------------------------------------
# # Study configuration (modify config.yml or use interface)
# study_info <- list(
#   name = "My Clinical Study",
#   protocol = "STUDY-2024-001",
#   pi = "Dr. Researcher",
#   target_enrollment = 50
# )

## ----user_setup---------------------------------------------------------------
# # Add study team members (done through interface)
# # Navigate to: Settings > User Management
# 
# team_roles <- c(
#   "Principal Investigator",
#   "Research Coordinator",
#   "Data Manager",
#   "Biostatistician"
# )

## ----data_entry_example-------------------------------------------------------
# # Example subject data structure
# subject_data <- list(
#   subject_id = "STUDY001",
#   initials = "AB",
#   date_of_birth = "1980-05-15",
#   gender = "Female",
#   enrollment_date = Sys.Date()
# )

## ----reporting----------------------------------------------------------------
# # Basic reporting workflow:
# # 1. Navigate to Reports tab
# # 2. Select report type
# # 3. Choose date range and filters
# # 4. Generate and download
# 
# # Available report formats:
# report_formats <- c("HTML", "PDF", "Word", "Excel")

## ----security-----------------------------------------------------------------
# # Security features
# security_features <- list(
#   user_authentication = "Database-based with secure password hashing",
#   session_management = "Configurable timeout and session tracking",
#   audit_trail = "Complete record of all user actions",
#   role_based_access = "Granular permissions by user role",
#   data_encryption = "Secure data storage and transmission"
# )

## ----compliance---------------------------------------------------------------
# # Compliance features
# compliance_features <- list(
#   gdpr = "Data subject rights, consent management, and privacy controls",
#   cfr_part_11 = "Electronic signatures, audit trail, and data integrity",
#   audit_logging = "Immutable, hash-chained audit records",
#   data_governance = "Purpose limitation and data minimization controls",
#   breach_management = "Incident tracking and notification capabilities"
# )

## ----ui_features--------------------------------------------------------------
# # UI Features
# ui_capabilities <- list(
#   responsive_design = "Works on desktop, tablet, and mobile",
#   accessibility = "WCAG 2.1 compliant interface",
#   modern_styling = "Bootstrap 5 with professional themes",
#   interactive_components = "Real-time updates and feedback",
#   data_visualization = "Integrated charts and graphs"
# )

## ----env_vars-----------------------------------------------------------------
# # Example environment variables
# Sys.setenv(
#   ZZEDC_DB_PATH = "/secure/path/to/database.db",
#   ZZEDC_SALT = "your-secure-salt-string",
#   ZZEDC_ADMIN_EMAIL = "admin@yourinstitution.edu"
# )

## ----sample_data--------------------------------------------------------------
# # Generate sample data for testing
# create_sample_subjects <- function(n = 10) {
#   data.frame(
#     subject_id = paste0("SAMP", sprintf("%03d", 1:n)),
#     age = sample(18:80, n, replace = TRUE),
#     gender = sample(c("Male", "Female"), n, replace = TRUE),
#     enrollment_date = seq(as.Date("2024-01-01"), by = "week", length.out = n),
#     status = sample(c("Active", "Completed", "Withdrawn"), n, replace = TRUE),
#     stringsAsFactors = FALSE
#   )
# }
# 
# sample_data <- create_sample_subjects(20)
# head(sample_data)

## ----database_setup-----------------------------------------------------------
# # Database initialization (done automatically on first launch)
# # Manual setup if needed:
# 
# # 1. Create database directory
# dir.create("data", showWarnings = FALSE)
# 
# # 2. Run setup script (if available)
# # source("setup_database.R")
# 
# # 3. Verify database connection
# # The application will create necessary tables automatically

## ----add_users----------------------------------------------------------------
# # User management workflow:
# # 1. Admin login to ZZedc
# # 2. Navigate to user management
# # 3. Click "Add User"
# # 4. Specify role and permissions
# 
# user_roles <- list(
#   admin = "Full system access",
#   pi = "Study oversight and data review",
#   coordinator = "Data entry and basic reporting",
#   monitor = "Data review and quality control"
# )

## ----data_entry_tips----------------------------------------------------------
# # Best practices for data entry
# best_practices <- list(
#   "Use consistent naming conventions",
#   "Enter data promptly after collection",
#   "Review entries before saving",
#   "Document any issues or deviations",
#   "Regularly backup data",
#   "Train all users on proper procedures"
# )

## ----backup-------------------------------------------------------------------
# # Regular backup workflow:
# # 1. Navigate to Export tab
# # 2. Select "Full Database Export"
# # 3. Choose format (CSV, SPSS, SAS)
# # 4. Download and store securely
# 
# backup_schedule <- list(
#   frequency = "Daily",
#   format = "Multiple formats",
#   location = "Secure server with access controls",
#   retention = "Per institutional policy"
# )

## ----troubleshoot_connection--------------------------------------------------
# # Check if R session is running
# # Verify port 3838 is available
# # Try different port:
# launch_zzedc(port = 3839)

## ----troubleshoot_login-------------------------------------------------------
# # Verify credentials
# # Check if database is accessible
# # Reset password if needed (contact administrator)

## ----troubleshoot_data--------------------------------------------------------
# # Check internet connection
# # Verify database permissions
# # Look for validation errors
# # Try refreshing the browser

## ----file_locations-----------------------------------------------------------
# # Important file locations
# file_structure <- list(
#   database = "data/memory001_study.db",
#   config = "config.yml",
#   logs = "logs/",
#   exports = "exports/",
#   backup = "backup/"
# )

