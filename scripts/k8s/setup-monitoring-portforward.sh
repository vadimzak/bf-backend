#!/bin/bash
# Setup port forwarding for monitoring services (Grafana, Prometheus, Loki, AlertManager)

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Configuration
NAMESPACE="monitoring"
KUBE_PROMETHEUS_RELEASE="kube-prometheus-stack"
LOKI_RELEASE="loki"

# Port mappings
GRAFANA_PORT="3000"
PROMETHEUS_PORT="9090"
LOKI_PORT="3100"
ALERTMANAGER_PORT="9093"

# Help function
show_help() {
    cat << EOF
Setup port forwarding for monitoring services

Usage: $0 [OPTIONS] [SERVICE]

Services:
    grafana        Forward Grafana dashboard (default: localhost:3000)
    prometheus     Forward Prometheus UI (default: localhost:9090)
    loki           Forward Loki API (default: localhost:3100)
    alertmanager   Forward AlertManager UI (default: localhost:9093)
    all            Forward all services (default)

Options:
    --grafana-port PORT     Custom port for Grafana (default: 3000)
    --prometheus-port PORT  Custom port for Prometheus (default: 9090)
    --loki-port PORT        Custom port for Loki (default: 3100)
    --alertmanager-port PORT Custom port for AlertManager (default: 9093)
    --stop                  Stop all port forwarding processes
    --status                Show status of forwarded ports
    --help                  Show this help message

Examples:
    $0                      Forward all services on default ports
    $0 grafana              Forward only Grafana
    $0 --grafana-port 8080  Forward Grafana on port 8080
    $0 --stop               Stop all port forwarding
    $0 --status             Check forwarding status

Access URLs:
    Grafana:      http://localhost:3000 (dashboards and visualization)
    Prometheus:   http://localhost:9090 (metrics and queries)
    Loki:         http://localhost:3100 (log queries)
    AlertManager: http://localhost:9093 (alert management)
EOF
}

# Parse arguments
SERVICE="all"
STOP=false
STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --grafana-port)
            GRAFANA_PORT="$2"
            shift 2
            ;;
        --prometheus-port)
            PROMETHEUS_PORT="$2"
            shift 2
            ;;
        --loki-port)
            LOKI_PORT="$2"
            shift 2
            ;;
        --alertmanager-port)
            ALERTMANAGER_PORT="$2"
            shift 2
            ;;
        --stop)
            STOP=true
            shift
            ;;
        --status)
            STATUS=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        grafana|prometheus|loki|alertmanager|all)
            SERVICE="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Function to check if port is in use
is_port_in_use() {
    local port="$1"
    lsof -i ":$port" >/dev/null 2>&1
}

# Function to find kubectl port-forward processes
find_kubectl_processes() {
    ps aux | grep "kubectl.*port-forward" | grep -v grep | awk '{print $2}' || true
}

# Function to stop port forwarding
stop_port_forwarding() {
    log_info "Stopping all kubectl port-forward processes..."
    
    local pids
    pids=$(find_kubectl_processes)
    
    if [[ -z "$pids" ]]; then
        log_info "No kubectl port-forward processes found"
        return 0
    fi
    
    echo "$pids" | while read -r pid; do
        if [[ -n "$pid" ]]; then
            log_info "Stopping process $pid"
            kill "$pid" 2>/dev/null || true
        fi
    done
    
    # Wait a moment for processes to terminate
    sleep 2
    
    # Check if any are still running
    local remaining
    remaining=$(find_kubectl_processes)
    if [[ -n "$remaining" ]]; then
        log_warning "Some processes still running, force killing..."
        echo "$remaining" | while read -r pid; do
            if [[ -n "$pid" ]]; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    log_info "Port forwarding stopped"
}

# Function to show status
show_status() {
    log_info "Port forwarding status:"
    echo
    
    local pids
    pids=$(find_kubectl_processes)
    
    if [[ -z "$pids" ]]; then
        log_info "No kubectl port-forward processes running"
        return 0
    fi
    
    echo "Active port-forward processes:"
    ps aux | grep "kubectl.*port-forward" | grep -v grep | while read -r line; do
        echo "  $line"
    done
    echo
    
    # Check specific ports
    local services=("grafana:$GRAFANA_PORT" "prometheus:$PROMETHEUS_PORT" "loki:$LOKI_PORT" "alertmanager:$ALERTMANAGER_PORT")
    
    for service_port in "${services[@]}"; do
        local service="${service_port%:*}"
        local port="${service_port#*:}"
        
        if is_port_in_use "$port"; then
            log_info "✓ $service: http://localhost:$port"
        else
            log_info "✗ $service: port $port not forwarded"
        fi
    done
}

# Function to start port forwarding for a service
start_port_forward() {
    local service="$1"
    local local_port="$2"
    local service_name="$3"
    local service_port="$4"
    
    if is_port_in_use "$local_port"; then
        log_warning "$service port $local_port is already in use"
        return 1
    fi
    
    log_info "Starting port forward for $service: localhost:$local_port -> $service_name:$service_port"
    
    kubectl port-forward -n "$NAMESPACE" "svc/$service_name" "$local_port:$service_port" >/dev/null 2>&1 &
    local pid=$!
    
    # Wait a moment and check if the process is still running
    sleep 2
    if ! kill -0 "$pid" 2>/dev/null; then
        log_error "Failed to start port forwarding for $service"
        return 1
    fi
    
    log_info "✓ $service available at: http://localhost:$local_port"
    return 0
}

