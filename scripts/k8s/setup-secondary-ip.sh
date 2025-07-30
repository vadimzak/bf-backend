#!/bin/bash
set -euo pipefail

# Setup secondary IP for Kubernetes cluster to resolve port 443 conflict
# This implements Option 3 from K8S_HTTPS_PORT_443_SOLUTIONS.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Run command or show what would be run
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*" >&2
        return 0
    else
        "$@"
    fi
}

# Configuration
ELASTIC_IP=""
ALLOCATION_ID=""
SKIP_ALLOCATE=false
FORCE=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --elastic-ip IP      Use existing Elastic IP"
            echo "  --allocation-id ID   Use existing Elastic IP allocation ID"
            echo "  --skip-allocate      Skip IP allocation (for pre-existing setup)"
            echo "  --force              Force reconfiguration even if already set up"
            echo "  --dry-run            Show what would be done without making changes"
            echo "  --help               Show this help message"
            echo ""
            echo "Note: Secondary private IPs are now auto-assigned by AWS for simplicity"
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
        log_error "Make sure cluster is running and kubectl is configured"
        return 1
    fi
    
    log_info "Found master IP: $master_ip" >&2
    
    # Get instance ID by public IP
    local instance_id
    instance_id=$(timeout 10 aws ec2 describe-instances \
        --filters "Name=network-interface.association.public-ip,Values=$master_ip" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ -z "$instance_id" ]] || [[ "$instance_id" == "None" ]]; then
        log_error "Could not find instance ID for master node with IP: $master_ip"
        log_error "AWS CLI error or instance not found"
        return 1
    fi
    
    # Get network interface ID
    local eni_id
    eni_id=$(timeout 10 aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ -z "$eni_id" ]] || [[ "$eni_id" == "None" ]]; then
        log_error "Could not find network interface ID for instance: $instance_id"
        return 1
    fi
    
    log_info "Found ENI: $eni_id" >&2
    
    # Get subnet CIDR for determining IP range
    local subnet_id
    subnet_id=$(timeout 10 aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].SubnetId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    local subnet_cidr
    subnet_cidr=$(timeout 10 aws ec2 describe-subnets \
        --subnet-ids "$subnet_id" \
        --query 'Subnets[0].CidrBlock' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    echo "$instance_id|$eni_id|$master_ip|$subnet_cidr"
}

