# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation

- full deployment and dev-ops description of our systems can be found at @docs/DEPLOYMENT.md
  - IMPORTANT: make sure to update this document with every change in the deployment or dev-ops procedures

## Dev Ops

- All deployment related changes should be executed by deployment scripts, every time you modify something directly on a server - make sure this change is covered in one of the deployment scripts for future interactions.
- NEVER execute a command that may lead to a downtime of any app on the server without explaining this to the user and getting an explicit permission.
- NEVER use direct SSH commands. Always use `scripts/remote-exec.sh` for executing commands on the EC2 instance.
- With every dev-ops change you perform - keep in mind that we many want to bootstrap all our infrastructure on a new AWS account from scratch and will need an easy way to recreate our existing setup, so make sure our current deployment state os always backed by scripts.

## Architecture Overview

This is an NX monorepo with a production-ready Node.js application deployed on AWS. The main application lives in `apps/sample-app/` and uses Express + DynamoDB with Docker containerization.

**Key Architecture Components:**
- **Monorepo Structure**: NX workspace with apps and shared libraries
- **Main App**: Node.js Express server in `apps/sample-app/`
- **Database**: AWS DynamoDB with SDK integration
- **Infrastructure**: AWS EC2 spot instances + Route53 + Let's Encrypt SSL
- **Containerization**: Docker + Docker Compose + NGINX reverse proxy
- **Deployment**: Automated scripts with health checks and rollback capability

## Development Commands

### Workspace-Level Commands
```bash
# Install all dependencies
npm install

# Build all projects
npm run build
# or
nx run-many --target=build

# Run tests across workspace
npm run test
# or  
nx run-many --target=test

# Serve applications
npm run serve
# or
nx serve sample-app
```

### Sample App Development
```bash
# Navigate to sample app
cd apps/sample-app

# Development server with hot reload
npm run dev

# Production server
npm start

# Install app-specific dependencies
npm install [package-name]
```


### Production Deployment

#### Sample App
```bash
# One-click deployment (main deployment method)
./apps/sample-app/deploy/one-click-deploy.sh

# Deploy with custom commit message
./apps/sample-app/deploy/one-click-deploy.sh "Fix authentication bug"

# Test deployment (dry run)
./apps/sample-app/deploy/one-click-deploy.sh --dry-run

# Rollback to previous version
./apps/sample-app/deploy/one-click-deploy.sh --rollback
```


## Key File Locations

### Sample App (apps/sample-app/)
- **Main Server**: `apps/sample-app/server.js` - Express server entry point
- **API Routes**: `apps/sample-app/routes/` - API endpoint definitions
- **DynamoDB Config**: `apps/sample-app/config/dynamodb.js` - Database connection
- **Deployment Scripts**: `apps/sample-app/deploy/` - All deployment automation
- **Docker Config**: `apps/sample-app/docker-compose.prod.yml` - Production containers


### Shared
- **Shared Libraries**: `libs/server-core/` - Reusable server components (currently minimal)

## Environment and Configuration

### Sample App
- **Production URL**: https://sample.vadimzak.com
- **Health Check**: `/health` endpoint for monitoring
- **Environment Variables**: Use `.env` files (see `.env.example`)


### General
- **AWS Profile**: Only use `bf` AWS profile for deployments

## Development Notes

### Sample App
- Uses AWS SDK v2 for DynamoDB operations
- Security middleware: Helmet, CORS enabled
- Static files served from `public/` directory
- Error handling middleware implemented
- Cron jobs for maintenance tasks in `cron/` directory
- Health checks and monitoring built-in


## Important Considerations

- Always use the one-click deployment script for production deployments
- Deployment includes automatic health checks and rollback on failure
- Cost-optimized using AWS spot instances (~$2-4/month)
- Wildcard SSL certificate (*.vadimzak.com) covers all subdomains - no downtime for new apps
- Zero-downtime deployments with rolling updates

## Streamlined Architecture

### Repository Scripts Overview

All infrastructure scripts are located in the `scripts/` directory:

#### Core Scripts
- **`scripts/add-new-app.sh`** - Creates new applications with complete structure
- **`scripts/prep-app-infra.sh`** - Prepares cloud infrastructure (DNS, nginx) for existing apps
- **`scripts/deploy-app.sh`** - Universal deployment script for all apps
- **`scripts/remove-app.sh`** - Removes apps from repository and production
- **`scripts/lib/deploy-common.sh`** - Shared deployment functions and utilities
- **`scripts/renew-wildcard-cert.sh`** - Renews the wildcard SSL certificate

#### SSH and Remote Management Scripts
- **`scripts/remote-exec.sh`** - Execute commands on the EC2 instance without manual SSH
- **`scripts/server-ops.sh`** - Server operations and management utilities

