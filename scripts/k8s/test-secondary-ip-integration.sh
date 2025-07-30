#!/bin/bash
set -euo pipefail

# Test script to verify secondary IP integration
# This script performs a dry run to ensure all scripts are properly integrated

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

log_info "Testing secondary IP integration..."

# Test 1: Check if all scripts exist and are executable
log_info "Test 1: Checking script files..."
SCRIPTS=(
    "bootstrap-cluster.sh"
    "setup-secondary-ip.sh"
    "setup-haproxy.sh"
    "setup-haproxy-https.sh"
    "quick-start-full.sh"
    "update-app-dns-secondary.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [[ -f "$SCRIPT_DIR/$script" ]]; then
        if [[ -x "$SCRIPT_DIR/$script" ]]; then
            log_info "✓ $script exists and is executable"
        else
            log_error "✗ $script exists but is not executable"
        fi
    else
        log_error "✗ $script does not exist"
    fi
done

# Test 2: Check help output
log_info ""
log_info "Test 2: Checking help output..."

# Check bootstrap-cluster.sh help
if "$SCRIPT_DIR/bootstrap-cluster.sh" --help 2>&1 | grep -q "with-secondary-ip"; then
    log_info "✓ bootstrap-cluster.sh has --with-secondary-ip option"
else
    log_error "✗ bootstrap-cluster.sh missing --with-secondary-ip option"
fi

# Check quick-start-full.sh help
if "$SCRIPT_DIR/quick-start-full.sh" --help 2>&1 | grep -q "with-secondary-ip"; then
    log_info "✓ quick-start-full.sh has --with-secondary-ip option"
else
    log_error "✗ quick-start-full.sh missing --with-secondary-ip option"
fi

# Check setup-secondary-ip.sh help
if "$SCRIPT_DIR/setup-secondary-ip.sh" --help 2>&1 | grep -q "private-ip"; then
    log_info "✓ setup-secondary-ip.sh has proper options"
else
    log_error "✗ setup-secondary-ip.sh missing options"
fi

# Check setup-haproxy-https.sh help
if "$SCRIPT_DIR/setup-haproxy-https.sh" --help 2>&1 | grep -q "secondary-ip"; then
    log_info "✓ setup-haproxy-https.sh has secondary IP options"
else
    log_error "✗ setup-haproxy-https.sh missing secondary IP options"
fi

# Test 3: Check script syntax
log_info ""
log_info "Test 3: Checking script syntax..."

for script in "${SCRIPTS[@]}"; do
    if bash -n "$SCRIPT_DIR/$script" 2>/dev/null; then
        log_info "✓ $script has valid syntax"
    else
        log_error "✗ $script has syntax errors"
    fi
done

# Test 4: Check dependencies
log_info ""
log_info "Test 4: Checking script dependencies..."

# Check if scripts reference each other correctly
if grep -q "setup-secondary-ip.sh" "$SCRIPT_DIR/bootstrap-cluster.sh"; then
    log_info "✓ bootstrap-cluster.sh references setup-secondary-ip.sh"
else
    log_error "✗ bootstrap-cluster.sh does not reference setup-secondary-ip.sh"
fi

if grep -q "setup-haproxy-https.sh" "$SCRIPT_DIR/quick-start-full.sh"; then
    log_info "✓ quick-start-full.sh references setup-haproxy-https.sh"
else
    log_error "✗ quick-start-full.sh does not reference setup-haproxy-https.sh"
fi

# Summary
echo
log_info "Integration test complete!"
echo
echo "To use the secondary IP solution:"
echo "================================="
echo
echo "Option 1: Quick start with secondary IP (recommended):"
echo "  ./scripts/k8s/quick-start-full.sh --with-secondary-ip"
echo
echo "Option 2: Bootstrap with secondary IP:"
echo "  ./scripts/k8s/bootstrap-cluster.sh --with-secondary-ip"
echo "  ./scripts/k8s/setup-haproxy-https.sh"
echo
echo "Option 3: Add secondary IP to existing cluster:"
echo "  ./scripts/k8s/setup-secondary-ip.sh"
echo "  ./scripts/k8s/setup-haproxy-https.sh"
echo "  ./scripts/k8s/update-app-dns-secondary.sh"
echo
echo "Cost: ~\$3.60/month for the additional Elastic IP"
echo "Benefit: Full HTTPS support on port 443"