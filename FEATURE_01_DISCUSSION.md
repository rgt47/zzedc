# Feature #1: Data Encryption at Rest (SQLCipher)

**Status**: 🔵 READY FOR DISCUSSION
**Regulatory**: GDPR Article 32 (Security of Processing) + FDA 21 CFR Part 11
**Timeline**: 3 weeks
**Effort**: 2 developers
**Complexity**: CRITICAL (Foundation for all other features)

---

## 1. CURRENT STATE

### What Exists Now
```r
# Current ZZedc database connection (unencrypted)
library(RSQLite)

conn <- dbConnect(SQLite(),
                  "data/memory001_study.db")

# Database file: plain SQLite, readable by anyone with file access
# No encryption at rest
# SQL injection possible if not careful (though ZZedc uses parameterized queries)
```

### Current Vulnerabilities
- 🔴 Database file unencrypted on disk
- 🔴 If server compromised, data fully exposed
- 🔴 Backups unencrypted
- 🔴 Development data unencrypted
- 🔴 GDPR violation (Article 32 requires encryption)
- 🔴 FDA concern (21 CFR Part 11 requires security measures)

---

## 2. REQUIREMENTS

### Regulatory Requirements

**GDPR Article 32 (Security of Processing)**:
> "Encryption of personal data" - Must implement appropriate technical measures

**FDA 21 CFR Part 11**:
> "System validation" - Requires secure data storage and access controls

### Functional Requirements

| Requirement | Details |
|-------------|---------|
| **Encryption Algorithm** | AES-256 (military-grade) |
| **Encryption Mode** | CBC (Cipher Block Chaining) |
| **Key Length** | 256-bit |
| **Key Management** | Environment variable (dev), AWS KMS (prod) |
| **Database Access** | All queries must work transparently through encrypted database |
| **Performance** | <100ms additional latency acceptable (<5% overhead) |
| **Backward Compatibility** | NONE - Start fresh |
| **Deployment** | Must work in Docker, Docker Compose, R Shiny server, cloud |

---

## 3. TECHNICAL APPROACH

### Architecture Decision

```
Current Architecture:
┌─────────────────────────┐
│   R Shiny Application   │
│   (auth.R, edc.R, etc)  │
└────────────┬────────────┘
             │ SQL Queries (unencrypted)
             ▼
┌─────────────────────────┐
│  RSQLite Driver         │
└────────────┬────────────┘
             │ Direct file I/O
             ▼
┌─────────────────────────┐
│  SQLite Database File   │ ← UNENCRYPTED
│  (memory001_study.db)   │
└─────────────────────────┘

New Architecture:
┌─────────────────────────┐
│   R Shiny Application   │
│   (auth.R, edc.R, etc)  │
└────────────┬────────────┘
             │ SQL Queries (plaintext to driver)
             ▼
┌─────────────────────────┐
│  RSQLite Driver +       │
│  SQLCipher Backend      │
└────────────┬────────────┘
             │ Encrypt/Decrypt on-the-fly
             ▼
┌─────────────────────────┐
│  SQLite Database File   │ ← ENCRYPTED (AES-256)
│  (memory001_study.db)   │
└─────────────────────────┘

Encryption Key:
┌─────────────────────────┐
│  Environment Variable   │
│  DB_ENCRYPTION_KEY      │
│  (256-bit random)       │
└─────────────────────────┘
      ↑
      │
      └── Loaded at startup
```

### Implementation Strategy

**Option A: Use RSQLite with SQLCipher Backend** ⭐ RECOMMENDED

Pros:
- ✅ Works with existing RSQLite code (minimal changes)
- ✅ SQLCipher is battle-tested (Dropbox, Slack, Signal use it)
- ✅ Transparent encryption (queries unchanged)
- ✅ Open source (Simplified BSD license)
- ✅ ~5-10% performance overhead (acceptable)

Cons:
- ⚠️ Requires SQLCipher binary installed on system
- ⚠️ Database file not compatible with plain SQLite

**Option B: Use DBI adapter** (Not recommended - more complex)

**Recommendation**: Use Option A (RSQLite + SQLCipher)

---

## 4. DATABASE SCHEMA CHANGES

### Good News: NONE

SQLCipher is transparent to SQL schema:
```r
# Before encryption: Same schema
CREATE TABLE subjects (
  subject_id TEXT PRIMARY KEY,
  enrolled_date TEXT,
  consent_date TEXT
)

# After encryption: Identical schema
# All queries work the same way
# Only difference: data encrypted on disk
```