# Check if secondary IP already exists
check_existing_secondary_ip() {
    local eni_id="$1"
    
    log_info "Checking for existing secondary IPs on ENI: $eni_id" >&2
    
    # Get all private IPs on the interface with timeout
    local secondary_ips
    secondary_ips=$(timeout 10 aws ec2 describe-network-interfaces \
        --network-interface-ids "$eni_id" \
        --query 'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].PrivateIpAddress' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$secondary_ips" ]] && [[ "$secondary_ips" != "None" ]] && [[ "$secondary_ips" != "" ]]; then
        echo "$secondary_ips"
        return 0
    fi
    
    return 1
}

# Note: Removed generate_private_ip function - we now use AWS auto-assign which is simpler and more reliable

# Allocate secondary private IP
allocate_secondary_ip() {
    local eni_id="$1"
    
    log_info "Allocating secondary private IP (auto-assign)..." >&2
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] aws ec2 assign-private-ip-addresses --network-interface-id $eni_id --secondary-private-ip-address-count 1" >&2
        echo "172.20.5.100"  # Mock IP for dry run
        return 0
    fi
    
    # Let AWS assign one automatically - simpler and more reliable
    local result
    local exit_code
    result=$(timeout 30 aws ec2 assign-private-ip-addresses \
        --network-interface-id "$eni_id" \
        --secondary-private-ip-address-count 1 \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --output json 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        # Extract the assigned IP
        local assigned_ip
        assigned_ip=$(echo "$result" | jq -r '.AssignedPrivateIpAddresses[0].PrivateIpAddress' 2>/dev/null || echo "")
        
        if [[ -n "$assigned_ip" ]] && [[ "$assigned_ip" != "null" ]] && [[ "$assigned_ip" != "" ]]; then
            log_info "Secondary private IP allocated successfully: $assigned_ip" >&2
            echo "$assigned_ip"
            return 0
        else
            log_error "Failed to extract assigned IP from response" >&2
            log_error "Response: $result" >&2
            return 1
        fi
    else
        log_error "Failed to allocate secondary private IP (exit code: $exit_code)" >&2
        log_error "Error: $result" >&2
        
        # Check for common errors
        if echo "$result" | grep -q "InsufficientFreeAddressesInSubnet"; then
            log_error "No free IP addresses available in subnet. The subnet may be too small." >&2
        elif echo "$result" | grep -q "UnauthorizedOperation"; then
            log_error "AWS permission issue. Check IAM policies for ec2:AssignPrivateIpAddresses" >&2
        fi
        
        return 1
    fi
}

# Allocate Elastic IP
allocate_elastic_ip() {
    log_info "Allocating new Elastic IP..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] aws ec2 allocate-address --domain vpc" >&2
        echo "eipalloc-dryrun12345|52.1.2.3"  # Mock values for dry run
        return 0
    fi
    
    local allocation_result
    allocation_result=$(timeout 30 aws ec2 allocate-address \
        --domain vpc \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --output json 2>&1)
    
    if [[ $? -eq 0 ]]; then
        local alloc_id
        alloc_id=$(echo "$allocation_result" | jq -r '.AllocationId')
        
        local public_ip
        public_ip=$(echo "$allocation_result" | jq -r '.PublicIp')
        
        if [[ -n "$alloc_id" ]] && [[ "$alloc_id" != "null" ]]; then
            log_info "Elastic IP allocated: $public_ip (Allocation ID: $alloc_id)"
            echo "$alloc_id|$public_ip"
            return 0
        else
            log_error "Failed to extract allocation info from response"
            return 1
        fi
    else
        log_error "Failed to allocate Elastic IP: $allocation_result"
        return 1
    fi
}

# Associate Elastic IP with secondary private IP
associate_elastic_ip() {
    local alloc_id="$1"
    local eni_id="$2"
    local private_ip="$3"
    
    log_info "Associating Elastic IP with secondary IP $private_ip..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] aws ec2 associate-address --allocation-id $alloc_id --network-interface-id $eni_id --private-ip-address $private_ip" >&2
        return 0
    fi
    
    # Retry logic for association (sometimes AWS needs time after IP allocation)
    local attempts=0
    local max_attempts=3
    local retry_delay=2
    
    while [[ $attempts -lt $max_attempts ]]; do
        local result
        result=$(timeout 30 aws ec2 associate-address \
            --allocation-id "$alloc_id" \
            --network-interface-id "$eni_id" \
            --private-ip-address "$private_ip" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            log_info "Elastic IP associated successfully"
            return 0
        else
            attempts=$((attempts + 1))
            if [[ $attempts -lt $max_attempts ]]; then
                log_warning "Association failed, retrying in ${retry_delay}s... (attempt $attempts/$max_attempts)"
                log_debug "Error was: $result"
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))  # Exponential backoff
            else
                log_error "Failed to associate Elastic IP after $max_attempts attempts: $result"
                return 1
            fi
        fi
    done
}

