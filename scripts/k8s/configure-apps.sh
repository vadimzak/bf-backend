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
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --no-build       Skip building Docker images"
            echo "  --no-push        Skip pushing images to ECR"
            echo "  --no-manifests   Skip generating K8s manifests"
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
        # Find all apps with deploy.config
        find "$PROJECT_ROOT/apps" -name "deploy.config" -type f | \
            while read -r config; do
                basename "$(dirname "$config")"
            done
    fi
}

# Read app configuration
read_app_config() {
    local app_name="$1"
    local config_file="$PROJECT_ROOT/apps/$app_name/deploy.config"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi
    
    # Source the config file
    source "$config_file"
    
    # Export variables for use in manifests
    export APP_NAME="$app_name"
    export APP_PORT="${APP_PORT:-3000}"
    export APP_DOMAIN="${APP_DOMAIN:-$app_name.vadimzak.com}"
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
    
    # Build for linux/amd64 platform
    docker build \
        --platform linux/amd64 \
        -t "$app_name:latest" \
        "$app_dir"
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
        ports:
        - containerPort: ${APP_PORT}
          name: http
        env:
        - name: NODE_ENV
          value: production
        - name: PORT
          value: "${APP_PORT}"
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
    echo "  Master IP: $(get_master_ip)"
    echo "  Update *.vadimzak.com A record to point to master IP"
    echo
}

# Main execution
main() {
    log_info "Starting application configuration..."
    
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