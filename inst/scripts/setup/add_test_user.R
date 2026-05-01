# add_test_user.R - Add a test user for easy testing

library(RSQLite)
library(DBI)
library(digest)

# Function to add a test user
add_test_user <- function() {
  
  # Connect to database
  con <- dbConnect(SQLite(), "data/memory001_study.db")
  
  # Check if test user already exists
  existing <- dbGetQuery(con, "SELECT username FROM edc_users WHERE username = 'test'")
  
  if (nrow(existing) > 0) {
    cat("⚠️  Test user already exists\n")
    dbDisconnect(con)
    return()
  }
  
  # Create password hash for "test" password
  salt <- "zzedc_salt_2024"
  password_hash <- digest(paste0("test", salt), algo = "sha256")
  
  # Insert test user
  dbExecute(con, "
    INSERT INTO edc_users (user_id, username, password_hash, full_name, email, role, site_id, active, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      "test_user",
      "test", 
      password_hash,
      "Test User",
      "test@example.com",
      "Coordinator",
      "001",
      1,
      "admin"
    ))
  
  dbDisconnect(con)
  
  cat("✅ Test user added successfully!\n")
  cat("   Username: test\n")
  cat("   Password: test\n")
  cat("   Role: Coordinator\n")
}

# Add the test user
add_test_user()

# Test the new credentials
source("test_auth_simple.R")

cat("\n🧪 Testing new test user credentials\n")
cat("====================================\n")

# Source the authentication function
authenticate_user <- function(username, password) {
  
  # Check if database exists
  if (!file.exists("data/memory001_study.db")) {
    return(list(success = FALSE, message = "Database not found. Please run setup_database.R"))
  }
  
  tryCatch({
    # Connect to database
    con <- dbConnect(SQLite(), "data/memory001_study.db")
    
    # Get user record
    user_query <- "SELECT * FROM edc_users WHERE username = ? AND active = 1"
    user_record <- dbGetQuery(con, user_query, params = list(username))
    
    dbDisconnect(con)
    
    if (nrow(user_record) == 0) {
      return(list(success = FALSE, message = "Invalid username or account inactive"))
    }
    
    # Verify password
    salt <- "zzedc_salt_2024"  # Same salt used in setup_database.R
    password_hash <- digest(paste0(password, salt), algo = "sha256")
    
    if (user_record$password_hash == password_hash) {
      return(list(
        success = TRUE, 
        user_id = user_record$user_id,
        username = user_record$username,
        full_name = user_record$full_name,
        role = user_record$role,
        site_id = user_record$site_id
      ))
    } else {
      return(list(success = FALSE, message = "Invalid password"))
    }
    
  }, error = function(e) {
    return(list(success = FALSE, message = paste("Database error:", e$message)))
  })
}

# Test the new test user
result_test <- authenticate_user("test", "test")
if (result_test$success) {
  cat("✅ Test user authentication successful\n")
  cat("   Username:", result_test$username, "\n")
  cat("   Full name:", result_test$full_name, "\n")
  cat("   Role:", result_test$role, "\n")
} else {
  cat("❌ Test user authentication failed:", result_test$message, "\n")
}

cat("\n🎯 Updated Credentials List\n")
cat("===========================\n")
cat("👤 test/test          - Test User (Coordinator)\n")
cat("👤 admin/admin123     - System Administrator\n") 
cat("👤 sjohnson/password123 - Dr. Sarah Johnson (PI)\n")
cat("👤 asmith/coord123    - Alice Smith (Coordinator)\n")
cat("👤 mbrown/data123     - Mike Brown (Data Manager)\n")

cat("\n🚀 Ready to test login in ZZedc application!\n")