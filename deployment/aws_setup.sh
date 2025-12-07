#!/bin/bash
################################################################################
# ZZedc AWS EC2 Deployment Script
#
# This script automates the complete setup of ZZedc on AWS EC2 with Docker,
# Caddy (automatic HTTPS), and R/Shiny stack.
#
# Usage:
#   ./aws_setup.sh --region us-west-2 --study-name "My Trial" \
#     --study-id "TRIAL-2025-001" --admin-password "SecurePass123!" \
#     --domain trial.example.org --instance-type t3.medium
#
# For complete instructions, see: docs/AWS_DEPLOYMENT_GUIDE.md
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

################################################################################
# Configuration Variables
################################################################################

# AWS Settings
AWS_REGION="${AWS_REGION:-us-west-2}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
KEY_PAIR_NAME="${KEY_PAIR_NAME}"

# Study Configuration
STUDY_NAME="${STUDY_NAME}"
STUDY_ID="${STUDY_ID}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
PI_EMAIL="${PI_EMAIL}"

# Network Configuration
DOMAIN_NAME="${DOMAIN_NAME}"
SECURITY_GROUP_NAME="zzedc-$(date +%s)"

# Docker & Application
DOCKER_IMAGE_NAME="zzedc-app"
APP_PORT=3838
CADDY_PORT=443

# Project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_DIR="$SCRIPT_DIR"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

validate_input() {
    if [ -z "$1" ]; then
        print_error "$2"
        exit 1
    fi
}

################################################################################
# Argument Parsing
################################################################################

print_header "ZZedc AWS Deployment Script"

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --key-pair)
            KEY_PAIR_NAME="$2"
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
        --pi-email)
            PI_EMAIL="$2"
            shift 2
            ;;
        --domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --help)
            cat << 'EOF'
Usage: ./aws_setup.sh [OPTIONS]

Required Options:
  --study-name TEXT           Study/Trial name (e.g., "Depression Trial 2025")
  --study-id TEXT             Study protocol ID (e.g., "DEPR-2025-001")
  --admin-password TEXT       Admin account password (8+ characters)
  --domain TEXT               Domain name for HTTPS (e.g., trial.example.org)

Optional Options:
  --region REGION             AWS region (default: us-west-2)
  --instance-type TYPE        EC2 instance type (default: t3.medium)
  --key-pair NAME             AWS EC2 Key Pair name (creates if not exists)
  --pi-email EMAIL            Principal Investigator email address
  --help                      Show this help message

Example:
  ./aws_setup.sh \
    --region us-west-2 \
    --study-name "Depression Treatment Trial" \
    --study-id "DEPR-2025-001" \
    --admin-password "SecurePass123!" \
    --domain trial.example.org \
    --instance-type t3.medium
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
# Validation
################################################################################

print_header "Validating Configuration"

validate_input "$STUDY_NAME" "Error: --study-name is required"
validate_input "$STUDY_ID" "Error: --study-id is required"
validate_input "$ADMIN_PASSWORD" "Error: --admin-password is required"
validate_input "$DOMAIN_NAME" "Error: --domain is required"

