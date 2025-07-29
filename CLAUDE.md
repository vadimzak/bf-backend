# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current Infrastructure (July 2025)

**IMPORTANT**: This project has migrated from Docker Compose to Kubernetes using KOPS on AWS.

### Key Changes:
- **Platform**: Single-node Kubernetes cluster (KOPS)
- **Container Orchestration**: Kubernetes instead of Docker Compose
- **Ingress**: NGINX Ingress Controller with NodePort
- **Port Access**: HAProxy for standard HTTP port (80)
- **Deployment**: Kubernetes manifests and Helm charts

## Documentation

- **Current Kubernetes Setup**: See `docs/K8S_MIGRATION_PLAN.md`
- **Standard Ports Configuration**: See `docs/K8S_STANDARD_PORTS_SETUP.md`
- **Legacy Docker Compose**: See `docs/DEPLOYMENT.md` (historical reference only)
  - IMPORTANT: Update these documents with every deployment or dev-ops change

## General Directives

- Always use dark mode design by default
- IMPORTANT: ALL deployment changes must be scripted for reproducibility
- NEVER execute commands that may cause downtime without user permission
- Use `scripts/k8s/` scripts for all Kubernetes operations
- Ensure all changes can recreate infrastructure from scratch

## Architecture Overview

### Kubernetes Infrastructure
- **Cluster**: Single-node KOPS cluster in il-central-1
- **Applications**: Deployed in `apps` namespace
- **Ingress**: NGINX Ingress Controller on NodePorts 30080/30443
- **Standard Ports**: HAProxy on master node for port 80 access
- **Container Registry**: AWS ECR for Docker images
- **SSL/TLS**: cert-manager with Let's Encrypt (future)

### Application Structure
- **Monorepo**: NX workspace with multiple apps
- **Main Apps**: 
  - `apps/sample-app/` - Main sample application
  - `apps/sample-6/` - Additional sample app
- **Database**: AWS DynamoDB
- **Health Checks**: `/health` endpoint required

## Kubernetes Commands

### Quick Setup
```bash
# Complete setup with standard ports
./scripts/k8s/quick-start-full.sh

# Basic setup (ports 30080/30443)
./scripts/k8s/quick-start.sh
```

### Application Deployment
```bash
# Configure all apps (build, push to ECR, generate manifests)
./scripts/k8s/configure-apps.sh

# Deploy individual app
./scripts/k8s/deploy-app.sh <app-name>

# Check cluster status
./scripts/k8s/cluster-status.sh
```

### Cluster Management
```bash
# Bootstrap new cluster
./scripts/k8s/bootstrap-cluster.sh

# Teardown cluster
./scripts/k8s/teardown-cluster.sh

# Fix DNS issues
./scripts/k8s/fix-dns.sh --use-ip
```

## Key Scripts

### Kubernetes Scripts (`scripts/k8s/`)
- `bootstrap-cluster.sh` - Create KOPS cluster
- `configure-apps.sh` - Setup ECR and build images
- `deploy-app.sh` - Deploy app to Kubernetes
- `setup-haproxy.sh` - Configure standard ports
- `quick-start-full.sh` - One-command full setup
- `teardown-cluster.sh` - Remove cluster
- `cluster-status.sh` - Health check
- `update-wildcard-dns.sh` - Update DNS records

### Application Configuration
Each app needs:
1. `Dockerfile` - Container definition
2. `k8s/` directory with:
   - `deployment.yaml` - Kubernetes deployment
   - `service.yaml` - Service definition
   - `ingress.yaml` - Ingress rules
   - `kustomization.yaml` - Kustomize config

## Current URLs

### With Standard Ports (HAProxy enabled):
- http://sample.vadimzak.com
- http://sample-6.vadimzak.com

### Without HAProxy:
- http://sample.vadimzak.com:30080
- https://sample.vadimzak.com:30443

### Infrastructure:
- HAProxy Stats: http://<master-ip>:8404/stats
- Kubernetes API: https://api.k8s.vadimzak.com

## Environment Variables

- **AWS Profile**: `bf`
- **AWS Region**: `il-central-1`
- **Cluster Name**: `k8s.vadimzak.com`
- **ECR Registry**: Check with `kubectl get cm -n apps`

## Development Workflow

### Local Development
```bash
cd apps/<app-name>
npm install
npm run dev
```

### Deploy Changes
```bash
# Auto-commits, builds, pushes, and deploys
./scripts/k8s/deploy-app.sh <app-name> "Description of changes"
```

## Important Considerations

1. **Single Node Limitation**: API server uses port 443, preventing standard HTTPS
2. **Cost**: ~$20-25/month (on-demand t3.small instance)
3. **DNS**: Uses wildcard DNS (*.vadimzak.com)
4. **Security Groups**: Managed by KOPS, additional ports via scripts
5. **SSL/TLS**: Currently disabled for HTTP access

## Troubleshooting

### Connection Issues
```bash
# If kubectl fails
./scripts/k8s/fix-dns.sh --use-ip

# Check nodes
kubectl get nodes

# Check pods
kubectl get pods --all-namespaces
```

### Application Issues
```bash
# Check app logs
kubectl logs -n apps deployment/<app-name>

# Describe pod
kubectl describe pod -n apps <pod-name>

# Check ingress
kubectl get ingress -n apps
```

### HAProxy Issues
```bash
# SSH to master
ssh -i ~/.ssh/kops-key ubuntu@<master-ip>

# Check HAProxy
sudo systemctl status haproxy
sudo journalctl -u haproxy -n 50

# Check stats
curl http://<master-ip>:8404/stats
```

## Cost Optimization

Current setup (~$20-25/month):
- Single t3.small instance (on-demand)
- No load balancer costs
- Minimal data transfer

For production, consider:
- Multi-node cluster
- AWS Load Balancer
- Spot instances for workers

## Security Notes

1. **Ingress**: SSL redirect disabled for HTTP access
2. **API Server**: Accessible publicly on port 443
3. **Applications**: Only accessible through ingress
4. **SSH**: Key-based access only (`~/.ssh/kops-key`)

## Migration Notes

When migrating from Docker Compose:
1. Build Docker images with same functionality
2. Create Kubernetes manifests
3. Use NodePort services for ingress
4. Configure HAProxy for standard ports
5. Update DNS to point to master node IP