# Configure secondary IP on the instance
configure_instance_networking() {
    local master_ip="$1"
    local secondary_private_ip="$2"
    
    log_info "Configuring secondary IP on instance..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would configure secondary IP $secondary_private_ip on instance $master_ip" >&2
        echo "[DRY RUN] - Add IP to network interface" >&2
        echo "[DRY RUN] - Create netplan configuration" >&2
        echo "[DRY RUN] - Apply configuration" >&2
        return 0
    fi
    
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

# Frontend for HTTPS traffic - binds to port 8443 (receives traffic from iptables redirect)
frontend https_front
    bind *:8443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route based on SNI
    use_backend api_backend if { req_ssl_sni -i api.k8s.vadimzak.com }
    default_backend ingress_https

# Frontend for HTTP traffic
frontend http_front
    bind *:80
    mode http
    default_backend ingress_http

# Stats page
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s

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
    
    # Verify cluster is accessible
    if ! kubectl get nodes >/dev/null 2>&1; then
        log_error "Cannot access Kubernetes cluster. Is kubectl configured?"
        log_error "Run: kops export kubecfg --admin"
        exit 1
    fi
    
    # Get master node information
    local master_info
    master_info=$(get_master_info)
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get master node information"
        log_error "Ensure the cluster is running and AWS credentials are configured"
        exit 1
    fi
    
    IFS='|' read -r instance_id eni_id primary_ip subnet_cidr <<< "$master_info"
    log_info "Master node: Instance=$instance_id, ENI=$eni_id, Primary IP=$primary_ip"
    
    # Initialize PRIVATE_IP variable
    local PRIVATE_IP=""
    
    # Check if secondary IP already exists
    local existing_secondary_ip
    existing_secondary_ip=$(check_existing_secondary_ip "$eni_id" || true)
    
    if [[ -n "$existing_secondary_ip" ]]; then
        if [[ "$FORCE" != "true" ]]; then
            log_warning "Secondary IP already exists: $existing_secondary_ip"
            
            # Check if it has an associated public IP
            local secondary_public_ip
            secondary_public_ip=$(aws ec2 describe-network-interfaces \
                --network-interface-ids "$eni_id" \
                --query 'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].Association.PublicIp' \
                --output text \
                --profile "$AWS_PROFILE" \
                --region "$AWS_REGION" 2>/dev/null || echo "")
            
            if [[ -n "$secondary_public_ip" ]] && [[ "$secondary_public_ip" != "None" ]]; then
                log_info "Secondary IP has public IP: $secondary_public_ip"
                log_info "Use --force to reconfigure"
                
                # Update HAProxy config if needed (no API forward service required with iptables solution)
                update_haproxy_config "$primary_ip" "$existing_secondary_ip"
                
                log_info "Secondary IP setup verified"
                exit 0
            else
                log_warning "Secondary IP exists but has no public IP - will continue setup"
                PRIVATE_IP="$existing_secondary_ip"
                # Don't exit - continue to associate Elastic IP
            fi
        else
            log_info "Force mode: will reconfigure existing secondary IP"
            PRIVATE_IP="$existing_secondary_ip"
        fi
    fi
    
    # Allocate secondary IP if needed (skip if we already have one without public IP)
    if [[ -z "$PRIVATE_IP" ]]; then
        if [[ -z "$existing_secondary_ip" ]]; then
            if [[ "$SKIP_ALLOCATE" != "true" ]]; then
                # Let AWS auto-assign a secondary IP
                PRIVATE_IP=$(allocate_secondary_ip "$eni_id")
                if [[ $? -ne 0 ]]; then
                    log_error "Failed to allocate secondary IP"
                    exit 1
                fi
            else
                log_error "No existing secondary IP and --skip-allocate was specified"
                exit 1
            fi
        else
            PRIVATE_IP="$existing_secondary_ip"
            log_info "Using existing secondary IP: $PRIVATE_IP"
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
        # First check for unused Elastic IPs
        log_info "Checking for unused Elastic IPs..." >&2
        local unused_eips
        unused_eips=$(aws ec2 describe-addresses \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query 'Addresses[?AssociationId==`null`].[AllocationId,PublicIp]' \
            --output text 2>/dev/null)
        
        if [[ -n "$unused_eips" ]]; then
            # Use the first unused EIP
            ALLOCATION_ID=$(echo "$unused_eips" | head -1 | awk '{print $1}')
            ELASTIC_IP=$(echo "$unused_eips" | head -1 | awk '{print $2}')
            log_info "Reusing existing unassociated Elastic IP: $ELASTIC_IP (AllocationId: $ALLOCATION_ID)" >&2
            elastic_ip_info="$ALLOCATION_ID|$ELASTIC_IP"
        else
            # Check current EIP count vs limit before trying to allocate
            log_info "No unused Elastic IPs found, checking account limits..." >&2
            local eip_count
            eip_count=$(aws ec2 describe-addresses \
                --profile "$AWS_PROFILE" \
                --region "$AWS_REGION" \
                --query 'length(Addresses)' \
                --output text 2>/dev/null || echo "0")
            
            # Default limit is 5 for most accounts
            local eip_limit=5
            # Try to get actual limit (requires proper IAM permissions)
            local actual_limit
            actual_limit=$(aws service-quotas get-service-quota \
                --service-code ec2 \
                --quota-code L-0263D0A3 \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE" \
                --query 'Quota.Value' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$actual_limit" ]] && [[ "$actual_limit" != "None" ]]; then
                eip_limit=$actual_limit
            fi
            
            log_info "Current Elastic IPs: $eip_count / $eip_limit" >&2
            
            if [[ $eip_count -ge ${eip_limit%.*} ]]; then
                log_error "Cannot allocate new Elastic IP - at account limit ($eip_count/$eip_limit)" >&2
                log_error "" >&2
                log_error "Current Elastic IP usage:" >&2
                aws ec2 describe-addresses --profile "$AWS_PROFILE" --region "$AWS_REGION" \
                    --query 'Addresses[].[PublicIp,AssociationId,InstanceId,Tags[?Key==`Name`].Value|[0]]' \
                    --output table >&2 || true
                log_error "" >&2
                log_error "Options to resolve:" >&2
                log_error "1. Release unused Elastic IPs:" >&2
                log_error "   ./scripts/k8s/cleanup-secondary-ip.sh" >&2
                log_error "" >&2
                log_error "2. Request a limit increase:" >&2
                log_error "   aws service-quotas request-service-quota-increase \\" >&2
                log_error "     --service-code ec2 --quota-code L-0263D0A3 \\" >&2
                log_error "     --desired-value 10 --region $AWS_REGION --profile $AWS_PROFILE" >&2
                log_error "" >&2
                log_error "3. Use cluster without secondary IP (HTTPS on port 30443):" >&2
                log_error "   ./scripts/k8s/teardown-cluster.sh" >&2
                log_error "   ./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip" >&2
                exit 1
            fi
            
            # Try to allocate new Elastic IP
            log_info "Attempting to allocate new Elastic IP..." >&2
            elastic_ip_info=$(allocate_elastic_ip)
            if [[ $? -ne 0 ]]; then
                log_error "Failed to allocate new Elastic IP" >&2
                log_error "Check AWS CloudTrail for detailed error information" >&2
                exit 1
            fi
            IFS='|' read -r ALLOCATION_ID ELASTIC_IP <<< "$elastic_ip_info"
        fi
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
    
    # Set up iptables PREROUTING redirect - this is the KEY INNOVATION!
    log_info "Setting up iptables PREROUTING redirect for HTTPS traffic..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would set up iptables redirect on $primary_ip:" >&2
        echo "[DRY RUN] - iptables -t nat -A PREROUTING -d $PRIVATE_IP -p tcp --dport 443 -j REDIRECT --to-port 8443" >&2
        echo "[DRY RUN] - Install iptables-persistent" >&2
        echo "[DRY RUN] - Save rules with netfilter-persistent" >&2
    else
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$primary_ip" << EOF
            # Add iptables rule to redirect port 443 to 8443 for secondary IP
            sudo iptables -t nat -A PREROUTING -d $PRIVATE_IP -p tcp --dport 443 -j REDIRECT --to-port 8443
            
            # Install iptables-persistent if not already installed
            if ! command -v netfilter-persistent >/dev/null 2>&1; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent netfilter-persistent
            fi
            
            # Save the rules
            sudo netfilter-persistent save
            
            # Verify the rule
            echo "iptables PREROUTING rules:"
            sudo iptables -t nat -L PREROUTING -n -v | grep -E "REDIRECT|443"
