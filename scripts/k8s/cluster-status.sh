#!/bin/bash
set -euo pipefail

# Quick cluster status check script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

echo "==================================="
echo "Kubernetes Cluster Status"
echo "==================================="
echo

# Check if we can connect
if ! kubectl get nodes >/dev/null 2>&1; then
    log_warning "Cannot connect to cluster via DNS"
    log_info "Trying with direct IP..."
    
    master_ip=$(get_master_ip)
    if [[ -n "$master_ip" ]]; then
        kubectl config set-cluster "$CLUSTER_NAME" --server="https://$master_ip" --insecure-skip-tls-verify=true >/dev/null 2>&1
        
        if ! kubectl get nodes >/dev/null 2>&1; then
            log_error "Cannot connect to cluster"
            log_info "Run ./scripts/k8s/fix-dns.sh --use-ip"
            exit 1
        fi
        
        # Restore DNS for next time
        kubectl config set-cluster "$CLUSTER_NAME" --server="https://api.$CLUSTER_NAME" >/dev/null 2>&1
    fi
fi

# Basic Info
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "State Store: $KOPS_STATE_STORE"
echo

# Node Status
echo "Nodes:"
kubectl get nodes
echo

# System Pods
echo "System Pods Status:"
kubectl get pods -n kube-system --no-headers | awk '{print $1, $3}' | column -t
echo

# Ingress Status
echo "Ingress Controller:"
kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | awk '{print $1, $3}' | column -t || echo "Not installed"
echo

# Cert Manager Status
echo "Cert Manager:"
kubectl get pods -n cert-manager --no-headers 2>/dev/null | awk '{print $1, $3}' | column -t || echo "Not installed"
echo

# Application Namespaces
echo "Application Pods:"
kubectl get pods -n apps --no-headers 2>/dev/null | awk '{print $1, $3}' | column -t || echo "No applications deployed"
echo

# Cluster Info
master_ip=$(get_master_ip)
echo "Master Node IP: $master_ip"
echo "API Server: https://api.$CLUSTER_NAME"
echo

# Access Info
echo "Access Commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods --all-namespaces"
echo "  ssh -i $SSH_KEY_PATH ubuntu@$master_ip"
echo

# Check for issues
issues=0

# Check for pending pods
pending_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
if [[ $pending_pods -gt 0 ]]; then
    log_warning "Found $pending_pods pending pod(s)"
    kubectl get pods --all-namespaces --field-selector=status.phase=Pending
    issues=$((issues + 1))
fi

# Check for failed pods
failed_pods=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | wc -l || true)
if [[ $failed_pods -gt 0 ]]; then
    log_warning "Found $failed_pods failed pod(s)"
    kubectl get pods --all-namespaces --no-headers | grep -E "Error|CrashLoopBackOff|ImagePullBackOff"
    issues=$((issues + 1))
fi

if [[ $issues -eq 0 ]]; then
    log_info "Cluster is healthy!"
else
    log_warning "Found $issues issue(s) that need attention"
fi