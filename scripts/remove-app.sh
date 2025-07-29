#!/bin/bash
# Script to safely remove an app from both the repository and production server
# Usage: ./scripts/remove-app.sh <app-name>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse command line arguments
APP_NAME=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: $0 [OPTIONS] <app-name>

Remove an app from both the repository and production server.

OPTIONS:
    --force, -f     Skip all confirmation prompts
    --help, -h      Show this help message

EXAMPLES:
    $0 my-old-app                    # Remove app with confirmation prompts
    $0 --force my-old-app            # Remove app without confirmation
    $0 -f my-old-app                 # Short form of --force

EOF
            exit 0
            ;;
        *)
            APP_NAME="$1"
            shift
            ;;
    esac
done

if [ -z "$APP_NAME" ]; then
    echo "Error: App name is required"
    echo "Usage: $0 [OPTIONS] <app-name>"
    echo "Try '$0 --help' for more information"
    exit 1
fi

# Configuration
APP_DIR="apps/$APP_NAME"
REMOTE_USER="ec2-user"
SSH_KEY="$HOME/.ssh/sample-app-key.pem"
SHARED_NETWORK="sample-app_app-network"
LOG_FILE="/tmp/remove-app-${APP_NAME}-$(date +%Y%m%d-%H%M%S).log"

# Validate app exists
if [[ ! -d "$APP_DIR" ]]; then
    log_error "App directory not found: $APP_DIR"
    log_error "Available apps:"
    ls -1 apps/ | grep -v '^\.' | sed 's/^/  - /'
    exit 1
fi