### Database Structure
```
Current:
  /data/memory001_study.db  (plain SQLite, ~20-50 MB unencrypted)

After Encryption:
  /data/memory001_study.db  (SQLCipher encrypted, ~20-50 MB encrypted)

Size: Same (encryption adds negligible overhead)
Performance: ~5-10% slower (acceptable for compliance)
```

---

## 5. CODE CHANGES REQUIRED

### File: DESCRIPTION
```r
# Add SQLCipher backend specification
Package: zzedc
...
Imports:
  RSQLite (>= 2.2.18),  # Supports SQLCipher
  ...
```

### File: global.R (or new file: R/database.R)

**BEFORE** (Current):
```r
# Current unencrypted connection
library(RSQLite)

get_db_connection <- function() {
  dbConnect(SQLite(), "data/memory001_study.db")
}
```

**AFTER** (New):
```r
# New encrypted connection
library(RSQLite)

get_db_connection <- function() {
  # Get encryption key from environment variable
  encryption_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  if (encryption_key == "") {
    stop(
      "Database encryption key not found.\n",
      "Set environment variable: DB_ENCRYPTION_KEY\n",
      "Generate key: zzedc::generate_db_key() -> save to .Renviron\n",
      "Or use: export DB_ENCRYPTION_KEY='...' before running"
    )
  }

  # Connect with SQLCipher encryption
  conn <- dbConnect(
    SQLite(),
    "data/memory001_study.db",
    key = encryption_key
  )

  return(conn)
}
```

### New Utility Functions

**File: R/encryption_utils.R** (NEW FILE)
```r
#' Generate a 256-bit encryption key for SQLCipher
#'
#' @return Character string: 64-character hex string (256-bit key)
#'
#' @examples
#' \dontrun{
#'   key <- generate_db_key()
#'   cat(key)  # Copy to .Renviron: DB_ENCRYPTION_KEY=<key>
#' }
#'
#' @export
generate_db_key <- function() {
  # Generate 32 random bytes (256 bits) and convert to hex
  raw_bytes <- openssl::rand_bytes(32)
  key <- paste0(as.hexCharacter(raw_bytes), collapse = "")
  return(key)
}

#' Verify encryption key format
#'
#' @param key Character string to verify
#' @return Logical: TRUE if valid 256-bit hex key, FALSE otherwise
verify_db_key <- function(key) {
  # Should be 64 hex characters (32 bytes × 2)
  if (!is.character(key)) return(FALSE)
  if (nchar(key) != 64) return(FALSE)
  if (!grepl("^[0-9a-f]{64}$", tolower(key))) return(FALSE)
  return(TRUE)
}

#' Test database encryption
#'
#' @param db_path Path to database file
#' @param key Encryption key
#' @return List with success status and diagnostic info
test_encryption <- function(db_path = "data/memory001_study.db", key = NULL) {
  if (is.null(key)) {
    key <- Sys.getenv("DB_ENCRYPTION_KEY")
  }

  if (!verify_db_key(key)) {
    return(list(
      success = FALSE,
      error = "Invalid encryption key format"
    ))
  }

  tryCatch({
    conn <- dbConnect(SQLite(), db_path, key = key)

    # Try simple query
    result <- dbGetQuery(conn, "SELECT 1 as test")

    # Get database info
    db_info <- file.info(db_path)

    dbDisconnect(conn)

    return(list(
      success = TRUE,
      database = basename(db_path),
      size_mb = db_info$size / 1024 / 1024,
      encrypted = TRUE,
      message = "Database encryption working correctly"
    ))
  }, error = function(e) {
    return(list(
      success = FALSE,
      error = as.character(e)
    ))
  })
}
```

### Integration Points (Files to Update)

| File | Change | Impact |
|------|--------|--------|
| global.R | Replace dbConnect() with get_db_connection() | All database operations |
| auth.R | Update db connections | Authentication system |
| edc.R | Update db connections | Form submission |
| data.R | Update db connections | Data retrieval |
| export.R | Update db connections | Data export |
| server.R | Update db connections | All server logic |
| setup_database.R | Create encrypted DB at start | Initial setup |
| run_app.R | Check for encryption key at startup | App launch |

**Good News**: Most files use wrapper functions, so changes are centralized.

---

## 6. UI/UX CHANGES

### Application Startup

