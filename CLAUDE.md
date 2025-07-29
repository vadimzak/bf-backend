# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

### Sample-2 App Development
```bash
# Navigate to sample-2 app
cd apps/sample-2

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

#### Sample-2 App
```bash
# One-click deployment (main deployment method)
./apps/sample-2/deploy/one-click-deploy.sh

# Deploy with custom commit message
./apps/sample-2/deploy/one-click-deploy.sh "Fix UI styling bug"

# Test deployment (dry run)
./apps/sample-2/deploy/one-click-deploy.sh --dry-run

# Rollback to previous version
./apps/sample-2/deploy/one-click-deploy.sh --rollback
```

## Key File Locations

### Sample App (apps/sample-app/)
- **Main Server**: `apps/sample-app/server.js` - Express server entry point
- **API Routes**: `apps/sample-app/routes/` - API endpoint definitions
- **DynamoDB Config**: `apps/sample-app/config/dynamodb.js` - Database connection
- **Deployment Scripts**: `apps/sample-app/deploy/` - All deployment automation
- **Docker Config**: `apps/sample-app/docker-compose.prod.yml` - Production containers

### Sample-2 App (apps/sample-2/)
- **Main Server**: `apps/sample-2/server.js` - Express server entry point
- **Static Content**: `apps/sample-2/public/` - HTML, CSS, JS files
- **Deployment Scripts**: `apps/sample-2/deploy/` - Deployment automation
- **Docker Config**: `apps/sample-2/docker-compose.prod.yml` - Production containers

### Shared
- **Shared Libraries**: `libs/server-core/` - Reusable server components (currently minimal)

## Environment and Configuration

### Sample App
- **Production URL**: https://sample.vadimzak.com
- **Health Check**: `/health` endpoint for monitoring
- **Environment Variables**: Use `.env` files (see `.env.example`)

### Sample-2 App
- **Production URL**: https://sample-2.vadimzak.com
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

### Sample-2 App
- Minimal static page application
- Security middleware: Helmet, CORS enabled
- Static files served from `public/` directory
- Error handling middleware implemented
- Health checks built-in
- Interactive status check functionality

## Important Considerations

- Always use the one-click deployment script for production deployments
- Deployment includes automatic health checks and rollback on failure
- Cost-optimized using AWS spot instances (~$2-4/month)
- Wildcard SSL certificate (*.vadimzak.com) covers all subdomains - no downtime for new apps
- Zero-downtime deployments with rolling updates

## Streamlined Architecture

### Adding New Apps
```bash
./scripts/add-new-app.sh my-new-app
```
This creates a complete app structure with minimal boilerplate.

### Deploying Apps
All apps use the same deployment system:
```bash
# From project root
./scripts/deploy-app.sh app-name

# Or from app directory
cd apps/app-name
./deploy.sh
```

### App Configuration
Each app has a simple `deploy.config` file:
```bash
APP_PORT=3004
APP_DOMAIN=my-app.vadimzak.com
```

### Shared Infrastructure
- All deployment logic is in `scripts/lib/deploy-common.sh`
- Wildcard SSL certificate covers all subdomains
- Shared nginx configuration with automatic routing
- Docker network connectivity handled automatically

## SSL Certificate Management

### Wildcard Certificate Setup
The infrastructure uses a single wildcard certificate (*.vadimzak.com) that covers all subdomains:
- Certificate location: `/var/www/ssl/`
- Managed by certbot with Route53 DNS validation
- Auto-renewal configured via certbot
- No need to update certificates when adding new apps

### Certificate Renewal
Run the renewal script manually or set up a cron job:
```bash
./scripts/renew-wildcard-cert.sh
```

### Important: Never expand certificates for individual subdomains
All apps use the same wildcard certificate to avoid downtime when adding new apps.