# Kubernetes Infrastructure Setup with KOPS

## Overview
This document describes the Kubernetes infrastructure setup using KOPS on AWS with a single on-demand instance.

## Quick Start

### One-Command Setup

#### Option A: Standard Ports with HTTPS (Recommended)
```bash
# Complete setup with secondary IP for HTTPS on port 443 (default)
./scripts/k8s/quick-start-full.sh

# Or without secondary IP (HTTPS only on port 30443)
./scripts/k8s/quick-start-full.sh --no-secondary-ip
```

This will:
- Install all prerequisites
- Bootstrap the Kubernetes cluster
- Install ingress controller and cert-manager
- Configure applications
- Setup secondary IP and HAProxy for standard ports (80/443) - enabled by default
- Or setup HAProxy for HTTP only (if --no-secondary-ip is used)

**Note**: Secondary IP is now ENABLED BY DEFAULT for HTTPS on port 443. If you encounter Elastic IP limit issues, see [Elastic IP Troubleshooting Guide](./K8S_ELASTIC_IP_TROUBLESHOOTING.md).

#### Option B: Basic Setup (Non-standard Ports)
```bash
# Basic setup without HAProxy
./scripts/k8s/quick-start.sh
```

This will:
- Install all prerequisites
- Bootstrap the Kubernetes cluster
- Install ingress controller and cert-manager
- Optionally configure applications
- Applications accessible on ports 30080/30443

### Manual Step-by-Step
```bash
# 1. Install prerequisites
./scripts/k8s/install-prerequisites.sh

# 2. Bootstrap Kubernetes cluster
./scripts/k8s/bootstrap-cluster.sh

# 3. Configure and deploy applications
./scripts/k8s/configure-apps.sh

# 4. Deploy individual apps
./scripts/k8s/deploy-app.sh sample-app
```

### Troubleshooting DNS Issues
If you encounter "no such host" errors:
```bash
# Use IP address temporarily
./scripts/k8s/fix-dns.sh --use-ip

# Check cluster status
./scripts/k8s/cluster-status.sh
```

### Available Scripts

| Script | Purpose |
|--------|---------|
| `scripts/k8s/install-prerequisites.sh` | Install kubectl, kops, helm |
| `scripts/k8s/bootstrap-cluster.sh` | Create and configure K8s cluster |
| `scripts/k8s/configure-apps.sh` | Set up ECR, build images, generate manifests |
| `scripts/k8s/deploy-app.sh` | Deploy individual applications |
| `scripts/k8s/teardown-cluster.sh` | Safely remove cluster and resources |
| `scripts/k8s/fix-dns.sh` | Handle DNS resolution issues |
| `scripts/k8s/cluster-status.sh` | Quick health check of cluster |
| `scripts/k8s/update-wildcard-dns.sh` | Update wildcard DNS to K8s node |
| `scripts/k8s/update-app-dns.sh` | Update individual app DNS records |
| `scripts/k8s/quick-start.sh` | One-command basic setup |
| `scripts/k8s/quick-start-full.sh` | Complete setup with standard ports |
| `scripts/k8s/setup-haproxy.sh` | Configure HAProxy for standard ports |
| `scripts/k8s/lib/k8s-common.sh` | Shared functions and configuration |

## Prerequisites

### Local Tools Installation

All required tools can be installed using our automated script:

```bash
./scripts/k8s/install-prerequisites.sh
```

This script will install:
- kubectl (latest stable version)
- kops (latest version)
- helm (v3)

The script supports both macOS and Linux, and handles architecture detection (amd64/arm64).

## Phase 1: KOPS Cluster Setup

### Automated Cluster Bootstrap

The entire cluster setup process has been automated. Simply run:

```bash
./scripts/k8s/bootstrap-cluster.sh
```

This script will:
1. Create S3 bucket for KOPS state
2. Generate SSH keys
3. Create and configure the cluster
4. Deploy the cluster with single-node setup
5. Configure security groups
6. Install core components (NGINX Ingress, cert-manager)