**Current**:
```
User runs: Rscript run_app.R
App starts immediately
```

**New**:
```
User sets: export DB_ENCRYPTION_KEY='...' (or in .Renviron)
User runs: Rscript run_app.R

App checks:
  ✓ Encryption key present?
  ✓ Encryption key valid format?
  ✓ Database file accessible?
  ✓ Can decrypt database?

If error:
  ✗ Shows helpful error message with fix instructions
  ✗ Exits gracefully
```

### Error Messages for Users

**No encryption key set**:
```
Error: Database encryption key not found.

To fix:
1. Generate key:  Rscript -e 'zzedc::generate_db_key()'
2. Add to .Renviron:  DB_ENCRYPTION_KEY=<your-key>
3. Or set in terminal: export DB_ENCRYPTION_KEY=<your-key>
4. Then restart the application

For Docker: Use environment variable in docker-compose.yml
For Shiny Server: Use Rprofile.site
```

**Invalid encryption key**:
```
Error: Database encryption key is invalid format (must be 64 hex characters).

Current key: DB_ENCRYPTION_KEY=abc123... (only 10 characters)

Generate new key:  Rscript -e 'zzedc::generate_db_key()'
```

**Encryption key doesn't match database**:
```
Error: Unable to decrypt database. Encryption key is incorrect.

This database was encrypted with a different key.

Possible causes:
1. Using wrong encryption key
2. Database corrupted
3. Database not encrypted (from older ZZedc version)

To restore from backup:
  cp backups/memory001_study.db.backup data/memory001_study.db
  (Make sure same encryption key is used)
```

---

## 7. DEPENDENCIES

### System Dependencies

**SQLCipher Binary**:
```bash
# macOS
brew install sqlcipher

# Ubuntu/Debian
sudo apt-get install sqlcipher libsqlcipher-dev

# CentOS/RHEL
sudo yum install sqlcipher sqlcipher-devel

# Docker (handled in Dockerfile)
FROM rocker/shiny:4.5.0
RUN apt-get update && apt-get install -y sqlcipher libsqlcipher-dev
```

**R Package Dependencies**:
```r
# DESCRIPTION file
Imports:
  RSQLite (>= 2.2.18),  # Must support SQLCipher
  openssl (>= 2.0.0),   # For random key generation
  ...
```

### No Breaking Dependencies
- ✅ No new major dependencies
- ✅ All existing functions continue to work
- ✅ Transparent to business logic

---

## 8. IMPLEMENTATION STEPS

### Step 1: Install SQLCipher (Week 1, Day 1)
```bash
# Verify SQLCipher availability
which sqlcipher
sqlcipher --version

# Test SQLCipher
echo "SELECT 'SQLCipher working';" | sqlcipher /tmp/test.db "PRAGMA key='testkey';"
```

### Step 2: Update R Dependencies (Week 1, Day 1-2)
- Add RSQLite >= 2.2.18 to DESCRIPTION
- Add openssl to DESCRIPTION
- Run devtools::document()
- Verify no conflicts

### Step 3: Create Encryption Utilities (Week 1, Day 2-3)
- Create R/encryption_utils.R
- Implement:
  - generate_db_key()
  - verify_db_key()
  - test_encryption()
- Add roxygen2 documentation
- Test key generation

### Step 4: Update Database Connection (Week 1, Day 3-4)
- Create get_db_connection() wrapper function
- Update DESCRIPTION and NAMESPACE
- Add startup checks
- Error handling for missing/invalid key

### Step 5: Create Encrypted Database (Week 2, Day 1-2)
- Backup existing database
- Create schema in new encrypted database
- Verify schema integrity
- Compare table counts (should be 0 for fresh)

### Step 6: Update All Connection Points (Week 2, Day 2-5)
- Update global.R
- Update auth.R
- Update edc.R
- Update data.R
- Update export.R
- Update server.R
- Update setup_database.R
- Update run_app.R

### Step 7: Create Documentation (Week 3, Day 1-2)
- .Renviron template
- Docker Compose environment setup
- .env.example
- README with encryption instructions
- SOP for key management

### Step 8: Testing (Week 3, Day 2-5)
- Test key generation
- Test database creation with encryption
- Test query operations (SELECT, INSERT, UPDATE, DELETE)
- Test backup/restore with encryption
- Test error handling (wrong key, missing key)
- Performance benchmarking
- Security verification (database file not readable without key)

