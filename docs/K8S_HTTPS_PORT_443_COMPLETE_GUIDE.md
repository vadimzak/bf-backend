# Kubernetes HTTPS Port 443 Complete Guide

This document provides a comprehensive guide to resolving the HTTPS port 443 conflict on single-node Kubernetes clusters deployed with KOPS on AWS, including troubleshooting, SSL implementation, and standard ports setup.

## Problem Statement

On a single-node Kubernetes cluster deployed with KOPS on AWS, both the Kubernetes API server and application ingress need port 443, creating a conflict. This document covers the evolution of the solution, all attempted approaches, and the current working implementation.

## Current Status (July 2025)

✅ **SOLVED**: Secondary IP solution is fully implemented and enabled by default
- HTTPS works on standard port 443 for all applications
- API server remains accessible on primary IP
- Cost: ~$3.60/month for secondary Elastic IP
- Fully automated in bootstrap scripts
- Comprehensive error handling and cleanup tools

## The Working Solution

### Architecture Overview

```
┌─────────────────┐
│    Internet     │
└────────┬────────┘
         │
    ┌────┴────┐
    │Route 53 │
    └────┬────┘
         │
┌────────┴────────────────────────┐
│   ┌─────────────┐               │
│   │ Primary IP  │               │
│   │51.16.46.89  │               │
│   │   Port 443  │               │
│   │ (API Server)├──→ Kubernetes API
│   └─────────────┘               │
│                                 │
│   ┌─────────────┐               │
│   │Secondary IP │               │
│   │51.84.199.169│               │
│   │  Port 443   │               │
│   │  (HAProxy)  ├──→ localhost:30443 (Ingress)
│   │  Port 80    ├──→ localhost:30080 (Ingress)
│   └─────────────┘               │
│                                 │
│        EC2 Instance             │
└─────────────────────────────────┘
```

### Key Innovation: iptables PREROUTING Redirect

The breakthrough that made this solution work was using iptables PREROUTING to redirect traffic:

```bash
sudo iptables -t nat -A PREROUTING -d <secondary-private-ip> -p tcp --dport 443 -j REDIRECT --to-port 8443
```

This allows HAProxy to listen on port 8443 (avoiding the conflict) while still receiving traffic that arrives on port 443.

### Traffic Flow

1. HTTPS request to `sample.vadimzak.com` → Secondary IP (51.84.153.25)
2. iptables redirects port 443 → 8443 on secondary private IP (172.20.213.46)
3. HAProxy receives on port 8443
4. HAProxy routes based on SNI to ingress controller (port 30443)
5. Ingress forwards to application pod

## Default Behavior Change (July 2025)

Secondary IP setup is now **ENABLED BY DEFAULT** when bootstrapping Kubernetes clusters.

### Before vs After

**Before:**
```bash
# Had to explicitly enable secondary IP
./scripts/k8s/bootstrap-cluster.sh --with-secondary-ip
./scripts/k8s/quick-start-full.sh --with-secondary-ip
```

**After:**
```bash
# Secondary IP is enabled by default
./scripts/k8s/bootstrap-cluster.sh
./scripts/k8s/quick-start-full.sh

# To disable (and save $3.60/month)
./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip
./scripts/k8s/quick-start-full.sh --no-secondary-ip
```

### Why This Change?

1. **Better User Experience**: HTTPS on port 443 works by default
2. **Standard Expectations**: Users expect HTTPS to work on standard ports
3. **Minimal Cost**: Only ~$3.60/month for the secondary Elastic IP
4. **Opt-out Available**: Users who want to save money can still disable it

## Complete Implementation History

### The Problem Discovery

After running the full cluster setup (`bootstrap-cluster.sh` → `configure-apps.sh` → `deploy-app.sh`), HTTPS on port 443 was not working. The application was only accessible on non-standard ports (30080/30443).

### Root Cause Analysis

The `setup-secondary-ip.sh` script was hanging during execution due to:
1. Log messages being captured in command substitution (functions returning values)
2. Missing timeouts on AWS CLI commands
3. IP generation logic issues for /16 subnets

This caused the bootstrap script to skip the secondary IP setup with a warning.

