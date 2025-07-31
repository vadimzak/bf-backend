#!/bin/bash
set -euo pipefail

# Gamani App IAM Role Setup
# This script creates or updates the IAM role for the Gamani application

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE_NAME="gamani-app-role"
POLICY_NAME="gamani-app-policy"
AWS_PROFILE="${AWS_PROFILE:-bf}"
AWS_REGION="${AWS_REGION:-il-central-1}"

echo "🔧 [IAM SETUP] Setting up IAM role for Gamani app..."
echo "🔧 [IAM SETUP] Role name: $ROLE_NAME"
echo "🔧 [IAM SETUP] Policy name: $POLICY_NAME"
echo "🔧 [IAM SETUP] AWS Profile: $AWS_PROFILE"
echo "🔧 [IAM SETUP] AWS Region: $AWS_REGION"

# Function to check if role exists
role_exists() {
    aws iam get-role --role-name "$ROLE_NAME" --profile "$AWS_PROFILE" >/dev/null 2>&1
}

# Function to check if policy exists
policy_exists() {
    aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text):policy/$POLICY_NAME" --profile "$AWS_PROFILE" >/dev/null 2>&1
}

# Create or update the IAM policy
echo "🔧 [IAM SETUP] Creating/updating IAM policy..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"

if policy_exists; then
    echo "✅ [IAM SETUP] Policy exists, creating new version..."
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document "file://$SCRIPT_DIR/permissions-policy.json" \
        --set-as-default \
        --profile "$AWS_PROFILE"
    echo "✅ [IAM SETUP] Policy updated with new version"
else
    echo "🔧 [IAM SETUP] Creating new policy..."
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document "file://$SCRIPT_DIR/permissions-policy.json" \
        --description "Minimal permissions for Gamani application" \
        --profile "$AWS_PROFILE"
    echo "✅ [IAM SETUP] Policy created: $POLICY_ARN"
fi

# Create or update the IAM role
if role_exists; then
    echo "✅ [IAM SETUP] Role exists, updating trust policy..."
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document "file://$SCRIPT_DIR/role-policy.json" \
        --profile "$AWS_PROFILE"
    echo "✅ [IAM SETUP] Role trust policy updated"
else
    echo "🔧 [IAM SETUP] Creating new role..."
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "file://$SCRIPT_DIR/role-policy.json" \
        --description "Application role for Gamani with minimal permissions" \
        --profile "$AWS_PROFILE"
    echo "✅ [IAM SETUP] Role created: $ROLE_NAME"
fi

# Attach the policy to the role
echo "🔧 [IAM SETUP] Attaching policy to role..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN" \
    --profile "$AWS_PROFILE"
echo "✅ [IAM SETUP] Policy attached to role"

# Display role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --profile "$AWS_PROFILE" --query Role.Arn --output text)
echo ""
echo "✅ [IAM SETUP] IAM setup completed successfully!"
echo "✅ [IAM SETUP] Role ARN: $ROLE_ARN"
echo ""
echo "📋 [IAM SETUP] Next steps:"
echo "   1. Run ./local-dev-setup.sh to assume this role for local development"
echo "   2. Configure Kubernetes service account to use this role in production"
echo ""