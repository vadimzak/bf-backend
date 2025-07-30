# SSL Implementation Cleanup Summary

## What Was Fixed

### 1. **Secondary IP Setup Script Hanging**
The `setup-secondary-ip.sh` script was hanging because it was waiting for AWS CLI commands without proper error handling. Fixed by:
- Adding proper error handling for AWS API calls
- Implementing the iptables PREROUTING redirect directly in the script
- Updating HAProxy configuration to bind to port 8443 instead of 443

### 2. **Implemented the ONLY Working Solution**
As documented in `K8S_HTTPS_PORT_443_SOLUTIONS.md`, the ONLY solution that works is:
- Allocate secondary private IP on the EC2 instance
- Associate an Elastic IP with the secondary IP
- Configure iptables PREROUTING to redirect port 443 → 8443
- HAProxy listens on port 8443 and routes based on SNI
- DNS: apps use secondary IP, API server uses primary IP

### 3. **Key Innovation: iptables PREROUTING**
```bash
sudo iptables -t nat -A PREROUTING -d <secondary-private-ip> -p tcp --dport 443 -j REDIRECT --to-port 8443
```
This allows HAProxy to receive HTTPS traffic without binding to port 443 directly.

## Scripts Updated

### 1. `scripts/k8s/setup-secondary-ip.sh`
- Fixed hanging issue
- Added iptables PREROUTING setup
- Updated HAProxy config to bind to port 8443
- Made configuration persistent with netfilter-persistent

### 2. `scripts/k8s/setup-haproxy-https.sh`
- Complete rewrite to implement the correct solution
- Configures HAProxy to listen on port 8443
- Routes based on SNI (api.k8s.vadimzak.com → API server, others → ingress)

### 3. `scripts/k8s/update-app-dns-secondary.sh`
- Properly queries AWS for secondary IP information
- Updates wildcard DNS to secondary IP
- Keeps API server DNS on primary IP

### 4. `scripts/k8s/bootstrap-cluster.sh`
- Already had the correct implementation
- Calls secondary IP setup when `--with-secondary-ip` is used

### 5. `scripts/k8s/configure-apps.sh`
- Added secondary IP detection
- Shows appropriate instructions based on setup

### 6. `scripts/k8s/deploy-app.sh`
- Detects secondary IP setup
- Shows correct URLs (with or without port numbers)

## Current Working Setup

### IPs and Routing
- **Primary IP (51.17.24.9)**: Kubernetes API server on port 443
- **Secondary IP (51.84.133.30)**: Application traffic on ports 80/443

### DNS Configuration
- `api.k8s.vadimzak.com` → 51.17.24.9 (primary)
- `*.vadimzak.com` → 51.84.133.30 (secondary)

### Traffic Flow
1. HTTPS request to `sample.vadimzak.com` → Secondary IP (51.84.133.30)
2. iptables redirects port 443 → 8443
3. HAProxy receives on port 8443
4. HAProxy routes to ingress controller (port 30443)
5. Ingress forwards to application pod

## How to Use (New Cluster)

### Option 1: Full Setup During Bootstrap
```bash
./scripts/k8s/quick-start-full.sh --with-secondary-ip
```

### Option 2: Add to Existing Cluster
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

## Cost
- Secondary Elastic IP: ~$3.60/month
- Everything else uses existing infrastructure

## Why Other Solutions Don't Work
1. **Moving API server port**: KOPS hardcodes port 443 expectations
2. **Binding API to localhost**: Certificate validation fails, KOPS overrides
3. **Port forwarding without iptables**: Can't solve binding conflicts
4. **Load balancers**: Overkill for single-node, adds $10-15/month

## Key Lessons
1. Don't fight KOPS - it's very opinionated about API server configuration
2. iptables PREROUTING is powerful for port conflict resolution
3. Secondary IPs on AWS are a clean solution for service separation
4. Always script infrastructure changes for reproducibility

## Verification Commands
```bash
# Check HTTPS works
curl -k https://sample.vadimzak.com/health

# Check iptables rule
sudo iptables -t nat -L PREROUTING -n -v | grep 443

# Check HAProxy status
sudo systemctl status haproxy

# Check what's listening
sudo ss -tlnp | grep -E ':443|:8443'
```