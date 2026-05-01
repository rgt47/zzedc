# ZZedc AWS Test Verification Checklist

Complete verification checklist for AWS deployment testing.

**Purpose**: Ensure all components of the AWS deployment are functioning correctly
**Audience**: QA Engineers, IT Staff, DevOps Teams
**Duration**: 10-15 minutes per test cycle

---

## Pre-Test Verification

### Environment Setup

- [ ] AWS CLI installed: `aws --version`
- [ ] AWS credentials configured: `aws sts get-caller-identity`
- [ ] AWS CLI version 2.x or later
- [ ] Default region set in AWS CLI config
- [ ] Sufficient AWS account permissions (EC2, security groups, key pairs)
- [ ] Local DNS resolution working: `nslookup google.com`
- [ ] SSH client available and functional
- [ ] curl utility available: `command -v curl`
- [ ] openssl utility available: `command -v openssl`
- [ ] Deployment script has execute permissions: `ls -la aws_test.sh`

### Deployment Files Present

- [ ] `aws_test.sh` exists and is executable
- [ ] `aws_setup.sh` exists and is executable
- [ ] `docker-compose.yml` exists and is readable
- [ ] `Dockerfile` exists and is readable
- [ ] `Caddyfile` exists and is readable
- [ ] `.env.template` exists and is readable
- [ ] `README.md` exists and is readable
- [ ] Documentation files present:
  - [ ] `IT_STAFF_DEPLOYMENT_CHECKLIST.md`
  - [ ] `IT_STAFF_TROUBLESHOOTING.md`
  - [ ] `AWS_DEPLOYMENT_GUIDE.md`

### Test Parameters

- [ ] Study name provided: ___________________
- [ ] Study ID provided: ___________________
- [ ] Admin password meets requirements (8+ chars): ___________
- [ ] Domain name is resolvable or will be configured: ___________________
- [ ] PI email address specified: ___________________
- [ ] AWS region selected: ___________________
- [ ] Instance type selected (default: t3.micro): ___________________

---

## Test Execution Phase

### Phase 1: Script Initialization

Start Time: ___________

```bash
cd deployment
./aws_test.sh \
  --region [REGION] \
  --study-name "[STUDY_NAME]" \
  --study-id "[STUDY_ID]" \
  --admin-password "[PASSWORD]" \
  --domain [DOMAIN_NAME]
```

- [ ] Script starts without errors
- [ ] Test phase numbers display (Phase 1, Phase 2, etc.)
- [ ] Color-coded output shows (✓, ✗, ℹ, ⚠)
- [ ] Script accepts all command-line arguments
- [ ] No immediate crashes or syntax errors

### Phase 2: Pre-Deployment Validation

**Expected**: All checks pass (5/5 ✓)

- [ ] AWS CLI installed check passes ✓
- [ ] AWS credentials configured check passes ✓
- [ ] openssl availability check passes ✓
- [ ] curl availability check passes ✓
- [ ] ssh availability check passes ✓
- [ ] aws_setup.sh file exists check passes ✓
- [ ] docker-compose.yml file exists check passes ✓
- [ ] Caddyfile file exists check passes ✓
- [ ] .env.template file exists check passes ✓

**Notes**: ___________________________________

### Phase 3: AWS Deployment Execution

**Expected Duration**: 5-10 minutes
**Expected Result**: EC2 instance launched with valid public IP

- [ ] Script outputs deployment start message
- [ ] "Creating new key pair" or "Using existing key pair" message appears
- [ ] Security group creation message appears: ✓
- [ ] Security group ID captured: sg-___________________
- [ ] Ubuntu 24.04 LTS AMI found: ami-___________________
- [ ] "Launching EC2 Instance" message appears
- [ ] Instance ID captured: i-___________________
- [ ] "Instance is running" message appears
- [ ] Public IP address captured: ___________________
- [ ] Private IP address captured: ___________________
- [ ] Key pair saved to local filesystem: `ls ~/.ssh/zzedc-*.pem`

**Instance Details**:
- Instance ID: ___________________
- Instance Type: ___________________
- Public IP: ___________________
- Private IP: ___________________
- Region: ___________________
- Key Pair Name: ___________________
- Security Group ID: ___________________

### Phase 4: Instance Readiness Testing

**Expected**: Instance status checks pass within 5-10 minutes

- [ ] Script outputs "Waiting for instance..." message
- [ ] Progress updates show attempt count
- [ ] Instance status changes from "pending" to "running"
- [ ] "Instance status checks passed" message appears ✓
- [ ] No errors or timeouts (if timeout occurs, see troubleshooting)

