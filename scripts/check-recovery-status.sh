#!/bin/bash
# Check the status of the Docker Apps Auto-Recovery Service
# This script provides detailed information about the recovery system

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/deploy-common.sh"

# Configuration
SERVICE_NAME="docker-apps-recovery"
RECOVERY_DIR="/etc/docker-apps-recovery"
APPS_CONFIG="${RECOVERY_DIR}/apps.conf"
LOG_FILE="/var/log/${SERVICE_NAME}.log"

# Parse command line arguments
SHOW_LOGS=false
LOG_LINES=20

while [[ $# -gt 0 ]]; do
    case $1 in
        --logs|-l)
            SHOW_LOGS=true
            shift
            if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                LOG_LINES=$1
                shift
            fi
            ;;
        --help)
            cat << EOF
Usage: $0 [options]

Check the status of the Docker Apps Auto-Recovery Service.

Options:
    --logs, -l [N]    Show last N lines of recovery log (default: 20)
    --help            Show this help message

Examples:
    # Check basic status
    $0

    # Show status with last 20 log lines
    $0 --logs

    # Show status with last 50 log lines
    $0 --logs 50

EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Checking Docker Apps Auto-Recovery Status..."
echo

# Connect to server and check status
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@51.16.33.8" << EOF
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Recovery Service Status ==="
echo

# Check if service exists
if ! systemctl list-unit-files | grep -q "${SERVICE_NAME}"; then
    echo -e "${RED}❌ Recovery service is NOT installed${NC}"
    echo
    echo "To install, run: ./scripts/setup-auto-recovery.sh"
    exit 1
fi

# Check service status
echo "Service Information:"
if systemctl is-enabled ${SERVICE_NAME} &>/dev/null; then
    echo -e "  Status: ${GREEN}✅ Enabled (will run on boot)${NC}"
else
    echo -e "  Status: ${YELLOW}⚠️  Disabled${NC}"
fi

# Get last run time
LAST_RUN=\$(systemctl show -p ExecMainStartTimestamp ${SERVICE_NAME} | cut -d= -f2)
if [[ -n "\$LAST_RUN" ]] && [[ "\$LAST_RUN" != "n/a" ]]; then
    echo "  Last Run: \$LAST_RUN"
else
    echo "  Last Run: Never"
fi

# Check if currently active
if systemctl is-active ${SERVICE_NAME} &>/dev/null; then
    echo -e "  Current State: ${GREEN}Active${NC}"
else
    echo -e "  Current State: ${YELLOW}Inactive${NC}"
fi

echo
echo "=== Registered Applications ==="
echo

if [[ -f "${APPS_CONFIG}" ]]; then
    APP_COUNT=\$(grep -v "^#" "${APPS_CONFIG}" | grep -v "^$" | wc -l)
    echo "Total registered apps: \$APP_COUNT"
    echo
    
    if [[ \$APP_COUNT -gt 0 ]]; then
        echo "Applications configured for auto-recovery:"
        grep -v "^#" "${APPS_CONFIG}" | while IFS='|' read -r app_name app_dir compose_file health_url port; do
            [[ -z "\$app_name" ]] && continue
            echo "  • \$app_name"
            echo "    Port: \$port"
            echo "    Directory: \$app_dir"
            echo "    Health: \$health_url"
            
            # Check if app is currently running
            if sudo docker ps | grep -q "\$app_name"; then
                echo -e "    Status: ${GREEN}Running${NC}"
            else
                echo -e "    Status: ${RED}Not Running${NC}"
            fi
            echo
        done
    else
        echo "No applications registered for auto-recovery"
    fi
else
    echo -e "${YELLOW}Recovery configuration file not found${NC}"
    echo "Run setup-auto-recovery.sh to configure"
fi

echo "=== System Information ==="
echo

# Check Docker status
echo -n "Docker Status: "
if systemctl is-active docker &>/dev/null; then
    echo -e "${GREEN}Running${NC}"
else
    echo -e "${RED}Not Running${NC}"
fi

# Check uptime
echo "System Uptime: \$(uptime -p)"

# Show next scheduled maintenance
echo
echo "=== Recovery Readiness ==="
echo

# Test recovery script
if [[ -x "${RECOVERY_DIR}/recovery.sh" ]]; then
    echo -e "Recovery Script: ${GREEN}✅ Present and executable${NC}"
else
    echo -e "Recovery Script: ${RED}❌ Missing or not executable${NC}"
fi

# Test log file
if [[ -f "${LOG_FILE}" ]]; then
    echo -e "Log File: ${GREEN}✅ Present${NC}"
    LOG_SIZE=\$(du -h "${LOG_FILE}" | cut -f1)
    echo "  Size: \$LOG_SIZE"
else
    echo -e "Log File: ${YELLOW}⚠️  Not yet created${NC}"
fi

# Check shared network
if sudo docker network inspect sample-app_app-network &>/dev/null; then
    echo -e "Shared Network: ${GREEN}✅ Exists${NC}"
else
    echo -e "Shared Network: ${YELLOW}⚠️  Missing (will be created on recovery)${NC}"
fi

EOF

# Show logs if requested
if [[ "$SHOW_LOGS" == "true" ]]; then
    echo
    echo "=== Recent Recovery Logs (last $LOG_LINES lines) ==="
    echo
    
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@51.16.33.8" "test -f $LOG_FILE"; then
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@51.16.33.8" "sudo tail -n $LOG_LINES $LOG_FILE"
    else
        log_info "No log file found yet (service hasn't run)"
    fi
fi