### Manual Implementation Steps

Since the script was hanging, we manually configured the secondary IP:

```bash
# 1. Allocate secondary private IP
aws ec2 assign-private-ip-addresses \
    --network-interface-id eni-023e03ab1e3ae5bd9 \
    --secondary-private-ip-address-count 1
# Result: 172.20.213.46

# 2. Allocate Elastic IP
aws ec2 allocate-address --domain vpc
# Result: 51.84.153.25 (eipalloc-059b3d4723e924b07)

# 3. Associate Elastic IP with secondary private IP
aws ec2 associate-address \
    --allocation-id eipalloc-059b3d4723e924b07 \
    --network-interface-id eni-023e03ab1e3ae5bd9 \
    --private-ip-address 172.20.213.46

# 4. Configure instance networking
sudo ip addr add 172.20.213.46/16 dev ens5

# 5. Set up iptables PREROUTING redirect (KEY INNOVATION!)
sudo iptables -t nat -A PREROUTING -d 172.20.213.46 -p tcp --dport 443 -j REDIRECT --to-port 8443

# 6. Make persistent
sudo apt-get install -y iptables-persistent netfilter-persistent
sudo netfilter-persistent save
```

### HAProxy Configuration

Ran `./scripts/k8s/setup-haproxy-https.sh` which:
- Installed HAProxy
- Configured it to listen on port 8443 (not 443)
- Set up SNI-based routing:
  - `api.k8s.vadimzak.com` → API server (127.0.0.1:443)
  - `*.vadimzak.com` → Ingress controller (127.0.0.1:30443)

### DNS Updates

Ran `./scripts/k8s/update-app-dns-secondary.sh` which:
- Updated `*.vadimzak.com` → 51.84.153.25 (secondary IP)
- Kept `api.k8s.vadimzak.com` → 51.16.45.179 (primary IP)

### Script Fixes Applied (July 2025)

**setup-secondary-ip.sh improvements:**
1. Added `>&2` to redirect log messages to stderr in functions that return values
2. Added `timeout` commands to AWS CLI calls to prevent hanging
3. Fixed IP generation logic for /16 subnets
4. Reduced retries from 3 to 2 (saves ~8 seconds)
5. Removed redundant verification (saves ~30 seconds)
6. Added timestamps to all log messages
7. Fixed unbound variable bug (`$3.60` interpreted as `$3` + `.60`)
8. Added Elastic IP limit checking and automatic reuse
9. Integrated comprehensive error handling

## All Attempted Solutions

| Solution | Status | Result |
|----------|--------|--------|
| Option 1: Move API Server to Different Port | ❌ FAILED | KOPS validation stuck |
| Option 2: API Server Bind to Localhost | ❌ FAILED | KOPS overrides configuration |
| Option 3: Secondary IP Address | ✅ SUCCESS | Working solution! |
| Option 4: iptables PREROUTING | ❌ ATTEMPTED | Doesn't solve binding conflict |
| Option 5: IPVS/iptables with Marks | 🔄 NOT TESTED | Too complex |
| Option 6: socat/stunnel | ❌ FAILED | Same binding conflicts |
| Option 7: Network Namespaces | 🔄 NOT TESTED | Too complex/risky |
| Option 8: NGINX Stream Module | 🔄 NOT TESTED | Same as HAProxy |
| Option 9: SSH Tunnel | 🔄 NOT TESTED | Not practical |
| Option 10: API Server Subpath | ❌ IMPOSSIBLE | Not supported |
| Option 11: TCP Multiplexer (sslh) | 🔄 NOT TESTED | Same binding issues |
| Option 12: Container Network Magic | 🔄 NOT TESTED | Too fragile |

### Failed Solution Details

#### Option 1: Move API Server to Different Port

**What we tried:**
```bash
# Modified /etc/kubernetes/manifests/kube-apiserver.manifest
--secure-port=8443  # or 6443
```

**Result:**
- Manifest updated successfully
- API server restarted on new port
- Cluster validation stuck: "Still waiting for cluster validation..."
- Components couldn't connect to API server

