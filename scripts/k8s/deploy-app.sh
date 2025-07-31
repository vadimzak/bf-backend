#!/bin/bash
set -euo pipefail

# Deploy application to Kubernetes cluster
# This script handles the complete deployment process for a single app
#
# Features:
# - AWS SDK v3 compatibility validation
# - IRSA (IAM Roles for Service Accounts) setup and verification
# - Automatic Docker image building and ECR push
# - Kubernetes deployment with health checks
# - Version management and tagging

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
SETUP_IAM=false
VERSION_BUMP="patch"
SKIP_VERSION_BUMP=false

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
        --setup-iam)
            SETUP_IAM=true
            shift
            ;;
        --version-bump)
            VERSION_BUMP="$2"
            shift 2
            ;;
        --skip-version-bump)
            SKIP_VERSION_BUMP=true
            shift
            ;;
        --help)
            echo "Usage: $0 APP_NAME [OPTIONS]"
            echo "Options:"
            echo "  --build-only     Only build Docker image, don't deploy"
            echo "  --skip-build     Skip building Docker image"
            echo "  --skip-push      Skip pushing image to ECR"
            echo "  --rollback       Rollback to previous deployment"
            echo "  --setup-iam      Setup IAM role if missing"
            echo "  --version-bump TYPE   Bump version (patch|minor|major, default: patch)"
            echo "  --skip-version-bump   Skip version bumping"
            echo "  --help           Show this help message"
            echo
            echo "Examples:"
            echo "  $0 sample-app                    # Build and deploy sample-app"
            echo "  $0 sample-app --build-only       # Only build image"
            echo "  $0 sample-app --skip-build       # Deploy without rebuilding"
            echo "  $0 sample-app --rollback         # Rollback to previous version"
            echo "  $0 sample-app --setup-iam        # Setup IAM role if missing"
            echo "  $0 sample-app --version-bump minor # Deploy with minor version bump"
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
        
        # Store timestamp for deployment use
        export DEPLOYMENT_IMAGE_TAG="$timestamp"
        
        # Get and store image digest for verification
        export DEPLOYMENT_IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$registry/$APP_NAME:$timestamp" 2>/dev/null | cut -d'@' -f2)
        if [[ -z "$DEPLOYMENT_IMAGE_DIGEST" ]]; then
            # If RepoDigests is empty, get the digest from ECR
            DEPLOYMENT_IMAGE_DIGEST=$(aws ecr describe-images \
                --repository-name "$APP_NAME" \
                --image-ids imageTag="$timestamp" \
                --query 'imageDetails[0].imageDigest' \
                --output text \
                --profile "$AWS_PROFILE" \
                --region "$ECR_REGION" 2>/dev/null)
        fi
        
        log_info "Pushed image with tags: latest, $timestamp (digest: ${DEPLOYMENT_IMAGE_DIGEST:0:12}...)"
    fi
}

