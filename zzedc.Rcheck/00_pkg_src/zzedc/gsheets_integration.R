# Google Sheets Integration Module for ZZedc
# Builds authentication tables and data dictionaries from Google Sheets

library(pacman)
p_load(googlesheets4, googledrive, dplyr, RSQLite, digest, readxl, stringr, lubridate)

# Configuration for Google Sheets EDC setup
GSHEETS_CONFIG <- list(
  # Expected Google Sheets structure
  auth_sheet_name = "zzedc_auth",           # Sheet containing user authentication data
  dd_sheet_name = "zzedc_data_dictionary",  # Sheet containing data dictionary

  # Authentication sheet columns (expected)
  auth_columns = c("username", "password", "full_name", "email", "role", "site_id", "active"),

  # Data dictionary sheet structure
  dd_main_sheet = "forms_overview",         # Main sheet listing all forms
  dd_form_prefix = "form_",                 # Prefix for individual form sheets

  # Standard data dictionary columns
  dd_columns = c("field", "prompt", "type", "length", "layout", "values", "cond", "req", "valid", "validmsg")
)

#' Authenticate with Google Sheets
#' Uses token-based authentication similar to c060 approach
setup_google_auth <- function(token_file = "googlesheets_token.rds") {
  if (file.exists(token_file)) {
    message("Using existing Google Sheets token...")
    gs4_auth(path = token_file)
  } else {
    message("Creating new Google Sheets authentication...")
    gs4_auth()
    # Save token for future use
    token <- gs4_token()
    saveRDS(token, file = token_file)
    message("Google Sheets token saved to: ", token_file)
  }
}

#' Read authentication data from Google Sheets
#' @param sheet_name Name of the Google Sheet containing authentication data
#' @return data.frame with authentication data
read_auth_from_gsheets <- function(sheet_name = GSHEETS_CONFIG$auth_sheet_name) {
  tryCatch({
    message("Reading authentication data from Google Sheets: ", sheet_name)

    # Read the authentication sheet
    auth_data <- read_sheet(sheet_name, sheet = "users")

    # Validate required columns
    required_cols <- GSHEETS_CONFIG$auth_columns
    missing_cols <- setdiff(required_cols, names(auth_data))
    if (length(missing_cols) > 0) {
      stop("Missing required columns in auth sheet: ", paste(missing_cols, collapse = ", "))
    }

    # Clean and validate data
    auth_data <- auth_data %>%
      filter(!is.na(username), !is.na(password)) %>%
      mutate(
        username = trimws(username),
        active = ifelse(is.na(active), 1, active),
        role = ifelse(is.na(role), "User", role),
        site_id = ifelse(is.na(site_id), 1, site_id),
        created_date = Sys.time(),
        last_login = as.POSIXct(NA)
      )

    message("Successfully read ", nrow(auth_data), " user records from Google Sheets")
    return(auth_data)

  }, error = function(e) {
    stop("Error reading authentication data from Google Sheets: ", e$message)
  })
}

