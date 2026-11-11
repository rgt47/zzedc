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


#' Open a SQLite connection and apply a key, without verification (internal)
#'
#' Supports both SQLite3MultipleCiphers (PRAGMA) and standard SQLCipher
#' (key param). On a stock CRAN RSQLite build neither mechanism exists,
#' and SQLite ignores the unknown PRAGMAs without error, so the
#' connection opens a plaintext file. Callers must therefore verify the
#' result with `sqlite_file_is_encrypted()`; `connect_encrypted()` does
#' this for them.
#'
#' @param db_path Character: Path to database file
#' @param key Character: Encryption key
#'
#' @return SQLiteConnection object
#'
#' @keywords internal
.connect_sqlite_with_key <- function(db_path, key) {
  tryCatch({
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path, synchronous = NULL)
    DBI::dbExecute(conn, "PRAGMA cipher = 'sqlcipher'")
    DBI::dbExecute(conn, sprintf("PRAGMA key = '%s'", key))
    conn
  }, error = function(e) {
    DBI::dbConnect(RSQLite::SQLite(), db_path, key = key)
  })
}


#' Determine Whether a SQLite File Is Encrypted
#'
#' Inspects the first 16 bytes of the file. Every plaintext SQLite
#' database begins with the magic string `"SQLite format 3\\0"`; a
#' SQLCipher or SQLite3MultipleCiphers file does not (with default
#' settings), because the header is encrypted along with the pages.
#'
#' @param db_path Character: Path to the database file.
#'
#' @return `TRUE` if the file exists, is non-empty, and lacks the
#'   plaintext SQLite header; `FALSE` if it carries the plaintext
#'   header; `NA` if the file does not exist or is empty (nothing has
#'   been written yet, so there is nothing to judge).
#'
#' @details
#' A file that lacks the header could also be corrupt or not a SQLite
#' file at all; this function reports only that its contents are not
#' readable as plaintext SQLite. A cipher configured to leave the header
#' unencrypted (SQLite3MultipleCiphers `plaintext_header_size`) would be
#' reported as unencrypted; zzedc never sets that option.
#'
#' @examples
#' f <- tempfile(fileext = ".db")
#' con <- DBI::dbConnect(RSQLite::SQLite(), f)
#' DBI::dbWriteTable(con, "t", data.frame(x = 1))
#' DBI::dbDisconnect(con)
#' sqlite_file_is_encrypted(f)
#' unlink(f)
#'
#' @export
sqlite_file_is_encrypted <- function(db_path) {
  if (is.null(db_path) || !file.exists(db_path) ||
      isTRUE(file.size(db_path) == 0)) {
    return(NA)
  }
  header <- readBin(db_path, "raw", n = 16)
  plaintext_magic <- c(charToRaw("SQLite format 3"), as.raw(0))
  !identical(header, plaintext_magic)
}


#' Check Whether the Installed RSQLite Can Encrypt
#'
#' Performs a functional test rather than checking for a package name:
#' it creates a temporary database with a key, writes a row, and
#' inspects the resulting file header. The result is cached for the
#' session.
#'
#' @param refresh Logical: re-run the probe instead of using the cached
#'   result.
#'
#' @return `TRUE` if a keyed SQLite file is actually written encrypted,
#'   `FALSE` otherwise (including on stock CRAN RSQLite).
#'
#' @examples
#' sqlite_cipher_available()
#'
#' @export
sqlite_cipher_available <- function(refresh = FALSE) {
  if (!refresh && !is.null(.zzedc_env$sqlite_cipher_available)) {
    return(.zzedc_env$sqlite_cipher_available)
  }
  probe <- tempfile(fileext = ".db")
  on.exit(unlink(probe), add = TRUE)
  available <- tryCatch({
    conn <- .connect_sqlite_with_key(probe, generate_db_key())
    on.exit(DBI::dbDisconnect(conn), add = TRUE, after = FALSE)
    DBI::dbWriteTable(conn, "zzedc_cipher_probe", data.frame(x = 1L))
    isTRUE(sqlite_file_is_encrypted(probe))
  }, error = function(e) FALSE)
  .zzedc_env$sqlite_cipher_available <- available
  available
}


#' Create encrypted database connection (internal)
#'
#' Opens a SQLite connection with the key applied, then checks whether
#' the file is in fact encrypted and applies the active security
#' profile (see `resolve_security_profile()`): under `regulated` a
#' plaintext file is an error, under `standard` a warning, under
#' `development` silent. A new or empty file cannot be judged until
#' something is written to it; callers that create databases
#' (`initialize_encrypted_database()`, `test_encryption()`) check again
#' after writing.
#'
#' @param db_path Character: Path to database file
#' @param key Character: Encryption key
#'
#' @return SQLiteConnection object
#'
#' @keywords internal
connect_encrypted <- function(db_path, key) {
  encrypted <- sqlite_file_is_encrypted(db_path)
  if (!is.na(encrypted)) {
    enforce_encryption_at_rest(
      encrypted, db_path,
      "The file has a plaintext SQLite header; the installed RSQLite does not apply the key."
    )
  }
  .connect_sqlite_with_key(db_path, key)
}


