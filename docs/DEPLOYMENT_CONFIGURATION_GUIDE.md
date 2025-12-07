# Deployment and Configuration Guide
## ZZedc Electronic Data Capture System

### Document Information
- **Document Type**: Deployment and Configuration Manual
- **Version**: 1.0.0
- **Date**: September 2025
- **Target Audience**: System Administrators, DevOps Engineers, IT Professionals

---

## Overview

This document provides comprehensive guidance for deploying and configuring the ZZedc Electronic Data Capture system across various environments, from local development installations to enterprise-grade production deployments. The system supports multiple deployment strategies to accommodate diverse organizational requirements and infrastructure constraints.

## System Requirements

### Hardware Requirements

#### Minimum Configuration
- **CPU**: 2 cores, 2.0 GHz
- **Memory**: 4 GB RAM
- **Storage**: 10 GB available disk space
- **Network**: Stable internet connection for package dependencies

#### Recommended Configuration
- **CPU**: 4 cores, 2.5 GHz or higher
- **Memory**: 8 GB RAM or higher
- **Storage**: 50 GB available disk space with SSD
- **Network**: High-speed internet connection with redundant connectivity

#### Enterprise Configuration
- **CPU**: 8+ cores, 3.0 GHz
- **Memory**: 16 GB RAM or higher
- **Storage**: 100 GB+ with RAID configuration
- **Network**: Dedicated network infrastructure with load balancing

### Software Requirements

#### Core Dependencies
- **R**: Version 4.0.0 or higher
- **Operating System**:
  - Ubuntu 20.04 LTS or higher
  - Windows Server 2019 or higher
  - macOS 11.0 or higher
  - CentOS 8 or higher

#### R Package Dependencies
Required packages are automatically managed through the DESCRIPTION file:
- shiny (≥ 1.7.0)
- bslib (≥ 0.4.0)
- bsicons (≥ 0.1.0)
- RSQLite (≥ 2.2.0)
- pool (≥ 0.1.6)
- Additional packages as specified in DESCRIPTION

## Deployment Methods

### Method 1: Local Development Deployment

#### Prerequisites
1. Install R (version 4.0.0 or higher)
2. Install RStudio (recommended for development)
3. Ensure internet connectivity for package installation

#### Installation Process
```r
# Clone repository or extract package
# Navigate to project directory

# Install package dependencies
install.packages(c("shiny", "bslib", "bsicons", "RSQLite", "pool",
                   "DT", "ggplot2", "plotly", "dplyr", "digest"))

# Setup database
source("setup_database.R")

# Launch application
source("run_app.R")
```

#### Verification
1. Navigate to http://localhost:3838
2. Login with test credentials: test/test
3. Verify all tabs load without errors
4. Test basic data entry functionality

### Method 2: Server Deployment

#### Prerequisites
- Linux server with R installed
- Web server (Apache/Nginx) for reverse proxy
- SSL certificate for HTTPS (production requirement)
- Database backup and recovery procedures

#### Installation Steps

1. **System Preparation**
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install R and dependencies
sudo apt install r-base r-base-dev libssl-dev libcurl4-openssl-dev

# Install system dependencies for R packages
sudo apt install libxml2-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev
```

2. **Application Installation**
```bash
# Create application directory
sudo mkdir -p /opt/zzedc
sudo chown $(whoami):$(whoami) /opt/zzedc

