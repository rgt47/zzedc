# ZZedc Setup Menu System
# Provides unified interface for all setup options including Google Sheets

# Main setup menu function
show_setup_menu <- function() {
  cat("\n")
  cat("=====================================\n")
  cat("     ZZedc Setup & Configuration     \n")
  cat("=====================================\n")
  cat("\n")
  cat("Choose your setup method:\n")
  cat("\n")
  cat("1. Setup from Google Sheets (Recommended)\n")
  cat("   - Configure users and forms in Google Sheets\n")
  cat("   - No R programming required\n")
  cat("\n")
  cat("2. Traditional Setup (Original Method)\n")
  cat("   - Use existing setup_database.R\n")
  cat("   - Requires R knowledge for customization\n")
  cat("\n")
  cat("3. Import from Existing Database\n")
  cat("   - Migrate from another ZZedc instance\n")
  cat("\n")
  cat("4. Quick Test Setup\n")
  cat("   - Creates demo data for testing\n")
  cat("\n")
  cat("5. View Current Configuration\n")
  cat("   - Show current database and settings\n")
  cat("\n")
  cat("6. Exit\n")
  cat("\n")
  cat("=====================================\n")

  choice <- readline(prompt = "Enter your choice (1-6): ")

  switch(choice,
    "1" = setup_from_gsheets_interactive(),
    "2" = setup_traditional(),
    "3" = setup_import_database(),
    "4" = setup_quick_test(),
    "5" = view_current_config(),
    "6" = {
      cat("Goodbye!\n")
      return(invisible(NULL))
    },
    {
      cat("Invalid choice. Please try again.\n")
      show_setup_menu()
    }
  )
}

# Interactive Google Sheets setup
setup_from_gsheets_interactive <- function() {
  cat("\n=== Google Sheets Setup ===\n")
  cat("This will configure ZZedc using Google Sheets for:\n")
  cat("- User authentication and roles\n")
  cat("- Data dictionary and forms\n")
  cat("- Validation rules\n\n")

  # Get Google Sheets information
  auth_sheet <- readline(prompt = "Authentication Google Sheet name [zzedc_auth]: ")
  if (auth_sheet == "") auth_sheet <- "zzedc_auth"

  dd_sheet <- readline(prompt = "Data Dictionary Google Sheet name [zzedc_data_dictionary]: ")
  if (dd_sheet == "") dd_sheet <- "zzedc_data_dictionary"

  project_name <- readline(prompt = "Project name [zzedc_project]: ")
  if (project_name == "") project_name <- "zzedc_project"

  # Confirm setup
  cat("\nSetup Configuration:\n")
  cat("- Authentication Sheet:", auth_sheet, "\n")
  cat("- Data Dictionary Sheet:", dd_sheet, "\n")
  cat("- Project Name:", project_name, "\n")

  confirm <- readline(prompt = "\nProceed with setup? (y/n): ")

  if (tolower(confirm) %in% c("y", "yes")) {
    cat("\nStarting Google Sheets setup...\n")

    # Source the setup script and run
    tryCatch({
      source("setup_from_gsheets.R")
      success <- setup_zzedc_from_gsheets_complete(
        auth_sheet_name = auth_sheet,
        dd_sheet_name = dd_sheet,
        project_name = project_name
      )

      if (success) {
        cat("\n✅ Setup completed successfully!\n")
        cat("Launch script created: launch_", gsub("[^A-Za-z0-9]", "_", project_name), ".R\n")

        launch_now <- readline(prompt = "Launch ZZedc now? (y/n): ")
        if (tolower(launch_now) %in% c("y", "yes")) {
          launch_script <- paste0("launch_", gsub("[^A-Za-z0-9]", "_", project_name), ".R")
          if (file.exists(launch_script)) {
            source(launch_script)
          }
        }
      } else {
        cat("\n❌ Setup failed. Check error messages above.\n")
      }

    }, error = function(e) {
      cat("\n❌ Setup failed with error:", e$message, "\n")
      cat("Make sure you have:\n")
      cat("1. Created the required Google Sheets\n")
      cat("2. Authenticated with Google (gs4_auth())\n")
      cat("3. Proper internet connection\n")
    })
  } else {
    cat("Setup cancelled.\n")
  }

  readline(prompt = "Press Enter to continue...")
  show_setup_menu()
}

# Traditional setup
setup_traditional <- function() {
  cat("\n=== Traditional Setup ===\n")

  if (file.exists("setup_database.R")) {
    cat("Running traditional database setup...\n")
    source("setup_database.R")
    cat("✅ Traditional setup completed!\n")

    launch_now <- readline(prompt = "Launch ZZedc now? (y/n): ")
    if (tolower(launch_now) %in% c("y", "yes")) {
      if (file.exists("run_app.R")) {
        source("run_app.R")
      } else {
        cat("Launch script not found. Try: shiny::runApp()\n")
      }
    }
  } else {
    cat("❌ setup_database.R not found\n")
  }

  readline(prompt = "Press Enter to continue...")
  show_setup_menu()
}