**Important**: Always use `scripts/remote-exec.sh` for SSH operations instead of direct SSH commands. Example:
```bash
./scripts/remote-exec.sh "sudo docker ps"
./scripts/remote-exec.sh "cat /var/www/sample-app/deploy/nginx.conf"
```

### Adding New Apps

#### Option 1: Full App Creation
```bash
./scripts/add-new-app.sh my-new-app
```
This script automatically:
- Creates app directory structure with boilerplate code
- Sets up package.json with standard dependencies
- Generates minimal Express server with health checks
- Creates Docker configuration files
- Allocates the next available port (starting from 3001)
- Creates DNS A record pointing to the EC2 instance
- Updates nginx configuration for routing
- Generates deployment configuration (`deploy.config`)

#### Option 2: Infrastructure Setup for Existing Apps
If you've created app files manually or copied from another app:
```bash
./scripts/prep-app-infra.sh my-existing-app [--deploy]
```
This script:
- Reads configuration from existing `deploy.config`
- Creates DNS A record pointing to the EC2 instance
- Updates nginx configuration for routing
- Restarts nginx automatically
- Optionally deploys the app with `--deploy` flag

**Requirements for prep-app-infra.sh:**
- App directory must exist at `apps/app-name/`
- `deploy.config` must exist with `APP_PORT` and `APP_DOMAIN` defined

### Deploying Apps
All apps use the unified deployment system:
```bash
# From project root (recommended)
./scripts/deploy-app.sh app-name [options] [commit-message]

# Or from app directory
cd apps/app-name
./deploy.sh [options] [commit-message]

# Options:
# --dry-run     Show what would be deployed without making changes
# --rollback    Rollback to previous deployment
# --force       Skip safety checks and deploy anyway
# --help        Show help message

# Examples:
./scripts/deploy-app.sh sample-app "Fix authentication bug"
./scripts/deploy-app.sh my-app --dry-run
./scripts/deploy-app.sh my-app --rollback
```

### Removing Apps
To remove an app from both the repository and production:
```bash
# With confirmation prompts
./scripts/remove-app.sh app-name

# Without confirmation prompts (force mode)
./scripts/remove-app.sh --force app-name
./scripts/remove-app.sh -f app-name

# Show help
./scripts/remove-app.sh --help
```

The removal script will:
- Stop and remove all Docker containers for the app
- Remove Docker images and volumes
- Delete the app directory from the production server
- Remove the app's nginx configuration blocks
- Delete the DNS A record
- Remove the app directory from the repository
- Commit the removal to git

### App Configuration
Each app requires a `deploy.config` file in its directory:
```bash
# apps/app-name/deploy.config
APP_PORT=3004
APP_DOMAIN=my-app.vadimzak.com
```

### Deployment Process Details

The deployment system (`scripts/deploy-app.sh` + `scripts/lib/deploy-common.sh`) performs:

1. **Pre-deployment checks**:
   - Validates Docker installation and daemon status
   - Checks SSH connectivity to EC2 instance
   - Verifies git status (warns about uncommitted changes)
   - Runs health check on current deployment

2. **Build and preparation**:
   - Auto-commits changes with formatted message
   - Builds Docker image for linux/amd64 platform
   - Tags image with git commit hash and 'latest'

3. **Transfer and deployment**:
   - Compresses and transfers Docker image via SCP
   - Sets up remote directory structure
   - Deploys using docker-compose with zero downtime
   - Connects containers to shared Docker network

4. **Post-deployment**:
   - Runs comprehensive health checks
   - Tests HTTPS redirect
   - Verifies container status
   - Automatic rollback on failure (if not using --force)
   - Cleans up old images (keeps latest 3)

### Shared Infrastructure
- All deployment logic is in `scripts/lib/deploy-common.sh`
- Common variables: `REMOTE_USER=ec2-user`, `SSH_KEY=$HOME/.ssh/sample-app-key.pem`
- Shared Docker network: `sample-app_app-network`
- Wildcard SSL certificate covers all subdomains
- Shared nginx and watchtower run as separate services
- Docker network connectivity handled automatically
- Apps can have multiple services (e.g., sample-app has cron tasks)

### Infrastructure Services
The shared infrastructure runs separately:
- **nginx**: Reverse proxy handling SSL and routing for all apps
- **watchtower**: Automated Docker container updates
- Located in `/var/www/sample-app` on the server
- Managed via `docker-compose-infra.yml`

#### Managing Infrastructure
```bash
# Start infrastructure services
./scripts/manage-infra.sh start

# Stop infrastructure services
./scripts/manage-infra.sh stop

# Restart infrastructure services
./scripts/manage-infra.sh restart

# Check infrastructure status
./scripts/manage-infra.sh status

# View logs
./scripts/manage-infra.sh logs
./scripts/manage-infra.sh logs nginx

# Reload nginx configuration (no downtime)
./scripts/manage-infra.sh reload-nginx
```

