#!/bin/bash
set -euo pipefail

# Gamani App Local Development Credentials Setup
# This script assumes the gamani-app-role and exports temporary credentials

ROLE_NAME="gamani-app-role"
AWS_PROFILE="${AWS_PROFILE:-bf}"
EXTERNAL_ID="gamani-app-local-dev"
SESSION_NAME="gamani-local-dev-$(date +%Y%m%d-%H%M%S)"

echo "[LOCAL DEV] Setting up local development credentials for Gamani..."
echo "[LOCAL DEV] Role name: $ROLE_NAME"
echo "[LOCAL DEV] AWS Profile: $AWS_PROFILE"
echo "[LOCAL DEV] Session name: $SESSION_NAME"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

echo "[LOCAL DEV] Assuming role: $ROLE_ARN"

# Assume the role
CREDENTIALS=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "$SESSION_NAME" \
    --external-id "$EXTERNAL_ID" \
    --duration-seconds 3600 \
    --profile "$AWS_PROFILE" \
    --output json)

# Extract credentials
ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
SECRET_KEY=$(echo "$CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.Credentials.SessionToken')
EXPIRATION=$(echo "$CREDENTIALS" | jq -r '.Credentials.Expiration')

# Export credentials
export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
export AWS_SESSION_TOKEN="$SESSION_TOKEN"

echo ""
echo "[LOCAL DEV] Credentials set successfully!"
echo "[LOCAL DEV] Expiration: $EXPIRATION"
echo ""

# If called with 'eval' argument, output export statements
if [[ "${1:-}" == "eval" ]]; then
    echo "export AWS_ACCESS_KEY_ID='$ACCESS_KEY'"
    echo "export AWS_SECRET_ACCESS_KEY='$SECRET_KEY'"
    echo "export AWS_SESSION_TOKEN='$SESSION_TOKEN'"
    echo "# Credentials expire at: $EXPIRATION"
fi

echo "[WARNING] These credentials will expire in 1 hour."
echo "[WARNING] Re-run this script when credentials expire."
echo ""