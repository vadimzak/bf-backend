#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE_NAME="test1-app-role"
POLICY_NAME="test1-app-policy"
AWS_PROFILE="bf"

echo "Setting up IAM role and policy for test1 app..."

# Check if role exists
if aws iam get-role --role-name "$ROLE_NAME" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    echo "Role $ROLE_NAME already exists, updating..."
    aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "file://$SCRIPT_DIR/role-policy.json" --profile "$AWS_PROFILE"
else
    echo "Creating role $ROLE_NAME..."
    aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "file://$SCRIPT_DIR/role-policy.json" --profile "$AWS_PROFILE"
fi

# Check if policy exists
POLICY_ARN="arn:aws:iam::363397505860:policy/$POLICY_NAME"
if aws iam get-policy --policy-arn "$POLICY_ARN" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    echo "Policy $POLICY_NAME already exists, creating new version..."
    aws iam create-policy-version --policy-arn "$POLICY_ARN" --policy-document "file://$SCRIPT_DIR/permissions-policy.json" --set-as-default --profile "$AWS_PROFILE"
else
    echo "Creating policy $POLICY_NAME..."
    aws iam create-policy --policy-name "$POLICY_NAME" --policy-document "file://$SCRIPT_DIR/permissions-policy.json" --profile "$AWS_PROFILE"
fi

# Attach policy to role
echo "Attaching policy to role..."
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" --profile "$AWS_PROFILE"

echo "IAM setup completed successfully!"
echo "Role ARN: arn:aws:iam::363397505860:role/$ROLE_NAME"