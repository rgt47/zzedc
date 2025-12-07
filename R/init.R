#' Initialize ZZedc Project
#'
#' Create a new ZZedc project locally or on a server.
#' Two modes available:
#' - Interactive: User-friendly prompts in R console (recommended for novices)
#' - Config: Read from YAML configuration file (recommended for DevOps/AWS)
#'
#' @param mode Character. Either "interactive" (default) or "config"
#' @param config_file Character. Path to configuration YAML file (required if mode="config")
#' @param project_dir Character. Directory where project will be created (default: current directory)
#'
#' @details
#' ## Interactive Mode
#' Guides users through setup with prompts in the R console:
#' ```r
#' zzedc::init()
#' # Will ask for:
#' # - Study name
#' # - Protocol ID
#' # - PI information
#' # - Admin account details
#' # - Security settings
#' ```
#'
#' ## Config File Mode
#' Reads configuration from YAML file (non-interactive):
#' ```r
#' zzedc::init(mode = "config", config_file = "zzedc_config.yml")
#' # Silently creates project from config
#' # Useful for automation, Docker, AWS
#' ```
#'
#' @return Invisibly returns list with setup results and project location
#'
#' @examples
#' \dontrun{
#' # Interactive mode (novice user)
#' zzedc::init()
#'
#' # Config file mode (DevOps)
#' zzedc::init(mode = "config", config_file = "aws_config.yml")
#' }
#'
#' @export
init <- function(mode = "interactive", config_file = NULL, project_dir = ".") {

  cat("\n")
  cat("╔═══════════════════════════════════════════════════════════╗\n")
  cat("║          ZZedc Project Initialization                    ║\n")
  cat("║          Electronic Data Capture System Setup             ║\n")
  cat("╚═══════════════════════════════════════════════════════════╝\n\n")

  if (mode == "interactive") {
    return(init_interactive(project_dir = project_dir))
  } else if (mode == "config") {
    if (is.null(config_file)) {
      stop("config_file parameter required when mode='config'")
    }
    return(init_from_config(config_file = config_file, project_dir = project_dir))
  } else {
    stop("mode must be 'interactive' or 'config'")
  }
}


