# ZZedc Deployment Troubleshooting Guide
## For IT Staff, Cloud Administrators, and DevOps Engineers

**Document Version:** 1.0
**Last Updated:** December 2025
**Quick Links:** [Deployment Checklist](IT_STAFF_DEPLOYMENT_CHECKLIST.md) | [AWS Deployment Guide](AWS_DEPLOYMENT_GUIDE.md)

---

## Table of Contents

1. [Pre-Deployment Issues](#pre-deployment-issues)
2. [AWS Infrastructure Issues](#aws-infrastructure-issues)
3. [Docker and Container Issues](#docker-and-container-issues)
4. [HTTPS and Caddy Issues](#https-and-caddy-issues)
5. [Application and Database Issues](#application-and-database-issues)
6. [Performance Issues](#performance-issues)
7. [Disaster Recovery](#disaster-recovery)
8. [Getting Help](#getting-help)

---

## Pre-Deployment Issues

### Problem: AWS CLI not found
**Symptoms:** `aws: command not found` or `aws: No such file or directory`

**Diagnosis:**
```bash
which aws
aws --version
```

**Solution:**
1. Install AWS CLI: https://aws.amazon.com/cli/
2. Verify installation: `aws --version` should show version 2.x or higher
3. Configure credentials:
   ```bash
   aws configure
   # Enter AWS Access Key ID
   # Enter AWS Secret Access Key
   # Enter default region (e.g., us-west-2)
   ```
4. Test access:
   ```bash
   aws sts get-caller-identity
   # Should show your AWS account info
   ```

---

### Problem: AWS credentials not configured
**Symptoms:** `InvalidSignatureException` or `UnauthorizedOperation` errors

**Diagnosis:**
```bash
aws sts get-caller-identity
# If this fails, credentials are not configured
```

**Solution:**
1. Run AWS configuration: `aws configure`
2. Provide valid AWS Access Key and Secret Access Key
3. Test again: `aws sts get-caller-identity`
4. If still failing, check:
   - [ ] Credentials file exists: `~/.aws/credentials`
   - [ ] Config file exists: `~/.aws/config`
   - [ ] Permissions are correct: `chmod 600 ~/.aws/credentials`

---

### Problem: Insufficient AWS IAM permissions
**Symptoms:** `UnauthorizedOperation: User: arn:aws... is not authorized to perform: ec2:RunInstances`

**Diagnosis:**
```bash
aws iam get-user
aws iam list-attached-user-policies --user-name <YOUR_USERNAME>
```

**Solution:**
1. Contact AWS account administrator
2. Ensure user/role has these permissions:
   - `ec2:RunInstances`
   - `ec2:DescribeInstances`
   - `ec2:CreateSecurityGroup`
   - `ec2:AuthorizeSecurityGroupIngress`
   - `ec2:DescribeKeyPairs`
   - `ec2:CreateKeyPair`
   - `ec2:DescribeImages` (for finding AMI)
   - `ssm:GetParameter` (for SSM parameter store)
3. If using role: ensure role has EC2 and VPC permissions
4. Policy example: `AmazonEC2FullAccess` (for testing only)

---

### Problem: Bash script permission denied
**Symptoms:** `Permission denied` when running `./aws_setup.sh`

**Diagnosis:**
```bash
ls -la aws_setup.sh
# Should show: -rwxr-xr-x (executable)
```

**Solution:**
```bash
chmod +x aws_setup.sh
./aws_setup.sh --help  # Verify it works
```

---

## AWS Infrastructure Issues

### Problem: EC2 instance fails to launch
**Symptoms:** Script shows "Error" when trying to create instance, or instance terminates immediately

**Diagnosis:**
```bash
# Check recent instance termination reasons
aws ec2 describe-instances --region us-west-2 \
  --filters Name=instance-state-name,Values=terminated \
  --query 'Reservations[].Instances[].[InstanceId,StateTransitionReason]'
```

**Solution:**

1. **Instance type not available in region:**
   - Try different instance type: `--instance-type t3.small` or `t3.large`
   - Or different region: `--region us-east-1`

2. **Insufficient capacity:**
   - AWS region at capacity, try different region
   - Wait a few minutes and retry

3. **Invalid AMI for region:**
   - Ubuntu 24.04 LTS might not be available in your region
   - Check available AMIs:
     ```bash
     aws ec2 describe-images --owners 099720109477 \
       --region us-west-2 \
       --filters "Name=name,Values=ubuntu*24.04*" \
       --query 'Images[].Name' | head -10
     ```

4. **VPC/Subnet issues:**
   - Verify default VPC exists: `aws ec2 describe-vpcs --region us-west-2`
   - Verify subnet exists: `aws ec2 describe-subnets --region us-west-2`

---

### Problem: Cannot SSH to instance
**Symptoms:** `ssh: Permission denied (publickey)` or `Connection timed out`

**Diagnosis:**
```bash
# Check instance is running
aws ec2 describe-instances --instance-ids i-xxxxxxx \
  --region us-west-2 --query 'Reservations[0].Instances[0].State.Name'

# Check public IP assigned
aws ec2 describe-instances --instance-ids i-xxxxxxx \
  --region us-west-2 --query 'Reservations[0].Instances[0].PublicIpAddress'

# Check security group allows port 22
aws ec2 describe-security-groups --group-ids sg-xxxxxxx \
  --region us-west-2 \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

**Solution:**

1. **Instance not running:**
   ```bash
   aws ec2 start-instances --instance-ids i-xxxxxxx --region us-west-2
   sleep 30  # Wait for startup
   ```

2. **No public IP assigned:**
   - Allocate Elastic IP: `aws ec2 allocate-address --domain vpc --region us-west-2`
   - Associate with instance: `aws ec2 associate-address --instance-id i-xxxxxxx --allocation-id eipalloc-xxxxx`

3. **Key pair permission issues:**
   ```bash
   chmod 400 ~/.ssh/zzedc-XXXXXXX.pem
   ```

4. **Wrong SSH user:**
   - Ubuntu instances use user: `ubuntu` (not root, ec2-user, or other)
   ```bash
   ssh -i ~/.ssh/zzedc-XXXXXXX.pem ubuntu@PUBLIC_IP
   ```

5. **Security group not allowing SSH:**
   ```bash
   aws ec2 authorize-security-group-ingress \
     --group-id sg-xxxxxxx \
     --protocol tcp --port 22 \
     --cidr 0.0.0.0/0 \
     --region us-west-2
   ```

---

### Problem: Security group rules not applied
**Symptoms:** Can't connect via HTTPS (443) or HTTP (80) even though security group created

**Diagnosis:**
```bash
aws ec2 describe-security-groups --group-ids sg-xxxxxxx \
  --region us-west-2 \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,ToPort,IpProtocol,IpRanges[*].CidrIp]'
```

**Solution:**

1. **Verify rules exist:** The output should show ports 22, 80, and 443
2. **If missing, add them:**
   ```bash
   # HTTPS
   aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxx \
     --protocol tcp --port 443 --cidr 0.0.0.0/0 --region us-west-2

   # HTTP
   aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxx \
     --protocol tcp --port 80 --cidr 0.0.0.0/0 --region us-west-2

   # SSH
   aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxx \
     --protocol tcp --port 22 --cidr 0.0.0.0/0 --region us-west-2
   ```

---

## Docker and Container Issues

### Problem: Docker not installed or not running
**Symptoms:** `docker: command not found` or `Cannot connect to Docker daemon`

**Diagnosis:**
```bash
docker --version
docker ps
systemctl status docker
```

**Solution:**
1. Check if Docker is installed:
   ```bash
   docker --version  # If not found, Docker not installed
   ```

2. Install Docker (on Ubuntu 24.04):
   ```bash
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   ```

3. Start Docker daemon:
   ```bash
   sudo systemctl start docker
   sudo systemctl enable docker  # Enable on boot
   ```

4. Add user to docker group (avoid needing sudo):
   ```bash
   sudo usermod -aG docker ubuntu
   # Log out and back in for this to take effect
   ```

---

### Problem: Docker Compose not installed
**Symptoms:** `docker-compose: command not found`

**Diagnosis:**
```bash
docker-compose --version
```

**Solution:**
```bash
# Install latest Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify
docker-compose --version
```

---

### Problem: Container fails to start
**Symptoms:** `docker-compose up -d` shows containers but `docker-compose ps` shows "Exited"

**Diagnosis:**
```bash
docker-compose ps  # Shows status
docker-compose logs zzedc  # Shows last 100 lines of logs
docker-compose logs zzedc --tail=200  # More lines
```

**Solution:**

1. **Check Shiny application logs:**
   ```bash
   docker-compose logs zzedc | tail -50
   # Look for R errors, missing packages, etc.
   ```

2. **If package missing:**
   ```bash
   docker-compose exec zzedc R
   > install.packages("missing-package-name")
   > q()
   ```

3. **If configuration issue:**
   - Check config.yml exists and is valid YAML
   - Verify environment variables are set correctly
   ```bash
   docker-compose exec zzedc env | grep ZZEDC
   ```

4. **Rebuild container:**
   ```bash
   docker-compose down
   docker-compose build --no-cache
   docker-compose up -d
   ```

---

### Problem: Out of disk space in Docker
**Symptoms:** `No space left on device` errors, containers won't start

**Diagnosis:**
```bash
df -h /opt/zzedc  # Show disk usage
docker system df   # Show Docker storage usage
```

**Solution:**

1. **Check what's using space:**
   ```bash
   du -sh /opt/zzedc/*
   du -sh /opt/zzedc/data/*
   ```

2. **Clean up Docker:**
   ```bash
   docker system prune -a  # WARNING: Removes unused images
   docker volume prune      # WARNING: Removes unused volumes
   ```

3. **Archive old data:**
   ```bash
   # Backup data
   tar -czf /tmp/zzedc-data-$(date +%Y%m%d).tar.gz /opt/zzedc/data/

   # Copy to external storage
   scp /tmp/zzedc-data-*.tar.gz <remote-server>:/backup/

   # Clear local space
   rm /opt/zzedc/data/*.db  # WARNING: only if backed up
   ```

---

### Problem: High CPU or memory usage
**Symptoms:** R process using 100% CPU, instance becomes unresponsive, or low memory

**Diagnosis:**
```bash
docker stats zzedc  # Real-time resource usage
docker stats zzedc --no-stream  # Single snapshot

# Top processes in container
docker-compose exec zzedc top
```

**Solution:**

1. **Check for long-running operations:**
   ```bash
   docker-compose logs zzedc | grep -i "error\|timeout\|long"
   ```

2. **Restart application:**
   ```bash
   docker-compose restart zzedc
   sleep 10
   docker stats zzedc  # Check if normal now
   ```

3. **Upgrade instance (if persistent):**
   - Stop instance
   - Change instance type to larger (e.g., t3.medium → t3.large)
   - Start instance

---

## HTTPS and Caddy Issues

### Problem: Caddy container not starting
**Symptoms:** `docker-compose ps` shows Caddy exited, or can't access HTTPS

**Diagnosis:**
```bash
docker-compose logs caddy | tail -50
# Look for Caddyfile syntax errors
```

**Solution:**

1. **Check Caddyfile syntax:**
   ```bash
   docker run --rm -v "$(pwd):/etc/caddy" caddy:latest \
     caddy validate --config /etc/caddy/Caddyfile
   ```

2. **Common Caddyfile errors:**
   - Missing domain name (should be your actual domain, not `DOMAIN_NAME`)
   - Indentation issues (use spaces, not tabs)
   - Missing braces or commas

3. **Fix Caddyfile:**
   ```bash
   # Edit the file
   nano /opt/zzedc/Caddyfile

   # Replace placeholder domain
   sed -i 's/DOMAIN_NAME/trial.example.org/g' /opt/zzedc/Caddyfile

   # Restart Caddy
   docker-compose restart caddy
   ```

---

### Problem: HTTPS certificate not issued
**Symptoms:** `curl https://trial.example.org` shows "untrusted certificate" or "can't connect"

**Diagnosis:**
```bash
# Check Caddy logs for certificate generation
docker-compose logs caddy | grep -i "certificate\|acme\|tls"

# Check if domain resolves
nslookup trial.example.org

# Test HTTP access first (should redirect to HTTPS)
curl -I http://trial.example.org
```

**Solution:**

1. **Verify DNS is working:**
   ```bash
   nslookup trial.example.org
   # Should show your instance's public IP

   # If not working, wait for DNS propagation (up to 24 hours)
   # Or check domain registrar's DNS settings
   ```

2. **Check Caddy can reach internet:**
   ```bash
   docker-compose exec caddy curl -I https://www.google.com
   # If fails, instance may not have internet access
   ```

3. **Check firewall allows port 80/443:**
   ```bash
   # From outside instance
   nmap -p 80,443 <PUBLIC_IP>

   # Or simple curl
   curl -I http://<PUBLIC_IP>
   curl -I https://<PUBLIC_IP>
   ```

4. **If still failing, force certificate renewal:**
   ```bash
   docker-compose exec caddy caddy reload --config /etc/caddy/Caddyfile
   docker-compose logs caddy | tail -30  # Check for success
   ```

5. **Use self-signed cert temporarily (testing only):**
   ```bash
   # Edit Caddyfile to use self-signed
   # Add "tls internal" to the site block
   # This is NOT recommended for production
   ```

---

### Problem: Certificate expires or renewal fails
**Symptoms:** Browser shows "certificate expired" or "untrusted"

**Diagnosis:**
```bash
# Check certificate validity
curl -I https://trial.example.org -w "\nCert expires: %{ssl_verify_result}\n"

# Check Caddy logs
docker-compose logs caddy | grep -i "expire\|renew"
```

**Solution:**

1. **Caddy renews automatically** (60 days before expiration)
   - No action needed in normal cases
   - Renewal happens silently in background

2. **If renewal failed, check these:**
   - Domain still resolves correctly: `nslookup trial.example.org`
   - Caddy container is running: `docker-compose ps caddy`
   - Port 80 still accessible: `curl -I http://trial.example.org`

3. **Force manual renewal:**
   ```bash
   docker-compose down
   docker volume rm zzedc_caddy-data  # WARNING: removes all certificates
   docker-compose up -d
   sleep 30
   docker-compose logs caddy | grep -i "certificate issued"
   ```

---

### Problem: Mixed content warnings (HTTPS with HTTP resources)
**Symptoms:** Browser console shows "mixed content blocked" warnings

**Diagnosis:**
```bash
# Check browser console for blocked resource URLs
# Most likely Shiny resources being loaded over HTTP
```

**Solution:**

This is usually handled automatically by Caddy's reverse proxy, but if it persists:

1. **Check Caddyfile has header configuration:**
   ```
   header_up X-Forwarded-Proto https
   header_up X-Forwarded-Host {host}
   ```

2. **Check Shiny app is using relative URLs** (not hardcoded http://)

3. **Restart containers:**
   ```bash
   docker-compose restart
   ```

---

## Application and Database Issues

### Problem: Login fails with all credentials
**Symptoms:** Admin login fails, "Invalid username or password"

**Diagnosis:**
```bash
# Check if database exists
docker-compose exec zzedc ls -la /app/data/zzedc.db

# Check database has admin user
docker-compose exec zzedc sqlite3 /app/data/zzedc.db ".tables"
docker-compose exec zzedc sqlite3 /app/data/zzedc.db "SELECT username FROM users LIMIT 5;"
```

**Solution:**

1. **If database doesn't exist:**
   - Initialization failed
   - Check initialization logs:
     ```bash
     docker-compose logs zzedc | grep -i "init\|database\|error"
     ```

2. **If database exists but wrong credentials:**
   - Admin password was mistyped during setup
   - Reset with SQL (if you have direct access):
     ```bash
     docker-compose exec zzedc sqlite3 /app/data/zzedc.db
     sqlite> DELETE FROM users WHERE username='admin';
     sqlite> .exit
     ```
   - Then reinitialize application

3. **If initialization error:**
   - Check config.yml is valid YAML:
     ```bash
     docker-compose exec zzedc cat /app/config.yml
     ```
   - Check password meets requirements (8+ chars, mixed types)
   - Re-run initialization:
     ```bash
     docker-compose restart zzedc
     # Check logs
     docker-compose logs zzedc | tail -50
     ```

---

### Problem: Data not persisting after restart
**Symptoms:** Data entered disappears after `docker-compose restart`

**Diagnosis:**
```bash
# Check volume mounts
docker-compose exec zzedc mount | grep data

# Check where database actually is
docker-compose exec zzedc ls -la /app/data/

# Check docker-compose.yml volume configuration
cat docker-compose.yml | grep -A 5 "volumes:"
```

**Solution:**

1. **Verify volume mounting in docker-compose.yml:**
   ```yaml
   zzedc:
     volumes:
       - ./data:/app/data  # This line is critical
   ```

2. **Verify local directory has proper permissions:**
   ```bash
   ls -la /opt/zzedc/data/
   # Should be readable/writable by container
   ```

3. **Recreate volume if corrupted:**
   ```bash
   docker-compose down
   mv /opt/zzedc/data /opt/zzedc/data.backup
   mkdir -p /opt/zzedc/data
   docker-compose up -d
   # Data will be fresh, old data in .backup
   ```

---

### Problem: Database corruption
**Symptoms:** `database disk image is malformed` errors, application won't load

**Diagnosis:**
```bash
docker-compose exec zzedc sqlite3 /app/data/zzedc.db "PRAGMA integrity_check;"
# Should say "ok" if not corrupt
```

**Solution:**

1. **Restore from backup:**
   ```bash
   # Stop app
   docker-compose down

   # Restore from backup (if you have one)
   cp /opt/zzedc/backups/zzedc.db.backup /opt/zzedc/data/zzedc.db

   # Restart
   docker-compose up -d
   ```

2. **If no backup, reinitialize:**
   ```bash
   # WARNING: This will lose all data
   docker-compose down
   rm /opt/zzedc/data/zzedc.db
   docker-compose up -d
   # App will reinitialize with empty database
   ```

---

## Performance Issues

### Problem: Application is slow (pages take >5 seconds to load)
**Symptoms:** Users report slow response times, long delays

**Diagnosis:**
```bash
# Check application logs for slow queries
docker-compose logs zzedc | grep -i "time\|slow\|took"

# Check R process resource usage
docker stats zzedc

# Check network latency to instance
ping <PUBLIC_IP>
curl -w "@curl-format.txt" -o /dev/null -s https://trial.example.org/
```

**Solution:**

1. **Database optimization:**
   - Backup database
   - Restart container to clear caches
   ```bash
   docker-compose restart zzedc
   ```

2. **Check for large data loads:**
   ```bash
   # Check database size
   docker-compose exec zzedc du -sh /app/data/zzedc.db
   # If > 500MB, data may be large for t3.small instance
   ```

3. **Upgrade instance if needed:**
   - Switch from t3.small to t3.medium or t3.large
   - See AWS documentation for instance type performance

4. **Check network from user's location:**
   - Geographic distance may cause latency
   - Consider CDN or multi-region deployment (advanced)

---

### Problem: High bandwidth usage
**Symptoms:** Unexpected AWS data transfer charges

**Diagnosis:**
```bash
# Check instance network metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkOut \
  --dimensions Name=InstanceId,Value=i-xxxxxxx \
  --start-time 2025-01-01T00:00:00Z \
  --end-time 2025-01-08T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

**Solution:**

1. **Check for data exports:**
   - Large data exports consume bandwidth
   - Limit export frequency or size

2. **Enable compression in Caddy:**
   - Already configured in provided Caddyfile
   - Verify: `docker-compose exec caddy caddy version`

3. **Monitor regularly:**
   ```bash
   # Set CloudWatch alarm for unusual data transfer
   aws cloudwatch put-metric-alarm \
     --alarm-name zzedc-high-bandwidth \
     --alarm-description "Alert if data transfer > 100GB/day" \
     --metric-name NetworkOut \
     --namespace AWS/EC2 \
     --statistic Sum \
     --period 86400 \
     --threshold 107374182400 \
     --comparison-operator GreaterThanThreshold
   ```

---

## Disaster Recovery

### Scenario: Instance suddenly terminates
**What happened:** EC2 instance is gone, or won't start

**Recovery steps:**

1. **Check instance status:**
   ```bash
   aws ec2 describe-instances --instance-ids i-xxxxxxx --region us-west-2
   # Look for State and StateTransitionReason
   ```

2. **Recover data if backup exists:**
   ```bash
   # If you have backup from S3 or local storage
   # Restore to new instance
   ```

3. **Launch new instance:**
   - Run aws_setup.sh again with same parameters
   - Point domain to new instance IP
   - Restore database from backup

---

### Scenario: Complete data loss
**What happened:** Database corrupted beyond repair, no backups

**Worst case recovery:**

1. **Application data is lost** (but application still works)
   - Clean database created on startup
   - Users can start fresh data entry

2. **No permanent data loss** if:
   - Users exported data before incident (have CSV/Excel)
   - Data was regularly backed up to S3

---

### Creating a backup (before disaster)
```bash
# On-demand backup
docker-compose exec zzedc tar -czf /tmp/zzedc-backup-$(date +%Y%m%d_%H%M%S).tar.gz /app/data/

# Copy to secure location
scp -i ~/.ssh/key.pem /tmp/zzedc-backup-*.tar.gz ubuntu@<BACKUP_SERVER>:/backups/

# Or to AWS S3
aws s3 cp /tmp/zzedc-backup-*.tar.gz s3://my-backup-bucket/zzedc/
```

---

### Restoring from backup
```bash
# Restore from local backup
docker-compose down
tar -xzf /tmp/zzedc-backup-20250101_120000.tar.gz -C /

# Verify
docker-compose up -d
docker-compose logs zzedc | head -20
```

---

## Getting Help

### Information to gather before contacting support

1. **Deployment details:**
   ```bash
   # Instance info
   aws ec2 describe-instances --instance-ids i-xxxxxxx --region us-west-2

   # Check script output was saved
   ls -la zzedc-deployment-*.txt

   # Detailed logs
   docker-compose logs --tail=200 > /tmp/zzedc-logs.txt
   ```

2. **System information:**
   ```bash
   # OS version
   cat /etc/os-release

   # Docker versions
   docker --version
   docker-compose --version

   # Caddy version
   docker-compose exec caddy caddy version
   ```

3. **Application information:**
   ```bash
   # R version in container
   docker-compose exec zzedc R --version

   # ZZedc version
   docker-compose exec zzedc R -e "packageVersion('zzedc')"

   # Configuration
   docker-compose exec zzedc cat /app/config.yml
   ```

### Contact information

**For ZZedc application issues:**
- Email: rgthomas@ucsd.edu
- GitHub: https://github.com/rgt47/zzedc
- Issues: https://github.com/rgt47/zzedc/issues

**For AWS deployment issues:**
- AWS Support Console: https://console.aws.amazon.com/support
- AWS Documentation: https://docs.aws.amazon.com/ec2/
- AWS Community Forums: https://forums.aws.amazon.com/

**For Docker issues:**
- Docker Documentation: https://docs.docker.com/
- Docker Community: https://community.docker.com/

---

## Quick Reference: Common Commands

```bash
# View recent logs
docker-compose logs --tail=50 zzedc
docker-compose logs caddy --tail=50

# Restart services
docker-compose restart zzedc
docker-compose restart caddy
docker-compose restart

# SSH into container
docker-compose exec zzedc bash
docker-compose exec caddy bash

# Check R packages
docker-compose exec zzedc R -e "installed.packages()[,3]"

# Manual database check
docker-compose exec zzedc sqlite3 /app/data/zzedc.db ".schema"

# System resources
docker stats zzedc
docker system df

# Network connectivity test
docker-compose exec zzedc curl -I https://www.google.com
docker-compose exec zzedc nslookup trial.example.org

# Caddy configuration test
docker run --rm -v "$(pwd):/etc/caddy" caddy:latest caddy validate --config /etc/caddy/Caddyfile
```

---

**Last Updated:** December 2025
**Version:** 1.0
**Feedback:** Please report issues at https://github.com/rgt47/zzedc/issues

