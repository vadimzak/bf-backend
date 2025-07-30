#!/bin/bash
set -euo pipefail

# Fix API server port conflict for secondary IP solution
# This script changes the API server to listen on port 8443 and creates a socat forwarder

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Get master IP
MASTER_IP=$(get_master_ip)
if [[ -z "$MASTER_IP" ]]; then
    log_error "Could not get master node IP"
    exit 1
fi

log_info "Configuring API server for secondary IP solution on master: $MASTER_IP"

# SSH to master and perform the configuration
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$MASTER_IP" << 'EOF'
    set -euo pipefail
    
    echo "[INFO] Backing up kube-apiserver manifest..."
    sudo cp /etc/kubernetes/manifests/kube-apiserver.manifest /etc/kubernetes/manifests/kube-apiserver.manifest.backup-$(date +%Y%m%d-%H%M%S)
    
    echo "[INFO] Updating kube-apiserver to listen on port 8443..."
    sudo sed -i 's/--secure-port=443/--secure-port=8443/' /etc/kubernetes/manifests/kube-apiserver.manifest
    
    echo "[INFO] Waiting for kube-apiserver to restart with new port..."
    sleep 30
    
    # Check if API server is listening on 8443
    for i in {1..10}; do
        if sudo ss -tlnp | grep -q ":8443.*kube-apiserver"; then
            echo "[INFO] API server is now listening on port 8443"
            break
        fi
        echo "[INFO] Waiting for API server to restart... ($i/10)"
        sleep 10
    done
    
    # Install socat if not present
    if ! command -v socat >/dev/null; then
        echo "[INFO] Installing socat..."
        sudo apt-get update
        sudo apt-get install -y socat
    fi
    
    # Get primary IP
    PRIMARY_IP=$(ip -4 addr show ens5 | grep -oP '(?<=inet\s)172\.20\.\d+\.\d+(?=/)' | head -1)
    echo "[INFO] Primary IP: $PRIMARY_IP"
    
    # Create systemd service for API forwarding
    echo "[INFO] Creating kube-api-forward service..."
    sudo tee /etc/systemd/system/kube-api-forward.service > /dev/null << SERVICE
[Unit]
Description=Kubernetes API Server Port Forwarding
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP4-LISTEN:443,bind=$PRIMARY_IP,reuseaddr,fork TCP4:127.0.0.1:8443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
    
    # Enable and start the service
    echo "[INFO] Starting kube-api-forward service..."
    sudo systemctl daemon-reload
    sudo systemctl enable kube-api-forward
    sudo systemctl start kube-api-forward
    
    # Check service status
    sudo systemctl status kube-api-forward --no-pager
    
    # Verify port bindings
    echo "[INFO] Current port bindings:"
    sudo ss -tlnp | grep -E ":(443|8443)"
EOF

if [[ $? -eq 0 ]]; then
    log_info "API server port configuration completed successfully"
    
    # Update kubeconfig to use port 8443 temporarily
    log_info "Updating local kubeconfig to use port 8443..."
    kubectl config set-cluster "$CLUSTER_NAME" --server="https://api.$CLUSTER_NAME:8443"
    
    # Test connection
    if kubectl get nodes >/dev/null 2>&1; then
        log_info "Successfully connected to API server on port 8443"
        
        # Restore to port 443 (which will be forwarded by socat)
        kubectl config set-cluster "$CLUSTER_NAME" --server="https://api.$CLUSTER_NAME"
        
        if kubectl get nodes >/dev/null 2>&1; then
            log_info "Successfully connected through socat forwarder on port 443"
        else
            log_warning "Could not connect through forwarder, keeping port 8443 in kubeconfig"
            kubectl config set-cluster "$CLUSTER_NAME" --server="https://api.$CLUSTER_NAME:8443"
        fi
    else
        log_error "Failed to connect to API server on port 8443"
        exit 1
    fi
    
    echo
    log_info "Next steps:"
    echo "1. Restart HAProxy: ssh -i $SSH_KEY_PATH ubuntu@$MASTER_IP 'sudo systemctl restart haproxy'"
    echo "2. Update DNS to secondary IP: ./scripts/k8s/update-app-dns-secondary.sh"
else
    log_error "Failed to configure API server port"
    exit 1
fi