**Root cause:**
- KOPS hardcodes port 443 in multiple places
- kubelet, health checks, etcd expect API on 443
- No central configuration to change this

#### Option 2: API Server Bind to Localhost Only

**What we tried:**
```bash
# Modified manifest to bind to localhost
--bind-address=127.0.0.1
--secure-port=443
```

**Result:**
- KOPS injected duplicate arguments:
  ```
  --bind-address=0.0.0.0
  --secure-port=8443
  --bind-address=127.0.0.1
  ```
- API server used last argument (localhost)
- Mysteriously bound to localhost:8443 instead of 443
- Certificate validation failed (no IP SANs for 127.0.0.1)
- Cluster became unstable

**Root cause:**
- KOPS runtime configuration management overrides manual changes
- Unknown mechanism changing port from 443 to 8443
- Certificate issues with localhost binding

## Elastic IP Troubleshooting

### Common Error: "Secondary IP exists but has no public IP associated"

This error occurs when the secondary IP setup succeeds but AWS cannot allocate an Elastic IP due to account limits.

#### Quick Resolution Steps

1. **Check your current Elastic IP usage**:
   ```bash
   ./scripts/k8s/cleanup-secondary-ip.sh --dry-run
   ```

2. **Release unused Elastic IPs**:
   ```bash
   ./scripts/k8s/cleanup-secondary-ip.sh
   ```

3. **If still at limit, request an increase**:
   ```bash
   aws service-quotas request-service-quota-increase \
     --service-code ec2 --quota-code L-0263D0A3 \
     --desired-value 10 --region il-central-1 --profile bf
   ```

4. **Or use the cluster without secondary IP** (HTTPS on port 30443):
   ```bash
   ./scripts/k8s/teardown-cluster.sh
   ./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip
   ```

#### Understanding AWS Elastic IP Limits

- Default limit: 5 Elastic IPs per region
- Each secondary IP for HTTPS requires 1 Elastic IP
- The limit applies to all EC2 resources in the region

#### Improved Error Handling (July 2025)

The scripts now include:
1. **Pre-allocation checks**: Verifies available Elastic IPs before attempting allocation
2. **Automatic reuse**: Finds and reuses unassociated Elastic IPs
3. **Clear error messages**: Provides specific steps to resolve issues
4. **Cleanup integration**: `teardown-cluster.sh` now cleans up secondary IP resources

#### New Cleanup Script

The `cleanup-secondary-ip.sh` script helps manage Elastic IP resources:

```bash
# Check what would be cleaned up
./scripts/k8s/cleanup-secondary-ip.sh --dry-run

# Clean up with confirmation prompts
./scripts/k8s/cleanup-secondary-ip.sh

# Force cleanup without prompts
./scripts/k8s/cleanup-secondary-ip.sh --force
```

## Standard Ports Implementation

### Current Status

- **HTTP (Port 80)**: ✅ Working via HAProxy on secondary IP
- **HTTPS (Port 443)**: ✅ Working via HAProxy on secondary IP for applications
- **API Server (Port 443)**: ✅ Working on primary IP
- **Applications**: Fully accessible on standard ports without port numbers
- **HAProxy Stats**: ✅ Available on port 8404

### Traffic Flow for Standard Ports

1. HTTP requests on port 80 → HAProxy (secondary IP)
2. HAProxy forwards to localhost:30080 (NGINX Ingress NodePort)
3. NGINX Ingress routes based on hostname to appropriate service
4. Service forwards to application pods

### Security Group Configuration

The following ports are open:
- **22**: SSH
- **80**: HTTP (HAProxy)
- **443**: HTTPS (Kubernetes API + HAProxy)
- **30080**: NodePort HTTP (internal)
- **30443**: NodePort HTTPS
- **8404**: HAProxy stats

## Key Discoveries

1. **KOPS Configuration Override:**
   - KOPS has runtime configuration management
   - Actively prevents API server binding modifications
   - Injects duplicate command-line arguments
   - Safety mechanism to prevent cluster lockout

2. **Port 8443 Mystery:**
   - When binding to localhost, API server uses port 8443
   - Even when manifest specifies port 443
   - Appears to be hardcoded behavior

