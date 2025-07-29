#!/bin/bash
set -euo pipefail

# Update wildcard DNS record to point to K8s master node

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Get master IP
master_ip=$(get_master_ip)

if [[ -z "$master_ip" ]]; then
    log_error "Could not get master node IP"
    exit 1
fi

log_info "Master node IP: $master_ip"

# Update wildcard DNS record
update_dns_record "*.${DNS_ZONE}" "$master_ip"

log_info "DNS update complete!"
log_info "It may take 5-15 minutes for DNS to propagate"
echo
echo "Applications will be accessible at:"
echo "  https://sample.vadimzak.com"
echo "  https://sample-6.vadimzak.com"
echo "  etc..."