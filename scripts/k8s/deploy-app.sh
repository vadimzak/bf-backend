#!/bin/bash
set -euo pipefail

# Deploy application to Kubernetes cluster
# This script handles the complete deployment process for a single app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Script options
APP_NAME=""
BUILD_ONLY=false
SKIP_BUILD=false
SKIP_PUSH=false
ROLLBACK=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-push)
            SKIP_PUSH=true
            shift
            ;;
        --rollback)
            ROLLBACK=true
            shift
            ;;
        --help)
            echo "Usage: $0 APP_NAME [OPTIONS]"
            echo "Options:"
            echo "  --build-only     Only build Docker image, don't deploy"
            echo "  --skip-build     Skip building Docker image"
            echo "  --skip-push      Skip pushing image to ECR"
            echo "  --rollback       Rollback to previous deployment"
            echo "  --help           Show this help message"
            echo
            echo "Examples:"
            echo "  $0 sample-app                    # Build and deploy sample-app"
            echo "  $0 sample-app --build-only       # Only build image"
            echo "  $0 sample-app --skip-build       # Deploy without rebuilding"
            echo "  $0 sample-app --rollback         # Rollback to previous version"
            exit 0
            ;;
        *)
            if [[ -z "$APP_NAME" ]]; then
                APP_NAME="$1"
            else
                log_error "Unknown option: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate app name
if [[ -z "$APP_NAME" ]]; then
    log_error "App name is required"
    echo "Usage: $0 APP_NAME [OPTIONS]"
    exit 1
fi

# Check if app exists
check_app_exists() {
    local app_dir="$PROJECT_ROOT/apps/$APP_NAME"
    
    if [[ ! -d "$app_dir" ]]; then
        log_error "App directory not found: $app_dir"
        exit 1
    fi
    
    # deploy.config is optional - we can get everything from k8s manifests
    if [[ -f "$app_dir/deploy.config" ]]; then
        log_info "Found deploy.config, loading additional configuration"
    fi
}

# Build and push image
build_and_push() {
    local app_dir="$PROJECT_ROOT/apps/$APP_NAME"
    
    # Ensure ECR repository exists
    ensure_ecr_repository "$APP_NAME"
    
    # Get registry URL
    local registry
    registry=$(get_ecr_registry)
    if [[ -z "$registry" ]]; then
        log_error "Could not get ECR registry URL"
        exit 1
    fi
    
    # Build image
    if [[ "$SKIP_BUILD" != "true" ]]; then
        log_info "Building Docker image for $APP_NAME..."
        
        # Build from workspace root context for NX monorepo
        # Build for platform matching cluster architecture
        local platform="${DOCKER_PLATFORM:-linux/amd64}"
        log_info "Building for platform: $platform"
        docker build \
            --platform "$platform" \
            -t "$APP_NAME:latest" \
            -f "$app_dir/Dockerfile" \
            "$PROJECT_ROOT"
    fi
    
    # Push image
    if [[ "$SKIP_PUSH" != "true" ]] && [[ "$BUILD_ONLY" != "true" ]]; then
        log_info "Pushing image to ECR..."
        
        # Login to ECR
        docker_ecr_login "$registry"
        
        # Tag with timestamp for versioning
        local timestamp=$(date +%Y%m%d-%H%M%S)
        docker tag "$APP_NAME:latest" "$registry/$APP_NAME:latest"
        docker tag "$APP_NAME:latest" "$registry/$APP_NAME:$timestamp"
        
        # Push both tags
        docker push "$registry/$APP_NAME:latest"
        docker push "$registry/$APP_NAME:$timestamp"
        
        log_info "Pushed image with tags: latest, $timestamp"
    fi
}

