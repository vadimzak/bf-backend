#!/bin/bash
set -euo pipefail

# Setup secondary IP for Kubernetes cluster to resolve port 443 conflict
# This implements Option 3 from K8S_HTTPS_PORT_443_SOLUTIONS.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Configuration
PRIVATE_IP=""
ELASTIC_IP=""
ALLOCATION_ID=""
SKIP_ALLOCATE=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --private-ip)
            PRIVATE_IP="$2"
            shift 2
            ;;
        --elastic-ip)
            ELASTIC_IP="$2"
            shift 2
            ;;
        --allocation-id)
            ALLOCATION_ID="$2"
            shift 2
            ;;
        --skip-allocate)
            SKIP_ALLOCATE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --private-ip IP      Use specific private IP (auto-generated if not provided)"
            echo "  --elastic-ip IP      Use existing Elastic IP"
            echo "  --allocation-id ID   Use existing Elastic IP allocation ID"
            echo "  --skip-allocate      Skip IP allocation (for pre-existing setup)"
            echo "  --force              Force reconfiguration even if already set up"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get master node information
get_master_info() {
    local master_ip
    master_ip=$(get_master_ip)
    
    if [[ -z "$master_ip" ]]; then
        log_error "Could not get master node IP"
        return 1
    fi
    
    # Get instance ID by public IP
    local instance_id
    instance_id=$(aws ec2 describe-instances \
        --filters "Name=network-interface.association.public-ip,Values=$master_ip" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    if [[ -z "$instance_id" ]] || [[ "$instance_id" == "None" ]]; then
        log_error "Could not find instance ID for master node"
        return 1
    fi
    
    # Get network interface ID
    local eni_id
    eni_id=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    if [[ -z "$eni_id" ]] || [[ "$eni_id" == "None" ]]; then
        log_error "Could not find network interface ID"
        return 1
    fi
    
    # Get subnet CIDR for determining IP range
    local subnet_id
    subnet_id=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].SubnetId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    local subnet_cidr
    subnet_cidr=$(aws ec2 describe-subnets \
        --subnet-ids "$subnet_id" \
        --query 'Subnets[0].CidrBlock' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    echo "$instance_id|$eni_id|$master_ip|$subnet_cidr"
}

# Check if secondary IP already exists
check_existing_secondary_ip() {
    local eni_id="$1"
    
    # Get all private IPs on the interface
    local secondary_ips
    secondary_ips=$(aws ec2 describe-network-interfaces \
        --network-interface-ids "$eni_id" \
        --query 'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].PrivateIpAddress' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    if [[ -n "$secondary_ips" ]] && [[ "$secondary_ips" != "None" ]]; then
        echo "$secondary_ips"
        return 0
    fi
    
    return 1
}

# Generate a private IP in the subnet range
generate_private_ip() {
    local subnet_cidr="$1"
    local eni_id="$2"
    
    # Extract network prefix and size
    local network_prefix="${subnet_cidr%/*}"
    local prefix_size="${subnet_cidr#*/}"
    
    # For simplicity, we'll use a specific IP based on the examples
    # In production, you might want to implement proper IP generation
    if [[ "$network_prefix" == "172.20.0.0" ]]; then
        echo "172.20.245.38"
    else
        # Try to get next available IP
        local base_ip="${network_prefix%.*}"
        local last_octet="${network_prefix##*.}"
        
        # Try IPs in sequence
        for i in {10..250}; do
            local test_ip="$base_ip.$i"
            # Check if IP is available
            if ! aws ec2 describe-network-interfaces \
                --filters "Name=addresses.private-ip-address,Values=$test_ip" \
                --query 'NetworkInterfaces[0]' \
                --output text \
                --profile "$AWS_PROFILE" \
                --region "$AWS_REGION" >/dev/null 2>&1; then
                echo "$test_ip"
                return 0
            fi
        done
    fi
    
    log_error "Could not generate available private IP"
    return 1
}

# Allocate secondary private IP
allocate_secondary_ip() {
    local eni_id="$1"
    local private_ip="$2"
    
    log_info "Allocating secondary private IP: $private_ip"
    
    if [[ -z "$private_ip" ]]; then
        # Let AWS assign one
        aws ec2 assign-private-ip-addresses \
            --network-interface-id "$eni_id" \
            --secondary-private-ip-address-count 1 \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION"
    else
        # Use specific IP
        aws ec2 assign-private-ip-addresses \
            --network-interface-id "$eni_id" \
            --private-ip-addresses "$private_ip" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION"
    fi
    
    if [[ $? -eq 0 ]]; then
        log_info "Secondary private IP allocated successfully"
        return 0
    else
        log_error "Failed to allocate secondary private IP"
        return 1
    fi
}

# Allocate Elastic IP
allocate_elastic_ip() {
    log_info "Allocating new Elastic IP..."
    
    local allocation_result
    allocation_result=$(aws ec2 allocate-address \
        --domain vpc \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --output json)
    
    local alloc_id
    alloc_id=$(echo "$allocation_result" | jq -r '.AllocationId')
    
    local public_ip
    public_ip=$(echo "$allocation_result" | jq -r '.PublicIp')
    
    if [[ -n "$alloc_id" ]] && [[ "$alloc_id" != "null" ]]; then
        log_info "Elastic IP allocated: $public_ip (Allocation ID: $alloc_id)"
        echo "$alloc_id|$public_ip"
        return 0
    else
        log_error "Failed to allocate Elastic IP"
        return 1
    fi
}

# Associate Elastic IP with secondary private IP
associate_elastic_ip() {
    local alloc_id="$1"
    local eni_id="$2"
    local private_ip="$3"
    
    log_info "Associating Elastic IP with secondary IP $private_ip..."
    
    aws ec2 associate-address \
        --allocation-id "$alloc_id" \
        --network-interface-id "$eni_id" \
        --private-ip-address "$private_ip" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    
    if [[ $? -eq 0 ]]; then
        log_info "Elastic IP associated successfully"
        return 0
    else
        log_error "Failed to associate Elastic IP"
        return 1
    fi
}

# Configure secondary IP on the instance
configure_instance_networking() {
    local master_ip="$1"
    local secondary_private_ip="$2"
    
    log_info "Configuring secondary IP on instance..."
    
    # Get the network interface name
    local interface_name
    interface_name=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" \
        "ip -o link show | grep -v lo | head -1 | cut -d: -f2 | tr -d ' '")
    
    if [[ -z "$interface_name" ]]; then
        interface_name="ens5"  # Default for AWS instances
    fi
    
    # Configure the secondary IP
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << EOF
        # Add secondary IP to interface
        sudo ip addr add ${secondary_private_ip}/16 dev $interface_name 2>/dev/null || true
        
        # Make it persistent with netplan
        sudo tee /etc/netplan/99-secondary-ip.yaml > /dev/null << 'NETPLAN'
network:
  version: 2
  ethernets:
    $interface_name:
      addresses:
        - ${secondary_private_ip}/16
NETPLAN
        
        # Apply netplan configuration
        sudo netplan apply
        
        # Verify configuration
        ip addr show $interface_name | grep "$secondary_private_ip"
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "Secondary IP configured on instance"
        return 0
    else
        log_error "Failed to configure secondary IP on instance"
        return 1
    fi
}

# Create API forwarding service
create_api_forward_service() {
    local master_ip="$1"
    local primary_private_ip="$2"
    
    log_info "Creating kube-api-forward service..."
    
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << EOF
        # Create systemd service for API forwarding
        sudo tee /etc/systemd/system/kube-api-forward.service > /dev/null << 'SERVICE'
[Unit]
Description=Kubernetes API Server Port Forwarding
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP4-LISTEN:443,bind=$primary_private_ip,reuseaddr,fork TCP4:127.0.0.1:8443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
        
        # Install socat if not present
        if ! command -v socat >/dev/null; then
            sudo apt-get update
            sudo apt-get install -y socat
        fi
        
        # Enable and start the service
        sudo systemctl daemon-reload
        sudo systemctl enable kube-api-forward
        sudo systemctl start kube-api-forward
        
        # Check status
        sudo systemctl status kube-api-forward --no-pager
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "API forwarding service created and started"
        return 0
    else
        log_error "Failed to create API forwarding service"
        return 1
    fi
}

# Update HAProxy configuration for secondary IP
update_haproxy_config() {
    local master_ip="$1"
    local secondary_private_ip="$2"
    
    log_info "Updating HAProxy configuration for secondary IP..."
    
    # Check if HAProxy is installed
    if ! ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" \
        "command -v haproxy >/dev/null"; then
        log_warning "HAProxy not installed. Run setup-haproxy.sh after this script."
        return 0
    fi
    
    # Create updated HAProxy configuration
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << EOF
        # Backup current configuration
        sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup-secondary-ip
        
        # Create new configuration with secondary IP binding
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
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Frontend for HTTPS traffic on secondary IP
frontend https_front
    bind ${secondary_private_ip}:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route based on SNI
    use_backend api_backend if { req_ssl_sni -i api.k8s.vadimzak.com }
    default_backend ingress_https

# Frontend for HTTP traffic on secondary IP
frontend http_front
    bind ${secondary_private_ip}:80
    mode http
    default_backend ingress_http

# Stats page
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s

# Backend for Kubernetes API server (primary IP)
backend api_backend
    mode tcp
    server api-server 127.0.0.1:8443 check

# Backend for ingress HTTPS
backend ingress_https
    mode tcp
    server ingress 127.0.0.1:30443 check

# Backend for ingress HTTP
backend ingress_http
    mode http
    option httpchk GET /healthz
    server ingress 127.0.0.1:30080 check
HAPROXY_CONFIG
        
        # Test configuration
        sudo haproxy -f /etc/haproxy/haproxy.cfg -c
        
        # Restart HAProxy
        sudo systemctl restart haproxy
        sudo systemctl status haproxy --no-pager
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "HAProxy configuration updated for secondary IP"
        return 0
    else
        log_error "Failed to update HAProxy configuration"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting secondary IP setup for Kubernetes cluster..."
    
    # Get master node information
    local master_info
    master_info=$(get_master_info)
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    IFS='|' read -r instance_id eni_id primary_ip subnet_cidr <<< "$master_info"
    log_info "Master node: Instance=$instance_id, ENI=$eni_id, Primary IP=$primary_ip"
    
    # Check if secondary IP already exists
    local existing_secondary_ip
    existing_secondary_ip=$(check_existing_secondary_ip "$eni_id")
    
    if [[ -n "$existing_secondary_ip" ]] && [[ "$FORCE" != "true" ]]; then
        log_warning "Secondary IP already exists: $existing_secondary_ip"
        log_info "Use --force to reconfigure"
        
        # Still create/update services if needed
        create_api_forward_service "$primary_ip" "$primary_ip"
        update_haproxy_config "$primary_ip" "$existing_secondary_ip"
        
        log_info "Secondary IP setup verified"
        exit 0
    fi
    
    # Determine private IP to use
    if [[ -z "$PRIVATE_IP" ]]; then
        if [[ -n "$existing_secondary_ip" ]]; then
            PRIVATE_IP="$existing_secondary_ip"
            log_info "Using existing secondary IP: $PRIVATE_IP"
        else
            PRIVATE_IP=$(generate_private_ip "$subnet_cidr" "$eni_id")
            if [[ $? -ne 0 ]]; then
                exit 1
            fi
            log_info "Generated private IP: $PRIVATE_IP"
        fi
    fi
    
    # Allocate secondary IP if needed
    if [[ "$SKIP_ALLOCATE" != "true" ]] && [[ -z "$existing_secondary_ip" ]]; then
        allocate_secondary_ip "$eni_id" "$PRIVATE_IP"
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
    fi
    
    # Allocate or use existing Elastic IP
    local elastic_ip_info
    if [[ -n "$ALLOCATION_ID" ]]; then
        # Get public IP for existing allocation
        ELASTIC_IP=$(aws ec2 describe-addresses \
            --allocation-ids "$ALLOCATION_ID" \
            --query 'Addresses[0].PublicIp' \
            --output text \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION")
        elastic_ip_info="$ALLOCATION_ID|$ELASTIC_IP"
    elif [[ -z "$ELASTIC_IP" ]]; then
        # Allocate new Elastic IP
        elastic_ip_info=$(allocate_elastic_ip)
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        IFS='|' read -r ALLOCATION_ID ELASTIC_IP <<< "$elastic_ip_info"
    else
        # Find allocation ID for existing Elastic IP
        ALLOCATION_ID=$(aws ec2 describe-addresses \
            --public-ips "$ELASTIC_IP" \
            --query 'Addresses[0].AllocationId' \
            --output text \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION")
    fi
    
    # Associate Elastic IP with secondary IP
    associate_elastic_ip "$ALLOCATION_ID" "$eni_id" "$PRIVATE_IP"
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    # Configure networking on instance
    configure_instance_networking "$primary_ip" "$PRIVATE_IP"
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    # Create API forwarding service
    create_api_forward_service "$primary_ip" "$primary_ip"
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    # Update HAProxy if installed
    update_haproxy_config "$primary_ip" "$PRIVATE_IP"
    
    # Print summary
    echo
    log_info "Secondary IP setup completed successfully!"
    echo
    echo "Configuration Summary:"
    echo "====================="
    echo "Primary IP (API Server): $primary_ip"
    echo "Secondary Private IP: $PRIVATE_IP"
    echo "Secondary Public IP: $ELASTIC_IP"
    echo "Allocation ID: $ALLOCATION_ID"
    echo
    echo "Services:"
    echo "========="
    echo "- API Server: https://api.$CLUSTER_NAME (via primary IP)"
    echo "- Applications: https://<app>.$DNS_ZONE (via secondary IP)"
    echo "- HAProxy Stats: http://$ELASTIC_IP:8404/stats"
    echo
    echo "Next steps:"
    echo "==========="
    echo "1. Update DNS records: ./scripts/k8s/update-app-dns-secondary.sh"
    echo "2. If HAProxy not installed: ./scripts/k8s/setup-haproxy.sh"
    echo "3. Deploy applications: ./scripts/k8s/deploy-app.sh <app-name>"
    echo
    echo "Cost: ~$3.60/month for the additional Elastic IP"
}

# Run main function
main "$@"