#### Script Options
```bash
# Dry run to see what would be created
./scripts/k8s/bootstrap-cluster.sh --dry-run

# Skip prerequisites check
./scripts/k8s/bootstrap-cluster.sh --skip-prerequisites

# Skip DNS propagation check
./scripts/k8s/bootstrap-cluster.sh --skip-dns-check
```

### Manual Steps (if needed)

If you prefer to run steps manually or need to customize, here are the individual commands:

1. **Create S3 State Store**: Handled by bootstrap script
2. **Environment Variables**: Defined in `scripts/k8s/lib/k8s-common.sh`
3. **SSH Key Generation**: Automatic in bootstrap script
4. **Cluster Creation**: Uses il-central-1 region with proper configuration
5. **Single Node Setup**: Automatically configured with taints removed

## Phase 2: Core Infrastructure Setup

### 2.1 Create Namespaces
```bash
kubectl create namespace apps
kubectl create namespace ingress-nginx
kubectl create namespace cert-manager
```

### 2.2 Install NGINX Ingress Controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.kind=DaemonSet \
  --set controller.hostNetwork=true \
  --set controller.dnsPolicy=ClusterFirstWithHostNet
```

### 2.3 Install Cert-Manager
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s
```

### 2.4 Create Let's Encrypt ClusterIssuer
```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        route53:
          region: us-east-1
          hostedZoneID: Z2O129XK0SJBV9
          accessKeyID: $(aws configure get aws_access_key_id --profile bf)
          secretAccessKeySecretRef:
            name: route53-secret
            key: secret-access-key
---
apiVersion: v1
kind: Secret
metadata:
  name: route53-secret
  namespace: cert-manager
type: Opaque
stringData:
  secret-access-key: $(aws configure get aws_secret_access_key --profile bf)
EOF
```

## Phase 3: Container Registry Setup

### 3.1 Create ECR Repositories
```bash
# Create ECR repos for each app
for app in sample-app sample-3 sample-4; do
  aws ecr create-repository \
    --repository-name $app \
    --region us-east-1 \
    --profile bf
done

# Get registry URL
export ECR_REGISTRY=$(aws ecr describe-repositories --repository-names sample-app --query 'repositories[0].repositoryUri' --output text --profile bf | cut -d'/' -f1)
echo "ECR Registry: $ECR_REGISTRY"
```

### 3.2 Configure Docker Authentication
```bash
aws ecr get-login-password --region us-east-1 --profile bf | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
```

## Phase 4: Application Migration

### 4.1 Build and Push Docker Images
```bash
# For each application
for app in sample-app sample-3 sample-4; do
  echo "Building $app..."
  docker build -t $app:latest apps/$app/
  docker tag $app:latest $ECR_REGISTRY/$app:latest
  docker push $ECR_REGISTRY/$app:latest
done
```

### 4.2 Create Kubernetes Manifests
Create the following structure for each app:

```
apps/
└── sample-app/
    └── k8s/
        ├── deployment.yaml
        ├── service.yaml
        └── ingress.yaml
```

### 4.3 Deploy Applications
```bash
# Apply all manifests for each app
for app in sample-app sample-3 sample-4; do
  kubectl apply -f apps/$app/k8s/ -n apps
done

# Verify deployments
kubectl get pods -n apps
kubectl get ingress -n apps
```

## Phase 5: DNS and Traffic Cutover

### 5.1 Get Node Public IP
```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "Kubernetes Node IP: $NODE_IP"
```

### 5.2 Update Route53 Records
```bash
# Update wildcard A record to point to K8s node
aws route53 change-resource-record-sets \
  --hosted-zone-id Z2O129XK0SJBV9 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.vadimzak.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$NODE_IP'"}]
      }
    }]
  }' \
  --profile bf
```

### 5.3 Verify Applications
```bash
# Test each application
for app in sample sample-3 sample-4; do
  echo "Testing $app.vadimzak.com..."
  curl -s https://$app.vadimzak.com/health | jq .
done
```

## Phase 6: Cleanup Old Infrastructure

