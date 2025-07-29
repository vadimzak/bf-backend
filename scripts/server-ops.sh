#!/bin/bash
# Server operations script for common SSH tasks
# Usage: ./scripts/server-ops.sh <operation> [args]

set -e

# Configuration
SSH_KEY="$HOME/.ssh/sample-app-key.pem"
SSH_USER="ec2-user"
SSH_HOST="sample.vadimzak.com"

# Helper function to execute remote commands
remote_exec() {
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" "$@"
}

# Helper function to copy files
remote_copy() {
    scp -i "$SSH_KEY" "$@"
}

# Show usage
show_usage() {
    echo "Usage: $0 <operation> [args]"
    echo ""
    echo "Operations:"
    echo "  ps [app]                 - Show docker containers (optionally filter by app name)"
    echo "  logs <container> [lines] - Show container logs (default: 50 lines)"
    echo "  restart <service>        - Restart a service (e.g., nginx, sample-app)"
    echo "  nginx-config             - Show nginx configuration"
    echo "  nginx-check              - Check nginx configuration syntax"
    echo "  nginx-reload             - Reload nginx configuration"
    echo "  nginx-fix                - Fix common nginx issues"
    echo "  health <app>             - Check app health endpoint"
    echo "  exec <command>           - Execute arbitrary command"
    echo "  copy-to <local> <remote> - Copy file to server"
    echo "  copy-from <remote> <local> - Copy file from server"
    echo ""
    echo "Examples:"
    echo "  $0 ps sample-4"
    echo "  $0 logs sample-app-nginx-1 100"
    echo "  $0 restart nginx"
    echo "  $0 health sample-4"
    exit 1
}

# Check if operation is provided
if [ $# -eq 0 ]; then
    show_usage
fi

OPERATION=$1
shift

case $OPERATION in
    ps)
        if [ -n "$1" ]; then
            remote_exec "sudo docker ps | grep -E 'CONTAINER|$1'"
        else
            remote_exec "sudo docker ps"
        fi
        ;;
    
    logs)
        if [ -z "$1" ]; then
            echo "Error: Container name required"
            exit 1
        fi
        LINES=${2:-50}
        remote_exec "sudo docker logs $1 --tail $LINES"
        ;;
    
    restart)
        if [ -z "$1" ]; then
            echo "Error: Service name required"
            exit 1
        fi
        case $1 in
            nginx)
                remote_exec "sudo docker restart sample-app-nginx-1"
                ;;
            *)
                remote_exec "cd /var/www/$1 && sudo docker-compose -f docker-compose.prod.yml restart"
                ;;
        esac
        ;;
    
    nginx-config)
        remote_exec "cat /var/www/sample-app/deploy/nginx.conf"
        ;;
    
    nginx-check)
        remote_exec "sudo docker exec sample-app-nginx-1 nginx -t"
        ;;
    
    nginx-reload)
        remote_exec "sudo docker exec sample-app-nginx-1 nginx -s reload"
        ;;
    
    nginx-fix)
        echo "Fetching current nginx config..."
        TEMP_CONFIG="/tmp/nginx.conf.fix.$$"
        remote_exec "cat /var/www/sample-app/deploy/nginx.conf" > "$TEMP_CONFIG"
        
        # Check if the config has proper http block
        if ! grep -q "^http {" "$TEMP_CONFIG"; then
            echo "Adding missing http block..."
            echo "http {" > "$TEMP_CONFIG.new"
            cat "$TEMP_CONFIG" >> "$TEMP_CONFIG.new"
            echo "}" >> "$TEMP_CONFIG.new"
            mv "$TEMP_CONFIG.new" "$TEMP_CONFIG"
        fi
        
        echo "Uploading fixed config..."
        remote_copy "$TEMP_CONFIG" "$SSH_USER@$SSH_HOST:/tmp/nginx.conf.fixed"
        remote_exec "sudo cp /tmp/nginx.conf.fixed /var/www/sample-app/deploy/nginx.conf"
        rm -f "$TEMP_CONFIG"
        
        echo "Restarting nginx..."
        remote_exec "sudo docker restart sample-app-nginx-1"
        ;;
    
    health)
        if [ -z "$1" ]; then
            echo "Error: App name required"
            exit 1
        fi
        APP=$1
        PORT=$(remote_exec "grep APP_PORT /var/www/$APP/deploy.config 2>/dev/null | cut -d= -f2" || echo "")
        if [ -n "$PORT" ]; then
            echo "Checking internal health endpoint..."
            remote_exec "curl -s http://localhost:$PORT/health | jq . || echo 'Failed to connect'"
        else
            echo "Error: Could not determine port for $APP"
        fi
        ;;
    
    exec)
        if [ $# -eq 0 ]; then
            echo "Error: Command required"
            exit 1
        fi
        remote_exec "$@"
        ;;
    
    copy-to)
        if [ $# -ne 2 ]; then
            echo "Error: Usage: $0 copy-to <local-file> <remote-path>"
            exit 1
        fi
        remote_copy "$1" "$SSH_USER@$SSH_HOST:$2"
        ;;
    
    copy-from)
        if [ $# -ne 2 ]; then
            echo "Error: Usage: $0 copy-from <remote-path> <local-file>"
            exit 1
        fi
        remote_copy "$SSH_USER@$SSH_HOST:$1" "$2"
        ;;
    
    *)
        echo "Error: Unknown operation '$OPERATION'"
        show_usage
        ;;
esac