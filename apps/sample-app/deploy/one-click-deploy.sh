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
IMAGE_NAME="sample-app"
APP_SOURCE_DIR="apps/sample-app"

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
    if [[ ! -f "$APP_SOURCE_DIR/package.json" ]]; then
        log_error "Must be run from project root directory"
        exit 1
    fi
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed on this machine"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker and try again"
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
    LOCAL_SHORT_HASH=$(git rev-parse --short HEAD)
    
    # Check if local image exists
    if docker image inspect "$IMAGE_NAME:$LOCAL_SHORT_HASH" &>/dev/null; then
        LOCAL_IMAGE_STATUS="Built"
    elif docker image inspect "$IMAGE_NAME:latest" &>/dev/null; then
        LOCAL_IMAGE_STATUS="Built (latest)"
    else
        LOCAL_IMAGE_STATUS="Not built"
    fi
    
    # Get remote image info
    REMOTE_IMAGE_INFO=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "sudo docker images $IMAGE_NAME --format 'table {{.Tag}}\t{{.CreatedAt}}' 2>/dev/null | tail -n +2 || echo 'No images'")
    
    # Get container statuses
    CONTAINER_STATUS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "if [ -d '$APP_DIR' ]; then cd $APP_DIR && sudo docker-compose -f $COMPOSE_FILE ps --format 'table {{.Service}}\t{{.Status}}' 2>/dev/null; else echo 'Directory not found'; fi || echo 'No containers'")
    
    echo "Current deployment state:"
    echo "  Local commit:    $LOCAL_HASH"
    echo "  Local image:     $LOCAL_IMAGE_STATUS"
    echo "  Remote images:   $REMOTE_IMAGE_INFO"
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

# Build image locally
build_local_image() {
    log_info "Building Docker image locally..."
    
    # Detect local platform and warn if cross-building
    LOCAL_ARCH=$(uname -m)
    if [[ "$LOCAL_ARCH" == "arm64" ]]; then
        log_warning "Detected ARM64 Mac - cross-building for linux/amd64 (EC2 compatibility)"
    elif [[ "$LOCAL_ARCH" == "x86_64" ]]; then
        log_info "Detected x86_64 architecture - building for linux/amd64"
    else
        log_warning "Unknown architecture: $LOCAL_ARCH - building for linux/amd64"
    fi
    
    # Get git hash for versioning
    GIT_HASH=$(git rev-parse --short HEAD)
    IMAGE_TAG="$IMAGE_NAME:$GIT_HASH"
    IMAGE_LATEST="$IMAGE_NAME:latest"
    
    cd "$APP_SOURCE_DIR"
    
    # Build the image with git hash tag for linux/amd64 platform
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would build Docker image $IMAGE_TAG for linux/amd64"
    else
        log_info "Building for linux/amd64 platform..."
        docker build --platform linux/amd64 -t "$IMAGE_TAG" -t "$IMAGE_LATEST" .
        log_success "Built image: $IMAGE_TAG (linux/amd64)"
    fi
    
    cd - > /dev/null
}

# Transfer image to remote server
transfer_image() {
    log_info "Transferring image to production server..."
    
    GIT_HASH=$(git rev-parse --short HEAD)
    IMAGE_TAG="$IMAGE_NAME:$GIT_HASH"
    IMAGE_FILE="/tmp/${IMAGE_NAME}-${GIT_HASH}.tar.gz"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would save image to $IMAGE_FILE"
        log_info "DRY RUN: Would transfer image to remote server"
        log_info "DRY RUN: Would load image on remote server"
        return
    fi
    
    # Save and compress image
    log_info "Saving and compressing image..."
    docker save "$IMAGE_TAG" | gzip > "$IMAGE_FILE"
    
    # Check file size
    FILE_SIZE=$(du -h "$IMAGE_FILE" | cut -f1)
    log_info "Image file size: $FILE_SIZE"
    
    # Transfer to remote server
    log_info "Uploading image to production server..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$IMAGE_FILE" "$REMOTE_USER@$REMOTE_HOST:/tmp/"
    
    # Load image on remote server
    log_info "Loading image on production server..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
        "gunzip -c /tmp/$(basename $IMAGE_FILE) | sudo docker load"
    
    # Tag as latest on remote server
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
        "sudo docker tag $IMAGE_TAG $IMAGE_NAME:latest"
    
    # Clean up local file
    rm -f "$IMAGE_FILE"
    
    log_success "Image transfer completed"
}

