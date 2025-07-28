#!/bin/bash

# One-Click Deployment Script for Sample App
# Automates the entire deployment process with safety checks and rollback capability

set -e  # Exit on any error

# Configuration
REMOTE_HOST="sample.vadimzak.com"
REMOTE_USER="ec2-user"
SSH_KEY="$HOME/.ssh/sample-app-key.pem"
APP_DIR="/var/www/sample-app"
COMPOSE_FILE="docker-compose.prod.yml"
HEALTH_ENDPOINT="https://sample.vadimzak.com/health"
API_ENDPOINT="https://sample.vadimzak.com/api/items"

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

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMIT_MESSAGE]

Deploy sample app to production with automated safety checks.

OPTIONS:
    --dry-run       Show what would be deployed without making changes
    --rollback      Rollback to previous deployment
    --force         Skip safety checks and deploy anyway
    --help          Show this help message

EXAMPLES:
    $0                                  # Deploy with auto-generated commit message
    $0 "Fix user authentication bug"    # Deploy with custom commit message
    $0 --dry-run                        # Check what would be deployed
    $0 --rollback                       # Rollback to previous version

EOF
}

# Parse command line arguments
DRY_RUN=false
ROLLBACK=false
FORCE=false
COMMIT_MESSAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --rollback)
            ROLLBACK=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            COMMIT_MESSAGE="$1"
            shift
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if we're in the correct directory
    if [[ ! -f "apps/sample-app/package.json" ]]; then
        log_error "Must be run from project root directory"
        exit 1
    fi
    
    # Check SSH key
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key not found at $SSH_KEY"
        exit 1
    fi
    
    # Check git status
    if [[ -n $(git status --porcelain) ]] && [[ "$FORCE" == "false" ]]; then
        log_warning "You have uncommitted changes:"
        git status --short
        echo
        read -p "Continue with deployment? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Test SSH connection
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection test'" &>/dev/null; then
        log_error "Cannot connect to $REMOTE_HOST via SSH"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Commit and push local changes
commit_and_push() {
    if [[ -n $(git status --porcelain) ]]; then
        log_info "Committing local changes..."
        
        if [[ -z "$COMMIT_MESSAGE" ]]; then
            COMMIT_MESSAGE="Deploy: $(date '+%Y-%m-%d %H:%M:%S')"
        fi
        
        git add .
        git commit -m "$COMMIT_MESSAGE

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
        
        log_info "Pushing to remote repository..."
        git push origin main
        
        log_success "Code committed and pushed"
    else
        log_info "No local changes to commit"
    fi
}

# Get current deployment state
get_deployment_state() {
    log_info "Getting current deployment state..."
    
    # Get current git hash locally
    LOCAL_HASH=$(git rev-parse HEAD)
    
    # Get current git hash on remote server
    REMOTE_HASH=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cd $APP_DIR && git rev-parse HEAD 2>/dev/null || echo 'none'")
    
    # Get container statuses
    CONTAINER_STATUS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cd $APP_DIR && sudo docker-compose -f $COMPOSE_FILE ps --format 'table {{.Service}}\t{{.Status}}' 2>/dev/null || echo 'No containers'")
    
    echo "Current deployment state:"
    echo "  Local commit:  $LOCAL_HASH"
    echo "  Remote commit: $REMOTE_HASH"
    echo "  Containers:"
    echo "$CONTAINER_STATUS" | sed 's/^/    /'
    echo
}

# Pre-deployment health check
pre_deployment_health_check() {
    log_info "Running pre-deployment health check..."
    
    # Check if application is currently healthy
    if curl -s --max-time 10 "$HEALTH_ENDPOINT" | grep -q "healthy"; then
        log_success "Application is currently healthy"
        return 0
    else
        log_warning "Application health check failed or timed out"
        if [[ "$FORCE" == "false" ]]; then
            read -p "Continue with deployment anyway? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deployment cancelled"
                exit 0
            fi
        fi
        return 1
    fi
}

# Deploy to remote server
deploy_to_remote() {
    log_info "Deploying to remote server..."
    
    # Create deployment script for remote execution
    cat > /tmp/deploy_commands.sh << 'EOF'
#!/bin/bash
set -e

APP_DIR="/var/www/sample-app"
COMPOSE_FILE="docker-compose.prod.yml"

cd $APP_DIR

# Pull latest code
echo "Pulling latest code..."
git fetch origin
git reset --hard origin/main

# Create backup of current containers
echo "Creating backup of current containers..."
sudo docker-compose -f $COMPOSE_FILE ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}' > deployment_backup.txt
echo "$(date): Pre-deployment backup created" >> deployment.log

# Build new images
echo "Building new Docker images..."
sudo docker-compose -f $COMPOSE_FILE build --no-cache

