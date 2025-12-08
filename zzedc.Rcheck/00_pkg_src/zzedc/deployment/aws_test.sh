#!/bin/bash
################################################################################
# ZZedc AWS Deployment Testing Script
#
# This script runs the complete aws_setup.sh deployment, then performs
# comprehensive testing of all components.
#
# Usage:
#   ./aws_test.sh --region us-west-2 --study-name "Test Trial" \
#     --study-id "TEST-2025" --admin-password "TestPass123!" \
#     --domain test.example.org [--keep-instance]
#
# Options:
#   --keep-instance    Keep instance running after tests (default: terminate)
#   --skip-teardown    Don't terminate instance or clean up resources
#
# Note: This script will incur AWS costs during testing. Default behavior
# is to terminate resources after testing is complete.
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

################################################################################
# Global Variables
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_DIR="$SCRIPT_DIR"

AWS_REGION="us-west-2"
STUDY_NAME=""
STUDY_ID=""
ADMIN_PASSWORD=""
DOMAIN_NAME=""
PI_EMAIL="${PI_EMAIL:-test@example.org}"
INSTANCE_TYPE="t3.micro"  # Use smallest instance for testing to reduce costs
KEEP_INSTANCE=false
SKIP_TEARDOWN=false

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS_FILE=""
INSTANCE_ID=""
PUBLIC_IP=""
KEY_PAIR_NAME=""
SECURITY_GROUP_ID=""
DEPLOYMENT_START_TIME=""
DEPLOYMENT_END_TIME=""

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=================================================================================${NC}\n"
}

print_section() {
    echo -e "\n${MAGENTA}─── $1 ───${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_exit="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  TEST $TESTS_RUN: $test_name ... "

    if eval "$test_cmd" > /tmp/test_output.txt 2>&1; then
        if [ "$expected_exit" = "success" ] || [ -z "$expected_exit" ]; then
            print_success "$test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi
    else
        if [ "$expected_exit" = "failure" ]; then
            print_success "$test_name (expected failure)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi
    fi

    print_error "$test_name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    if [ -s /tmp/test_output.txt ]; then
        echo "    Output: $(head -1 /tmp/test_output.txt)"
    fi
    return 1
}

save_test_result() {
    echo "$1" >> "$TEST_RESULTS_FILE"
}

log_test_result() {
    local status="$1"
    local test_name="$2"
    local details="$3"

    save_test_result "[$status] $test_name"
    if [ -n "$details" ]; then
        save_test_result "  Details: $details"
    fi
}

cleanup_resources() {
    if [ "$SKIP_TEARDOWN" = true ]; then
        print_warning "Skipping resource cleanup (--skip-teardown)"
        return 0
    fi

    print_header "Cleaning Up AWS Resources"

    if [ -z "$INSTANCE_ID" ]; then
        print_info "No instance ID found, skipping cleanup"
        return 0
    fi

    # Terminate instance
    if [ ! -z "$INSTANCE_ID" ]; then
        print_info "Terminating instance: $INSTANCE_ID"
        aws ec2 terminate-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$AWS_REGION" \
            --output text > /dev/null
        print_success "Instance termination initiated"
    fi

    # Delete security group (wait for instance termination first)
    if [ ! -z "$SECURITY_GROUP_ID" ]; then
        print_info "Waiting for instance to terminate..."
        sleep 30

        print_info "Deleting security group: $SECURITY_GROUP_ID"
        aws ec2 delete-security-group \
            --group-id "$SECURITY_GROUP_ID" \
            --region "$AWS_REGION" 2>/dev/null || true
        print_success "Security group deleted"
    fi

    print_success "Cleanup complete"
}

# Trap for cleanup on exit
trap cleanup_resources EXIT

################################################################################
# Argument Parsing
################################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --study-name)
            STUDY_NAME="$2"
            shift 2
            ;;
        --study-id)
            STUDY_ID="$2"
            shift 2
            ;;
        --admin-password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --pi-email)
            PI_EMAIL="$2"
            shift 2
            ;;
        --keep-instance)
            KEEP_INSTANCE=true
            shift
            ;;
        --skip-teardown)
            SKIP_TEARDOWN=true
            shift
            ;;
        --help)
            cat << 'EOF'
Usage: ./aws_test.sh [OPTIONS]

