# Kubernetes with Standard Ports Setup

This document describes how we achieved standard port access (80/443) for applications on a single-node Kubernetes cluster.

## Architecture Overview

```
Internet -> Primary IP (51.16.46.89)
             -> Port 443 -> socat -> localhost:8443 (API Server)
         
         -> Secondary IP (51.84.199.169)  
             -> Port 80 -> HAProxy -> Port 30080 -> NGINX Ingress -> Apps
             -> Port 443 -> HAProxy -> Port 30443 -> NGINX Ingress -> Apps
```

## Current Status

- **HTTP (Port 80)**: ✅ Working via HAProxy on secondary IP
- **HTTPS (Port 443)**: ✅ Working via HAProxy on secondary IP for applications
- **API Server (Port 443)**: ✅ Working via socat forwarding on primary IP
- **Applications**: Fully accessible on standard ports without port numbers
- **HAProxy Stats**: ✅ Available on port 8404

## Implementation Details

### 1. HAProxy Configuration

HAProxy is installed on the master node to handle port 80 traffic:

```
Location: /etc/haproxy/haproxy.cfg
Service: haproxy.service
Stats: http://<master-ip>:8404/stats
```

**Current Implementation**: We're using a secondary IP address solution:
- Primary IP (51.16.46.89) handles Kubernetes API traffic on port 443
- Secondary IP (51.84.199.169) handles all application traffic on ports 80/443
- HAProxy binds to the secondary IP and forwards to NodePorts
- socat forwards API traffic from primary IP port 443 to localhost:8443

### 2. Traffic Flow

1. HTTP requests on port 80 → HAProxy
2. HAProxy forwards to localhost:30080 (NGINX Ingress NodePort)
3. NGINX Ingress routes based on hostname to appropriate service
4. Service forwards to application pods

### 3. Security Group Configuration

The following ports are open:
- **22**: SSH
- **80**: HTTP (HAProxy)
- **443**: HTTPS (Kubernetes API)
- **30080**: NodePort HTTP (internal)
- **30443**: NodePort HTTPS
- **8404**: HAProxy stats

### 4. SSL/TLS Considerations

Currently, SSL termination is disabled for HTTP access. For production:
1. Configure cert-manager for Let's Encrypt certificates
2. Use AWS Load Balancer for proper SSL termination
3. Or implement SNI-based routing with HAProxy (requires moving API to different port)

## Deployment Process

### Automated Deployment

```bash
# Complete setup with standard ports
./scripts/k8s/quick-start-full.sh
```

### Manual Steps

1. **Bootstrap cluster**:
   ```bash
   ./scripts/k8s/bootstrap-cluster.sh
   ```

2. **Deploy applications**:
   ```bash
   ./scripts/k8s/configure-apps.sh
   ./scripts/k8s/deploy-app.sh <app-name>
   ```

3. **Setup HAProxy** (for standard ports):
   ```bash
   ./scripts/k8s/setup-haproxy.sh
   ```

## Application Access

### With DNS (after propagation):
- http://sample.vadimzak.com
- http://sample-6.vadimzak.com

### Direct IP access:
```bash
curl http://<master-ip>/health -H "Host: sample.vadimzak.com"
```

## Limitations

1. **HTTPS on port 443**: Not available due to API server conflict
2. **Single point of failure**: HAProxy on single node
3. **No SSL termination**: Currently HTTP only on standard port

## Future Improvements

### Option 1: Full SNI-based Routing (Recommended)
- Move API server to port 6443
- Configure HAProxy for SNI-based HTTPS routing
- Enables both HTTP and HTTPS on standard ports

### Option 2: AWS Load Balancer
- Use NLB/ALB for standard port access
- Proper SSL termination
- High availability
- Additional cost (~$20/month)

### Option 3: Multi-node Cluster
- Dedicated ingress node
- No port conflicts
- Production-ready architecture
- Higher cost

## Troubleshooting

### Check HAProxy status:
```bash
sudo systemctl status haproxy
```

### View HAProxy stats:
```
http://<master-ip>:8404/stats
```

### View HAProxy configuration:
```bash
ssh -i ~/.ssh/kops-key ubuntu@<master-ip> "cat /etc/haproxy/haproxy.cfg"
```

### Check ingress controller:
```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

### Test connectivity:
```bash
# From master node
curl http://localhost:30080/health -H "Host: app.domain.com"

# From external
curl http://<master-ip>/health -H "Host: app.domain.com"
```

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

## Cost Analysis

Current setup adds no additional AWS costs:
- HAProxy runs on existing master node
- No load balancer charges
- Same instance cost as before

## Scripts Reference

- `scripts/k8s/setup-haproxy.sh`: HAProxy setup script (HTTP-only version)
- `scripts/k8s/quick-start-full.sh`: Complete setup including HAProxy
- `scripts/k8s/update-wildcard-dns.sh`: Updates wildcard DNS records
- `scripts/k8s/update-app-dns.sh`: Updates app DNS to primary IP
- `scripts/k8s/update-app-dns-secondary.sh`: Updates app DNS to secondary IP (used for port 443 solution)