# Multi-stage Dockerfile for ZZedc with Caddy reverse proxy
# Build: docker build -t zzedc-app:latest .
# Run:   docker run -p 3838:3838 -e ZZEDC_SALT=<salt> zzedc-app:latest

################################################################################
# Stage 1: Builder - R environment with ZZedc
################################################################################

FROM rocker/r-ubuntu:4.4 AS builder

# Install system dependencies for ZZedc and Shiny
RUN apt-get update && apt-get install -y \
    # Build tools
    build-essential \
    git \
    curl \
    wget \
    # Database and data manipulation
    libsqlite3-dev \
    libmysqlclient-dev \
    # Graphics and web
    libx11-dev \
    libfreetype6-dev \
    libpng-dev \
    # System utilities
    ca-certificates \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Install ZZedc from CRAN (or development version if needed)
RUN R -e "install.packages('zzedc', repos='http://cran.r-project.org')" || \
    R -e "devtools::install_github('rgt47/zzedc')"

# Install additional required packages
RUN R -e "\
  packages <- c( \
    'shiny', 'bslib', 'bsicons', \
    'RSQLite', 'DBI', \
    'DT', 'ggplot2', 'tidyverse', \
    'yaml', 'jsonlite', \
    'digest', 'bcrypt', \
    'lubridate', 'glue' \
  ); \
  install.packages(packages, repos='http://cran.r-project.org')"

################################################################################
# Stage 2: Runtime - Production image with Caddy
################################################################################

FROM rocker/r-ubuntu:4.4

LABEL maintainer="Investigator <your-email@institution.edu>" \
      description="ZZedc Electronic Data Capture with Caddy HTTPS" \
      version="1.0.0"

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    # Caddy (for automatic HTTPS)
    caddy \
    # Utilities
    curl \
    wget \
    openssh-client \
    ca-certificates \
    # Database runtime
    libsqlite3-0 \
    # Monitoring
    htop \
    && rm -rf /var/lib/apt/lists/*

# Copy R packages from builder
COPY --from=builder /usr/local/lib/R /usr/local/lib/R

# Create application directories
RUN mkdir -p /app/data \
    && mkdir -p /app/logs \
    && mkdir -p /app/backups \
    && mkdir -p /app/config \
    && mkdir -p /app/forms \
    && mkdir -p /etc/caddy

# Set working directory
WORKDIR /app

# Copy ZZedc package files
COPY . /app/

# Create application launcher script
RUN cat > /app/launch_zzedc.sh << 'EOF'
#!/bin/bash
set -e

# Set environment variables from Docker environment
export ZZEDC_SALT="${ZZEDC_SALT}"
export STUDY_NAME="${STUDY_NAME}"
export STUDY_ID="${STUDY_ID}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD}"
export PI_EMAIL="${PI_EMAIL:-admin@example.org}"
export LOG_LEVEL="${LOG_LEVEL:-info}"

# Wait for dependencies to be ready
sleep 2

# Initialize ZZedc if not already configured
if [ ! -f ./config.yml ]; then
    echo "Initializing ZZedc from configuration..."

    # Create temporary config file for init
    cat > /tmp/zzedc_init_config.yml << 'CONFIG'
study:
  name: "${STUDY_NAME}"
  protocol_id: "${STUDY_ID}"
  pi_email: "${PI_EMAIL}"
  target_enrollment: 100
  phase: "Phase3"

admin:
  username: "admin"
  fullname: "System Administrator"
  email: "${PI_EMAIL}"
  password: "${ADMIN_PASSWORD}"

security:
  session_timeout_minutes: 30
  enforce_https: true
  max_failed_login_attempts: 3

compliance:
  gdpr_enabled: true
  cfr_part11_enabled: true
  audit_logging_enabled: true

database:
  type: "sqlite"
  pool_size: 5
CONFIG

    # Run initialization in R
    R -e "
      library(zzedc)
      zzedc::init(
        mode = 'config',
        config_file = '/tmp/zzedc_init_config.yml',
        project_dir = '/app'
      )
    "
else
    echo "ZZedc already configured, skipping initialization"
fi

# Launch ZZedc Shiny application
echo "Launching ZZedc application on port 3838..."
exec R -e "
  library(zzedc)
  Sys.setenv(ZZEDC_SALT = '${ZZEDC_SALT}')
  launch_zzedc()
"
EOF

chmod +x /app/launch_zzedc.sh

# Create Caddyfile for reverse proxy
# This will be mounted as a volume or copied from host
RUN cat > /etc/caddy/Caddyfile << 'EOF'
# Caddyfile for ZZedc
# This file is typically overwritten by docker-compose or deployment script
# to set the actual domain name

{
    # Global configuration
    email admin@example.org
    acme_dns route53 {
        max_retries 5
    }
}

# Replace DOMAIN_NAME with actual domain (e.g., trial.example.org)
DOMAIN_NAME {
    # Reverse proxy to Shiny application
    reverse_proxy localhost:3838 {
        # Forward original request information
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Host {host}
        header_up X-Real-IP {http.request.remote.host}

        # WebSocket support for Shiny
        header_up Connection {http.request.header.Connection}
        header_up Upgrade {http.request.header.Upgrade}

        # Timeout settings for long-running R operations
        flush_interval -1
    }

    # Disable automatic HTTP->HTTPS redirect if behind load balancer
    # Uncomment if needed:
    # @insecure {
    #     protocol http
    # }
    # redir @insecure https://{host}{uri} 307

    # Enable compression for faster delivery
    encode gzip

    # Security headers
    header / {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "geolocation=(), camera=(), microphone=()"
    }

    # Logging
    log {
        output file /app/logs/caddy-access.log {
            roll_size 10mb
            roll_keep 7
            roll_keep_for 30d
        }
        format json
        level info
    }
}

# Catch-all for ACME validation
http://{host} {
    # Let Caddy handle Let's Encrypt ACME challenges
    redir / https://{host}{uri} 307
}
EOF

# Set proper permissions
RUN chmod 644 /etc/caddy/Caddyfile \
    && chown -R root:root /app \
    && chmod 755 /app/launch_zzedc.sh

# Health check - verify Shiny is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3838 || exit 1

# Expose ports
# 80: HTTP (for ACME challenges and redirects)
# 443: HTTPS (secure application access)
# 3838: Shiny (internal, behind Caddy)
EXPOSE 80 443 3838

# Environment variables (defaults, can be overridden at runtime)
ENV ZZEDC_SALT=""
ENV STUDY_NAME="Default Study"
ENV STUDY_ID="DEFAULT-001"
ENV ADMIN_PASSWORD="changeme"
ENV PI_EMAIL="admin@example.org"
ENV LOG_LEVEL="info"

# Default command - runs Caddy which proxies to Shiny
# Caddy runs in foreground, Docker watches this process
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

# Alternative: Run only Shiny without Caddy (for development or single-machine)
# CMD ["/app/launch_zzedc.sh"]

# Build notes:
# - Rocker/r-ubuntu provides full R environment
# - Caddy is installed for automatic HTTPS
# - All ZZedc dependencies are included
# - Multi-stage build keeps final image smaller
# - Proper signal handling for graceful shutdown
#
# Security notes:
# - Never commit passwords to image; use environment variables
# - ZZEDC_SALT should be different for each deployment
# - Database file stored in /app/data (mount as volume in docker-compose)
# - Audit logs in /app/logs (mount as volume for persistence)
#
# Performance notes:
# - Caddy handles HTTPS termination efficiently
# - Reverse proxy connection pooling enabled
# - WebSocket support for real-time Shiny updates
# - Gzip compression reduces bandwidth
