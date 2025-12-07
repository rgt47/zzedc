# Unified ZZedc Application Launcher
# Supports both traditional and Google Sheets enhanced modes
#
# This script launches the ZZedc EDC application with automatic detection
# of Google Sheets integration and graceful fallback to traditional mode.

cat("🚀 Starting ZZedc EDC Application...\n")
cat("=====================================\n")

# Function to check for Google Sheets integration
check_gsheets_integration <- function() {
  required_files <- c(
    "gsheets_integration.R",
    "gsheets_form_loader.R",
    "gsheets_ui_integration.R",
    "gsheets_server_integration.R"
  )

  missing_files <- required_files[!sapply(required_files, file.exists)]

  if (length(missing_files) > 0) {
    return(list(
      available = FALSE,
      missing_files = missing_files
    ))
  }

  # Check for generated forms
  gsheets_forms <- dir.exists("forms_generated") &&
                   length(list.files("forms_generated", pattern = "\\.R$")) > 0

  return(list(
    available = TRUE,
    forms_generated = gsheets_forms
  ))
}

# Check integration status
gsheets_status <- check_gsheets_integration()

# Helper function to display application information
display_app_info <- function(gsheets_status) {
  # Core features
  cat("\n📋 ZZedc Application Features:\n")
  cat("==============================\n")
  features <- c(
    "🏠 Home: Modern dashboard with system overview",
    "📝 EDC: Secure data entry forms with validation",
    "📊 Reports: Professional three-tier reporting system",
    "🔍 Data Explorer: Advanced data management tools",
    "📤 Export Center: Flexible export with templates"
  )
  cat(paste(features, collapse = "\n"), "\n")

  # Integration status
  if (gsheets_status$available) {
    cat("✅ Google Sheets Integration: Available\n")
    if (gsheets_status$forms_generated) {
      cat("📝 Google Sheets Forms: Active\n")
    } else {
      cat("ℹ️  Google Sheets Forms: Not configured (using traditional forms)\n")
    }
  } else {
    cat("❌ Google Sheets Integration: Not available\n")
    cat("   Missing files: ", paste(gsheets_status$missing_files, collapse = ", "), "\n")
  }

  # Security info
  cat("\n🔐 Authentication:\n")
  cat("===================\n")
  auth_features <- c(
    "• Secure database-based authentication",
    "• Role-based access control",
    "• Default test credentials available (see documentation)",
    "⚠️  Change default credentials before production!"
  )
  cat(paste(auth_features, collapse = "\n"), "\n")

  # UI info
  cat("\n🎨 UI Features:\n")
  cat("================\n")
  ui_features <- c(
    "• Modern Bootstrap 5 with bslib",
    "• Responsive design for all devices",
    "• Professional icons and layouts",
    "• Graceful fallback for missing packages"
  )
  cat(paste(ui_features, collapse = "\n"), "\n")
}

# Display application information
display_app_info(gsheets_status)

# Launch the appropriate version
cat("\n🚀 Launching ZZedc EDC Portal...\n")
cat("=================================\n")

# Launch unified application (handles both modes automatically)
cat("Mode: Unified (Auto-detection)\n")

# Use the unified launcher if available
if (file.exists("R/launch_zzedc.R")) {
  cat("✅ Using professional package launcher\n")
  source("R/launch_zzedc.R")
  launch_zzedc(host = "0.0.0.0", port = 3838, launch.browser = TRUE)
} else {
  cat("ℹ️  Using direct launch\n")

  # Load unified UI and server (they handle mode detection internally)
  ui <- source("ui.R")$value
  server <- source("server.R")$value

  cat("✅ Unified UI/Server loaded\n")
  cat("🌐 Starting application server...\n")

  # Launch the application
  shiny::runApp(
    list(ui = ui, server = server),
    port = 3838,
    launch.browser = TRUE,
    host = "0.0.0.0"
  )
}