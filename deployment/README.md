# ZZedc Deployment Guide

Complete deployment tools and documentation for ZZedc (Electronic Data Capture System).

**Status**: ✅ Production Ready
**Version**: 1.0
**Last Updated**: December 2025

---

## Quick Start (AWS Deployment)

Deploy ZZedc to AWS in 15 minutes:

```bash
# 1. Configure and run deployment script
chmod +x aws_setup.sh

./aws_setup.sh \
  --region us-west-2 \
  --study-name "Depression Trial" \
  --study-id "DEPR-2025-001" \
  --admin-password "SecurePass123!" \
  --domain trial.example.org \
  --instance-type t3.medium

# 2. Point your domain to the instance IP (returned by script)
# Add A record in your domain registrar

# 3. Access application when DNS propagates
# https://trial.example.org
```

For detailed AWS deployment instructions, see `IT_STAFF_DEPLOYMENT_CHECKLIST.md`.

---

## Files in This Directory

### Deployment Scripts

| File | Purpose | Use When |
|------|---------|----------|
| **aws_setup.sh** | Automated AWS EC2 deployment | Deploying to AWS (recommended for teams) |
| **Dockerfile** | Docker image definition | Building container (AWS or local) |
| **docker-compose.yml** | Container orchestration | Starting/managing containers |
| **Caddyfile** | HTTPS reverse proxy config | Setting up automatic HTTPS |

### Configuration Templates

| File | Purpose | Use When |
|------|---------|----------|
| **.env.template** | Environment variables template | Creating .env configuration file |

### Documentation

| File | Purpose | Audience |
|------|---------|----------|
| **IT_STAFF_DEPLOYMENT_CHECKLIST.md** | Step-by-step deployment verification | IT staff, cloud admins |
| **IT_STAFF_TROUBLESHOOTING.md** | Problem diagnosis and solutions | IT staff during troubleshooting |
| **README.md** (this file) | Directory overview | Everyone |

### Generated Files (After Deployment)

These files are created during deployment and should be secured:

