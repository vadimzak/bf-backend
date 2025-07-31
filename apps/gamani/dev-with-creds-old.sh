#!/bin/bash
set -euo pipefail

# Gamani Development Server with Minimal Permissions
# This script sets up AWS credentials and starts the development server

echo "[DEV] Setting up development environment for Gamani..."

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up AWS credentials
echo "[DEV] Assuming IAM role for minimal permissions..."
eval "$(${SCRIPT_DIR}/aws/iam/local-dev-setup.sh eval)"

# Verify credentials are set
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    echo "[ERROR] Failed to set AWS credentials"
    exit 1
fi

echo "[DEV] AWS credentials configured with minimal permissions"
echo "[DEV] Access Key: ${AWS_ACCESS_KEY_ID:0:20}..."

# Set environment for development
export NODE_ENV=development
export PORT=3002
export AWS_REGION=il-central-1
export AWS_DEFAULT_REGION=il-central-1
export DYNAMODB_TABLE_NAME=gamani-items

echo "[DEV] Starting development server..."
echo "[DEV] Server will be available at: http://localhost:3002"
echo "[DEV] Credentials expire in 1 hour - re-run this script when needed"
echo ""

# Start the development server
npm run dev