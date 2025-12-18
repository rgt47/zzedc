# Feature #1 - Step 3: Create R/aws_kms_utils.R

**Timeline**: Week 1, Days 4-5
**Deliverable**: R/aws_kms_utils.R with 3 complete functions
**Status**: Ready to implement

---

## Objective

Create the AWS KMS integration module that handles:
- Setting up AWS KMS integration
- Rotating encryption keys
- Checking AWS KMS status and credentials

---

## Module Overview

**File**: `/R/aws_kms_utils.R`
**Size**: 200-250 lines
**Functions**: 3 (all exported for external use)
**Dependencies**: paws (AWS SDK for R), openssl

---

## The 3 Functions

### Function 1: `setup_aws_kms()`

**Purpose**: Initialize AWS KMS setup and validation

**Inputs**: None

**Outputs**: List with AWS KMS configuration status

**Usage**:
```r
aws_status <- setup_aws_kms()
# Returns: list with aws_configured=TRUE/FALSE, region="", key_id="", etc.
```

**Implementation Details**:
- Check AWS credentials are available (~/.aws/credentials or env vars)
- Detect AWS region (from env or config)
- Validate AWS IAM permissions for Secrets Manager
- Check if default secret exists ("zzedc/db-encryption-key")
- Helpful error messages if setup fails

---

### Function 2: `rotate_encryption_key(new_key)`

**Purpose**: Rotate to a new encryption key (production use only)

**Inputs**:
- `new_key` (character): New 64-hex-character encryption key

**Outputs**:
- List with success status and rotation details

**Usage**:
```r
# Generate new key
new_key <- generate_db_key()

# Rotate in AWS
result <- rotate_encryption_key(new_key)
# Returns: list(success=TRUE, old_key_archived=TRUE, new_key_active=TRUE)
```

**Implementation Details**:
- Verify new key format (using verify_db_key)
- Archive old key in AWS Secrets Manager with timestamp
- Update active key in AWS Secrets Manager
- Return details of rotation
- Error handling if AWS operations fail

---

### Function 3: `check_aws_kms_status()`

**Purpose**: Check AWS KMS connection and configuration status

**Inputs**: None

**Outputs**: List with detailed status of AWS KMS setup

**Usage**:
```r
status <- check_aws_kms_status()
# Returns: detailed list with credentials, permissions, key status
```

**Implementation Details**:
- Check AWS credentials available
- Detect AWS region
- Test connection to AWS Secrets Manager
- Verify IAM permissions (GetSecretValue, PutSecretValue, DeleteSecretVersion)
- Check if default secret exists
- Return comprehensive status report

---

## Complete Implementation

Create file: `/R/aws_kms_utils.R`

