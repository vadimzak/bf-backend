#!/bin/bash
set -euo pipefail

# Configure applications for Kubernetes deployment
# This script sets up ECR repositories, builds images, and prepares K8s manifests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Script options
BUILD_IMAGES=true
PUSH_IMAGES=true
GENERATE_MANIFESTS=true
HTTP_ONLY=false
APPS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-build)
            BUILD_IMAGES=false
            shift
            ;;
        --no-push)
            PUSH_IMAGES=false
            shift
            ;;
        --no-manifests)
            GENERATE_MANIFESTS=false
            shift
            ;;
        --app)
            APPS+=("$2")
            shift 2
            ;;
        --http-only)
            HTTP_ONLY=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --no-build       Skip building Docker images"
            echo "  --no-push        Skip pushing images to ECR"
            echo "  --no-manifests   Skip generating K8s manifests"
            echo "  --http-only      Generate ingress without HTTPS redirect (for rate limit situations)"
            echo "  --app APP        Configure specific app (can be used multiple times)"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get list of apps
get_apps() {
    if [[ ${#APPS[@]} -gt 0 ]]; then
        echo "${APPS[@]}"
    else
        # Find all apps with either Dockerfile or existing k8s manifests
        local apps=()
        for app_dir in "$PROJECT_ROOT/apps"/*; do
            if [[ -d "$app_dir" ]]; then
                local app_name=$(basename "$app_dir")
                if [[ -f "$app_dir/Dockerfile" ]] || [[ -d "$app_dir/k8s" ]]; then
                    apps+=("$app_name")
                fi
            fi
        done
        echo "${apps[@]}"
    fi
}

# Read app configuration
read_app_config() {
    local app_name="$1"
    local config_file="$PROJECT_ROOT/apps/$app_name/deploy.config"
    
    # Initialize app-specific defaults
    export APP_NAME="$app_name"
    case "$app_name" in
        "gamani")
            export APP_PORT="3002"
            ;;
        "sample-app")
            export APP_PORT="3001"
            ;;
        *)
            export APP_PORT="3000"
            ;;
    esac
    export APP_DOMAIN="$app_name.vadimzak.com"
    
    # Try to detect port from existing deployment manifest
    local deployment_file="$PROJECT_ROOT/apps/$app_name/k8s/deployment.yaml"
    if [[ -f "$deployment_file" ]]; then
        local detected_port=$(grep -m1 "containerPort:" "$deployment_file" | awk '{print $3}' || echo "")
        if [[ -n "$detected_port" ]]; then
            export APP_PORT="$detected_port"
            log_info "Detected port $APP_PORT from existing deployment manifest"
        fi
    fi
    
    # Override with deploy.config if it exists
    if [[ -f "$config_file" ]]; then
        log_info "Loading configuration from $config_file"
        source "$config_file"
        # Re-export with any overrides from config file
        export APP_PORT="${APP_PORT:-$APP_PORT}"
        export APP_DOMAIN="${APP_DOMAIN:-$app_name.vadimzak.com}"
    else
        log_info "Using configuration for $app_name (port: $APP_PORT, domain: $APP_DOMAIN)"
    fi
}

# Create ECR repositories
create_ecr_repositories() {
    log_info "Creating ECR repositories..."
    
    local apps
    apps=$(get_apps)
    
    for app in $apps; do
        ensure_ecr_repository "$app"
    done
}

# Build Docker image
build_docker_image() {
    local app_name="$1"
    local app_dir="$PROJECT_ROOT/apps/$app_name"
    
    if [[ ! -f "$app_dir/Dockerfile" ]]; then
        log_warning "No Dockerfile found for $app_name, skipping build"
        return 0
    fi
    
    log_info "Building Docker image for $app_name..."
    
    # Build from workspace root context for NX monorepo
    # Build for platform matching cluster architecture
    local platform="${DOCKER_PLATFORM:-linux/amd64}"
    log_info "Building for platform: $platform"
    docker build \
        --platform "$platform" \
        -t "$app_name:latest" \
        -f "$app_dir/Dockerfile" \
        "$PROJECT_ROOT"
}

# Push Docker image to ECR
push_docker_image() {
    local app_name="$1"
    local registry
    
    registry=$(get_ecr_registry)
    if [[ -z "$registry" ]]; then
        # Create first repository to get registry URL
        ensure_ecr_repository "$app_name"
        registry=$(get_ecr_registry)
    fi
    
    log_info "Pushing Docker image for $app_name to ECR..."
    
    # Login to ECR
    docker_ecr_login "$registry"
    
    # Tag image
    docker tag "$app_name:latest" "$registry/$app_name:latest"
    
    # Push image
    docker push "$registry/$app_name:latest"
}

# Generate K8s manifests for an app
generate_app_manifests() {
    local app_name="$1"
    local manifests_dir="$PROJECT_ROOT/apps/$app_name/k8s"
    
    # Read app configuration
    read_app_config "$app_name"
    
    # Create version info for manifest generation
    create_version_info "$app_name" "$PROJECT_ROOT"
    
    log_info "Generating K8s manifests for $app_name..."
    
    # Create manifests directory
    mkdir -p "$manifests_dir"
    
    local registry
    registry=$(get_ecr_registry)
    
    # Generate Deployment manifest
    cat > "$manifests_dir/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: apps
  labels:
    app: ${APP_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
      - name: app
        image: ${registry}/${APP_NAME}:latest
        imagePullPolicy: Always
        ports:
        - containerPort: ${APP_PORT}
          name: http
        env:
        - name: NODE_ENV
          value: production
        - name: PORT
          value: "${APP_PORT}"
        - name: APP_VERSION
          value: "${APP_VERSION:-1.0.0}"
        - name: APP_GIT_COMMIT
          value: "${APP_GIT_COMMIT:-unknown}"
        - name: APP_BUILD_TIME
          value: "${APP_BUILD_TIME:-unknown}"
        - name: APP_DEPLOYED_BY
          value: "${APP_DEPLOYED_BY:-unknown}"
        livenessProbe:
          httpGet:
            path: /health
            port: ${APP_PORT}
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: ${APP_PORT}
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
EOF
    
    # Generate Service manifest
    cat > "$manifests_dir/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: apps
  labels:
    app: ${APP_NAME}
spec:
  selector:
    app: ${APP_NAME}
  ports:
  - port: 80
    targetPort: ${APP_PORT}
    protocol: TCP
    name: http
  type: ClusterIP
EOF
    
    # Generate Ingress manifest
    if [[ "$HTTP_ONLY" == "true" ]]; then
        log_warning "Generating HTTP-only ingress for $APP_NAME (no HTTPS redirect)"
        cat > "$manifests_dir/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}
  namespace: apps
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: ${APP_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${APP_NAME}
            port:
              number: 80
EOF
    else
        cat > "$manifests_dir/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}
  namespace: apps
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - ${APP_DOMAIN}
    secretName: ${APP_NAME}-tls
  rules:
  - host: ${APP_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${APP_NAME}
            port:
              number: 80
EOF
    fi
    
    # Generate kustomization.yaml for easy deployment
    cat > "$manifests_dir/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: apps

resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml

commonLabels:
  app: ${APP_NAME}
  environment: production
EOF
    
    log_info "Generated manifests in: $manifests_dir"
}

# Deploy app to Kubernetes
deploy_app() {
    local app_name="$1"
    local manifests_dir="$PROJECT_ROOT/apps/$app_name/k8s"
    
    if [[ ! -d "$manifests_dir" ]]; then
        log_error "Manifests directory not found: $manifests_dir"
        log_error "Run with --generate-manifests first"
        return 1
    fi
    
    log_info "Deploying $app_name to Kubernetes..."
    
    # Apply manifests using kubectl
    kubectl apply -k "$manifests_dir"
    
    # Wait for deployment to be ready
    kubectl rollout status deployment/"$app_name" -n apps --timeout=5m
}

# Print deployment instructions
print_deployment_instructions() {
    local apps
    apps=$(get_apps)
    
    echo
    log_info "Application configuration completed!"
    echo
    echo "ECR Registry: $(get_ecr_registry)"
    echo
    echo "Configured applications:"
    for app in $apps; do
        read_app_config "$app"
        echo "  - $app -> $APP_DOMAIN"
    done
    echo
    echo "To deploy applications to Kubernetes:"
    echo "  kubectl apply -k apps/APP_NAME/k8s/"
    echo
    echo "Or deploy all apps:"
    for app in $apps; do
        echo "  kubectl apply -k apps/$app/k8s/"
    done
    echo
    echo "To update DNS records for apps:"
    
    # Check if secondary IP is configured
    local master_ip=$(get_master_ip)
    local instance_id=$(aws ec2 describe-instances \
        --filters "Name=network-interface.association.public-ip,Values=$master_ip" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [[ -n "$instance_id" ]] && [[ "$instance_id" != "None" ]]; then
        local secondary_ip=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].Association.PublicIp | [0]' \
            --output text \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" 2>/dev/null)
        
        if [[ -n "$secondary_ip" ]] && [[ "$secondary_ip" != "None" ]]; then
            echo "  Secondary IP configured: $secondary_ip"
            echo "  DNS should already be configured for HTTPS on port 443"
        else
            echo "  Master IP: $master_ip"
            echo "  Update *.vadimzak.com A record to point to master IP"
            echo "  Note: For HTTPS on port 443, run ./scripts/k8s/setup-secondary-ip.sh"
        fi
    fi
    echo
}

# Main execution
main() {
    log_info "Starting application configuration..."
    log_info "Docker build platform: ${DOCKER_PLATFORM:-linux/amd64} (auto-detected from instance types)"
    
    # Verify prerequisites
    if ! verify_prerequisites; then
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl get nodes >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Run ./scripts/k8s/bootstrap-cluster.sh first"
        exit 1
    fi
    
    # Create ECR repositories
    create_ecr_repositories
    
    # Process each app
    local apps
    apps=$(get_apps)
    
    for app in $apps; do
        log_info "Processing app: $app"
        
        if [[ "$BUILD_IMAGES" == "true" ]]; then
            build_docker_image "$app"
        fi
        
        if [[ "$PUSH_IMAGES" == "true" ]]; then
            push_docker_image "$app"
        fi
        
        if [[ "$GENERATE_MANIFESTS" == "true" ]]; then
            generate_app_manifests "$app"
        fi
    done
    
    print_deployment_instructions
}

# Run main function
main "$@"