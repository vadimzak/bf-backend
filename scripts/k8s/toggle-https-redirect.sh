#!/bin/bash
set -euo pipefail

# Toggle HTTPS redirect for all applications
# This script enables/disables SSL redirect on all ingress resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Default values
ENABLE_HTTPS=true
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --disable-https|--http-only)
            ENABLE_HTTPS=false
            shift
            ;;
        --enable-https)
            ENABLE_HTTPS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Toggle HTTPS redirect for all application ingresses"
            echo ""
            echo "Options:"
            echo "  --disable-https, --http-only  Disable HTTPS redirect (allow HTTP)"
            echo "  --enable-https                Enable HTTPS redirect (force HTTPS) [default]"
            echo "  --dry-run                     Show what would be done without making changes"
            echo "  --help                        Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Disable HTTPS redirect (allow HTTP access)"
            echo "  $0 --disable-https"
            echo ""
            echo "  # Re-enable HTTPS redirect"
            echo "  $0 --enable-https"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set SSL redirect value
if [[ "$ENABLE_HTTPS" == "true" ]]; then
    SSL_REDIRECT="true"
    log_info "Enabling HTTPS redirect for all applications"
else
    SSL_REDIRECT="false"
    log_warning "Disabling HTTPS redirect - applications will accept HTTP traffic"
    log_warning "This should only be used temporarily (e.g., when hitting Let's Encrypt rate limits)"
fi

# Get all ingresses in the apps namespace
log_info "Getting all ingresses in apps namespace..."
INGRESSES=$(kubectl get ingress -n apps -o json | jq -r '.items[].metadata.name' 2>/dev/null || echo "")

if [[ -z "$INGRESSES" ]]; then
    log_warning "No ingresses found in apps namespace"
    exit 0
fi

# Update each ingress
for ingress in $INGRESSES; do
    log_info "Updating ingress: $ingress"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would update ingress $ingress with:"
        echo "  nginx.ingress.kubernetes.io/ssl-redirect: $SSL_REDIRECT"
        echo "  nginx.ingress.kubernetes.io/force-ssl-redirect: $SSL_REDIRECT"
    else
        kubectl annotate ingress "$ingress" -n apps \
            "nginx.ingress.kubernetes.io/ssl-redirect=$SSL_REDIRECT" \
            "nginx.ingress.kubernetes.io/force-ssl-redirect=$SSL_REDIRECT" \
            --overwrite
    fi
done

# Show current status
if [[ "$DRY_RUN" != "true" ]]; then
    echo
    log_info "Current ingress configuration:"
    kubectl get ingress -n apps -o wide
    
    echo
    if [[ "$ENABLE_HTTPS" == "true" ]]; then
        log_info "HTTPS redirect is now ENABLED"
        log_info "All HTTP traffic will be redirected to HTTPS"
    else
        log_warning "HTTPS redirect is now DISABLED"
        log_warning "Applications will accept both HTTP and HTTPS traffic"
        log_warning "Remember to re-enable HTTPS redirect when the issue is resolved:"
        log_warning "  $0 --enable-https"
    fi
fi