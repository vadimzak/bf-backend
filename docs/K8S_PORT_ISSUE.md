# Kubernetes Port Conflict Issue

## Problem

On a single-node KOPS cluster, the Kubernetes API server binds to port 443 on all interfaces (0.0.0.0:443), which prevents the NGINX ingress controller from using the standard HTTPS port.

## Current Status

- **API Server**: Uses port 443 (https://api.k8s.vadimzak.com)
- **Ingress Controller**: Available on NodePort 30080 (HTTP) and 30443 (HTTPS)
- **Applications**: Accessible but require non-standard ports

## Access URLs

### Current Working URLs:
- http://sample.vadimzak.com:30080
- https://sample.vadimzak.com:30443 (self-signed cert warning)
- http://sample-6.vadimzak.com:30080
- https://sample-6.vadimzak.com:30443 (self-signed cert warning)

### Health Check Examples:
```bash
# HTTP
curl http://sample.vadimzak.com:30080/health

# HTTPS (ignore cert warning)
curl -k https://sample.vadimzak.com:30443/health
```

## Solutions

### Option 1: Use Non-Standard Ports (Current)
- Pros: Simple, works immediately
- Cons: URLs include port numbers

### Option 2: Use AWS Load Balancer
- Pros: Standard ports, proper SSL termination
- Cons: Additional cost (~$20/month)

### Option 3: Multi-Node Cluster
- Pros: Dedicated ingress node, standard ports
- Cons: Higher cost, more complex

### Option 4: Move API Server Port
- Pros: Frees port 443 for ingress
- Cons: Complex, requires custom KOPS configuration that doesn't propagate properly to all components

## Recommendation

For a cost-conscious development/staging environment, using non-standard ports (Option 1) is acceptable. For production, consider Option 2 (Load Balancer) or Option 3 (Multi-node cluster).

## Port Forwarding Workaround

You can use iptables to forward standard ports to NodePorts:
```bash
# Forward port 80 to 30080
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 30080

# Note: Port 443 cannot be forwarded as it's used by the API server
```

## Note

This is a known limitation of single-node Kubernetes clusters where the API server and ingress controller compete for the same ports.