# Rolling restart - start with app containers, then nginx
echo "Performing rolling restart..."

# Stop and start sample-app service
sudo docker-compose -f $COMPOSE_FILE stop sample-app
sudo docker-compose -f $COMPOSE_FILE up -d sample-app

# Wait for app to be healthy
echo "Waiting for application to start..."
sleep 10

# Check if app container is healthy
if sudo docker ps | grep -q "sample-app-sample-app.*healthy"; then
    echo "Application container is healthy"
else
    echo "Warning: Application container may not be healthy"
fi

# Restart other services
sudo docker-compose -f $COMPOSE_FILE up -d cron-tasks watchtower

# Finally restart nginx (minimal downtime)
sudo docker-compose -f $COMPOSE_FILE stop nginx
sudo docker-compose -f $COMPOSE_FILE up -d nginx

echo "Deployment completed successfully"
echo "$(date): Deployment completed" >> deployment.log
EOF

    # Copy and execute deployment script on remote server
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute deployment on remote server"
        cat /tmp/deploy_commands.sh
    else
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/deploy_commands.sh "$REMOTE_USER@$REMOTE_HOST:/tmp/"
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "chmod +x /tmp/deploy_commands.sh && /tmp/deploy_commands.sh"
        log_success "Remote deployment completed"
    fi
    
    # Clean up
    rm -f /tmp/deploy_commands.sh
}

# Post-deployment health check
post_deployment_health_check() {
    log_info "Running post-deployment health check..."
    
    # Wait a moment for services to stabilize
    sleep 5
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    if curl -s --max-time 10 "$HEALTH_ENDPOINT" | grep -q "healthy"; then
        log_success "✅ Health endpoint: PASSED"
    else
        log_error "❌ Health endpoint: FAILED"
        return 1
    fi
    
    # Test API endpoint
    log_info "Testing API endpoint..."
    if curl -s --max-time 10 "$API_ENDPOINT" | grep -q "success"; then
        log_success "✅ API endpoint: PASSED"
    else
        log_error "❌ API endpoint: FAILED"
        return 1
    fi
    
    # Test HTTPS redirect
    log_info "Testing HTTPS redirect..."
    if curl -s --max-time 10 -I "http://sample.vadimzak.com" | grep -q "301"; then
        log_success "✅ HTTPS redirect: PASSED"
    else
        log_error "❌ HTTPS redirect: FAILED"
        return 1
    fi
    
    # Test container status
    log_info "Checking container status..."
    CONTAINER_HEALTH=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cd $APP_DIR && sudo docker-compose -f $COMPOSE_FILE ps --format 'table {{.Service}}\t{{.Status}}'")
    echo "$CONTAINER_HEALTH"
    
    if echo "$CONTAINER_HEALTH" | grep -q "Up"; then
        log_success "✅ Containers are running"
        return 0
    else
        log_error "❌ Some containers are not running properly"
        return 1
    fi
}

# Rollback function
rollback_deployment() {
    log_warning "Rolling back deployment..."
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" << 'EOF'
cd /var/www/sample-app

# Get previous commit
PREVIOUS_COMMIT=$(git log --oneline -2 | tail -1 | cut -d' ' -f1)
echo "Rolling back to commit: $PREVIOUS_COMMIT"

# Reset to previous commit
git reset --hard $PREVIOUS_COMMIT

# Rebuild and restart containers
sudo docker-compose -f docker-compose.prod.yml build --no-cache
sudo docker-compose -f docker-compose.prod.yml up -d

echo "$(date): Rollback completed to $PREVIOUS_COMMIT" >> deployment.log
EOF
    
    log_success "Rollback completed"
}

# Main deployment flow
main() {
    echo "🚀 Sample App One-Click Deployment"
    echo "=================================="
    echo
    
    if [[ "$ROLLBACK" == "true" ]]; then
        rollback_deployment
        exit 0
    fi
    
    # Show current state
    get_deployment_state
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No changes will be made"
        echo
    fi
    
    # Run deployment steps
    check_prerequisites
    
    if [[ "$DRY_RUN" == "false" ]]; then
        pre_deployment_health_check
        commit_and_push
    fi
    
    deploy_to_remote
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if post_deployment_health_check; then
            log_success "🎉 Deployment completed successfully!"
            echo
            echo "Application is running at: https://sample.vadimzak.com"
            echo "Health check: $HEALTH_ENDPOINT"
            echo "API endpoint: $API_ENDPOINT"
        else
            log_error "❌ Post-deployment health checks failed!"
            echo
            read -p "Would you like to rollback? [Y/n]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                rollback_deployment
                log_info "Please investigate the deployment issues and try again"
            fi
            exit 1
        fi
    else
        log_info "DRY RUN completed - use without --dry-run to execute deployment"
    fi
}

# Run main function
main "$@"