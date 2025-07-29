#!/bin/bash
# Setup automatic recovery for Docker applications after instance reboot
# This script installs a systemd service that ensures all apps restart after spot interruptions

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/deploy-common.sh"

# Configuration
SERVICE_NAME="docker-apps-recovery"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
RECOVERY_DIR="/etc/docker-apps-recovery"
APPS_CONFIG="${RECOVERY_DIR}/apps.conf"
RECOVERY_SCRIPT="${RECOVERY_DIR}/recovery.sh"
LOG_FILE="/var/log/${SERVICE_NAME}.log"

# Parse command line arguments
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
            cat << EOF
Usage: $0 [options]

Setup automatic recovery for Docker applications after EC2 instance reboot.

Options:
    --dry-run     Show what would be done without making changes
    --uninstall   Remove the auto-recovery service
    --help        Show this help message

Examples:
    # Install auto-recovery
    $0

    # Test what would be installed
    $0 --dry-run

    # Remove auto-recovery
    $0 --uninstall

EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to get all currently deployed apps
get_deployed_apps() {
    log_info "Discovering deployed applications..."
    
    # Connect to server and find all apps
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@51.16.33.8" << 'EOF'
# Find all directories in /var/www that have docker-compose.prod.yml
for dir in /var/www/*/; do
    if [[ -f "${dir}docker-compose.prod.yml" ]]; then
        app_name=$(basename "$dir")
        # Skip infrastructure directory
        if [[ "$app_name" != "sample-app" ]] || [[ -f "${dir}apps.json" ]]; then
            continue
        fi
        
        # Get port and domain from running container or compose file
        port=$(sudo docker-compose -f "${dir}docker-compose.prod.yml" ps -q | head -1 | xargs sudo docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{(index $conf 0).HostPort}}{{end}}{{end}}' 2>/dev/null | grep -o '[0-9]*' | head -1)
        
        # If no running container, extract from compose file
        if [[ -z "$port" ]]; then
            port=$(grep -E "^\s*-\s*\"[0-9]+:" "${dir}docker-compose.prod.yml" | head -1 | sed 's/.*"\([0-9]*\):.*/\1/')
        fi
        
        # Construct domain (could be extracted from nginx config if needed)
        domain="${app_name}.vadimzak.com"
        
        echo "${app_name}|${dir}|docker-compose.prod.yml|https://${domain}/health|${port}"
    fi
done
EOF
}

# Function to create recovery script
create_recovery_script() {
    cat << 'EOF'
#!/bin/bash
# Docker Apps Recovery Script
# This script is called by systemd to recover all Docker applications

LOG_FILE="/var/log/docker-apps-recovery.log"
APPS_CONFIG="/etc/docker-apps-recovery/apps.conf"
MAX_RETRIES=30
RETRY_DELAY=2

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" | tee -a "$LOG_FILE"
}

# Wait for Docker daemon
wait_for_docker() {
    log "Waiting for Docker daemon to be ready..."
    
    for i in $(seq 1 $MAX_RETRIES); do
        if docker info >/dev/null 2>&1; then
            log_success "Docker daemon is ready"
            return 0
        fi
        log "Docker not ready, retry $i/$MAX_RETRIES..."
        sleep $RETRY_DELAY
    done
    
    log_error "Docker daemon failed to start after $MAX_RETRIES attempts"
    return 1
}

# Ensure shared network exists
ensure_shared_network() {
    log "Checking shared Docker network..."
    
    if ! docker network inspect sample-app_app-network >/dev/null 2>&1; then
        log "Creating shared network: sample-app_app-network"
        docker network create sample-app_app-network
    else
        log "Shared network already exists"
    fi
}

# Start infrastructure services
start_infrastructure() {
    log "Starting infrastructure services..."
    
    INFRA_DIR="/var/www/sample-app"
    if [[ -d "$INFRA_DIR" ]] && [[ -f "$INFRA_DIR/docker-compose-infra.yml" ]]; then
        cd "$INFRA_DIR"
        log "Starting nginx and watchtower..."
        docker-compose -f docker-compose-infra.yml up -d
        
        # Wait for nginx to be ready
        sleep 10
        
        if docker ps | grep -q "nginx.*Up"; then
            log_success "Infrastructure services started successfully"
        else
            log_error "Infrastructure services failed to start properly"
            return 1
        fi
    else
        log_error "Infrastructure directory not found at $INFRA_DIR"
        return 1
    fi
    
    return 0
}

# Start individual application
start_application() {
    local app_name="$1"
    local app_dir="$2"
    local compose_file="$3"
    local health_url="$4"
    
    log "Starting application: $app_name"
    
    if [[ ! -d "$app_dir" ]]; then
        log_error "Application directory not found: $app_dir"
        return 1
    fi
    
    cd "$app_dir"
    
    # Start the application
    if docker-compose -f "$compose_file" up -d; then
        log "Application $app_name started, checking health..."
        
        # Wait for application to be healthy
        local health_retries=10
        for i in $(seq 1 $health_retries); do
            if curl -s --max-time 5 "$health_url" | grep -q "healthy"; then
                log_success "Application $app_name is healthy"
                return 0
            fi
            log "Health check attempt $i/$health_retries for $app_name..."
            sleep 3
        done
        
        log_error "Application $app_name failed health check"
        return 1
    else
        log_error "Failed to start application $app_name"
        return 1
    fi
}

