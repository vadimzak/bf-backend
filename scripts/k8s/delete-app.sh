#!/bin/bash
set -euo pipefail

# Delete application from Kubernetes cluster and clean up ECR repository
# This script handles the complete deletion process for a single app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Script options
APP_NAME=""
KEEP_ECR=false
FORCE=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-ecr)
            KEEP_ECR=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 APP_NAME [OPTIONS]"
            echo "Delete application from Kubernetes cluster and clean up ECR repository"
            echo ""
            echo "Options:"
            echo "  --keep-ecr       Keep ECR repository (only delete K8s resources)"
            echo "  --force          Skip confirmation prompts"
            echo "  --dry-run        Show what would be deleted without deleting"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 sample-app                    # Delete app and ECR repository"
            echo "  $0 sample-app --keep-ecr         # Delete app but keep ECR repository"
            echo "  $0 sample-app --dry-run          # Show what would be deleted"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$APP_NAME" ]]; then
                APP_NAME="$1"
            else
                log_error "Multiple app names provided. Use one app at a time."
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

# Validate app exists
validate_app() {
    local app_dir="$PROJECT_ROOT/apps/$APP_NAME"
    local config_file="$app_dir/deploy.config"
    local k8s_dir="$app_dir/k8s"
    
    if [[ ! -d "$app_dir" ]]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi
    
    # Check if it has either deploy.config or k8s manifests
    if [[ ! -f "$config_file" ]] && [[ ! -d "$k8s_dir" ]]; then
        log_error "App config not found: $config_file"
        log_error "And no k8s manifests found in: $k8s_dir"
        log_error "This doesn't appear to be a deployable app"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_warning "No deploy.config found, but k8s manifests exist"
        log_warning "Proceeding with k8s manifest-based deletion"
    fi
    
    return 0
}

# Check what exists
check_app_status() {
    local k8s_exists=false
    local ecr_exists=false
    
    # Check if Kubernetes resources exist
    if kubectl get deployment "$APP_NAME" -n apps >/dev/null 2>&1; then
        k8s_exists=true
    fi
    
    # Check if ECR repository exists
    if aws ecr describe-repositories \
        --repository-names "$APP_NAME" \
        --profile "$AWS_PROFILE" \
        --region "$ECR_REGION" >/dev/null 2>&1; then
        ecr_exists=true
    fi
    
    echo "$k8s_exists $ecr_exists"
}