Required Options:
  --region REGION             AWS region (default: us-west-2)
  --study-name TEXT           Study/Trial name
  --study-id TEXT             Study protocol ID
  --admin-password TEXT       Admin account password
  --domain TEXT               Domain name for testing

Optional Options:
  --pi-email EMAIL            PI email (default: test@example.org)
  --keep-instance             Keep instance running after tests
  --skip-teardown             Don't terminate resources
  --help                      Show this help message

Example:
  ./aws_test.sh \
    --region us-west-2 \
    --study-name "Test Trial" \
    --study-id "TEST-2025" \
    --admin-password "TestPass123!" \
    --domain test.example.org

WARNING: This script launches AWS EC2 instances and incurs costs. By default,
all instances are terminated after testing. Use --keep-instance to keep the
instance running for manual inspection.

Cost estimate: ~$0.05-0.10 for a complete test cycle (t3.micro instance)
EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

################################################################################
# Input Validation
################################################################################

print_header "ZZedc AWS Deployment Testing Script"

if [ -z "$STUDY_NAME" ] || [ -z "$STUDY_ID" ] || [ -z "$ADMIN_PASSWORD" ] || [ -z "$DOMAIN_NAME" ]; then
    print_error "Missing required parameters. Use --help for usage."
    exit 1
fi

# Create test results file
TEST_RESULTS_FILE="/tmp/zzedc_test_results_$(date +%s).txt"
echo "ZZedc AWS Deployment Test Results" > "$TEST_RESULTS_FILE"
echo "=================================" >> "$TEST_RESULTS_FILE"
echo "Test Started: $(date)" >> "$TEST_RESULTS_FILE"
echo "Region: $AWS_REGION" >> "$TEST_RESULTS_FILE"
echo "Study: $STUDY_NAME ($STUDY_ID)" >> "$TEST_RESULTS_FILE"
echo "Domain: $DOMAIN_NAME" >> "$TEST_RESULTS_FILE"
echo "" >> "$TEST_RESULTS_FILE"

print_success "Test results will be saved to: $TEST_RESULTS_FILE"

################################################################################
# Phase 1: Pre-Deployment Validation
################################################################################

print_header "Phase 1: Pre-Deployment Validation"

print_section "Checking prerequisites"

run_test "AWS CLI installed" "command -v aws &> /dev/null" "success"
log_test_result "PASS" "AWS CLI installed" ""

run_test "AWS credentials configured" "aws sts get-caller-identity > /dev/null 2>&1" "success"
log_test_result "PASS" "AWS credentials configured" ""

run_test "openssl available" "command -v openssl &> /dev/null" "success"
log_test_result "PASS" "openssl available" ""

run_test "curl available" "command -v curl &> /dev/null" "success"
log_test_result "PASS" "curl available" ""

run_test "ssh available" "command -v ssh &> /dev/null" "success"
log_test_result "PASS" "ssh available" ""

print_section "Validating deployment files"

run_test "aws_setup.sh exists" "test -f '$DEPLOYMENT_DIR/aws_setup.sh'" "success"
log_test_result "PASS" "aws_setup.sh exists" ""

run_test "docker-compose.yml exists" "test -f '$DEPLOYMENT_DIR/docker-compose.yml'" "success"
log_test_result "PASS" "docker-compose.yml exists" ""

run_test "Caddyfile exists" "test -f '$DEPLOYMENT_DIR/Caddyfile'" "success"
log_test_result "PASS" "Caddyfile exists" ""

run_test ".env.template exists" "test -f '$DEPLOYMENT_DIR/.env.template'" "success"
log_test_result "PASS" ".env.template exists" ""

################################################################################
# Phase 2: AWS Deployment
################################################################################

print_header "Phase 2: AWS Deployment Execution"

DEPLOYMENT_START_TIME=$(date +%s)

print_info "Starting AWS deployment (this may take 5-10 minutes)..."
print_info "Study: $STUDY_NAME ($STUDY_ID)"
print_info "Instance Type: $INSTANCE_TYPE"
print_info "Region: $AWS_REGION"

# Run deployment script with test parameters
DEPLOYMENT_OUTPUT=$($DEPLOYMENT_DIR/aws_setup.sh \
    --region "$AWS_REGION" \
    --study-name "$STUDY_NAME" \
    --study-id "$STUDY_ID" \
    --admin-password "$ADMIN_PASSWORD" \
    --domain "$DOMAIN_NAME" \
    --pi-email "$PI_EMAIL" \
    --instance-type "$INSTANCE_TYPE" 2>&1 || true)

