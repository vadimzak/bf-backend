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
- **Cost**: ~$20-25/month using on-demand t3.small instance (add ~$3.60/month for HTTPS on port 443)
- **Monitoring**: Kubernetes health checks and pod monitoring
- **Ingress**: NGINX Ingress Controller with HAProxy for standard ports
- **HTTPS**: Secondary IP solution for port 443 (enabled by default)

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

- [Kubernetes Migration Guide](docs/K8S_MIGRATION_PLAN.md) - Complete setup instructions
- [Elastic IP Troubleshooting](docs/K8S_ELASTIC_IP_TROUBLESHOOTING.md) - Resolve HTTPS port 443 issues
- [Stack Overview](docs/Stack.md) - Technology stack details
- [Standard Ports Setup](docs/K8S_STANDARD_PORTS_SETUP.md) - HAProxy configuration guide

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