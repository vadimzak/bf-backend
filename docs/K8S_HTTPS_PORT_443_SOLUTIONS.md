# Kubernetes HTTPS Port 443 Solutions - Complete Analysis

## Problem Statement

On a single-node Kubernetes cluster deployed with KOPS on AWS, both the Kubernetes API server and application ingress need port 443, creating a conflict. This document comprehensively covers all attempted solutions and findings.

## Summary of Attempts

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

## Detailed Solution Analysis

### Option 1: Move API Server to Different Port (FAILED)

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

### Option 2: API Server Bind to Localhost Only (FAILED)

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

### Option 3: Secondary IP Address (SUCCESS! ✅)

**Implementation:**
```bash
# 1. Assign secondary private IP
aws ec2 assign-private-ip-addresses \
  --network-interface-id eni-098604c52f9eaec90 \
  --private-ip-addresses 172.20.245.38

# 2. Allocate and associate Elastic IP
aws ec2 allocate-address --domain vpc
aws ec2 associate-address \
  --allocation-id eipalloc-0906614816b28d4bf \
  --network-interface-id eni-098604c52f9eaec90 \
  --private-ip-address 172.20.245.38

# 3. Configure on instance
sudo ip addr add 172.20.245.38/16 dev ens5

# 4. Make persistent with netplan
cat > /etc/netplan/99-secondary-ip.yaml << EOF
network:
  version: 2
  ethernets:
    ens5:
      addresses:
        - 172.20.245.38/16
EOF
```

**HAProxy Configuration:**
```
# Bind to secondary IP for apps
frontend https_front
    bind 172.20.245.38:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    use_backend api_backend if { req_ssl_sni -i api.k8s.vadimzak.com }
    default_backend ingress_https
```

**API Server Access:**
```bash
# socat forwards primary IP:443 to localhost:8443
sudo systemctl create kube-api-forward.service
ExecStart=/usr/bin/socat TCP4-LISTEN:443,bind=172.20.245.37,reuseaddr,fork TCP4:127.0.0.1:8443
```

**Result:**
- Applications: https://sample.vadimzak.com ✅ (secondary IP)
- API Server: https://api.k8s.vadimzak.com ✅ (primary IP)
- Complete separation of traffic
- Both work on standard ports!

**Cost:** ~$3.60/month for additional Elastic IP

### Option 4: iptables PREROUTING (ATTEMPTED)

**What we tried:**
```bash
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
```

**Result:**
- Didn't solve the binding conflict
- Both services still try to bind to same port
- Only works for incoming traffic, not binding

### Key Discoveries

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

## Working Architecture

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
│   │   (socat)   ├──→ localhost:8443 (API Server)
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

## Scripts Created

1. **update-app-dns-secondary.sh** - Updates DNS to use secondary IP
2. **setup-haproxy.sh** - Configures HAProxy (updated for secondary IP)
3. **kube-api-forward.service** - systemd service for API forwarding

## Costs Comparison

| Solution | Monthly Cost | Complexity |
|----------|-------------|------------|
| Current (Secondary IP) | +$3.60 | Medium |
| Multi-node cluster | +$15-20 | High |
| External LB | +$10-15 | Medium |
| Accept limitation | $0 | Low |

## Recommendations

1. **For Production:** Use the secondary IP solution - it works perfectly
2. **For Development:** Accept the limitation (use port 30443)
3. **For Scale:** Move to multi-node cluster

## Lessons Learned

1. **KOPS is opinionated** - Don't fight the system
2. **Single-node limitations** - Some architectural decisions assume multi-node
3. **Secondary IPs work well** - Clean separation of concerns
4. **Certificate management** - Critical for Kubernetes components
5. **Always script changes** - For reproducibility

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
```

## Troubleshooting

### API Server Not Accessible
```bash
# Check socat forwarding
sudo systemctl status kube-api-forward

# Check API server is running
sudo crictl ps | grep apiserver

# Check listening ports
sudo ss -tlnp | grep -E ':443|:8443'
```

### Applications Not Accessible
```bash
# Check HAProxy
sudo systemctl status haproxy

# Check ingress controller
kubectl get pods -n ingress-nginx

# Check DNS resolution
dig sample.vadimzak.com
```

## Future Improvements

1. **Automate secondary IP setup** in bootstrap scripts
2. **Add monitoring** for both IPs
3. **Document in CLAUDE.md** for future reference
4. **Consider cert-manager** for API server certificates
5. **Implement health checks** for socat forwarding

## Conclusion

The secondary IP solution provides a clean, working approach to the port 443 conflict in single-node KOPS clusters. While KOPS prevents direct API server configuration changes, the combination of secondary IP + HAProxy + socat forwarding achieves the goal of standard port access for all services.