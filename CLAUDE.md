# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current Infrastructure (July 2025)

**IMPORTANT**: This project uses Kubernetes on AWS with KOPS.

### Infrastructure:
- **Platform**: Single-node Kubernetes cluster (KOPS)
- **Container Orchestration**: Kubernetes
- **Ingress**: NGINX Ingress Controller with NodePort
- **Port Access**: HAProxy for standard ports (80/443)
- **HTTPS Support**: Secondary IP solution for port 443 (optional)
- **Deployment**: Kubernetes manifests and Helm charts

## Documentation

- **Current Kubernetes Setup**: See `docs/K8S_MIGRATION_PLAN.md`
- **Standard Ports Configuration**: See `docs/K8S_STANDARD_PORTS_SETUP.md`
- **HTTPS Port 443 Solution**: See `docs/K8S_HTTPS_PORT_443_SOLUTIONS.md`
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
- **Standard Ports**: HAProxy on master node for ports 80/443
- **Secondary IP**: Optional setup for HTTPS on port 443
- **Container Registry**: AWS ECR for Docker images
- **SSL/TLS**: cert-manager with Let's Encrypt

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
# Complete setup with HTTPS on port 443 (recommended)
./scripts/k8s/quick-start-full.sh --with-secondary-ip

# Complete setup with HTTP only on port 80
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

## Secondary IP Solution for HTTPS

To enable HTTPS on port 443 on a single-node cluster:

### Option 1: New Cluster with Secondary IP
```bash
./scripts/k8s/quick-start-full.sh --with-secondary-ip
```

### Option 2: Add to Existing Cluster
```bash
./scripts/k8s/setup-secondary-ip.sh
./scripts/k8s/setup-haproxy-https.sh
./scripts/k8s/update-app-dns-secondary.sh
```

### How It Works
The solution uses iptables PREROUTING to redirect HTTPS traffic:
1. Secondary IP receives traffic on port 443
2. iptables redirects it to HAProxy on port 8443
3. HAProxy forwards to the appropriate backend (ingress or API server)
4. This avoids the port conflict with the Kubernetes API server

Key components:
- Allocates a secondary IP address to the EC2 instance  
- Uses iptables redirect: `iptables -t nat -A PREROUTING -d <secondary-ip> -p tcp --dport 443 -j REDIRECT --to-port 8443`
- HAProxy listens on port 8443 instead of 443
- Keeps API server on primary IP port 443
- Costs an additional ~$3.60/month for the Elastic IP

## Key Scripts

### Kubernetes Scripts (`scripts/k8s/`)
- `bootstrap-cluster.sh` - Create KOPS cluster (supports `--with-secondary-ip`)
- `configure-apps.sh` - Setup ECR and build images
- `deploy-app.sh` - Deploy app to Kubernetes
- `setup-haproxy.sh` - Configure HTTP on port 80
- `setup-haproxy-https.sh` - Configure HTTP/HTTPS with secondary IP
- `setup-secondary-ip.sh` - Setup secondary IP for HTTPS on port 443
- `quick-start-full.sh` - One-command full setup (supports `--with-secondary-ip`)
- `teardown-cluster.sh` - Remove cluster
- `cluster-status.sh` - Health check
- `update-wildcard-dns.sh` - Update DNS records
- `update-app-dns-secondary.sh` - Update DNS to use secondary IP

### Application Configuration
Each app needs:
1. `Dockerfile` - Container definition
2. `k8s/` directory with:
   - `deployment.yaml` - Kubernetes deployment
   - `service.yaml` - Service definition
   - `ingress.yaml` - Ingress rules
   - `kustomization.yaml` - Kustomize config

## Current URLs

### With Secondary IP (HTTPS on port 443):
- http://sample.vadimzak.com
- https://sample.vadimzak.com
- http://sample-6.vadimzak.com
- https://sample-6.vadimzak.com

### With HAProxy (HTTP only):
- http://sample.vadimzak.com
- http://sample-6.vadimzak.com
- https://sample.vadimzak.com:30443 (non-standard port)

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

1. **Single Node Limitation**: API server uses port 443 (resolved with secondary IP solution)
2. **Cost**: ~$20-25/month (on-demand t3.small instance) + $3.60/month for secondary IP (optional)
3. **DNS**: Uses wildcard DNS (*.vadimzak.com)
4. **Security Groups**: Managed by KOPS, additional ports via scripts
5. **SSL/TLS**: Full HTTPS support available with secondary IP solution

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
- Optional: +$3.60/month for secondary IP (HTTPS on port 443)

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