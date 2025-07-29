#!/bin/bash
set -euo pipefail

# Setup HAProxy for SNI-based routing to enable standard ports
# This allows both API server and applications to be accessible on standard ports

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Check if running with sudo when needed
check_sudo() {
    if [[ $EUID -ne 0 ]] && [[ "$1" == "true" ]]; then
        log_error "This operation requires sudo privileges"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

# Install HAProxy
install_haproxy() {
    log_info "Installing HAProxy on master node..."
    
    local master_ip
    master_ip=$(get_master_ip)
    
    if [[ -z "$master_ip" ]]; then
        log_error "Could not get master node IP"
        exit 1
    fi
    
    # Install HAProxy
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF'
        # Update package list
        sudo apt-get update
        
        # Install HAProxy
        sudo apt-get install -y haproxy
        
        # Enable HAProxy
        sudo systemctl enable haproxy
EOF
    
    log_info "HAProxy installed successfully"
}

# Configure HAProxy
configure_haproxy() {
    log_info "Configuring HAProxy for SNI-based routing..."
    
    local master_ip
    master_ip=$(get_master_ip)
    
    # Create HAProxy configuration
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF'
        # Backup original configuration
        sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup
        
        # Create new configuration
        sudo tee /etc/haproxy/haproxy.cfg > /dev/null << 'HAPROXY_CONFIG'
global
    log 127.0.0.1:514 local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    
    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private
    
    # Tune for better performance
    tune.ssl.default-dh-param 2048
    maxconn 4096

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# Frontend for HTTP traffic
frontend http_front
    bind *:80
    mode http
    # All HTTP traffic goes to ingress
    default_backend ingress_http

# Frontend for HTTPS traffic with SNI routing
frontend https_front
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route based on SNI hostname
    use_backend api_backend if { req_ssl_sni -i api.k8s.vadimzak.com }
    default_backend ingress_https

# Backend for Kubernetes API server
backend api_backend
    mode tcp
    option tcp-check
    server api 127.0.0.1:8443 check

# Backend for ingress HTTP
backend ingress_http
    mode http
    option httpchk GET /healthz
    server ingress 127.0.0.1:30080 check

# Backend for ingress HTTPS
backend ingress_https
    mode tcp
    option tcp-check
    server ingress 127.0.0.1:30443 check

# Stats page
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE
HAPROXY_CONFIG
        
        # Test configuration
        sudo haproxy -f /etc/haproxy/haproxy.cfg -c
        
        # Restart HAProxy with new configuration
        sudo systemctl restart haproxy
        
        # Check status
        sudo systemctl status haproxy --no-pager
EOF
    
    log_info "HAProxy configured successfully"
}

# Modify API server to bind to different port
modify_api_server() {
    log_info "Modifying API server to bind to localhost:8443..."
    
    local master_ip
    master_ip=$(get_master_ip)
    
    # Update API server manifest
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF'
        # Backup original manifest
        sudo cp /etc/kubernetes/manifests/kube-apiserver.manifest /etc/kubernetes/manifests/kube-apiserver.manifest.backup
        
        # Modify the manifest to change secure-port and bind address
        sudo sed -i.bak2 \
            -e 's/--secure-port=443/--secure-port=8443/' \
            -e '/--secure-port=8443/a\    - --bind-address=127.0.0.1' \
            /etc/kubernetes/manifests/kube-apiserver.manifest
        
        # Also update advertise address to use port 8443
        sudo sed -i \
            -e 's/--advertise-address=\([^:]*\)$/--advertise-address=\1:8443/' \
            /etc/kubernetes/manifests/kube-apiserver.manifest
        
        # The kubelet will automatically restart the API server pod
        echo "Waiting for API server to restart with new configuration..."
        sleep 30
        
        # Check if API server is listening on new port
        for i in {1..30}; do
            if sudo ss -tlnp | grep -q ':8443.*kube-apiserver'; then
                echo "API server is now listening on port 8443"
                break
            fi
            echo "Waiting for API server to start on port 8443... ($i/30)"
            sleep 10
        done
        
        # Update kubelet kubeconfig to use new port
        sudo sed -i 's|https://127.0.0.1|https://127.0.0.1:8443|' /var/lib/kubelet/kubeconfig
        
        # Restart kubelet
        sudo systemctl restart kubelet
EOF
    
    log_info "API server reconfigured to port 8443"
}

# Update kubectl configuration
update_kubectl_config() {
    log_info "Updating kubectl configuration..."
    
    # Keep the original server URL (HAProxy will handle the routing)
    kubectl config set-cluster "$CLUSTER_NAME" --server="https://api.$CLUSTER_NAME"
    
    log_info "kubectl configuration updated"
}

# Test the setup
test_setup() {
    log_info "Testing HAProxy setup..."
    
    local master_ip
    master_ip=$(get_master_ip)
    
    # Test HTTP
    log_info "Testing HTTP access..."
    if curl -s -o /dev/null -w "%{http_code}" "http://$master_ip/healthz" | grep -q "200\|404"; then
        log_info "✓ HTTP routing working"
    else
        log_warning "HTTP routing may have issues"
    fi
    
    # Test HTTPS API
    log_info "Testing API access through HAProxy..."
    if kubectl get nodes >/dev/null 2>&1; then
        log_info "✓ API access working through HAProxy"
    else
        log_error "API access not working through HAProxy"
    fi
    
    # Show HAProxy stats
    log_info "HAProxy stats available at: http://$master_ip:8404/stats"
}

# Configure firewall rules
configure_firewall() {
    log_info "Configuring firewall rules..."
    
    local master_ip
    master_ip=$(get_master_ip)
    
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF'
        # Allow HAProxy stats port
        sudo iptables -I INPUT -p tcp --dport 8404 -j ACCEPT
        
        # Ensure localhost traffic is allowed
        sudo iptables -I INPUT -i lo -j ACCEPT
        
        # Save iptables rules
        if command -v netfilter-persistent >/dev/null; then
            sudo netfilter-persistent save
        fi
EOF
    
    log_info "Firewall rules configured"
}

# Main execution
main() {
    log_info "Starting HAProxy setup for standard ports..."
    
    # Check prerequisites
    if ! command_exists kubectl; then
        log_error "kubectl not found. Please ensure cluster is bootstrapped first."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl get nodes >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Install and configure HAProxy
    install_haproxy
    configure_haproxy
    configure_firewall
    
    # Modify API server
    modify_api_server
    
    # Update kubectl config
    update_kubectl_config
    
    # Test the setup
    test_setup
    
    log_info "HAProxy setup completed!"
    echo
    echo "Summary:"
    echo "========"
    echo "✓ HAProxy installed and configured"
    echo "✓ API server moved to port 8443"
    echo "✓ Standard ports (80/443) now available"
    echo
    echo "Access patterns:"
    echo "- API: https://api.$CLUSTER_NAME (routed via HAProxy)"
    echo "- Apps: https://<app>.$DNS_ZONE (standard ports)"
    echo
    echo "Note: DNS propagation may take 5-15 minutes"
}

# Run main function
main "$@"