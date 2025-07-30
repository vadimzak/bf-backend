#!/bin/bash
# Install monitoring stack (Prometheus, Grafana, Loki) on Kubernetes cluster

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error trap
set_error_trap

# Configuration
NAMESPACE="monitoring"
KUBE_PROMETHEUS_RELEASE="kube-prometheus-stack"
LOKI_RELEASE="loki"

# Help function
show_help() {
    cat << EOF
Install monitoring stack (Prometheus, Grafana, Loki) on Kubernetes cluster

Usage: $0 [OPTIONS]

Options:
    --dry-run          Show what would be installed without executing
    --uninstall        Remove monitoring stack
    --help             Show this help message

Examples:
    $0                 Install monitoring stack
    $0 --dry-run       Preview installation
    $0 --uninstall     Remove monitoring stack

The script installs:
- Prometheus (metrics collection)
- Grafana (dashboards and visualization)
- AlertManager (alerting)
- Loki (log aggregation)

All services are accessible only internally via port forwarding.
Use scripts/k8s/setup-monitoring-portforward.sh for local access.
EOF
}

# Parse arguments
DRY_RUN=false
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verify prerequisites
log_info "Verifying prerequisites..."
if ! verify_prerequisites; then
    exit 1
fi

# Check if cluster is running
log_info "Checking cluster status..."
if [[ "$(get_cluster_status)" != "running" ]]; then
    log_error "Cluster is not running. Please start it first."
    exit 1
fi

# Uninstall function
uninstall_monitoring() {
    log_info "Uninstalling monitoring stack..."
    
    if $DRY_RUN; then
        log_info "[DRY-RUN] Would uninstall monitoring stack"
        return 0
    fi
    
    # Uninstall Helm releases
    if helm list -n "$NAMESPACE" | grep -q "$KUBE_PROMETHEUS_RELEASE"; then
        log_info "Uninstalling kube-prometheus-stack..."
        helm uninstall "$KUBE_PROMETHEUS_RELEASE" -n "$NAMESPACE"
    fi
    
    if helm list -n "$NAMESPACE" | grep -q "$LOKI_RELEASE"; then
        log_info "Uninstalling Loki..."
        helm uninstall "$LOKI_RELEASE" -n "$NAMESPACE"
    fi
    
    # Delete namespace
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_info "Deleting namespace: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE"
    fi
    
    log_info "Monitoring stack uninstalled successfully"
    return 0
}

# Handle uninstall
if $UNINSTALL; then
    uninstall_monitoring
    exit 0
fi