### 6.1 Stop Old EC2 Spot Instance
```bash
# Get instance ID
OLD_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=sample-app-server" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text \
  --profile bf)

# Terminate instance
aws ec2 terminate-instances --instance-ids $OLD_INSTANCE_ID --profile bf
```

### 6.2 Archive Old Configurations
```bash
# Create archive directory
mkdir -p archives/docker-compose-setup
mv scripts/docker-compose-infra.yml archives/docker-compose-setup/
# Keep deployment scripts for reference
```

## Phase 7: Post-Migration Setup

### 7.1 Create New Deployment Script
Create `scripts/k8s-deploy.sh` for future deployments.

### 7.2 Update Documentation
- Update CLAUDE.md with K8s commands
- Update DEPLOYMENT.md with new procedures

### 7.3 Set Up Monitoring
```bash
# Simple monitoring with kubectl
kubectl top nodes
kubectl top pods -n apps
```

## Maintenance Commands

### View Cluster Status
```bash
kops validate cluster
kubectl get nodes
kubectl get pods --all-namespaces
```

### Update Application
```bash
./scripts/k8s-deploy.sh app-name
```

### View Logs
```bash
kubectl logs -n apps deployment/sample-app --follow
```

### Scale Application
```bash
kubectl scale deployment/sample-app --replicas=2 -n apps
```

### KOPS Cluster Management
```bash
# Edit cluster
kops edit cluster

# Update cluster
kops update cluster --yes

# Delete cluster (WARNING!)
kops delete cluster --yes
```

## Rollback Plan

If issues arise:
1. Update Route53 to point back to old EC2 IP (if not terminated)
2. Or quickly deploy Docker Compose on new EC2 instance
3. All old configurations are archived for reference

## Cost Breakdown

### Monthly Costs
- EC2 t3.small (on-demand): ~$15/month
- EBS Volumes (30GB): ~$3/month
- Data Transfer: ~$1-2/month
- **Total**: ~$19-20/month

### Cost Comparison
- Previous: ~$3-5/month (spot instance)
- New: ~$19-20/month (on-demand K8s)
- **Increase**: ~4-5x

## Security Considerations

1. **Network Security**
   - Single node exposed on ports 80, 443, 22
   - Security group limits access
   - No internal cluster network needed

2. **Secrets Management**
   - Use Kubernetes Secrets for sensitive data
   - Cert-manager handles SSL certificates

3. **Access Control**
   - kubectl access via kubeconfig
   - SSH access via kops-key

## Troubleshooting

### Common Issues and Solutions

#### DNS Resolution Issues
If you get "dial tcp: lookup api.k8s.vadimzak.com: no such host":
```bash
# Temporarily use IP address
./scripts/k8s/fix-dns.sh --use-ip

# Check cluster status
./scripts/k8s/cluster-status.sh

# Restore DNS when it propagates
./scripts/k8s/fix-dns.sh --restore-dns
```

#### Pod Issues
```bash
kubectl describe pod <pod-name> -n apps
kubectl logs <pod-name> -n apps
```

#### Ingress Controller Issues
- If ingress pod is pending with "didn't have free ports", we use Deployment mode without host networking
- Access via NodePort: http://NODE_IP:30080 or https://NODE_IP:30443
```bash
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
kubectl get events -n ingress-nginx
```

#### Certificate Issues
```bash
kubectl describe certificate -n apps
kubectl logs -n cert-manager deployment/cert-manager
# Check webhook is ready before creating issuers
kubectl get pods -n cert-manager
```

#### Node Issues
```bash
kubectl describe node
ssh -i ~/.ssh/kops-key ubuntu@MASTER_IP
sudo journalctl -u kubelet -n 100
```

#### etcd Issues
If API server crashes with etcd errors:
- Use Kubernetes 1.28.5 (stable version)
- Wait for kops validate cluster to pass
- Check etcd-manager logs: `sudo crictl logs $(sudo crictl ps | grep etcd-manager | awk '{print $1}')`

## Application Deployment

### Configure All Applications
```bash
# This will create ECR repositories, build images, and generate K8s manifests
./scripts/k8s/configure-apps.sh
```