# Function to setup port forwarding
setup_port_forwarding() {
    log_info "Setting up port forwarding for monitoring services..."
    
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
    
    # Check if services exist
    local services_exist=true
    
    if [[ "$SERVICE" == "all" || "$SERVICE" == "grafana" ]]; then
        if ! kubectl get svc -n "$NAMESPACE" "$KUBE_PROMETHEUS_RELEASE-grafana" >/dev/null 2>&1; then
            log_error "Grafana service not found"
            services_exist=false
        fi
    fi
    
    if [[ "$SERVICE" == "all" || "$SERVICE" == "prometheus" ]]; then
        if ! kubectl get svc -n "$NAMESPACE" "$KUBE_PROMETHEUS_RELEASE-prometheus" >/dev/null 2>&1; then
            log_error "Prometheus service not found"
            services_exist=false
        fi
    fi
    
    if [[ "$SERVICE" == "all" || "$SERVICE" == "loki" ]]; then
        if ! kubectl get svc -n "$NAMESPACE" "$LOKI_RELEASE" >/dev/null 2>&1; then
            log_error "Loki service not found"
            services_exist=false
        fi
    fi
    
    if [[ "$SERVICE" == "all" || "$SERVICE" == "alertmanager" ]]; then
        if ! kubectl get svc -n "$NAMESPACE" "$KUBE_PROMETHEUS_RELEASE-alertmanager" >/dev/null 2>&1; then
            log_error "AlertManager service not found"
            services_exist=false
        fi
    fi
    
    if [[ "$services_exist" == "false" ]]; then
        log_error "Some monitoring services are missing. Please check your installation."
        exit 1
    fi
    
    # Start port forwarding based on service selection
    local failed=0
    
    case "$SERVICE" in
        "grafana")
            start_port_forward "Grafana" "$GRAFANA_PORT" "$KUBE_PROMETHEUS_RELEASE-grafana" "80" || ((failed++))
            ;;
        "prometheus")
            start_port_forward "Prometheus" "$PROMETHEUS_PORT" "$KUBE_PROMETHEUS_RELEASE-prometheus" "9090" || ((failed++))
            ;;
        "loki")
            start_port_forward "Loki" "$LOKI_PORT" "$LOKI_RELEASE" "3100" || ((failed++))
            ;;
        "alertmanager")
            start_port_forward "AlertManager" "$ALERTMANAGER_PORT" "$KUBE_PROMETHEUS_RELEASE-alertmanager" "9093" || ((failed++))
            ;;
        "all")
            start_port_forward "Grafana" "$GRAFANA_PORT" "$KUBE_PROMETHEUS_RELEASE-grafana" "80" || ((failed++))
            start_port_forward "Prometheus" "$PROMETHEUS_PORT" "$KUBE_PROMETHEUS_RELEASE-prometheus" "9090" || ((failed++))
            start_port_forward "Loki" "$LOKI_PORT" "$LOKI_RELEASE" "3100" || ((failed++))
            start_port_forward "AlertManager" "$ALERTMANAGER_PORT" "$KUBE_PROMETHEUS_RELEASE-alertmanager" "9093" || ((failed++))
            ;;
    esac
    
    if [[ $failed -gt 0 ]]; then
        log_warning "$failed service(s) failed to start port forwarding"
    fi
    
    echo
    log_info "Port forwarding setup complete!"
    echo
    log_info "Available services:"
    if [[ "$SERVICE" == "all" || "$SERVICE" == "grafana" ]]; then
        log_info "  📊 Grafana (Dashboards):  http://localhost:$GRAFANA_PORT"
    fi
    if [[ "$SERVICE" == "all" || "$SERVICE" == "prometheus" ]]; then
        log_info "  📈 Prometheus (Metrics):   http://localhost:$PROMETHEUS_PORT"
    fi
    if [[ "$SERVICE" == "all" || "$SERVICE" == "loki" ]]; then
        log_info "  📋 Loki (Logs):           http://localhost:$LOKI_PORT"
    fi
    if [[ "$SERVICE" == "all" || "$SERVICE" == "alertmanager" ]]; then
        log_info "  🚨 AlertManager (Alerts): http://localhost:$ALERTMANAGER_PORT"
    fi
    echo
    log_info "To stop port forwarding: $0 --stop"
    log_info "To check status: $0 --status"
    echo
    log_info "Press Ctrl+C to stop all port forwarding"
    
    # Keep the script running if forwarding all services
    if [[ "$SERVICE" == "all" ]]; then
        # Wait for interrupt signal
        trap 'stop_port_forwarding; exit 0' SIGINT SIGTERM
        
        log_info "Monitoring for process termination..."
        while true; do
            sleep 5
            # Check if any processes died
            local current_pids
            current_pids=$(find_kubectl_processes)
            if [[ -z "$current_pids" ]]; then
                log_warning "All port forwarding processes stopped"
                break
            fi
        done
    fi
}

# Main execution
if $STOP; then
    stop_port_forwarding
elif $STATUS; then
    show_status
else
    setup_port_forwarding
fi