#' Read data dictionary from Google Sheets
#' @param sheet_name Name of the Google Sheet containing data dictionary
#' @return list with forms overview and individual form definitions
read_dd_from_gsheets <- function(sheet_name = GSHEETS_CONFIG$dd_sheet_name) {
  tryCatch({
    message("Reading data dictionary from Google Sheets: ", sheet_name)

    # Read the main forms overview sheet
    forms_overview <- read_sheet(sheet_name, sheet = GSHEETS_CONFIG$dd_main_sheet)

    # Validate forms overview structure
    required_cols <- c("workingname", "fullname", "visits")
    missing_cols <- setdiff(required_cols, names(forms_overview))
    if (length(missing_cols) > 0) {
      stop("Missing required columns in forms overview: ", paste(missing_cols, collapse = ", "))
    }

    # Read individual form definitions
    form_definitions <- list()

    for (i in 1:nrow(forms_overview)) {
      form_name <- forms_overview$workingname[i]
      sheet_name_full <- paste0(GSHEETS_CONFIG$dd_form_prefix, form_name)

      message("Reading form definition: ", sheet_name_full)

      tryCatch({
        form_def <- read_sheet(sheet_name, sheet = sheet_name_full)

        # Add default values for missing columns
        expected_cols <- GSHEETS_CONFIG$dd_columns
        for (col in expected_cols) {
          if (!col %in% names(form_def)) {
            form_def[[col]] <- NA
          }
        }

        # Clean and standardize the form definition
        form_def <- form_def %>%
          mutate(
            req = ifelse(is.na(req), 0, req),
            type = ifelse(is.na(type), "C", type),
            layout = ifelse(is.na(layout), "text", layout)
          ) %>%
          filter(!is.na(field))  # Remove empty rows

        form_definitions[[form_name]] <- form_def

      }, error = function(e) {
        warning("Could not read form definition '", sheet_name_full, "': ", e$message)
      })
    }

    message("Successfully read ", length(form_definitions), " form definitions from Google Sheets")

    return(list(
      forms_overview = forms_overview,
      form_definitions = form_definitions
    ))

  }, error = function(e) {
    stop("Error reading data dictionary from Google Sheets: ", e$message)
  })
}

#' Hash password with salt for database storage
#' @param password Plain text password
#' @param salt Salt value (from config or environment)
#' @return Hashed password string
hash_password <- function(password, salt = "zzedc_default_salt") {
  digest(paste0(password, salt), algo = "sha256")
}

#' Build authentication tables in SQLite database from Google Sheets data
#' @param auth_data Authentication data from Google Sheets
#' @param db_path Path to SQLite database file
#' @param salt Salt for password hashing
build_auth_tables <- function(auth_data, db_path, salt = "zzedc_default_salt") {
  message("Building authentication tables in database: ", db_path)

  # Connect to database
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con))

  tryCatch({
    # Hash passwords
    auth_data$password_hash <- sapply(auth_data$password, function(p) hash_password(p, salt))

    # Remove plain text passwords
    auth_data$password <- NULL

    # Add user_id if not present
    if (!"user_id" %in% names(auth_data)) {
      auth_data$user_id <- 1:nrow(auth_data)
    }

    # Drop existing table if it exists
    if (dbExistsTable(con, "edc_users")) {
      dbExecute(con, "DROP TABLE edc_users")
      message("Dropped existing edc_users table")
    }

    # Write authentication data to database
    dbWriteTable(con, "edc_users", auth_data, overwrite = TRUE)

    # Create indexes for performance
    dbExecute(con, "CREATE INDEX idx_username ON edc_users(username)")
    dbExecute(con, "CREATE INDEX idx_active ON edc_users(active)")

    message("Successfully created edc_users table with ", nrow(auth_data), " users")

    # Verify the table was created correctly
    user_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users")$count
    active_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users WHERE active = 1")$count

    message("Database verification: ", user_count, " total users, ", active_count, " active users")

    return(TRUE)

  }, error = function(e) {
    message("Error building authentication tables: ", e$message)
    return(FALSE)
  })
}

