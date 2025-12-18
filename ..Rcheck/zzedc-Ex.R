pkgname <- "zzedc"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
library('zzedc')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("check_aws_kms_status")
### * check_aws_kms_status

flush(stderr()); flush(stdout())

### Name: check_aws_kms_status
### Title: Check AWS KMS Status and Permissions
### Aliases: check_aws_kms_status

### ** Examples

## Not run: 
##D   status <- check_aws_kms_status()
##D 
##D   if (status$configured) {
##D     cat("AWS KMS fully configured\n")
##D   } else {
##D     cat("Issues found:\n")
##D     cat("Errors:", status$errors, "\n")
##D   }
## End(Not run)




cleanEx()
nameEx("connect_encrypted_db")
### * connect_encrypted_db

flush(stderr()); flush(stdout())

### Name: connect_encrypted_db
### Title: Connect to Encrypted Database
### Aliases: connect_encrypted_db

### ** Examples

## Not run: 
##D   # Development (environment variable):
##D   Sys.setenv(DB_ENCRYPTION_KEY = "a1b2c3d4...")
##D   conn <- connect_encrypted_db()
##D 
##D   # Production (AWS KMS):
##D   conn <- connect_encrypted_db(aws_kms_key_id = "arn:aws:kms:...")
##D 
##D   # Use connection normally
##D   result <- DBI::dbGetQuery(conn, "SELECT * FROM subjects")
##D   DBI::dbDisconnect(conn)
## End(Not run)




cleanEx()
nameEx("create_export_manifest")
### * create_export_manifest

flush(stderr()); flush(stdout())

### Name: create_export_manifest
### Title: Create Export Manifest
### Aliases: create_export_manifest

### ** Examples

## Not run: 
##D   manifest_path <- create_export_manifest(
##D     export_file_path = "./exports/export_subjects_20251218_123456.csv",
##D     metadata = list(
##D       study_id = "TOY-TRIAL-001",
##D       export_reason = "DSMB Review",
##D       exported_by = "john_doe"
##D     )
##D   )
## End(Not run)




cleanEx()
nameEx("create_wizard_database")
### * create_wizard_database

flush(stderr()); flush(stdout())

### Name: create_wizard_database
### Title: Create ZZedc Database from Wizard Configuration
### Aliases: create_wizard_database

### ** Examples

## Not run: 
##D config <- list(
##D   study_name = "My Study",
##D   protocol_id = "PROTO-001",
##D   admin_username = "admin",
##D   admin_password = "MyPass123!",
##D   security_salt = "abc123..."
##D )
##D create_wizard_database(config, "~/my_study.db")
## End(Not run)



cleanEx()
nameEx("export_encrypted_data")
### * export_encrypted_data

flush(stderr()); flush(stdout())

### Name: export_encrypted_data
### Title: Export Encrypted Data with Integrity Verification
### Aliases: export_encrypted_data

### ** Examples

## Not run: 
##D   # Export all subjects
##D   file_path <- export_encrypted_data(
##D     query = "SELECT * FROM subjects",
##D     format = "csv"
##D   )
##D 
##D   # Export with password protection
##D   file_path <- export_encrypted_data(
##D     query = "SELECT * FROM mmse_assessments WHERE visit_label = 'Baseline'",
##D     format = "xlsx",
##D     password = "secure_password"
##D   )
## End(Not run)




cleanEx()
nameEx("generate_db_key")
### * generate_db_key

flush(stderr()); flush(stdout())

### Name: generate_db_key
### Title: Generate a random database encryption key
### Aliases: generate_db_key

### ** Examples

## Not run: 
##D   key <- generate_db_key()
##D   Sys.setenv(DB_ENCRYPTION_KEY = key)
## End(Not run)




cleanEx()
nameEx("get_db_path")
### * get_db_path

flush(stderr()); flush(stdout())

### Name: get_db_path
### Title: Get Database Path
### Aliases: get_db_path

### ** Examples

