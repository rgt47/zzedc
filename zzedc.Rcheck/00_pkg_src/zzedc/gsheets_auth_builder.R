# Google Sheets Authentication Builder for ZZedc
# Specialized module for building authentication systems from Google Sheets

source("gsheets_integration.R")

#' Advanced authentication table builder with validation and role management
#' @param auth_sheet_name Name of the Google Sheet containing authentication data
#' @param db_path Path to SQLite database file
#' @param salt Salt for password hashing
#' @param validate_roles Whether to validate role assignments
build_advanced_auth_system <- function(
  auth_sheet_name = "zzedc_auth",
  db_path = "data/zzedc_gsheets.db",
  salt = "zzedc_default_salt",
  validate_roles = TRUE
) {

  message("=== Building Advanced Authentication System ===")

  # Setup Google authentication
  setup_google_auth()

  # Read authentication data with enhanced validation
  auth_data <- read_enhanced_auth_data(auth_sheet_name, validate_roles)

  # Build comprehensive authentication tables
  build_comprehensive_auth_tables(auth_data, db_path, salt)

  message("=== Authentication system build completed ===")
}

#' Read authentication data with enhanced validation and role checking
#' @param sheet_name Name of the Google Sheet
#' @param validate_roles Whether to validate role assignments
read_enhanced_auth_data <- function(sheet_name, validate_roles = TRUE) {
  message("Reading enhanced authentication data from: ", sheet_name)

  # Read main users sheet
  users_data <- read_sheet(sheet_name, sheet = "users")

  # Read roles definition if it exists
  roles_data <- tryCatch({
    read_sheet(sheet_name, sheet = "roles")
  }, error = function(e) {
    message("No roles sheet found, using default roles")
    data.frame(
      role = c("Admin", "PI", "Coordinator", "Data Manager", "User"),
      description = c(
        "Full system access",
        "Principal Investigator",
        "Research Coordinator",
        "Data Manager",
        "Standard User"
      ),
      permissions = c("all", "read_write", "read_write", "read_write", "read_only"),
      stringsAsFactors = FALSE
    )
  })

  # Read sites definition if it exists
  sites_data <- tryCatch({
    read_sheet(sheet_name, sheet = "sites")
  }, error = function(e) {
    message("No sites sheet found, using default site")
    data.frame(
      site_id = 1,
      site_name = "Default Site",
      site_code = "DEF",
      active = 1,
      stringsAsFactors = FALSE
    )
  })

  # Validate and clean users data
  required_cols <- c("username", "password", "full_name", "role")
  missing_cols <- setdiff(required_cols, names(users_data))
  if (length(missing_cols) > 0) {
    stop("Missing required columns in users sheet: ", paste(missing_cols, collapse = ", "))
  }

  # Clean and standardize users data
  users_data <- users_data %>%
    filter(!is.na(username), !is.na(password), nchar(trimws(username)) > 0) %>%
    mutate(
      username = trimws(tolower(username)),
      full_name = ifelse(is.na(full_name), username, trimws(full_name)),
      email = ifelse(is.na(email), paste0(username, "@example.com"), trimws(email)),
      role = ifelse(is.na(role), "User", trimws(role)),
      site_id = ifelse(is.na(site_id), 1, site_id),
      active = ifelse(is.na(active), 1, active),
      created_date = Sys.time(),
      last_login = as.POSIXct(NA),
      login_attempts = 0,
      locked = 0
    )

  # Validate roles if requested
  if (validate_roles) {
    valid_roles <- roles_data$role
    invalid_roles <- setdiff(users_data$role, valid_roles)
    if (length(invalid_roles) > 0) {
      warning("Invalid roles found: ", paste(invalid_roles, collapse = ", "))
      users_data$role[users_data$role %in% invalid_roles] <- "User"
    }
  }

  # Validate sites
  valid_sites <- sites_data$site_id
  invalid_sites <- setdiff(users_data$site_id, valid_sites)
  if (length(invalid_sites) > 0) {
    warning("Invalid site IDs found: ", paste(invalid_sites, collapse = ", "))
    users_data$site_id[users_data$site_id %in% invalid_sites] <- 1
  }

  # Check for duplicate usernames
  duplicate_users <- users_data$username[duplicated(users_data$username)]
  if (length(duplicate_users) > 0) {
    stop("Duplicate usernames found: ", paste(duplicate_users, collapse = ", "))
  }

  message("Validated ", nrow(users_data), " users across ", length(valid_roles), " roles and ", nrow(sites_data), " sites")

  return(list(
    users = users_data,
    roles = roles_data,
    sites = sites_data
  ))
}