3. **Certificate Requirements:**
   - API server certificates don't include IP SANs for 127.0.0.1
   - Causes validation failures when binding to localhost
   - Would need certificate regeneration

4. **Component Dependencies:**
   - kubelet expects API on standard location
   - Health checks hardcoded to port 443
   - etcd configuration expects standard ports

## Usage Examples

### Quick Setup Commands

```bash
# Complete setup with HTTPS on port 443 (default)
./scripts/k8s/quick-start-full.sh

# Complete setup without secondary IP (HTTPS only on port 30443)
./scripts/k8s/quick-start-full.sh --no-secondary-ip

# Basic setup (ports 30080/30443)
./scripts/k8s/quick-start.sh
```

### Application Access

**With Secondary IP (Default):**
- ✅ `https://app.vadimzak.com` - Works on standard port 443
- ✅ `http://app.vadimzak.com` - Works on standard port 80
- 💰 Additional cost: ~$3.60/month

**Without Secondary IP (Opt-out):**
- ❌ `https://app.vadimzak.com` - Does NOT work
- ✅ `https://app.vadimzak.com:30443` - Works on non-standard port
- ✅ `http://app.vadimzak.com` - Works on standard port 80
- 💰 No additional cost

## Scripts Created/Modified

### Core Scripts
1. **setup-secondary-ip.sh** - Secondary IP allocation and configuration
2. **setup-haproxy-https.sh** - HAProxy configuration for HTTPS
3. **update-app-dns-secondary.sh** - Updates DNS to use secondary IP
4. **quick-start-full.sh** - One-command full setup
5. **bootstrap-cluster.sh** - Cluster creation with secondary IP by default

### Troubleshooting Scripts
6. **cleanup-secondary-ip.sh** - Manages Elastic IP resources
7. **diagnose-secondary-ip.sh** - Diagnostic tool for secondary IP issues
8. **toggle-https-redirect.sh** - Enable/disable HTTPS redirect for all apps

### Updated Scripts
9. **configure-apps.sh** - Added secondary IP detection and HTTP-only mode
10. **deploy-app.sh** - Detects secondary IP setup and shows correct URLs
11. **teardown-cluster.sh** - Integrated ECR and secondary IP cleanup

## SSL Implementation Summary

### What Was Fixed

1. **Secondary IP Setup Script Hanging**
   - Added proper error handling for AWS API calls
   - Implemented the iptables PREROUTING redirect directly in the script
   - Updated HAProxy configuration to bind to port 8443 instead of 443

2. **Implemented the ONLY Working Solution**
   - Allocate secondary private IP on the EC2 instance
   - Associate an Elastic IP with the secondary IP
   - Configure iptables PREROUTING to redirect port 443 → 8443
   - HAProxy listens on port 8443 and routes based on SNI
   - DNS: apps use secondary IP, API server uses primary IP

3. **Key Innovation: iptables PREROUTING**
   ```bash
   sudo iptables -t nat -A PREROUTING -d <secondary-private-ip> -p tcp --dport 443 -j REDIRECT --to-port 8443
   ```
   This allows HAProxy to receive HTTPS traffic without binding to port 443 directly.

### Current Working Setup

**IPs and Routing:**
- **Primary IP**: Kubernetes API server on port 443
- **Secondary IP**: Application traffic on ports 80/443

**DNS Configuration:**
- `api.k8s.vadimzak.com` → Primary IP
- `*.vadimzak.com` → Secondary IP

## Cost Analysis

| Solution | Monthly Cost | Complexity |
|----------|-------------|------------|
| Current (Secondary IP) | +$3.60 | Medium |
| Multi-node cluster | +$15-20 | High |
| External LB | +$10-15 | Medium |
| Accept limitation | $0 | Low |

### Cost Considerations

- Secondary IP with Elastic IP: ~$3.60/month
- Without secondary IP: No additional cost, but HTTPS only on port 30443
- The secondary IP adds value by providing standard port access

## Commands Reference

