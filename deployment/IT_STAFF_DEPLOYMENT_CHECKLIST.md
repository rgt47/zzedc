# ZZedc AWS Deployment Checklist
## For IT Staff and Cloud Administrators

**Document Version:** 1.0
**Last Updated:** December 2025
**Intended Audience:** IT staff, cloud administrators, DevOps engineers deploying ZZedc for research teams

---

## Pre-Deployment Phase

### AWS Account and Permissions
- [ ] AWS account created and active
- [ ] AWS CLI installed on local machine: `aws --version`
- [ ] AWS credentials configured: `aws configure`
- [ ] IAM user has EC2, VPC, and Route53 permissions
- [ ] Test AWS access: `aws sts get-caller-identity`

### Prerequisites Installed Locally
- [ ] Git installed: `git --version`
- [ ] Docker installed: `docker --version`
- [ ] OpenSSL installed: `openssl version`
- [ ] Bash shell available (macOS, Linux, or WSL on Windows)

### Study Information Gathered
- [ ] Study name confirmed with investigator
- [ ] Study protocol ID obtained (e.g., "DEPR-2025-001")
- [ ] Principal Investigator email address confirmed
- [ ] Domain name decided (e.g., trial.example.org)
- [ ] Secure admin password generated (8+ characters, mix of types)
- [ ] Security salt generated (will be auto-generated, confirm storage plan)

### DNS and Domain Setup
- [ ] Domain name registered and accessible
- [ ] Domain registrar dashboard access available
- [ ] Ability to add A records confirmed
- [ ] OR: Route53 hosted zone created if using AWS Route53

---

## AWS Infrastructure Setup Phase

### Execute Deployment Script
- [ ] Navigate to `deployment/` directory
- [ ] Make script executable: `chmod +x aws_setup.sh`
- [ ] Run with required parameters:
  ```bash
  ./aws_setup.sh \
    --region us-west-2 \
    --study-name "Depression Treatment Trial" \
    --study-id "DEPR-2025-001" \
    --admin-password "SecurePassword123!" \
    --domain trial.example.org \
    --instance-type t3.medium
  ```
- [ ] Script completes successfully (look for green checkmarks)
- [ ] Note the output values:
  - [ ] Instance ID: `i-xxxxxxxxx`
  - [ ] Public IP address: `xx.xxx.xxx.xxx`
  - [ ] Security Group ID: `sg-xxxxxxxxx`
  - [ ] Key pair filename: `zzedc-XXXXXXX.pem`

### Verify AWS Resources Created
- [ ] EC2 instance appears in AWS Console
- [ ] Instance status shows "running" (2/2 checks passing)
- [ ] Security group shows 3 rules (HTTP, HTTPS, SSH)
- [ ] VPC and subnet allocation correct
- [ ] Elastic IP assigned (if configured)

### SSH Access Verification
- [ ] Key pair file exists locally: `~/.ssh/zzedc-*.pem`
- [ ] Key pair has correct permissions: `ls -la ~/.ssh/zzedc-*.pem` shows 400
- [ ] SSH connection succeeds:
  ```bash
  ssh -i ~/.ssh/zzedc-XXXXXXX.pem ubuntu@<PUBLIC_IP>
  ```
- [ ] Connected to Ubuntu 24.04 LTS instance confirmed

---

## Instance Initialization Phase

### Docker and Dependencies Installation
- [ ] SSH into instance as `ubuntu` user
- [ ] Check Docker installed: `docker --version`
- [ ] Check Docker Compose installed: `docker-compose --version`
- [ ] Verify Docker daemon running: `docker ps`
- [ ] Verify permissions (no sudo required): confirmed
- [ ] Check system packages updated: logs show apt-get upgrade completed

### Application Directory Setup
- [ ] Application directory exists: `/opt/zzedc/`
- [ ] Data volume exists: `/opt/zzedc/data/`
- [ ] Logs volume exists: `/opt/zzedc/logs/`
- [ ] Backups volume exists: `/opt/zzedc/backups/`
- [ ] Configuration directory exists: `/opt/zzedc/config/`

### Docker Image Build
- [ ] Navigate to application directory: `cd /opt/zzedc`
- [ ] Caddyfile exists and edited with domain name
  - [ ] Search and replace `CADDY_DOMAIN` with actual domain
  - [ ] Caddy config syntax validated (no errors)
- [ ] Build Docker image: `docker-compose build`
  - [ ] Build completes without errors (watch for final "Successfully tagged")
  - [ ] Image size reasonable (~1.5-2GB including R)

### Docker Container Startup
- [ ] Start containers: `docker-compose up -d`
- [ ] Verify running: `docker-compose ps`
  - [ ] `zzedc-caddy` container running
  - [ ] `zzedc-app` container running
  - [ ] Both status shows "Up"