# Show dry run information
show_dry_run() {
    local status=$(check_app_status)
    local k8s_exists=$(echo "$status" | cut -d' ' -f1)
    local ecr_exists=$(echo "$status" | cut -d' ' -f2)
    
    log_info "DRY RUN: Would delete the following resources for app '$APP_NAME':"
    echo
    
    # Kubernetes resources
    if [[ "$k8s_exists" == "true" ]]; then
        echo "Kubernetes resources (namespace: apps):"
        echo "  ✓ Deployment: $APP_NAME"
        echo "  ✓ Service: $APP_NAME"
        echo "  ✓ Ingress: $APP_NAME"
        if kubectl get secret "${APP_NAME}-tls" -n apps >/dev/null 2>&1; then
            echo "  ✓ TLS Secret: ${APP_NAME}-tls"
        fi
    else
        echo "Kubernetes resources:"
        echo "  • No Kubernetes resources found"
    fi
    
    echo
    
    # ECR repository
    if [[ "$KEEP_ECR" == "true" ]]; then
        echo "ECR repository:"
        echo "  • ECR repository will be kept (--keep-ecr specified)"
    elif [[ "$ecr_exists" == "true" ]]; then
        local registry=$(get_ecr_registry)
        local image_count=$(aws ecr describe-images \
            --repository-name "$APP_NAME" \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" \
            --query 'length(imageDetails)' \
            --output text 2>/dev/null || echo "0")
        
        echo "ECR repository:"
        echo "  ✓ Repository: $registry/$APP_NAME ($image_count images)"
    else
        echo "ECR repository:"
        echo "  • No ECR repository found"
    fi
    
    echo
    
    if [[ "$k8s_exists" == "false" ]] && [[ "$ecr_exists" == "false" ]]; then
        log_warning "No resources found for app '$APP_NAME'"
    elif [[ "$k8s_exists" == "false" ]] && [[ "$KEEP_ECR" == "true" ]]; then
        log_warning "No Kubernetes resources found and ECR will be kept"
    else
        log_info "Use --force to skip confirmation, or run without --dry-run to proceed"
    fi
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will delete app '$APP_NAME' from the Kubernetes cluster"
    if [[ "$KEEP_ECR" != "true" ]]; then
        log_warning "This will also delete the ECR repository and all Docker images"
    fi
    log_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled"
        exit 0
    fi
}

# Delete Kubernetes resources
delete_k8s_resources() {
    log_info "Deleting Kubernetes resources for $APP_NAME..."
    
    # Check if resources exist
    if ! kubectl get deployment "$APP_NAME" -n apps >/dev/null 2>&1; then
        log_warning "No Kubernetes resources found for $APP_NAME"
        return 0
    fi
    
    # Delete using kustomize if available
    local manifests_dir="$PROJECT_ROOT/apps/$APP_NAME/k8s"
    if [[ -f "$manifests_dir/kustomization.yaml" ]]; then
        log_info "Deleting resources using kustomize..."
        kubectl delete -k "$manifests_dir" --ignore-not-found=true
    else
        # Delete individual resources
        log_info "Deleting individual resources..."
        kubectl delete deployment "$APP_NAME" -n apps --ignore-not-found=true
        kubectl delete service "$APP_NAME" -n apps --ignore-not-found=true
        kubectl delete ingress "$APP_NAME" -n apps --ignore-not-found=true
        kubectl delete secret "${APP_NAME}-tls" -n apps --ignore-not-found=true
    fi
    
    # Wait for resources to be fully deleted
    log_info "Waiting for resources to be deleted..."
    kubectl wait --for=delete deployment/"$APP_NAME" -n apps --timeout=60s 2>/dev/null || true
}

# Delete ECR repository
delete_ecr_repo() {
    if [[ "$KEEP_ECR" == "true" ]]; then
        log_info "Keeping ECR repository as requested"
        return 0
    fi
    
    log_info "Deleting ECR repository for $APP_NAME..."
    delete_ecr_repository "$APP_NAME" "true"  # Force delete with images
}

# Print summary
print_summary() {
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed for app: $APP_NAME"
    else
        log_info "App deletion completed: $APP_NAME"
        echo
        echo "Summary:"
        echo "========"
        echo "✓ Kubernetes resources deleted"
        if [[ "$KEEP_ECR" == "true" ]]; then
            echo "• ECR repository kept"
        else
            echo "✓ ECR repository deleted"
        fi
    fi
    echo
}

# Main execution
main() {
    log_info "Starting app deletion: $APP_NAME"
    
    # Validate app
    if ! validate_app; then
        exit 1
    fi
    
    # Verify prerequisites for K8s operations
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! kubectl get nodes >/dev/null 2>&1; then
            log_error "Cannot connect to Kubernetes cluster"
            exit 1
        fi
    fi
    
    # Show dry run or proceed with deletion
    if [[ "$DRY_RUN" == "true" ]]; then
        show_dry_run
    else
        local status=$(check_app_status)
        local k8s_exists=$(echo "$status" | cut -d' ' -f1)
        local ecr_exists=$(echo "$status" | cut -d' ' -f2)
        
        if [[ "$k8s_exists" == "false" ]] && [[ "$ecr_exists" == "false" ]]; then
            log_warning "No resources found for app '$APP_NAME'"
            exit 0
        elif [[ "$k8s_exists" == "false" ]] && [[ "$KEEP_ECR" == "true" ]]; then
            log_warning "No Kubernetes resources found and ECR will be kept"
            exit 0
        fi
        
        confirm_deletion
        delete_k8s_resources
        delete_ecr_repo
    fi
    
    print_summary
}

# Run main function
main "$@"