#' Interactive Mode: Guided Setup
#'
#' @param project_dir Directory where project will be created
#' @return List with setup results
#' @keywords internal
init_interactive <- function(project_dir = ".") {

  cat("Welcome to ZZedc Setup!\n")
  cat("This will guide you through setting up your research study.\n\n")

  # Step 1: Study Information
  cat("Step 1: Study Information\n")
  cat("────────────────────────────────────────────\n\n")

  study_name <- readline(prompt = "Study Name (e.g., 'Depression Treatment Trial'): ")
  if (study_name == "") {
    stop("Study name is required")
  }

  protocol_id <- readline(prompt = "Protocol ID (e.g., 'DEPR-2024-001'): ")
  if (protocol_id == "") {
    stop("Protocol ID is required")
  }

  pi_name <- readline(prompt = "Principal Investigator Name (e.g., 'Dr. Jane Smith'): ")
  if (pi_name == "") {
    stop("PI name is required")
  }

  pi_email <- readline(prompt = "PI Email (e.g., 'jane@university.edu'): ")
  if (pi_email == "" || !grepl("^[^@]+@[^@]+\\.[^@]+$", pi_email)) {
    stop("Valid email address is required")
  }

  target_enrollment <- readline(prompt = "Target Enrollment (e.g., '50'): ")
  if (target_enrollment == "" || is.na(as.numeric(target_enrollment))) {
    stop("Target enrollment must be a number")
  }

  study_phase <- readline(prompt = "Study Phase (Pilot/Phase1/Phase2/Phase3/Phase4/Observational): ")
  if (study_phase == "") {
    study_phase <- "Pilot"
  }

  cat("\n✓ Study information recorded\n\n")

  # Step 2: Administrator Account
  cat("Step 2: Administrator Account\n")
  cat("────────────────────────────────────────────\n\n")

  admin_username <- readline(prompt = "Admin Username (e.g., 'jane_smith'): ")
  if (admin_username == "" || grepl(" ", admin_username)) {
    stop("Username is required and cannot contain spaces")
  }

  admin_fullname <- readline(prompt = "Your Full Name: ")
  if (admin_fullname == "") {
    stop("Full name is required")
  }

  admin_email <- readline(prompt = "Your Email: ")
  if (admin_email == "" || !grepl("^[^@]+@[^@]+\\.[^@]+$", admin_email)) {
    stop("Valid email address is required")
  }

  # Password entry (hidden)
  cat("Create a strong password (8+ characters, mix of letters/numbers/symbols)\n")
  admin_password <- readline(prompt = "Admin Password: ")
  if (nchar(admin_password) < 8) {
    stop("Password must be at least 8 characters")
  }

  admin_password_confirm <- readline(prompt = "Confirm Password: ")
  if (admin_password != admin_password_confirm) {
    stop("Passwords do not match")
  }

  cat("\n✓ Administrator account created\n\n")

  # Step 3: Security Configuration
  cat("Step 3: Security Configuration\n")
  cat("────────────────────────────────────────────\n\n")

  # Generate security salt
  security_salt <- paste0(
    sample(c(letters, LETTERS, 0:9), 32, replace = TRUE),
    collapse = ""
  )

  cat("A unique security salt has been generated for your system:\n")
  cat(sprintf("  %s\n\n", security_salt))
  cat("⚠️  IMPORTANT: Save this salt in a secure location!\n")
  cat("   If you lose it, you cannot recover your passwords.\n\n")

  saved_salt <- readline(prompt = "Have you saved the security salt? (yes/no): ")
  if (tolower(saved_salt) != "yes") {
    cat("Please save the security salt before continuing.\n")
    stop("Setup cancelled - security salt not saved")
  }

  session_timeout <- readline(prompt = "Session Timeout in minutes (default 30): ")
  if (session_timeout == "") {
    session_timeout <- 30
  } else {
    session_timeout <- as.numeric(session_timeout)
  }

  enforce_https <- readline(prompt = "Enforce HTTPS? (yes/no, default yes): ")
  enforce_https <- tolower(enforce_https) %in% c("yes", "y", "")

  cat("\n✓ Security configuration complete\n\n")

  # Step 4: Confirmation
  cat("Step 4: Confirmation\n")
  cat("────────────────────────────────────────────\n\n")

  cat("Summary of your configuration:\n\n")
  cat(sprintf("  Study Name: %s\n", study_name))
  cat(sprintf("  Protocol ID: %s\n", protocol_id))
  cat(sprintf("  PI: %s (%s)\n", pi_name, pi_email))
  cat(sprintf("  Target Enrollment: %s\n", target_enrollment))
  cat(sprintf("  Study Phase: %s\n", study_phase))
  cat(sprintf("  Admin Username: %s\n", admin_username))
  cat(sprintf("  Session Timeout: %d minutes\n", session_timeout))
  cat(sprintf("  Enforce HTTPS: %s\n\n", ifelse(enforce_https, "Yes", "No")))

  confirm <- readline(prompt = "Create project with these settings? (yes/no): ")
  if (tolower(confirm) != "yes") {
    cat("Setup cancelled.\n")
    return(invisible(list(success = FALSE, message = "Setup cancelled by user")))
  }

  cat("\n")

  # Create configuration
  config <- list(
    study_name = study_name,
    protocol_id = protocol_id,
    pi_name = pi_name,
    pi_email = pi_email,
    target_enrollment = as.numeric(target_enrollment),
    study_phase = study_phase,
    admin_username = admin_username,
    admin_fullname = admin_fullname,
    admin_email = admin_email,
    admin_password = admin_password,
    security_salt = security_salt,
    session_timeout = session_timeout,
    enforce_https = enforce_https,
    team_members = data.frame()
  )

  # Execute setup
  result <- execute_init_setup(config = config, project_dir = project_dir)

  return(invisible(result))
}


#' Config File Mode: Non-Interactive Setup
#'
#' @param config_file Path to YAML configuration file
#' @param project_dir Directory where project will be created
#' @return List with setup results
#' @keywords internal
init_from_config <- function(config_file, project_dir = ".") {

  if (!file.exists(config_file)) {
    stop(sprintf("Config file not found: %s", config_file))
  }

  cat(sprintf("Reading configuration from: %s\n", config_file))

  # Parse YAML config
  tryCatch({
    config_yaml <- yaml::read_yaml(config_file)
  }, error = function(e) {
    stop(sprintf("Error reading YAML config: %s", e$message))
  })

  # Validate required fields
  required_fields <- c(
    "study_name", "protocol_id", "pi_name", "pi_email",
    "target_enrollment", "study_phase", "admin_username",
    "admin_fullname", "admin_email", "admin_password"
  )

  config <- config_yaml$study
  admin <- config_yaml$admin
  security <- config_yaml$security %||% list()

  # Validate study config
  if (is.null(config) || is.null(config$name)) {
    stop("Config must have 'study' section with 'name' field")
  }

  if (is.null(admin) || is.null(admin$username) || is.null(admin$password)) {
    stop("Config must have 'admin' section with 'username' and 'password'")
  }

  # Build config list
  config_list <- list(
    study_name = config$name %||% "Unnamed Study",
    protocol_id = config$protocol_id %||% "PROTOCOL-001",
    pi_name = config$pi_name %||% "PI Name",
    pi_email = config$pi_email %||% "pi@example.com",
    target_enrollment = as.numeric(config$target_enrollment %||% 50),
    study_phase = config$phase %||% "Pilot",
    admin_username = admin$username,
    admin_fullname = admin$fullname %||% admin$username,
    admin_email = admin$email %||% "admin@example.com",
    admin_password = admin$password,
    security_salt = generate_security_salt(),
    session_timeout = as.numeric(security$session_timeout_minutes %||% 30),
    enforce_https = as.logical(security$enforce_https %||% TRUE),
    team_members = data.frame()
  )

  # Execute setup
  result <- execute_init_setup(config = config_list, project_dir = project_dir)

  return(invisible(result))
}


