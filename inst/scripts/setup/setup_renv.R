# renv Setup Script
# This script initializes renv for reproducible package management

cat("Setting up renv for reproducible package management...\n")

# Install renv if not already available
if (!requireNamespace("renv", quietly = TRUE)) {
  cat("Installing renv package...\n")
  install.packages("renv")
}

# Initialize renv with explicit snapshot type
# explicit: Only packages explicitly referenced in DESCRIPTION or library() calls
cat("Initializing renv...\n")
renv::init(settings = list(snapshot.type = "explicit"))

# Essential packages for R package development
essential_packages <- c(
  "devtools",      # Package development tools
  "usethis",       # Project setup utilities  
  "roxygen2",      # Documentation generation
  "testthat",      # Unit testing framework
  "knitr",         # Dynamic report generation
  "rmarkdown",     # R Markdown documents
  "pkgdown",       # Package websites
  "here",          # Relative file paths
  "conflicted"     # Handle package conflicts
)

cat("Installing essential development packages...\n")
install.packages(essential_packages)

# Take snapshot to lock package versions
cat("Creating renv.lock snapshot...\n")
renv::snapshot()

cat("renv setup complete!\n")
cat("- Project library:", renv::paths$library(), "\n")
cat("- Lockfile created:", file.exists("renv.lock"), "\n")
cat("- Use renv::status() to check package synchronization\n")
cat("- Use renv::snapshot() to update lockfile after adding packages\n")