# Install function
install_monitoring() {
    log_info "Installing monitoring stack..."
    
    if $DRY_RUN; then
        log_info "[DRY-RUN] Would install monitoring stack in namespace: $NAMESPACE"
        log_info "[DRY-RUN] Components: Prometheus, Grafana, AlertManager, Loki"
        return 0
    fi
    
    # Create namespace
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Helm repositories
    log_info "Adding Helm repositories..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Install kube-prometheus-stack
    log_info "Installing kube-prometheus-stack (Prometheus + Grafana + AlertManager)..."
    helm upgrade --install "$KUBE_PROMETHEUS_RELEASE" prometheus-community/kube-prometheus-stack \
        --namespace "$NAMESPACE" \
        --set grafana.adminPassword="admin" \
        --set grafana.service.type="ClusterIP" \
        --set grafana.service.port=80 \
        --set grafana.auth.anonymous.enabled=true \
        --set grafana.auth.anonymous.org_role="Admin" \
        --set grafana.auth.disable_login_form=true \
        --set prometheus.service.type="ClusterIP" \
        --set prometheus.service.port=9090 \
        --set alertmanager.service.type="ClusterIP" \
        --set alertmanager.service.port=9093 \
        --set grafana.persistence.enabled=true \
        --set grafana.persistence.size="10Gi" \
        --set prometheus.prometheusSpec.retention="30d" \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage="20Gi" \
        --wait --timeout=10m
    
    # Install Loki (using loki-stack for simpler deployment)
    # Note: Using loki-stack instead of loki chart due to newer loki chart requiring object storage for scalable mode
    log_info "Installing Loki for log aggregation..."
    helm upgrade --install "$LOKI_RELEASE" grafana/loki-stack \
        --namespace "$NAMESPACE" \
        --set loki.enabled=true \
        --set promtail.enabled=true \
        --set grafana.enabled=false \
        --set prometheus.enabled=false \
        --set loki.persistence.enabled=true \
        --set loki.persistence.size=10Gi \
        --set loki.config.auth_enabled=false \
        --set loki.config.ingester.chunk_idle_period=3m \
        --set loki.config.ingester.chunk_block_size=262144 \
        --set loki.config.ingester.chunk_retain_period=1m \
        --set loki.config.ingester.max_transfer_retries=0 \
        --set loki.config.storage_config.boltdb_shipper.active_index_directory=/data/loki/boltdb-shipper-active \
        --set loki.config.storage_config.boltdb_shipper.cache_location=/data/loki/boltdb-shipper-cache \
        --set loki.config.storage_config.filesystem.directory=/data/loki/chunks \
        --set loki.config.schema_config.configs[0].from=2020-10-24 \
        --set loki.config.schema_config.configs[0].store=boltdb-shipper \
        --set loki.config.schema_config.configs[0].object_store=filesystem \
        --set loki.config.schema_config.configs[0].schema=v11 \
        --set loki.config.schema_config.configs[0].index.prefix=index_ \
        --set loki.config.schema_config.configs[0].index.period=24h \
        --set loki.config.limits_config.reject_old_samples=true \
        --set loki.config.limits_config.reject_old_samples_max_age=168h \
        --wait --timeout=10m
    
    # Wait for pods to be ready
    log_info "Waiting for monitoring components to be ready..."
    wait_for "kubectl get pods -n $NAMESPACE | grep -v Terminating | grep -E '(prometheus|grafana|loki)' | awk '{print \$3}' | grep -v Running | wc -l | grep -q '^0\$'" 300 10
    
    # Configure Loki as data source in Grafana
    log_info "Configuring Loki data source in Grafana..."
    
    # Wait a bit for Grafana to be fully ready
    sleep 30
    
    # Get Grafana pod name
    GRAFANA_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=grafana" -o jsonpath="{.items[0].metadata.name}")
    
    # Configure Loki data source
    kubectl exec -n "$NAMESPACE" "$GRAFANA_POD" -- sh -c '
cat > /tmp/loki-datasource.yaml << EOF
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false
    editable: true
EOF
'
    
    # Copy datasource config (Grafana will auto-reload)
    kubectl exec -n "$NAMESPACE" "$GRAFANA_POD" -- cp /tmp/loki-datasource.yaml /etc/grafana/provisioning/datasources/loki.yaml
    
    # Restart Grafana to pick up the new datasource
    kubectl rollout restart deployment -n "$NAMESPACE" "$KUBE_PROMETHEUS_RELEASE-grafana"
    
    # Wait for Grafana to restart
    kubectl rollout status deployment -n "$NAMESPACE" "$KUBE_PROMETHEUS_RELEASE-grafana" --timeout=300s
    
    log_info "Monitoring stack installed successfully!"
    echo
    log_info "Components installed:"
    log_info "  • Prometheus (metrics): ClusterIP service on port 9090"
    log_info "  • Grafana (dashboards): ClusterIP service on port 80"
    log_info "  • AlertManager (alerts): ClusterIP service on port 9093"
    log_info "  • Loki (logs): ClusterIP service on port 3100"
    echo
    log_info "Access via port forwarding:"
    log_info "  kubectl port-forward -n $NAMESPACE svc/$KUBE_PROMETHEUS_RELEASE-grafana 3000:80"
    log_info "  kubectl port-forward -n $NAMESPACE svc/$KUBE_PROMETHEUS_RELEASE-prometheus 9090:9090"
    log_info "  kubectl port-forward -n $NAMESPACE svc/loki 3100:3100"
    log_info "  kubectl port-forward -n $NAMESPACE svc/$KUBE_PROMETHEUS_RELEASE-alertmanager 9093:9093"
    echo
    log_info "Or use the convenience script:"
    log_info "  ./scripts/k8s/setup-monitoring-portforward.sh"
}

# Main execution
install_monitoring

log_info "Monitoring installation completed!"