# Copy application files
cp -r zzedc/* /opt/zzedc/

# Install R dependencies
cd /opt/zzedc
Rscript -e "install.packages(readLines('requirements.txt'), repos='https://cran.rstudio.com/')"
```

3. **Database Configuration**
```bash
# Create data directory with appropriate permissions
sudo mkdir -p /var/data/zzedc
sudo chown $(whoami):$(whoami) /var/data/zzedc
chmod 750 /var/data/zzedc

# Setup database
cd /opt/zzedc
Rscript setup_database.R
```

4. **Service Configuration**
Create systemd service file `/etc/systemd/system/zzedc.service`:
```ini
[Unit]
Description=ZZedc Electronic Data Capture System
After=network.target

[Service]
Type=simple
User=zzedc
WorkingDirectory=/opt/zzedc
ExecStart=/usr/bin/Rscript run_app.R
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

5. **Web Server Configuration**
Nginx configuration example:
```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /path/to/certificate.crt;
    ssl_certificate_key /path/to/private.key;

    location / {
        proxy_pass http://localhost:3838;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Method 3: Container Deployment

#### Docker Configuration
Create `Dockerfile`:
```dockerfile
FROM rocker/shiny:4.3.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy application
COPY . /srv/shiny-server/zzedc/

# Install R dependencies
RUN Rscript -e "install.packages(c('shiny', 'bslib', 'bsicons', 'RSQLite', 'pool'))"

# Setup database
WORKDIR /srv/shiny-server/zzedc
RUN Rscript setup_database.R

# Expose port
EXPOSE 3838

# Start application
CMD ["R", "-e", "source('run_app.R')"]
```

#### Docker Compose Configuration
Create `docker-compose.yml`:
```yaml
version: '3.8'

services:
  zzedc:
    build: .
    ports:
      - "3838:3838"
    volumes:
      - ./data:/srv/shiny-server/zzedc/data
      - ./logs:/var/log/shiny-server
    environment:
      - ZZEDC_ENV=production
      - ZZEDC_SALT=your_secure_salt_here
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/ssl/certs
    depends_on:
      - zzedc
    restart: unless-stopped
```

#### Kubernetes Deployment
Create `kubernetes-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zzedc-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: zzedc
  template:
    metadata:
      labels:
        app: zzedc
    spec:
      containers:
      - name: zzedc
        image: zzedc:latest
        ports:
        - containerPort: 3838
        env:
        - name: ZZEDC_ENV
          value: "production"
        volumeMounts:
        - name: data-volume
          mountPath: /srv/shiny-server/zzedc/data
      volumes:
      - name: data-volume
        persistentVolumeClaim:
          claimName: zzedc-data-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: zzedc-service
spec:
  selector:
    app: zzedc
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3838
  type: LoadBalancer
```

## Configuration Management

### Environment Configuration

#### Configuration File Structure
The system uses hierarchical YAML configuration in `config.yml`:

```yaml
default:
  database:
    path: "data/memory001_study.db"
    pool_size: 5
  auth:
    salt_env_var: "ZZEDC_SALT"
    session_timeout_minutes: 30

production:
  database:
    path: "/var/data/memory001_study_prod.db"
    pool_size: 10
  auth:
    default_salt: "secure_production_salt"
  app:
    debug: false
```

#### Environment Variables
Key environment variables for production deployment:
- `ZZEDC_ENV`: Environment name (development/production/testing)
- `ZZEDC_SALT`: Secure salt for password hashing
- `ZZEDC_DB_PATH`: Database file path
- `ZZEDC_LOG_LEVEL`: Logging level (DEBUG/INFO/WARN/ERROR)

### Security Configuration

#### Authentication Settings
```yaml
auth:
  max_failed_attempts: 3
  session_timeout_minutes: 30
  password_complexity:
    min_length: 8
    require_uppercase: true
    require_lowercase: true
    require_numbers: true
    require_special: true
```

#### SSL/TLS Configuration
For production deployments, implement SSL/TLS encryption:
1. Obtain SSL certificate from trusted Certificate Authority
2. Configure web server for HTTPS redirect
3. Implement HTTP Strict Transport Security (HSTS)
4. Configure secure cookie settings

### Database Configuration

#### SQLite Configuration
Default configuration uses SQLite for simplicity:
```yaml
database:
  type: "sqlite"
  path: "/var/data/zzedc/study.db"
  pool_size: 10
  connection_timeout: 30
```

#### PostgreSQL Configuration (Optional)
For enterprise deployments requiring enhanced scalability:
```yaml
database:
  type: "postgresql"
  host: "localhost"
  port: 5432
  database: "zzedc_production"
  username: "zzedc_user"
  password_env_var: "ZZEDC_DB_PASSWORD"
  pool_size: 20
```

#### Backup Configuration
```yaml
backup:
  enabled: true
  schedule: "0 2 * * *"  # Daily at 2 AM
  retention_days: 30
  destination: "/backup/zzedc/"
  encryption: true
```

## Regulatory Compliance Configuration

### GDPR Configuration
```yaml
gdpr:
  enabled: true
  legal_basis:
    regular_data: "legitimate_interest"
    special_category: "explicit_consent"
  retention:
    clinical_data: 300      # 25 years
    audit_logs: 84          # 7 years
  rights:
    enable_access: true
    enable_rectification: true
    enable_erasure: true
```

### 21 CFR Part 11 Configuration
```yaml
cfr_part11:
  enabled: true
  electronic_signatures:
    enabled: true
    validation_required: true
  audit_trail:
    enhanced_logging: true
    immutable_records: true
    hash_chaining: true
  validation:
    level: "operational"
    change_control: true
```

## Monitoring and Logging

### Application Monitoring
```yaml
monitoring:
  enabled: true
  metrics:
    - "response_time"
    - "user_sessions"
    - "database_connections"
    - "error_rate"
  alerts:
    email: "admin@yourorganization.org"
    thresholds:
      response_time: 5000  # milliseconds
      error_rate: 0.05     # 5%
```

### Logging Configuration
```yaml
logging:
  level: "INFO"
  file: "/var/log/zzedc/app.log"
  rotation:
    max_size: "100MB"
    max_files: 10
  audit_logging:
    enabled: true
    file: "/var/log/zzedc/audit.log"
```

## Performance Optimization

### Database Optimization
- Implement appropriate database indexes
- Configure connection pooling parameters
- Regular database maintenance and optimization
- Monitor query performance and optimize slow queries

### Application Optimization
- Enable caching for frequently accessed data
- Optimize reactive dependencies in Shiny applications
- Implement lazy loading for large datasets
- Configure appropriate session timeouts

### Infrastructure Optimization
- Implement load balancing for high availability
- Configure content delivery networks (CDN) for static assets
- Optimize network configuration and bandwidth
- Implement database replication for read scalability

## Backup and Recovery

### Backup Strategy
1. **Database Backups**: Automated daily backups with retention policy
2. **Configuration Backups**: Version control for configuration files
3. **Application Backups**: Complete application state preservation
4. **Log Backups**: Audit trail preservation for compliance

### Recovery Procedures
1. **Database Recovery**: Point-in-time recovery capabilities
2. **Application Recovery**: Rapid deployment from backups
3. **Configuration Recovery**: Environment restoration procedures
4. **Disaster Recovery**: Complete system restoration protocols

## Troubleshooting

### Common Issues

#### Database Connection Issues
- Verify database file permissions
- Check connection pool configuration
- Monitor database locks and transactions
- Validate database schema integrity

#### Authentication Problems
- Verify user credentials in database
- Check password hashing configuration
- Monitor failed login attempts
- Validate session management settings

#### Performance Issues
- Monitor memory usage and optimization
- Check database query performance
- Analyze network latency and bandwidth
- Review application logs for errors

### Diagnostic Tools
- Application performance monitoring
- Database performance analysis
- Network connectivity testing
- Log analysis and aggregation

## Maintenance Procedures

### Regular Maintenance Tasks
1. **Database Maintenance**: Index optimization, statistics updates
2. **Log Rotation**: Automated log cleanup and archival
3. **Security Updates**: Regular package and system updates
4. **Performance Monitoring**: Continuous system performance analysis

### Update Procedures
1. **Package Updates**: Scheduled R package updates
2. **Security Patches**: Emergency security update procedures
3. **Application Updates**: Version control and deployment procedures
4. **Configuration Updates**: Change control and validation procedures

---

## Conclusion

This deployment and configuration guide provides comprehensive instructions for implementing the ZZedc Electronic Data Capture system across various environments and deployment scenarios. Following these procedures ensures secure, scalable, and compliant deployment suitable for clinical research requirements while maintaining system reliability and performance standards.