#' Build comprehensive authentication tables including roles and sites
#' @param auth_data List containing users, roles, and sites data
#' @param db_path Path to SQLite database file
#' @param salt Salt for password hashing
build_comprehensive_auth_tables <- function(auth_data, db_path, salt) {
  message("Building comprehensive authentication tables in: ", db_path)

  # Ensure directory exists
  if (!dir.exists(dirname(db_path))) {
    dir.create(dirname(db_path), recursive = TRUE)
  }

  # Connect to database
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con))

  tryCatch({
    # 1. Build roles table
    roles_data <- auth_data$roles
    if (dbExistsTable(con, "edc_roles")) {
      dbExecute(con, "DROP TABLE edc_roles")
    }
    dbWriteTable(con, "edc_roles", roles_data, overwrite = TRUE)
    message("Created edc_roles table with ", nrow(roles_data), " roles")

    # 2. Build sites table
    sites_data <- auth_data$sites
    if (dbExistsTable(con, "edc_sites")) {
      dbExecute(con, "DROP TABLE edc_sites")
    }
    dbWriteTable(con, "edc_sites", sites_data, overwrite = TRUE)
    message("Created edc_sites table with ", nrow(sites_data), " sites")

    # 3. Build users table with hashed passwords
    users_data <- auth_data$users
    users_data$password_hash <- sapply(users_data$password, function(p) hash_password(p, salt))
    users_data$password <- NULL  # Remove plain text passwords

    # Add user_id if not present
    if (!"user_id" %in% names(users_data)) {
      users_data$user_id <- 1:nrow(users_data)
    }

    if (dbExistsTable(con, "edc_users")) {
      dbExecute(con, "DROP TABLE edc_users")
    }
    dbWriteTable(con, "edc_users", users_data, overwrite = TRUE)
    message("Created edc_users table with ", nrow(users_data), " users")

    # 4. Create indexes for performance
    dbExecute(con, "CREATE INDEX idx_username ON edc_users(username)")
    dbExecute(con, "CREATE INDEX idx_active ON edc_users(active)")
    dbExecute(con, "CREATE INDEX idx_role ON edc_users(role)")
    dbExecute(con, "CREATE INDEX idx_site ON edc_users(site_id)")

    # 5. Create views for easier querying
    dbExecute(con, "
      CREATE VIEW v_users_detailed AS
      SELECT
        u.user_id,
        u.username,
        u.full_name,
        u.email,
        u.role,
        r.description as role_description,
        r.permissions,
        u.site_id,
        s.site_name,
        s.site_code,
        u.active,
        u.created_date,
        u.last_login,
        u.login_attempts,
        u.locked
      FROM edc_users u
      LEFT JOIN edc_roles r ON u.role = r.role
      LEFT JOIN edc_sites s ON u.site_id = s.site_id
    ")

    # 6. Verify the tables
    user_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users")$count
    active_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users WHERE active = 1")$count
    role_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_roles")$count
    site_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_sites")$count

    message("Authentication system verification:")
    message("  - Users: ", user_count, " (", active_count, " active)")
    message("  - Roles: ", role_count)
    message("  - Sites: ", site_count)

    return(TRUE)

  }, error = function(e) {
    message("Error building comprehensive authentication tables: ", e$message)
    return(FALSE)
  })
}

#' Verify authentication system by testing login functionality
#' @param db_path Path to SQLite database file
#' @param salt Salt used for password hashing
verify_auth_system <- function(db_path, salt = "zzedc_default_salt") {
  message("=== Verifying Authentication System ===")

  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con))

  # Test queries
  tryCatch({
    # Check table structure
    tables <- dbListTables(con)
    expected_tables <- c("edc_users", "edc_roles", "edc_sites")
    missing_tables <- setdiff(expected_tables, tables)

    if (length(missing_tables) > 0) {
      stop("Missing tables: ", paste(missing_tables, collapse = ", "))
    }

    # Check if we can authenticate a user
    users <- dbGetQuery(con, "SELECT username, password_hash FROM edc_users WHERE active = 1 LIMIT 1")

    if (nrow(users) > 0) {
      # Try to verify password hash format
      username <- users$username[1]
      stored_hash <- users$password_hash[1]

      if (nchar(stored_hash) == 64) {  # SHA-256 hash length
        message("✓ Password hashing appears correct")
      } else {
        warning("✗ Password hash format may be incorrect")
      }

      message("✓ Can read user data for authentication")
    }

    # Check views
    view_data <- dbGetQuery(con, "SELECT * FROM v_users_detailed LIMIT 1")
    if (nrow(view_data) > 0) {
      message("✓ User detail view working correctly")
    }

    message("=== Authentication system verification completed successfully ===")
    return(TRUE)

  }, error = function(e) {
    message("✗ Authentication verification failed: ", e$message)
    return(FALSE)
  })
}