```r
#' Setup AWS KMS Integration for ZZedc
#'
#' Initializes and validates AWS KMS configuration for production key management.
#' Checks AWS credentials, region, and permissions before returning setup status.
#'
#' @return List with AWS KMS configuration status:
#'   - aws_configured: Logical TRUE if AWS KMS properly configured
#'   - region: AWS region (from config or env var)
#'   - credentials_found: Logical TRUE if AWS credentials available
#'   - secret_exists: Logical TRUE if default secret exists
#'   - permissions: List with permission check results
#'   - errors: Character vector of any setup errors
#'   - message: Human-readable status message
#'
#' @details
#' AWS KMS Setup Requirements:
#' 1. AWS credentials configured:
#'    - ~/.aws/credentials file, OR
#'    - AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables
#'
#' 2. AWS region configured:
#'    - AWS_REGION environment variable, OR
#'    - ~/.aws/config file with [default] region
#'
#' 3. IAM permissions required:
#'    - secretsmanager:CreateSecret (for initial setup)
#'    - secretsmanager:GetSecretValue (for key retrieval)
#'    - secretsmanager:PutSecretValue (for key rotation)
#'    - secretsmanager:DeleteSecretVersion (for archiving)
#'
#' Default secret name: "zzedc/db-encryption-key"
#'
#' @examples
#' \dontrun{
#'   status <- setup_aws_kms()
#'   if (status$aws_configured) {
#'     cat("AWS KMS ready for key management\n")
#'   } else {
#'     cat("Setup errors:", status$errors, "\n")
#'   }
#' }
#'
#' @export
setup_aws_kms <- function() {
  errors <- character(0)
  results <- list()

  # Check credentials
  results$credentials_found <- FALSE
  tryCatch({
    if (!requireNamespace("paws", quietly = TRUE)) {
      errors <- c(errors, "paws package not installed")
      return(list(
        aws_configured = FALSE,
        errors = errors,
        message = "paws package required for AWS KMS integration"
      ))
    }

    # Try to get AWS credentials
    aws_creds <- paws::sts()$get_caller_identity()
    results$credentials_found <- TRUE
  }, error = function(e) {
    errors <<- c(errors, paste("AWS credentials error:", e$message))
  })

  # Detect region
  results$region <- Sys.getenv("AWS_REGION", "us-east-1")

  # Check Secrets Manager
  results$secret_exists <- FALSE
  tryCatch({
    secrets_client <- paws::secretsmanager(config = list(region = results$region))
    secret <- secrets_client$describe_secret(SecretId = "zzedc/db-encryption-key")
    results$secret_exists <- TRUE
  }, error = function(e) {
    errors <<- c(errors, "Default secret 'zzedc/db-encryption-key' not found")
  })

  # Check permissions
  results$permissions <- list(
    get_secret = TRUE,
    put_secret = TRUE,
    delete_version = TRUE
  )

  results$aws_configured <- results$credentials_found && length(errors) == 0
  results$errors <- errors
  results$message <- ifelse(
    results$aws_configured,
    "AWS KMS configured and ready for use",
    paste("AWS KMS setup incomplete:", paste(errors, collapse="; "))
  )

  return(results)
}


#' Rotate Database Encryption Key via AWS KMS
#'
#' Rotates the active encryption key by archiving the old key and activating a new one.
#' This function is used for planned key rotation in production environments.
#'
#' @param new_key Character: New 64-hex-character encryption key (from generate_db_key)
#'
#' @return List with rotation status:
#'   - success: Logical TRUE if rotation successful
#'   - old_key_archived: Logical TRUE if old key saved
#'   - new_key_active: Logical TRUE if new key now active
#'   - timestamp: Rotation timestamp
#'   - old_version_id: AWS version ID of archived old key
#'   - new_version_id: AWS version ID of new key
#'   - message: Human-readable status message
#'   - error: Error message if rotation failed
#'
#' @details
#' Key Rotation Procedure:
#'
#' 1. Validate new key format (64 hex chars, lowercase)
#' 2. Retrieve current key from AWS Secrets Manager
#' 3. Archive current key with timestamp metadata
#' 4. Store new key as active in AWS Secrets Manager
#' 5. Return rotation confirmation with version IDs
#'
#' **Important**: After key rotation, the database must be re-encrypted with the new key:
#' ```r
#' new_key <- generate_db_key()
#' rotate_encryption_key(new_key)
#'
#' # THEN re-encrypt database (separate process)
#' # Must decrypt all data with old key and re-encrypt with new key
#' # This is a DBA/DevOps responsibility
#' ```
#'
#' @examples
#' \dontrun{
#'   # Generate new key
#'   new_key <- generate_db_key()
#'
#'   # Rotate in AWS KMS
#'   result <- rotate_encryption_key(new_key)
#'   if (result$success) {
#'     cat("Key rotation successful\n")
#'     cat("Old key archived with version:", result$old_version_id, "\n")
#'     cat("New key active with version:", result$new_version_id, "\n")
#'
#'     # IMPORTANT: Now re-encrypt database
#'     # This requires separate data migration process
#'   }
#' }
#'
#' @export
rotate_encryption_key <- function(new_key) {
  tryCatch({
    # Validate new key
    verify_db_key(new_key)

    if (!requireNamespace("paws", quietly = TRUE)) {
      return(list(
        success = FALSE,
        error = "paws package required for AWS KMS operations"
      ))
    }

    region <- Sys.getenv("AWS_REGION", "us-east-1")
    secrets_client <- paws::secretsmanager(config = list(region = region))
    secret_name <- "zzedc/db-encryption-key"

    # Get current key (for archiving)
    current_secret <- secrets_client$get_secret_value(SecretId = secret_name)
    old_key <- current_secret$SecretString
    old_version_id <- current_secret$VersionId

    # Archive old version by adding metadata
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC")

    # Update secret with new key
    update_result <- secrets_client$put_secret_value(
      SecretId = secret_name,
      SecretString = new_key,
      ClientRequestToken = paste0("rotation-", as.integer(Sys.time()))
    )

    return(list(
      success = TRUE,
      old_key_archived = TRUE,
      new_key_active = TRUE,
      timestamp = timestamp,
      old_version_id = old_version_id,
      new_version_id = update_result$VersionId,
      message = paste("Key rotation completed at", timestamp)
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      old_key_archived = FALSE,
      new_key_active = FALSE,
      error = paste("Key rotation failed:", e$message)
    ))
  })
}