# Load app configuration
APP_CONFIG_FILE="$APP_DIR/deploy.config"
if [[ ! -f "$APP_CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $APP_CONFIG_FILE"
    exit 1
fi

# Source app configuration
source "$APP_CONFIG_FILE"

# Validate required configuration
if [[ -z "$APP_PORT" ]] || [[ -z "$APP_DOMAIN" ]]; then
    log_error "APP_PORT and APP_DOMAIN must be defined in $APP_CONFIG_FILE"
    exit 1
fi

# Set derived variables
REMOTE_HOST="$APP_DOMAIN"
REMOTE_APP_DIR="/var/www/$APP_NAME"
COMPOSE_FILE="docker-compose.prod.yml"
IMAGE_NAME="$APP_NAME"

# Start logging
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "🗑️  App Removal Script"
echo "===================="
echo "App Name: $APP_NAME"
echo "Domain: $APP_DOMAIN"
echo "Port: $APP_PORT"
echo "Log file: $LOG_FILE"
echo

# Confirmation prompt
if [[ "$FORCE" != "true" ]]; then
    log_warning "⚠️  WARNING: This will PERMANENTLY remove the following:"
    echo "  - Production containers and images for $APP_NAME"
    echo "  - Remote directory: $REMOTE_APP_DIR"
    echo "  - Local directory: $APP_DIR"
    echo "  - DNS A record for $APP_DOMAIN"
    echo "  - Nginx configuration for $APP_DOMAIN"
    echo

    read -p "Are you ABSOLUTELY SURE you want to remove $APP_NAME? Type the app name to confirm: " CONFIRM_NAME
    if [[ "$CONFIRM_NAME" != "$APP_NAME" ]]; then
        log_error "Confirmation failed. Exiting."
        exit 1
    fi

    echo
    read -p "This action CANNOT be undone. Continue? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Removal cancelled"
        exit 0
    fi
else
    log_warning "Force mode enabled - skipping confirmation prompts"
    log_warning "Removing app: $APP_NAME"
fi

echo
log_info "Starting removal process for $APP_NAME..."
echo

# Function to check SSH connection
check_ssh_connection() {
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection test'" &>/dev/null; then
        log_warning "Cannot connect to $REMOTE_HOST via SSH - server components may already be removed"
        return 1
    fi
    return 0
}

# Step 1: Remove from production server
if check_ssh_connection; then
    log_info "Step 1: Removing app from production server..."
    
    # Create removal script for remote execution
    cat > /tmp/remove_app_commands.sh << EOF
#!/bin/bash
set -e

APP_NAME="$APP_NAME"
APP_DIR="$REMOTE_APP_DIR"
IMAGE_NAME="$IMAGE_NAME"

echo "Checking if app directory exists..."
if [ -d "\$APP_DIR" ]; then
    cd "\$APP_DIR"
    
    # Stop and remove containers
    if [ -f "$COMPOSE_FILE" ]; then
        echo "Stopping and removing containers..."
        sudo docker-compose -f $COMPOSE_FILE down -v || true
        
        # Remove containers that might be connected to shared network
        for container in \$(sudo docker ps -a --filter "name=${APP_NAME}" --format "{{.Names}}"); do
            echo "Removing container: \$container"
            sudo docker rm -f \$container || true
        done
    fi
    
    # Remove app directory
    echo "Removing app directory..."
    cd /
    sudo rm -rf "\$APP_DIR"
else
    echo "App directory not found on server"
fi

# Remove Docker images
echo "Removing Docker images..."
for image in \$(sudo docker images "\$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}"); do
    echo "Removing image: \$image"
    sudo docker rmi -f "\$image" || true
done

# Clean up any volumes
echo "Cleaning up volumes..."
for volume in \$(sudo docker volume ls --filter "name=\${APP_NAME}" --format "{{.Name}}"); do
    echo "Removing volume: \$volume"
    sudo docker volume rm -f "\$volume" || true
done

echo "Server cleanup completed"
EOF

    # Execute removal script on remote server
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/remove_app_commands.sh "$REMOTE_USER@$REMOTE_HOST:/tmp/" 2>/dev/null || true
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "chmod +x /tmp/remove_app_commands.sh && /tmp/remove_app_commands.sh" 2>/dev/null; then
        log_success "✅ Removed from production server"
    else
        log_warning "⚠️  Some server cleanup may have failed (app might already be partially removed)"
    fi
    
    # Clean up
    rm -f /tmp/remove_app_commands.sh
else
    log_warning "Cannot connect to production server - skipping server cleanup"
fi

# Step 2: Update nginx configuration
log_info "Step 2: Updating nginx configuration..."

# Try to connect to the main sample app server for nginx update
NGINX_HOST="sample.vadimzak.com"
if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "$REMOTE_USER@$NGINX_HOST" "echo 'Connected'" &>/dev/null; then
    # Download current nginx config
    NGINX_CONFIG="/tmp/nginx.conf.current"
    NGINX_CONFIG_NEW="/tmp/nginx.conf.new"
    
    if scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$NGINX_HOST:/var/www/sample-app/deploy/nginx.conf" "$NGINX_CONFIG" 2>/dev/null; then
        # Remove app's server blocks
        # Use awk to remove the server blocks for this app
        awk -v app="$APP_NAME" -v domain="$APP_DOMAIN" '
        BEGIN { skip = 0; buffer = "" }
        /^# .* App Configuration$/ && $2 == app {
            skip = 1
            next
        }
        /^server \{/ && skip == 0 {
            in_server = 1
            buffer = $0 "\n"
            next
        }
        in_server && /server_name/ && $2 ~ domain {
            skip = 1
            in_server = 0
            buffer = ""
            next
        }
        in_server && /^\}/ {
            in_server = 0
            if (skip == 0) {
                print buffer $0
            } else {
                skip = 0
            }
            buffer = ""
            next
        }
        in_server {
            buffer = buffer $0 "\n"
            next
        }
        skip && /^server \{/ {
            skip_depth = 1
        }
        skip && skip_depth > 0 && /^\{/ {
            skip_depth++
        }
        skip && skip_depth > 0 && /^\}/ {
            skip_depth--
            if (skip_depth == 0) {
                skip = 0
            }
            next
        }
        skip {
            next
        }
        {
            print
        }
        ' "$NGINX_CONFIG" > "$NGINX_CONFIG_NEW"
        
        # Upload updated nginx config
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$NGINX_CONFIG_NEW" "$REMOTE_USER@$NGINX_HOST:/tmp/nginx.conf.new" 2>/dev/null
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$NGINX_HOST" "sudo cp /tmp/nginx.conf.new /var/www/sample-app/deploy/nginx.conf" 2>/dev/null
        
        # Reload nginx
        log_info "Reloading nginx configuration..."
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$NGINX_HOST" "cd /var/www/sample-app && sudo docker-compose -f docker-compose.prod.yml exec -T nginx nginx -s reload" 2>/dev/null || \
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$NGINX_HOST" "cd /var/www/sample-app && sudo docker-compose -f docker-compose.prod.yml restart nginx" 2>/dev/null || \
        log_warning "Failed to reload nginx - you may need to manually restart it"
        
        log_success "✅ Nginx configuration updated"
        
        # Clean up
        rm -f "$NGINX_CONFIG" "$NGINX_CONFIG_NEW"
    else
        log_warning "⚠️  Could not update nginx configuration - you may need to manually remove the server blocks for $APP_DOMAIN"
    fi
else
    log_warning "⚠️  Cannot connect to nginx server - you may need to manually update nginx configuration"
fi

# Step 3: Remove DNS record
log_info "Step 3: Removing DNS record for $APP_DOMAIN..."

# Get the hosted zone ID (same as in add-new-app.sh)
HOSTED_ZONE_ID="Z2O129XK0SJBV9"

# Create change batch for deletion
CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "$APP_DOMAIN",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "51.16.33.8"}]
    }
  }]
}
EOF
)