## Not run: 
##D   db_path <- get_db_path()
##D   # Returns: "/path/to/data/zzedc.db"
## End(Not run)




cleanEx()
nameEx("get_encryption_key")
### * get_encryption_key

flush(stderr()); flush(stdout())

### Name: get_encryption_key
### Title: Get database encryption key from environment or AWS KMS
### Aliases: get_encryption_key

### ** Examples

## Not run: 
##D   # Development (environment variable):
##D   Sys.setenv(DB_ENCRYPTION_KEY = "a1b2c3d4...")
##D   key <- get_encryption_key()
##D 
##D   # Production (AWS KMS):
##D   key <- get_encryption_key(aws_kms_key_id = "arn:aws:kms:...")
## End(Not run)




cleanEx()
nameEx("get_encryption_key_from_aws_kms")
### * get_encryption_key_from_aws_kms

flush(stderr()); flush(stdout())

### Name: get_encryption_key_from_aws_kms
### Title: Retrieve encryption key from AWS Secrets Manager
### Aliases: get_encryption_key_from_aws_kms
### Keywords: internal

### ** Examples

## Not run: 
##D   # Requires AWS credentials
##D   key <- get_encryption_key_from_aws_kms("zzedc/db-encryption-key")
## End(Not run)




cleanEx()
nameEx("get_export_history")
### * get_export_history

flush(stderr()); flush(stdout())

### Name: get_export_history
### Title: Get Export Activity History
### Aliases: get_export_history

### ** Examples

## Not run: 
##D   # Get all exports in last 7 days
##D   history <- get_export_history(
##D     filters = list(date_from = Sys.Date() - 7)
##D   )
##D 
##D   # Get exports by user
##D   history <- get_export_history(
##D     filters = list(user = "jane_smith")
##D   )
## End(Not run)




cleanEx()
nameEx("handle_error")
### * handle_error

flush(stderr()); flush(stdout())

### Name: handle_error
### Title: Handle errors with logging and user notification
### Aliases: handle_error

### ** Examples

## Not run: 
##D result <- handle_error({
##D   authenticate_user(username, password)
##D }, error_title = "Authentication Failed")
## End(Not run)



cleanEx()
nameEx("import_instrument")
### * import_instrument

flush(stderr()); flush(stdout())

### Name: import_instrument
### Title: Import instrument as new form
### Aliases: import_instrument

### ** Examples

## Not run: 
##D result <- import_instrument(
##D   instrument_name = "phq9",
##D   form_name = "baseline_depression",
##D   form_description = "PHQ-9 administered at baseline visit",
##D   db_conn = conn
##D )
## End(Not run)



cleanEx()
nameEx("init")
### * init

flush(stderr()); flush(stdout())

### Name: init
### Title: Initialize ZZedc Project
### Aliases: init

### ** Examples

## Not run: 
##D # Interactive mode (novice user)
##D zzedc::init()
##D 
##D # Config file mode (DevOps)
##D zzedc::init(mode = "config", config_file = "aws_config.yml")
## End(Not run)




cleanEx()
nameEx("init_audit_log")
### * init_audit_log

flush(stderr()); flush(stdout())

### Name: init_audit_log
### Title: Initialize audit log
### Aliases: init_audit_log

### ** Examples

## Not run: 
##D audit_log <- init_audit_log()
##D log_audit_event(audit_log, "user1", "LOGIN", "authentication", status = "success")
## End(Not run)



cleanEx()
nameEx("initialize_encrypted_database")
### * initialize_encrypted_database

flush(stderr()); flush(stdout())

### Name: initialize_encrypted_database
### Title: Initialize Encrypted Database
### Aliases: initialize_encrypted_database

### ** Examples

## Not run: 
##D   result <- initialize_encrypted_database(
##D     db_path = "./data/new_study.db",
##D     overwrite = FALSE
##D   )
##D   if (result$success) {
##D     cat("Database created at:", result$path, "\n")
##D   }
## End(Not run)




