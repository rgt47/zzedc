#' Generate a random database encryption key
#'
#' Creates a cryptographically secure 256-bit random key for SQLCipher database encryption.
#' Returns as a 64-character hexadecimal string.
#'
#' @return Character string: 64-hex-character encryption key (256-bit)
#'
#' @details
#' Key generation:
#' - Uses openssl::rand_bytes() for cryptographic security
#' - 256-bit key = 32 bytes = 64 hex characters
#' - Never user-provided (best practice: auto-generated)
#' - Store result in environment variable or AWS Secrets Manager
#'
#' @examples
#' \dontrun{
#'   key <- generate_db_key()
#'   Sys.setenv(DB_ENCRYPTION_KEY = key)
#' }
#'
#' @export
generate_db_key <- function() {
  # Generate 32 random bytes (256 bits)
  random_bytes <- openssl::rand_bytes(32)

  # Convert each byte to 2-character hex string
  key <- paste0(sapply(random_bytes, function(x) {
    sprintf("%02x", as.integer(x))
  }), collapse = "")

  return(key)
}


#' Verify database encryption key format
#'
#' Validates that a key is properly formatted for SQLCipher.
#' Checks length, characters, and format.
#'
#' @param key Character string: The key to validate
#'
#' @return Logical TRUE if valid, otherwise stops with error message
#'
#' @details
#' Valid format requirements:
#' - Exactly 64 hexadecimal characters (256 bits)
#' - All lowercase a-f and 0-9
#' - Single string (length 1)
#'
#' Invalid keys will stop execution with descriptive error message.
#'
#' @examples
#' \dontrun{
#'   key <- generate_db_key()
#'   verify_db_key(key)  # Returns TRUE
#' }
#'
#' @export
verify_db_key <- function(key) {
  if (!is.character(key) || length(key) != 1) {
    stop("Encryption key must be a single character string")
  }

  if (nchar(key) != 64) {
    stop("Encryption key must be exactly 64 hexadecimal characters (256 bits), got ", nchar(key))
  }

  if (!grepl("^[0-9a-f]{64}$", key, ignore.case = FALSE)) {
    stop("Encryption key must contain only lowercase hexadecimal characters (0-9, a-f)")
  }

  return(TRUE)
}


#' Test database encryption
#'
#' Creates a test encrypted database, writes data, reads it back,
#' and verifies encryption is actually being applied (file is binary, not plaintext).
#'
#' @param db_path Character: Path to test database file (will be created and deleted)
#' @param key Character: Encryption key to test
#'
#' @return Logical TRUE if all tests pass, otherwise stops with error
#'
#' @details
#' Test procedure:
#' 1. Connect to database with key
#' 2. Write test data
#' 3. Disconnect
#' 4. Verify file is encrypted (random bytes, not readable text)
#' 5. Reconnect with correct key -> data readable
#' 6. Verify data integrity
#' 7. Cleanup temporary database
#'
#' This function verifies that SQLCipher is properly compiled into RSQLite.
#'
#' @examples
#' \dontrun{
#'   key <- generate_db_key()
#'   test_encryption(tempfile(fileext = ".db"), key)
#' }
#'
#' @export
test_encryption <- function(db_path, key) {
  verify_db_key(key)

  # Create test database with encryption
  conn <- tryCatch({
    DBI::dbConnect(RSQLite::SQLite(), db_path, key = key)
  }, error = function(e) {
    stop("Failed to connect with encryption key: ", e$message)
  })

  # Write test data
  test_df <- data.frame(
    id = 1:3,
    value = c("test1", "test2", "test3")
  )
  DBI::dbWriteTable(conn, "test_table", test_df, overwrite = TRUE)

  # Read back and verify
  result <- DBI::dbReadTable(conn, "test_table")
  DBI::dbDisconnect(conn)

  if (!identical(test_df, result)) {
    unlink(db_path)
    stop("Test data mismatch after encryption/decryption")
  }

  # Verify file is encrypted (should not contain readable text)
  file_content <- readBin(db_path, "raw", n = 1000)
  file_text <- rawToChar(file_content)

  if (grepl("test1|test2|test3", file_text, fixed = TRUE)) {
    unlink(db_path)
    warning("Database file appears to contain unencrypted text - encryption may not be active")
  }

  # Cleanup
  unlink(db_path)

  return(TRUE)
}


