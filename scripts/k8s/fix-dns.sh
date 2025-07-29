#!/bin/bash
set -euo pipefail

# Script to handle DNS resolution issues with kubectl
# This is a common issue when DNS hasn't propagated yet

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Script options
USE_IP=false
RESTORE_DNS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --use-ip)
            USE_IP=true
            shift
            ;;
        --restore-dns)
            RESTORE_DNS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --use-ip      Configure kubectl to use direct IP instead of DNS"
            echo "  --restore-dns Configure kubectl to use DNS (default)"
            echo "  --help        Show this help message"
            echo
            echo "This script helps when you get 'no such host' errors with kubectl"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "$USE_IP" == "true" ]]; then
    log_info "Getting master node IP..."
    master_ip=$(get_master_ip)
    
    if [[ -z "$master_ip" ]]; then
        log_error "Could not get master node IP"
        exit 1
    fi
    
    log_info "Configuring kubectl to use IP: $master_ip"
    kubectl config set-cluster "$CLUSTER_NAME" --server="https://$master_ip" --insecure-skip-tls-verify=true
    
    log_info "Testing connection..."
    if kubectl get nodes >/dev/null 2>&1; then
        log_info "Success! You can now use kubectl commands."
        log_warning "Note: TLS verification is disabled. This is only for temporary use."
    else
        log_error "Failed to connect to cluster"
        exit 1
    fi
elif [[ "$RESTORE_DNS" == "true" ]]; then
    log_info "Restoring DNS-based access..."
    kubectl config set-cluster "$CLUSTER_NAME" --server="https://api.$CLUSTER_NAME"
    kubectl config unset clusters."$CLUSTER_NAME".insecure-skip-tls-verify
    
    log_info "Testing connection..."
    if kubectl get nodes >/dev/null 2>&1; then
        log_info "Success! DNS-based access restored."
    else
        log_warning "DNS might not have propagated yet. You can use --use-ip temporarily."
    fi
else
    # Default: check current status
    log_info "Checking cluster connectivity..."
    
    if kubectl get nodes >/dev/null 2>&1; then
        log_info "Cluster is accessible!"
    else
        log_error "Cannot connect to cluster"
        log_info "Try: $0 --use-ip"
    fi
fi