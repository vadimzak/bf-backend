# Kubernetes HTTPS Port 443 Troubleshooting Guide

This guide helps troubleshoot issues with HTTPS on port 443 for Kubernetes applications.

## Common Issues and Solutions

### 1. setup-secondary-ip.sh Script Hangs

**Symptoms:**
- Script outputs initial messages then hangs
- No progress after "Checking for existing secondary IPs..."

**Root Cause:**
- Log messages being captured in command substitution
- AWS CLI commands hanging without timeout

**Solution:**
The script has been fixed to:
- Redirect log messages to stderr in functions: `log_info "message" >&2`
- Add timeouts to all AWS CLI commands: `timeout 10 aws ec2 ...`
- Simplify IP allocation by using AWS auto-assign

### 2. HTTPS Not Working After Bootstrap

**Symptoms:**
- Applications only accessible on ports 30080/30443
- https://app.vadimzak.com/ returns connection refused
- bootstrap-cluster.sh shows "Secondary IP setup failed"

**Root Cause:**
- Secondary IP setup didn't run during bootstrap
- Port 443 conflict between API server and ingress

**Solution:**
Run the three scripts manually:
```bash
./scripts/k8s/setup-secondary-ip.sh
./scripts/k8s/setup-haproxy-https.sh
./scripts/k8s/update-app-dns-secondary.sh
```

### 3. iptables Rules Not Persisting

**Symptoms:**
- HTTPS works initially but stops after reboot
- `sudo iptables -t nat -L PREROUTING -n` shows no redirect rule

**Solution:**
```bash
# Re-add the rule
sudo iptables -t nat -A PREROUTING -d <secondary-private-ip> -p tcp --dport 443 -j REDIRECT --to-port 8443

# Save permanently
sudo netfilter-persistent save
```

### 4. DNS Not Resolving to Secondary IP

**Symptoms:**
- `dig app.vadimzak.com` returns primary IP instead of secondary
- HTTPS redirects to API server

**Solution:**
```bash
# Update DNS records
./scripts/k8s/update-app-dns-secondary.sh

# Verify DNS
dig +short *.vadimzak.com  # Should show secondary IP
dig +short api.k8s.vadimzak.com  # Should show primary IP
```

### 5. HAProxy Not Routing Correctly

**Symptoms:**
- Connection timeouts on HTTPS
- HAProxy stats page shows backends down

**Solution:**
Check HAProxy configuration:
```bash
ssh -i ~/.ssh/kops-key ubuntu@<master-ip>
sudo haproxy -f /etc/haproxy/haproxy.cfg -c  # Validate config
sudo systemctl status haproxy
sudo journalctl -u haproxy -n 50
```

Ensure HAProxy binds to port 8443 (not 443):
```
frontend https_front
    bind *:8443  # NOT bind *:443
```

## Verification Commands

### Check Secondary IP Setup
```bash
# Check secondary IP exists
aws ec2 describe-network-interfaces \
    --network-interface-ids <eni-id> \
    --query 'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`]' \
    --profile bf --region il-central-1

# Check iptables redirect
ssh -i ~/.ssh/kops-key ubuntu@<master-ip> \
    'sudo iptables -t nat -L PREROUTING -n -v | grep 443'

# Check network interface
ssh -i ~/.ssh/kops-key ubuntu@<master-ip> 'ip addr show ens5'
```

### Test HTTPS Access
```bash
# Test with curl
curl -k https://app.vadimzak.com/health

# Check what's listening on ports
ssh -i ~/.ssh/kops-key ubuntu@<master-ip> \
    'sudo ss -tlnp | grep -E ":443|:8443"'

# Check HAProxy stats
curl http://<secondary-ip>:8404/stats
```

## Best Practices

### 1. Always Use Timeouts
```bash
# Good
result=$(timeout 10 aws ec2 describe-instances ...)

# Bad
result=$(aws ec2 describe-instances ...)
```

### 2. Redirect Logs in Functions
```bash
# Good - logs go to terminal, not captured
function_that_returns_value() {
    log_info "Processing..." >&2
    echo "return_value"
}

# Bad - log message gets captured as return value
function_that_returns_value() {
    log_info "Processing..."
    echo "return_value"
}
```

### 3. Test with Dry Run
```bash
# Test changes without making them
./scripts/k8s/setup-secondary-ip.sh --dry-run
```

### 4. Use AWS Auto-Assign
Let AWS automatically assign secondary IPs instead of searching for available ones:
```bash
aws ec2 assign-private-ip-addresses \
    --network-interface-id <eni-id> \
    --secondary-private-ip-address-count 1
```

## Architecture Reminder

```
Internet → Route 53 DNS
           ├─ api.k8s.vadimzak.com → Primary IP (51.16.45.179)
           │                         └─ API Server (port 443)
           │
           └─ *.vadimzak.com → Secondary IP (51.84.153.25)
                               └─ iptables PREROUTING (443 → 8443)
                                  └─ HAProxy (port 8443)
                                     └─ Ingress (port 30443)
                                        └─ Application Pods
```

## Cost Breakdown
- Primary Elastic IP: Free (attached to running instance)
- Secondary Elastic IP: ~$3.60/month
- Total additional cost: ~$3.60/month

## Emergency Recovery

If everything is broken:
1. SSH to master: `ssh -i ~/.ssh/kops-key ubuntu@<master-ip>`
2. Check what's running: `sudo ss -tlnp`
3. Restart HAProxy: `sudo systemctl restart haproxy`
4. Re-add iptables rule if missing
5. Verify secondary IP on interface: `ip addr show ens5`