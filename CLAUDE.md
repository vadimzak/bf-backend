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
- **Monitoring**: Prometheus + Grafana + Loki stack (internal access via port forwarding)

## Documentation

### Current Implementation Guides
- **HTTPS Port 443 Solution**: See `docs/K8S_HTTPS_PORT_443_SOLUTIONS.md`
- **AWS SDK v3 Migration**: See `docs/AWS_SDK_V3_MIGRATION.md`
- **IRSA Implementation**: See `docs/IRSA_IMPLEMENTATION.md` (comprehensive guide)

### Reference Documentation  
- **Kubernetes Setup**: See `docs/K8S_MIGRATION_PLAN.md`
- **Standard Ports Config**: See `docs/K8S_STANDARD_PORTS_SETUP.md`
- **Elastic IP Troubleshooting**: See `docs/K8S_ELASTIC_IP_TROUBLESHOOTING.md`
- **SSL Implementation**: See `docs/SSL_IMPLEMENTATION_CLEANUP.md`
- **OIDC Provider Management**: See `docs/OIDC_CLEANUP_NOTES.md`
- **Secondary IP Configuration**: See `docs/HTTPS_PORT_443_FIX_SUMMARY.md`
- **Project Status**: See `docs/TODO.md`

**IMPORTANT**: Update these documents with every deployment or dev-ops change

## General Directives

- Always use dark mode design by default
- IMPORTANT: Our whole cloud environment should be bootable  ALL deployment changes must be scripted for reproducibility
- NEVER execute commands that may cause downtime without user permission
- Use `scripts/k8s/` scripts for all Kubernetes operations
- Ensure all changes can recreate infrastructure from scratch

## Dev-Ops scripts

- Do not add fallbacks to dev-ops scripts unless requested, if something fails - the script should fail with a clear message.
- Make sure to have timeouts on commands that may take long time or get stuck, there should be no case where our scripts hang.
- Avoid long (2+ sec) sleeps when waiting for something to be ready, use retry loops instead 
- Play an error sound when scripts fail
- When using `set -u` (or `set -euo pipefail`), be careful with dollar signs in strings - escape them (`\$`) or use single quotes to avoid unbound variable errors (e.g., `echo "Cost: \$3.60"` not `echo "Cost: $3.60"`)

## Architecture Overview

### Kubernetes Infrastructure
- **Cluster**: Single-node KOPS cluster in il-central-1
- **Architecture**: ARM64 (cost savings ~10-20% vs AMD64)
- **Instance Types**: t4g.medium (ARM64)
- **Applications**: Deployed in `apps` namespace
- **Ingress**: NGINX Ingress Controller on NodePorts 30080/30443
- **Standard Ports**: HAProxy on master node for ports 80/443
- **Secondary IP**: Optional setup for HTTPS on port 443
- **Container Registry**: AWS ECR for Docker images
- **SSL/TLS**: cert-manager with Let's Encrypt
- **Monitoring**: Prometheus, Grafana, Loki in `monitoring` namespace

### Application Structure
- **Monorepo**: NX workspace with multiple apps
- **Main Apps**: 
  - `apps/sample-app/` - Main sample application
- **Database**: AWS DynamoDB
- **Health Checks**: `/health` endpoint required

## Kubernetes Commands

### Quick Setup
```bash
# Complete setup with HTTPS on port 443 and monitoring (default)
./scripts/k8s/quick-start-full.sh

# Complete setup without secondary IP (HTTPS only on port 30443)
./scripts/k8s/quick-start-full.sh --no-secondary-ip

# Complete setup without monitoring stack
./scripts/k8s/quick-start-full.sh --skip-monitoring

# Basic setup (ports 30080/30443, no monitoring)
./scripts/k8s/quick-start.sh
```

**Note**: Secondary IP and monitoring stack are now ENABLED BY DEFAULT.
- Secondary IP costs ~$3.60/month but enables HTTPS on port 443
- Monitoring provides Grafana dashboards and Prometheus metrics
- Use `--no-secondary-ip` and `--skip-monitoring` flags to disable if needed

### Application Deployment
```bash
# Configure all apps (build, push to ECR, generate manifests)
./scripts/k8s/configure-apps.sh

# Configure apps with HTTP-only ingress (no HTTPS redirect)
./scripts/k8s/configure-apps.sh --http-only

# Deploy individual app
./scripts/k8s/deploy-app.sh <app-name>

# Delete individual app (including ECR repository)
./scripts/k8s/delete-app.sh <app-name>

# Delete app but keep ECR repository
./scripts/k8s/delete-app.sh <app-name> --keep-ecr

# Check cluster status
./scripts/k8s/cluster-status.sh
```