cleanEx()
nameEx("launch_zzedc")
### * launch_zzedc

flush(stderr()); flush(stdout())

### Name: launch_zzedc
### Title: Launch the ZZedc Shiny Application
### Aliases: launch_zzedc

### ** Examples

## Not run: 
##D # Launch the application
##D launch_zzedc()
##D 
##D # Launch on specific port
##D launch_zzedc(port = 3838)
##D 
##D # Launch without opening browser
##D launch_zzedc(launch.browser = FALSE)
## End(Not run)




cleanEx()
nameEx("list_available_instruments")
### * list_available_instruments

flush(stderr()); flush(stdout())

### Name: list_available_instruments
### Title: List available instruments
### Aliases: list_available_instruments

### ** Examples

## Not run: 
##D available <- list_available_instruments()
##D print(available)
## End(Not run)



cleanEx()
nameEx("load_instrument_template")
### * load_instrument_template

flush(stderr()); flush(stdout())

### Name: load_instrument_template
### Title: Load instrument template from CSV
### Aliases: load_instrument_template

### ** Examples

## Not run: 
##D phq9_fields <- load_instrument_template("phq9")
##D head(phq9_fields)
## End(Not run)



cleanEx()
nameEx("log_audit_event")
### * log_audit_event

flush(stderr()); flush(stdout())

### Name: log_audit_event
### Title: Log an audit event
### Aliases: log_audit_event

### ** Examples

## Not run: 
##D audit_log <- init_audit_log()
##D log_audit_event(
##D   audit_log,
##D   user_id = "john.doe",
##D   action = "LOGIN_ATTEMPT",
##D   resource = "authentication",
##D   status = "success"
##D )
## End(Not run)



cleanEx()
nameEx("paginate_data")
### * paginate_data

flush(stderr()); flush(stdout())

### Name: paginate_data
### Title: Create paginated data view
### Aliases: paginate_data

### ** Examples

## Not run: 
##D paginated <- paginate_data(
##D   large_dataset,
##D   page_size = 25,
##D   page_number = 1
##D )
##D display_data(paginated$data)
##D show_page_numbers(paginated$pagination$total_pages)
## End(Not run)



cleanEx()
nameEx("prepare_export_data")
### * prepare_export_data

flush(stderr()); flush(stdout())

### Name: prepare_export_data
### Title: Prepare data for export
### Aliases: prepare_export_data

### ** Examples

## Not run: 
##D export_result <- prepare_export_data(
##D   data_source = "edc",
##D   format = "csv",
##D   options = list(include_metadata = TRUE, include_timestamps = TRUE)
##D )
## End(Not run)



cleanEx()
nameEx("renderPanel")
### * renderPanel

flush(stderr()); flush(stdout())

### Name: renderPanel
### Title: Render form panel with typed input fields
### Aliases: renderPanel

### ** Examples

## Not run: 
##D metadata <- list(
##D   age = list(type = "numeric", required = TRUE, label = "Age (years)"),
##D   gender = list(
##D     type = "select",
##D     choices = c("M", "F"),
##D     label = "Gender"
##D   ),
##D   pregnancy_date = list(
##D     type = "date",
##D     label = "Pregnancy Due Date",
##D     show_if = "gender == 'F'"  # Branching logic
##D   ),
##D   visit_time = list(type = "time", required = TRUE, label = "Visit Time")
##D )
##D renderPanel(names(metadata), metadata)
## End(Not run)




cleanEx()
nameEx("rotate_encryption_key")
### * rotate_encryption_key

flush(stderr()); flush(stdout())

### Name: rotate_encryption_key
### Title: Rotate Database Encryption Key via AWS KMS
### Aliases: rotate_encryption_key

### ** Examples

## Not run: 
##D   new_key <- generate_db_key()
##D   result <- rotate_encryption_key(new_key)
##D   if (result$success) {
##D     cat("Key rotation successful\n")
##D   }
## End(Not run)




cleanEx()
nameEx("selective_field_export")
### * selective_field_export