### Deploy Individual Application
```bash
# Full deployment (build, push, deploy)
./scripts/k8s/deploy-app.sh sample-app

# Skip rebuild if image exists
./scripts/k8s/deploy-app.sh sample-app --skip-build

# Rollback to previous version
./scripts/k8s/deploy-app.sh sample-app --rollback
```

### Deploy All Applications
```bash
# Configure and generate manifests for all apps
./scripts/k8s/configure-apps.sh

# Deploy each app
for app in sample-app sample-3 sample-4; do
  ./scripts/k8s/deploy-app.sh $app
done
```

## Cluster Teardown

### Complete Teardown
```bash
# Remove cluster and all AWS resources
./scripts/k8s/teardown-cluster.sh

# Force removal without confirmation
./scripts/k8s/teardown-cluster.sh --force

# Also delete S3 state store
./scripts/k8s/teardown-cluster.sh --delete-state-store

# Also delete local SSH keys and kubeconfig
./scripts/k8s/teardown-cluster.sh --delete-local-config
```

## Important Notes

1. **Region**: Cluster is created in il-central-1 (not us-east-1)
2. **Single Node**: Master node runs workloads (taints removed)
3. **DNS**: Manual update may be needed for api.k8s.vadimzak.com
4. **Costs**: ~$20-25/month (5-6x more than Docker Compose)
5. **Security Groups**: Ports 80, 443, 30080, 30443 are open

## Migration Status

### ✅ Successfully Completed (July 29, 2025)

1. **Cluster Created**: Single-node K8s cluster running on t3.small in il-central-1
2. **Components Installed**:
   - NGINX Ingress Controller (NodePort mode)
   - cert-manager with Let's Encrypt
   - All system pods healthy
3. **Applications Deployed**:
   - sample-app → https://sample.vadimzak.com
   - sample-6 → https://sample-6.vadimzak.com
4. **Infrastructure**:
   - Master IP: 51.16.244.249
   - Wildcard DNS updated
   - SSL certificates auto-provisioning

### Key Scripts Created

- `fix-dns.sh` - Handle DNS resolution issues
- `cluster-status.sh` - Quick health check
- `quick-start.sh` - One-command cluster setup
- `update-wildcard-dns.sh` - Update wildcard DNS record

### Access Applications

**Important**: On a single-node KOPS cluster, port 443 is used by the Kubernetes API server. Applications are accessible via NodePort:

- HTTP: http://sample.vadimzak.com:30080
- HTTPS: https://sample.vadimzak.com:30443 (self-signed cert warning is normal)

For health checks:
```bash
# HTTP
curl http://sample.vadimzak.com:30080/health

# HTTPS (ignore cert warning)
curl -k https://sample.vadimzak.com:30443/health
```

**Note**: In a production multi-node setup, you would use a LoadBalancer service or configure the ingress controller to use host networking on a dedicated node.

## See Also

- [Lessons Learned](./LESSONS_LEARNED.md) - Detailed insights from the migration
- [Deployment Guide](./DEPLOYMENT.md) - Original Docker Compose deployment
## Logging Configuration

The bootstrap scripts now include timestamps in all log messages. You can control the timestamp format using the `LOG_TIMESTAMP_FORMAT` environment variable:

### Timestamp Formats

1. **Full timestamps** (default):
   ```bash
   ./scripts/k8s/bootstrap-cluster.sh
   # Output: [2025-07-30 15:30:47] [INFO] Starting Kubernetes cluster bootstrap...
   ```

2. **Short timestamps** (time only):
   ```bash
   LOG_TIMESTAMP_FORMAT=short ./scripts/k8s/bootstrap-cluster.sh
   # Output: [15:30:47] [INFO] Starting Kubernetes cluster bootstrap...
   ```

3. **No timestamps**:
   ```bash
   LOG_TIMESTAMP_FORMAT=none ./scripts/k8s/bootstrap-cluster.sh
   # Output: [INFO] Starting Kubernetes cluster bootstrap...
   ```

This makes it easier to track timing and debug slow operations during bootstrap.
