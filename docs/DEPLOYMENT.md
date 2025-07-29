# Comprehensive Deployment Guide

**⚠️ IMPORTANT: As of July 29, 2025, this project has migrated to Kubernetes. The Docker Compose infrastructure described below has been decommissioned. For current deployment instructions, see [K8S_MIGRATION_PLAN.md](./K8S_MIGRATION_PLAN.md)**

---

## Legacy Docker Compose Documentation

This guide covers the previous Docker Compose infrastructure that was used before the Kubernetes migration. It is kept for historical reference.

## Table of Contents

1. [Setting Up Infrastructure on a Fresh AWS Account](#1-setting-up-infrastructure-on-a-fresh-aws-account)
2. [Adding a New Application](#2-adding-a-new-application)
3. [Deploying Application Updates](#3-deploying-application-updates)
4. [Infrastructure Management](#4-infrastructure-management)
5. [SSL Certificate Management](#5-ssl-certificate-management)
6. [Auto-Recovery Setup](#6-auto-recovery-setup)
7. [Monitoring and Troubleshooting](#7-monitoring-and-troubleshooting)
8. [Cost Optimization](#8-cost-optimization)
9. [Security Best Practices](#9-security-best-practices)
10. [Emergency Procedures](#10-emergency-procedures)

## 1. Setting Up Infrastructure on a Fresh AWS Account

### Prerequisites

#### Local Machine Requirements
- Docker and Docker Compose installed
- AWS CLI installed and configured
- Git installed
- SSH client

#### AWS Account Setup
1. Create an AWS account
2. Create an IAM user with programmatic access:
   ```bash
   # Required permissions:
   - EC2: Full access (for spot instances)
   - Route53: Full access (for DNS management)
   - IAM: Limited (for certbot DNS validation)
   ```

3. Configure AWS CLI with the new profile:
   ```bash
   aws configure --profile bf
   # Enter your Access Key ID
   # Enter your Secret Access Key
   # Default region: us-east-1 (or your preferred region)
   # Output format: json
   ```

### Step 1: Create Route53 Hosted Zone

1. Register your domain or transfer it to Route53
2. Create a hosted zone:
   ```bash
   aws route53 create-hosted-zone \
     --name vadimzak.com \
     --caller-reference "initial-setup-$(date +%s)" \
     --profile bf
   ```
3. Note the Hosted Zone ID (update in scripts if different from Z2O129XK0SJBV9)
4. Update your domain's nameservers to Route53's nameservers

### Step 2: Launch EC2 Spot Instance

1. Create a key pair:
   ```bash
   aws ec2 create-key-pair \
     --key-name sample-app-key \
     --query 'KeyMaterial' \
     --output text \
     --profile bf > ~/.ssh/sample-app-key.pem
   
   chmod 400 ~/.ssh/sample-app-key.pem
   ```

2. Create security group:
   ```bash
   aws ec2 create-security-group \
     --group-name sample-app-sg \
     --description "Security group for sample app" \
     --profile bf
   
   # Get the security group ID from output
   SG_ID=sg-xxxxxxxxx
   
   # Allow SSH, HTTP, and HTTPS
   aws ec2 authorize-security-group-ingress \
     --group-id $SG_ID \
     --protocol tcp --port 22 --cidr 0.0.0.0/0 \
     --profile bf
   
   aws ec2 authorize-security-group-ingress \
     --group-id $SG_ID \
     --protocol tcp --port 80 --cidr 0.0.0.0/0 \
     --profile bf
   
   aws ec2 authorize-security-group-ingress \
     --group-id $SG_ID \
     --protocol tcp --port 443 --cidr 0.0.0.0/0 \
     --profile bf
   ```

3. Launch spot instance:
   ```bash
   # Create spot instance request
   aws ec2 run-instances \
     --image-id ami-0c02fb55956c7d316 \  # Amazon Linux 2 AMI (update for your region)
     --instance-type t3.micro \
     --key-name sample-app-key \
     --security-group-ids $SG_ID \
     --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"persistent","InstanceInterruptionBehavior":"stop"}}' \
     --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=sample-app-server}]' \
     --profile bf
   ```

4. Get the public IP and update it in scripts (if different from 51.16.33.8)

### Step 3: Configure EC2 Instance

1. SSH into the instance:
   ```bash
   ssh -i ~/.ssh/sample-app-key.pem ec2-user@<PUBLIC_IP>
   ```

2. Install Docker and Docker Compose:
   ```bash
   # Update system
   sudo yum update -y
   
   # Install Docker
   sudo yum install -y docker
   sudo systemctl start docker
   sudo systemctl enable docker
   sudo usermod -a -G docker ec2-user
   
   # Install Docker Compose
   sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   
   # Logout and login again for group changes
   exit
   ```

3. Set up directory structure:
   ```bash
   ssh -i ~/.ssh/sample-app-key.pem ec2-user@<PUBLIC_IP>
   
   # Create base directories
   sudo mkdir -p /var/www
   sudo chown ec2-user:ec2-user /var/www
   mkdir -p /var/www/ssl
   ```

### Step 4: Set Up Wildcard SSL Certificate

1. Install certbot on the server:
   ```bash
   sudo yum install -y certbot python3-certbot-dns-route53
   ```

2. Create IAM policy for certbot:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "route53:ListHostedZones",
           "route53:GetChange"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "route53:ChangeResourceRecordSets"
         ],
         "Resource": "arn:aws:route53:::hostedzone/Z2O129XK0SJBV9"
       }
     ]
   }
   ```

3. Attach the policy to an IAM user and configure AWS credentials on the server

4. Generate wildcard certificate:
   ```bash
   sudo certbot certonly \
     --dns-route53 \
     --agree-tos \
     --email your-email@example.com \
     -d "*.vadimzak.com" \
     -d "vadimzak.com"
   
   # Copy certificates to the expected location
   sudo cp /etc/letsencrypt/live/vadimzak.com/fullchain.pem /var/www/ssl/
   sudo cp /etc/letsencrypt/live/vadimzak.com/privkey.pem /var/www/ssl/
   sudo chown ec2-user:ec2-user /var/www/ssl/*
   ```

### Step 5: Deploy Infrastructure Services

1. Clone the repository locally:
   ```bash
   git clone <your-repo-url> bf-backend
   cd bf-backend
   ```

2. Create the shared Docker network on the server:
   ```bash
   ./scripts/remote-exec.sh "docker network create sample-app_app-network"
   ```

3. Deploy infrastructure services:
   ```bash
   # Copy infrastructure files
   scp -i ~/.ssh/sample-app-key.pem \
     scripts/docker-compose-infra.yml \
     ec2-user@<PUBLIC_IP>:/var/www/
   
   # Start infrastructure services
   ./scripts/manage-infra.sh start
   ```

### Step 6: Deploy Your First App

1. Ensure sample-app exists in the repository
2. Deploy it:
   ```bash
   ./scripts/deploy-app.sh sample-app "Initial deployment"
   ```

### Step 7: Set Up Auto-Recovery

Set up the auto-recovery service to handle spot instance interruptions:
```bash
./scripts/setup-auto-recovery.sh
```

Verify it's working:
```bash
./scripts/check-recovery-status.sh
```

## 2. Adding a New Application

### Option A: Create App Structure Manually

1. Create the app directory:
   ```bash
   mkdir -p apps/my-new-app
   cd apps/my-new-app
   ```

2. Create minimal Express server (`server.js`):
   ```javascript
   const express = require('express');
   const app = express();
   const PORT = process.env.PORT || 3002;

   app.get('/health', (req, res) => {
     res.json({ status: 'healthy', app: 'my-new-app' });
   });

   app.get('/', (req, res) => {
     res.send('Welcome to My New App!');
   });

   app.listen(PORT, () => {
     console.log(`Server running on port ${PORT}`);
   });
   ```

3. Create `package.json`:
   ```json
   {
     "name": "my-new-app",
     "version": "1.0.0",
     "scripts": {
       "start": "node server.js",
       "dev": "nodemon server.js"
     },
     "dependencies": {
       "express": "^4.18.2"
     },
     "devDependencies": {
       "nodemon": "^3.0.1"
     }
   }
   ```

4. Create `Dockerfile`:
   ```dockerfile
   FROM node:18-alpine
   WORKDIR /app
   COPY package*.json ./
   RUN npm ci --only=production
   COPY . .
   EXPOSE 3002
   CMD ["npm", "start"]
   ```

5. Create `docker-compose.prod.yml`:
   ```yaml
   version: '3.8'
   services:
     app:
       image: my-new-app:latest
       container_name: my-new-app-green
       restart: unless-stopped
       ports:
         - "3002:3002"
       environment:
         - NODE_ENV=production
         - PORT=3002
       healthcheck:
         test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3002/health"]
         interval: 30s
         timeout: 10s
         retries: 3
         start_period: 40s
       networks:
         - app-network
       logging:
         driver: "json-file"
         options:
           max-size: "10m"
           max-file: "3"

   networks:
     app-network:
       external: true
       name: sample-app_app-network
   ```

6. Create `deploy.config`:
   ```bash
   APP_PORT=3002
   APP_DOMAIN=my-new-app.vadimzak.com
   ```

7. Create deployment script link:
   ```bash
   ln -s ../../scripts/deploy-app.sh deploy.sh
   chmod +x deploy.sh
   ```

### Option B: Copy from Existing App

1. Copy an existing app as template:
   ```bash
   cp -r apps/sample-app apps/my-new-app
   cd apps/my-new-app
   ```

2. Update `deploy.config`:
   ```bash
   APP_PORT=3002  # Use next available port
   APP_DOMAIN=my-new-app.vadimzak.com
   ```

3. Update app-specific files:
   - Modify `package.json` name
   - Update `docker-compose.prod.yml` service names and ports
   - Adjust server code as needed

### Step 2: Prepare Infrastructure

Run the infrastructure preparation script:
```bash
./scripts/prep-app-infra.sh my-new-app
```

This will:
- Create DNS A record pointing to the EC2 instance
- Update nginx configuration with the new app
- Reload nginx configuration

### Step 3: Deploy the App

Deploy your new app:
```bash
./scripts/deploy-app.sh my-new-app "Initial deployment of my-new-app"
```

Or deploy directly from prep script:
```bash
./scripts/prep-app-infra.sh my-new-app --deploy
```

## 3. Deploying Application Updates

### Standard Deployment

The deployment system uses blue-green deployment for zero downtime:

```bash
# From project root (recommended)
./scripts/deploy-app.sh app-name "Description of changes"

# From app directory
cd apps/app-name
./deploy.sh "Fix authentication bug"
```

### Deployment Options

#### Dry Run Mode
Test what would be deployed without making changes:
```bash
./scripts/deploy-app.sh app-name --dry-run
```

#### Rollback
Rollback to the previous deployment:
```bash
./scripts/deploy-app.sh app-name --rollback
```

#### Force Deploy
Skip safety checks (use with caution):
```bash
./scripts/deploy-app.sh app-name --force "Emergency fix"
```

### Deployment Process

1. **Pre-deployment Checks:**
   - Docker daemon status
   - SSH connectivity
   - Git status (warns about uncommitted changes)
   - Current deployment health check

2. **Build Phase:**
   - Auto-commits changes with provided message
   - Builds Docker image for linux/amd64
   - Tags with git commit hash and 'latest'

3. **Transfer Phase:**
   - Compresses Docker image
   - Transfers via SCP to server
   - Validates transfer integrity

4. **Deployment Phase:**
   - Starts new container (green/blue)
   - Waits for health check
   - Updates nginx configuration
   - Stops old container
   - Cleans up old images (keeps latest 3)

5. **Post-deployment:**
   - Comprehensive health checks
   - HTTPS redirect verification
   - Container status check
   - Automatic rollback on failure

### Best Practices

1. **Always provide meaningful commit messages:**
   ```bash
   ./scripts/deploy-app.sh app-name "Add user authentication feature"
   ```

2. **Test locally first:**
   ```bash
   cd apps/app-name
   npm run dev
   # Test your changes
   ```

3. **Use dry-run for major changes:**
   ```bash
   ./scripts/deploy-app.sh app-name --dry-run
   ```

4. **Monitor logs after deployment:**
   ```bash
   ./scripts/server-ops.sh logs app-name
   ```

## 4. Infrastructure Management

### Managing Shared Services

The infrastructure consists of shared services (nginx, watchtower) that run independently of applications:

#### Start Infrastructure
```bash
./scripts/manage-infra.sh start
```

#### Stop Infrastructure
```bash
./scripts/manage-infra.sh stop
```

#### Restart Infrastructure
```bash
./scripts/manage-infra.sh restart
```

#### Check Status
```bash
./scripts/manage-infra.sh status
```

#### View Logs
```bash
# All infrastructure logs
./scripts/manage-infra.sh logs

# Specific service logs
./scripts/manage-infra.sh logs nginx
./scripts/manage-infra.sh logs watchtower
```

#### Reload Nginx (No Downtime)
```bash
./scripts/manage-infra.sh reload-nginx
```

### Docker Network Management

All applications share a common Docker network for inter-container communication:

```bash
# View network details
./scripts/remote-exec.sh "docker network inspect sample-app_app-network"

# List connected containers
./scripts/remote-exec.sh "docker network inspect sample-app_app-network | grep -A 3 Containers"
```

### Nginx Configuration

Nginx serves as the reverse proxy for all applications:

1. **Configuration Location:**
   - Server: `/var/www/nginx.conf`
   - Container: `/etc/nginx/nginx.conf`

2. **Configuration Structure:**
   ```nginx
   # Default catch-all server
   server {
       listen 80 default_server;
       server_name _;
       return 301 https://$host$request_uri;
   }

   # Per-app server blocks
   server {
       listen 443 ssl;
       server_name app.vadimzak.com;
       
       ssl_certificate /etc/ssl/fullchain.pem;
       ssl_certificate_key /etc/ssl/privkey.pem;
       
       location / {
           proxy_pass http://app-container:3001;
           # ... proxy settings
       }
   }
   ```

3. **Adding Manual Nginx Config:**
   ```bash
   # Edit nginx config
   ./scripts/remote-exec.sh "nano /var/www/nginx.conf"
   
   # Reload configuration
   ./scripts/manage-infra.sh reload-nginx
   ```

## 5. SSL Certificate Management

### Wildcard Certificate Details

The infrastructure uses a single wildcard certificate for all subdomains:
- Certificate: `*.vadimzak.com`
- Location on server: `/var/www/ssl/`
- Mounted in nginx: `/etc/ssl/`
- Covers all app subdomains automatically

### Manual Certificate Renewal

Run the renewal script:
```bash
./scripts/renew-wildcard-cert.sh
```

This script:
1. Connects to EC2 via SSH
2. Runs certbot renewal with Route53 DNS validation
3. Copies renewed certificates to `/var/www/ssl/`
4. Restarts nginx to apply new certificates

### Automatic Renewal Setup

Set up a cron job on the server:
```bash
./scripts/remote-exec.sh "crontab -e"

# Add this line for weekly renewal attempts
0 2 * * 0 /home/ec2-user/renew-cert.sh >> /var/log/cert-renewal.log 2>&1
```

Create the renewal script on server:
```bash
./scripts/remote-exec.sh "cat > /home/ec2-user/renew-cert.sh << 'EOF'
#!/bin/bash
sudo certbot renew --dns-route53
sudo cp /etc/letsencrypt/live/vadimzak.com/*.pem /var/www/ssl/
docker exec sample-app-nginx-1 nginx -s reload
EOF"

./scripts/remote-exec.sh "chmod +x /home/ec2-user/renew-cert.sh"
```

### Certificate Troubleshooting

1. **Check certificate expiry:**
   ```bash
   ./scripts/remote-exec.sh "openssl x509 -in /var/www/ssl/fullchain.pem -noout -dates"
   ```

2. **Verify nginx is using correct certificates:**
   ```bash
   ./scripts/remote-exec.sh "docker exec sample-app-nginx-1 ls -la /etc/ssl/"
   ```

3. **Test SSL configuration:**
   ```bash
   curl -I https://your-app.vadimzak.com
   ```

## 6. Auto-Recovery Setup

The auto-recovery service ensures applications automatically restart after spot instance interruptions.

### Installation

```bash
./scripts/setup-auto-recovery.sh
```

This creates a systemd service that:
- Starts on system boot
- Discovers all deployed applications
- Starts each application's containers
- Monitors recovery progress

### Monitoring Recovery Status

```bash
./scripts/check-recovery-status.sh
```

Output shows:
- Service status
- Registered applications
- Recovery readiness
- Recent recovery logs

### Manual Recovery Operations

```bash
# Start recovery service
./scripts/remote-exec.sh "sudo systemctl start app-recovery"

# Stop recovery service
./scripts/remote-exec.sh "sudo systemctl stop app-recovery"

# View recovery logs
./scripts/remote-exec.sh "sudo journalctl -u app-recovery -n 50"

# Trigger manual recovery
./scripts/remote-exec.sh "sudo /usr/local/bin/recover-apps.sh"
```

### Adding Apps to Recovery

Apps are automatically discovered if they have:
- Directory in `/var/www/app-name/`
- Valid `docker-compose.prod.yml`
- The recovery service will find them on next run

## 7. Monitoring and Troubleshooting

### Health Checks

All applications should implement a `/health` endpoint:

```bash
# Check individual app health
curl https://app-name.vadimzak.com/health

# Check all apps
for app in sample-app my-app another-app; do
  echo -n "$app: "
  curl -s https://$app.vadimzak.com/health | jq -r .status
done
```

### Container Monitoring

```bash
# List all containers with status
./scripts/server-ops.sh ps

# View container logs
./scripts/server-ops.sh logs app-name

# Follow logs in real-time
./scripts/server-ops.sh logs app-name -f

# Check container resource usage
./scripts/remote-exec.sh "docker stats --no-stream"
```

### Common Issues and Solutions

#### 1. Deployment Fails with "Container not healthy"

**Causes:**
- Application startup error
- Port mismatch
- Missing dependencies

**Solution:**
```bash
# Check container logs
./scripts/server-ops.sh logs app-name

# Inspect container
./scripts/remote-exec.sh "docker inspect app-name-green"

# Test health endpoint locally
./scripts/remote-exec.sh "docker exec app-name-green wget -O- http://localhost:3001/health"
```

#### 2. DNS Resolution Fails

**Causes:**
- DNS propagation delay (5-15 minutes)
- Incorrect Route53 configuration

**Solution:**
```bash
# Check DNS record
aws route53 list-resource-record-sets \
  --hosted-zone-id Z2O129XK0SJBV9 \
  --query "ResourceRecordSets[?Name=='app.vadimzak.com.']" \
  --profile bf

# Deploy using IP instead
SSH_REMOTE_HOST=51.16.33.8 ./scripts/deploy-app.sh app-name
```

#### 3. Nginx Configuration Error

**Symptoms:**
- 502 Bad Gateway
- SSL errors

**Solution:**
```bash
# Check nginx logs
./scripts/manage-infra.sh logs nginx

# Test configuration
./scripts/remote-exec.sh "docker exec sample-app-nginx-1 nginx -t"

# View current config
./scripts/remote-exec.sh "cat /var/www/nginx.conf"
```

#### 4. Disk Space Issues

**Check disk usage:**
```bash
./scripts/remote-exec.sh "df -h"
./scripts/remote-exec.sh "docker system df"
```

**Clean up:**
```bash
# Remove unused images
./scripts/remote-exec.sh "docker image prune -f"

# Remove stopped containers
./scripts/remote-exec.sh "docker container prune -f"

# Clean build cache
./scripts/remote-exec.sh "docker builder prune -f"
```

### Performance Monitoring

```bash
# System resources
./scripts/remote-exec.sh "top -b -n 1 | head -20"

# Docker resource usage
./scripts/remote-exec.sh "docker stats --no-stream"

# Network connections
./scripts/remote-exec.sh "netstat -tuln | grep LISTEN"
```

## 8. Cost Optimization

### Current Cost Structure

- **EC2 Spot Instance**: ~$2-4/month (t3.micro)
- **Route53 Hosted Zone**: $0.50/month
- **Data Transfer**: Minimal (included in free tier)
- **Total**: ~$3-5/month

### Cost-Saving Strategies

1. **Use Spot Instances**
   - Already implemented
   - 70-90% cheaper than on-demand
   - Auto-recovery handles interruptions

2. **Optimize Container Resources**
   ```yaml
   # In docker-compose.prod.yml
   deploy:
     resources:
       limits:
         cpus: '0.5'
         memory: 256M
   ```

3. **Enable Docker Log Rotation**
   ```yaml
   logging:
     driver: "json-file"
     options:
       max-size: "10m"
       max-file: "3"
   ```

4. **Clean Up Unused Resources**
   ```bash
   # Schedule weekly cleanup
   0 3 * * 0 docker system prune -af
   ```

5. **Monitor AWS Costs**
   ```bash
   # Check current month costs
   aws ce get-cost-and-usage \
     --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
     --granularity MONTHLY \
     --metrics "UnblendedCost" \
     --profile bf
   ```

## 9. Security Best Practices

### SSH Security

1. **Key Management:**
   - Store keys securely: `chmod 400 ~/.ssh/sample-app-key.pem`
   - Never commit keys to git
   - Rotate keys periodically

2. **SSH Configuration:**
   ```bash
   # Add to ~/.ssh/config
   Host sample-app
     HostName 51.16.33.8
     User ec2-user
     IdentityFile ~/.ssh/sample-app-key.pem
     StrictHostKeyChecking no
   ```

### Application Security

1. **Environment Variables:**
   - Never hardcode secrets
   - Use `.env` files (git-ignored)
   - Example:
     ```bash
     # apps/app-name/.env
     DB_PASSWORD=secret
     API_KEY=key
     ```

2. **Docker Security:**
   - Use specific image versions
   - Run as non-root user
   - Limit container capabilities

3. **Network Security:**
   - Apps only accessible via nginx
   - Use Docker networks for isolation
   - No direct port exposure

### SSL/TLS Security

1. **Strong Ciphers:**
   ```nginx
   ssl_protocols TLSv1.2 TLSv1.3;
   ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
   ssl_prefer_server_ciphers off;
   ```

2. **Security Headers:**
   ```nginx
   add_header Strict-Transport-Security "max-age=63072000" always;
   add_header X-Content-Type-Options "nosniff" always;
   add_header X-Frame-Options "DENY" always;
   ```

### AWS Security

1. **IAM Best Practices:**
   - Use least privilege principle
   - Enable MFA for console access
   - Rotate access keys regularly

2. **Security Group Rules:**
   - Only open required ports
   - Restrict SSH to your IP if possible
   - Regular audit of rules

## 10. Emergency Procedures

### Application Emergency Rollback

If automated rollback fails:

```bash
# 1. List available images
./scripts/remote-exec.sh "docker images app-name"

# 2. Manually tag previous version
./scripts/remote-exec.sh "docker tag app-name:commit-hash app-name:latest"

# 3. Restart with previous version
./scripts/remote-exec.sh "cd /var/www/app-name && docker-compose -f docker-compose.prod.yml down"
./scripts/remote-exec.sh "cd /var/www/app-name && docker-compose -f docker-compose.prod.yml up -d"
```

### Infrastructure Recovery

If nginx or infrastructure is down:

```bash
# 1. Check infrastructure status
./scripts/manage-infra.sh status

# 2. Force restart infrastructure
./scripts/remote-exec.sh "cd /var/www && docker-compose -f docker-compose-infra.yml down"
./scripts/remote-exec.sh "cd /var/www && docker-compose -f docker-compose-infra.yml up -d"

# 3. Verify nginx is running
./scripts/remote-exec.sh "docker ps | grep nginx"
```

### Complete System Recovery

If the EC2 instance is terminated:

1. **Launch new instance** (follow Section 1, Step 2)
2. **Restore SSL certificates** from backup or regenerate
3. **Clone repository** and deploy infrastructure
4. **Deploy all applications**:
   ```bash
   for app in sample-app my-app another-app; do
     ./scripts/deploy-app.sh $app "Recovery deployment"
   done
   ```

### Backup Procedures

Regular backups should include:

1. **Application Data:**
   ```bash
   # Backup DynamoDB tables
   aws dynamodb create-backup \
     --table-name YourTable \
     --backup-name "backup-$(date +%Y%m%d)" \
     --profile bf
   ```

2. **SSL Certificates:**
   ```bash
   # Backup certificates locally
   scp -i ~/.ssh/sample-app-key.pem \
     ec2-user@51.16.33.8:/var/www/ssl/* \
     ./backups/ssl/
   ```

3. **Application Configurations:**
   ```bash
   # Already in git, ensure regular commits
   git add -A && git commit -m "Backup configurations"
   git push origin main
   ```

### Disaster Recovery Plan

1. **Documentation**: Keep this guide updated and accessible
2. **Backups**: Regular automated backups of data and configurations
3. **Testing**: Quarterly disaster recovery drills
4. **Monitoring**: Set up CloudWatch alarms for instance health
5. **Communication**: Maintain emergency contact list

---

## Quick Reference

### Common Commands

```bash
# Deploy app
./scripts/deploy-app.sh app-name "Description"

# Check app health
curl https://app-name.vadimzak.com/health

# View logs
./scripts/server-ops.sh logs app-name

# Restart app
./scripts/server-ops.sh restart app-name

# Infrastructure status
./scripts/manage-infra.sh status

# Execute remote command
./scripts/remote-exec.sh "command"
```

### Important Paths

- **Server Base**: `/var/www/`
- **App Directories**: `/var/www/app-name/`
- **SSL Certificates**: `/var/www/ssl/`
- **Nginx Config**: `/var/www/nginx.conf`
- **Recovery Script**: `/usr/local/bin/recover-apps.sh`

### Key Configuration Files

- **App Config**: `apps/app-name/deploy.config`
- **Docker Compose**: `apps/app-name/docker-compose.prod.yml`
- **Infrastructure**: `scripts/docker-compose-infra.yml`
- **Shared Functions**: `scripts/lib/deploy-common.sh`

### Support and Troubleshooting

For additional help:
1. Check application logs first
2. Review this documentation
3. Check infrastructure status
4. Contact system administrator

Remember: Always use `scripts/remote-exec.sh` for SSH operations instead of direct SSH commands.