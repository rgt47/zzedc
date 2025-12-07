# Local Development Troubleshooting Guide

Solutions to common issues when running ZZedc locally with Docker.

---

## Quick Reference

| Issue | Symptom | Solution |
|-------|---------|----------|
| Port in use | "bind: address already in use" | Change port to 3839 or kill process |
| Build fails | "Error: failed to solve" | Clear cache, check internet |
| Slow startup | Takes >2 minutes | Allocate more Docker resources |
| Login fails | "Invalid username or password" | Check .env.dev, reset database |
| Database error | "Error reading database" | Check permissions, restart containers |
| Can't access app | "Connection refused" | Check if container is running |
| Out of disk space | "No space left" | Clear Docker cache and old images |
| Docker not installed | Command not found | Install Docker Desktop |

---

## Installation Issues

### Docker Not Installed

**Error Message**:
```
docker: command not found
```

**Solution**:

1. **Download and Install Docker Desktop**:
   - macOS: https://docs.docker.com/desktop/install/mac-install/
   - Windows: https://docs.docker.com/desktop/install/windows-install/
   - Linux: https://docs.docker.com/engine/install/

2. **Verify Installation**:
   ```bash
   docker --version
   docker-compose --version
   ```

3. **Start Docker**:
   - macOS/Windows: Open Docker Desktop application
   - Linux: `sudo systemctl start docker`

### Docker Requires Admin Privileges

**Error Message**:
```
permission denied while trying to connect to Docker daemon
```

**Solution - Windows**:
- Right-click Docker Desktop → Run as administrator
- Or: Add your user to docker group (requires restart)

**Solution - macOS**:
- Open Docker Desktop application from Applications folder
- Docker daemon should start automatically

**Solution - Linux**:
```bash
# Add current user to docker group
sudo usermod -aG docker $USER

# Log out and log back in for changes to take effect
# Or use newgrp:
newgrp docker

# Verify
docker ps
```

### Insufficient Disk Space

**Error Message**:
```
no space left on device
failed to solve with frontend dockerfile.v0
```

**Solution**:

1. **Check available disk space**:
   ```bash
   # macOS/Linux:
   df -h

   # Windows:
   dir C:
   ```

2. **Free up space**:
   ```bash
   # Remove unused Docker images
   docker image prune -a

   # Remove unused volumes
   docker volume prune

   # Remove unused networks
   docker network prune

   # Remove everything unused
   docker system prune -a
   ```

3. **Allocate more disk space to Docker** (Docker Desktop):
   - Open Docker Desktop settings
   - Resources → Disk Image Size → Increase to 50 GB
   - Apply and restart

### Unable to Download Docker Image

**Error Message**:
```
failed to solve with frontend dockerfile.v0
```

**Solution**:

1. **Check internet connection**:
   ```bash
   ping docker.io
   ```

2. **Retry the build**:
   ```bash
   docker-compose -f docker-compose.dev.yml build --no-cache
   ```

3. **Check Docker daemon**:
   ```bash
   docker ps
   ```
   If this fails, restart Docker Desktop

4. **Try different Docker registry**:
   ```bash
   # Edit Dockerfile if needed and rebuild
   docker-compose -f docker-compose.dev.yml build --verbose
   ```

---

## Build Issues

### Build Takes Too Long

**Symptom**: Build takes more than 5 minutes

**Causes**:
- First build downloads large R packages (~500 MB)
- Slow internet connection
- Docker has limited resources
- Disk I/O bottleneck

**Solutions**:

1. **Allocate more Docker resources**:
   - Open Docker Desktop settings
   - Resources → CPU: 4, Memory: 4GB
   - Apply and restart

2. **Use a wired internet connection**:
   - WiFi can be slow for large downloads
   - Use Ethernet if available

3. **Rebuild with verbose output** to see progress:
   ```bash
   docker-compose -f docker-compose.dev.yml build --verbose
   ```

4. **Rebuild without cache** (clean rebuild):
   ```bash
   docker-compose -f docker-compose.dev.yml build --no-cache
   ```

### Build Fails Partway Through

**Error Message**:
```
ERROR: failed to solve with frontend dockerfile.v0
```

**Causes**:
- Network interruption
- Insufficient memory
- Disk full
- Package not available

