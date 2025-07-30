#!/bin/bash
set -euo pipefail

# Complete quick start script for Kubernetes cluster setup with standard ports
# This runs all the necessary steps including HAProxy setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Script options
SKIP_PREREQUISITES=false
CONFIGURE_APPS=true
SETUP_HAPROXY=true
SETUP_SECONDARY_IP=true  # Default to true for HTTPS on port 443
SKIP_CONFIRM=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        --skip-apps)
            CONFIGURE_APPS=false
            shift
            ;;
        --skip-haproxy)
            SETUP_HAPROXY=false
            shift
            ;;
        --no-secondary-ip|--without-secondary-ip)
            SETUP_SECONDARY_IP=false
            shift
            ;;
        --with-secondary-ip)
            # Kept for backwards compatibility
            SETUP_SECONDARY_IP=true
            shift
            ;;
        --yes|-y)
            SKIP_CONFIRM=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --skip-prerequisites      Skip installing kubectl, kops, helm"
            echo "  --skip-apps              Skip application configuration"
            echo "  --skip-haproxy           Skip HAProxy setup (apps on non-standard ports)"
            echo "  --no-secondary-ip        Disable secondary IP (HTTPS only on port 30443)"
            echo "  --without-secondary-ip   Same as --no-secondary-ip"
            echo "  --yes, -y                Skip confirmation prompts"
            echo "  --help                   Show this help message"
            echo ""
            echo "Note: Secondary IP is ENABLED BY DEFAULT for HTTPS on port 443"
            echo "      Use --no-secondary-ip to disable and save ~$3.60/month"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting Complete Kubernetes Setup with Standard Ports"
echo "This will:"
echo "1. Install prerequisites (kubectl, kops, helm)"
echo "2. Bootstrap a Kubernetes cluster"
echo "3. Install ingress controller and cert-manager"
echo "4. Configure applications"
if [[ "$SETUP_SECONDARY_IP" == "true" ]]; then
    echo "5. Setup secondary IP and HAProxy for HTTPS on standard ports (80/443)"
    echo
    echo "Note: Secondary IP is ENABLED BY DEFAULT and costs ~$3.60/month"
    echo "      Use --no-secondary-ip to disable and use port 30443 for HTTPS"
else
    echo "5. Setup HAProxy for HTTP on port 80 (HTTPS on non-standard port 30443)"
    echo
    echo "Note: Secondary IP is DISABLED. HTTPS will only work on port 30443"
    echo "      Remove --no-secondary-ip flag to enable HTTPS on port 443"
fi
echo
echo "Estimated time: 20-25 minutes"
echo

if [[ "$SKIP_CONFIRM" != "true" ]]; then
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted"
        exit 0
    fi
fi

# Step 1: Install prerequisites
if [[ "$SKIP_PREREQUISITES" != "true" ]]; then
    log_info "Step 1/5: Installing prerequisites..."
    if ! "$SCRIPT_DIR/install-prerequisites.sh"; then
        log_error "Failed to install prerequisites"
        exit 1
    fi
else
    log_info "Step 1/5: Skipping prerequisites installation"
fi

# Step 2: Bootstrap cluster
log_info "Step 2/5: Bootstrapping Kubernetes cluster..."
BOOTSTRAP_ARGS=""
if [[ "$SETUP_SECONDARY_IP" != "true" ]]; then
    BOOTSTRAP_ARGS="--no-secondary-ip"
fi
if ! "$SCRIPT_DIR/bootstrap-cluster.sh" $BOOTSTRAP_ARGS; then
    log_error "Failed to bootstrap cluster"
    exit 1
fi

# Step 3: Check cluster status
log_info "Step 3/5: Checking cluster status..."
if ! "$SCRIPT_DIR/cluster-status.sh"; then
    log_warning "Cluster might not be fully ready yet"
    log_info "Waiting for cluster to stabilize..."
    sleep 30
fi

