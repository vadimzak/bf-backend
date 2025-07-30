# BF Backend

A production-ready Node.js application deployed on AWS with Kubernetes.

## Quick Start

### Local Development
```bash
npm install
npm run dev
```

### Production Deployment

**Kubernetes Deployment:**
```bash
# Deploy application
./scripts/k8s/deploy-app.sh sample-app

# Check cluster status
./scripts/k8s/cluster-status.sh
```

## Architecture

- **Application**: Node.js + Express + DynamoDB
- **Infrastructure**: Kubernetes (KOPS) on AWS EC2 + Route53
- **Containerization**: Docker + Kubernetes + NGINX Ingress Controller
- **Deployment**: Kubernetes manifests with automated health checks

## Production Environment

- **URL**: https://sample.vadimzak.com
- **Cost**: ~$20-25/month using on-demand t3.small instance
- **Monitoring**: Kubernetes health checks and pod monitoring
- **Ingress**: NGINX Ingress Controller with HAProxy for standard ports

## Project Structure

```
bf-backend/
├── apps/
│   └── sample-app/           # Main application
│       ├── k8s/              # Kubernetes manifests
│       ├── public/           # Static files
│       ├── routes/           # API routes
│       └── Dockerfile        # Container definition
├── scripts/
│   └── k8s/                  # Kubernetes scripts
├── libs/                     # Shared libraries
├── docs/                     # Documentation
└── package.json             # Workspace configuration
```

## Key Features

✅ **Production Ready**: HTTP/HTTPS, security headers, monitoring  
✅ **Infrastructure as Code**: KOPS-managed Kubernetes cluster  
✅ **Zero Downtime**: Kubernetes rolling deployments  
✅ **Container Registry**: AWS ECR for image management  
✅ **Scalable**: Kubernetes-native scaling and management  

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
./scripts/k8s/deploy-app.sh sample-app
```

## Monitoring

- **Health Check**: https://sample.vadimzak.com/health
- **API Status**: https://sample.vadimzak.com/api/items
- **Container Status**: `kubectl get pods -n apps`

For detailed deployment instructions and troubleshooting, see [deployment-insights.md](docs/deployment-insights.md).