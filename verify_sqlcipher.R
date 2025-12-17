#!/usr/bin/env Rscript

cat("SQLCipher Installation Verification\n")
cat("=====================================\n\n")

# 1. Check SQLCipher binary
cat("1. Checking SQLCipher binary...\n")
sqlcipher_version <- system("sqlcipher --version", intern = TRUE)
if (length(sqlcipher_version) > 0) {
  cat("   OK: ", sqlcipher_version, "\n\n")
} else {
  cat("   FAILED: SQLCipher binary not found\n")
  cat("   Action: Install SQLCipher using: brew install sqlcipher\n\n")
}

# 2. Check R packages
cat("2. Checking R packages...\n")

packages_required <- c("RSQLite", "openssl", "digest")
packages_ok <- TRUE
for (pkg in packages_required) {
  if (require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat("   OK: ", pkg, "\n")
  } else {
    cat("   FAILED: ", pkg, " not installed\n")
    packages_ok <- FALSE
  }
}
cat("\n")

# 3. Test database connection
cat("3. Testing encrypted database connection...\n")

test_connection_ok <- FALSE
tryCatch({
  # Create temporary test database
  test_db <- tempfile(fileext = ".db")
  test_key <- "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  # Connect with encryption
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = test_key)

  # Write test data
  test_df <- data.frame(id = 1:3, value = c("test1", "test2", "test3"))
  DBI::dbWriteTable(conn, "test_table", test_df, overwrite = TRUE)

  # Read back
  result <- DBI::dbReadTable(conn, "test_table")

  # Verify
  if (identical(nrow(result), 3L)) {
    cat("   OK: Encrypted database write/read successful\n\n")
    test_connection_ok <- TRUE
  } else {
    cat("   FAILED: Data mismatch\n\n")
  }

  DBI::dbDisconnect(conn)
  unlink(test_db)

}, error = function(e) {
  cat("   FAILED: ", e$message, "\n\n")
})

# 4. Check file encryption
cat("4. Checking file encryption (verifying not plaintext)...\n")

test_encryption_ok <- FALSE
tryCatch({
  test_db <- tempfile(fileext = ".db")
  test_key <- "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  # Create encrypted database with recognizable text
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = test_key)
  DBI::dbWriteTable(conn, "users", data.frame(name = "TESTVALUE123"))
  DBI::dbDisconnect(conn)

  # Check file content
  file_content <- readBin(test_db, "raw")
  file_text <- rawToChar(file_content)

  if (grepl("TESTVALUE123", file_text, fixed = TRUE)) {
    cat("   WARNING: Database file contains plaintext (encryption may not be active)\n\n")
  } else {
    cat("   OK: Database file encrypted (no plaintext found)\n\n")
    test_encryption_ok <- TRUE
  }

  unlink(test_db)

}, error = function(e) {
  cat("   ERROR: ", e$message, "\n\n")
})

# 5. Final summary
cat("Verification Complete\n")
cat("=====================\n\n")

all_passed <- length(sqlcipher_version) > 0 && packages_ok && test_connection_ok && test_encryption_ok

if (all_passed) {
  cat("SUCCESS: All checks passed!\n")
  cat("SQLCipher is properly installed and ready for Feature #1 implementation.\n")
} else {
  cat("FAILURE: Some checks did not pass.\n")
  cat("Review the errors above and:\n")
  cat("1. For SQLCipher: brew install sqlcipher\n")
  cat("2. For R packages: In R, run install.packages('RSQLite')\n")
  cat("3. For connection issues: Check RSQLite version >= 2.2.18\n")
  cat("4. For encryption issues: Reinstall RSQLite from source\n")
}