**Solutions**:

1. **Clear everything and retry**:
   ```bash
   docker-compose -f docker-compose.dev.yml down
   docker system prune -a
   docker-compose -f docker-compose.dev.yml build
   ```

2. **Check Docker log**:
   ```bash
   # macOS/Windows: Check Docker Desktop → Preferences → Resources
   # Linux: journalctl -u docker
   ```

3. **Try a different base image version**:
   - Edit Dockerfile if needed
   - Change FROM rocker/r-ubuntu:4.4 to rocker/r-ubuntu:4.3
   - Try rebuild

---

## Startup Issues

### Application Won't Start

**Symptom**: Nothing appears after `docker-compose up`, or errors appear

**Diagnosis**:
```bash
# Check if container is running
docker-compose -f docker-compose.dev.yml ps

# View logs
docker-compose -f docker-compose.dev.yml logs -f
```

**Common Causes and Solutions**:

#### R Packages Not Loading
```
Error in library(shiny): there is no package called 'shiny'
```

**Solution**:
```bash
# Rebuild Docker image
docker-compose -f docker-compose.dev.yml down
docker-compose -f docker-compose.dev.yml build --no-cache
docker-compose -f docker-compose.dev.yml up
```

#### Port Already Bound
```
Error: cannot bind to 127.0.0.1:3838
```

**Solution**: See "Port Already in Use" section below

#### Database Locked
```
Error: database is locked
```

**Solution**:
```bash
# Stop all containers
docker-compose -f docker-compose.dev.yml down
docker-compose -f docker-compose.dev.yml down -v  # This also removes volumes

# Wait 10 seconds, then restart
sleep 10
docker-compose -f docker-compose.dev.yml up
```

#### Memory Issues
```
Killed (exit code 137)
```

**Solution**:
- Container ran out of memory
- Allocate more RAM to Docker (Settings → Resources → Memory: 4GB+)

---

## Port Issues

### Port 3838 Already in Use

**Error Message**:
```
Error response from daemon: bind: address already in use
```

**Diagnosis**:
```bash
# macOS/Linux - Find what's using the port:
lsof -i :3838

# Windows - Find what's using the port:
netstat -ano | findstr :3838
```

**Solution 1: Use Different Port**

Edit `docker-compose.dev.yml`:
```yaml
services:
  zzedc:
    ports:
      - "3839:3838"  # Changed from "3838:3838"
```

Then access: http://localhost:3839

**Solution 2: Kill the Process**

If you know it's safe to kill the other process:

```bash
# macOS/Linux:
kill -9 [PID from lsof output]

# Windows (in Administrator command prompt):
taskkill /PID [PID] /F
```

Then try again:
```bash
docker-compose -f docker-compose.dev.yml up
```

**Solution 3: Stop Other Containers**

If another ZZedc instance is running:
```bash
# Stop all containers
docker stop $(docker ps -q)

# Or specifically
docker-compose -f docker-compose.dev.yml down
```

---

## Connectivity Issues

### Can't Access http://localhost:3838

**Check List**:

1. **Is the container running?**
   ```bash
   docker-compose -f docker-compose.dev.yml ps
   # Should show: zzedc-dev ... Up
   ```

2. **Does the log show "Listen on"?**
   ```bash
   docker-compose -f docker-compose.dev.yml logs
   # Should contain: Listen on http://0.0.0.0:3838
   ```

3. **Try different URLs**:
   - http://localhost:3838
   - http://127.0.0.1:3838
   - http://host.docker.internal:3838 (on Mac/Windows)

4. **Check firewall**:
   - macOS: System Preferences → Security & Privacy → Firewall
   - Windows: Settings → Firewall → Allow Docker through firewall
   - Linux: `sudo firewall-cmd --add-port=3838/tcp`

**Solutions**:

```bash
# Restart everything
docker-compose -f docker-compose.dev.yml down
docker-compose -f docker-compose.dev.yml up

# Check logs for errors
docker-compose -f docker-compose.dev.yml logs -f

# Verify port is actually bound
netstat -tulpn | grep 3838  # Linux
lsof -i :3838              # macOS
netstat -ano | grep 3838   # Windows
```

### Slow Loading