**Status Timeline**:
- Instance running at: ___________
- Status checks passed at: ___________
- Time to readiness: _____ minutes

### Phase 5: SSH Connectivity Testing

**Expected**: SSH connection successful or understandable timeout

- [ ] Script locates key pair file
- [ ] Key file path displayed correctly
- [ ] SSH connection attempt made
- [ ] **Either**:
  - [ ] SSH connection successful (✓), OR
  - [ ] SSH timeout is acceptable (instance initializing)
- [ ] SSH authentication method correct (key-based)

**SSH Details**:
- Key file: ~/.ssh/___________________
- SSH User: ubuntu
- SSH Command: `ssh -i [KEY] ubuntu@[IP]`

### Phase 6: HTTP/HTTPS Connectivity Testing

**Expected**: At least port 3838 responds (others may still be initializing)

- [ ] Script tests HTTP on port 80
- [ ] Script tests Shiny on port 3838
- [ ] At least one port responds successfully
- [ ] Port 3838 (Shiny) responsive: Yes / No / Not yet
- [ ] Port 80 (HTTP) responsive: Yes / No / Not yet
- [ ] Response codes documented in output

**Connectivity Results**:
- Port 80 status: ___________________
- Port 3838 status: ___________________
- HTTP response time: _____ ms

### Phase 7: DNS and Domain Testing

**Expected**: Domain resolves (if configured) or skipped appropriately

- [ ] DNS resolution check performed
- [ ] **Either**:
  - [ ] Domain resolves to instance IP ✓, OR
  - [ ] Domain not yet configured (acceptable), OR
  - [ ] DNS propagation pending (acceptable)
- [ ] Resolved IP matches instance public IP (if applicable)
- [ ] No DNS errors in output

**DNS Results**:
- Domain: ___________________
- Resolved to: ___________________
- Instance IP: ___________________
- Match: Yes / No / Pending

### Phase 8: Container Health Testing (SSH-based)

**Expected**: Docker installation verified via SSH (or SSH not available yet)

- [ ] Script attempts SSH into instance
- [ ] Docker installation check performed
- [ ] **Either**:
  - [ ] Docker confirmed installed ✓, OR
  - [ ] SSH not available yet (acceptable)
- [ ] No critical Docker errors shown

**Container Status**:
- Docker installed: Yes / No / Not verified
- Docker accessible via SSH: Yes / No / Not yet

### Phase 9: Database Verification (SSH-based)

**Expected**: Data directory exists and ready for use

- [ ] Script attempts SSH check for data directory
- [ ] **Either**:
  - [ ] Data directory confirmed at /opt/zzedc/data ✓, OR
  - [ ] SSH not available yet (acceptable)
- [ ] Directory path correct: /opt/zzedc/data
- [ ] No permission errors shown

**Database Status**:
- Data directory exists: Yes / No / Not verified
- Path: ___________________
- Permissions: ___________________

### Phase 10: Security Verification

**Expected**: All three security group rules present (22, 80, 443)

- [ ] Script queries security group rules
- [ ] SSH (port 22) rule present ✓
- [ ] HTTP (port 80) rule present ✓
- [ ] HTTPS (port 443) rule present ✓
- [ ] All rules allow inbound traffic (0.0.0.0/0)
- [ ] No extraneous rules blocking required ports

**Security Group Verification**:
- Port 22 (SSH): [ ] Present [ ] Missing [ ] Error checking
- Port 80 (HTTP): [ ] Present [ ] Missing [ ] Error checking
- Port 443 (HTTPS): [ ] Present [ ] Missing [ ] Error checking
- Group ID: ___________________
- Rules Status: ___________________

---

## Post-Test Verification

### Test Results Summary

- [ ] Test completed without script errors
- [ ] Results file created: `/tmp/zzedc_test_results_*.txt`
- [ ] Results file is readable and contains data
- [ ] Test completion timestamp recorded

**Results File**: ___________________

### Test Metrics

```
Tests Run:     _____ / 20
Tests Passed:  _____ / 20
Tests Failed:  _____
Success Rate:  _____ %
```

**Expected**:
- Minimum 15/20 tests passed (75% success rate)
- 0 critical failures
- Acceptable warnings/timeouts for "Not yet" items

### Cost Verification

- [ ] Estimated cost displayed (should be <$0.10)
- [ ] Cost estimate: $___________
- [ ] Instance type correct: ___________________
- [ ] Deployment duration recorded: _____ seconds
- [ ] AWS costs align with estimate

### Instance State After Test

- [ ] Instance still running (check AWS Console)
- [ ] Instance has public IP assigned
- [ ] Instance security group allows required ports
- [ ] Instance key pair matches local file
- [ ] Instance tags show study name and ID