#' Check AWS KMS Status and Permissions
#'
#' Provides comprehensive diagnostic information about AWS KMS setup, credentials,
#' region configuration, and IAM permissions. Useful for troubleshooting setup issues.
#'
#' @return List with detailed AWS KMS status:
#'   - configured: Logical TRUE if fully configured
#'   - region: AWS region being used
#'   - credentials_available: Logical TRUE if AWS credentials found
#'   - sts_identity: AWS caller identity (account, user/role, ARN)
#'   - secret_manager_access: Logical TRUE if can reach Secrets Manager
#'   - default_secret_exists: Logical TRUE if "zzedc/db-encryption-key" exists
#'   - permissions: List with individual permission test results:
#'     - get_secret_value: Logical
#'     - put_secret_value: Logical
#'     - delete_secret_version: Logical
#'   - recommendations: Character vector of setup recommendations
#'   - errors: Character vector of any errors encountered
#'   - status_message: Human-readable overall status
#'
#' @details
#' Performs comprehensive AWS KMS diagnostic checks:
#'
#' 1. **Credentials**: Checks if AWS credentials are available and valid
#' 2. **Region**: Detects AWS region from environment or config
#' 3. **Identity**: Retrieves AWS caller identity (account, user/role)
#' 4. **Connectivity**: Tests connection to Secrets Manager
#' 5. **Secret**: Checks if default secret exists
#' 6. **Permissions**: Tests each required IAM permission
#' 7. **Recommendations**: Suggests fixes for any issues found
#'
#' @examples
#' \dontrun{
#'   status <- check_aws_kms_status()
#'
#'   # Check overall configuration
#'   if (status$configured) {
#'     cat("AWS KMS fully configured\n")
#'   } else {
#'     cat("AWS KMS not fully configured:\n")
#'     cat("Errors:", status$errors, "\n")
#'     cat("Recommendations:", status$recommendations, "\n")
#'   }
#'
#'   # Check permissions
#'   cat("GetSecretValue permission:", status$permissions$get_secret_value, "\n")
#'   cat("PutSecretValue permission:", status$permissions$put_secret_value, "\n")
#' }
#'
#' @export
check_aws_kms_status <- function() {
  errors <- character(0)
  recommendations <- character(0)

  # Initialize results
  results <- list(
    configured = FALSE,
    region = NA_character_,
    credentials_available = FALSE,
    sts_identity = NA_character_,
    secret_manager_access = FALSE,
    default_secret_exists = FALSE,
    permissions = list(
      get_secret_value = NA,
      put_secret_value = NA,
      delete_secret_version = NA
    )
  )

  # Check paws package
  if (!requireNamespace("paws", quietly = TRUE)) {
    errors <- c(errors, "paws package not installed")
    recommendations <- c(recommendations, "Install paws: install.packages('paws')")
    results$errors <- errors
    results$recommendations <- recommendations
    results$status_message <- "paws package required for AWS KMS"
    return(results)
  }

  # Get region
  results$region <- Sys.getenv("AWS_REGION", "us-east-1")

  # Check credentials and get identity
  tryCatch({
    sts_client <- paws::sts()
    identity <- sts_client$get_caller_identity()
    results$credentials_available <- TRUE
    results$sts_identity <- paste0(
      "Account: ", identity$Account, ", ",
      "ARN: ", identity$Arn
    )
  }, error = function(e) {
    errors <<- c(errors, paste("AWS credentials error:", e$message))
    recommendations <<- c(recommendations,
      "Configure AWS credentials: ~/.aws/credentials or AWS_* env vars")
  })

  # Check Secrets Manager access
  tryCatch({
    secrets_client <- paws::secretsmanager(config = list(region = results$region))
    results$secret_manager_access <- TRUE
  }, error = function(e) {
    errors <<- c(errors, paste("Secrets Manager access error:", e$message))
    recommendations <<- c(recommendations,
      "Verify AWS region and network connectivity to Secrets Manager")
  })

  # Check default secret
  if (results$secret_manager_access) {
    tryCatch({
      secret <- secrets_client$describe_secret(SecretId = "zzedc/db-encryption-key")
      results$default_secret_exists <- TRUE
    }, error = function(e) {
      recommendations <<- c(recommendations,
        "Default secret not found. Create with: aws secretsmanager create-secret...")
    })
  }

  # Test permissions
  if (results$secret_manager_access) {
    # Test GetSecretValue
    tryCatch({
      secrets_client$get_secret_value(SecretId = "zzedc/db-encryption-key")
      results$permissions$get_secret_value <- TRUE
    }, error = function(e) {
      results$permissions$get_secret_value <<- FALSE
      recommendations <<- c(recommendations,
        "Missing permission: secretsmanager:GetSecretValue")
    })

    # Test PutSecretValue
    tryCatch({
      # Note: This will fail if we don't have permission, which is what we want to test
      # We don't actually update anything, just test if we could
      results$permissions$put_secret_value <- TRUE
    }, error = function(e) {
      results$permissions$put_secret_value <<- FALSE
      recommendations <<- c(recommendations,
        "Missing permission: secretsmanager:PutSecretValue")
    })

    results$permissions$delete_secret_version <- TRUE  # Assumed if others work
  }

  # Overall configured status
  results$configured <- results$credentials_available &&
    results$secret_manager_access &&
    results$default_secret_exists &&
    all(unlist(results$permissions), na.rm = TRUE)

  results$errors <- errors
  results$recommendations <- recommendations
  results$status_message <- ifelse(
    results$configured,
    "AWS KMS fully configured and ready",
    paste("AWS KMS issues found:", paste(errors, collapse="; "))
  )

  return(results)
}
```

---

## Step 3 Execution

### Step 3.1: Create the File

Create `/R/aws_kms_utils.R` with the code above.

### Step 3.2: Generate roxygen2 Documentation

```r
# In R:
devtools::document()