**Symptom**: Page takes 10+ seconds to load

**Causes**:
- Docker resource constraints
- Network latency
- Large dataset
- Browser cache

**Solutions**:

1. **Increase Docker resources**:
   - Docker Desktop → Settings → Resources
   - CPU: 4+, Memory: 4GB+
   - Apply and restart

2. **Clear browser cache**:
   - Ctrl+Shift+Delete (most browsers)
   - Or use Incognito/Private window

3. **Check system resources**:
   ```bash
   # macOS:
   top

   # Linux:
   top
   htop

   # Windows:
   Task Manager (Ctrl+Shift+Esc)
   ```

4. **Restart container**:
   ```bash
   docker-compose -f docker-compose.dev.yml restart
   ```

---

## Login Issues

### Login Fails

**Error Message**:
```
Invalid username or password
```

**Diagnosis**:

1. **Check credentials in .env.dev**:
   ```bash
   cat .env.dev | grep -E "ADMIN|PASSWORD"
   ```

2. **Check logs for auth errors**:
   ```bash
   docker-compose -f docker-compose.dev.yml logs | grep -i "auth\|login\|password"
   ```

**Solutions**:

1. **Verify password is correct**:
   - Check .env.dev: `ADMIN_PASSWORD=development123`
   - Passwords are case-sensitive
   - No extra spaces

2. **Reset the database** (deletes all data):
   ```bash
   docker-compose -f docker-compose.dev.yml down
   rm ./data/zzedc.db
   docker-compose -f docker-compose.dev.yml up
   # Login with: admin / development123
   ```

3. **Create a new admin user**:
   ```bash
   docker-compose -f docker-compose.dev.yml exec zzedc \
     Rscript -e "source('add_test_user.R')"
   ```

4. **Check database**:
   ```bash
   docker-compose -f docker-compose.dev.yml exec zzedc \
     sqlite3 /app/data/zzedc.db "SELECT username, email FROM users;"
   ```

---

## Database Issues

### "Database is Locked" Error

**Error Message**:
```
database is locked
attempt to write a readonly database
```

**Causes**:
- Multiple containers/processes accessing database simultaneously
- Incorrect file permissions
- Corrupted database

**Solutions**:

1. **Stop all containers**:
   ```bash
   docker-compose -f docker-compose.dev.yml down

   # Wait 5 seconds
   sleep 5

   # Restart
   docker-compose -f docker-compose.dev.yml up
   ```

2. **Fix file permissions**:
   ```bash
   chmod 755 ./data/
   chmod 644 ./data/zzedc.db
   ```

3. **Check database integrity**:
   ```bash
   docker-compose -f docker-compose.dev.yml exec zzedc \
     sqlite3 /app/data/zzedc.db "PRAGMA integrity_check;"
   # Should return: ok
   ```

4. **Rebuild database** (if corrupted):
   ```bash
   docker-compose -f docker-compose.dev.yml down
   rm ./data/zzedc.db
   docker-compose -f docker-compose.dev.yml up
   ```

### "Unable to Open Database File"

**Error Message**:
```
unable to open database file
```

**Causes**:
- /app/data directory doesn't exist
- Missing write permissions
- Volume not mounted correctly

**Solutions**:

1. **Ensure data directory exists**:
   ```bash
   # Create on host machine
   mkdir -p ./data
   chmod 755 ./data
   ```

2. **Verify volume is mounted**:
   ```bash
   docker-compose -f docker-compose.dev.yml exec zzedc ls -la /app/data/
   # Should show the directory
   ```

3. **Check docker-compose.dev.yml volume**:
   ```yaml
   volumes:
     - ./data:/app/data  # This line must exist
   ```

4. **Restart and rebuild**:
   ```bash
   docker-compose -f docker-compose.dev.yml down
   docker-compose -f docker-compose.dev.yml build
   docker-compose -f docker-compose.dev.yml up
   ```

### Data Lost After Restart

**Symptom**: Data was there, then disappeared after restart

**Causes**:
- Accidentally deleted ./data/zzedc.db
- Used `docker-compose down -v` (removes volumes)
- Volume not mounted correctly

**Solution**:

1. **Check if data directory exists**:
   ```bash
   ls -la ./data/
   # Should show zzedc.db
   ```