# Execute DNS deletion
if aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" > /dev/null 2>&1; then
    log_success "✅ DNS record removed"
else
    log_warning "⚠️  Failed to remove DNS record (it may not exist)"
fi

# Step 4: Clean up local Docker resources
log_info "Step 4: Cleaning up local Docker resources..."

# Remove local images
for image in $(docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null); do
    log_info "Removing local image: $image"
    docker rmi -f "$image" 2>/dev/null || true
done

# Remove any local volumes
for volume in $(docker volume ls --filter "name=${APP_NAME}" --format "{{.Name}}" 2>/dev/null); do
    log_info "Removing local volume: $volume"
    docker volume rm -f "$volume" 2>/dev/null || true
done

log_success "✅ Local Docker cleanup completed"

# Step 5: Remove from repository
log_info "Step 5: Removing app directory from repository..."

# Check git status
if [[ -n $(git status --porcelain) ]]; then
    log_warning "You have uncommitted changes. Please commit or stash them before removing the app directory."
    git status --short
    echo
    if [[ "$FORCE" != "true" ]]; then
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removal cancelled"
            exit 0
        fi
    else
        log_warning "Force mode - continuing despite uncommitted changes"
    fi
fi

# Remove the app directory
rm -rf "$APP_DIR"
log_success "✅ App directory removed"

# Commit the removal
log_info "Creating git commit for app removal..."
git add -A
git commit -m "Remove $APP_NAME app

- Removed app directory: $APP_DIR
- Removed DNS record: $APP_DOMAIN
- Cleaned up production server resources
- Updated nginx configuration

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>" || log_warning "No changes to commit (app may have already been removed from git)"

# Push if remote exists
if git remote | grep -q origin; then
    log_info "Pushing changes to remote repository..."
    git push origin main || log_warning "Failed to push to remote repository"
fi

# Final summary
echo
echo "🎉 App Removal Summary"
echo "====================="
echo
log_success "✅ $APP_NAME has been removed successfully!"
echo
echo "Completed actions:"
echo "  ✓ Removed production containers and images"
echo "  ✓ Removed remote directory: $REMOTE_APP_DIR"
echo "  ✓ Updated nginx configuration"
echo "  ✓ Removed DNS record for $APP_DOMAIN"
echo "  ✓ Cleaned up local Docker resources"
echo "  ✓ Removed local directory: $APP_DIR"
echo "  ✓ Committed changes to git"
echo
echo "Log file saved to: $LOG_FILE"
echo
log_info "Note: DNS changes may take a few minutes to propagate"
log_info "Note: The wildcard SSL certificate (*.vadimzak.com) remains unchanged"