### Cluster Management
```bash
# Bootstrap new cluster (ARM64 with secondary IP by default)
./scripts/k8s/bootstrap-cluster.sh

# Bootstrap without secondary IP
./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip

# Teardown cluster
./scripts/k8s/teardown-cluster.sh

# Fix DNS issues
./scripts/k8s/fix-dns.sh --use-ip
```

### ECR Repository Management
```bash
# Delete ECR repositories for specific apps
./scripts/k8s/delete-app-ecr.sh --app <app-name>

# Delete multiple ECR repositories
./scripts/k8s/delete-app-ecr.sh --app app1 --app app2

# Force delete repositories even with images
./scripts/k8s/delete-app-ecr.sh --force --app <app-name>

# Show what would be deleted (dry run)
./scripts/k8s/delete-app-ecr.sh --dry-run

# Delete all detected app ECR repositories
./scripts/k8s/delete-app-ecr.sh --force
```

### Monitoring Stack
```bash
# Install monitoring stack (Prometheus, Grafana, Loki)
./scripts/k8s/install-monitoring.sh

# Uninstall monitoring stack
./scripts/k8s/install-monitoring.sh --uninstall

# Setup port forwarding for monitoring services
./scripts/k8s/setup-monitoring-portforward.sh

# Forward specific service only
./scripts/k8s/setup-monitoring-portforward.sh grafana
./scripts/k8s/setup-monitoring-portforward.sh prometheus

# Stop all port forwarding
./scripts/k8s/setup-monitoring-portforward.sh --stop

# Import pre-configured Kubernetes dashboards
./scripts/k8s/setup-monitoring-dashboards.sh

# Import specific dashboard
./scripts/k8s/setup-monitoring-dashboards.sh kubernetes-cluster-overview
```

**Monitoring URLs (after port forwarding):**
- **Grafana**: http://localhost:3000 (dashboards and visualization)
- **Prometheus**: http://localhost:9090 (metrics and queries)
- **Loki**: http://localhost:3100 (log queries)
- **AlertManager**: http://localhost:9093 (alert management)

**Access**: Grafana uses anonymous authentication by default - no login required.

**Pre-configured Dashboards**: 20+ Kubernetes monitoring dashboards including:
- Cluster resource monitoring (CPU, Memory, Storage)
- Node and pod metrics
- Networking dashboards
- AlertManager overview
- CoreDNS monitoring

**Note**: All monitoring services are internal-only (ClusterIP) for security. Access via port forwarding only.

**Troubleshooting**: If Grafana shows login page or appears empty, see `docs/GRAFANA_AUTH_TROUBLESHOOTING.md`

## Secondary IP Solution for HTTPS

**Note**: Secondary IP is now ENABLED BY DEFAULT when bootstrapping clusters.

