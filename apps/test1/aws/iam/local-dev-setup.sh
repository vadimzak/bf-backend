#!/bin/bash

set -euo pipefail

ROLE_NAME="test1-app-role"
ROLE_ARN="arn:aws:iam::363397505860:role/$ROLE_NAME"
SESSION_NAME="test1-local-dev-$(date +%s)"
AWS_PROFILE="bf"

echo "Assuming role for local development..."

# Assume role and get credentials
TEMP_CREDS=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "$SESSION_NAME" \
    --duration-seconds 3600 \
    --profile "$AWS_PROFILE" \
    --output json)

# Extract credentials
export AWS_ACCESS_KEY_ID=$(echo "$TEMP_CREDS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$TEMP_CREDS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$TEMP_CREDS" | jq -r '.Credentials.SessionToken')
export AWS_REGION="il-central-1"

echo "Credentials set for 1 hour. You can now run: npm run dev"

# If "eval" argument is passed, just export the variables for eval
if [ "${1:-}" = "eval" ]; then
    echo "export AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID'"
    echo "export AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY'"
    echo "export AWS_SESSION_TOKEN='$AWS_SESSION_TOKEN'"
    echo "export AWS_REGION='$AWS_REGION'"
fi