**Instance Status Check**:
```bash
aws ec2 describe-instances --instance-ids [INSTANCE_ID] \
  --region [REGION] --query 'Reservations[0].Instances[0].[State.Name,PublicIpAddress]'
# Expected: running [PUBLIC_IP]
```

---

## Manual Post-Test Verification

### Phase 1: SSH Access Verification

```bash
# Set variables
INSTANCE_ID="[INSTANCE_ID_FROM_TEST]"
PUBLIC_IP="[PUBLIC_IP_FROM_TEST]"
KEY_FILE="$HOME/.ssh/[KEY_PAIR_NAME].pem"
REGION="[AWS_REGION]"

# Verify key file exists
ls -la "$KEY_FILE"
# Expected: -r--------  1  user  group  [size]  Date

# Test SSH connection
ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@"$PUBLIC_IP" "echo 'SSH successful'"
# Expected output: SSH successful
```

- [ ] Key file has correct permissions (400)
- [ ] Key file is readable by current user
- [ ] SSH connection succeeds
- [ ] Remote echo command executes
- [ ] No permission denied errors

### Phase 2: Docker Container Verification

```bash
# SSH into instance
ssh -i "$KEY_FILE" ubuntu@"$PUBLIC_IP"

# Inside instance:
docker ps
# Expected: Two containers running
# - zzedc-caddy (Caddy reverse proxy)
# - zzedc-app (R Shiny application)

docker compose -f /opt/zzedc/docker-compose.yml ps
```

- [ ] At least 2 containers listed
- [ ] Caddy container running: Yes / No / Status: _____
- [ ] ZZedc app container running: Yes / No / Status: _____
- [ ] Containers have been running for reasonable time
- [ ] No "restarting" or "exited" status

**Container Status**:
```
CONTAINER ID  IMAGE           STATUS
_________     zzedc-caddy     ___________
_________     zzedc-app       ___________
```

### Phase 3: Application Port Verification

```bash
# SSH into instance
ssh -i "$KEY_FILE" ubuntu@"$PUBLIC_IP"

# Test local connectivity
curl -I http://localhost:3838
# Expected: HTTP/1.1 200 OK (from Shiny)

curl -I http://localhost:80
# Expected: HTTP/1.1 307 (redirect to HTTPS)
```

- [ ] Shiny responds on port 3838: Yes / No
- [ ] HTTP responds on port 80: Yes / No
- [ ] Response codes documented above
- [ ] No connection refused errors

### Phase 4: Configuration File Verification

```bash
# SSH into instance
ssh -i "$KEY_FILE" ubuntu@"$PUBLIC_IP"

# Check configuration
test -f /opt/zzedc/.env && echo "ENV file exists"
test -f /opt/zzedc/Caddyfile && echo "Caddyfile exists"
test -f /opt/zzedc/docker-compose.yml && echo "docker-compose exists"

# View environment variables (don't expose passwords)
head -20 /opt/zzedc/.env | grep -v PASSWORD
```

- [ ] .env file exists: Yes / No
- [ ] .env file is readable
- [ ] STUDY_NAME variable set
- [ ] STUDY_ID variable set
- [ ] ZZEDC_SALT variable set (32-char hex)
- [ ] Caddyfile exists and contains domain
- [ ] docker-compose.yml exists and is valid

**Configuration Verification**:
- STUDY_NAME: ___________________
- STUDY_ID: ___________________
- ZZEDC_SALT length: _____ chars
- Domain in Caddyfile: ___________________

### Phase 5: Database Verification

```bash
# SSH into instance
ssh -i "$KEY_FILE" ubuntu@"$PUBLIC_IP"

# Check database files
ls -lah /opt/zzedc/data/

# Check database integrity (if sqlite3 available)
docker exec zzedc-app sqlite3 /app/data/zzedc.db "SELECT name FROM sqlite_master WHERE type='table';"
# Expected: List of tables (if initialized)
```

- [ ] Data directory exists: /opt/zzedc/data/
- [ ] Data directory is writable
- [ ] zzedc.db file exists (or will be created on first run)
- [ ] Directory size reasonable (<100MB)
- [ ] No permission errors

**Database Status**:
- Directory: ___________________
- Size: ___________ MB
- Tables: ___________________

### Phase 6: Log File Verification

```bash
# SSH into instance
ssh -i "$KEY_FILE" ubuntu@"$PUBLIC_IP"

# Check logs directory
ls -lah /opt/zzedc/logs/

# Check recent logs
tail -20 /opt/zzedc/logs/caddy.log
tail -20 /opt/zzedc/logs/caddy-access.log

# Check Docker logs
docker logs --tail 50 zzedc-caddy
docker logs --tail 50 zzedc-app
```