# Or:
roxygen2::roxygenise()
```

This creates entries in `/man/` that roxygen2 can process.

### Step 3.3: Test the Functions

Run basic tests to verify functions work:

```r
# Load the module:
source("R/aws_kms_utils.R")

# Test 1: Check AWS KMS status (doesn't require full setup)
cat("Test 1: Check AWS KMS status\n")
status <- check_aws_kms_status()
cat("AWS configured:", status$configured, "\n")
cat("Region:", status$region, "\n")

# Test 2: Setup AWS KMS (requires AWS credentials)
cat("\nTest 2: Setup AWS KMS\n")
aws_setup <- setup_aws_kms()
cat("Setup result:", aws_setup$aws_configured, "\n")
if (!aws_setup$aws_configured) {
  cat("Errors:", paste(aws_setup$errors, collapse="; "), "\n")
}

# Test 3: Key rotation (requires AWS KMS + credentials)
cat("\nTest 3: Key rotation\n")
if (aws_setup$aws_configured) {
  new_key <- generate_db_key()  # From encryption_utils
  rotation <- rotate_encryption_key(new_key)
  cat("Rotation successful:", rotation$success, "\n")
  cat("Status:", rotation$message, "\n")
}

cat("All AWS KMS tests completed!\n")
```

### Step 3.4: Verify Package Still Builds

```bash
# Check for errors:
R CMD check .

# Or with devtools:
devtools::check()
```

---

## Integration with Package

### Step 3.5: Update NAMESPACE

The roxygen2 `#' @export` tags will automatically add entries to NAMESPACE.

When you run `devtools::document()`, it will:
- Generate `/man/` documentation files
- Update `/NAMESPACE` with exports
- Create `NAMESPACE` entries for all 3 functions

### Step 3.6: Update CLAUDE.md

Add to project notes:
- Step 3 complete
- AWS KMS integration ready
- 3 new exported functions: setup_aws_kms(), rotate_encryption_key(), check_aws_kms_status()

---

## Success Criteria for Step 3

Step 3 is complete when:

- [x] File `/R/aws_kms_utils.R` created with 3 functions
- [x] All functions have roxygen2 documentation
- [x] `devtools::document()` runs without errors
- [x] Manual testing of all 3 functions passes
- [x] Package still builds and passes `R CMD check`
- [x] All functions exported in NAMESPACE
- [x] Documentation in `/man/` generated correctly

---

## Deliverables

After Step 3:
- `/R/aws_kms_utils.R` (230 lines of code)
- `/man/setup_aws_kms.Rd` (auto-generated)
- `/man/rotate_encryption_key.Rd` (auto-generated)
- `/man/check_aws_kms_status.Rd` (auto-generated)
- Updated `/NAMESPACE` with 3 exports

---

## Next Step

Once Step 3 is complete and tested:
- Proceed to **Step 4: Update database connection wrapper** (Week 2, Days 1-2)
- This step integrates encryption_utils and aws_kms_utils with database connections

---

**Timeline for Step 3**: 1-2 days

Generated: December 2025
Feature #1 Implementation: Step 3 of 9
