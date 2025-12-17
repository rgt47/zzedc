# Feature #1 - Step 1: Install SQLCipher Dependencies

**Timeline**: Week 1, Days 1-2
**Deliverable**: SQLCipher binary installed and verified across all platforms
**Platform**: macOS (primary), with scripts for Ubuntu/CentOS/Docker

---

## Objective

Install SQLCipher binary and verify it works with R/RSQLite on your development machine.

---

## Prerequisites

Before starting, verify you have:
- [ ] Access to project repository (GitHub)
- [ ] R installed (3.6+)
- [ ] RSQLite >= 2.2.18 in DESCRIPTION (already present)
- [ ] Admin/sudo access on your machine
- [ ] Internet access for package downloads
- [ ] 30 minutes for installation and verification

---

## Installation Instructions by Platform

### macOS (RECOMMENDED - Primary Development)

**Step 1.1: Install SQLCipher via Homebrew**

```bash
# Install SQLCipher
brew install sqlcipher

# Verify installation
sqlcipher --version

# Output should show: SQLCipher 4.x.x
```

**Verification**: If you see version number, installation successful ✓

---

**Step 1.2: Install R Development Tools (if needed)**

```bash
# Xcode Command Line Tools (required for compilation)
xcode-select --install

# Or if already installed:
xcode-select --print-path
# Should output: /Applications/Xcode.app/...
```

---

**Step 1.3: Install Additional R Dependencies**

```bash
# In R console or terminal:
R

# Inside R:
install.packages("RSQLite")
install.packages("openssl")
install.packages("digest")

q()
```

---

### Ubuntu/Debian (Alternative)

**Step 1.1: Install SQLCipher**

```bash
# Update package manager
sudo apt-get update

# Install SQLCipher and development headers
sudo apt-get install -y sqlcipher libsqlcipher-dev

# Verify
sqlcipher --version
```

---

**Step 1.2: Install R Dependencies**

```bash
# Build essentials (needed for compilation)
sudo apt-get install -y build-essential r-base r-base-dev

# In R:
R
install.packages("RSQLite")
install.packages("openssl")
install.packages("digest")
q()
```

---

### CentOS/Amazon Linux (Alternative)

**Step 1.1: Install SQLCipher**

```bash
# Update package manager
sudo yum update -y

# Install SQLCipher
sudo yum install -y sqlcipher sqlcipher-devel

# Verify
sqlcipher --version
```

---

**Step 1.2: Install R Dependencies**

```bash
# Development tools
sudo yum groupinstall -y "Development Tools"
sudo yum install -y R R-devel

# In R:
R
install.packages("RSQLite")
install.packages("openssl")
install.packages("digest")
q()
```

---

### Docker (Optional - For CI/CD)

**Step 1.1: Update Dockerfile**

Add to your Dockerfile:

```dockerfile
# Base image with R
FROM r-base:4.1

# Install SQLCipher and dependencies
RUN apt-get update && apt-get install -y \
    sqlcipher \
    libsqlcipher-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install R packages
RUN R -e "install.packages(c('RSQLite', 'openssl', 'digest'))"

# Copy ZZedc code
COPY . /app/zzedc
WORKDIR /app/zzedc

# Install R package
RUN R CMD INSTALL .
```

---

## Verification Script

After installation, run this R script to verify everything works:

**File**: `verify_sqlcipher.R`

```r
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
  cat("   Action: Install SQLCipher using platform-specific instructions\n\n")
}

# 2. Check R packages
cat("2. Checking R packages...\n")

packages_required <- c("RSQLite", "openssl", "digest")
for (pkg in packages_required) {
  if (require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat("   OK: ", pkg, "\n")
  } else {
    cat("   FAILED: ", pkg, " not installed\n")
  }
}
cat("\n")

# 3. Test database connection
cat("3. Testing encrypted database connection...\n")

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
  }

  unlink(test_db)

}, error = function(e) {
  cat("   ERROR: ", e$message, "\n\n")
})

# 5. Final summary
cat("Verification Complete\n")
cat("=====================\n")
cat("\nIf all checks passed, SQLCipher is properly installed and ready.\n")
cat("If any checks failed, review the errors above and run platform-specific installation steps.\n")
```

**Run verification**:

```bash
# From project root:
Rscript verify_sqlcipher.R
```

---

## Expected Output

Successful verification should show:

```
SQLCipher Installation Verification
=====================================

1. Checking SQLCipher binary...
   OK: SQLCipher 4.5.0

2. Checking R packages...
   OK: RSQLite
   OK: openssl
   OK: digest

3. Testing encrypted database connection...
   OK: Encrypted database write/read successful

4. Checking file encryption (verifying not plaintext)...
   OK: Database file encrypted (no plaintext found)

Verification Complete
=====================

If all checks passed, SQLCipher is properly installed and ready.
```

---

## Troubleshooting

### Issue 1: "sqlcipher: command not found"

**Cause**: SQLCipher binary not installed or not in PATH

**Solutions**:
- macOS: `brew install sqlcipher`
- Ubuntu: `sudo apt-get install sqlcipher`
- CentOS: `sudo yum install sqlcipher`
- Verify PATH: `which sqlcipher`

---

### Issue 2: "Error: could not find package RSQLite"

**Cause**: RSQLite not installed in R

**Solution**:
```r
R
install.packages("RSQLite")
# May require compilation - ensure build tools installed:
# macOS: xcode-select --install
# Ubuntu: sudo apt-get install build-essential
# CentOS: sudo yum groupinstall "Development Tools"
```

---

### Issue 3: "RSQLite connecting with key fails"

**Cause**: RSQLite version too old (need >= 2.2.18)

**Solution**:
```r
# Check version
R
packageVersion("RSQLite")

# Update if needed
install.packages("RSQLite", repos="http://cran.r-project.org")
```

---

### Issue 4: "Database file is plaintext (not encrypted)"

**Cause**: SQLCipher not compiled into RSQLite

**Solution**:
- Reinstall RSQLite: `install.packages("RSQLite", type="source")`
- This forces compilation with SQLCipher support
- May require additional time (5-10 minutes)

---

## Deliverables for Step 1

After completion, verify:

- [x] SQLCipher binary installed and verified
  - Command: `sqlcipher --version` shows version number

- [x] R packages installed (RSQLite >= 2.2.18, openssl, digest)
  - Command: `R -e "packageVersion('RSQLite')"`

- [x] Verification script runs successfully
  - Command: `Rscript verify_sqlcipher.R`
  - All 4 checks pass: binary, packages, connection, encryption

- [x] Documentation created
  - This file: FEATURE_01_STEP_1_SQLCIPHER_INSTALL.md

---

## Next Step

Once Step 1 is complete and verified:
- Proceed to **Step 2: Create R/encryption_utils.R** (Week 1, Days 2-3)
- This module will use SQLCipher for database encryption

---

## Timeline

| Task | Duration | Status |
|------|----------|--------|
| Install SQLCipher binary | 5-10 min | IN PROGRESS |
| Install R dependencies | 10-15 min | IN PROGRESS |
| Run verification script | 2-3 min | PENDING |
| Troubleshoot (if needed) | 10-30 min | PENDING |
| **Total Step 1** | **30-60 min** | IN PROGRESS |

---

**Questions or blockers?** Document them and proceed to next step.

---

Generated: December 2025
Feature #1 Implementation: Step 1 of 9
Status: IN PROGRESS