```bash
# Check what's listening on ports
sudo ss -tlnp | grep -E ':443|:8443'

# Check API server arguments
ps aux | grep kube-apiserver | tr ' ' '\n' | grep -E 'bind-address|secure-port'

# Test API access
curl -k https://api.k8s.vadimzak.com/healthz

# Test app access
curl -s https://sample.vadimzak.com/health

# Check HAProxy stats
curl http://51.84.199.169:8404/stats

# Check secondary IP configuration
ip addr show ens5
sudo iptables -t nat -L PREROUTING -n --line-numbers

# Check all Elastic IPs in your account
aws ec2 describe-addresses --profile bf --region il-central-1 \
  --query 'Addresses[].[PublicIp,AssociationId,InstanceId]' \
  --output table

# Check your current limit
aws service-quotas get-service-quota \
  --service-code ec2 --quota-code L-0263D0A3 \
  --region il-central-1 --profile bf

# Run full diagnostics
./scripts/k8s/diagnose-secondary-ip.sh
```

## Troubleshooting

### API Server Not Accessible
```bash
# Check API server is running
sudo crictl ps | grep apiserver

# Check listening ports
sudo ss -tlnp | grep -E ':443|:8443'

# Check certificates
kubectl config view --minify
```

### Applications Not Accessible
```bash
# Check HAProxy
sudo systemctl status haproxy

# Check ingress controller
kubectl get pods -n ingress-nginx

# Check DNS resolution
dig sample.vadimzak.com

# Check secondary IP
ip addr show ens5 | grep "172.20"

# Check iptables rules
sudo iptables -t nat -L PREROUTING -n
```

### Secondary IP Issues
```bash
# Check AWS association
aws ec2 describe-network-interfaces --network-interface-ids eni-023e03ab1e3ae5bd9 --profile bf

# Check Elastic IP
aws ec2 describe-addresses --profile bf

# Verify iptables redirect
sudo iptables -t nat -L PREROUTING -n --line-numbers | grep 8443

# Check HTTPS works
curl -k https://sample.vadimzak.com/health

# Check iptables rule
sudo iptables -t nat -L PREROUTING -n -v | grep 443

# Check HAProxy status
sudo systemctl status haproxy

# Check what's listening
sudo ss -tlnp | grep -E ':443|:8443'
```

### SSL/TLS Considerations

Currently, SSL termination happens at the ingress controller level. For production:
1. Configure cert-manager for Let's Encrypt certificates
2. Use AWS Load Balancer for proper SSL termination
3. Or implement SNI-based routing with HAProxy

### Handling Let's Encrypt Rate Limits

When hitting Let's Encrypt rate limits, you can temporarily allow HTTP-only access:

#### Option 1: Toggle HTTPS Redirect for Existing Apps
```bash
# Disable HTTPS redirect (allow HTTP access)
./scripts/k8s/toggle-https-redirect.sh --disable-https

# Re-enable HTTPS redirect when rate limits are resolved
./scripts/k8s/toggle-https-redirect.sh --enable-https
```

#### Option 2: Generate HTTP-Only Ingress from Start
```bash
# Generate manifests without HTTPS/TLS configuration
./scripts/k8s/configure-apps.sh --http-only

# Deploy as normal
./scripts/k8s/deploy-app.sh <app-name>
```

**Note**: HTTP-only mode should be temporary. Re-enable HTTPS as soon as rate limits allow.

## Lessons Learned

1. **KOPS is opinionated** - Don't fight the system
2. **Single-node limitations** - Some architectural decisions assume multi-node
3. **Secondary IPs work well** - Clean separation of concerns
4. **Certificate management** - Critical for Kubernetes components
5. **Always script changes** - For reproducibility
6. **Always redirect log output to stderr in bash functions that return values via echo**
7. **Add timeouts to AWS CLI commands to prevent hanging**
8. **The iptables PREROUTING redirect is a clean solution for port conflicts**
9. **Test scripts thoroughly before including them in automated workflows**
10. **Don't fight KOPS - it's very opinionated about API server configuration**
11. **iptables PREROUTING is powerful for port conflict resolution**
12. **Secondary IPs on AWS are a clean solution for service separation**
13. **Always script infrastructure changes for reproducibility**

## Migration Guide

### For Existing Scripts
The `--with-secondary-ip` flag is kept for backwards compatibility but is no longer needed:

```bash
# Still works but redundant
./scripts/k8s/bootstrap-cluster.sh --with-secondary-ip

# Preferred (same result)
./scripts/k8s/bootstrap-cluster.sh
```

### For CI/CD Pipelines
Update your pipelines to either:
1. Remove `--with-secondary-ip` (recommended)
2. Add `--no-secondary-ip` if you want to save costs

### For New Clusters

#### Option 1: Full Setup During Bootstrap
```bash
./scripts/k8s/quick-start-full.sh
```

#### Option 2: Add to Existing Cluster
```bash
./scripts/k8s/setup-secondary-ip.sh
./scripts/k8s/setup-haproxy-https.sh
./scripts/k8s/update-app-dns-secondary.sh
```

### Deploy Applications
```bash
./scripts/k8s/deploy-app.sh sample-app
# Access at: https://sample.vadimzak.com (port 443!)
```

## Bootstrap Options

```bash
# Default: WITH secondary IP (HTTPS on port 443)
./scripts/k8s/bootstrap-cluster.sh

# WITHOUT secondary IP (HTTPS on port 30443)
./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip

# Quick start with all features
./scripts/k8s/quick-start-full.sh

# Quick start without secondary IP
./scripts/k8s/quick-start-full.sh --no-secondary-ip
```

## Recommendations

1. **For Production:** Use the secondary IP solution - it works perfectly
2. **For Development:** Use secondary IP by default, opt-out if cost is a concern
3. **For Scale:** Move to multi-node cluster when needed
4. **For Cost Optimization:** Use `--no-secondary-ip` for development environments

## Future Improvements

1. **Add monitoring** for both IPs
2. **Consider cert-manager** for API server certificates
3. **Implement health checks** for iptables forwarding
4. **Add metrics** for HAProxy performance
5. **Consider IPv6** support
6. **Automate certificate management**
7. **Add monitoring for Elastic IP usage**
8. **Implement automated failover for secondary IP**

## Why Other Solutions Don't Work

1. **Moving API server port**: KOPS hardcodes port 443 expectations
2. **Binding API to localhost**: Certificate validation fails, KOPS overrides
3. **Port forwarding without iptables**: Can't solve binding conflicts
4. **Load balancers**: Overkill for single-node, adds $10-15/month
5. **Network namespaces**: Too complex and risky for single-node setup
6. **NGINX stream module**: Same binding conflicts as HAProxy
7. **TCP multiplexers**: Still have the same port binding issues

## Security Considerations

1. **Disable SSL redirect** for HTTP-only access:
   ```bash
   kubectl annotate ingress <app-name> -n apps \
     nginx.ingress.kubernetes.io/ssl-redirect=false \
     nginx.ingress.kubernetes.io/force-ssl-redirect=false \
     --overwrite
   ```

2. **HAProxy security**: Runs as non-root user with chroot
3. **Network isolation**: Applications only accessible through ingress
4. **Ingress**: SSL redirect disabled for HTTP access
5. **API Server**: Accessible publicly on port 443
6. **Applications**: Only accessible through ingress
7. **SSH**: Key-based access only (`~/.ssh/kops-key`)

## Conclusion

The secondary IP solution with iptables PREROUTING redirect provides a clean, working approach to the port 443 conflict in single-node KOPS clusters. While KOPS prevents direct API server configuration changes, this solution achieves the goal of standard port access for all services with minimal additional cost and complexity.

The solution is now fully automated and enabled by default, providing the best user experience while maintaining the option to opt-out for cost-conscious deployments. Comprehensive error handling, troubleshooting tools, and cleanup scripts ensure reliable operation and easy maintenance.

### Key Success Factors

1. **Secondary IP separation**: Clean separation between API and application traffic
2. **iptables PREROUTING**: Elegant solution to port binding conflicts
3. **HAProxy SNI routing**: Smart routing based on domain names
4. **Comprehensive automation**: Fully scripted setup and teardown
5. **Error handling**: Robust error detection and recovery
6. **Cost optimization**: Reasonable cost for significant functionality improvement
7. **Backward compatibility**: Smooth migration path for existing setups