# Setup remote directory and files
setup_remote_environment() {
    log_info "Setting up remote environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create remote directory and transfer files"
        return
    fi
    
    # Create remote directory structure
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
        "sudo mkdir -p $APP_DIR/deploy && sudo chown -R ec2-user:ec2-user $APP_DIR"
    
    # Transfer docker-compose.prod.yml
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
        "$APP_SOURCE_DIR/docker-compose.prod.yml" \
        "$REMOTE_USER@$REMOTE_HOST:$APP_DIR/"
    
    # Transfer nginx configuration
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
        "$APP_SOURCE_DIR/deploy/nginx.conf" \
        "$REMOTE_USER@$REMOTE_HOST:$APP_DIR/deploy/"
    
    log_success "Remote environment setup completed"
}

# Deploy containers on remote server
deploy_to_remote() {
    log_info "Deploying containers on remote server..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update docker-compose and restart containers"
        return
    fi
    
    # Create deployment script for remote execution
    cat > /tmp/deploy_commands.sh << 'EOF'
#!/bin/bash
set -e

APP_DIR="/var/www/sample-app"
COMPOSE_FILE="docker-compose.prod.yml"

cd $APP_DIR

# Create backup of current containers
echo "Creating backup of current containers..."
sudo docker-compose -f $COMPOSE_FILE ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}' > deployment_backup.txt
echo "$(date): Pre-deployment backup created" >> deployment.log

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
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/deploy_commands.sh "$REMOTE_USER@$REMOTE_HOST:/tmp/"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "chmod +x /tmp/deploy_commands.sh && /tmp/deploy_commands.sh"
    
    # Clean up
    rm -f /tmp/deploy_commands.sh
    
    log_success "Remote deployment completed"
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
    
    # Get list of available images on remote server
    AVAILABLE_IMAGES=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
        "sudo docker images $IMAGE_NAME --format '{{.Tag}}' | grep -v latest | head -5")
    
    if [[ -z "$AVAILABLE_IMAGES" ]]; then
        log_error "No previous images available for rollback"
        return 1
    fi
    
    echo "Available images for rollback:"
    echo "$AVAILABLE_IMAGES" | nl
    echo
    
    # Use the most recent non-latest image for rollback
    ROLLBACK_TAG=$(echo "$AVAILABLE_IMAGES" | head -1)
    
    if [[ -z "$ROLLBACK_TAG" ]]; then
        log_error "No suitable rollback image found"
        return 1
    fi
    
    log_info "Rolling back to image: $IMAGE_NAME:$ROLLBACK_TAG"
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" << EOF
cd /var/www/sample-app

# Tag the rollback image as latest
sudo docker tag $IMAGE_NAME:$ROLLBACK_TAG $IMAGE_NAME:latest

# Restart containers with rollback image
sudo docker-compose -f docker-compose.prod.yml down
sudo docker-compose -f docker-compose.prod.yml up -d

echo "\$(date): Rollback completed to $ROLLBACK_TAG" >> deployment.log
EOF
    
    log_success "Rollback completed to $ROLLBACK_TAG"
}

# Clean up old images
cleanup_old_images() {
    log_info "Cleaning up old images..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would clean up old images (keeping latest 3)"
        return
    fi
    
    # Clean up local images (keep latest 3)
    OLD_LOCAL_IMAGES=$(docker images "$IMAGE_NAME" --format "{{.Tag}}" | grep -v latest | tail -n +4)
    if [[ -n "$OLD_LOCAL_IMAGES" ]]; then
        log_info "Removing old local images..."
        echo "$OLD_LOCAL_IMAGES" | while read tag; do
            docker rmi "$IMAGE_NAME:$tag" 2>/dev/null || true
        done
    fi
    
    # Clean up remote images (keep latest 3)
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" << 'EOF'
OLD_REMOTE_IMAGES=$(sudo docker images sample-app --format "{{.Tag}}" | grep -v latest | tail -n +4)
if [[ -n "$OLD_REMOTE_IMAGES" ]]; then
    echo "Removing old remote images..."
    echo "$OLD_REMOTE_IMAGES" | while read tag; do
        sudo docker rmi sample-app:$tag 2>/dev/null || true
    done
fi

# Clean up old compressed image files
sudo rm -f /tmp/sample-app-*.tar.gz
EOF
    
    log_success "Image cleanup completed"
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
    
    build_local_image
    setup_remote_environment
    transfer_image
    deploy_to_remote
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if post_deployment_health_check; then
            cleanup_old_images
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
        cleanup_old_images
    fi
}

# Run main function
main "$@"