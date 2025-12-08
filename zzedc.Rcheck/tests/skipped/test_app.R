# Test script to check if the shiny app loads without errors

# Working directory should already be set to app directory
# setwd() removed to avoid hardcoded paths

# Load required packages (only essential ones for testing)
required_packages <- c("shiny", "RSQLite", "jsonlite", "digest")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("Warning: Package", pkg, "not available. Test may fail.\n")
  } else {
    library(pkg, character.only = TRUE)
  }
}

# Test loading the main components
cat("Testing app components...\n")

# Test global.R
cat("Loading global.R...\n")
tryCatch({
  source("global.R")
  cat("✓ global.R loaded successfully\n")
}, error = function(e) {
  cat("✗ Error in global.R:", e$message, "\n")
})

# Test ui.R
cat("Loading ui.R...\n")
tryCatch({
  source("ui.R")
  cat("✓ ui.R loaded successfully\n")
}, error = function(e) {
  cat("✗ Error in ui.R:", e$message, "\n")
})

# Test server.R
cat("Loading server.R...\n")
tryCatch({
  source("server.R")
  cat("✓ server.R loaded successfully\n")
}, error = function(e) {
  cat("✗ Error in server.R:", e$message, "\n")
})

cat("\nApp component test completed!\n")
cat("To run the app, use: shiny::runApp()\n")