2. **Restore from backup** (if available):
   ```bash
   cp ./data/zzedc.db.backup ./data/zzedc.db
   docker-compose -f docker-compose.dev.yml up
   ```

3. **Prevent future loss - create backups**:
   ```bash
   # Create backup before each major change
   cp ./data/zzedc.db ./data/zzedc.db.backup-$(date +%Y%m%d-%H%M%S)
   ```

---

## Performance Issues

### Application Running Slowly

**Symptom**: Data entry, reports, or export takes a long time

**Causes**:
- Limited Docker resources
- Large dataset in database
- Inefficient queries
- System resource constraints

**Solutions**:

1. **Allocate more resources to Docker**:
   - Docker Desktop → Settings → Resources
   - CPU: 4, Memory: 4GB, Disk: 50GB
   - Apply and restart

2. **Close other applications**:
   - Free up system RAM
   - Close browser tabs
   - Quit other Docker containers

3. **Check database size**:
   ```bash
   ls -lh ./data/zzedc.db
   # If > 1GB, database is large
   ```

4. **Optimize database**:
   ```bash
   docker-compose -f docker-compose.dev.yml exec zzedc \
     sqlite3 /app/data/zzedc.db "VACUUM;"
   ```

5. **Monitor resource usage**:
   - Docker Desktop → Preferences → Resources → Usage
   - Or: `docker stats`

---

## Advanced Troubleshooting

### Check Full Container Logs

```bash
# All logs with timestamps
docker-compose -f docker-compose.dev.yml logs --timestamps

# Follow logs in real-time
docker-compose -f docker-compose.dev.yml logs -f

# Last 200 lines
docker-compose -f docker-compose.dev.yml logs --tail 200

# All logs saved to file
docker-compose -f docker-compose.dev.yml logs > logs.txt 2>&1
```

### Access Container Shell

```bash
# Get shell inside running container
docker-compose -f docker-compose.dev.yml exec zzedc /bin/bash

# Inside the container, you can:
# - Check files: ls -la
# - View database: sqlite3 /app/data/zzedc.db
# - Run R: R
# - Check environment: env
# - Exit: exit
```

### Reset Docker Completely

**Warning**: This removes all Docker containers and images!

```bash
# Remove only ZZedc
docker-compose -f docker-compose.dev.yml down
docker system prune -a

# Rebuild
docker-compose -f docker-compose.dev.yml build
docker-compose -f docker-compose.dev.yml up
```

### Check Docker System Status

```bash
# View all containers
docker ps -a

# View all images
docker images

# Check Docker disk usage
docker system df

# View docker events (in another terminal)
docker events

# Inspect a container
docker inspect zzedc-dev
```

---

## Getting Help

If you're still stuck:

1. **Collect diagnostic information**:
   ```bash
   docker-compose -f docker-compose.dev.yml logs > zzedc_logs.txt 2>&1
   docker-compose -f docker-compose.dev.yml ps > containers.txt
   docker system df > docker_usage.txt
   ```

2. **Check existing issues**:
   - https://github.com/rgt47/zzedc/issues

3. **Create a new issue** with:
   - Error message and logs
   - Steps to reproduce
   - Operating system and Docker version
   - System resources (CPU, RAM)
   - Output of diagnostic commands above

4. **Contact support**:
   - Email: rgthomas@ucsd.edu
   - Include diagnostic files

---

## Prevention Tips

### Avoid Common Problems

1. **Regular backups**:
   ```bash
   # Daily backup
   cp ./data/zzedc.db ./backups/zzedc.db.$(date +%Y%m%d)
   ```

2. **Monitor logs regularly**:
   ```bash
   docker-compose -f docker-compose.dev.yml logs | grep -i error
   ```

3. **Keep Docker updated**:
   - Check Docker Desktop for updates weekly
   - Update your ZZedc code: `git pull`

4. **Document your setup**:
   - Save your .env.dev configuration
   - Document any customizations
   - Keep notes on troubleshooting steps

5. **Test before major changes**:
   - Back up database first
   - Make one change at a time
   - Test thoroughly before next change

---

**Last Updated**: December 2025
**Version**: 1.0
**Status**: Comprehensive Troubleshooting Guide
