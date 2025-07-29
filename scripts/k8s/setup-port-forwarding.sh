#!/bin/bash
set -euo pipefail

# Set up port forwarding from 80/443 to NodePorts
# This allows apps to be accessed on standard ports

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Get master IP
master_ip=$(get_master_ip)

if [[ -z "$master_ip" ]]; then
    log_error "Could not get master node IP"
    exit 1
fi

log_info "Setting up port forwarding on master node: $master_ip"

# SSH and set up iptables rules
ssh -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF'
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Add iptables rules for HTTP (80 -> 30080)
# First check if rule exists
if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 30080 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 30080
    echo "Added port forwarding rule: 80 -> 30080"
else
    echo "Port forwarding rule already exists: 80 -> 30080"
fi

# For HTTPS, we can't forward 443 as it's used by API server
# Instead, we'll add a rule for external traffic only
if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 8443 -j REDIRECT --to-port 30443 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp --dport 8443 -j REDIRECT --to-port 30443
    echo "Added port forwarding rule: 8443 -> 30443"
else
    echo "Port forwarding rule already exists: 8443 -> 30443"
fi

# Save iptables rules to persist across reboots
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# List current NAT rules
echo
echo "Current NAT rules:"
sudo iptables -t nat -L PREROUTING -n -v
EOF

log_info "Port forwarding setup complete!"
echo
echo "Applications are now accessible at:"
echo "  HTTP:  http://sample.vadimzak.com (port 80)"
echo "  HTTPS: https://sample.vadimzak.com:8443 (port 8443)"
echo
echo "Note: Port 443 is reserved for the Kubernetes API server"