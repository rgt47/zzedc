# ZZedc AWS Deployment Testing Guide

Complete guide for testing the ZZedc deployment pipeline on AWS.

**Status**: Ready for testing
**Target Infrastructure**: AWS EC2 + Docker + Caddy + R/Shiny
**Estimated Duration**: 15-20 minutes for full test cycle
**Cost Estimate**: ~$0.05-0.10 per test (t3.micro instance)

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Testing Phases](#testing-phases)
4. [Running Tests](#running-tests)
5. [Interpreting Results](#interpreting-results)
6. [Manual Testing](#manual-testing)
7. [Troubleshooting](#troubleshooting)
8. [Cost Management](#cost-management)

---

## Quick Start

**For experienced AWS users**, running the complete test takes one command:

```bash
cd deployment
./aws_test.sh \
  --region us-west-2 \
  --study-name "ZZedc Test Trial" \
  --study-id "TEST-2025-001" \
  --admin-password "TestPass123!" \
  --domain test.example.org
```

This will:
- Launch an EC2 instance
- Run the full deployment script
- Execute 20+ automated tests
- Terminate resources (unless `--keep-instance` is specified)
- Save results to `/tmp/zzedc_test_results_*.txt`

---

## Prerequisites

### Required Software

```bash
# Check AWS CLI
aws --version          # Should be v2.x or later
aws configure          # Verify credentials are set

# Check required utilities
command -v curl        # For HTTP testing
command -v ssh         # For instance access
command -v openssl     # For salt generation
command -v nslookup    # For DNS testing
```

### AWS Account Setup

1. **AWS Account**: Active AWS account with permissions to:
   - Launch EC2 instances
   - Create security groups
   - Create key pairs
   - View instance details

2. **AWS CLI Configuration**:
   ```bash
   aws configure
   # Enter: Access Key ID, Secret Access Key, Region, Output format

   # Verify configuration
   aws sts get-caller-identity
   ```

3. **Domain Name** (optional for basic testing):
   - Registered domain (or use a test subdomain)
   - Ability to update DNS records (for HTTPS testing)
   - Not required for initial instance launch

### System Requirements

- **OS**: macOS, Linux, or Windows (WSL2)
- **Disk Space**: 2 GB free (for logs and test artifacts)
- **Network**: Unrestricted outbound access to AWS
- **SSH Key**: SSH client with key pair support

---

## Testing Phases

The test script performs testing in 9 phases:

### Phase 1: Pre-Deployment Validation
- Verifies AWS CLI, credentials, and required tools
- Checks deployment files exist and are readable
- **Expected Result**: All checks pass

### Phase 2: AWS Deployment Execution
- Runs `aws_setup.sh` with test parameters
- Creates EC2 instance, security group, key pair
- Launches Docker containers
- **Expected Duration**: 5-10 minutes
- **Expected Result**: Instance running, IP address obtained

### Phase 3: Instance Readiness Testing
- Polls EC2 instance status checks
- Waits for instance to be fully initialized
- **Expected Duration**: 2-5 minutes
- **Expected Result**: Instance status shows "ok"

### Phase 4: SSH Connectivity Testing
- Attempts SSH connection to instance
- Verifies security group allows SSH
- **Expected Result**: SSH connection successful

### Phase 5: HTTP/HTTPS Connectivity Testing
- Tests HTTP access to instance (port 80)
- Tests Shiny application (port 3838)
- **Expected Result**: Ports responding (after initialization)

### Phase 6: DNS and Domain Testing
- Verifies domain resolves to instance IP
- Checks DNS propagation
- **Expected Result**: Domain points to correct IP

### Phase 7: Container Health Testing
- Verifies Docker is installed and running
- Checks container logs (via SSH)
- **Expected Result**: Docker and containers healthy

### Phase 8: Database Verification
- Checks database directory exists
- Verifies data persistence setup
- **Expected Result**: Database directory ready

### Phase 9: Security Verification
- Validates security group rules
- Checks ingress rules for ports 22, 80, 443
- **Expected Result**: All required ports open

---

## Running Tests

### Basic Test (Recommended for first time)

```bash
cd /path/to/zzedc/deployment

./aws_test.sh \
  --study-name "ZZedc Test Trial" \
  --study-id "TEST-2025-001" \
  --admin-password "TestPass123!" \
  --domain test.example.org
```

**Duration**: ~15 minutes
**Cost**: ~$0.05
**Resources Cleaned Up**: Yes (automatically)

### Full Test with Instance Inspection

```bash
./aws_test.sh \
  --region us-west-2 \
  --study-name "ZZedc Test Trial" \
  --study-id "TEST-2025-001" \
  --admin-password "TestPass123!" \
  --domain test.example.org \
  --keep-instance
```

**Duration**: ~15 minutes
**Cost**: Includes instance runtime after test
**Resources Cleaned Up**: No (instance remains for inspection)

After testing, you can SSH in:
```bash
ssh -i ~/.ssh/zzedc-[timestamp].pem ubuntu@[PUBLIC_IP]
```

### Test Without Cleanup (for Debugging)

```bash
./aws_test.sh \
  --study-name "ZZedc Test Trial" \
  --study-id "TEST-2025-001" \
  --admin-password "TestPass123!" \
  --domain test.example.org \
  --skip-teardown
```

**Use when**: You need to inspect resources or troubleshoot failures
**Remember**: You must manually clean up resources in AWS console

### Different AWS Region

```bash
./aws_test.sh \
  --region eu-west-1 \
  --study-name "ZZedc Test Trial" \
  --study-id "TEST-2025-001" \
  --admin-password "TestPass123!" \
  --domain test.example.org
```

---

## Interpreting Results

### Test Output

The test script provides real-time feedback with color coding:

```
✓ AWS CLI installed
✓ AWS credentials configured
✗ SSH connection successful
ℹ HTTP not responding yet (instance still initializing)
⚠ Domain does not resolve yet (DNS may not be configured)
```

**Symbols**:
- `✓` **Success**: Test passed
- `✗` **Failure**: Test failed (requires attention)
- `ℹ` **Info**: Expected delay (initialization in progress)
- `⚠` **Warning**: Potential issue (may resolve with time)

### Test Results File

Results are saved to a timestamped file:

```bash
cat /tmp/zzedc_test_results_1702000000.txt
```

Contents include:
- Test start/end time
- Pass/fail count and percentage
- Instance details (ID, IP, cost estimate)
- Detailed results for each test phase

### Success Criteria

**All tests pass** if:
- Pre-deployment validation: 5/5 ✓
- AWS deployment: Instance created with valid IP
- Instance readiness: Status checks pass
- Security group: Ports 22, 80, 443 open
- SSH connectivity: Connection succeeds or times out (not refused)

### Expected Warnings (Not Failures)

These are **normal** and don't indicate problems:

```
⚠ HTTP not responding yet (instance still initializing)
⚠ Shiny application not responding yet (still initializing)
⚠ Domain does not resolve yet (DNS may not be configured)
⚠ Instance status checks timed out (may still be initializing)
```

These typically resolve as Docker containers finish starting.

### Common Failures and Solutions

| Symptom | Cause | Solution |
|---------|-------|----------|
| `✗ AWS CLI installed` | CLI not in PATH | Install AWS CLI v2 |
| `✗ AWS credentials configured` | AWS credentials not set | Run `aws configure` |
| `✗ SSH connection failed` | Instance not ready | Wait 2-3 minutes, retry |
| `⚠ Domain does not resolve` | DNS not configured | Add A record to domain registrar |
| `⚠ HTTP not responding` | Docker still starting | Wait for Docker health check |

---

## Manual Testing

After automated tests complete, perform these manual checks:

### 1. SSH Into Instance

```bash
# Find the key file
ls ~/.ssh/zzedc-*.pem

# SSH in
ssh -i ~/.ssh/zzedc-[timestamp].pem ubuntu@[PUBLIC_IP]

# Inside instance, check Docker status
docker ps
docker logs zzedc-app
docker logs zzedc-caddy
```

### 2. Test Application via HTTP

```bash
# From your local machine
curl -I http://[PUBLIC_IP]

# Expected response:
# HTTP/1.1 307 Temporary Redirect
# Location: https://...
```

### 3. Test Shiny Application Port

```bash
curl -I http://[PUBLIC_IP]:3838

# Expected response:
# HTTP/1.1 200 OK
# (Shiny app is responding)
```

### 4. Verify Database Exists

```bash
# SSH into instance
ssh -i ~/.ssh/zzedc-[timestamp].pem ubuntu@[PUBLIC_IP]

# Check database file
ls -la /opt/zzedc/data/

# Should see: zzedc.db (or similar)
```

### 5. Test Configuration Files

```bash
# SSH into instance
ssh -i ~/.ssh/zzedc-[timestamp].pem ubuntu@[PUBLIC_IP]

# Check configuration
cat /opt/zzedc/.env

# Should show: STUDY_NAME, STUDY_ID, ADMIN_PASSWORD (masked), etc.
```

### 6. Monitor Docker Startup

```bash
# SSH into instance
ssh -i ~/.ssh/zzedc-[timestamp].pem ubuntu@[PUBLIC_IP]

# Follow Docker logs in real-time
docker-compose -f /opt/zzedc/docker-compose.yml logs -f

# Wait for message: "Launching ZZedc application"
# Then Ctrl+C to exit logs
```

### 7. HTTPS Certificate Generation (if domain configured)

```bash
# After DNS propagates (24-48 hours)
curl -I https://[DOMAIN_NAME]

# Should show:
# HTTP/2 200
# Date: ...
# (certificate information in browser)

# Check Caddy logs
ssh -i ~/.ssh/zzedc-[timestamp].pem ubuntu@[PUBLIC_IP] \
  docker logs zzedc-caddy | grep certificate
```

---

## Troubleshooting

### Issue: AWS deployment script hangs

**Symptoms**: Script stops at "Waiting for instance..." for more than 10 minutes

**Solutions**:
1. Check AWS console for instance launch errors
2. Verify security group was created
3. Check AWS API rate limits (see CloudTrail)
4. Retry with `--skip-teardown` and check logs

### Issue: SSH connection times out

**Symptoms**: "Connection timed out" when trying to SSH

**Solutions**:
1. Wait 2-3 more minutes for system to initialize
2. Verify key pair file exists: `ls ~/.ssh/zzedc-*.pem`
3. Check security group allows SSH on port 22
4. Verify instance has public IP assigned

### Issue: HTTP port not responding

**Symptoms**: `curl http://[IP]` hangs or refuses connection

**Solutions**:
1. SSH into instance and check Docker logs: `docker logs zzedc-caddy`
2. Verify port 80 is open in security group
3. Wait for container initialization to complete
4. Check instance disk space: `df -h`

### Issue: Domain resolves to wrong IP

**Symptoms**: `nslookup [domain]` returns different IP than instance

**Solutions**:
1. Verify you updated the correct domain registrar account
2. Check DNS propagation time (up to 24 hours)
3. Use `nslookup` to check: `nslookup [domain] 8.8.8.8`
4. Verify A record points to instance public IP

### Issue: HTTPS certificate not generated

**Symptoms**: Browser shows "NET::ERR_CERT_AUTHORITY_INVALID"

**Solutions**:
1. Verify domain resolves to correct IP first
2. Check Caddy logs: `docker logs zzedc-caddy`
3. Wait 5-10 minutes for Let's Encrypt challenge
4. Look for ACME errors in logs
5. Check ports 80 and 443 are accessible from internet

### Issue: Database errors after restart

**Symptoms**: Application starts but database queries fail

**Solutions**:
1. Check data volume is mounted: `docker inspect zzedc-app | grep -A 5 Mounts`
2. Verify data directory permissions: `ls -la /opt/zzedc/data/`
3. Check database integrity: `sqlite3 /opt/zzedc/data/zzedc.db ".tables"`
4. Check Docker logs for SQL errors

---

## Cost Management

### Cost Breakdown (Single Test Cycle)

| Component | Time | Cost |
|-----------|------|------|
| t3.micro instance | ~15 min | $0.0029 |
| Docker image storage | Included | $0.00 |
| Data transfer (out) | <100 MB | <$0.01 |
| **Total** | | **~$0.05** |

### Cost Reduction Tips

1. **Use smallest instance type** (t3.micro or t3.small)
2. **Test in lowest-cost region** (us-east-1)
3. **Remove instance immediately** after testing (`--keep-instance` auto-cleanup)
4. **Batch multiple tests** to amortize setup time

### Cost Monitoring

```bash
# View current AWS costs
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-02 \
  --granularity DAILY \
  --metrics "UnblendedCost"

# Set up billing alerts
# AWS Console → Billing → Budgets → Create budget
```

### Cleanup Commands

If you use `--skip-teardown`, clean up manually:

```bash
# List instances
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' --output table

# Terminate specific instance
aws ec2 terminate-instances --instance-ids i-0123456789abcdef0 --region us-west-2

# Delete security group (after instance terminates)
aws ec2 delete-security-group --group-id sg-0123456789abcdef0 --region us-west-2

# Delete key pair (if no longer needed)
aws ec2 delete-key-pair --key-name zzedc-1234567890 --region us-west-2
rm ~/.ssh/zzedc-1234567890.pem
```

---

## Best Practices

### Test Configuration

1. **Use test study parameters**:
   ```bash
   --study-name "Test Trial"
   --study-id "TEST-2025"
   --admin-password "TestPass123!"
   ```

2. **Test in lowest-cost region first**:
   ```bash
   --region us-east-1
   ```

3. **Always start with `--keep-instance` once**:
   - Allows manual inspection
   - Helps debug any issues

4. **Use consistent test domain**:
   ```bash
   --domain test.yourinstitution.org
   ```

### Debugging

1. **Keep instances for post-test inspection**:
   ```bash
   ./aws_test.sh ... --keep-instance
   ```

2. **Check logs immediately after test**:
   ```bash
   cat /tmp/zzedc_test_results_*.txt
   ```

3. **SSH in and inspect Docker**:
   ```bash
   ssh -i ~/.ssh/zzedc-*.pem ubuntu@[IP]
   docker-compose logs -f
   ```

4. **Save instance details for analysis**:
   - Instance ID
   - Public IP
   - Instance type
   - Region
   - Any errors encountered

### Performance Testing

For load testing after successful deployment:

1. Use `--keep-instance` to preserve instance
2. Connect as normal user and create test data
3. Use Apache JMeter or similar for load tests
4. Monitor via CloudWatch and instance SSH

---

## Next Steps After Testing

### If Tests Pass ✓

1. Review test results: `cat /tmp/zzedc_test_results_*.txt`
2. Document any warnings or timeouts observed
3. Note actual deployment duration
4. Compare actual vs. estimated costs
5. Update deployment documentation if needed
6. Proceed to production deployment

### If Tests Fail ✗

1. Review failure details in results file
2. Check troubleshooting section above
3. Verify all prerequisites are met
4. Use `--keep-instance --skip-teardown` to inspect
5. Check CloudTrail for AWS API errors
6. Consult IT_STAFF_TROUBLESHOOTING.md

### For Production Deployment

After successful test:

1. Use actual production parameters:
   ```bash
   ./aws_setup.sh \
     --study-name "Production Study Name" \
     --study-id "PROD-2025-001" \
     --admin-password "[Strong password]" \
     --domain trial.yourinstitution.org \
     --instance-type t3.small  # Production should use t3.small or larger
   ```

2. Configure production domain DNS
3. Wait for DNS propagation (24-48 hours)
4. Follow IT_STAFF_DEPLOYMENT_CHECKLIST.md
5. Perform post-deployment security review

---

## Support

If tests fail or you need assistance:

1. **Check documentation**:
   - AWS_DEPLOYMENT_GUIDE.md
   - IT_STAFF_TROUBLESHOOTING.md
   - IT_STAFF_DEPLOYMENT_CHECKLIST.md

2. **Review AWS CloudTrail**:
   - CloudTrail → Events → Filter by service/resource

3. **Check system logs**:
   - `/tmp/zzedc_test_results_*.txt` (local test log)
   - Instance `/var/log/` (via SSH)
   - Docker logs (via `docker logs [container]`)

4. **Contact support**:
   - Email: rgthomas@ucsd.edu
   - GitHub: https://github.com/rgt47/zzedc/issues
   - Include: test results, instance details, error messages

---

## Additional Resources

- **AWS Documentation**: https://docs.aws.amazon.com/ec2/
- **Docker Documentation**: https://docs.docker.com/
- **Caddy Documentation**: https://caddyserver.com/docs/
- **ZZedc GitHub**: https://github.com/rgt47/zzedc
- **Deployment Guide**: IT_STAFF_DEPLOYMENT_CHECKLIST.md

---

**Last Updated**: December 2025
**Version**: 1.0
**Status**: Production Ready