# Import from existing database
setup_import_database <- function() {
  cat("\n=== Import Database ===\n")
  cat("This feature allows you to import from another ZZedc database.\n")

  db_path <- readline(prompt = "Path to existing database file: ")

  if (file.exists(db_path)) {
    new_path <- readline(prompt = "New database path [data/imported_study.db]: ")
    if (new_path == "") new_path <- "data/imported_study.db"

    # Ensure directory exists
    if (!dir.exists(dirname(new_path))) {
      dir.create(dirname(new_path), recursive = TRUE)
    }

    # Copy database
    file.copy(db_path, new_path, overwrite = TRUE)

    # Update config
    update_config_database(new_path)

    cat("✅ Database imported successfully!\n")
  } else {
    cat("❌ Database file not found:", db_path, "\n")
  }

  readline(prompt = "Press Enter to continue...")
  show_setup_menu()
}

# Quick test setup
setup_quick_test <- function() {
  cat("\n=== Quick Test Setup ===\n")
  cat("This will create a test database with sample data.\n")

  confirm <- readline(prompt = "Create test setup? (y/n): ")

  if (tolower(confirm) %in% c("y", "yes")) {
    # Use the existing test setup if available
    if (file.exists("add_test_user.R")) {
      source("add_test_user.R")
    }

    if (file.exists("setup_database.R")) {
      source("setup_database.R")
    }

    cat("✅ Test setup created!\n")
    cat("Test credentials: test/test\n")

    launch_now <- readline(prompt = "Launch test instance? (y/n): ")
    if (tolower(launch_now) %in% c("y", "yes")) {
      if (file.exists("run_app.R")) {
        source("run_app.R")
      } else {
        shiny::runApp()
      }
    }
  }

  readline(prompt = "Press Enter to continue...")
  show_setup_menu()
}

# View current configuration
view_current_config <- function() {
  cat("\n=== Current Configuration ===\n")

  # Show config file if it exists
  if (file.exists("config.yml")) {
    cat("Configuration file: config.yml\n")

    # Try to load config
    tryCatch({
      if (requireNamespace("config", quietly = TRUE)) {
        cfg <- config::get()
        cat("Database path:", cfg$database$path, "\n")
        cat("Database exists:", file.exists(cfg$database$path), "\n")

        if (file.exists(cfg$database$path)) {
          # Check database tables
          con <- RSQLite::dbConnect(RSQLite::SQLite(), cfg$database$path)
          tables <- RSQLite::dbListTables(con)
          RSQLite::dbDisconnect(con)

          cat("Database tables:", length(tables), "\n")
          if ("edc_users" %in% tables) {
            con <- RSQLite::dbConnect(RSQLite::SQLite(), cfg$database$path)
            user_count <- RSQLite::dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users WHERE active = 1")$count
            RSQLite::dbDisconnect(con)
            cat("Active users:", user_count, "\n")
          }
        }
      } else {
        cat("Config package not available\n")
      }
    }, error = function(e) {
      cat("Error reading configuration:", e$message, "\n")
    })
  } else {
    cat("No config.yml found\n")
  }

  # Show available databases
  if (dir.exists("data")) {
    db_files <- list.files("data", pattern = "\\.db$", full.names = TRUE)
    if (length(db_files) > 0) {
      cat("\nAvailable database files:\n")
      for (db in db_files) {
        cat("-", db, "(", file.size(db), "bytes )\n")
      }
    }
  }

  # Show launch scripts
  launch_scripts <- list.files(".", pattern = "^launch_.*\\.R$")
  if (length(launch_scripts) > 0) {
    cat("\nAvailable launch scripts:\n")
    for (script in launch_scripts) {
      cat("-", script, "\n")
    }
  }

  readline(prompt = "Press Enter to continue...")
  show_setup_menu()
}

# Helper function to update config database path
update_config_database <- function(new_db_path) {
  if (file.exists("config.yml")) {
    config_content <- readLines("config.yml")

    # Find and update database path line
    db_line_idx <- grep("^\\s*path:", config_content)
    if (length(db_line_idx) > 0) {
      config_content[db_line_idx[1]] <- paste0('    path: "', new_db_path, '"')
      writeLines(config_content, "config.yml")
      cat("Updated config.yml with new database path\n")
    }
  }
}

# Auto-run menu if sourced interactively
if (interactive()) {
  show_setup_menu()
}