### Health Checks
- [ ] Caddy container logs show no errors: `docker-compose logs caddy | head -20`
- [ ] Shiny container logs show initialization: `docker-compose logs zzedc | head -30`
- [ ] Port 3838 responsive: `curl http://localhost:3838/` (from instance)
- [ ] Container health check passing: `docker-compose ps` shows healthy status

---

## DNS and HTTPS Configuration Phase

### Domain Name Resolution
- [ ] Log into domain registrar
- [ ] Add A record pointing domain to instance Public IP
  - [ ] Record type: A
  - [ ] Hostname: `trial.example.org` (or your domain)
  - [ ] Value: `<PUBLIC_IP_ADDRESS>`
  - [ ] TTL: 3600 or default
- [ ] Verify DNS propagation (may take up to 24 hours):
  ```bash
  nslookup trial.example.org
  # Should return the instance's public IP
  ```
- [ ] DNS resolution confirmed from multiple locations

### HTTPS Certificate and Caddy Configuration
- [ ] Domain is publicly accessible: `curl https://trial.example.org/` (may initially fail, that's ok)
- [ ] Check Caddy logs for certificate generation:
  ```bash
  docker-compose logs caddy | grep "certificate"
  ```
- [ ] Let's Encrypt certificate generated automatically
- [ ] Caddy logs show certificate as valid for domain
- [ ] HTTPS access working: `curl https://trial.example.org/` (eventually succeeds)

### Security Verification
- [ ] SSL/TLS certificate valid: check in browser
  - [ ] Green padlock visible
  - [ ] Certificate issuer: Let's Encrypt or ZeroSSL
  - [ ] Domain matches
  - [ ] No "untrusted" warnings
- [ ] HSTS header present: `curl -I https://trial.example.org/ | grep Strict`
- [ ] Security headers configured: X-Frame-Options, X-Content-Type-Options

---

## Application Configuration Phase

### First-Time Access
- [ ] Access application via HTTPS: `https://trial.example.org`
- [ ] Application loads without errors
- [ ] Login page displays (or setup page if first-time)

### Database Initialization
- [ ] Database file created: `/opt/zzedc/data/zzedc.db` exists
- [ ] Database has proper size (not 0 bytes)
- [ ] Configuration file created: `/opt/zzedc/config/config.yml`
- [ ] Configuration shows study name and settings

### Admin Login
- [ ] Login with credentials:
  - [ ] Username: `admin`
  - [ ] Password: (as provided during setup)
- [ ] Login successful, redirected to dashboard
- [ ] Dashboard displays study information
- [ ] Admin panel accessible

### Role Verification
- [ ] Admin user has "Admin" role confirmed
- [ ] User management page accessible
- [ ] Settings page accessible
- [ ] Backup/restore page accessible
- [ ] Audit log viewer accessible

---

## Operational Readiness Phase

### Data Persistence Verification
- [ ] Create test data entry via web interface
- [ ] Restart container: `docker-compose restart zzedc`
- [ ] Data still present after restart
- [ ] Confirms: database is persisted on volume, not lost on restart

### Backup Configuration
- [ ] Backup location accessible: `/opt/zzedc/backups/`
- [ ] Test backup creation from web interface
- [ ] Backup file created with reasonable size
- [ ] Backup can be manually copied to secure storage
- [ ] Document backup procedure for team

### Logging Verification
- [ ] Application logs written: `/opt/zzedc/logs/` directory has files
- [ ] Caddy access logs present: `/opt/zzedc/logs/caddy-access.log`
- [ ] Log rotation configured (prevents disk space issues)
- [ ] Log files have recent timestamps

### Performance Baseline
- [ ] Application response time reasonable (<2 seconds for typical pages)
- [ ] Database queries responsive
- [ ] No memory leaks evident: `docker stats zzedc` shows stable memory
- [ ] CPU usage normal (spikes during operations, returns to baseline)

### Monitoring and Alerting (Optional)
- [ ] Consider CloudWatch agent installation for AWS monitoring
- [ ] Set up alerts for:
  - [ ] EC2 instance status checks
  - [ ] Disk space usage on instance
  - [ ] Memory usage spikes
  - [ ] Application crashes

---

## Documentation and Handoff Phase

### Documentation Completion
- [ ] Deployment summary document created (from aws_setup.sh output)
- [ ] Instance ID, Public IP, security group recorded
- [ ] Key pair location documented: `~/.ssh/zzedc-XXXXXXX.pem`
- [ ] Domain name and certificate details recorded
- [ ] Admin credentials stored securely (not in email, use password manager)

### Team Communication
- [ ] Investigator notified of deployment completion
- [ ] Investigator provided with:
  - [ ] HTTPS URL for accessing application
  - [ ] Admin username and temporary password
  - [ ] Instructions for first login
  - [ ] Link to user documentation
- [ ] IT support contact information provided
- [ ] Issue escalation procedure documented

### Troubleshooting Guide Review
- [ ] IT team familiarized with troubleshooting guide
- [ ] Common issues documented and solutions reviewed:
  - [ ] Container fails to start
  - [ ] HTTPS certificate errors
  - [ ] Database connection errors
  - [ ] Shiny application crashes
- [ ] Escalation procedure documented (when to contact support)

### Disaster Recovery
- [ ] Backup strategy documented
- [ ] How to backup data manually confirmed
- [ ] How to restore from backup confirmed
- [ ] How to migrate to new instance if needed
- [ ] Data export procedure documented (for worst-case scenario)

---

## Post-Deployment Verification (24 hours)

### System Stability Check
- [ ] Application has been running continuously for 24 hours
- [ ] No unexpected restarts observed in logs
- [ ] Containers in healthy state: `docker-compose ps`
- [ ] Disk space usage reasonable
- [ ] CPU and memory usage stable

### User Acceptance Testing
- [ ] Investigator successfully logged in
- [ ] Investigator completed test data entry
- [ ] Investigator accessed reports and exports
- [ ] Investigator confirmed functionality meets requirements
- [ ] Any issues identified and resolved

### Certificate Renewal Verification
- [ ] Certificate auto-renewal will occur in 60 days
- [ ] Caddy automatic renewal configuration confirmed
- [ ] Calendar reminder set to verify renewal in 30 days
- [ ] No manual intervention required (Caddy handles renewal)

---

## Ongoing Maintenance

### Weekly Checks
- [ ] Check container logs for errors: `docker-compose logs --since 7 days`
- [ ] Verify application still accessible: `curl -I https://trial.example.org`
- [ ] Check disk usage: `df -h /opt/zzedc/`
- [ ] Monitor CPU/memory: `docker stats zzedc`

### Monthly Checks
- [ ] Review access logs for unusual activity
- [ ] Test backup/restore procedure
- [ ] Update OS packages: `apt-get update && apt-get upgrade`
- [ ] Update Docker image if new ZZedc version available

### Quarterly Reviews
- [ ] Certificate expiration check (should renew automatically)
- [ ] Security group rules review
- [ ] Instance size adequacy for data volume
- [ ] Cost optimization review (instance right-sizing)

### Annual Audit
- [ ] Complete security audit
- [ ] Compliance review (GDPR, CFR Part 11)
- [ ] Disaster recovery drill (practice restore)
- [ ] Data archival and retention review

---

## Rollback Plan (If Needed)

In case of critical issues during deployment:

1. **Stop everything:**
   ```bash
   docker-compose down
   ```

2. **Preserve data:**
   ```bash
   cp -r /opt/zzedc/data /opt/zzedc/data.backup
   ```

3. **Terminate EC2 instance:**
   ```bash
   aws ec2 terminate-instances --instance-ids i-xxxxxxx --region us-west-2
   ```

4. **Delete security group:**
   ```bash
   aws ec2 delete-security-group --group-id sg-xxxxxxx --region us-west-2
   ```

5. **Release Elastic IP (if used)**

6. **Data recovery:** Data backed up at `/opt/zzedc/data.backup` if copied before termination

---

## Sign-Off

- [ ] Deployment Completed By: _________________
- [ ] Date: _________________
- [ ] Verified By: _________________
- [ ] Date: _________________
- [ ] Investigator Acceptance: _________________
- [ ] Date: _________________

**Notes:**
```
[Space for any special notes or deviations from standard process]
```

---

## Appendix: Quick Reference Commands

### Common Operational Commands
```bash
# Check container status
docker-compose ps

# View recent logs
docker-compose logs --tail=50 zzedc

# Restart application
docker-compose restart zzedc

# Stop everything
docker-compose stop

# Start everything
docker-compose start

# Rebuild from source
docker-compose build

# Clean rebuild
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Access container shell
docker-compose exec zzedc bash

# Monitor resources
docker stats zzedc

# Disk usage
du -sh /opt/zzedc/*
```

### Backup and Restore
```bash
# Create manual backup
docker-compose exec zzedc tar -czf /tmp/zzedc-backup-$(date +%Y%m%d).tar.gz /app/data/

# Copy backup locally
docker-compose cp zzedc:/tmp/zzedc-backup-*.tar.gz ./backups/

# Restore from backup (if needed)
docker-compose exec zzedc tar -xzf /tmp/backup.tar.gz -C /
```

### Monitoring and Troubleshooting
```bash
# Check certificate status
docker-compose logs caddy | grep -i "certificate"

# Test DNS resolution
nslookup trial.example.org

# Test HTTPS connection
curl -I https://trial.example.org/

# Monitor real-time activity
docker-compose exec zzedc tail -f /app/logs/app.log
```

---

**For additional support, see IT_STAFF_TROUBLESHOOTING.md**