# Deploy to Kubernetes
deploy_to_k8s() {
    local manifests_dir="$PROJECT_ROOT/apps/$APP_NAME/k8s"
    
    # Check if manifests exist
    if [[ ! -d "$manifests_dir" ]]; then
        log_info "Generating K8s manifests..."
        "$SCRIPT_DIR/configure-apps.sh" --app "$APP_NAME" --no-build --no-push
    fi
    
    log_info "Deploying $APP_NAME to Kubernetes..."
    
    # Apply manifests
    kubectl apply -k "$manifests_dir"
    
    # Wait for rollout
    log_info "Waiting for deployment rollout..."
    if ! kubectl rollout status deployment/"$APP_NAME" -n apps --timeout=5m; then
        log_error "Deployment rollout failed"
        exit 1
    fi
    
    # Get deployment info
    log_info "Deployment successful!"
    kubectl get deployment,service,ingress -n apps -l app="$APP_NAME"
}

# Rollback deployment
rollback_deployment() {
    log_info "Rolling back $APP_NAME deployment..."
    
    # Check if deployment exists
    if ! kubectl get deployment "$APP_NAME" -n apps >/dev/null 2>&1; then
        log_error "Deployment not found: $APP_NAME"
        exit 1
    fi
    
    # Rollback to previous revision
    kubectl rollout undo deployment/"$APP_NAME" -n apps
    
    # Wait for rollout
    kubectl rollout status deployment/"$APP_NAME" -n apps --timeout=5m
    
    log_info "Rollback completed!"
}

# Get app URL
get_app_url() {
    local app_domain=""
    
    # Try to get domain from deploy.config if it exists
    if [[ -f "$PROJECT_ROOT/apps/$APP_NAME/deploy.config" ]]; then
        source "$PROJECT_ROOT/apps/$APP_NAME/deploy.config"
        app_domain="${APP_DOMAIN:-}"
    fi
    
    # If not found, try to extract from ingress.yaml
    if [[ -z "$app_domain" ]] && [[ -f "$PROJECT_ROOT/apps/$APP_NAME/k8s/ingress.yaml" ]]; then
        app_domain=$(grep -m1 "host:" "$PROJECT_ROOT/apps/$APP_NAME/k8s/ingress.yaml" | awk '{print $3}' | tr -d '"')
    fi
    
    # Default to APP_NAME.vadimzak.com if still not found
    app_domain="${app_domain:-$APP_NAME.vadimzak.com}"
    
    local master_ip=$(get_master_ip)
    
    # Check if secondary IP is configured
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=network-interface.association.public-ip,Values=$master_ip" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null)
    
    local secondary_ip=""
    if [[ -n "$instance_id" ]] && [[ "$instance_id" != "None" ]]; then
        secondary_ip=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].Association.PublicIp | [0]' \
            --output text \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" 2>/dev/null)
    fi
    
    echo
    if [[ -n "$secondary_ip" ]] && [[ "$secondary_ip" != "None" ]]; then
        echo "Application URLs:"
        echo "  - https://$app_domain (HTTPS on standard port 443)"
        echo "  - http://$app_domain"
        echo
        echo "Secondary IP is configured and DNS should be pointing to: $secondary_ip"
    else
        echo "Application URLs:"
        echo "  - http://$app_domain:30080"
        echo "  - https://$app_domain:30443"
        echo
        echo "Note: For HTTPS on standard port 443, run:"
        echo "  ./scripts/k8s/setup-secondary-ip.sh"
        echo "  ./scripts/k8s/setup-haproxy-https.sh"
        echo "  ./scripts/k8s/update-app-dns-secondary.sh"
    fi
}

# Main execution
main() {
    log_info "Kubernetes deployment for: $APP_NAME"
    
    # Verify prerequisites
    if ! verify_prerequisites; then
        exit 1
    fi
    
    # Check app exists
    check_app_exists
    
    # Check cluster connection
    if [[ "$BUILD_ONLY" != "true" ]]; then
        if ! kubectl get nodes >/dev/null 2>&1; then
            log_error "Cannot connect to Kubernetes cluster"
            log_error "Run ./scripts/k8s/bootstrap-cluster.sh first"
            exit 1
        fi
    fi
    
    # Execute deployment steps
    if [[ "$ROLLBACK" == "true" ]]; then
        rollback_deployment
    else
        build_and_push
        
        if [[ "$BUILD_ONLY" != "true" ]]; then
            deploy_to_k8s
            get_app_url
        fi
    fi
}

# Run main function
main "$@"