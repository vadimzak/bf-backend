#!/bin/bash
set -euo pipefail

# Setup HAProxy for HTTPS on port 443 using secondary IP and iptables redirect
# This implements the successful solution from K8S_HTTPS_PORT_443_SOLUTIONS.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Ensure commands complete in reasonable time
export TIMEOUT_CMD="timeout 30"

# Get master node IP
MASTER_IP=$(get_master_ip)
if [[ -z "$MASTER_IP" ]]; then
    log_error "Could not get master node IP"
    exit 1
fi

log_info "Starting HAProxy setup for HTTPS support..."
log_info "This uses the iptables PREROUTING redirect solution from K8S_HTTPS_PORT_443_SOLUTIONS.md"

# Install HAProxy if not already installed
log_info "Installing HAProxy on master node..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$MASTER_IP" << 'EOF'
    if ! command -v haproxy >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y haproxy
    fi
EOF

# Configure HAProxy for HTTPS with iptables redirect
log_info "Configuring HAProxy for HTTPS support..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$MASTER_IP" << 'EOF'
    # Create HAProxy configuration
    sudo tee /etc/haproxy/haproxy.cfg > /dev/null << 'HAPROXY_CONFIG'
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Stats page
stats enable
stats uri /stats
stats refresh 30s

# Frontend for HTTP traffic
frontend http_front
    bind *:80
    mode http
    default_backend ingress_http

# Frontend for HTTPS traffic - binds to port 8443 (receives traffic from iptables redirect)
frontend https_front
    bind *:8443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route based on SNI
    use_backend api_backend if { req_ssl_sni -i api.k8s.vadimzak.com }
    default_backend ingress_https

# Backend for Kubernetes API server
backend api_backend
    mode tcp
    server api-server 127.0.0.1:443 check

# Backend for ingress HTTPS
backend ingress_https
    mode tcp
    server ingress 127.0.0.1:30443 check

# Backend for ingress HTTP
backend ingress_http
    mode http
    server ingress 127.0.0.1:30080 check
HAPROXY_CONFIG
    
    # Test configuration
    sudo haproxy -f /etc/haproxy/haproxy.cfg -c
    
    # Restart HAProxy
    sudo systemctl restart haproxy
    sudo systemctl enable haproxy
    sudo systemctl status haproxy --no-pager
EOF

if [[ $? -eq 0 ]]; then
    log_info "HAProxy configured successfully!"
    
    # Add security group rule for stats page
    add_security_group_rule 8404 tcp
    
    echo
    echo "HAProxy is now configured for HTTPS support!"
    echo "================================================"
    echo "Important: This HAProxy setup requires the secondary IP to be configured."
    echo "If you haven't already, run: ./scripts/k8s/setup-secondary-ip.sh"
    echo
    echo "HAProxy Stats: http://$MASTER_IP:8404/stats"
    echo
    echo "How it works:"
    echo "1. Secondary IP receives HTTPS traffic on port 443"
    echo "2. iptables redirects it to HAProxy on port 8443"
    echo "3. HAProxy routes based on SNI:"
    echo "   - api.k8s.vadimzak.com → API server (port 443)"
    echo "   - *.vadimzak.com → Ingress controller (port 30443)"
    echo
else
    log_error "Failed to configure HAProxy"
    exit 1
fi