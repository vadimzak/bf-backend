#!/bin/bash
set -euo pipefail

# Clean up old ECR images for applications
# This script provides immediate cleanup of old images beyond automatic lifecycle policies

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Script options
KEEP_COUNT=10
DRY_RUN=false
APPS=()
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep)
            KEEP_COUNT="$2"
            shift 2
            ;;
        --app)
            APPS+=("$2")
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --keep N         Keep last N images (default: 10)"
            echo "  --app APP        Clean specific app (can be used multiple times)"
            echo "  --dry-run        Show what would be deleted without actually deleting"
            echo "  --force          Skip confirmation prompts"
            echo "  --help           Show this help message"
            echo
            echo "Examples:"
            echo "  $0                          # Clean all apps, keep last 10 images"
            echo "  $0 --keep 5                 # Keep only last 5 images"
            echo "  $0 --app gamani --app sample-app  # Clean specific apps only"
            echo "  $0 --dry-run                # Show what would be cleaned"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get list of apps to clean
get_apps_to_clean() {
    if [[ ${#APPS[@]} -gt 0 ]]; then
        echo "${APPS[@]}"
    else
        # Find all apps with ECR repositories
        local apps=()
        local all_repos=$(list_ecr_repositories)
        
        for repo in $all_repos; do
            if [[ -d "$PROJECT_ROOT/apps/$repo" ]]; then
                apps+=("$repo")
            fi
        done
        echo "${apps[@]}"
    fi
}

# Show cleanup summary
show_cleanup_summary() {
    local apps
    apps=$(get_apps_to_clean)
    
    if [[ -z "$apps" ]]; then
        log_warning "No apps found to clean up"
        return 0
    fi
    
    echo
    log_info "ECR Image Cleanup Summary"
    echo "========================="
    echo "Keep count: $KEEP_COUNT images per repository"
    echo "Apps to clean: $apps"
    echo "Dry run: $DRY_RUN"
    echo
    
    local total_to_delete=0
    
    for app in $apps; do
        local total_images=$(aws ecr describe-images \
            --repository-name "$app" \
            --query 'length(imageDetails)' \
            --output text \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" 2>/dev/null || echo "0")
        
        local to_delete=$(( total_images > KEEP_COUNT ? total_images - KEEP_COUNT : 0 ))
        total_to_delete=$(( total_to_delete + to_delete ))
        
        echo "  $app: $total_images total images, $to_delete to delete"
    done
    
    echo
    echo "Total images to delete: $total_to_delete"
    echo
}

# Main cleanup function
main() {
    log_info "ECR Image Cleanup Tool"
    
    # Verify prerequisites
    if ! verify_prerequisites; then
        exit 1
    fi
    
    # Get apps to clean
    local apps
    apps=$(get_apps_to_clean)
    
    if [[ -z "$apps" ]]; then
        log_warning "No apps found to clean up"
        exit 0
    fi
    
    # Show summary
    show_cleanup_summary
    
    # Confirm if not in dry-run mode and not forced
    if [[ "$DRY_RUN" != "true" ]] && [[ "$FORCE" != "true" ]]; then
        echo -n "Do you want to proceed with cleanup? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
    
    # Clean up each app
    for app in $apps; do
        cleanup_old_ecr_images "$app" "$KEEP_COUNT" "$DRY_RUN"
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo
        log_info "Dry run completed. Use --force to perform actual cleanup."
    else
        echo
        log_info "ECR image cleanup completed!"
        echo
        log_info "Note: ECR lifecycle policies are automatically applied to keep last $KEEP_COUNT images going forward."
    fi
}

# Run main function
main "$@"