# Validate image freshness before deployment
validate_image_freshness() {
    local registry="$1"
    local app_name="$2"
    local image_tag="$3"
    
    # Skip validation for latest tag
    if [[ "$image_tag" == "latest" ]]; then
        log_warning "⚠️  Using :latest tag - image freshness validation skipped"
        return 0
    fi
    
    # Get current deployment image if it exists
    local current_image=""
    if kubectl get deployment "$app_name" -n apps >/dev/null 2>&1; then
        current_image=$(kubectl get deployment "$app_name" -n apps -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
        
        # Extract current tag
        local current_tag=""
        if [[ "$current_image" =~ :([^:]+)$ ]]; then
            current_tag="${BASH_REMATCH[1]}"
        fi
        
        # Compare timestamps if both are timestamped
        if [[ "$current_tag" =~ ^[0-9]{8}-[0-9]{6}$ ]] && [[ "$image_tag" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
            if [[ "$image_tag" < "$current_tag" ]]; then
                log_error "❌ Image freshness validation failed!"
                log_error "Attempting to deploy older image: $image_tag"
                log_error "Current deployment uses: $current_tag"
                log_error "Use --skip-build flag if this is intentional"
                return 1
            fi
        fi
        
        log_info "✅ Image freshness validated: $image_tag > $current_tag"
    fi
    
    return 0
}

# Log deployment audit information
log_deployment_audit() {
    local audit_log="$PROJECT_ROOT/deployment-audit.log"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user=$(whoami)
    local git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local image_tag="${DEPLOYMENT_IMAGE_TAG:-latest}"
    local registry=$(get_ecr_registry)
    local full_image_url="$registry/$APP_NAME:$image_tag"
    local version="${APP_VERSION:-unknown}"
    
    # Create audit log entry with version
    local audit_entry="$timestamp | $user | $APP_NAME | v$version | $full_image_url | $git_commit"
    
    # Append to audit log
    echo "$audit_entry" >> "$audit_log"
    
    log_info "📝 Deployment logged to: $audit_log"
}

# Deploy to Kubernetes
deploy_to_k8s() {
    local manifests_dir="$PROJECT_ROOT/apps/$APP_NAME/k8s"
    
    # Check if manifests exist
    if [[ ! -d "$manifests_dir" ]]; then
        log_info "Generating K8s manifests..."
        "$SCRIPT_DIR/configure-apps.sh" --app "$APP_NAME" --no-build --no-push
    fi
    
    # Get ECR registry URL
    local registry
    registry=$(get_ecr_registry)
    
    # Use timestamped tag if available, otherwise use latest
    local image_tag="${DEPLOYMENT_IMAGE_TAG:-latest}"
    local full_image_url="$registry/$APP_NAME:$image_tag"
    
    # Validate image freshness
    if ! validate_image_freshness "$registry" "$APP_NAME" "$image_tag"; then
        exit 1
    fi
    
    log_info "Deploying $APP_NAME to Kubernetes with image: $full_image_url"
    
    # Update deployment manifest with specific image tag
    local temp_manifest=$(mktemp)
    sed "s|image: $registry/$APP_NAME:latest|image: $full_image_url|g" "$manifests_dir/deployment.yaml" > "$temp_manifest"
    
    # Apply updated manifest
    kubectl apply -f "$temp_manifest"
    # Apply other manifests
    kubectl apply -f "$manifests_dir/service.yaml"
    kubectl apply -f "$manifests_dir/ingress.yaml"
    
    # Clean up temp file
    rm "$temp_manifest"
    
    # Force rollout restart to ensure new image is pulled (especially important with :latest tags)
    log_info "Forcing deployment restart to ensure latest image is used..."
    kubectl rollout restart deployment/"$APP_NAME" -n apps
    
    # Wait for rollout
    log_info "Waiting for deployment rollout..."
    if ! kubectl rollout status deployment/"$APP_NAME" -n apps --timeout=5m; then
        log_error "Deployment rollout failed"
        exit 1
    fi
    
    # Verify deployed image matches expected image
    if [[ -n "$DEPLOYMENT_IMAGE_TAG" ]]; then
        local deployed_image=$(kubectl get deployment "$APP_NAME" -n apps -o jsonpath='{.spec.template.spec.containers[0].image}')
        local expected_image="$registry/$APP_NAME:$DEPLOYMENT_IMAGE_TAG"
        
        if [[ "$deployed_image" == "$expected_image" ]]; then
            log_info "✅ Image verification successful: $deployed_image"
        else
            log_error "❌ Image verification failed!"
            log_error "Expected: $expected_image"
            log_error "Deployed: $deployed_image"
            exit 1
        fi
        
        # Additional verification: check running pod image
        local pod_name=$(kubectl get pods -n apps -l app="$APP_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -n "$pod_name" ]]; then
            local running_image=$(kubectl get pod "$pod_name" -n apps -o jsonpath='{.spec.containers[0].image}')
            if [[ "$running_image" == "$expected_image" ]]; then
                log_info "✅ Running pod verification successful: $running_image"
            else
                log_warning "⚠️  Running pod image differs: $running_image"
            fi
        fi
    fi
    
    # Log deployment audit information
    log_deployment_audit
    
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
    
    # Check app exists
    check_app_exists
    
    # Bump version if not skipped and not rollback
    if [[ "$SKIP_VERSION_BUMP" != "true" ]] && [[ "$ROLLBACK" != "true" ]] && [[ "$SKIP_BUILD" != "true" ]]; then
        # Validate version bump type
        if [[ ! "$VERSION_BUMP" =~ ^(patch|minor|major)$ ]]; then
            log_error "Invalid version bump type: $VERSION_BUMP. Must be patch, minor, or major"
            exit 1
        fi
        
        if ! bump_app_version "$APP_NAME" "$VERSION_BUMP" "$PROJECT_ROOT" >/dev/null; then
            exit 1
        fi
    fi
    
    # Create version info for deployment
    create_version_info "$APP_NAME" "$PROJECT_ROOT"
    
    # Setup IAM if requested
    if [[ "$SETUP_IAM" == "true" ]]; then
        if ! setup_app_iam "$APP_NAME" "$PROJECT_ROOT"; then
            exit 1
        fi
    fi
    
    # Validate deployment prerequisites (includes IAM validation)
    if [[ "$BUILD_ONLY" != "true" ]]; then
        if ! validate_deployment_prerequisites "$APP_NAME" "$PROJECT_ROOT"; then
            # If IAM setup is missing and user didn't request setup, suggest it
            if ! check_iam_setup "$APP_NAME" "$PROJECT_ROOT" >/dev/null 2>&1; then
                log_info "💡 Tip: Run with --setup-iam to automatically configure IAM role"
            fi
            exit 1
        fi
    else
        # For build-only, just check basic prerequisites
        if ! verify_prerequisites; then
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