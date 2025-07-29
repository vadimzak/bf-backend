#!/bin/bash
set -euo pipefail

# Quick start script for Kubernetes cluster setup
# This runs all the necessary steps in sequence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

log_info "Starting Kubernetes Quick Setup"
echo "This will:"
echo "1. Install prerequisites (kubectl, kops, helm)"
echo "2. Bootstrap a Kubernetes cluster"
echo "3. Install ingress controller and cert-manager"
echo "4. Configure applications"
echo
echo "Estimated time: 15-20 minutes"
echo

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Aborted"
    exit 0
fi

# Step 1: Install prerequisites
log_info "Step 1/4: Installing prerequisites..."
if ! "$SCRIPT_DIR/install-prerequisites.sh"; then
    log_error "Failed to install prerequisites"
    exit 1
fi

# Step 2: Bootstrap cluster
log_info "Step 2/4: Bootstrapping Kubernetes cluster..."
if ! "$SCRIPT_DIR/bootstrap-cluster.sh"; then
    log_error "Failed to bootstrap cluster"
    exit 1
fi

# Step 3: Check cluster status
log_info "Step 3/4: Checking cluster status..."
if ! "$SCRIPT_DIR/cluster-status.sh"; then
    log_warning "Cluster might not be fully ready yet"
    log_info "You can check status later with: ./scripts/k8s/cluster-status.sh"
fi

# Step 4: Configure applications (optional)
read -p "Configure applications now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Step 4/4: Configuring applications..."
    if ! "$SCRIPT_DIR/configure-apps.sh"; then
        log_error "Failed to configure applications"
        log_info "You can retry with: ./scripts/k8s/configure-apps.sh"
    fi
else
    log_info "Skipping application configuration"
    log_info "You can run it later with: ./scripts/k8s/configure-apps.sh"
fi

echo
log_info "Kubernetes cluster setup complete!"
echo
echo "Next steps:"
echo "1. Deploy applications: ./scripts/k8s/deploy-app.sh APP_NAME"
echo "2. Check cluster status: ./scripts/k8s/cluster-status.sh"
echo "3. If DNS issues: ./scripts/k8s/fix-dns.sh --use-ip"
echo
echo "Cluster details:"
echo "- Name: $CLUSTER_NAME"
echo "- Region: $AWS_REGION"
echo "- Master IP: $(get_master_ip || echo 'pending')"
echo "- API Server: https://api.$CLUSTER_NAME"