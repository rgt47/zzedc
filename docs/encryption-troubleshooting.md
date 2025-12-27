# Encryption Troubleshooting Guide

This document addresses common issues encountered when using ZZedc database
encryption features and provides diagnostic procedures and solutions.

## Diagnostic Commands

### Verify Environment Configuration

```r
cat("DB_ENCRYPTION_KEY set:", Sys.getenv("DB_ENCRYPTION_KEY") != "", "\n")
cat("ZZEDC_DB_PATH:", Sys.getenv("ZZEDC_DB_PATH"), "\n")
cat("USE_AWS_KMS:", Sys.getenv("USE_AWS_KMS"), "\n")
cat("AWS_REGION:", Sys.getenv("AWS_REGION"), "\n")
```

### Verify Key Format

```r
key <- Sys.getenv("DB_ENCRYPTION_KEY")
cat("Key length:", nchar(key), "(expected: 64)\n")
cat("Key format valid:", grepl("^[0-9a-f]{64}$", key), "\n")
```

### Check Database File

```r
db_path <- get_db_path()
cat("Database path:", db_path, "\n")
cat("File exists:", file.exists(db_path), "\n")
cat("File size:", file.size(db_path), "bytes\n")
cat("File readable:", file.access(db_path, 4) == 0, "\n")
cat("File writable:", file.access(db_path, 2) == 0, "\n")
```

## Common Issues and Solutions

### Issue: "Database encryption key not found"

**Symptoms**
```
Error: Database encryption key not found.

Set one of the following:
1. Environment variable:
   Sys.setenv(DB_ENCRYPTION_KEY = 'your-64-char-hex-key')
```

**Causes**

- Environment variable not set
- AWS KMS not configured
- Wrong variable name

**Solutions**

1. Set the environment variable:
```r
key <- generate_db_key()
Sys.setenv(DB_ENCRYPTION_KEY = key)
```

2. For persistent configuration, add to `.Renviron`:
```
DB_ENCRYPTION_KEY=your-64-character-hex-key-here
```

3. For AWS KMS, ensure credentials are configured:
```bash
aws sts get-caller-identity
```

### Issue: "Encryption key must be exactly 64 hexadecimal characters"

**Symptoms**
```
Error: Encryption key must be exactly 64 hexadecimal characters (256 bits), got 32
```

**Causes**

- Key truncated during copy/paste
- Wrong key format
- Base64 encoded instead of hex

**Solutions**

1. Generate a new valid key:
```r
key <- generate_db_key()
verify_db_key(key)
```

2. Check for whitespace:
```r
key <- trimws(Sys.getenv("DB_ENCRYPTION_KEY"))
```

3. Verify character count:
```r
nchar(Sys.getenv("DB_ENCRYPTION_KEY"))
```

### Issue: "Database file not found"

**Symptoms**
```
Error: Failed to connect to encrypted database: Database file not found at: ./data/zzedc.db
Use initialize_encrypted_database() to create a new database
```

**Causes**

- Database not created
- Wrong path specified
- Working directory changed

**Solutions**

1. Create new database:
```r
initialize_encrypted_database(db_path = "./data/zzedc.db")
```

2. Specify absolute path:
```r
Sys.setenv(ZZEDC_DB_PATH = "/full/path/to/database.db")
```

3. Check current working directory:
```r
getwd()
```

### Issue: "Failed to connect to encrypted database"

**Symptoms**
```
Error: Failed to connect to encrypted database: unable to open database file
```

**Causes**

- File permissions incorrect
- Directory does not exist
- Database file corrupted
- Wrong encryption key

**Solutions**

1. Check file permissions:
```bash
ls -la /path/to/database.db
chmod 600 /path/to/database.db
```

2. Create parent directory:
```r
dir.create(dirname(db_path), recursive = TRUE)
```

3. Verify key matches database:
```r
verification <- verify_database_encryption(db_path)
print(verification)
```

### Issue: "Migration failed"

**Symptoms**
```
Error: Migration failed: disk I/O error
```

**Causes**

- Insufficient disk space
- Source database locked
- Backup directory not writable

**Solutions**

1. Check disk space:
```bash
df -h /path/to/database
```

2. Ensure no other processes accessing database:
```bash
lsof /path/to/database.db
```

3. Verify backup directory permissions:
```r
dir.create(backup_dir, recursive = TRUE)
file.access(backup_dir, 2) == 0
```

### Issue: "Export verification failed"

**Symptoms**
```
Warning: File integrity check failed
Expected: abc123...
Actual:   def456...
```

**Causes**

- File modified after export
- Hash file corrupted
- File encoding changed

**Solutions**

1. Re-export the data:
```r
export_encrypted_data(query, format = "csv", include_hash = TRUE)
```

2. Verify hash file exists:
```r
hash_file <- paste0(export_path, ".sha256")
file.exists(hash_file)
```

3. Check for encoding issues:
```r
readLines(hash_file)
```

### Issue: "Audit logging failed"