# Validate password strength
if [ ${#ADMIN_PASSWORD} -lt 8 ]; then
    print_error "Password must be at least 8 characters"
    exit 1
fi

# Check AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    print_info "See: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials are not configured. Run: aws configure"
    exit 1
fi

print_success "AWS credentials configured"
print_success "Configuration validated"

################################################################################
# Create/Get Key Pair
################################################################################

print_header "Setting up EC2 Key Pair"

if [ -z "$KEY_PAIR_NAME" ]; then
    KEY_PAIR_NAME="zzedc-$(date +%s)"
    print_info "Key pair name not provided, generating: $KEY_PAIR_NAME"
fi

# Check if key pair already exists
if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" 2>/dev/null; then
    print_success "Using existing key pair: $KEY_PAIR_NAME"
else
    print_info "Creating new key pair: $KEY_PAIR_NAME"

    # Create key pair and save locally
    KEYPAIR_FILE="$HOME/.ssh/${KEY_PAIR_NAME}.pem"

    aws ec2 create-key-pair \
        --key-name "$KEY_PAIR_NAME" \
        --region "$AWS_REGION" \
        --query 'KeyMaterial' \
        --output text > "$KEYPAIR_FILE"

    chmod 400 "$KEYPAIR_FILE"
    print_success "Key pair created and saved to: $KEYPAIR_FILE"
fi

################################################################################
# Create Security Group
################################################################################

print_header "Setting up Security Group"

# Create security group
SG_ID=$(aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Security group for ZZedc application" \
    --region "$AWS_REGION" \
    --query 'GroupId' \
    --output text)

print_success "Security group created: $SG_ID"

# Add ingress rules
# HTTPS (443)
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION" \
    --description "HTTPS access"

# HTTP (80) - for Caddy let's encrypt validation
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION" \
    --description "HTTP for ACME challenges"

# SSH (22) - for management
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION" \
    --description "SSH access"

print_success "Ingress rules configured (HTTP, HTTPS, SSH)"

################################################################################
# Get Latest Ubuntu 24.04 LTS AMI
################################################################################

print_header "Finding Latest Ubuntu 24.04 LTS AMI"

# Use SSM Parameter Store for latest Ubuntu 24.04 LTS AMI
# This is the canonical approach - the AMI ID is resolved dynamically
AMI_ID=$(aws ssm get-parameter \
    --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text)

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    # Fallback: Use AWS CLI to find latest Ubuntu 24.04 LTS
    print_info "SSM parameter not available, using describe-images..."

    AMI_ID=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text \
        --region "$AWS_REGION")
fi

validate_input "$AMI_ID" "Could not find Ubuntu 24.04 LTS AMI in region $AWS_REGION"
print_success "Using AMI: $AMI_ID (Ubuntu 24.04 LTS)"

################################################################################
# Create User Data Script
################################################################################

print_header "Preparing EC2 Initialization Script"

# Create user-data script that will run on EC2 startup
cat > /tmp/zzedc_userdata.sh << 'USERDATA_EOF'
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y
apt-get install -y curl git wget

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
rm get-docker.sh

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directories
mkdir -p /opt/zzedc/{data,logs,backups,config}
cd /opt/zzedc

# Write Docker Compose configuration
cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.9'

services:
  caddy:
    image: caddy:latest
    container_name: zzedc-caddy
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    networks:
      - zzedc-network
    restart: always
    depends_on:
      - zzedc

  zzedc:
    image: zzedc-app:latest
    container_name: zzedc-app
    ports:
      - "3838:3838"
    environment:
      ZZEDC_SALT: "${ZZEDC_SALT}"
      STUDY_NAME: "${STUDY_NAME}"
      STUDY_ID: "${STUDY_ID}"
      ADMIN_PASSWORD: "${ADMIN_PASSWORD}"
      PI_EMAIL: "${PI_EMAIL}"
      LOG_LEVEL: "info"
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
      - ./backups:/app/backups
      - ./config:/app/config
    networks:
      - zzedc-network
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3838"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  caddy-data:
  caddy-config:

networks:
  zzedc-network:
    driver: bridge
COMPOSE_EOF

# Create Caddyfile (populated by bootstrap script)
cat > Caddyfile << 'CADDY_EOF'
{
    acme_dns route53 {
        max_retries 5
    }
}

CADDY_DOMAIN {
    reverse_proxy zzedc:3838 {
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Host {host}
    }
}
CADDY_EOF

# Set proper permissions
chown -R ubuntu:ubuntu /opt/zzedc
chmod 750 /opt/zzedc

# Signal completion
echo "ZZedc AWS deployment bootstrap complete" > /var/log/zzedc-bootstrap.log
USERDATA_EOF

print_success "User data script prepared"

################################################################################
# Launch EC2 Instance
################################################################################

print_header "Launching EC2 Instance"

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_PAIR_NAME" \
    --security-group-ids "$SG_ID" \
    --user-data file:///tmp/zzedc_userdata.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=zzedc-${STUDY_ID}},{Key=Study,Value=${STUDY_NAME}}]" \
    --region "$AWS_REGION" \
    --query 'Instances[0].InstanceId' \
    --output text)

validate_input "$INSTANCE_ID" "Failed to launch EC2 instance"
print_success "EC2 instance launched: $INSTANCE_ID"

# Wait for instance to be running
print_info "Waiting for instance to start (this may take 1-2 minutes)..."

aws ec2 wait instance-running \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION"

print_success "Instance is running"

################################################################################
# Get Instance Details
################################################################################

INSTANCE_INFO=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0]' \
    --output json)

PUBLIC_IP=$(echo "$INSTANCE_INFO" | grep -o '"PublicIpAddress": "[^"]*"' | cut -d'"' -f4)
PRIVATE_IP=$(echo "$INSTANCE_INFO" | grep -o '"PrivateIpAddress": "[^"]*"' | cut -d'"' -f4)

print_success "Public IP: $PUBLIC_IP"
print_success "Private IP: $PRIVATE_IP"

################################################################################
# Wait for Instance Readiness
################################################################################

