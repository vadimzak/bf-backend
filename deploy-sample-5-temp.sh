#!/bin/bash
# Temporary deployment script for sample-5 using IP address

set -e

# Override REMOTE_HOST to use IP address
export APP_NAME="sample-5"
export APP_PORT="3005"
export APP_DOMAIN="sample-5.vadimzak.com"
export REMOTE_HOST="51.16.33.8"
export APP_DIR="/var/www/sample-5"
export COMPOSE_FILE="docker-compose.prod.yml"
export HEALTH_ENDPOINT="https://sample-5.vadimzak.com/health"
export IMAGE_NAME="sample-5"
export APP_SOURCE_DIR="apps/sample-5"

# Source common deployment functions
source "scripts/lib/deploy-common.sh"

# Run deployment
echo "🚀 sample-5 App Deployment (using IP address)"
echo "============================================"
echo

get_deployment_state
check_prerequisites
pre_deployment_health_check || true  # Don't fail on first deployment
commit_and_push
build_local_image
setup_remote_environment
transfer_image
deploy_to_remote
post_deployment_health_check
cleanup_old_images

log_success "🎉 Deployment completed successfully!"
echo
echo "Application is running at: https://sample-5.vadimzak.com"
echo "Health check: https://sample-5.vadimzak.com/health"