## SSL Certificate Management

### Wildcard Certificate Setup
The infrastructure uses a single wildcard certificate (*.vadimzak.com) that covers all subdomains:
- Certificate location on server: `/var/www/ssl/`
- Mounted in nginx container as: `/etc/ssl/`
- Managed by certbot with Route53 DNS validation
- Auto-renewal configured via certbot
- No need to update certificates when adding new apps

**Note**: Nginx config files should reference certificates as `/etc/ssl/fullchain.pem` and `/etc/ssl/privkey.pem`

### Certificate Renewal
Run the renewal script manually or set up a cron job:
```bash
./scripts/renew-wildcard-cert.sh
```

This script:
- Connects to the EC2 instance via SSH
- Runs certbot renewal with Route53 DNS validation
- Copies renewed certificates to `/var/www/ssl/`
- Restarts nginx to use the new certificate

### Important: Never expand certificates for individual subdomains
All apps use the same wildcard certificate to avoid downtime when adding new apps.

## DevOps Operations Reference

### Common Operations

#### Check Application Status
```bash
# View all running containers on server
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com \
  "sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Check specific app health
curl https://app-name.vadimzak.com/health

# View app logs
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com \
  "cd /var/www/app-name && sudo docker-compose -f docker-compose.prod.yml logs --tail 50"
```

#### Manual Nginx Operations
```bash
# Reload nginx configuration (preferred - no downtime)
./scripts/manage-infra.sh reload-nginx

# Restart nginx service
./scripts/manage-infra.sh restart

# View nginx logs
./scripts/manage-infra.sh logs nginx
```

#### Emergency Rollback
```bash
# If automated rollback fails, manually rollback
./scripts/deploy-app.sh app-name --rollback

# Or connect and rollback manually
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com
cd /var/www/app-name
sudo docker images app-name  # List available versions
sudo docker tag app-name:previous-hash app-name:latest
sudo docker-compose -f docker-compose.prod.yml down
sudo docker-compose -f docker-compose.prod.yml up -d
```

### Infrastructure Details

#### EC2 Instance
- Type: Spot instance (cost-optimized)
- IP: 51.16.33.8
- SSH Key: `~/.ssh/sample-app-key.pem`
- User: `ec2-user`

#### DNS Configuration
- Hosted Zone ID: Z2O129XK0SJBV9
- All subdomains point to: 51.16.33.8
- TTL: 300 seconds

#### Port Allocation
- Apps start at port 3001 and increment
- Each app gets a unique port via `deploy.config`
- Nginx proxies from 443 to app ports

#### Docker Networks
- Shared network: `sample-app_app-network`
- All app containers connect to this network
- Enables inter-container communication

### Troubleshooting

#### Deployment Failures
1. Check pre-deployment health: `curl https://app.vadimzak.com/health`
2. Verify Docker daemon: `ssh ... "sudo systemctl status docker"`
3. Check disk space: `ssh ... "df -h"`
4. Review deployment logs: `ssh ... "cat /var/www/app-name/deployment.log"`

#### Container Issues
1. List all containers: `ssh ... "sudo docker ps -a"`
2. Inspect container: `ssh ... "sudo docker inspect container-name"`
3. Check container logs: `ssh ... "sudo docker logs container-name"`
4. Restart container: `ssh ... "cd /var/www/app && sudo docker-compose restart"`

#### Network Connectivity
1. Verify network exists: `ssh ... "sudo docker network ls"`
2. Check network connections: `ssh ... "sudo docker network inspect sample-app_app-network"`
3. Test internal connectivity: `ssh ... "sudo docker exec container-1 ping container-2"`

#### DNS Propagation Issues
If deployment fails with DNS resolution errors on a new app:
1. DNS records may not have propagated yet (can take 5-15 minutes)
2. The deployment script will automatically fall back to using IP address
3. Alternatively, use the IP directly: `SSH_REMOTE_HOST=51.16.33.8 ./scripts/deploy-app.sh app-name`

#### Nginx SSL Certificate Issues
If nginx fails to start or reload with SSL certificate errors:
1. Ensure certificates exist: `./scripts/remote-exec.sh "ls -la /var/www/ssl/"`
2. Check certificate paths in nginx config use `/etc/ssl/` not `/var/www/ssl/`
3. Verify certificate mounting: `./scripts/remote-exec.sh "sudo docker exec sample-app-nginx-1 ls -la /etc/ssl/"`
4. Fix and reload: `./scripts/manage-infra.sh reload-nginx`