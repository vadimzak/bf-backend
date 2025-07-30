#!/bin/bash
set -euo pipefail

# Delete ECR repositories for specific apps
# This script deletes ECR repositories for one or more apps

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Script options
FORCE=false
DRY_RUN=false
APPS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --app)
            APPS+=("$2")
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS] [APP_NAMES...]"
            echo "Delete ECR repositories for specific apps"
            echo ""
            echo "Options:"
            echo "  --force      Force delete repositories even with images"
            echo "  --dry-run    Show what would be deleted without deleting"
            echo "  --app APP    Specify app name (can be used multiple times)"
            echo "  --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --app sample-app                    # Delete ECR repo for sample-app"
            echo "  $0 --force --app app1 --app app2       # Force delete multiple apps"
            echo "  $0 --dry-run                           # Show all app ECR repos that would be deleted"
            echo "  $0 sample-app another-app              # Delete ECR repos for specified apps"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            APPS+=("$1")
            shift
            ;;
    esac
done

# Get list of apps to delete
get_apps_to_delete() {
    if [[ ${#APPS[@]} -gt 0 ]]; then
        echo "${APPS[@]}"
    else
        # Auto-detect all apps
        local project_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
        find "$project_root/apps" -name "deploy.config" -type f | \
            while read -r config; do
                basename "$(dirname "$config")"
            done
    fi
}

# Confirm deletion
confirm_deletion() {
    local apps="$1"
    
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will delete ECR repositories for: $apps"
    log_warning "All Docker images in these repositories will be permanently lost!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled"
        exit 0
    fi
}

# Show repositories that would be deleted
show_dry_run() {
    local apps="$1"
    
    log_info "DRY RUN: Would delete the following ECR repositories:"
    echo
    
    local found_any=false
    for app in $apps; do
        if aws ecr describe-repositories \
            --repository-names "$app" \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" >/dev/null 2>&1; then
            
            local registry=$(get_ecr_registry)
            local image_count=$(aws ecr describe-images \
                --repository-name "$app" \
                --profile "$AWS_PROFILE" \
                --region "$ECR_REGION" \
                --query 'length(imageDetails)' \
                --output text 2>/dev/null || echo "0")
            
            echo "  ✓ $app ($registry/$app with $image_count images)"
            found_any=true
        else
            echo "  • $app (repository does not exist)"
        fi
    done
    
    if [[ "$found_any" == "false" ]]; then
        log_warning "No existing ECR repositories found for specified apps"
    fi
    
    echo
    log_info "Use --force to delete repositories with images, or run without --dry-run to proceed"
}

# Delete ECR repositories for apps
delete_app_repositories() {
    local apps="$1"
    
    log_info "Deleting ECR repositories for apps: $apps"
    
    local deleted_count=0
    local skipped_count=0
    
    for app in $apps; do
        if aws ecr describe-repositories \
            --repository-names "$app" \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" >/dev/null 2>&1; then
            
            # Check if repository has images
            local image_count=$(aws ecr describe-images \
                --repository-name "$app" \
                --profile "$AWS_PROFILE" \
                --region "$ECR_REGION" \
                --query 'length(imageDetails)' \
                --output text 2>/dev/null || echo "0")
            
            if [[ "$image_count" -gt 0 ]] && [[ "$FORCE" != "true" ]]; then
                log_warning "Repository $app has $image_count images. Use --force to delete"
                ((skipped_count++))
                continue
            fi
            
            delete_ecr_repository "$app" "$FORCE"
            ((deleted_count++))
        else
            log_debug "ECR repository $app does not exist, skipping"
        fi
    done
    
    echo
    log_info "ECR repository cleanup completed:"
    log_info "  Deleted: $deleted_count repositories"
    if [[ $skipped_count -gt 0 ]]; then
        log_warning "  Skipped: $skipped_count repositories with images (use --force to delete)"
    fi
}

# Print summary
print_summary() {
    local apps="$1"
    
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed for apps: $apps"
    else
        log_info "ECR repository deletion completed for apps: $apps"
    fi
    echo
}

# Main execution
main() {
    log_info "Starting ECR repository deletion..."
    
    # Verify prerequisites
    if ! command_exists aws; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Get apps to delete
    local apps
    apps=$(get_apps_to_delete)
    
    if [[ -z "$apps" ]]; then
        log_warning "No apps found to delete ECR repositories"
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        show_dry_run "$apps"
    else
        confirm_deletion "$apps"
        delete_app_repositories "$apps"
    fi
    
    print_summary "$apps"
}

# Run main function
main "$@"