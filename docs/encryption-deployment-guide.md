# Encryption Deployment Guide

This document provides operational guidance for deploying ZZedc with
database encryption at rest in production environments.

## Prerequisites

### System Requirements

- R version 4.4 or higher
- RSQLite package version 2.2.18 or higher
- SQLCipher libraries (for full encryption support)
- Minimum 2GB available RAM
- SSD storage recommended for optimal performance

### SQLCipher Installation

SQLCipher provides transparent database encryption. Installation varies
by platform.

**macOS**
```bash
brew install sqlcipher
```

**Ubuntu/Debian**
```bash
sudo apt-get update
sudo apt-get install sqlcipher libsqlcipher-dev
```

**Amazon Linux/CentOS**
```bash
sudo yum install sqlcipher sqlcipher-devel
```

**Docker**
```dockerfile
RUN apt-get update && apt-get install -y sqlcipher libsqlcipher-dev
```

### Verifying SQLCipher Installation

```bash
sqlcipher --version
```

Expected output includes SQLCipher version information.

## Key Management Configuration

### Development Environment

For development and testing, use environment variables:

```bash
export DB_ENCRYPTION_KEY="your-64-character-hex-key-here"
```

Generate a new key:
```r
key <- zzedc::generate_db_key()
cat(key)
```

### Production Environment with AWS Secrets Manager

AWS Secrets Manager provides secure, centralized key management suitable
for production deployments.

#### Creating the Secret

Using AWS CLI:
```bash
aws secretsmanager create-secret \
    --name zzedc/db-encryption-key \
    --description "ZZedc database encryption key" \
    --secret-string "$(Rscript -e 'cat(zzedc::generate_db_key())')"
```

#### IAM Policy Requirements