#' Execute Initialization Setup
#'
#' Common code for both interactive and config modes
#'
#' @param config Configuration list
#' @param project_dir Directory where project will be created
#' @return List with setup results
#' @keywords internal
execute_init_setup <- function(config, project_dir = ".") {

  tryCatch({
    # Create project directory structure
    cat("Creating project structure...\n")
    project_path <- file.path(project_dir, tolower(gsub("[^a-zA-Z0-9_]", "_", config$study_name)))

    result <- create_wizard_directories(project_path)
    if (!result$success) {
      stop(result$message)
    }

    # Create database
    cat("Creating database...\n")
    db_path <- file.path(project_path, "data", "zzedc.db")
    db_result <- create_wizard_database(config, db_path)
    if (!db_result$success) {
      stop(db_result$message)
    }

    # Create config file
    cat("Creating configuration file...\n")
    config_path <- file.path(project_path, "config.yml")
    config_result <- create_wizard_config(config, config_path, config$security_salt)
    if (!config_result$success) {
      stop(config_result$message)
    }

    # Create launch script
    cat("Creating launch script...\n")
    launch_path <- file.path(project_path, "launch_app.R")
    launch_result <- create_launch_script(config, launch_path)
    if (!launch_result$success) {
      stop(launch_result$message)
    }

    # Save environment file with salt
    env_path <- file.path(project_path, ".env")
    env_content <- sprintf("# ZZedc Environment Configuration\nZZEDC_SALT=%s\nZZEDC_PROJECT_PATH=%s\n",
                           config$security_salt, project_path)
    writeLines(env_content, env_path)

    # Success message
    cat("\n")
    cat("╔═══════════════════════════════════════════════════════════╗\n")
    cat("║          ✓ ZZedc Project Created Successfully!            ║\n")
    cat("╚═══════════════════════════════════════════════════════════╝\n\n")

    cat(sprintf("Project Location: %s\n\n", project_path))
    cat("Next Steps:\n")
    cat("───────────────────────────────────────────────────────────\n\n")

    cat("1. Set environment variable:\n")
    cat(sprintf("   export ZZEDC_SALT='%s'\n\n", config$security_salt))

    cat("2. Launch your ZZedc application:\n")
    if (.Platform$OS.type == "windows") {
      cat(sprintf("   Rscript \"%s\"\n", launch_path))
    } else {
      cat(sprintf("   Rscript %s\n", launch_path))
    }
    cat("   OR\n")
    cat(sprintf("   R CMD BATCH %s\n\n", launch_path))

    cat("3. Open your browser to:\n")
    cat("   http://localhost:3838\n\n")

    cat("4. Login with:\n")
    cat(sprintf("   Username: %s\n", config$admin_username))
    cat("   Password: [the password you created]\n\n")

    cat("Security Reminder:\n")
    cat("───────────────────────────────────────────────────────────\n")
    cat(sprintf("Keep this security salt safe: %s\n", config$security_salt))
    cat("It's stored in .env file but should be backed up securely.\n\n")

    return(list(
      success = TRUE,
      message = "ZZedc project created successfully",
      project_path = project_path,
      study_name = config$study_name,
      protocol_id = config$protocol_id,
      database_path = db_path,
      config_path = config_path,
      launch_script = launch_path
    ))

  }, error = function(e) {
    cat("\n")
    cat("✗ Error during setup:\n")
    cat(sprintf("  %s\n\n", e$message))
    cat("Please check the error message above and try again.\n")

    return(list(
      success = FALSE,
      message = paste("Setup failed:", e$message)
    ))
  })
}


#' Generate Security Salt
#'
#' Creates a random 32-character salt for password hashing
#'
#' @return Character string of random salt
#' @keywords internal
generate_security_salt <- function() {
  paste0(sample(c(letters, LETTERS, 0:9), 32, replace = TRUE), collapse = "")
}


#' Null Coalesce Operator
#'
#' @param x First value
#' @param y Default value if x is NULL
#' @return x if not NULL, otherwise y
#' @keywords internal
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
