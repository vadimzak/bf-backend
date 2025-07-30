#!/bin/bash
set -euo pipefail

# Update DNS records to use secondary IP for applications
# This is part of the HTTPS port 443 solution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

log_info "Updating DNS records to use secondary IP..."

# Get the secondary IP information
MASTER_IP=$(get_master_ip)
if [[ -z "$MASTER_IP" ]]; then
    log_error "Could not get master node IP"
    exit 1
fi

# Get instance information
INSTANCE_ID=$(timeout 10 aws ec2 describe-instances \
    --filters "Name=network-interface.association.public-ip,Values=$MASTER_IP" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [[ -z "$INSTANCE_ID" ]] || [[ "$INSTANCE_ID" == "None" ]]; then
    log_error "Could not find instance ID for master node"
    exit 1
fi

# Get network interface ID
ENI_ID=$(timeout 10 aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
    --output text \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

# Get secondary IP information
SECONDARY_IP_INFO=$(timeout 10 aws ec2 describe-network-interfaces \
    --network-interface-ids "$ENI_ID" \
    --query 'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].[PrivateIpAddress,Association.PublicIp]' \
    --output text \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -z "$SECONDARY_IP_INFO" ]]; then
    log_error "No secondary IP found. Run ./scripts/k8s/setup-secondary-ip.sh first"
    exit 1
fi

# Extract secondary public IP
SECONDARY_PUBLIC_IP=$(echo "$SECONDARY_IP_INFO" | awk '{print $2}')
if [[ -z "$SECONDARY_PUBLIC_IP" ]] || [[ "$SECONDARY_PUBLIC_IP" == "None" ]]; then
    log_error "Secondary IP exists but has no public IP associated"
    exit 1
fi

log_info "Found secondary public IP: $SECONDARY_PUBLIC_IP"

# Update wildcard DNS record
log_info "Updating wildcard DNS record (*.${DNS_ZONE}) to point to secondary IP..."
update_dns_record "*.${DNS_ZONE}" "$SECONDARY_PUBLIC_IP"

# Keep API server DNS pointing to primary IP
log_info "Ensuring API server DNS (api.${CLUSTER_NAME}) points to primary IP..."
update_dns_record "api.${CLUSTER_NAME}" "$MASTER_IP"

echo
log_info "DNS records updated successfully!"
echo
echo "DNS Configuration:"
echo "=================="
echo "Primary IP ($MASTER_IP):"
echo "  - api.${CLUSTER_NAME} → Kubernetes API Server"
echo
echo "Secondary IP ($SECONDARY_PUBLIC_IP):"
echo "  - *.${DNS_ZONE} → Application ingress"
echo
echo "Applications will be accessible at:"
echo "  - https://<app-name>.${DNS_ZONE}"
echo "  - http://<app-name>.${DNS_ZONE}"
echo
echo "Note: DNS propagation may take a few minutes."
echo