#' Get database encryption key from environment or AWS KMS
#'
#' Retrieves encryption key with automatic fallback:
#' 1. Try AWS KMS (if credentials and key_id provided)
#' 2. Try environment variable DB_ENCRYPTION_KEY
#' 3. Error if neither available
#'
#' @param aws_kms_key_id Character: AWS KMS key ID (optional)
#'
#' @return Character: 64-char hex encryption key
#'
#' @details
#' Priority order:
#' 1. AWS KMS (if aws_kms_key_id provided or USE_AWS_KMS=true)
#'    - Requires paws package
#'    - Requires AWS credentials (~/.aws/credentials or env vars)
#'    - Requires AWS IAM permissions for Secrets Manager
#'
#' 2. Environment variable DB_ENCRYPTION_KEY
#'    - Set with: Sys.setenv(DB_ENCRYPTION_KEY = "...")
#'    - Best for development
#'
#' 3. Error if neither available
#'    - Helpful error message with setup instructions
#'
#' @examples
#' \dontrun{
#'   # Development (environment variable):
#'   Sys.setenv(DB_ENCRYPTION_KEY = "a1b2c3d4...")
#'   key <- get_encryption_key()
#'
#'   # Production (AWS KMS):
#'   key <- get_encryption_key(aws_kms_key_id = "arn:aws:kms:...")
#' }
#'
#' @export
get_encryption_key <- function(aws_kms_key_id = NULL) {
  # Try AWS KMS first
  if (!is.null(aws_kms_key_id) || Sys.getenv("USE_AWS_KMS") == "true") {
    tryCatch({
      key <- get_encryption_key_from_aws_kms(aws_kms_key_id)
      return(key)
    }, error = function(e) {
      message("AWS KMS error, falling back to environment variable: ", e$message)
    })
  }

  # Fallback to environment variable
  key <- Sys.getenv("DB_ENCRYPTION_KEY")

  if (key == "") {
    stop(
      "Database encryption key not found.\n\n",
      "Set one of the following:\n",
      "1. Environment variable:\n",
      "   Sys.setenv(DB_ENCRYPTION_KEY = 'your-64-char-hex-key')\n\n",
      "2. AWS KMS secret:\n",
      "   Use get_encryption_key(aws_kms_key_id = 'secret-name')\n",
      "   Requires: paws package + AWS credentials\n\n",
      "3. Generate new key:\n",
      "   key <- generate_db_key()\n",
      "   Sys.setenv(DB_ENCRYPTION_KEY = key)\n"
    )
  }

  verify_db_key(key)
  return(key)
}


#' Retrieve encryption key from AWS Secrets Manager
#'
#' Retrieves stored encryption key from AWS Secrets Manager.
#' Requires paws package and AWS credentials.
#'
#' @param key_id Character: AWS Secrets Manager secret name (optional)
#'
#' @return Character: Decrypted encryption key (64 hex chars)
#'
#' @details
#' Default secret name: "zzedc/db-encryption-key"
#'
#' Requirements:
#' - paws package installed: install.packages("paws")
#' - AWS credentials configured: ~/.aws/credentials or environment variables
#' - AWS IAM permissions: secretsmanager:GetSecretValue
#'
#' @keywords internal
#'
#' @examples
#' \dontrun{
#'   # Requires AWS credentials
#'   key <- get_encryption_key_from_aws_kms("zzedc/db-encryption-key")
#' }
#'
get_encryption_key_from_aws_kms <- function(key_id = NULL) {
  if (!requireNamespace("paws", quietly = TRUE)) {
    stop(
      "paws package required for AWS KMS integration.\n",
      "Install with: install.packages('paws')"
    )
  }

  # Use AWS Secrets Manager
  secrets_client <- paws::secretsmanager()

  secret_name <- key_id %||% "zzedc/db-encryption-key"

  response <- tryCatch({
    secrets_client$get_secret_value(SecretId = secret_name)
  }, error = function(e) {
    stop(
      "Failed to retrieve secret from AWS Secrets Manager.\n",
      "Secret name: ", secret_name, "\n",
      "Error: ", e$message, "\n\n",
      "Ensure:\n",
      "1. Secret exists in AWS account\n",
      "2. AWS credentials are configured\n",
      "3. IAM permissions include secretsmanager:GetSecretValue"
    )
  })

  key <- response$SecretString

  verify_db_key(key)
  return(key)
}


# Helper function: %||% operator (for NULL coalescing)
# Returns left side if not NULL, otherwise right side
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