# Step 4: Configure applications
if [[ "$CONFIGURE_APPS" == "true" ]]; then
    log_info "Step 4/5: Configuring applications..."
    # Add PATH for tools in ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"
    if ! "$SCRIPT_DIR/configure-apps.sh"; then
        log_error "Failed to configure applications"
        log_info "You can retry with: ./scripts/k8s/configure-apps.sh"
    fi
else
    log_info "Step 4/5: Skipping application configuration"
fi

# Step 5: Setup HAProxy for standard ports
if [[ "$SETUP_HAPROXY" == "true" ]]; then
    log_info "Step 5/5: Setting up HAProxy for standard ports..."
    if [[ "$SETUP_SECONDARY_IP" == "true" ]]; then
        # Use the HTTPS-enabled HAProxy setup
        if ! "$SCRIPT_DIR/setup-haproxy-https.sh"; then
            log_error "Failed to setup HAProxy with HTTPS"
            log_info "You can retry with: ./scripts/k8s/setup-haproxy-https.sh"
            log_info "Note: Applications will still work on non-standard ports"
        fi
    else
        # Use the standard HTTP-only HAProxy setup
        if ! "$SCRIPT_DIR/setup-haproxy.sh"; then
            log_error "Failed to setup HAProxy"
            log_info "You can retry with: ./scripts/k8s/setup-haproxy.sh"
            log_info "Note: Applications will still work on non-standard ports"
        fi
    fi
else
    log_info "Step 5/5: Skipping HAProxy setup"
    log_warning "Applications will be accessible on non-standard ports:"
    log_warning "  HTTP: port 30080"
    log_warning "  HTTPS: port 30443"
fi

echo
log_info "Kubernetes cluster setup complete!"
echo

# Get master IP
master_ip=$(get_master_ip || echo "pending")

echo "Cluster details:"
echo "==============="
echo "- Name: $CLUSTER_NAME"
echo "- Region: $AWS_REGION"
echo "- Master IP: $master_ip"
echo "- API Server: https://api.$CLUSTER_NAME"
echo

if [[ "$SETUP_HAPROXY" == "true" ]]; then
    if [[ "$SETUP_SECONDARY_IP" == "true" ]]; then
        echo "Access URLs (standard ports with HTTPS):"
        echo "========================================"
        echo "- API: https://api.$CLUSTER_NAME"
        echo "- Apps HTTP: http://<app-name>.$DNS_ZONE"
        echo "- Apps HTTPS: https://<app-name>.$DNS_ZONE"
        echo "- HAProxy Stats: http://$master_ip:8404/stats"
        echo
        echo "Secondary IP configured for full HTTPS support!"
    else
        echo "Access URLs (HTTP on standard port):"
        echo "===================================="
        echo "- API: https://api.$CLUSTER_NAME"
        echo "- Apps HTTP: http://<app-name>.$DNS_ZONE"
        echo "- Apps HTTPS: https://<app-name>.$DNS_ZONE:30443 (non-standard port)"
        echo "- HAProxy Stats: http://$master_ip:8404/stats"
    fi
else
    echo "Access URLs (with port numbers):"
    echo "==============================="
    echo "- API: https://api.$CLUSTER_NAME"
    echo "- Apps HTTP: http://<app-name>.$DNS_ZONE:30080"
    echo "- Apps HTTPS: https://<app-name>.$DNS_ZONE:30443"
fi

echo
echo "Next steps:"
echo "==========="
echo "1. Deploy applications: ./scripts/k8s/deploy-app.sh <app-name>"
echo "2. Check cluster status: ./scripts/k8s/cluster-status.sh"
if [[ "$SETUP_HAPROXY" != "true" ]]; then
    echo "3. Enable standard ports: ./scripts/k8s/setup-haproxy.sh"
fi
echo
echo "Troubleshooting:"
echo "==============="
echo "- DNS issues: ./scripts/k8s/fix-dns.sh --use-ip"
echo "- View logs: kubectl logs -n <namespace> <pod-name>"
echo "- SSH to master: ssh -i $SSH_KEY_PATH ubuntu@$master_ip"