# Main recovery process
main() {
    log "========================================="
    log "Starting Docker Apps Recovery Process"
    log "========================================="
    
    # Wait for Docker
    if ! wait_for_docker; then
        exit 1
    fi
    
    # Ensure shared network
    ensure_shared_network
    
    # Start infrastructure first
    if ! start_infrastructure; then
        log_error "Infrastructure startup failed, continuing anyway..."
    fi
    
    # Start all registered applications
    if [[ -f "$APPS_CONFIG" ]]; then
        log "Reading applications from $APPS_CONFIG"
        
        while IFS='|' read -r app_name app_dir compose_file health_url port; do
            # Skip empty lines and comments
            [[ -z "$app_name" ]] && continue
            [[ "$app_name" =~ ^#.*$ ]] && continue
            
            start_application "$app_name" "$app_dir" "$compose_file" "$health_url"
        done < "$APPS_CONFIG"
    else
        log_error "No applications config found at $APPS_CONFIG"
    fi
    
    log "========================================="
    log "Recovery process completed"
    log "========================================="
}

# Run main function
main
EOF
}

# Function to create systemd service
create_systemd_service() {
    cat << EOF
[Unit]
Description=Docker Apps Auto Recovery Service
Documentation=https://github.com/yourusername/yourrepo
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${RECOVERY_SCRIPT}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# Security settings
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
}

# Uninstall function
uninstall_recovery() {
    log_warning "Uninstalling Docker Apps Recovery Service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would remove the following:"
        echo "  - Systemd service: $SERVICE_FILE"
        echo "  - Recovery directory: $RECOVERY_DIR"
        echo "  - Log file: $LOG_FILE"
        return
    fi
    
    # Execute on remote server
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@51.16.33.8" << EOF
# Stop and disable service
sudo systemctl stop ${SERVICE_NAME} 2>/dev/null || true
sudo systemctl disable ${SERVICE_NAME} 2>/dev/null || true

# Remove files
sudo rm -f ${SERVICE_FILE}
sudo rm -rf ${RECOVERY_DIR}
sudo rm -f ${LOG_FILE}

# Reload systemd
sudo systemctl daemon-reload

echo "Auto-recovery service has been removed"
EOF
    
    log_success "Auto-recovery uninstalled successfully"
}

# Main installation logic
if [[ "$UNINSTALL" == "true" ]]; then
    uninstall_recovery
    exit 0
fi

log_info "Setting up Docker Apps Auto-Recovery Service..."

# Get deployed apps
DEPLOYED_APPS=$(get_deployed_apps)

if [[ -z "$DEPLOYED_APPS" ]]; then
    log_warning "No deployed applications found"
else
    log_success "Found deployed applications:"
    echo "$DEPLOYED_APPS" | while IFS='|' read -r app_name app_dir compose_file health_url port; do
        echo "  - $app_name (port: $port)"
    done
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN MODE - Showing what would be installed:"
    echo
    echo "1. Recovery script would be created at: ${RECOVERY_SCRIPT}"
    echo "2. Systemd service would be created at: ${SERVICE_FILE}"
    echo "3. Apps configuration would be saved to: ${APPS_CONFIG}"
    echo "4. The following apps would be registered:"
    echo "$DEPLOYED_APPS" | while IFS='|' read -r app_name app_dir compose_file health_url port; do
        echo "   - $app_name"
    done
    echo
    echo "5. Service would start automatically on boot"
    echo "6. Logs would be written to: ${LOG_FILE}"
    exit 0
fi

# Create recovery script content
RECOVERY_SCRIPT_CONTENT=$(create_recovery_script)
SYSTEMD_SERVICE_CONTENT=$(create_systemd_service)

# Install on remote server
log_info "Installing auto-recovery service on EC2 instance..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@51.16.33.8" << EOF
set -e

# Create recovery directory
sudo mkdir -p ${RECOVERY_DIR}

# Create recovery script
echo '${RECOVERY_SCRIPT_CONTENT}' | sudo tee ${RECOVERY_SCRIPT} > /dev/null
sudo chmod +x ${RECOVERY_SCRIPT}

# Create apps configuration
echo '# Docker Apps Recovery Configuration' | sudo tee ${APPS_CONFIG} > /dev/null
echo '# Format: app_name|app_dir|compose_file|health_url|port' | sudo tee -a ${APPS_CONFIG} > /dev/null
echo '${DEPLOYED_APPS}' | sudo tee -a ${APPS_CONFIG} > /dev/null

# Create systemd service
echo '${SYSTEMD_SERVICE_CONTENT}' | sudo tee ${SERVICE_FILE} > /dev/null

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}

echo "Auto-recovery service installed successfully"
EOF

log_success "Auto-recovery service has been installed and enabled"
log_info "The service will automatically start all Docker applications after system reboot"
log_info "To check recovery status, use: ./scripts/check-recovery-status.sh"