**Symptoms**
```
Warning: Failed to log audit event: no such table: audit_log
```

**Causes**

- Audit tables not initialized
- Database connection issue
- Schema mismatch

**Solutions**

1. Initialize audit logging:
```r
init_audit_logging(db_path = "./data/zzedc.db")
```

2. Verify tables exist:
```r
conn <- connect_encrypted_db()
DBI::dbListTables(conn)
DBI::dbDisconnect(conn)
```

### Issue: SQLCipher Not Available

**Symptoms**

Database contains unencrypted data despite key being set.

**Diagnostic**
```r
has_sqlcipher_support <- function() {
  test_db <- tempfile(fileext = ".db")
  key <- generate_db_key()
  on.exit(unlink(test_db))

  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db, key = key)
  DBI::dbWriteTable(conn, "test", data.frame(x = 1))
  DBI::dbDisconnect(conn)

  header <- readBin(test_db, "raw", 16)
  !identical(header[1:6], charToRaw("SQLite"))
}

cat("SQLCipher available:", has_sqlcipher_support(), "\n")
```

**Solutions**

1. Install SQLCipher system libraries (see Deployment Guide)
2. Reinstall RSQLite from source:
```r
install.packages("RSQLite", type = "source")
```

### Issue: AWS Secrets Manager Connection Failed

**Symptoms**
```
Error: Failed to retrieve secret from AWS Secrets Manager.
Secret name: zzedc/db-encryption-key
Error: Unable to locate credentials
```

**Causes**

- AWS credentials not configured
- IAM permissions insufficient
- Wrong region specified

**Solutions**

1. Configure AWS credentials:
```bash
aws configure
```

2. Verify credentials work:
```bash
aws sts get-caller-identity
```

3. Check secret exists:
```bash
aws secretsmanager describe-secret --secret-id zzedc/db-encryption-key
```

4. Verify IAM permissions include `secretsmanager:GetSecretValue`

## Performance Issues

### Slow Database Queries

**Diagnostic**
```r
system.time({
  conn <- connect_encrypted_db()
  result <- DBI::dbGetQuery(conn, "SELECT COUNT(*) FROM subjects")
  DBI::dbDisconnect(conn)
})
```

**Solutions**

1. Add database indexes:
```r
conn <- connect_encrypted_db()
DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_subjects_status
                      ON subjects(status)")
DBI::dbDisconnect(conn)
```

2. Optimize queries with EXPLAIN:
```r
DBI::dbGetQuery(conn, "EXPLAIN QUERY PLAN SELECT * FROM subjects")
```

### Slow Export Operations

**Diagnostic**
```r
system.time({
  export_encrypted_data("SELECT * FROM large_table", format = "csv")
})
```

**Solutions**

1. Export in batches:
```r
for (offset in seq(0, total_rows, by = 10000)) {
  query <- sprintf("SELECT * FROM table LIMIT 10000 OFFSET %d", offset)
  export_encrypted_data(query, format = "csv")
}
```

2. Use JSON format for large datasets (more efficient):
```r
export_encrypted_data(query, format = "json")
```

## Recovery Procedures

### Recovering from Corrupted Database

1. Stop application
2. Locate most recent backup
3. Verify backup integrity:
```bash
sha256sum -c backup.db.sha256
```
4. Restore from backup:
```r
rollback_migration(backup_path, restore_to = db_path)
```
5. Restart application
6. Verify data integrity

### Recovering from Lost Encryption Key

If the encryption key is lost and no backup key exists, encrypted data
cannot be recovered. Prevention measures:

1. Store keys in AWS Secrets Manager with versioning
2. Maintain offline key backup in secure location
3. Document key recovery procedures
4. Test recovery procedures periodically

## Log Analysis

### Shiny Server Logs

```bash
tail -f /var/log/shiny-server/*.log | grep -i encrypt
```

### R Session Logs

Enable verbose logging:
```r
options(zzedc.verbose = TRUE)
```

### Audit Trail Analysis

```r
audit <- get_audit_trail(
  filters = list(event_type = "ACCESS"),
  include_chain = TRUE
)

audit[audit$hash_verified == FALSE, ]
```

## Getting Help

### Information to Collect

When reporting issues, include:

1. R version: `R.version.string`
2. RSQLite version: `packageVersion("RSQLite")`
3. Operating system: `Sys.info()["sysname"]`
4. Error message (complete)
5. Steps to reproduce
6. Relevant log excerpts

### Diagnostic Report

Generate a diagnostic report:
```r
diagnostic_report <- function() {
  list(
    r_version = R.version.string,
    rsqlite_version = as.character(packageVersion("RSQLite")),
    os = Sys.info()["sysname"],
    key_set = Sys.getenv("DB_ENCRYPTION_KEY") != "",
    db_path = tryCatch(get_db_path(), error = function(e) e$message),
    aws_kms = Sys.getenv("USE_AWS_KMS"),
    sqlcipher = tryCatch(has_sqlcipher_support(), error = function(e) FALSE)
  )
}

print(diagnostic_report())
```