### Option 1: New Cluster (Secondary IP is automatic)
```bash
# HTTPS on port 443 is enabled by default
./scripts/k8s/quick-start-full.sh

# Or explicitly with bootstrap
./scripts/k8s/bootstrap-cluster.sh  # Secondary IP enabled by default
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
- `bootstrap-cluster.sh` - Create KOPS cluster (secondary IP enabled by default, use `--no-secondary-ip` to disable)
- `configure-apps.sh` - Setup ECR and build images
- `deploy-app.sh` - Deploy app to Kubernetes (fixed for NX monorepo)
- `delete-app.sh` - Delete app from Kubernetes and ECR repository
- `delete-app-ecr.sh` - Delete ECR repositories for specific apps
- `setup-haproxy.sh` - Configure HTTP on port 80
- `setup-haproxy-https.sh` - Configure HTTP/HTTPS with secondary IP
- `setup-secondary-ip.sh` - Setup secondary IP for HTTPS on port 443 (supports `--dry-run`)
- `cleanup-secondary-ip.sh` - Clean up secondary IP resources and unused Elastic IPs
- `diagnose-secondary-ip.sh` - Diagnose secondary IP setup issues
- `quick-start-full.sh` - One-command full setup (secondary IP enabled by default)
- `teardown-cluster.sh` - Remove cluster (now includes ECR and secondary IP cleanup)
- `cluster-status.sh` - Health check
- `update-wildcard-dns.sh` - Update DNS records
- `update-app-dns-secondary.sh` - Update DNS to use secondary IP
- `toggle-https-redirect.sh` - Enable/disable HTTPS redirect for all apps (useful during Let's Encrypt rate limits)

**Recent Improvements (July 2025):**
- Secondary IP now ENABLED BY DEFAULT (opt-out with `--no-secondary-ip`)
- Fixed setup-secondary-ip.sh hanging issues (added timeouts, stderr redirects)
- Simplified IP allocation (now uses AWS auto-assign)
- Added --dry-run mode for testing
- Fixed NX monorepo Docker builds in deploy-app.sh
- Added Elastic IP limit checking and automatic reuse of unassociated IPs
- Created cleanup-secondary-ip.sh script for resource management
- Integrated secondary IP cleanup into teardown process
- Improved error messages with specific resolution steps
- Added comprehensive Elastic IP troubleshooting guide
- **Bootstrap Optimizations (July 30)**:
  - Fixed unbound variable bug in setup-secondary-ip.sh (line 764: `$3.60` interpreted as `$3` + `.60`)
  - Reduced retries from 3 to 2 (saves ~8 seconds)
  - Removed redundant verification (saves ~30 seconds)
  - Added timestamps to all log messages (configurable via LOG_TIMESTAMP_FORMAT)
  - Overall bootstrap time reduced by ~2.5-3 minutes
  - Added HTTP-only mode support for Let's Encrypt rate limit situations:
    - New `toggle-https-redirect.sh` script to enable/disable HTTPS redirect
    - Added `--http-only` flag to `configure-apps.sh` for generating HTTP-only ingress
- **ECR Cleanup (July 30)**:
  - Added ECR repository deletion functions to `k8s-common.sh`
  - Created `delete-app.sh` script for complete app deletion (K8s + ECR)
  - Created `delete-app-ecr.sh` script for ECR-only cleanup
  - Integrated ECR cleanup into `teardown-cluster.sh`
  - All ECR scripts support dry-run mode and force deletion

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

### With HAProxy (HTTP only):
- http://sample.vadimzak.com
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

## Deployment Prerequisites (Updated July 2025)

### Application Requirements
Before deploying any application, ensure it meets these requirements:

1. **AWS SDK v3**: Use latest v3 packages for IRSA compatibility
2. **Package.json**: Include IRSA-compatible AWS SDK dependencies
3. **IAM Setup**: Each app must have dedicated IAM role and policy
4. **Service Account**: Kubernetes service account with IRSA annotations
5. **Environment Variables**: IRSA credentials configuration in deployment

### Automatic Validation
The deployment scripts now automatically validate:
- ✅ IAM role existence and configuration
- ✅ Service account setup with correct annotations
- ✅ AWS SDK v3 package compatibility
- ✅ IRSA environment variable configuration
- ✅ Trust policy OIDC provider compatibility

### Pre-deployment Checklist
```bash
# 1. Verify app has IRSA setup
ls apps/<app-name>/aws/iam/

# 2. Check AWS SDK v3 dependencies
grep "@aws-sdk" apps/<app-name>/package.json

# 3. Validate deployment configuration
./scripts/k8s/deploy-app.sh <app-name> --build-only

# 4. Deploy with IAM setup if needed
./scripts/k8s/deploy-app.sh <app-name> --setup-iam
```

## Development Workflow

### Local Development

#### First-time Setup (per app)
```bash
# Create IAM role with minimal permissions (run once per app)
apps/<app-name>/aws/iam/setup-iam.sh

# Or use deployment script with IAM setup
./scripts/k8s/deploy-app.sh <app-name> --setup-iam
```

#### Daily Development
```bash
# Preferred: Use npm script (handles credentials automatically)
npm run dev:<app-name>

# Alternative: Navigate to app directory
cd apps/<app-name>
npm install

# Use development script with credential setup
./dev-with-creds.sh

# Or manually assume role and start
./aws/iam/local-dev-setup.sh && npm run dev
```

#### Development Features
- **Automatic credential renewal**: npm scripts handle IAM role assumption
- **Minimal permissions**: Local development uses same restricted permissions as production
- **1-hour sessions**: Credentials automatically expire for security
- **No personal credentials**: Development never uses your main AWS credentials

### Deploy Changes
```bash
# Build and deploy (validates IAM setup)
./scripts/k8s/deploy-app.sh <app-name>

# Deploy with automatic IAM setup if missing
./scripts/k8s/deploy-app.sh <app-name> --setup-iam

# Build only (useful for testing IAM validation)
./scripts/k8s/deploy-app.sh <app-name> --build-only
```

## Important Considerations

1. **Single Node Limitation**: API server uses port 443 (resolved with secondary IP solution)
2. **Cost**: ~$20-25/month (on-demand t3.small instance) + $3.60/month for secondary IP (optional)
3. **DNS**: Uses wildcard DNS (*.vadimzak.com)
4. **Security Groups**: Managed by KOPS, additional ports via scripts
5. **SSL/TLS**: Full HTTPS support available with secondary IP solution

## Handling Let's Encrypt Rate Limits

When hitting Let's Encrypt rate limits, you can temporarily allow HTTP-only access:

### Option 1: Toggle HTTPS Redirect for Existing Apps
```bash
# Disable HTTPS redirect (allow HTTP access)
./scripts/k8s/toggle-https-redirect.sh --disable-https