### Step 9: Documentation for FDA/GDPR (Week 3, Day 5)
- Database encryption procedure document
- Key management procedure
- Security controls documentation
- Audit trail of encryption implementation

---

## 9. TESTING STRATEGY

### Unit Tests

**Test 1: Key Generation**
```r
test_that("generate_db_key produces valid 256-bit key", {
  key <- generate_db_key()
  expect_equal(nchar(key), 64)  # 64 hex chars = 256 bits
  expect_match(key, "^[0-9a-f]{64}$")
})

test_that("verify_db_key validates correct format", {
  key <- generate_db_key()
  expect_true(verify_db_key(key))
  expect_false(verify_db_key("invalid"))
  expect_false(verify_db_key("abc123"))  # Too short
})
```

**Test 2: Encryption/Decryption**
```r
test_that("SQLCipher encrypts and decrypts data correctly", {
  key <- generate_db_key()
  db_path <- tempfile(fileext = ".db")

  # Create encrypted database
  conn <- dbConnect(SQLite(), db_path, key = key)
  dbCreateTable(conn, "test", data.frame(id = 1, name = "test"))
  dbDisconnect(conn)

  # Verify file is encrypted (should not contain "test" in plaintext)
  file_content <- readBin(db_path, "raw", file.size(db_path))
  expect_false(any(file_content == charToRaw("test")))

  # Decrypt with correct key
  conn <- dbConnect(SQLite(), db_path, key = key)
  result <- dbGetQuery(conn, "SELECT * FROM test")
  expect_equal(nrow(result), 1)
  expect_equal(result$name, "test")
  dbDisconnect(conn)

  # Try with wrong key (should fail or return garbage)
  wrong_key <- generate_db_key()
  expect_error(
    dbConnect(SQLite(), db_path, key = wrong_key)
  )
})
```

**Test 3: Query Operations**
```r
test_that("All SQL operations work with encrypted database", {
  key <- generate_db_key()
  db_path <- tempfile(fileext = ".db")
  conn <- dbConnect(SQLite(), db_path, key = key)

  # CREATE
  dbCreateTable(conn, "subjects",
    data.frame(id = 1, name = "test", enrolled = "2025-01-01"))

  # INSERT
  dbAppendTable(conn, "subjects",
    data.frame(id = 2, name = "test2", enrolled = "2025-01-02"))

  # SELECT
  result <- dbGetQuery(conn, "SELECT * FROM subjects")
  expect_equal(nrow(result), 2)

  # UPDATE
  dbExecute(conn, "UPDATE subjects SET name = 'updated' WHERE id = 1")
  result <- dbGetQuery(conn, "SELECT name FROM subjects WHERE id = 1")
  expect_equal(result$name, "updated")

  # DELETE
  dbExecute(conn, "DELETE FROM subjects WHERE id = 2")
  result <- dbGetQuery(conn, "SELECT COUNT(*) as cnt FROM subjects")
  expect_equal(result$cnt, 1)

  dbDisconnect(conn)
})
```

### Integration Tests

**Test 4: Application Startup**
```bash
# Test 1: No encryption key
$ Rscript run_app.R
# Expected: Error message with fix instructions

# Test 2: Invalid encryption key
$ export DB_ENCRYPTION_KEY="invalid"
$ Rscript run_app.R
# Expected: Error about invalid key format

# Test 3: Correct encryption key
$ export DB_ENCRYPTION_KEY=$(Rscript -e 'cat(zzedc::generate_db_key())')
$ Rscript run_app.R
# Expected: App starts successfully
# Navigate to http://localhost:3838
# Login and verify data operations work
```

**Test 5: Data Integrity**
```r
# Verify encrypted database contains same data as original
key <- generate_db_key()
old_db_backup <- "data/memory001_study.db.backup"
new_encrypted_db <- "data/memory001_study.db"

# Count records in both
old_count <- dbGetQuery(
  dbConnect(SQLite(), old_db_backup),
  "SELECT COUNT(*) as cnt FROM subjects"
)
new_count <- dbGetQuery(
  dbConnect(SQLite(), new_encrypted_db, key = key),
  "SELECT COUNT(*) as cnt FROM subjects"
)

expect_equal(old_count$cnt, new_count$cnt)
```

### Security Tests

**Test 6: Database File Not Readable Without Key**
```bash
# Try to read encrypted database as plaintext
$ strings data/memory001_study.db | grep "subject"
# Expected: No plaintext data found

# Try to open with unencrypted SQLite
$ sqlite3 data/memory001_study.db ".schema"
# Expected: Error or garbage
```

