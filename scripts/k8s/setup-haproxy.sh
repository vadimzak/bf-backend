#!/bin/bash
set -euo pipefail

# Setup HAProxy for HTTP routing on standard port 80
# This is a simplified version that only handles HTTP traffic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

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

# Configure HAProxy for HTTP only
configure_haproxy() {
    log_info "Configuring HAProxy for HTTP routing..."
    
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
    maxconn 4096

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Frontend for HTTP traffic
frontend http_front
    bind *:80
    default_backend ingress_http

# Stats page
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s

# Backend for ingress HTTP
backend ingress_http
    option httpchk GET /healthz
    server ingress 127.0.0.1:30080 check
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

# Configure security group
configure_security_group() {
    log_info "Configuring security group rules..."
    
    local master_ip
    master_ip=$(get_master_ip)
    
    # Get instance ID
    local instance_id
    instance_id=$(aws ec2 describe-instances \
        --filters "Name=network-interface.addresses.private-ip-address,Values=$master_ip" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --profile bf)
    
    if [[ -z "$instance_id" ]] || [[ "$instance_id" == "None" ]]; then
        log_error "Could not find instance ID for master node"
        return 1
    fi
    
    # Get security group ID
    local sg_id
    sg_id=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text \
        --profile bf)
    
    if [[ -z "$sg_id" ]] || [[ "$sg_id" == "None" ]]; then
        log_error "Could not find security group ID"
        return 1
    fi
    
    # Add security group rule for port 80
    log_info "Adding security group rule for port 80..."
    if aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --profile bf 2>/dev/null; then
        log_info "✓ Added port 80 to security group"
    else
        log_info "Port 80 might already be open (this is fine)"
    fi
    
    # Add security group rule for HAProxy stats (port 8404)
    log_info "Adding security group rule for HAProxy stats (port 8404)..."
    if aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 8404 \
        --cidr 0.0.0.0/0 \
        --profile bf 2>/dev/null; then
        log_info "✓ Added port 8404 to security group"
    else
        log_info "Port 8404 might already be open (this is fine)"
    fi
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
    
    # Test with host header
    log_info "Testing application access..."
    if curl -s "http://$master_ip/health" -H "Host: sample.vadimzak.com" | grep -q "healthy"; then
        log_info "✓ Application routing working"
    else
        log_warning "Application routing may need DNS propagation"
    fi
    
    # Show HAProxy stats
    log_info "HAProxy stats available at: http://$master_ip:8404/stats"
}

# Main execution
main() {
    log_info "Starting HAProxy setup for HTTP on standard port 80..."
    
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
    configure_security_group
    configure_firewall
    
    # Test the setup
    test_setup
    
    log_info "HAProxy HTTP setup completed!"
    echo
    echo "Summary:"
    echo "========"
    echo "✓ HAProxy installed and configured"
    echo "✓ HTTP traffic on port 80 routed to ingress"
    echo "✓ Security group rules configured"
    echo
    echo "Access patterns:"
    echo "- HTTP: http://<app>.$DNS_ZONE"
    echo "- HTTPS: https://<app>.$DNS_ZONE:30443 (non-standard port)"
    echo "- Stats: http://$master_ip:8404/stats"
    echo
    echo "Note: For HTTPS on port 443, the Kubernetes API server"
    echo "      would need to be moved to a different port."
}

# Run main function
main "$@"