# Re-enable HTTPS redirect when rate limits are resolved
./scripts/k8s/toggle-https-redirect.sh --enable-https
```

### Option 2: Generate HTTP-Only Ingress from Start
```bash
# Generate manifests without HTTPS/TLS configuration
./scripts/k8s/configure-apps.sh --http-only

# Deploy as normal
./scripts/k8s/deploy-app.sh <app-name>
```

**Note**: HTTP-only mode should be temporary. Re-enable HTTPS as soon as rate limits allow.

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

Current setup (~$18-22/month with ARM64):
- Single t4g.medium instance (on-demand, ARM64)
- 10-20% cost savings vs AMD64 equivalent
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

## IAM Security Architecture (IRSA)

**IMPORTANT**: Each application now uses IRSA (IAM Roles for Service Accounts) with minimal permissions through dedicated roles.

### IRSA Implementation Status ✅
- **AWS SDK**: Upgraded to v3 with full IRSA support
- **Service Account Tokens**: Using S3-based OIDC provider (`https://bf-kops-oidc-store.s3.il-central-1.amazonaws.com`)
- **Credential Management**: Automatic role assumption via Kubernetes service accounts
- **Production Ready**: All apps use IRSA for AWS service access

### Recent IRSA Fixes (July 31, 2025)
1. **OIDC Provider Configuration**: Fixed JWT token audience mismatch
2. **Cluster Configuration**: Updated serviceAccountIssuer to use S3-based OIDC
3. **Trust Policies**: Corrected audience from `sts.amazonaws.com` to `kubernetes.svc.default`
4. **Client ID Setup**: Added `kubernetes.svc.default` to OIDC provider client IDs
5. **AWS SDK v3 Migration**: Complete migration from v2 to v3 with IRSA support

### AWS SDK v3 Migration Details ✅
- **Packages Updated**: `aws-sdk` v2 → `@aws-sdk/client-*` v3.857.0
- **DynamoDB**: `AWS.DynamoDB.DocumentClient` → `DynamoDBDocumentClient` with command pattern
- **Secrets Manager**: `AWS.SecretsManager` → `SecretsManagerClient` with `GetSecretValueCommand`
- **Credential Provider**: Automatic IRSA detection via environment variables
- **Command Pattern**: All operations use new `send(command)` pattern

### Per-App IAM Roles

Each application has its own IAM role with minimal required permissions:

- **Role naming**: `{app-name}-app-role` (e.g., `gamani-app-role`)
- **Policy naming**: `{app-name}-app-policy` (e.g., `gamani-app-policy`)
- **Principle of least privilege**: Only permissions needed for app functionality

### IAM Directory Structure

Each app should have an `aws/iam/` directory:
```
apps/{app-name}/aws/iam/
├── setup-iam.sh              # Creates/updates IAM role and policy
├── permissions-policy.json   # Minimal permissions for the app
├── role-policy.json          # Trust policy (who can assume the role)
└── local-dev-setup.sh        # Assume role for local development
```

### IRSA Configuration Example (Gamani App)

**Trust Policy** (`apps/gamani/aws/iam/role-policy.json`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::363397505860:oidc-provider/bf-kops-oidc-store.s3.il-central-1.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "bf-kops-oidc-store.s3.il-central-1.amazonaws.com:sub": "system:serviceaccount:apps:gamani-service-account",
          "bf-kops-oidc-store.s3.il-central-1.amazonaws.com:aud": "kubernetes.svc.default"
        }
      }
    }
  ]
}
```

**Service Account Configuration**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gamani-service-account
  namespace: apps
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::363397505860:role/gamani-app-role
```

**Deployment Environment Variables**:
```yaml
env:
- name: AWS_ROLE_ARN
  value: "arn:aws:iam::363397505860:role/gamani-app-role"
- name: AWS_WEB_IDENTITY_TOKEN_FILE
  value: "/var/run/secrets/kubernetes.io/serviceaccount/token"
```

### Development vs Production Credentials

#### Local Development
```bash
# Navigate to app directory
cd apps/{app-name}

# Assume role with minimal permissions (1-hour session)
./aws/iam/local-dev-setup.sh

# Or use the development wrapper script
./dev-with-creds.sh

# Or use npm script (preferred)
npm run dev:{app-name}
```

