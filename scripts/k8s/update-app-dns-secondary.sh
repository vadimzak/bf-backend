#!/bin/bash
set -euo pipefail

# Update DNS records to point to secondary IP for applications

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Get secondary IP address dynamically
SECONDARY_IP="${SECONDARY_IP:-}"

# If not provided, try to get it from AWS
if [[ -z "$SECONDARY_IP" ]]; then
    # Get master instance
    MASTER_IP=$(get_master_ip)
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=network-interface.association.public-ip,Values=$MASTER_IP" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
    
    # Get secondary public IP
    SECONDARY_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].Association.PublicIp | [0]' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION")
fi

# Fallback to hardcoded if still not found
SECONDARY_IP="${SECONDARY_IP:-51.84.26.89}"

# Update application DNS records
update_app_dns() {
    local app_name="$1"
    local current_ip
    
    # Check current DNS
    current_ip=$(dig +short "$app_name.$DNS_ZONE" | head -1)
    
    if [[ -z "$current_ip" ]]; then
        log_info "$app_name.$DNS_ZONE doesn't exist, skipping"
        return
    fi
    
    if [[ "$current_ip" == "$SECONDARY_IP" ]]; then
        log_info "$app_name.$DNS_ZONE already points to secondary IP $SECONDARY_IP"
        return
    fi
    
    log_info "Updating $app_name.$DNS_ZONE from $current_ip to $SECONDARY_IP"
    
    # Update DNS record
    update_dns_record "$app_name.$DNS_ZONE" "$SECONDARY_IP"
}

# Main execution
main() {
    log_info "Secondary IP: $SECONDARY_IP"
    
    # Update specific apps
    update_app_dns "sample"
    update_app_dns "sample-6"
    update_app_dns "sample-3"
    update_app_dns "sample-4"
    
    log_info "DNS updates complete!"
    log_info "It may take 5-15 minutes for DNS to propagate"
    echo
    echo "Applications will be accessible at:"
    echo "  https://sample.vadimzak.com"
    echo "  https://sample-6.vadimzak.com"
    echo
    echo "API server remains at: https://api.k8s.vadimzak.com (primary IP)"
}

# Run main function
main "$@"