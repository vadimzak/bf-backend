#!/bin/bash
set -euo pipefail

# Script to install Kubernetes prerequisites (kubectl, kops, helm)
# Supports macOS and Linux

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Add local bin to PATH for this script
export PATH="$HOME/.local/bin:$PATH"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="darwin"
        ARCH="amd64"
        if [[ $(uname -m) == "arm64" ]]; then
            ARCH="arm64"
        fi
    elif [[ "$OSTYPE" == "linux"* ]]; then
        OS="linux"
        ARCH="amd64"
        if [[ $(uname -m) == "aarch64" ]]; then
            ARCH="arm64"
        fi
    else
        log_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
    log_info "Detected OS: $OS, Architecture: $ARCH"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/$1" ]]
}

# Install kubectl
install_kubectl() {
    if command_exists kubectl; then
        log_info "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
        return 0
    fi

    log_info "Installing kubectl..."
    
    # Get latest stable version
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    
    # Download kubectl
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
    
    # Verify checksum
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl.sha256"
    
    if [[ "$OS" == "darwin" ]]; then
        # macOS
        if ! shasum -a 256 -c kubectl.sha256; then
            log_error "kubectl checksum verification failed"
            rm -f kubectl kubectl.sha256
            exit 1
        fi
    else
        # Linux
        if ! echo "$(<kubectl.sha256) kubectl" | sha256sum --check; then
            log_error "kubectl checksum verification failed"
            rm -f kubectl kubectl.sha256
            exit 1
        fi
    fi
    
    chmod +x kubectl
    
    # Install to user's local bin directory
    mkdir -p "$HOME/.local/bin"
    mv kubectl "$HOME/.local/bin/"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_warning "Add $HOME/.local/bin to your PATH by adding this to your shell profile:"
        log_warning "export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
    
    rm -f kubectl.sha256
    log_info "kubectl installed successfully: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
}

# Install kops
install_kops() {
    if command_exists kops; then
        log_info "kops is already installed: $(kops version)"
        return 0
    fi

    log_info "Installing kops..."
    
    # Get latest version
    KOPS_VERSION=$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)
    
    # Download kops
    curl -Lo kops "https://github.com/kubernetes/kops/releases/download/${KOPS_VERSION}/kops-${OS}-${ARCH}"
    
    chmod +x kops
    
    # Install to user's local bin directory
    mkdir -p "$HOME/.local/bin"
    mv kops "$HOME/.local/bin/"
    
    log_info "kops installed successfully: $(kops version)"
}

# Install helm
install_helm() {
    if command_exists helm; then
        log_info "helm is already installed: $(helm version --short)"
        return 0
    fi

    log_info "Installing helm..."
    
    # Get installer script
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    
    # Run installer with custom install directory
    HELM_INSTALL_DIR="$HOME/.local/bin" ./get_helm.sh --no-sudo
    
    rm -f get_helm.sh
    log_info "helm installed successfully: $(helm version --short)"
}

# Check AWS CLI
check_aws_cli() {
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first:"
        log_error "  macOS: brew install awscli"
        log_error "  Linux: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html"
        exit 1
    fi
    
    log_info "AWS CLI is installed: $(aws --version)"
    
    # Check if bf profile exists
    if ! aws configure list --profile bf >/dev/null 2>&1; then
        log_error "AWS profile 'bf' not configured. Please run: aws configure --profile bf"
        exit 1
    fi
    
    log_info "AWS profile 'bf' is configured"
}

# Main installation
main() {
    log_info "Starting Kubernetes prerequisites installation..."
    
    detect_os
    check_aws_cli
    
    # Create temp directory for downloads
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Install tools
    install_kubectl
    install_helm
    install_kops
    
    # Cleanup
    cd - >/dev/null
    rm -rf "$TEMP_DIR"
    
    log_info "All prerequisites installed successfully!"
    
    # Verify installations
    echo
    log_info "Verification:"
    kubectl version --client --short 2>/dev/null || kubectl version --client
    kops version
    helm version --short
}

# Run main function
main "$@"