- [ ] Logs directory exists: /opt/zzedc/logs/
- [ ] caddy.log file exists
- [ ] caddy-access.log file exists
- [ ] Logs contain recent timestamps
- [ ] No critical error messages
- [ ] Docker containers log output is captured

**Log Sample** (last 3 lines):
```
___________________________________
___________________________________
___________________________________
```

### Phase 7: HTTPS Certificate Verification (if domain configured)

```bash
# After DNS propagation (24-48 hours), test:
curl -I https://[DOMAIN_NAME]
# Expected: HTTP/2 200 OK with certificate details

# Or via SSH to instance:
docker logs zzedc-caddy | grep -i certificate
# Expected: Certificate issued by Let's Encrypt or ZeroSSL
```

- [ ] Domain resolves to instance: Yes / No / Not yet
- [ ] HTTPS certificate obtained: Yes / No / Not yet
- [ ] Certificate issuer: Let's Encrypt / ZeroSSL / Other: _____
- [ ] Certificate valid date: ___________________
- [ ] Certificate expiration: ___________________

**Certificate Details** (after DNS ready):
- Status: ___________________
- Issuer: ___________________
- Valid From: ___________________
- Valid To: ___________________

---

## Cleanup and Resource Management

### Instance Preservation Decision

- [ ] **KEEP instance for further testing**: Document reason:
  ___________________________________________________________________

- [ ] **TERMINATE instance**: Proceed to cleanup below

### Manual Cleanup (if --skip-teardown used)

```bash
# Terminate instance
aws ec2 terminate-instances \
  --instance-ids [INSTANCE_ID] \
  --region [REGION]

# Wait for termination
aws ec2 wait instance-terminated \
  --instance-ids [INSTANCE_ID] \
  --region [REGION]

# Delete security group (5 minutes after instance terminates)
aws ec2 delete-security-group \
  --group-id [SECURITY_GROUP_ID] \
  --region [REGION]

# Delete key pair (optional, if not reusing)
aws ec2 delete-key-pair \
  --key-name [KEY_PAIR_NAME] \
  --region [REGION]

rm ~/.ssh/[KEY_PAIR_NAME].pem
```

- [ ] Termination command executed
- [ ] Waited for instance termination
- [ ] Security group deleted
- [ ] Key pair deleted (optional)
- [ ] Local key file deleted (optional)

### Cost Review

- [ ] Test duration: _____ minutes
- [ ] Instance type: t3.micro / other: _____
- [ ] Estimated cost: $___________
- [ ] Actual AWS billing checked
- [ ] Cost within budget: Yes / No / Unknown

---

## Test Result Summary

### Overall Result

- [ ] **PASS**: All critical tests passed, system ready for deployment
- [ ] **PASS WITH WARNINGS**: Minor issues noted, acceptable for testing
- [ ] **FAIL**: Critical failures, requires troubleshooting

### Critical Test Results Required for PASS

- [ ] Pre-deployment validation: 100%
- [ ] AWS deployment: Instance launched with valid IP
- [ ] Instance readiness: Status checks passed
- [ ] Security group: All 3 required ports open
- [ ] At least one application port responds (3838 or 80)

### Known Issues / Notes

___________________________________________________________________
___________________________________________________________________
___________________________________________________________________

### Recommendations

- [ ] Proceed to production deployment
- [ ] Investigate warnings further before production
- [ ] Repeat test after addressing failures
- [ ] Document any deviations from expected behavior
- [ ] Update deployment guides if changes needed

---

## Sign-Off

**Test Performed By**: ___________________
**Date**: ___________________
**Time**: ___________ to ___________
**Duration**: _____ minutes

**Test Result**: [ ] PASS [ ] PASS WITH WARNINGS [ ] FAIL

**Approval for Production Deployment**: [ ] Yes [ ] No [ ] Pending Review

**Approver Name**: ___________________
**Approver Signature**: ___________________
**Approval Date**: ___________________

---

## References

- AWS_TESTING_GUIDE.md - Complete testing guide
- AWS_DEPLOYMENT_GUIDE.md - Deployment procedures
- IT_STAFF_TROUBLESHOOTING.md - Issue resolution
- IT_STAFF_DEPLOYMENT_CHECKLIST.md - Production deployment steps

**For Support**:
- Email: rgthomas@ucsd.edu
- GitHub: https://github.com/rgt47/zzedc/issues

---

**Last Updated**: December 2025
**Version**: 1.0
**Status**: Production Ready