#### Production Deployment
- **Kubernetes Service Account**: Each app has a dedicated service account
- **Service Account Annotation**: Links to the IAM role via IRSA-style annotation
- **EC2 Instance Role**: Master node assumes app roles on behalf of service accounts

### IAM Setup Commands

#### Create IAM Role for New App
```bash
# Create IAM infrastructure (run once per app)
apps/{app-name}/aws/iam/setup-iam.sh

# Deploy with automatic IAM setup
./scripts/k8s/deploy-app.sh {app-name} --setup-iam

# Verify IAM setup
./scripts/k8s/deploy-app.sh {app-name} --build-only  # Includes validation
```

#### Update IAM Permissions
```bash
# Modify apps/{app-name}/aws/iam/permissions-policy.json
# Then run:
apps/{app-name}/aws/iam/setup-iam.sh
```

### Security Best Practices

1. **Minimal Permissions**: Each app only gets permissions it actually needs
2. **Time-Limited Sessions**: Local development uses 1-hour assumed role sessions
3. **No Hardcoded Credentials**: Never store credentials in code or manifests
4. **Service Account Isolation**: Each app has its own Kubernetes service account
5. **Regular Rotation**: Assumed role sessions automatically expire

### Example IAM Permissions (Gamani App)

**Permissions Policy** (`apps/gamani/aws/iam/permissions-policy.json`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem", 
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": [
        "arn:aws:dynamodb:il-central-1:363397505860:table/gamani-items"
      ]
    }
  ]
}
```

**Trust Policy** (`apps/gamani/aws/iam/role-policy.json`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::363397505860:user/vadim-cli"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "gamani-app-local-dev"
        }
      }
    }
  ]
}
```

### Troubleshooting IRSA Issues

#### Common IRSA Problems
```bash
# Check JWT token issuer and audience
kubectl exec -n apps deployment/<app-name> -- sh -c 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); echo $TOKEN | cut -d"." -f2 | base64 -d 2>/dev/null'

# Verify OIDC provider configuration
aws iam get-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::363397505860:oidc-provider/bf-kops-oidc-store.s3.il-central-1.amazonaws.com --profile bf

# Check service account annotations
kubectl get serviceaccount <app-name>-service-account -n apps -o yaml

# Test role assumption
kubectl exec -n apps deployment/<app-name> -- env | grep AWS_
```

#### OIDC Verification Errors
If you see "Couldn't retrieve verification key from your identity provider":
1. Ensure cluster uses S3-based OIDC issuer
2. Verify OIDC provider client IDs include `kubernetes.svc.default`
3. Check trust policy audience matches JWT token audience
4. Confirm serviceAccountIssuer in cluster configuration

#### Common Issues
```bash
# Check if IAM role exists
aws iam get-role --role-name {app-name}-app-role --profile bf

# Validate IAM setup for app
./scripts/k8s/deploy-app.sh {app-name} --build-only

# Check service account in cluster
kubectl get serviceaccount {app-name}-service-account -n apps

# Check assumed role credentials
cd apps/{app-name} && ./aws/iam/local-dev-setup.sh eval
```

#### Missing IAM Setup
If deployment fails with IAM warnings:
1. Run `./scripts/k8s/deploy-app.sh {app-name} --setup-iam`
2. Or manually: `apps/{app-name}/aws/iam/setup-iam.sh`

#### Credential Expiration
Local development credentials expire after 1 hour:
```bash
# Re-assume role when credentials expire
npm run dev:{app-name}  # Automatically renews credentials
```

## Migration Notes

When migrating from Docker Compose:
1. Build Docker images with same functionality
2. Create Kubernetes manifests
3. Use NodePort services for ingress
4. Configure HAProxy for standard ports
5. Update DNS to point to master node IP

## MISC

- Use AWS Secrets Manager for secrets instead of K8S Secrets
- Never deploy without permission
- Always install the latest versions of NPM packages, Fetch latest version from https://www.npmjs.com, NEVER assume a version without consulting a tool or MCP
- Use Playwrite MCP to perform e2e borwser tests
- TypeScript - use types instead of interfaces
- don't prematurely put in ENV vars values that do not have different values
- check TS errors before completing or deploying
- prefer to fail the server init if something is wrong (missing permissions / service fails to init)
- IMPORTANT! do not deploy to prod without my permission
- when I ask you to fix a problem, and you find a problem and fix it, don't be sure you fixed THE problem, you may have fixed another problem. either check yourself, or state that you fixed something, but don't say that the problem I reported is fixed