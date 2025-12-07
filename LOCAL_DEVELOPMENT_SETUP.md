# ZZedc Local Development Setup Guide

Complete guide for solo researchers to run ZZedc on their local machine.

**Status**: ✅ Ready for immediate use
**Target Users**: Solo researchers, developers, pilot testing
**Cost**: $0 (runs on your laptop)
**Setup Time**: 5-10 minutes (first time)

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [System Requirements](#system-requirements)
3. [Installation Steps](#installation-steps)
4. [Starting the Application](#starting-the-application)
5. [Using the Application](#using-the-application)
6. [Development Workflow](#development-workflow)
7. [Stopping and Restarting](#stopping-and-restarting)
8. [Data Persistence](#data-persistence)
9. [Testing Features](#testing-features)
10. [Transitioning to Production](#transitioning-to-production)
11. [Troubleshooting](#troubleshooting)

---

## Quick Start

For experienced Docker users, the complete setup is 3 commands:

```bash
# 1. Prepare configuration
cp .env.dev.example .env.dev
nano .env.dev  # Edit study info (optional - defaults are fine)

# 2. Build and start
docker-compose -f docker-compose.dev.yml build
docker-compose -f docker-compose.dev.yml up

# 3. Open browser
# http://localhost:3838
# Username: admin
# Password: development123
```

Then skip to [Using the Application](#using-the-application).

---

## System Requirements

### Required Software

You must have these installed on your computer:

#### **Docker Desktop** (Required)

- **macOS**: Download from https://www.docker.com/products/docker-desktop
  - Apple Silicon (M1/M2): Choose "Apple Silicon" version
  - Intel: Choose "Intel Chip" version
  - Minimum: macOS 11 (Big Sur) or later
  - Disk Space: 5 GB minimum

- **Windows**: Download from https://www.docker.com/products/docker-desktop
  - Requires Windows 10/11 Pro, Enterprise, or Education
  - WSL2 (Windows Subsystem for Linux 2) required
  - Disk Space: 5 GB minimum
  - Administrator privileges required

- **Linux**: Install via package manager
  - Ubuntu/Debian: `sudo apt-get install docker.io docker-compose`
  - Fedora/RHEL: `sudo dnf install docker docker-compose`
  - Requires `sudo` privileges

**Verify Installation**:
```bash
docker --version
docker-compose --version

# Both should show version 20.x or later
```

#### **Git** (Recommended)

For cloning the repository:

```bash
# Check if installed
git --version

# Install if needed:
# macOS: brew install git
# Windows: https://git-scm.com/download/win
# Linux: sudo apt-get install git
```

#### **Text Editor** (Recommended)

Edit configuration files:

- **macOS/Linux**: nano (built-in), vim, VS Code
- **Windows**: Notepad, VS Code, Notepad++

### Hardware Requirements

**Minimum**:
- CPU: 2 cores
- RAM: 2 GB
- Disk: 5 GB free
- Network: Local internet connection

**Recommended**:
- CPU: 4 cores
- RAM: 4 GB
- Disk: 10 GB free
- Network: Stable connection

### Network Requirements

- Port 3838 available on localhost (or change in docker-compose.dev.yml)
- Docker can download images (~500 MB on first build)
- Internet connection for initial setup

---

## Installation Steps

### Step 1: Get the Code

**Option A: Clone from GitHub** (Recommended)

```bash
git clone https://github.com/rgt47/zzedc.git
cd zzedc
```

**Option B: Download as ZIP**

1. Go to https://github.com/rgt47/zzedc
2. Click "Code" → "Download ZIP"
3. Extract the zip file
4. Open terminal/command prompt in extracted directory

### Step 2: Verify Files

Ensure these files exist in your zzedc directory:

```bash
# Check for required files
ls -la docker-compose.dev.yml
ls -la .env.dev.example
ls -la Dockerfile
ls -la deployment/docker-compose.yml

# You should see all these files
```

### Step 3: Configure Environment

```bash
# Copy the example configuration
cp .env.dev.example .env.dev

# Edit the configuration (optional - defaults are fine for testing)
# macOS/Linux:
nano .env.dev

# Or use your preferred editor:
# - VS Code: code .env.dev
# - vim: vim .env.dev
# - Notepad++: notepad++ .env.dev (Windows)
```

**Configuration Options** (Optional):

You can customize these values, but defaults work fine:
- `STUDY_NAME`: Change to your study name (default: "Local Development Trial")
- `STUDY_ID`: Change to study ID (default: "DEV-2025-001")
- `ADMIN_PASSWORD`: Change admin password (default: "development123")
- All other settings can stay as default for local testing

**Example .env.dev** (if you want to customize):

```ini
STUDY_NAME=My Research Project
STUDY_ID=MYRESEARCH-2025
PI_EMAIL=myemail@institution.edu
ADMIN_PASSWORD=mypassword123
LOG_LEVEL=debug
```

### Step 4: Allocate Docker Resources

Docker on your machine needs enough resources:

#### **macOS/Windows with Docker Desktop**

1. Open Docker Desktop application
2. Click **Settings** (or **Preferences**)
3. Go to **Resources**
4. Allocate:
   - **CPUs**: 2 (minimum) or 4 (recommended)
   - **Memory**: 2 GB (minimum) or 4 GB (recommended)
   - **Disk Image Size**: 20 GB minimum
5. Click **Apply & Restart**

#### **Linux**

Resources allocated automatically from system. No configuration needed.

---

## Starting the Application

### First Time: Build and Start

```bash
# Navigate to zzedc directory
cd /path/to/zzedc

# Build the Docker image (first time only - takes 2-5 minutes)
docker-compose -f docker-compose.dev.yml build

# Start the application
docker-compose -f docker-compose.dev.yml up
```

**Expected Output**:

```
Creating network "zzedc_zzedc-dev-network" with driver "bridge"
Building zzedc
...
[+] Building 2.5s
[+] Building ZZedc development image...
[+] Image successfully built
Creating zzedc-dev ... done
Attaching to zzedc-dev
zzedc-dev | ... initialization messages ...
zzedc-dev | Launching ZZedc application ...
zzedc-dev | Listen on http://0.0.0.0:3838
```

**When you see "Listen on http://0.0.0.0:3838", the app is ready!**

### Subsequent Starts (After First Build)

```bash
# Just start (no need to rebuild)
docker-compose -f docker-compose.dev.yml up
```

### Run in Background

If you want to use the terminal for other tasks:

```bash
# Start in background (detached mode)
docker-compose -f docker-compose.dev.yml up -d

# View logs anytime
docker-compose -f docker-compose.dev.yml logs -f

# Stop when done
docker-compose -f docker-compose.dev.yml down
```

---

## Using the Application

### Access the Application

Once "Listen on http://0.0.0.0:3838" appears:

1. **Open your browser** (Chrome, Safari, Firefox, Edge)
2. **Navigate to**: http://localhost:3838
3. **You should see** the ZZedc login page

### First Login

**Login Credentials**:
- **Username**: `admin`
- **Password**: `development123` (or your custom password from .env.dev)

**First Time Actions**:
1. Click "Login"
2. Verify you're logged in (see admin dashboard)
3. Change your password (Settings → Change Password)
   - Important for non-development use
   - Remember the new password

### Main Features to Test

#### 1. **EDC Tab**: Data Entry Forms
   - Create test forms for your study
   - Test form validation
   - Enter test data for participants
   - Verify data is saved

#### 2. **Reports Tab**: Data Analysis
   - Generate basic reports
   - Quality assurance checks
   - Statistical summaries

#### 3. **Data Explorer**: Browse Data
   - View all entered data
   - Search for specific records
   - Filter by participant or form

#### 4. **Export Tab**: Data Export
   - Export data in CSV format
   - Test export functions
   - Verify data integrity

#### 5. **Admin Panel**: User Management
   - Create test user accounts
   - Assign roles (Coordinator, Manager, etc.)
   - Verify access control

---

## Development Workflow

### Typical Daily Workflow

**Morning - Start Work**:
```bash
# Start the application
docker-compose -f docker-compose.dev.yml up

# Open browser: http://localhost:3838
# Login with your credentials
```

**During Day - Testing**:
1. Create forms and test data
2. Verify validation rules work
3. Test export/reporting functions
4. Create participant records
5. Check data persistence

**End of Day - Save Work**:
```bash
# Data is automatically saved in ./data/zzedc.db
# Application data survives restart

# Stop the application (Ctrl+C in terminal)
# Or in background mode:
docker-compose -f docker-compose.dev.yml down
```

### Modifying Application Code

If you want to make code changes:

```bash
# 1. Stop the application
docker-compose -f docker-compose.dev.yml down

# 2. Edit your code
# Edit files in R/, ui.R, server.R, etc.

# 3. Rebuild
docker-compose -f docker-compose.dev.yml build

# 4. Restart
docker-compose -f docker-compose.dev.yml up
```

### Viewing Logs for Debugging

```bash
# View logs in real-time
docker-compose -f docker-compose.dev.yml logs -f zzedc

# View logs with timestamps
docker-compose -f docker-compose.dev.yml logs -f --timestamps

# View just errors
docker-compose -f docker-compose.dev.yml logs zzedc | grep -i error

# View last 100 lines
docker-compose -f docker-compose.dev.yml logs --tail 100
```

---

## Stopping and Restarting

### Stop the Application

**In Foreground**:
```bash
# Press Ctrl+C in the terminal
# Application stops cleanly
```

**In Background**:
```bash
docker-compose -f docker-compose.dev.yml down
```

### Restart the Application

```bash
# Just start again (data is preserved)
docker-compose -f docker-compose.dev.yml up

# Background:
docker-compose -f docker-compose.dev.yml up -d
```

### Check Running Containers

```bash
# See if ZZedc is running
docker-compose -f docker-compose.dev.yml ps

# All Docker containers on your machine:
docker ps
```

---

## Data Persistence

### Where is My Data?

**Database File Location**:
```
./data/zzedc.db
```

This SQLite database contains:
- All study configurations
- All participant records
- All form responses
- All user accounts
- All audit logs

### Data Survives

✅ **Survives these events**:
- Container restart
- Application restart
- Docker daemon restart
- Computer restart (if you save ./data/)

❌ **Lost in these events**:
- Deleting ./data/ directory
- Running `docker-compose down -v` (with -v flag)
- Deleting entire zzedc directory

### Backup Your Data

**Important**: Back up your database regularly!

```bash
# Create a backup
cp ./data/zzedc.db ./data/zzedc.db.backup-$(date +%Y%m%d)

# Or on macOS/Linux:
cp ./data/zzedc.db ~/Desktop/zzedc_backup_$(date +%Y%m%d_%H%M%S).db

# Or on Windows:
copy data\zzedc.db data\zzedc.db.backup
```

### Restore from Backup

```bash
# Stop the application first
docker-compose -f docker-compose.dev.yml down

# Restore backup
cp ./data/zzedc.db.backup-YYYYMMDD ./data/zzedc.db

# Start again
docker-compose -f docker-compose.dev.yml up
```

---

## Testing Features

### Creating Test Data

1. **Create a test participant**:
   - Go to EDC tab → Create New Record
   - Enter participant ID: "TEST001"
   - Fill in form fields with test values
   - Save

2. **Create another participant**:
   - Repeat with different ID: "TEST002"
   - Test form validation (required fields, etc.)
   - Verify error messages

3. **Test export**:
   - Go to Export tab
   - Download data as CSV
   - Open in Excel/Numbers to verify format

### Testing Validation Rules

1. **Test required fields**:
   - Leave required fields blank
   - Try to save
   - See error message

2. **Test range validation**:
   - Enter value outside acceptable range
   - See validation error

3. **Test conditional fields**:
   - Set field value
   - See dependent fields appear/disappear
   - Verify branching logic

### Testing Data Persistence

1. **Create a record**
2. **Stop the application**: Ctrl+C
3. **Start it again**: `docker-compose -f docker-compose.dev.yml up`
4. **Login and check**: Your data is still there! ✓

### Clearing Test Data

If you want to start fresh:

```bash
# Stop the application
docker-compose -f docker-compose.dev.yml down

# Delete the database
rm ./data/zzedc.db

# Start again (fresh database)
docker-compose -f docker-compose.dev.yml up

# First login will set up empty database
```

---

## Transitioning to Production

When ready to deploy to AWS:

### Step 1: Prepare Production Configuration

```bash
# Copy production template
cp deployment/.env.template .env

# Edit with production values
nano .env

# Set:
# STUDY_NAME=Your Real Study Name
# STUDY_ID=REAL-PROTOCOL-ID
# ADMIN_PASSWORD=StrongPassword123!
# PI_EMAIL=real.email@institution.edu
# Generate new ZZEDC_SALT: openssl rand -hex 16
```

### Step 2: Test on AWS

```bash
# From deployment directory
cd deployment

# Run AWS test
./aws_test.sh \
  --study-name "Your Study Name" \
  --study-id "PROTOCOL-ID" \
  --admin-password "StrongPassword123!" \
  --domain trial.yourinstitution.org
```

### Step 3: Deploy to Production

```bash
# Run AWS deployment
./aws_setup.sh \
  --study-name "Your Study Name" \
  --study-id "PROTOCOL-ID" \
  --admin-password "StrongPassword123!" \
  --domain trial.yourinstitution.org \
  --instance-type t3.small
```

### Step 4: Follow Deployment Checklist

See `deployment/IT_STAFF_DEPLOYMENT_CHECKLIST.md` for complete verification steps.

---

## Troubleshooting

### Issue: Port 3838 Already in Use

**Symptom**: Error like "bind: address already in use"

**Solutions**:

1. **Find what's using the port**:
   ```bash
   # macOS/Linux:
   lsof -i :3838

   # Windows:
   netstat -ano | findstr :3838
   ```

2. **Use a different port**:
   Edit `docker-compose.dev.yml`:
   ```yaml
   ports:
     - "3839:3838"  # Changed from 3838
   ```
   Then access http://localhost:3839

3. **Kill the process** (if safe):
   ```bash
   # macOS/Linux:
   kill -9 [PID]
   ```

### Issue: Docker Build Fails

**Symptom**: "Error: failed to solve..."

**Solutions**:

1. **Check internet connection**
2. **Clear Docker cache**:
   ```bash
   docker-compose -f docker-compose.dev.yml down
   docker system prune -a
   docker-compose -f docker-compose.dev.yml build --no-cache
   ```
3. **Check disk space**:
   - Docker needs 5-10 GB free space
   - Clear old Docker images if needed

### Issue: Application Slow to Start

**Symptom**: Takes more than 2 minutes to see "Listen on..."

**Solutions**:

1. **Allocate more Docker resources**:
   - Open Docker Desktop settings
   - Increase CPU and memory allocation
   - Apply and restart Docker

2. **Check system resources**:
   - Close other applications
   - Free up RAM
   - Check disk space

3. **View build logs**:
   ```bash
   docker-compose -f docker-compose.dev.yml build --verbose
   ```

### Issue: Login Fails

**Symptom**: "Invalid username or password" despite correct credentials

**Solutions**:

1. **Check password**:
   - Verify in .env.dev: `ADMIN_PASSWORD=development123`
   - Case-sensitive!

2. **Reset password**:
   ```bash
   # Stop application
   docker-compose -f docker-compose.dev.yml down

   # Delete database to reset
   rm ./data/zzedc.db

   # Start again - use default password
   docker-compose -f docker-compose.dev.yml up
   ```

3. **Check logs**:
   ```bash
   docker-compose -f docker-compose.dev.yml logs -f
   ```

### Issue: Database Errors

**Symptom**: "Error reading/writing to database"

**Solutions**:

1. **Check file permissions**:
   ```bash
   ls -la ./data/
   chmod 755 ./data/
   chmod 644 ./data/zzedc.db
   ```

2. **Stop all containers**:
   ```bash
   docker-compose -f docker-compose.dev.yml down
   # Wait 5 seconds
   docker-compose -f docker-compose.dev.yml up
   ```

3. **Check database integrity**:
   ```bash
   docker-compose -f docker-compose.dev.yml exec zzedc \
     sqlite3 /app/data/zzedc.db "PRAGMA integrity_check;"
   ```

### Issue: Can't Access http://localhost:3838

**Symptom**: "Connection refused" or page won't load

**Solutions**:

1. **Verify application is running**:
   ```bash
   docker-compose -f docker-compose.dev.yml ps
   # Should show: zzedc-dev ... Up
   ```

2. **Check logs**:
   ```bash
   docker-compose -f docker-compose.dev.yml logs -f
   # Look for "Listen on http://0.0.0.0:3838"
   ```

3. **Try the IP address directly**:
   - http://127.0.0.1:3838
   - http://host.docker.internal:3838 (on Windows/Mac)

4. **Restart everything**:
   ```bash
   docker-compose -f docker-compose.dev.yml down
   docker-compose -f docker-compose.dev.yml up
   ```

### More Help

See `LOCAL_DEVELOPMENT_TROUBLESHOOTING.md` for additional solutions.

---

## Common Questions

**Q: Will my data be lost if I restart the computer?**

A: No! Your SQLite database is saved in `./data/zzedc.db` on your computer. It survives restarts.

**Q: Can I use this for a real study?**

A: Yes, but you should back up your data regularly and consider moving to AWS for better security and multi-user access.

**Q: How do I share data with collaborators?**

A: Export to CSV in the Export tab, or deploy to AWS so multiple people can access it.

**Q: What if I need HTTPS locally?**

A: For most development, HTTP on localhost is fine. For production, use `docker-compose.yml` which includes Caddy for automatic HTTPS.

**Q: Can I make changes to the code while it's running?**

A: You can see changes to some files immediately, but for major changes, rebuild:
```bash
docker-compose -f docker-compose.dev.yml down
docker-compose -f docker-compose.dev.yml build
docker-compose -f docker-compose.dev.yml up
```

---

## Next Steps

1. **[START NOW]** Follow "Quick Start" section above
2. **Create test data** using the application
3. **Explore features** (EDC, Reports, Export, etc.)
4. **Test validation** rules and workflows
5. **When ready for production**: Follow "Transitioning to Production" section

---

## Support

- **GitHub Issues**: https://github.com/rgt47/zzedc/issues
- **Email**: rgthomas@ucsd.edu
- **Documentation**: See `LOCAL_DEVELOPMENT_TROUBLESHOOTING.md`

---

**Last Updated**: December 2025
**Version**: 1.0
**Status**: Production Ready for Local Development