The application requires the following IAM permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:zzedc/*"
        }
    ]
}
```

#### Configuring ZZedc for AWS KMS

Set environment variable to enable AWS KMS:
```bash
export USE_AWS_KMS=true
export AWS_REGION=us-east-1
```

Or specify the key ID directly:
```r
conn <- connect_encrypted_db(
  aws_kms_key_id = "zzedc/db-encryption-key"
)
```

## Database Initialization

### Creating a New Encrypted Database

```r
library(zzedc)

result <- initialize_encrypted_database(
  db_path = "/var/data/zzedc/study.db",
  overwrite = FALSE
)

if (!result$success) {
  stop("Database initialization failed: ", result$error)
}

cat("Database created at:", result$path, "\n")
```

### Migrating Existing Databases

For existing unencrypted databases:

```r
result <- migrate_to_encrypted(
  old_db_path = "/var/data/zzedc/legacy.db",
  backup_dir = "/var/backups/zzedc"
)

if (result$success) {
  cat("Migration complete:", result$records_migrated, "records\n")
  cat("New database:", result$new_path, "\n")
  cat("Backup at:", result$backup_path, "\n")
} else {
  stop("Migration failed: ", result$error)
}
```

### Initializing Audit Logging

```r
audit_result <- init_audit_logging(
  db_path = "/var/data/zzedc/study.db"
)

if (!audit_result$success) {
  warning("Audit logging initialization failed")
}
```

## Server Configuration

### Shiny Server Configuration

Add to `/etc/shiny-server/shiny-server.conf`:
```
run_as shiny;

server {
  listen 3838;

  location / {
    site_dir /srv/shiny-server;
    log_dir /var/log/shiny-server;
    directory_index on;
  }
}
```

### Environment Variables

Create `/etc/shiny-server/env.conf`:
```
DB_ENCRYPTION_KEY=your-64-character-hex-key
ZZEDC_DB_PATH=/var/data/zzedc/study.db
USE_AWS_KMS=true
AWS_REGION=us-east-1
```

### File Permissions

```bash
chown -R shiny:shiny /var/data/zzedc
chmod 700 /var/data/zzedc
chmod 600 /var/data/zzedc/*.db
```

## Backup Procedures

### Automated Backup Script

Create `/usr/local/bin/zzedc-backup.sh`:
```bash
#!/bin/bash
set -e

BACKUP_DIR="/var/backups/zzedc"
DB_PATH="/var/data/zzedc/study.db"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/study_$TIMESTAMP.db"

mkdir -p "$BACKUP_DIR"

cp "$DB_PATH" "$BACKUP_FILE"

sha256sum "$BACKUP_FILE" > "$BACKUP_FILE.sha256"

find "$BACKUP_DIR" -name "*.db" -mtime +30 -delete
find "$BACKUP_DIR" -name "*.sha256" -mtime +30 -delete

echo "Backup complete: $BACKUP_FILE"
```

### Cron Configuration

Add to `/etc/cron.d/zzedc-backup`:
```
0 2 * * * root /usr/local/bin/zzedc-backup.sh >> /var/log/zzedc-backup.log 2>&1
```

### Backup Verification

Verify backup integrity:
```bash
sha256sum -c /var/backups/zzedc/study_20251218_020000.db.sha256
```

## Key Rotation Procedures

### Annual Key Rotation

Rotate encryption keys annually or after security incidents:

```r
rotate_encryption_key(
  db_path = "/var/data/zzedc/study.db",
  old_key = Sys.getenv("DB_ENCRYPTION_KEY"),
  secret_name = "zzedc/db-encryption-key"
)
```

### Key Rotation Steps

1. Generate new encryption key
2. Create database backup
3. Re-encrypt database with new key
4. Update AWS Secrets Manager
5. Update environment configurations
6. Verify application connectivity
7. Securely destroy old key material

## Monitoring and Alerting

### Health Check Endpoint

Add to application for monitoring:
```r
health_check <- function() {
  tryCatch({
    conn <- connect_encrypted_db()
    result <- DBI::dbGetQuery(conn, "SELECT 1")
    DBI::dbDisconnect(conn)
    list(status = "healthy", timestamp = Sys.time())
  }, error = function(e) {
    list(status = "unhealthy", error = e$message)
  })
}
```

### Log Monitoring

Monitor for encryption-related errors:
```bash
grep -E "(encryption|decryption|key)" /var/log/shiny-server/*.log
```

### Audit Log Review

Regular audit log review:
```r
recent_activity <- get_audit_trail(
  filters = list(
    date_from = Sys.Date() - 7
  ),
  db_path = "/var/data/zzedc/study.db"
)
```

## Disaster Recovery

### Recovery from Backup

```r
success <- rollback_migration(
  backup_path = "/var/backups/zzedc/study_20251218_020000.db",
  restore_to = "/var/data/zzedc/study.db"
)
```

### Key Recovery Procedures

Document key recovery procedures separately and store securely:

1. Contact authorized key custodian
2. Verify identity through multi-factor authentication
3. Retrieve key from secure offline storage
4. Update AWS Secrets Manager if applicable
5. Restart application services
6. Verify data accessibility
7. Document recovery in incident log

## Security Checklist

### Pre-Deployment

- [ ] SQLCipher installed and verified
- [ ] Encryption key generated securely
- [ ] AWS Secrets Manager configured (production)
- [ ] IAM policies configured
- [ ] Database file permissions set
- [ ] Backup procedures tested
- [ ] Key rotation procedure documented

### Post-Deployment

- [ ] Application connects successfully
- [ ] Data encryption verified
- [ ] Audit logging functioning
- [ ] Backup automation confirmed
- [ ] Monitoring alerts configured
- [ ] Recovery procedures tested

## Compliance Documentation

### GDPR Article 32 Evidence

- Encryption implementation: This document
- Key management procedures: AWS Secrets Manager configuration
- Access controls: IAM policies and file permissions
- Audit trail: init_audit_logging() implementation

### FDA 21 CFR Part 11 Evidence

- Electronic records: Encrypted database storage
- Audit trail: Hash-chained audit logging
- Access controls: Role-based application security
- Data integrity: SHA-256 verification for exports

## Support and Resources

### Documentation

- Feature documentation: `vignettes/feature-encryption-at-rest.Rmd`
- Troubleshooting guide: `docs/ENCRYPTION_TROUBLESHOOTING.md`
- API reference: Package documentation

### Contact

For technical support regarding encryption implementation, contact the
development team with relevant log excerpts and configuration details.
