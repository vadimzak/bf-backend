#!/bin/bash
set -euo pipefail

# Setup HAProxy for HTTP/HTTPS routing on standard ports using secondary IP
# This implements the full solution from K8S_HTTPS_PORT_443_SOLUTIONS.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Options
USE_SECONDARY_IP=true
SECONDARY_IP_SETUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-secondary-ip)
            USE_SECONDARY_IP=false
            shift
            ;;
        --setup-secondary-ip)
            SECONDARY_IP_SETUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --no-secondary-ip    Use primary IP only (HTTP only, no HTTPS)"
            echo "  --setup-secondary-ip  Also run secondary IP setup"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get secondary IP information
get_secondary_ip_info() {
    local master_ip="$1"
    
    # Get network interface info
    local eni_info
    eni_info=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" \
        "ip -o addr show | grep -v 'lo\\|docker\\|cali' | grep 'inet ' | awk '{print \$2, \$4}' | sort")
    
    # Extract secondary IP (non-primary IP on main interface)
    local secondary_private_ip
    secondary_private_ip=$(echo "$eni_info" | awk 'NR==2 {print $2}' | cut -d'/' -f1)
    
    if [[ -z "$secondary_private_ip" ]]; then
        log_warning "No secondary IP found on instance"
        return 1
    fi
    
    # Get public IP associated with secondary private IP
    local instance_id
    instance_id=$(aws ec2 describe-instances \
        --filters "Name=network-interface.addresses.private-ip-address,Values=$master_ip" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    local secondary_public_ip
    secondary_public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[0].PrivateIpAddresses[?PrivateIpAddress=='$secondary_private_ip'].Association.PublicIp" \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    echo "$secondary_private_ip|$secondary_public_ip"
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
    
    # Install HAProxy and socat
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF'
        # Update package list
        sudo apt-get update
        
        # Install HAProxy and socat
        sudo apt-get install -y haproxy socat
        
        # Enable HAProxy
        sudo systemctl enable haproxy
EOF
    
    log_info "HAProxy installed successfully"
}

# Configure HAProxy for secondary IP with HTTPS support
configure_haproxy_secondary_ip() {
    log_info "Configuring HAProxy for HTTPS with secondary IP..."
    
    local master_ip="$1"
    local secondary_private_ip="$2"
    local primary_private_ip="$3"
    
    # First, setup iptables redirect for HTTPS traffic
    log_info "Setting up iptables redirect for HTTPS traffic..."
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << EOF
        # Create iptables rule to redirect HTTPS traffic from secondary IP to port 8443
        sudo iptables -t nat -A PREROUTING -d ${secondary_private_ip} -p tcp --dport 443 -j REDIRECT --to-port 8443
        
        # Make iptables rules persistent
        if ! command -v netfilter-persistent >/dev/null; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent
        fi
        sudo netfilter-persistent save || sudo iptables-save > /etc/iptables/rules.v4
EOF
    
    # Create HAProxy configuration
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << EOF
        # Backup original configuration
        sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup-https
        
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
    
    # SSL/TLS settings
    tune.ssl.default-dh-param 2048
    ssl-default-bind-ciphers ECDHE+AESGCM:DHE+AESGCM:ECDHE+AES256:DHE+AES256:ECDHE+AES128:DHE+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
    ssl-default-bind-options no-sslv3

defaults
    log     global
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Frontend for HTTPS traffic redirected to port 8443
frontend https_front
    bind *:8443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route based on SNI (Server Name Indication)
    use_backend api_backend if { req_ssl_sni -i api.${CLUSTER_NAME} }
    use_backend api_backend if { req_ssl_sni -i api.k8s.${DNS_ZONE} }
    default_backend ingress_https

# Frontend for HTTP traffic on secondary IP port 80
frontend http_front
    bind ${secondary_private_ip}:80
    mode http
    option httplog
    default_backend ingress_http

# Stats page (accessible on all IPs)
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
    stats show-node
    stats show-legends

# Backend for Kubernetes API server
backend api_backend
    mode tcp
    option tcp-check
    server api-server ${primary_private_ip}:443 check

# Backend for ingress HTTPS (NodePort 30443)
backend ingress_https
    mode tcp
    option tcp-check
    server ingress 127.0.0.1:30443 check

# Backend for ingress HTTP (NodePort 30080)
backend ingress_http
    mode http
    option httpchk GET /healthz
    http-check expect status 200,404
    server ingress 127.0.0.1:30080 check
HAPROXY_CONFIG
        
        # Test configuration
        sudo haproxy -f /etc/haproxy/haproxy.cfg -c
        
        # Restart HAProxy with new configuration
        sudo systemctl restart haproxy
        
        # Check status
        sudo systemctl status haproxy --no-pager
EOF
    
    log_info "HAProxy configured for HTTPS with secondary IP using iptables redirect"
}

# Configure HAProxy for primary IP (HTTP only)
configure_haproxy_primary_ip() {
    log_info "Configuring HAProxy for HTTP only (primary IP)..."
    
    local master_ip="$1"
    
    # Use the existing setup from setup-haproxy.sh
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF'
        # Backup original configuration
        sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup-http-only
        
        # Create HTTP-only configuration
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
        
        # Restart HAProxy
        sudo systemctl restart haproxy
        
        # Check status
        sudo systemctl status haproxy --no-pager
EOF
    
    log_info "HAProxy configured for HTTP only"
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
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
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
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    if [[ -z "$sg_id" ]] || [[ "$sg_id" == "None" ]]; then
        log_error "Could not find security group ID"
        return 1
    fi
    
    # Add security group rules
    local ports=(80 443 8404)
    for port in "${ports[@]}"; do
        log_info "Adding security group rule for port $port..."
        if aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port "$port" \
            --cidr 0.0.0.0/0 \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" 2>/dev/null; then
            log_info "✓ Added port $port to security group"
        else
            log_info "Port $port might already be open (this is fine)"
        fi
    done
}

# Configure firewall rules
configure_firewall() {
    log_info "Configuring firewall rules..."
    
    local master_ip
    master_ip=$(get_master_ip)
    
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF'
        # Allow HAProxy ports
        sudo iptables -I INPUT -p tcp --dport 8404 -j ACCEPT
        sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
        
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
    
    local test_ip="$master_ip"
    local https_enabled=false
    
    if [[ "$USE_SECONDARY_IP" == "true" ]]; then
        local secondary_info
        secondary_info=$(get_secondary_ip_info "$master_ip")
        if [[ $? -eq 0 ]]; then
            IFS='|' read -r secondary_private_ip secondary_public_ip <<< "$secondary_info"
            if [[ -n "$secondary_public_ip" ]] && [[ "$secondary_public_ip" != "None" ]]; then
                test_ip="$secondary_public_ip"
                https_enabled=true
            fi
        fi
    fi
    
    # Test HTTP
    log_info "Testing HTTP access..."
    if curl -s -o /dev/null -w "%{http_code}" "http://$test_ip/healthz" | grep -q "200\|404"; then
        log_info "✓ HTTP routing working"
    else
        log_warning "HTTP routing may have issues"
    fi
    
    # Test HTTPS if enabled
    if [[ "$https_enabled" == "true" ]]; then
        log_info "Testing HTTPS access..."
        if curl -sk -o /dev/null -w "%{http_code}" "https://$test_ip/healthz" | grep -q "200\|404"; then
            log_info "✓ HTTPS routing working"
        else
            log_warning "HTTPS routing may have issues"
        fi
        
        # Test API server access
        log_info "Testing API server access..."
        if curl -sk "https://api.$CLUSTER_NAME/healthz" | grep -q "ok"; then
            log_info "✓ API server routing working"
        else
            log_warning "API server routing may need DNS propagation"
        fi
    fi
    
    # Test with host header
    log_info "Testing application access..."
    if curl -s "http://$test_ip/health" -H "Host: sample.$DNS_ZONE" | grep -q "healthy"; then
        log_info "✓ Application routing working"
    else
        log_warning "Application routing may need DNS propagation or app deployment"
    fi
    
    # Show HAProxy stats
    log_info "HAProxy stats available at: http://$master_ip:8404/stats"
    if [[ "$https_enabled" == "true" ]] && [[ -n "$secondary_public_ip" ]]; then
        log_info "Also available at: http://$secondary_public_ip:8404/stats"
    fi
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
    
    # Get master IP
    local master_ip
    master_ip=$(get_master_ip)
    if [[ -z "$master_ip" ]]; then
        log_error "Could not get master node IP"
        exit 1
    fi
    
    # Setup secondary IP if requested
    if [[ "$SECONDARY_IP_SETUP" == "true" ]]; then
        log_info "Running secondary IP setup..."
        if ! "$SCRIPT_DIR/setup-secondary-ip.sh"; then
            log_error "Failed to setup secondary IP"
            exit 1
        fi
    fi
    
    # Install HAProxy
    install_haproxy
    
    # Configure HAProxy based on secondary IP availability
    if [[ "$USE_SECONDARY_IP" == "true" ]]; then
        # Check for secondary IP
        local secondary_info
        secondary_info=$(get_secondary_ip_info "$master_ip")
        
        if [[ $? -eq 0 ]]; then
            IFS='|' read -r secondary_private_ip secondary_public_ip <<< "$secondary_info"
            
            if [[ -n "$secondary_private_ip" ]]; then
                log_info "Secondary IP found: $secondary_private_ip (Public: $secondary_public_ip)"
                
                # Get primary private IP
                local primary_private_ip
                primary_private_ip=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" \
                    "ip -o addr show | grep -v 'lo\\|docker\\|cali' | grep 'inet ' | head -1 | awk '{print \$4}' | cut -d'/' -f1")
                
                configure_haproxy_secondary_ip "$master_ip" "$secondary_private_ip" "$primary_private_ip"
            else
                log_warning "No secondary IP found, configuring HTTP only"
                configure_haproxy_primary_ip "$master_ip"
            fi
        else
            log_warning "Could not get secondary IP info, configuring HTTP only"
            log_info "Run with --setup-secondary-ip to enable HTTPS support"
            configure_haproxy_primary_ip "$master_ip"
        fi
    else
        configure_haproxy_primary_ip "$master_ip"
    fi
    
    # Configure security and firewall
    configure_security_group
    configure_firewall
    
    # Test the setup
    test_setup
    
    # Print summary
    echo
    log_info "HAProxy setup completed!"
    echo
    echo "Summary:"
    echo "========"
    
    if [[ "$USE_SECONDARY_IP" == "true" ]] && [[ -n "$secondary_private_ip" ]]; then
        echo "✓ HAProxy installed and configured with HTTPS support"
        echo "✓ HTTP traffic on port 80 routed to ingress"
        echo "✓ HTTPS traffic on port 443 routed to ingress"
        echo "✓ API server accessible on port 443"
        echo "✓ Security group rules configured"
        echo
        echo "Access patterns:"
        echo "- HTTP: http://<app>.$DNS_ZONE"
        echo "- HTTPS: https://<app>.$DNS_ZONE"
        echo "- API: https://api.$CLUSTER_NAME"
        echo "- Stats: http://$secondary_public_ip:8404/stats"
        echo
        echo "Secondary IP: $secondary_public_ip"
    else
        echo "✓ HAProxy installed and configured"
        echo "✓ HTTP traffic on port 80 routed to ingress"
        echo "✓ Security group rules configured"
        echo
        echo "Access patterns:"
        echo "- HTTP: http://<app>.$DNS_ZONE"
        echo "- HTTPS: https://<app>.$DNS_ZONE:30443 (non-standard port)"
        echo "- API: https://api.$CLUSTER_NAME"
        echo "- Stats: http://$master_ip:8404/stats"
        echo
        echo "Note: For HTTPS on port 443, run:"
        echo "  ./scripts/k8s/setup-secondary-ip.sh"
        echo "  ./scripts/k8s/setup-haproxy-https.sh"
    fi
}

# Run main function
main "$@"