#' Build data dictionary tables in SQLite database from Google Sheets data
#' @param dd_data Data dictionary data from Google Sheets
#' @param db_path Path to SQLite database file
build_dd_tables <- function(dd_data, db_path) {
  message("Building data dictionary tables in database: ", db_path)

  # Connect to database
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con))

  tryCatch({
    # Build forms overview table
    forms_overview <- dd_data$forms_overview

    if (dbExistsTable(con, "edc_forms")) {
      dbExecute(con, "DROP TABLE edc_forms")
    }

    dbWriteTable(con, "edc_forms", forms_overview, overwrite = TRUE)
    message("Created edc_forms table with ", nrow(forms_overview), " forms")

    # Build individual form field tables
    form_definitions <- dd_data$form_definitions

    # Create a unified fields table
    all_fields <- data.frame()

    for (form_name in names(form_definitions)) {
      form_def <- form_definitions[[form_name]]
      form_def$form_name <- form_name
      all_fields <- rbind(all_fields, form_def)
    }

    if (dbExistsTable(con, "edc_fields")) {
      dbExecute(con, "DROP TABLE edc_fields")
    }

    dbWriteTable(con, "edc_fields", all_fields, overwrite = TRUE)
    message("Created edc_fields table with ", nrow(all_fields), " fields")

    # Create indexes
    dbExecute(con, "CREATE INDEX idx_form_name ON edc_fields(form_name)")
    dbExecute(con, "CREATE INDEX idx_field_name ON edc_fields(field)")

    # Create data storage tables for each form
    for (form_name in names(form_definitions)) {
      form_def <- form_definitions[[form_name]]
      table_name <- paste0("data_", form_name)

      # Drop existing table
      if (dbExistsTable(con, table_name)) {
        dbExecute(con, paste("DROP TABLE", table_name))
      }

      # Build CREATE TABLE statement
      col_definitions <- c(
        "record_id INTEGER PRIMARY KEY AUTOINCREMENT",
        "subject_id TEXT",
        "site_id TEXT",
        "visit TEXT",
        "entry_date TEXT",
        "user_id TEXT"
      )

      # Add form-specific columns
      for (i in 1:nrow(form_def)) {
        field_name <- form_def$field[i]
        field_type <- form_def$type[i]

        sql_type <- case_when(
          field_type == "N" ~ "REAL",
          field_type == "D" ~ "TEXT",
          field_type == "L" ~ "INTEGER",
          TRUE ~ "TEXT"
        )

        col_definitions <- c(col_definitions, paste(field_name, sql_type))
      }

      create_sql <- paste("CREATE TABLE", table_name, "(", paste(col_definitions, collapse = ", "), ")")
      dbExecute(con, create_sql)

      message("Created data table: ", table_name)
    }

    return(TRUE)

  }, error = function(e) {
    message("Error building data dictionary tables: ", e$message)
    return(FALSE)
  })
}

#' Main function to setup ZZedc from Google Sheets
#' @param auth_sheet_name Name of authentication Google Sheet
#' @param dd_sheet_name Name of data dictionary Google Sheet
#' @param db_path Path to SQLite database file
#' @param salt Salt for password hashing
#' @param token_file Path to Google Sheets token file
setup_zzedc_from_gsheets <- function(
  auth_sheet_name = GSHEETS_CONFIG$auth_sheet_name,
  dd_sheet_name = GSHEETS_CONFIG$dd_sheet_name,
  db_path = "data/zzedc_gsheets.db",
  salt = "zzedc_default_salt",
  token_file = "googlesheets_token.rds"
) {

  message("=== Setting up ZZedc from Google Sheets ===")
  message("Authentication sheet: ", auth_sheet_name)
  message("Data dictionary sheet: ", dd_sheet_name)
  message("Database path: ", db_path)

  # Ensure data directory exists
  if (!dir.exists(dirname(db_path))) {
    dir.create(dirname(db_path), recursive = TRUE)
  }

  # Step 1: Setup Google authentication
  setup_google_auth(token_file)

  # Step 2: Read authentication data
  auth_data <- read_auth_from_gsheets(auth_sheet_name)

  # Step 3: Read data dictionary
  dd_data <- read_dd_from_gsheets(dd_sheet_name)

  # Step 4: Build authentication tables
  auth_success <- build_auth_tables(auth_data, db_path, salt)

  # Step 5: Build data dictionary tables
  dd_success <- build_dd_tables(dd_data, db_path)

  if (auth_success && dd_success) {
    message("=== ZZedc setup completed successfully! ===")
    message("Database created at: ", db_path)
    message("Ready to launch ZZedc application")
    return(TRUE)
  } else {
    message("=== ZZedc setup failed ===")
    return(FALSE)
  }
}

#' Helper function to create template Google Sheets for ZZedc
create_template_gsheets <- function() {
  message("This function would create template Google Sheets with proper structure")
  message("Templates should include:")
  message("1. Authentication sheet with columns: username, password, full_name, email, role, site_id, active")
  message("2. Data dictionary sheet with forms_overview and form_* sheets")
  message("3. Proper column structures as defined in GSHEETS_CONFIG")
}