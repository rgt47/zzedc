#!/usr/bin/env Rscript
#
# Add test users to toy trial database
#

library(DBI)
library(RSQLite)
library(digest)

# Paths
script_dir <- dirname(rstudioapi::getActiveDocumentContext()$path)
base_dir <- dirname(dirname(script_dir))
db_path <- file.path(base_dir, "data", "toy_trial.db")

conn <- dbConnect(SQLite(), db_path)

# Create users table
dbExecute(conn, "
  CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name TEXT,
    email TEXT,
    role TEXT,
    active BOOLEAN DEFAULT 1,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
")

# Define salt for password hashing
salt <- "toy_trial_salt_2025"

# Add users
users <- data.frame(
  username = c("admin", "jane_smith", "bob_johnson", "researcher"),
  password = c("admin123", "jane123", "bob123", "research123"),
  full_name = c("Admin User", "Jane Smith", "Bob Johnson", "Lead Researcher"),
  email = c("admin@trial.org", "jane@trial.org", "bob@trial.org", "lead@trial.org"),
  role = c("Admin", "Coordinator", "Coordinator", "Researcher"),
  stringsAsFactors = FALSE
)

for (i in 1:nrow(users)) {
  user_id <- paste0("USER-", i)
  pwd_hash <- digest(paste0(users[i, "password"], salt), algo = "sha256")

  dbExecute(conn, "
    INSERT OR REPLACE INTO users
    (user_id, username, password_hash, full_name, email, role, active)
    VALUES (?, ?, ?, ?, ?, ?, 1)
  ", list(
    user_id,
    users[i, "username"],
    pwd_hash,
    users[i, "full_name"],
    users[i, "email"],
    users[i, "role"]
  ))

  cat("Added user:", users[i, "username"], "password:", users[i, "password"], "\n")
}

dbDisconnect(conn)

cat("\nUsers created successfully!\n")
cat("Test Credentials:\n")
cat("  admin / admin123\n")
cat("  jane_smith / jane123\n")
cat("  bob_johnson / bob123\n")
cat("  researcher / research123\n")
