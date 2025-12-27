# HTTPS/TLS Deployment Guide

This document provides comprehensive guidance for deploying ZZedc with
HTTPS/TLS encryption to ensure secure data transmission. This addresses
GDPR Article 32 requirements for security of processing.

## Overview

ZZedc, as a Shiny application, does not handle TLS termination directly.
Instead, secure deployment requires a reverse proxy (nginx or Apache)
that handles SSL/TLS termination and forwards requests to the Shiny
application.

## Architecture

```
┌─────────────┐     HTTPS     ┌─────────────┐     HTTP      ┌─────────────┐
│   Client    │──────────────>│   nginx/    │──────────────>│   Shiny     │
│   Browser   │    (443)      │   Apache    │   (3838)      │   Server    │
└─────────────┘               └─────────────┘               └─────────────┘
                                    │
                              ┌─────┴─────┐
                              │ SSL Cert  │
                              │ (Let's    │
                              │  Encrypt) │
                              └───────────┘
```

## Prerequisites

- Domain name pointing to your server
- Root or sudo access to the server
- Shiny Server running on localhost:3838
- Firewall allowing ports 80 and 443

## Option 1: nginx Configuration

### Installation

**Ubuntu/Debian**
```bash
sudo apt update
sudo apt install nginx certbot python3-certbot-nginx
```

**Amazon Linux/CentOS**
```bash
sudo yum install nginx certbot python3-certbot-nginx
```

### nginx Configuration File

Create `/etc/nginx/sites-available/zzedc`:
```nginx
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name your-domain.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name your-domain.com;

    # SSL Certificate (Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # SSL Configuration (Mozilla Intermediate)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS (Strict Transport Security)
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' wss:; frame-ancestors 'self';" always;

    # Logging
    access_log /var/log/nginx/zzedc_access.log;
    error_log /var/log/nginx/zzedc_error.log;

    # Proxy settings for Shiny
    location / {
        proxy_pass http://127.0.0.1:3838;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_buffering off;

        # Secure cookie settings
        proxy_cookie_path / "/; HTTPOnly; Secure; SameSite=Strict";
    }

    # WebSocket support for Shiny
    location /websocket/ {
        proxy_pass http://127.0.0.1:3838;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }
}
```

### Enable the Configuration

```bash
sudo ln -s /etc/nginx/sites-available/zzedc /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Obtain SSL Certificate

```bash
sudo certbot --nginx -d your-domain.com
```

### Automatic Certificate Renewal

Certbot installs a cron job automatically. Verify with:
```bash
sudo certbot renew --dry-run
```

## Option 2: Apache Configuration

### Installation

**Ubuntu/Debian**
```bash
sudo apt update
sudo apt install apache2 certbot python3-certbot-apache
sudo a2enmod ssl proxy proxy_http proxy_wstunnel headers rewrite
```

**Amazon Linux/CentOS**
```bash
sudo yum install httpd mod_ssl certbot python3-certbot-apache
```

### Apache Configuration File

Create `/etc/apache2/sites-available/zzedc.conf`:
```apache
# Redirect HTTP to HTTPS
<VirtualHost *:80>
    ServerName your-domain.com

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>

# HTTPS VirtualHost
<VirtualHost *:443>
    ServerName your-domain.com

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/your-domain.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/your-domain.com/privkey.pem

    # SSL Protocols and Ciphers (Mozilla Intermediate)
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder off

    # Security Headers
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' wss:;"

    # Logging
    ErrorLog ${APACHE_LOG_DIR}/zzedc_error.log
    CustomLog ${APACHE_LOG_DIR}/zzedc_access.log combined

    # Proxy to Shiny Server
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3838/
    ProxyPassReverse / http://127.0.0.1:3838/

    # WebSocket support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*) ws://127.0.0.1:3838/$1 [P,L]

    # Secure cookies
    Header edit Set-Cookie ^(.*)$ "$1; HTTPOnly; Secure; SameSite=Strict"
</VirtualHost>
```

### Enable the Configuration

```bash
sudo a2ensite zzedc.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

### Obtain SSL Certificate

```bash
sudo certbot --apache -d your-domain.com
```

## Option 3: Docker with Traefik

For containerized deployments, use Traefik as a reverse proxy with
automatic Let's Encrypt certificates.

