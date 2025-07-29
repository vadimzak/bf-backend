#!/bin/bash
set -euo pipefail

# Update individual app DNS records to point to K8s master node

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Get master IP
master_ip=$(get_master_ip)

if [[ -z "$master_ip" ]]; then
    log_error "Could not get master node IP"
    exit 1
fi

log_info "Master node IP: $master_ip"

# List of app subdomains to update
SUBDOMAINS=(
    "sample"
    "sample-6"
    "sample-3"
    "sample-4"
)

# Update each subdomain
for subdomain in "${SUBDOMAINS[@]}"; do
    # Check if record exists
    existing_ip=$(aws route53 list-resource-record-sets \
        --hosted-zone-id Z2O129XK0SJBV9 \
        --query "ResourceRecordSets[?Name=='${subdomain}.${DNS_ZONE}.'].ResourceRecords[0].Value" \
        --output text \
        --profile "$AWS_PROFILE" 2>/dev/null || echo "")
    
    if [[ -n "$existing_ip" ]]; then
        if [[ "$existing_ip" == "$master_ip" ]]; then
            log_info "$subdomain.${DNS_ZONE} already points to $master_ip"
        else
            log_info "Updating $subdomain.${DNS_ZONE} from $existing_ip to $master_ip"
            update_dns_record "${subdomain}.${DNS_ZONE}" "$master_ip"
        fi
    else
        log_info "$subdomain.${DNS_ZONE} doesn't exist, skipping"
    fi
done

log_info "DNS updates complete!"
log_info "It may take 5-15 minutes for DNS to propagate"
echo
echo "Applications will be accessible at:"
for subdomain in "${SUBDOMAINS[@]}"; do
    echo "  https://${subdomain}.vadimzak.com"
done