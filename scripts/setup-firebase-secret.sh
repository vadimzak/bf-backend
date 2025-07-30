#!/bin/bash

# Setup Firebase service account secret in AWS Secrets Manager
# Usage: ./scripts/setup-firebase-secret.sh <path-to-service-account.json>

set -euo pipefail

# Configuration
SECRET_NAME="gamani/firebase/service-account"
AWS_REGION="il-central-1"
AWS_PROFILE="bf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up Firebase service account secret in AWS Secrets Manager${NC}"

# Check if service account file is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Please provide the path to your Firebase service account JSON file${NC}"
    echo "Usage: $0 <path-to-service-account.json>"
    echo ""
    echo "Example:"
    echo "  $0 ~/Downloads/vadimzak-com-firebase-adminsdk-xxxxx.json"
    exit 1
fi

SERVICE_ACCOUNT_FILE="$1"

# Check if file exists
if [ ! -f "$SERVICE_ACCOUNT_FILE" ]; then
    echo -e "${RED}Error: Service account file not found: $SERVICE_ACCOUNT_FILE${NC}"
    exit 1
fi

# Validate JSON file
if ! jq empty "$SERVICE_ACCOUNT_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON file: $SERVICE_ACCOUNT_FILE${NC}"
    exit 1
fi

# Extract project ID from service account for validation
PROJECT_ID=$(jq -r '.project_id' "$SERVICE_ACCOUNT_FILE")
echo -e "${YELLOW}Firebase Project ID: $PROJECT_ID${NC}"

# Create or update the secret
echo "Creating/updating secret: $SECRET_NAME"

if aws secretsmanager describe-secret \
    --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    >/dev/null 2>&1; then
    
    echo "Secret already exists. Updating..."
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string file://"$SERVICE_ACCOUNT_FILE" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        >/dev/null
    
    echo -e "${GREEN}✅ Secret updated successfully${NC}"
else
    echo "Creating new secret..."
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Firebase service account for Gamani application" \
        --secret-string file://"$SERVICE_ACCOUNT_FILE" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        >/dev/null
    
    echo -e "${GREEN}✅ Secret created successfully${NC}"
fi

echo ""
echo -e "${GREEN}Firebase service account secret is now stored in AWS Secrets Manager${NC}"
echo "Secret name: $SECRET_NAME"
echo "Region: $AWS_REGION"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Update your application to fetch the secret"
echo "2. Ensure your application has permission to read this secret"
echo "3. Deploy the updated application"