### docker-compose.yml

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=admin@your-domain.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt:/letsencrypt"
    networks:
      - web

  zzedc:
    build: .
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.zzedc.rule=Host(`your-domain.com`)"
      - "traefik.http.routers.zzedc.entrypoints=websecure"
      - "traefik.http.routers.zzedc.tls.certresolver=letsencrypt"
      - "traefik.http.services.zzedc.loadbalancer.server.port=3838"
      # HTTP to HTTPS redirect
      - "traefik.http.routers.zzedc-http.rule=Host(`your-domain.com`)"
      - "traefik.http.routers.zzedc-http.entrypoints=web"
      - "traefik.http.routers.zzedc-http.middlewares=https-redirect"
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"
      # Security headers
      - "traefik.http.middlewares.security-headers.headers.stsSeconds=63072000"
      - "traefik.http.middlewares.security-headers.headers.stsIncludeSubdomains=true"
      - "traefik.http.middlewares.security-headers.headers.frameDeny=true"
      - "traefik.http.middlewares.security-headers.headers.contentTypeNosniff=true"
      - "traefik.http.routers.zzedc.middlewares=security-headers"
    environment:
      - DB_ENCRYPTION_KEY=${DB_ENCRYPTION_KEY}
    volumes:
      - ./data:/srv/shiny-server/data
    networks:
      - web

networks:
  web:
    external: true
```

## Option 4: AWS Application Load Balancer

For AWS deployments, use Application Load Balancer (ALB) with
AWS Certificate Manager (ACM).

### Terraform Configuration

```hcl
resource "aws_lb" "zzedc" {
  name               = "zzedc-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.zzedc.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.zzedc.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.zzedc.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.zzedc.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_acm_certificate" "zzedc" {
  domain_name       = "your-domain.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
```

## Security Headers Reference

### Required Headers for GDPR Compliance

| Header | Value | Purpose |
|--------|-------|---------|
| Strict-Transport-Security | max-age=63072000; includeSubDomains | Force HTTPS |
| X-Frame-Options | SAMEORIGIN | Prevent clickjacking |
| X-Content-Type-Options | nosniff | Prevent MIME sniffing |
| X-XSS-Protection | 1; mode=block | XSS filter |
| Referrer-Policy | strict-origin-when-cross-origin | Control referrer |
| Content-Security-Policy | (see config) | Prevent XSS/injection |

### Cookie Security Flags

All session cookies must include:

- `HTTPOnly` - Prevent JavaScript access
- `Secure` - Only transmit over HTTPS
- `SameSite=Strict` - Prevent CSRF attacks

## Verification

### Test SSL Configuration

Use SSL Labs to verify configuration:
```
https://www.ssllabs.com/ssltest/analyze.html?d=your-domain.com
```

Target grade: A or A+

### Verify Headers

```bash
curl -I https://your-domain.com
```

Expected output includes all security headers.

### Test HTTPS Redirect

```bash
curl -I http://your-domain.com
```

Expected: HTTP 301 redirect to https://

### Test WebSocket Connection

Open browser developer tools, navigate to the application, and verify
WebSocket connections use `wss://` protocol.

## Monitoring

### Certificate Expiration

Monitor certificate expiration:
```bash
echo | openssl s_client -servername your-domain.com -connect your-domain.com:443 2>/dev/null | openssl x509 -noout -dates
```

### Log Monitoring

Monitor for SSL errors:
```bash
tail -f /var/log/nginx/zzedc_error.log | grep -i ssl
```

## Troubleshooting

### Certificate Issues

**Problem**: Certificate not trusted

**Solution**:
```bash
sudo certbot certificates
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

### WebSocket Connection Failures

**Problem**: Real-time updates not working

**Solution**: Verify WebSocket proxy configuration and upgrade headers.

### Mixed Content Warnings

**Problem**: Browser shows mixed content warnings

**Solution**: Ensure all resources use HTTPS URLs. Check for hardcoded
HTTP URLs in application code.

## Compliance Checklist

- [ ] HTTPS enforced (HTTP redirects to HTTPS)
- [ ] Valid SSL certificate installed
- [ ] TLS 1.2 or higher only
- [ ] HSTS header configured
- [ ] Security headers configured
- [ ] Secure cookie flags set
- [ ] SSL Labs grade A or higher
- [ ] Certificate auto-renewal configured
- [ ] WebSocket connections use WSS

## Related Documentation

- [Encryption Deployment Guide](ENCRYPTION_DEPLOYMENT_GUIDE.md)
- [Encryption Troubleshooting](ENCRYPTION_TROUBLESHOOTING.md)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
