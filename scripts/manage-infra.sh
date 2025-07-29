#!/bin/bash
# Script to manage shared infrastructure (nginx, watchtower)
# Usage: ./scripts/manage-infra.sh [start|stop|restart|status|logs]

set -e

# Configuration
REMOTE_USER="ec2-user"
REMOTE_HOST="51.16.33.8"  # Using IP to avoid DNS issues
SSH_KEY="$HOME/.ssh/sample-app-key.pem"
INFRA_DIR="/var/www/sample-app"
COMPOSE_FILE="docker-compose-infra.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check SSH connectivity
check_ssh() {
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "echo 'Connected'" &>/dev/null; then
        log_error "Cannot connect to server via SSH"
        exit 1
    fi
}

# Deploy infrastructure compose file
deploy_compose() {
    log_info "Deploying infrastructure compose file..."
    scp -i "$SSH_KEY" "scripts/docker-compose-infra.yml" "$REMOTE_USER@$REMOTE_HOST:/tmp/" >/dev/null
    ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "sudo cp /tmp/docker-compose-infra.yml $INFRA_DIR/$COMPOSE_FILE"
    log_success "Infrastructure compose file deployed"
}

# Start infrastructure
start_infra() {
    log_info "Starting infrastructure services..."
    deploy_compose
    ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "cd $INFRA_DIR && sudo docker-compose -f $COMPOSE_FILE up -d"
    log_success "Infrastructure services started"
}

# Stop infrastructure
stop_infra() {
    log_info "Stopping infrastructure services..."
    ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "cd $INFRA_DIR && sudo docker-compose -f $COMPOSE_FILE down"
    log_success "Infrastructure services stopped"
}

# Restart infrastructure
restart_infra() {
    log_info "Restarting infrastructure services..."
    ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "cd $INFRA_DIR && sudo docker-compose -f $COMPOSE_FILE restart"
    log_success "Infrastructure services restarted"
}

# Show infrastructure status
show_status() {
    log_info "Infrastructure status:"
    ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "cd $INFRA_DIR && sudo docker-compose -f $COMPOSE_FILE ps"
}

# Show logs
show_logs() {
    SERVICE=$2
    if [ -z "$SERVICE" ]; then
        log_info "Showing all infrastructure logs (last 50 lines):"
        ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "cd $INFRA_DIR && sudo docker-compose -f $COMPOSE_FILE logs --tail 50"
    else
        log_info "Showing $SERVICE logs (last 50 lines):"
        ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "cd $INFRA_DIR && sudo docker-compose -f $COMPOSE_FILE logs --tail 50 $SERVICE"
    fi
}

# Reload nginx configuration
reload_nginx() {
    log_info "Reloading nginx configuration..."
    ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "cd $INFRA_DIR && sudo docker-compose -f $COMPOSE_FILE exec -T nginx nginx -s reload"
    log_success "Nginx configuration reloaded"
}

# Main
ACTION=$1

check_ssh

case "$ACTION" in
    start)
        start_infra
        ;;
    stop)
        stop_infra
        ;;
    restart)
        restart_infra
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$@"
        ;;
    reload-nginx)
        reload_nginx
        ;;
    deploy)
        deploy_compose
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|reload-nginx|deploy}"
        echo ""
        echo "Commands:"
        echo "  start         Start infrastructure services"
        echo "  stop          Stop infrastructure services"
        echo "  restart       Restart infrastructure services"
        echo "  status        Show infrastructure status"
        echo "  logs [service] Show logs (optionally for specific service)"
        echo "  reload-nginx  Reload nginx configuration"
        echo "  deploy        Deploy compose file without starting services"
        echo ""
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 logs nginx"
        echo "  $0 reload-nginx"
        exit 1
        ;;
esac