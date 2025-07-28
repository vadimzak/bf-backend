#!/bin/bash

# Health monitoring and auto-recovery script
# Run this script via cron every 5 minutes

set -e

LOG_FILE="/var/log/sample-app/monitoring.log"
COMPOSE_FILE="/var/www/sample-app/docker-compose.prod.yml"
HEALTH_URL="http://localhost/health"
MAX_RETRIES=3
RETRY_DELAY=10

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_health() {
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        if curl -f -s --max-time 10 "$HEALTH_URL" > /dev/null 2>&1; then
            return 0
        fi
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            log "Health check failed, retrying in ${RETRY_DELAY}s (attempt $retries/$MAX_RETRIES)"
            sleep $RETRY_DELAY
        fi
    done
    return 1
}

check_containers() {
    cd /var/www/sample-app
    
    # Check if all containers are running
    local stopped_containers
    stopped_containers=$(docker-compose -f "$COMPOSE_FILE" ps -q --filter "status=exited")
    
    if [ -n "$stopped_containers" ]; then
        log "WARNING: Found stopped containers: $stopped_containers"
        return 1
    fi
    
    return 0
}

restart_services() {
    log "CRITICAL: Restarting all services due to health check failure"
    
    cd /var/www/sample-app
    
    # Restart services
    docker-compose -f "$COMPOSE_FILE" restart
    
    # Wait for services to start
    sleep 30
    
    # Verify health after restart
    if check_health; then
        log "SUCCESS: Services restarted successfully and health check passed"
        return 0
    else
        log "CRITICAL: Health check still failing after restart"
        return 1
    fi
}

send_alert() {
    local message="$1"
    log "ALERT: $message"
    
    # In production, you could send alerts via:
    # - AWS SNS
    # - Slack webhook
    # - Email
    # - PagerDuty
    
    # Example: Send to CloudWatch Logs
    if command -v aws >/dev/null 2>&1; then
        aws logs put-log-events \
            --log-group-name "/aws/ec2/sample-app" \
            --log-stream-name "monitoring" \
            --log-events timestamp=$(date +%s)000,message="$message" \
            2>/dev/null || true
    fi
}

check_disk_space() {
    local usage
    usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -gt 90 ]; then
        log "WARNING: Disk usage is at ${usage}%"
        
        # Clean up Docker images and containers
        docker system prune -f 2>/dev/null || true
        
        # Clean up old logs
        find /var/log -name "*.log" -mtime +7 -exec rm -f {} \; 2>/dev/null || true
        
        return 1
    fi
    
    return 0
}

check_memory() {
    local usage
    usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    
    if [ "$usage" -gt 90 ]; then
        log "WARNING: Memory usage is at ${usage}%"
        return 1
    fi
    
    return 0
}

main() {
    log "Starting health monitoring check"
    
    local issues=0
    
    # Check application health
    if ! check_health; then
        log "CRITICAL: Application health check failed"
        if ! restart_services; then
            send_alert "Application restart failed - manual intervention required"
            issues=$((issues + 1))
        fi
    else
        log "Application health check passed"
    fi
    
    # Check container status
    if ! check_containers; then
        log "WARNING: Some containers are not running properly"
        issues=$((issues + 1))
    fi
    
    # Check system resources
    if ! check_disk_space; then
        issues=$((issues + 1))
    fi
    
    if ! check_memory; then
        issues=$((issues + 1))
    fi
    
    if [ $issues -eq 0 ]; then
        log "All checks passed successfully"
    else
        log "Monitoring completed with $issues issues"
    fi
    
    # Rotate log file if it gets too large (> 10MB)
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt 10485760 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        log "Log file rotated"
    fi
}

# Run main function
main "$@"