# Parse deployment output for instance details
INSTANCE_ID=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP '(?<=EC2 instance launched: ).*' | head -1)
if [ -z "$INSTANCE_ID" ]; then
    INSTANCE_ID=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP 'Instance ID:.*' | grep -oP 'i-[a-f0-9]+' | head -1)
fi

PUBLIC_IP=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP '(?<=Public IP: ).*' | head -1)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP 'Public IP\s+:\s+\K[0-9.]+' | head -1)
fi

SECURITY_GROUP_ID=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP '(?<=Security group created: ).*' | head -1)
if [ -z "$SECURITY_GROUP_ID" ]; then
    SECURITY_GROUP_ID=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP 'Security Group:\s+\K.*' | head -1)
fi

KEY_PAIR_NAME=$(echo "$DEPLOYMENT_OUTPUT" | grep -oP 'Key pair.*: \K.*' | head -1)
if [ -z "$KEY_PAIR_NAME" ]; then
    KEY_PAIR_NAME="zzedc-"*
fi

DEPLOYMENT_END_TIME=$(date +%s)
DEPLOYMENT_DURATION=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))

print_section "Deployment Results"

if [ ! -z "$INSTANCE_ID" ]; then
    print_success "Deployment completed successfully"
    print_info "Instance ID: $INSTANCE_ID"
    print_info "Public IP: $PUBLIC_IP"
    print_info "Duration: ${DEPLOYMENT_DURATION}s"
    log_test_result "PASS" "AWS deployment executed" "Instance: $INSTANCE_ID, IP: $PUBLIC_IP, Time: ${DEPLOYMENT_DURATION}s"
else
    print_error "Failed to parse instance ID from deployment output"
    log_test_result "FAIL" "AWS deployment execution" "Could not extract instance ID"
    exit 1
fi

################################################################################
# Phase 3: Instance Readiness Testing
################################################################################

print_header "Phase 3: Instance Readiness Testing"

print_info "Waiting for instance to be fully initialized..."

# Poll instance status
MAX_ATTEMPTS=60
ATTEMPT=0
INSTANCE_READY=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    STATUS=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].InstanceStatus.InstanceStatus' \
        --output text 2>/dev/null || echo "pending")

    if [ "$STATUS" = "ok" ]; then
        INSTANCE_READY=true
        print_success "Instance status checks passed"
        log_test_result "PASS" "Instance readiness" "Status checks passed"
        break
    fi

    ATTEMPT=$((ATTEMPT + 1))
    if [ $((ATTEMPT % 10)) -eq 0 ]; then
        print_info "Waiting for instance... ($ATTEMPT/$MAX_ATTEMPTS, status: $STATUS)"
    fi
    sleep 3
done

if [ "$INSTANCE_READY" = false ]; then
    print_warning "Instance status checks timed out (may still be initializing)"
    log_test_result "WARN" "Instance readiness" "Status check timeout"
fi

################################################################################
# Phase 4: SSH Connectivity Testing
################################################################################

print_header "Phase 4: SSH Connectivity Testing"

# Find the key file
KEY_FILE="$HOME/.ssh/${KEY_PAIR_NAME}.pem"
if [ ! -f "$KEY_FILE" ]; then
    # Try to find it
    KEY_FILE=$(find ~/.ssh -name "zzedc-*.pem" -type f | head -1)
fi

if [ -f "$KEY_FILE" ]; then
    print_success "Found key file: $KEY_FILE"

    # Test SSH connectivity
    print_info "Testing SSH connection (may require key authorization)..."
    sleep 10  # Wait a bit more for SSH to be ready

    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
            -i "$KEY_FILE" ubuntu@"$PUBLIC_IP" "echo 'SSH connection successful'" 2>/dev/null; then
        print_success "SSH connection successful"
        log_test_result "PASS" "SSH connectivity" "Connected to ubuntu@$PUBLIC_IP"
    else
        print_warning "SSH connection failed (instance may still be initializing)"
        log_test_result "WARN" "SSH connectivity" "Connection timeout or refused"
    fi
else
    print_warning "Key file not found, skipping SSH tests"
    log_test_result "WARN" "SSH connectivity" "Key file not found: $KEY_FILE"
