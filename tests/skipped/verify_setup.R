# verify_setup.R - Verify database setup and ZZedc installation

library(RSQLite)
library(DBI)

# Check database connection and structure
cat("🔍 Verifying ZZedc Database Setup\n")
cat("=================================\n")

# Connect to database
tryCatch({
  con <- dbConnect(SQLite(), "data/memory001_study.db")
  cat("✅ Database connection successful\n")
  
  # List all tables
  tables <- dbListTables(con)
  cat("📊 Tables found:", length(tables), "\n")
  cat("   •", paste(tables, collapse = "\n   • "), "\n")
  
  # Check subjects data
  subjects <- dbGetQuery(con, "SELECT COUNT(*) as count FROM subjects")
  cat("\n👥 Subjects enrolled:", subjects$count, "\n")
  
  if (subjects$count > 0) {
    subject_details <- dbGetQuery(con, "
      SELECT subject_id, randomization_group, status, enrollment_date 
      FROM subjects 
      ORDER BY subject_id")
    
    cat("📋 Subject details:\n")
    for (i in 1:nrow(subject_details)) {
      cat("   •", subject_details$subject_id[i], 
          "| Group:", subject_details$randomization_group[i],
          "| Status:", subject_details$status[i], 
          "| Enrolled:", subject_details$enrollment_date[i], "\n")
    }
  }
  
  # Check users
  users <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_users")
  cat("\n🔐 EDC users configured:", users$count, "\n")
  
  user_details <- dbGetQuery(con, "
    SELECT username, full_name, role, active 
    FROM edc_users 
    WHERE active = 1")
  
  cat("👤 Active users:\n")
  for (i in 1:nrow(user_details)) {
    cat("   •", user_details$username[i], 
        "(", user_details$full_name[i], ")",
        "| Role:", user_details$role[i], "\n")
  }
  
  # Check validation rules
  validation_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM validation_rules WHERE active = 1")
  cat("\n🛡️  Active validation rules:", validation_count$count, "\n")
  
  dbDisconnect(con)
  
}, error = function(e) {
  cat("❌ Database error:", e$message, "\n")
})

# Check ZZedc application files
cat("\n📁 ZZedc Application Files\n")
cat("===========================\n")

required_files <- c(
  "ui.R", "server.R", "global.R", "run_app.R",
  "home.R", "edc.R", "auth.R", "savedata.R",
  "report1.R", "report2.R", "report3.R", "data.R", "export.R",
  "R/launch_zzedc.R", "R/zzedc-package.R"
)

missing_files <- c()
for (file in required_files) {
  if (file.exists(file)) {
    cat("✅", file, "\n")
  } else {
    cat("❌", file, "- MISSING\n")
    missing_files <- c(missing_files, file)
  }
}

# Check directories
required_dirs <- c("forms", "www", "credentials", "data", "scripts", "R", "tests")
missing_dirs <- c()

cat("\n📂 Required Directories\n")
cat("=======================\n")

for (dir in required_dirs) {
  if (dir.exists(dir)) {
    file_count <- length(list.files(dir, recursive = TRUE))
    cat("✅", dir, "(", file_count, "files )\n")
  } else {
    cat("❌", dir, "- MISSING\n")
    missing_dirs <- c(missing_dirs, dir)
  }
}

# Check R packages
cat("\n📦 R Package Dependencies\n")
cat("=========================\n")

required_packages <- c(
  "shiny", "bslib", "bsicons", "DT", "ggplot2", "plotly", 
  "dplyr", "RSQLite", "jsonlite", "digest", "shinyjs"
)

missing_packages <- c()
for (pkg in required_packages) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat("✅", pkg, "\n")
  } else {
    cat("❌", pkg, "- NOT INSTALLED\n")
    missing_packages <- c(missing_packages, pkg)
  }
}

# Summary
cat("\n🎯 Setup Verification Summary\n")
cat("=============================\n")

if (length(missing_files) == 0 && length(missing_dirs) == 0 && length(missing_packages) == 0) {
  cat("🎉 All components verified successfully!\n")
  cat("🚀 ZZedc is ready to launch!\n")
  cat("\n💡 Quick start commands:\n")
  cat("   library(zzedc)           # Load package functions\n")
  cat("   launch_zzedc()           # Launch with function\n")
  cat("   source('run_app.R')      # Launch with run script\n")
  cat("   shiny::runApp()          # Standard shiny launch\n")
} else {
  cat("⚠️  Issues found:\n")
  if (length(missing_files) > 0) {
    cat("   Missing files:", paste(missing_files, collapse = ", "), "\n")
  }
  if (length(missing_dirs) > 0) {
    cat("   Missing directories:", paste(missing_dirs, collapse = ", "), "\n")
  }
  if (length(missing_packages) > 0) {
    cat("   Missing packages:", paste(missing_packages, collapse = ", "), "\n")
    cat("   Install with: install.packages(c('", paste(missing_packages, collapse = "', '"), "'))\n")
  }
}

cat("\n📚 Documentation:\n")
cat("   • User Guide: ZZEDC_USER_GUIDE.md\n")
cat("   • README: README.md\n")
cat("   • Package docs: R/zzedc-package.R\n")

cat("\n🔐 Default login credentials (CHANGE IN PRODUCTION):\n")
cat("   • admin/admin123 (Administrator)\n")
cat("   • sjohnson/password123 (PI)\n")
cat("   • asmith/coord123 (Coordinator)\n")
cat("   • mbrown/data123 (Data Manager)\n")

cat("\n✨ ZZedc verification complete!\n")