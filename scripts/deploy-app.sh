#!/bin/bash
# Universal deployment script for all apps
# Usage: ./scripts/deploy-app.sh <app-name> [options] [commit-message]

set -e

# Get app name from first argument
APP_NAME=$1
shift  # Remove app name from arguments

# Validate app name
if [[ -z "$APP_NAME" ]]; then
    echo "Error: App name is required"
    echo "Usage: ./scripts/deploy-app.sh <app-name> [options] [commit-message]"
    echo "Example: ./scripts/deploy-app.sh sample-2 --force \"Fix user interface bug\""
    exit 1
fi

# Load app configuration
APP_CONFIG_FILE="apps/$APP_NAME/deploy.config"
if [[ ! -f "$APP_CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found: $APP_CONFIG_FILE"
    echo "Please create a deploy.config file in your app directory"
    exit 1
fi

# Source app configuration
source "$APP_CONFIG_FILE"

# Validate required configuration
if [[ -z "$APP_PORT" ]] || [[ -z "$APP_DOMAIN" ]]; then
    echo "Error: APP_PORT and APP_DOMAIN must be defined in $APP_CONFIG_FILE"
    exit 1
fi

# Set derived variables
REMOTE_HOST="$APP_DOMAIN"
APP_DIR="/var/www/$APP_NAME"
COMPOSE_FILE="docker-compose.prod.yml"
HEALTH_ENDPOINT="https://$APP_DOMAIN/health"
IMAGE_NAME="$APP_NAME"
APP_SOURCE_DIR="apps/$APP_NAME"

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
            cat << EOF
Usage: $0 $APP_NAME [OPTIONS] [COMMIT_MESSAGE]

Deploy $APP_NAME app to production with automated safety checks.

OPTIONS:
    --dry-run       Show what would be deployed without making changes
    --rollback      Rollback to previous deployment
    --force         Skip safety checks and deploy anyway
    --help          Show this help message

EXAMPLES:
    $0 $APP_NAME                                  # Deploy with auto-generated commit message
    $0 $APP_NAME "Fix user interface bug"         # Deploy with custom commit message
    $0 $APP_NAME --dry-run                        # Check what would be deployed
    $0 $APP_NAME --rollback                       # Rollback to previous version

EOF
            exit 0
            ;;
        *)
            COMMIT_MESSAGE="$1"
            shift
            ;;
    esac
done

# Source common deployment functions
source "scripts/lib/deploy-common.sh"

# Main deployment flow
main() {
    echo "🚀 $APP_NAME App Deployment"
    echo "=========================="
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
        if [[ "$FORCE" == "false" ]]; then
            pre_deployment_health_check
        fi
        commit_and_push
    fi
    
    build_local_image
    setup_remote_environment
    transfer_image
    deploy_to_remote
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if post_deployment_health_check; then
            cleanup_old_images
            
            # Register app with auto-recovery service
            register_with_recovery
            
            log_success "🎉 Deployment completed successfully!"
            echo
            echo "Application is running at: https://$APP_DOMAIN"
            echo "Health check: $HEALTH_ENDPOINT"
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