#' Test database encryption
#'
#' Creates a test encrypted database, writes data, reads it back,
#' and verifies encryption is actually being applied (file is binary, not plaintext).
#'
#' @param db_path Character: Path to test database file (will be created and deleted)
#' @param key Character: Encryption key to test
#'
#' @return Logical TRUE if all tests pass, otherwise stops with an
#'   error. Under every security profile, a file that is written in
#'   plaintext is an error: this function exists to answer whether
#'   encryption works, so a warning would defeat its purpose.
#'
#' @details
#' Test procedure:
#' 1. Connect to database with key
#' 2. Write test data
#' 3. Disconnect
#' 4. Verify the file lacks the plaintext SQLite header and does not
#'    contain the written values as plaintext bytes
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
#' @keywords internal
#' @export
test_encryption <- function(db_path, key) {
  verify_db_key(key)
  on.exit(unlink(db_path), add = TRUE)

  conn <- tryCatch({
    .connect_sqlite_with_key(db_path, key)
  }, error = function(e) {
    stop("Failed to connect with encryption key: ", e$message)
  })

  test_df <- data.frame(
    id = 1:3,
    value = c("zzedc_probe_1", "zzedc_probe_2", "zzedc_probe_3")
  )
  DBI::dbWriteTable(conn, "test_table", test_df, overwrite = TRUE)
  DBI::dbDisconnect(conn)

  if (!isTRUE(sqlite_file_is_encrypted(db_path))) {
    stop(
      "Encryption is not active: the test database was written with a ",
      "plaintext SQLite header. The installed RSQLite does not support ",
      "SQLCipher or SQLite3MultipleCiphers, so keys are ignored."
    )
  }

  file_bytes <- readBin(db_path, "raw", n = file.size(db_path))
  if (length(grepRaw(charToRaw("zzedc_probe_"), file_bytes, fixed = TRUE)) > 0) {
    stop("Encryption is not active: test values appear as plaintext in the file.")
  }

  conn <- .connect_sqlite_with_key(db_path, key)
  result <- DBI::dbReadTable(conn, "test_table")
  DBI::dbDisconnect(conn)

  if (!identical(test_df, result)) {
    stop("Test data mismatch after encryption/decryption")
  }

  TRUE
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
  # Caching strategy: the resolved key is invariant for the
  # session in production, but tests rotate the env var between
  # fixtures. AWS-path callers cache by key_id; env-var-path
  # callers cache only when the current env var matches the
  # cached value (so a test-side `Sys.setenv()` invalidates it
  # automatically).
  use_aws <- !is.null(aws_kms_key_id) ||
    Sys.getenv("USE_AWS_KMS") == "true"

  if (is.null(.zzedc_env$encryption_keys)) {
    .zzedc_env$encryption_keys <- list()
  }

  if (use_aws) {
    cache_key <- paste0(
      "aws::",
      if (is.null(aws_kms_key_id)) "_default_" else aws_kms_key_id
    )
    cached <- .zzedc_env$encryption_keys[[cache_key]]
    if (!is.null(cached)) return(cached)

    kms_key <- tryCatch(
      get_encryption_key_from_aws_kms(aws_kms_key_id),
      error = function(e) e
    )
    if (!inherits(kms_key, "error")) {
      .zzedc_env$encryption_keys[[cache_key]] <- kms_key
      return(kms_key)
    }

    # Falling back from KMS to an environment variable changes who
    # holds the key, so the profile decides whether that is allowed.
    profile <- get_security_profile()
    fallback_msg <- paste0(
      "AWS KMS error; falling back to the DB_ENCRYPTION_KEY ",
      "environment variable: ", conditionMessage(kms_key)
    )
    if (profile == "regulated") {
      stop(
        "AWS KMS key retrieval failed and the 'regulated' security ",
        "profile does not allow falling back to an environment ",
        "variable: ", conditionMessage(kms_key),
        call. = FALSE
      )
    } else if (profile == "standard") {
      warning(fallback_msg, call. = FALSE)
    } else {
      message(fallback_msg)
    }
  }

  current <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (current == "") {
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

  cached_env <- .zzedc_env$encryption_keys[["env::value"]]
  if (!is.null(cached_env) && identical(cached_env, current)) {
    return(cached_env)
  }

  verify_db_key(current)
  .zzedc_env$encryption_keys[["env::value"]] <- current
  current
}

#' Clear the cached encryption key
#'
#' The result of `get_encryption_key()` is cached in the package
#' environment for the session. Call this to drop the cache:
#' for example, after rotating the key with
#' `rotate_encryption_key()`, or in tests that need to validate
#' the key-resolution code path itself.
#'
#' @return `invisible(NULL)`.
#' @export
clear_encryption_key_cache <- function() {
  .zzedc_env$encryption_keys <- NULL
  invisible(NULL)
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


#' Convert a Hex String to Raw Bytes (internal)
#' @param hex Character scalar of even length.
#' @return Raw vector.
#' @keywords internal
.hex_to_raw <- function(hex) {
  starts <- seq(1, nchar(hex), by = 2)
  as.raw(strtoi(substring(hex, starts, starts + 1), 16L))
}


# Helper function: %||% operator (for NULL coalescing)
# Returns left side if not NULL, otherwise right side
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
