# ZZedc Deployment Configurations

This directory contains production-ready deployment configurations for
ZZedc with HTTPS/TLS encryption.

## Directory Structure

```
deployment/
├── nginx/
│   └── zzedc.conf          # nginx reverse proxy configuration
├── apache/
│   └── zzedc.conf          # Apache reverse proxy configuration
├── docker/
│   ├── Dockerfile          # Docker image definition
│   ├── docker-compose.yml  # Docker Compose with Traefik
│   └── shiny-server.conf   # Shiny Server configuration
└── README.md               # This file
```

## Quick Start

### Option 1: nginx (Recommended for Linux servers)

```bash
# Install nginx and certbot
sudo apt install nginx certbot python3-certbot-nginx

# Copy configuration
sudo cp nginx/zzedc.conf /etc/nginx/sites-available/

# Edit configuration (replace YOUR_DOMAIN)
sudo nano /etc/nginx/sites-available/zzedc.conf

# Enable site
sudo ln -s /etc/nginx/sites-available/zzedc.conf /etc/nginx/sites-enabled/

# Obtain SSL certificate
sudo certbot --nginx -d your-domain.com

# Reload nginx
sudo nginx -t && sudo systemctl reload nginx
```

### Option 2: Apache

```bash
# Install Apache and certbot
sudo apt install apache2 certbot python3-certbot-apache

# Enable required modules
sudo a2enmod ssl proxy proxy_http proxy_wstunnel headers rewrite

# Copy configuration
sudo cp apache/zzedc.conf /etc/apache2/sites-available/

# Edit configuration (replace YOUR_DOMAIN)
sudo nano /etc/apache2/sites-available/zzedc.conf

# Enable site
sudo a2ensite zzedc.conf

# Obtain SSL certificate
sudo certbot --apache -d your-domain.com

# Reload Apache
sudo apache2ctl configtest && sudo systemctl reload apache2
```

### Option 3: Docker with Traefik

```bash
# Create external network
docker network create web

# Create environment file
echo "DB_ENCRYPTION_KEY=$(Rscript -e 'cat(zzedc::generate_db_key())')" > .env

# Edit docker-compose.yml (replace YOUR_DOMAIN and YOUR_EMAIL)
nano docker/docker-compose.yml

# Start services
cd docker
docker-compose up -d

# View logs
docker-compose logs -f
```

## Configuration Checklist

Before deployment, ensure:

- Domain name configured and pointing to server
- Replace YOUR_DOMAIN in configuration files
- Replace YOUR_EMAIL in Docker Compose (for Let's Encrypt)
- Set DB_ENCRYPTION_KEY environment variable
- Firewall allows ports 80 and 443
- Shiny Server running on port 3838

## Security Verification

After deployment, verify:

```bash
# Test HTTPS redirect
curl -I http://your-domain.com

# Test SSL certificate
curl -I https://your-domain.com

# Test security headers
curl -I https://your-domain.com | grep -E "(Strict-Transport|X-Frame|X-Content)"

# SSL Labs test
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=your-domain.com
```

## Troubleshooting

### Certificate Issues

```bash
# Check certificate status
sudo certbot certificates

# Force renewal
sudo certbot renew --force-renewal
```

### Connection Issues

```bash
# Check nginx configuration
sudo nginx -t

# Check Apache configuration
sudo apache2ctl configtest

# Check Shiny Server status
sudo systemctl status shiny-server
```

### Docker Issues

```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs zzedc

# Restart services
docker-compose restart
```

## Related Documentation

- HTTPS/TLS Deployment Guide: ../docs/HTTPS_TLS_DEPLOYMENT_GUIDE.md
- Encryption Deployment Guide: ../docs/ENCRYPTION_DEPLOYMENT_GUIDE.md
- Encryption Troubleshooting: ../docs/ENCRYPTION_TROUBLESHOOTING.md