| File | Purpose |
|------|---------|
| **.env** | Environment variables (SECRET - never commit) |
| **data/** | Database files (SQLite) |
| **logs/** | Application logs |
| **backups/** | Manual backup files |
| **config/** | Configuration files |
| **forms/** | Form definitions |

---

## Deployment Paths

### Path 1: Solo Researcher (Local Laptop)

**For**: Individual investigators, pilot studies, small deployments
**Cost**: $0 (just your laptop)
**Setup**: ~10 minutes

```r
# In R console
install.packages("zzedc")
library(zzedc)
zzedc::init()  # Interactive setup
launch_zzedc()  # Opens in browser
```

See: `vignettes/quick-start-solo-researcher.Rmd`

---

### Path 2: Team Research (AWS Single Server)

**For**: Research team, multi-site trials, production deployment
**Cost**: ~$30-50/month (EC2 + data)
**Setup**: ~20 minutes (plus DNS propagation)

**Files you'll use**:
1. `aws_setup.sh` - Automated deployment
2. `IT_STAFF_DEPLOYMENT_CHECKLIST.md` - Verification steps
3. `IT_STAFF_TROUBLESHOOTING.md` - Problem solving

**Process**:
```bash
# 1. Run AWS deployment
./aws_setup.sh --region us-west-2 --study-name "..." --domain trial.example.org

# 2. Follow checklist for verification
# IT_STAFF_DEPLOYMENT_CHECKLIST.md

# 3. Point domain to instance
# Add A record in domain registrar

# 4. Access application
# https://trial.example.org
```

See: `vignettes/quick-start-aws-devops.Rmd`

---

### Path 3: Local Docker Development

**For**: Testing, development, quick prototyping
**Cost**: $0 (your machine)
**Setup**: ~5 minutes (Docker required)

```bash
# Prepare directories
mkdir -p data logs backups config forms

# Configure environment
cp .env.template .env
# Edit .env with your values

# Configure Caddy
sed -i 's/DOMAIN_NAME/localhost/g' Caddyfile

# Build and start
docker-compose build
docker-compose up -d

# Monitor startup
docker-compose logs -f zzedc

# Access at http://localhost:3838 (or https if domain configured)
```

---

## Step-by-Step: AWS Deployment with Checklist

### Prerequisites Checklist
- [ ] AWS account created
- [ ] AWS CLI installed and configured
- [ ] Domain name registered
- [ ] Study information prepared
  - [ ] Study name
  - [ ] Study protocol ID
  - [ ] PI email
  - [ ] Admin password

### Deployment Steps

**1. Run aws_setup.sh**
```bash
chmod +x aws_setup.sh
./aws_setup.sh \
  --region us-west-2 \
  --study-name "Your Study" \
  --study-id "STUDY-2025" \
  --admin-password "SecurePass123!" \
  --domain trial.example.org
```

**2. Note the output:**
- Instance ID (e.g., `i-0a1b2c3d4e5f6g7h8`)
- Public IP (e.g., `54.xxx.xxx.xxx`)
- Security Group ID
- Key pair name

**3. Configure domain DNS**
- Log into domain registrar
- Add A record: `trial.example.org` → `54.xxx.xxx.xxx`
- Wait for DNS propagation (up to 24 hours)

**4. Follow IT_STAFF_DEPLOYMENT_CHECKLIST.md**
- Verify AWS resources created
- Test SSH access
- Monitor Docker startup
- Verify HTTPS certificate
- Test application login

**5. Perform post-deployment verification**
- Test user login (admin credentials)
- Create test data entry
- Verify data persists after restart
- Check backup/restore works

---

## Configuration Guide

### Environment Variables (.env file)

Required variables (see `.env.template` for full reference):

```bash
# Security salt (unique per deployment, generated)
ZZEDC_SALT=a7f9e2c4d1b3f8a6e9d2c5b8f1a4e7d0

# Study information
STUDY_NAME="Depression Treatment Trial"
STUDY_ID="DEPR-2025-001"
PI_EMAIL="pi@institution.edu"

# Admin account (initial login)
ADMIN_PASSWORD="SecurePassword123!"

# Application settings
LOG_LEVEL="info"
```

**To create .env file:**
```bash
cp .env.template .env
# Edit .env with your values
chmod 600 .env  # Secure permissions
```

### Caddyfile Configuration

Edit `Caddyfile` and replace `DOMAIN_NAME` with your actual domain:

```bash
sed -i 's/DOMAIN_NAME/trial.example.org/g' Caddyfile
```

Or manually edit:
```
DOMAIN_NAME {
    reverse_proxy localhost:3838
}
```

→ becomes:

```
trial.example.org {
    reverse_proxy localhost:3838
}
```

---

## Docker Compose Commands

### Startup and Monitoring

```bash
# Build images
docker-compose build

# Start services
docker-compose up -d

# Check status
docker-compose ps

# View logs (all services)
docker-compose logs

# Follow logs in real-time
docker-compose logs -f

# View logs for specific service
docker-compose logs zzedc
docker-compose logs caddy
```

### Maintenance

```bash
# Restart a service
docker-compose restart zzedc
docker-compose restart caddy

# Restart everything
docker-compose restart

# Stop containers (preserves volumes)
docker-compose stop

# Start containers
docker-compose start

# Stop and remove containers (preserves volumes)
docker-compose down

# Full cleanup (WARNING: removes volumes!)
docker-compose down -v
```

### Debugging

```bash
# Access container shell
docker-compose exec zzedc bash
docker-compose exec caddy bash

# Run commands in container
docker-compose exec zzedc R --version
docker-compose exec zzedc sqlite3 /app/data/zzedc.db ".tables"

# View resource usage
docker stats

# Check certificate status
docker-compose logs caddy | grep certificate
```

---

## Common Tasks

### Backup Data

```bash
# Manual backup
docker-compose exec zzedc tar -czf /tmp/backup-$(date +%Y%m%d).tar.gz /app/data/

# Copy backup locally
docker-compose cp zzedc:/tmp/backup-*.tar.gz ./backups/

# Or upload to S3
aws s3 cp ./backups/backup-*.tar.gz s3://my-backup-bucket/zzedc/
```

### Update Domain/Certificate

```bash
# Edit Caddyfile
nano Caddyfile

# Reload Caddy (no downtime)
docker-compose exec caddy caddy reload --config /etc/caddy/Caddyfile

# Verify
docker-compose logs caddy | grep certificate
```

### Restart Application After Configuration Change

```bash
# Stop services
docker-compose stop

# Make configuration changes
# (edit .env, Caddyfile, etc.)

# Start again
docker-compose up -d

# Monitor startup
docker-compose logs -f
```

### Monitor Resources

```bash
# Real-time resource usage
docker stats

# Check disk usage
df -h data/ logs/ backups/

# Check container sizes
docker ps --size
```

---

## Security Checklist

Before going live:

- [ ] `.env` file has restrictive permissions: `chmod 600 .env`
- [ ] `.env` is listed in `.gitignore` (never commit)
- [ ] Security salt (`ZZEDC_SALT`) is unique and kept secret
- [ ] Admin password is strong and changed after first login
- [ ] HTTPS is working (certificate should be from Let's Encrypt)
- [ ] Database backups are tested and working
- [ ] Access logs are being monitored
- [ ] Regular backups scheduled (daily recommended)
- [ ] Disaster recovery plan in place

---

## Troubleshooting

See `IT_STAFF_TROUBLESHOOTING.md` for comprehensive troubleshooting guide.

### Quick Fixes

**Containers won't start:**
```bash
docker-compose logs zzedc
docker-compose logs caddy
# Look for error messages
```

**HTTPS not working:**
```bash
# Verify domain resolves
nslookup trial.example.org

# Check Caddy logs
docker-compose logs caddy | grep certificate

# Verify DNS points to this server's IP
# Verify ports 80 and 443 are open
```

**Port conflicts:**
```bash
# Find what's using the port
sudo netstat -tlnp | grep 80
sudo netstat -tlnp | grep 443
```

**Database errors:**
```bash
# Check database file
docker-compose exec zzedc ls -la /app/data/zzedc.db

# Verify database integrity
docker-compose exec zzedc sqlite3 /app/data/zzedc.db "PRAGMA integrity_check;"
```

---

## Support and Resources

### Documentation
- **Solo Researcher Setup**: See `vignettes/quick-start-solo-researcher.Rmd`
- **AWS/DevOps Setup**: See `vignettes/quick-start-aws-devops.Rmd`
- **Deployment Checklist**: See `IT_STAFF_DEPLOYMENT_CHECKLIST.md`
- **Troubleshooting**: See `IT_STAFF_TROUBLESHOOTING.md`

### External Resources
- **ZZedc GitHub**: https://github.com/rgt47/zzedc
- **Docker Documentation**: https://docs.docker.com/
- **Caddy Documentation**: https://caddyserver.com/docs/
- **AWS EC2 Documentation**: https://docs.aws.amazon.com/ec2/

### Contact
- **Email**: rgthomas@ucsd.edu
- **GitHub Issues**: https://github.com/rgt47/zzedc/issues

---

## File Manifest

```
deployment/
├── README.md                              (this file)
├── aws_setup.sh                           (AWS automated deployment - EXECUTABLE)
├── Dockerfile                             (Docker image definition)
├── docker-compose.yml                     (Container orchestration)
├── Caddyfile                              (HTTPS reverse proxy config)
├── .env.template                          (Environment variables template)
├── IT_STAFF_DEPLOYMENT_CHECKLIST.md       (QA checklist for deployment)
└── IT_STAFF_TROUBLESHOOTING.md            (Comprehensive troubleshooting guide)

data/                                      (Database files - created at runtime)
logs/                                      (Application logs - created at runtime)
backups/                                   (Backup files - created at runtime)
config/                                    (Configuration files - created at runtime)
forms/                                     (Form definitions - created at runtime)
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Dec 2025 | Initial production release |

---

## License

ZZedc is open source. See repository for license details.

---

## Quick Links

- **Deploy to AWS**: Run `./aws_setup.sh --help` for options
- **Configure environment**: Copy `.env.template` to `.env` and edit
- **Verify deployment**: Follow `IT_STAFF_DEPLOYMENT_CHECKLIST.md`
- **Troubleshoot issues**: See `IT_STAFF_TROUBLESHOOTING.md`
- **Learn more**: Visit https://github.com/rgt47/zzedc

---

**Ready to deploy? Start with `aws_setup.sh` or follow the deployment checklist!**