flush(stderr()); flush(stdout())

### Name: selective_field_export
### Title: Selective Field Encryption on Export
### Aliases: selective_field_export

### ** Examples

## Not run: 
##D   # Encrypt PII fields
##D   file_path <- selective_field_export(
##D     data_df = subjects_data,
##D     fields_to_encrypt = c("subject_id", "age"),
##D     format = "csv"
##D   )
## End(Not run)




cleanEx()
nameEx("set_encryption_for_existing_db")
### * set_encryption_for_existing_db

flush(stderr()); flush(stdout())

### Name: set_encryption_for_existing_db
### Title: Enable Encryption on Existing Database
### Aliases: set_encryption_for_existing_db

### ** Examples

## Not run: 
##D   result <- set_encryption_for_existing_db(
##D     db_path = "./data/existing.db",
##D     new_key = generate_db_key()
##D   )
##D   if (result$success) {
##D     cat("Encryption enabled!\n")
##D   }
## End(Not run)




cleanEx()
nameEx("setup_aws_kms")
### * setup_aws_kms

flush(stderr()); flush(stdout())

### Name: setup_aws_kms
### Title: Setup AWS KMS Integration for ZZedc
### Aliases: setup_aws_kms

### ** Examples

## Not run: 
##D   status <- setup_aws_kms()
##D   if (status$aws_configured) {
##D     cat("AWS KMS ready for key management\n")
##D   } else {
##D     cat("Setup errors:", status$errors, "\n")
##D   }
## End(Not run)




cleanEx()
nameEx("test_encryption")
### * test_encryption

flush(stderr()); flush(stdout())

### Name: test_encryption
### Title: Test database encryption
### Aliases: test_encryption

### ** Examples

## Not run: 
##D   key <- generate_db_key()
##D   test_encryption(tempfile(fileext = ".db"), key)
## End(Not run)




cleanEx()
nameEx("validate_form")
### * validate_form

flush(stderr()); flush(stdout())

### Name: validate_form
### Title: Validate entire form submission
### Aliases: validate_form

### ** Examples

## Not run: 
##D metadata <- list(
##D   age = list(type = "numeric", required = TRUE, min = 18, max = 120),
##D   email = list(type = "email", required = TRUE)
##D )
##D 
##D result <- validate_form(
##D   list(age = 25, email = "user@example.com"),
##D   metadata
##D )
##D 
##D if (result$valid) {
##D   # Process the cleaned data
##D   save_record(result$cleaned_data)
##D } else {
##D   # Show errors to user
##D   show_validation_errors(result$errors)
##D }
## End(Not run)



cleanEx()
nameEx("verify_database_encryption")
### * verify_database_encryption

flush(stderr()); flush(stdout())

### Name: verify_database_encryption
### Title: Verify Database Encryption
### Aliases: verify_database_encryption

### ** Examples

## Not run: 
##D   verification <- verify_database_encryption()
##D   if (verification$encrypted) {
##D     cat("Database encryption verified!\n")
##D   } else {
##D     cat("Encryption issues:", verification$message, "\n")
##D   }
## End(Not run)




cleanEx()
nameEx("verify_db_key")
### * verify_db_key

flush(stderr()); flush(stdout())

### Name: verify_db_key
### Title: Verify database encryption key format
### Aliases: verify_db_key

### ** Examples

## Not run: 
##D   key <- generate_db_key()
##D   verify_db_key(key)  # Returns TRUE
## End(Not run)




cleanEx()
nameEx("verify_exported_data")
### * verify_exported_data

flush(stderr()); flush(stdout())

### Name: verify_exported_data
### Title: Verify Exported Data Integrity
### Aliases: verify_exported_data

### ** Examples

## Not run: 
##D   verification <- verify_exported_data(
##D     file_path = "./exports/export_subjects_20251218_123456.csv"
##D   )
##D   if (verification$valid) {
##D     cat("Data integrity verified!\n")
##D   }
## End(Not run)




### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
