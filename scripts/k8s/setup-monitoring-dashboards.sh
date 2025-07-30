#!/bin/bash
# Import pre-configured Kubernetes dashboards into Grafana

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Configuration
NAMESPACE="monitoring"
KUBE_PROMETHEUS_RELEASE="kube-prometheus-stack"

# Dashboard IDs from grafana.com (popular Kubernetes dashboards)
declare -A DASHBOARDS=(
    ["kubernetes-cluster-overview"]="7249"
    ["kubernetes-node-exporter"]="1860"
    ["kubernetes-pod-monitoring"]="6417"
    ["kubernetes-cluster-monitoring"]="315"
    ["kubernetes-resource-requests"]="13332"
    ["kubernetes-persistent-volumes"]="13646"
    ["node-exporter-full"]="12486"
    ["loki-logs-dashboard"]="13639"
)

# Help function
show_help() {
    cat << EOF
Import pre-configured Kubernetes dashboards into Grafana

Usage: $0 [OPTIONS] [DASHBOARD]

Dashboards:
    kubernetes-cluster-overview    Kubernetes Cluster Overview (ID: 7249)
    kubernetes-node-exporter       Node Exporter Full (ID: 1860)
    kubernetes-pod-monitoring      Kubernetes Pod Monitoring (ID: 6417)
    kubernetes-cluster-monitoring  Kubernetes Cluster Monitoring (ID: 315)
    kubernetes-resource-requests   Kubernetes Resource Requests (ID: 13332)
    kubernetes-persistent-volumes  Kubernetes Persistent Volumes (ID: 13646)
    node-exporter-full            Node Exporter Full (ID: 12486)
    loki-logs-dashboard           Loki Logs Dashboard (ID: 13639)
    all                           Import all dashboards (default)

Options:
    --dry-run          Show what would be imported without executing
    --list             List available dashboards
    --grafana-port PORT Port for Grafana access (default: 3000)
    --help             Show this help message

Examples:
    $0                               Import all dashboards
    $0 kubernetes-cluster-overview   Import specific dashboard
    $0 --list                        Show available dashboards
    $0 --dry-run                     Preview what would be imported

Note: Grafana must be accessible (use setup-monitoring-portforward.sh first)
EOF
}

# Parse arguments
DASHBOARD="all"
DRY_RUN=false
LIST=false
GRAFANA_PORT="3000"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --list)
            LIST=true
            shift
            ;;
        --grafana-port)
            GRAFANA_PORT="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        kubernetes-cluster-overview|kubernetes-node-exporter|kubernetes-pod-monitoring|kubernetes-cluster-monitoring|kubernetes-resource-requests|kubernetes-persistent-volumes|node-exporter-full|loki-logs-dashboard|all)
            DASHBOARD="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# List dashboards function
list_dashboards() {
    log_info "Available Kubernetes dashboards:"
    echo
    for name in "${!DASHBOARDS[@]}"; do
        echo "  $name (ID: ${DASHBOARDS[$name]})"
    done | sort
    echo
    log_info "Use '$0 [dashboard-name]' to import a specific dashboard"
    log_info "Use '$0 all' to import all dashboards"
}

# Check if Grafana is accessible
check_grafana_access() {
    if ! curl -s "http://localhost:$GRAFANA_PORT/api/health" >/dev/null 2>&1; then
        log_error "Cannot access Grafana at http://localhost:$GRAFANA_PORT"
        log_error "Please ensure port forwarding is active:"
        log_error "  ./scripts/k8s/setup-monitoring-portforward.sh grafana"
        exit 1
    fi
}

# Download and import dashboard
import_dashboard() {
    local name="$1"
    local dashboard_id="$2"
    
    if $DRY_RUN; then
        log_info "[DRY-RUN] Would import dashboard: $name (ID: $dashboard_id)"
        return 0
    fi
    
    log_info "Importing dashboard: $name (ID: $dashboard_id)"
    
    # Create temp directory
    local temp_dir
    temp_dir=$(mktemp -d)
    local dashboard_file="$temp_dir/dashboard.json"
    
    # Download dashboard JSON from grafana.com
    if ! curl -s "https://grafana.com/api/dashboards/$dashboard_id/revisions/latest/download" -o "$dashboard_file"; then
        log_error "Failed to download dashboard $name (ID: $dashboard_id)"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Check if download was successful and file is valid JSON
    if ! jq . "$dashboard_file" >/dev/null 2>&1; then
        log_error "Downloaded dashboard is not valid JSON: $name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Prepare dashboard for import (remove id and uid, set title)
    local import_payload
    import_payload=$(jq --arg title "$name" '{
        dashboard: (. | del(.id, .uid) | .title = $title),
        overwrite: true,
        inputs: []
    }' "$dashboard_file")
    
    # Import dashboard via Grafana API
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$import_payload" \
        "http://localhost:$GRAFANA_PORT/api/dashboards/import")
    
    # Check response
    if echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        local dashboard_url
        dashboard_url=$(echo "$response" | jq -r '.url')
        log_info "✓ Dashboard imported: $name"
        log_info "  URL: http://localhost:$GRAFANA_PORT$dashboard_url"
    else
        log_error "Failed to import dashboard: $name"
        log_error "Response: $response"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    return 0
}

# Import specific dashboards
import_dashboards() {
    local failed=0
    
    if [[ "$DASHBOARD" == "all" ]]; then
        log_info "Importing all Kubernetes dashboards..."
        for name in "${!DASHBOARDS[@]}"; do
            import_dashboard "$name" "${DASHBOARDS[$name]}" || ((failed++))
            sleep 1  # Small delay between imports
        done
    else
        if [[ -n "${DASHBOARDS[$DASHBOARD]:-}" ]]; then
            import_dashboard "$DASHBOARD" "${DASHBOARDS[$DASHBOARD]}" || ((failed++))
        else
            log_error "Unknown dashboard: $DASHBOARD"
            log_error "Use --list to see available dashboards"
            exit 1
        fi
    fi
    
    echo
    if [[ $failed -eq 0 ]]; then
        log_info "All dashboards imported successfully!"
    else
        log_warning "$failed dashboard(s) failed to import"
    fi
    
    echo
    log_info "Access Grafana at: http://localhost:$GRAFANA_PORT"
    log_info "Navigate to 'Dashboards' to view imported dashboards"
}

# Verify prerequisites
verify_dashboard_prerequisites() {
    # Check if jq is available
    if ! command_exists jq; then
        log_error "jq is required for dashboard import"
        log_error "Install with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
        exit 1
    fi
    
    # Check if curl is available
    if ! command_exists curl; then
        log_error "curl is required for dashboard import"
        exit 1
    fi
    
    # Check if cluster is running
    if [[ "$(get_cluster_status)" != "running" ]]; then
        log_error "Cluster is not running. Please start it first."
        exit 1
    fi
    
    # Check if monitoring namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Monitoring namespace '$NAMESPACE' does not exist."
        log_error "Please install monitoring stack first: ./scripts/k8s/install-monitoring.sh"
        exit 1
    fi
}

# Main execution
if $LIST; then
    list_dashboards
    exit 0
fi

if $DRY_RUN; then
    log_info "Dry run mode - showing what would be imported"
fi

# Verify prerequisites
verify_dashboard_prerequisites

# Check Grafana access (skip in dry run)
if ! $DRY_RUN; then
    check_grafana_access
fi

# Import dashboards
import_dashboards

log_info "Dashboard import completed!"