print_header "Waiting for Instance Initialization"
print_info "Instance is starting Docker and ZZedc components..."
print_info "This typically takes 3-5 minutes on first launch"

# Wait for status checks
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    STATUS=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].InstanceStatus.InstanceStatus' \
        --output text)

    if [ "$STATUS" = "ok" ]; then
        print_success "Instance status checks passed"
        break
    fi

    ATTEMPT=$((ATTEMPT + 1))
    if [ $((ATTEMPT % 10)) -eq 0 ]; then
        print_info "Still waiting... ($ATTEMPT/$MAX_ATTEMPTS attempts)"
    fi
    sleep 3
done

################################################################################
# Generate Configuration
################################################################################

print_header "Generating Configuration Files"

# Generate security salt
ZZEDC_SALT=$(openssl rand -hex 16)

# Create configuration file
CONFIG_FILE="/tmp/zzedc_config.yml"

cat > "$CONFIG_FILE" << EOF
# ZZedc Configuration
# Generated: $(date)
# Study: $STUDY_NAME ($STUDY_ID)

study:
  name: "$STUDY_NAME"
  protocol_id: "$STUDY_ID"
  pi_email: "$PI_EMAIL"
  target_enrollment: 100
  phase: "Phase3"

admin:
  username: "admin"
  fullname: "System Administrator"
  email: "$PI_EMAIL"
  password: "$ADMIN_PASSWORD"

security:
  session_timeout_minutes: 30
  enforce_https: true
  max_failed_login_attempts: 3
  salt: "$ZZEDC_SALT"

compliance:
  gdpr_enabled: true
  cfr_part11_enabled: true
  audit_logging_enabled: true

database:
  type: "sqlite"
  pool_size: 5
EOF

print_success "Configuration generated"

################################################################################
# Output Summary
################################################################################

print_header "Deployment Summary"

cat << EOF

✓ EC2 Instance Successfully Launched

Instance Information:
  Instance ID:        $INSTANCE_ID
  Instance Type:      $INSTANCE_TYPE
  Region:             $AWS_REGION
  Public IP:          $PUBLIC_IP
  Private IP:         $PRIVATE_IP
  Security Group:     $SG_ID

Study Configuration:
  Study Name:         $STUDY_NAME
  Study ID:           $STUDY_ID
  Domain:             $DOMAIN_NAME
  Admin Email:        $PI_EMAIL

Next Steps:

1. SSH into your instance:
   ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem ubuntu@${PUBLIC_IP}

2. Complete Docker setup:
   cd /opt/zzedc

   # Replace CADDY_DOMAIN in Caddyfile
   sed -i 's/CADDY_DOMAIN/${DOMAIN_NAME}/g' Caddyfile

   # Build and start services
   docker-compose build
   docker-compose up -d

3. Point your domain to the instance:
   Add an A record pointing ${DOMAIN_NAME} to ${PUBLIC_IP}
   (May take 24-48 hours to propagate)

4. First Login:
   Once DNS propagates, visit: https://${DOMAIN_NAME}
   Username: admin
   Password: (as provided)

5. Backup Configuration:
   Save this information:
   - Instance ID: $INSTANCE_ID
   - Key Pair: ${KEY_PAIR_NAME}.pem
   - Security Salt: $ZZEDC_SALT
   - Admin Password (change in app after first login)

Documentation:
   See deployment/AWS_DEPLOYMENT_GUIDE.md for detailed instructions
   See deployment/IT_STAFF_DEPLOYMENT_CHECKLIST.md for checklist
   See deployment/IT_STAFF_TROUBLESHOOTING.md for troubleshooting

Support:
   If you encounter issues, check the troubleshooting guide.

EOF

# Save deployment details
DETAILS_FILE="zzedc-deployment-${INSTANCE_ID}.txt"
cat > "$DETAILS_FILE" << EOF
ZZedc AWS Deployment Details
Generated: $(date)

Instance ID: $INSTANCE_ID
Public IP: $PUBLIC_IP
Private IP: $PRIVATE_IP
Key Pair: $KEY_PAIR_NAME
Security Group: $SG_ID
Region: $AWS_REGION
Instance Type: $INSTANCE_TYPE

Study: $STUDY_NAME ($STUDY_ID)
Domain: $DOMAIN_NAME
Admin Email: $PI_EMAIL

Security Salt: $ZZEDC_SALT
Configuration saved to: $CONFIG_FILE

Keep this file safe - it contains sensitive deployment information.
EOF

print_success "Deployment details saved to: $DETAILS_FILE"

print_header "Deployment Complete!"
print_success "Your ZZedc instance is initializing."
print_info "Check back in 3-5 minutes for full readiness."