EOF
    fi
    
    # Create API forwarding service (if needed - usually not required with HAProxy)
    # create_api_forward_service "$primary_ip" "$primary_ip"
    
    # Update HAProxy if installed
    if [[ "$DRY_RUN" != "true" ]]; then
        update_haproxy_config "$primary_ip" "$PRIVATE_IP"
    else
        echo "[DRY RUN] Would update HAProxy configuration" >&2
    fi
    
    # Print summary
    echo
    log_info "Secondary IP setup completed successfully!"
    echo
    echo "Configuration Summary:"
    echo "====================="
    echo "Primary IP (API Server): $primary_ip"
    echo "Secondary Private IP: $PRIVATE_IP"
    if [[ -n "$ELASTIC_IP" ]]; then
        echo "Secondary Public IP: $ELASTIC_IP"
    fi
    if [[ -n "$ALLOCATION_ID" ]]; then
        echo "Allocation ID: $ALLOCATION_ID"
    fi
    echo
    echo "Services:"
    echo "========="
    echo "- API Server: https://api.$CLUSTER_NAME (via primary IP)"
    echo "- Applications: https://<app>.$DNS_ZONE (via secondary IP)"
    if [[ -n "$ELASTIC_IP" ]]; then
        echo "- HAProxy Stats: http://$ELASTIC_IP:8404/stats"
    fi
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
# The script already has set -euo pipefail which will cause it to exit on any error
main "$@"