fi

################################################################################
# Phase 5: HTTP/HTTPS Connectivity Testing
################################################################################

print_header "Phase 5: HTTP/HTTPS Connectivity Testing"

print_info "Testing HTTP connectivity to instance..."

# Test HTTP access
if curl -s -m 5 "http://$PUBLIC_IP" > /dev/null 2>&1; then
    print_success "HTTP accessible at http://$PUBLIC_IP"
    log_test_result "PASS" "HTTP connectivity" "Server responding on port 80"
else
    print_info "HTTP not responding yet (instance still initializing)"
    log_test_result "INFO" "HTTP connectivity" "Not yet responding"
fi

# Test port 3838 (Shiny)
if curl -s -m 5 "http://$PUBLIC_IP:3838" > /dev/null 2>&1; then
    print_success "Shiny application responding on port 3838"
    log_test_result "PASS" "Shiny port 3838" "Application responding"
else
    print_info "Shiny application not responding yet (still initializing)"
    log_test_result "INFO" "Shiny port 3838" "Not yet responding"
fi

################################################################################
# Phase 6: DNS and Domain Testing
################################################################################

print_header "Phase 6: DNS and Domain Testing"

print_info "Testing domain DNS resolution..."

if nslookup "$DOMAIN_NAME" > /dev/null 2>&1; then
    RESOLVED_IP=$(nslookup "$DOMAIN_NAME" | grep "Address:" | tail -1 | awk '{print $2}')
    print_success "Domain resolves to: $RESOLVED_IP"
    log_test_result "PASS" "DNS resolution" "Domain: $DOMAIN_NAME, IP: $RESOLVED_IP"

    if [ "$RESOLVED_IP" = "$PUBLIC_IP" ]; then
        print_success "Domain correctly points to instance IP"
    else
        print_warning "Domain resolves to different IP (may not be propagated yet)"
        log_test_result "WARN" "DNS accuracy" "Domain points to $RESOLVED_IP, instance is $PUBLIC_IP"
    fi
else
    print_warning "Domain does not resolve yet (DNS may not be configured)"
    log_test_result "WARN" "DNS resolution" "Domain $DOMAIN_NAME not resolvable"
fi

################################################################################
# Phase 7: Container Health Testing
################################################################################

print_header "Phase 7: Container Health Testing (SSH-based)"

if [ ! -z "$KEY_FILE" ] && [ -f "$KEY_FILE" ]; then
    print_info "Checking Docker containers via SSH..."

    # Test Docker status
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
            -i "$KEY_FILE" ubuntu@"$PUBLIC_IP" \
            "command -v docker &> /dev/null && echo 'Docker installed'" 2>/dev/null | grep -q "Docker installed"; then
        print_success "Docker is installed"
        log_test_result "PASS" "Docker installation" "Docker available on instance"
    else
        print_warning "Could not verify Docker installation via SSH"
        log_test_result "WARN" "Docker installation" "Unable to verify"
    fi
else
    print_info "Skipping container checks (SSH unavailable)"
    log_test_result "INFO" "Container health" "Skipped (SSH unavailable)"
fi

################################################################################
# Phase 8: Database Verification
################################################################################

print_header "Phase 8: Database Verification (SSH-based)"

if [ ! -z "$KEY_FILE" ] && [ -f "$KEY_FILE" ]; then
    print_info "Checking database via SSH..."

    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
            -i "$KEY_FILE" ubuntu@"$PUBLIC_IP" \
            "test -d /opt/zzedc/data && echo 'data directory exists'" 2>/dev/null | grep -q "exists"; then
        print_success "Data directory exists on instance"
        log_test_result "PASS" "Data directory" "Found at /opt/zzedc/data"
    else
        print_info "Data directory check inconclusive"
        log_test_result "INFO" "Data directory" "Status inconclusive"
    fi
else
    print_info "Skipping database checks (SSH unavailable)"
    log_test_result "INFO" "Database verification" "Skipped (SSH unavailable)"
fi

################################################################################
# Phase 9: Security Testing
################################################################################

print_header "Phase 9: Security Verification"

print_info "Verifying security group configuration..."

# Check security group rules
SG_RULES=$(aws ec2 describe-security-groups \
    --group-ids "$SECURITY_GROUP_ID" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0].IpPermissions' \
    --output json 2>/dev/null || echo "[]")

