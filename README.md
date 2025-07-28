# BF Backend

A production-ready Node.js application deployed on AWS with Docker containerization.

## Quick Start

### Local Development
```bash
npm install
npm run dev
```

### Production Deployment

**One-Click Deployment:**
```bash
# Deploy latest changes
./apps/sample-app/deploy/one-click-deploy.sh

# Deploy with custom message
./apps/sample-app/deploy/one-click-deploy.sh "Fix authentication bug"

# Test what would be deployed
./apps/sample-app/deploy/one-click-deploy.sh --dry-run

# Rollback to previous version
./apps/sample-app/deploy/one-click-deploy.sh --rollback
```

## Architecture

- **Application**: Node.js + Express + DynamoDB
- **Infrastructure**: AWS EC2 (spot instances) + Route53 + Let's Encrypt SSL
- **Containerization**: Docker + Docker Compose + NGINX reverse proxy
- **Deployment**: Automated with health checks and rollback capability

## Production Environment

- **URL**: https://sample.vadimzak.com
- **Cost**: ~$2-4/month using spot instances
- **Monitoring**: Automated health checks and container monitoring
- **SSL**: Let's Encrypt with auto-renewal

## Project Structure

```
bf-backend/
├── apps/
│   └── sample-app/           # Main application
│       ├── deploy/           # Deployment scripts
│       ├── public/           # Static files
│       ├── routes/           # API routes
│       └── docker-compose.prod.yml
├── libs/                     # Shared libraries
├── docs/                     # Documentation
└── package.json             # Workspace configuration
```

## Key Features

✅ **Production Ready**: HTTPS, security headers, monitoring  
✅ **Cost Optimized**: AWS spot instances, on-demand DynamoDB  
✅ **Zero Downtime**: Rolling deployments with health checks  
✅ **Auto Rollback**: Reverts on deployment failure  
✅ **Comprehensive Testing**: Automated endpoint verification  

## Documentation

- [Deployment Insights](docs/deployment-insights.md) - Lessons learned and best practices
- [Stack Overview](docs/Stack.md) - Technology stack details
- [TODO List](docs/TODO.md) - Current tasks and improvements

## Development Commands

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build

# Run tests
npm run test

# Deploy to production
./apps/sample-app/deploy/one-click-deploy.sh
```

## Monitoring

- **Health Check**: https://sample.vadimzak.com/health
- **API Status**: https://sample.vadimzak.com/api/items
- **Container Status**: `docker ps` on production server

For detailed deployment instructions and troubleshooting, see [deployment-insights.md](docs/deployment-insights.md).