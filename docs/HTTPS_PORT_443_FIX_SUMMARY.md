# HTTPS Port 443 Fix Summary

## Issue
After running the full cluster setup (`bootstrap-cluster.sh` → `configure-apps.sh` → `deploy-app.sh`), HTTPS on port 443 was not working. The application was only accessible on non-standard ports (30080/30443).

## Root Cause
The `setup-secondary-ip.sh` script was hanging during execution due to:
1. Log messages being captured in command substitution (functions returning values)
2. Missing timeouts on AWS CLI commands
3. IP generation logic issues for /16 subnets

This caused the bootstrap script to skip the secondary IP setup with a warning.

## Solution Implemented

### 1. Manual Secondary IP Setup
Since the script was hanging, we manually configured the secondary IP:

```bash
# Allocate secondary private IP
aws ec2 assign-private-ip-addresses \
    --network-interface-id eni-023e03ab1e3ae5bd9 \
    --secondary-private-ip-address-count 1

# Result: 172.20.213.46

# Allocate Elastic IP
aws ec2 allocate-address --domain vpc
# Result: 51.84.153.25 (eipalloc-059b3d4723e924b07)

# Associate Elastic IP with secondary private IP
aws ec2 associate-address \
    --allocation-id eipalloc-059b3d4723e924b07 \
    --network-interface-id eni-023e03ab1e3ae5bd9 \
    --private-ip-address 172.20.213.46
```

### 2. Configure Instance Networking
```bash
# Add secondary IP to network interface
sudo ip addr add 172.20.213.46/16 dev ens5

# Set up iptables PREROUTING redirect (KEY INNOVATION!)
sudo iptables -t nat -A PREROUTING -d 172.20.213.46 -p tcp --dport 443 -j REDIRECT --to-port 8443

# Make persistent
sudo apt-get install -y iptables-persistent netfilter-persistent
sudo netfilter-persistent save
```

### 3. Install and Configure HAProxy
Ran `./scripts/k8s/setup-haproxy-https.sh` which:
- Installed HAProxy
- Configured it to listen on port 8443 (not 443)
- Set up SNI-based routing:
  - `api.k8s.vadimzak.com` → API server (127.0.0.1:443)
  - `*.vadimzak.com` → Ingress controller (127.0.0.1:30443)

### 4. Update DNS Records
Ran `./scripts/k8s/update-app-dns-secondary.sh` which:
- Updated `*.vadimzak.com` → 51.84.153.25 (secondary IP)
- Kept `api.k8s.vadimzak.com` → 51.16.45.179 (primary IP)

## Script Fixes Applied

### setup-secondary-ip.sh
1. Added `>&2` to redirect log messages to stderr in functions that return values
2. Added `timeout` commands to AWS CLI calls to prevent hanging
3. Fixed IP generation logic for /16 subnets

## Result
✅ HTTPS on port 443 is now working!
- https://sample.vadimzak.com/ - Accessible
- https://sample-6.vadimzak.com/ - Accessible

## Cost
- Secondary Elastic IP: ~$3.60/month
- Everything else uses existing infrastructure

## Traffic Flow
1. HTTPS request to `sample.vadimzak.com` → Secondary IP (51.84.153.25)
2. iptables redirects port 443 → 8443 on secondary private IP (172.20.213.46)
3. HAProxy receives on port 8443
4. HAProxy routes based on SNI to ingress controller (port 30443)
5. Ingress forwards to application pod

## Lessons Learned
1. Always redirect log output to stderr in bash functions that return values via echo
2. Add timeouts to AWS CLI commands to prevent hanging
3. The iptables PREROUTING redirect is a clean solution for port conflicts
4. Test scripts thoroughly before including them in automated workflows