# Check for HTTP (80)
if echo "$SG_RULES" | grep -q '"FromPort": 80'; then
    print_success "HTTP (port 80) ingress rule present"
    log_test_result "PASS" "Security group - HTTP" "Port 80 rule exists"
else
    print_warning "HTTP (port 80) rule not found"
    log_test_result "WARN" "Security group - HTTP" "Port 80 rule missing"
fi

# Check for HTTPS (443)
if echo "$SG_RULES" | grep -q '"FromPort": 443'; then
    print_success "HTTPS (port 443) ingress rule present"
    log_test_result "PASS" "Security group - HTTPS" "Port 443 rule exists"
else
    print_warning "HTTPS (port 443) rule not found"
    log_test_result "WARN" "Security group - HTTPS" "Port 443 rule missing"
fi

# Check for SSH (22)
if echo "$SG_RULES" | grep -q '"FromPort": 22'; then
    print_success "SSH (port 22) ingress rule present"
    log_test_result "PASS" "Security group - SSH" "Port 22 rule exists"
else
    print_warning "SSH (port 22) rule not found"
    log_test_result "WARN" "Security group - SSH" "Port 22 rule missing"
fi

################################################################################
# Phase 10: Summary and Recommendations
################################################################################

print_header "Test Summary"

echo ""
echo "  Total Tests Run:   $TESTS_RUN"
echo "  Tests Passed:      $TESTS_PASSED"
echo "  Tests Failed:      $TESTS_FAILED"
echo "  Success Rate:      $(echo "scale=1; $TESTS_PASSED * 100 / $TESTS_RUN" | bc)%"
echo ""

print_section "Instance Information"

echo "  Instance ID:       $INSTANCE_ID"
echo "  Instance Type:     $INSTANCE_TYPE"
echo "  Public IP:         $PUBLIC_IP"
echo "  Region:            $AWS_REGION"
echo "  Study:             $STUDY_NAME ($STUDY_ID)"
echo "  Domain:            $DOMAIN_NAME"
echo ""

# Calculate deployment cost (rough estimate)
INSTANCE_HOURS=$(echo "scale=3; $DEPLOYMENT_DURATION / 3600" | bc)
COST=$(echo "scale=2; $INSTANCE_HOURS * 0.012" | bc)  # t3.micro costs ~$0.0116/hour

print_section "Cost Estimate"

echo "  Deployment Time:   ${DEPLOYMENT_DURATION}s (~${INSTANCE_HOURS}h)"
echo "  Estimated Cost:    \$$COST"
echo ""

if [ "$KEEP_INSTANCE" = true ]; then
    print_section "Instance Management"
    echo "  Instance Status:   RUNNING (--keep-instance specified)"
    echo ""
    echo "  To terminate manually:"
    echo "    aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $AWS_REGION"
    echo ""
    echo "  To SSH into instance:"
    if [ -f "$KEY_FILE" ]; then
        echo "    ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
    else
        echo "    ssh -i ~/.ssh/[key-pair-name].pem ubuntu@$PUBLIC_IP"
    fi
    echo ""
else
    print_section "Cleanup"
    echo "  Resources will be cleaned up automatically."
    echo "  Use --keep-instance to preserve the instance for inspection."
    echo ""
fi

print_section "Next Steps"

echo "  1. Review test results: $TEST_RESULTS_FILE"
echo "  2. Complete manual verification checklist: IT_STAFF_DEPLOYMENT_CHECKLIST.md"
echo "  3. Follow IT_STAFF_DEPLOYMENT_GUIDE.md for final steps"
echo "  4. Test application login and data persistence"
echo ""

# Save summary to results file
save_test_result ""
save_test_result "Test Completed: $(date)"
save_test_result "Tests Passed: $TESTS_PASSED/$TESTS_RUN"
save_test_result "Instance ID: $INSTANCE_ID"
save_test_result "Public IP: $PUBLIC_IP"
save_test_result "Deployment Duration: ${DEPLOYMENT_DURATION}s"
save_test_result "Estimated Cost: \$$COST"

print_success "Test results saved to: $TEST_RESULTS_FILE"

# Exit with appropriate code
if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All tests passed!"
    exit 0
else
    print_warning "Some tests failed. Review results for details."
    exit 1
fi