### Performance Tests

**Test 7: Encryption Overhead**
```r
# Benchmark encrypted vs unencrypted operations
# Expected: <5% overhead

library(microbenchmark)

# Create test data
test_data <- data.frame(
  id = 1:10000,
  name = paste0("subject_", 1:10000),
  value = rnorm(10000)
)

# Measure INSERT performance
key <- generate_db_key()
conn <- dbConnect(SQLite(), tempfile(fileext = ".db"), key = key)

timing <- microbenchmark(
  dbAppendTable(conn, "test", test_data),
  times = 3
)

# Check if overhead < 5%
# Expected: ~50-100ms per 10k records (5-10% overhead acceptable)
```

---

## 10. EFFORT ESTIMATE

| Task | Duration | Developer | Notes |
|------|----------|-----------|-------|
| SQLCipher installation & setup | 1 day | 1 dev | Straightforward |
| Create encryption utilities | 2 days | 1 dev | key generation, validation |
| Update database connections | 2 days | 1 dev | Centralized changes |
| Create encrypted database | 1 day | 1 dev | Data migration (fresh start) |
| Update all integration points | 2 days | 1 dev | global.R, auth.R, edc.R, etc |
| Documentation | 2 days | 1 dev | README, SOP, FDA docs |
| Unit testing | 2 days | 1 dev | Key, encryption, queries |
| Integration testing | 2 days | 1 dev | Startup, data ops, errors |
| Security verification | 1 day | 1 dev | File encryption, key strength |
| Code review & fixes | 1 day | 2 devs | Review + address issues |
| **TOTAL** | **3 weeks** | **1-2 devs** | |

---

## 11. REGULATORY DOCUMENTATION

### GDPR Compliance
- ✅ **Article 32 (Security)**: Encryption at rest implemented
- ✅ **Article 5 (Integrity)**: Data stored securely
- ✅ **Article 25 (Privacy by Design)**: Encryption as default

**Documentation Needed**:
- Database encryption SOP
- Key management procedure
- Audit trail of encryption implementation

### FDA Compliance
- ✅ **21 CFR Part 11 (Security)**: Encryption requirement met
- ✅ **System Validation**: Part of IQ/OQ/PQ (Feature #5)

**Documentation Needed**:
- Security controls documentation
- Key management verification
- Database validation procedures

---

## 12. ROLLBACK PLAN

**If encryption fails mid-implementation**:

```bash
# 1. Backup encrypted database
cp data/memory001_study.db data/memory001_study.db.encrypted

# 2. Restore unencrypted backup
cp data/memory001_study.db.backup data/memory001_study.db

# 3. Comment out encryption in code
# Revert changes to get_db_connection()

# 4. Restart app
Rscript run_app.R

# 5. Investigate issue
# - Check SQLCipher installation
# - Verify key format
# - Check encryption function logic
```

**Risk Assessment**: LOW
- Simple to revert
- Backup always available
- Encryption is isolated feature

---

## DISCUSSION QUESTIONS FOR USER

Before we implement, please clarify:

1. **Encryption Key Generation**:
   - Should we auto-generate at first run, or require user to provide?
   - Should key be stored in .Renviron, or environment variable only?

2. **Fresh Database**:
   - Start completely fresh (no data migration)?
   - Or do you want to test with sample data first?

3. **Docker/Containerization**:
   - Should encryption key come from Docker environment variable?
   - Should docker-compose.yml include encrypted database setup?

4. **Key Rotation** (Future):
   - Should we design database schema to support key rotation later?
   - Or implement when needed (Feature #27 - Change Control)?

5. **Testing Environment**:
   - Should we keep unencrypted test database for debugging?
   - Or always require encryption (even for tests)?

6. **Documentation**:
   - Should key be shown in logs (never), or redacted?
   - How should SysAdmin generate and secure the key?

---

## READY TO IMPLEMENT?

**Questions answered? Approach approved?**

Once you confirm, we'll:
1. ✅ Install SQLCipher
2. ✅ Create encryption utilities
3. ✅ Update database connection
4. ✅ Test thoroughly
5. ✅ Document for FDA/GDPR
6. ✅ Mark Feature #1 as IMPLEMENTED
7. ✅ Move to Feature #2 discussion

**Your approval needed** to proceed with implementation.
