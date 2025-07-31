# IRSA (IAM Roles for Service Accounts) Implementation Guide

## Overview

This document describes our implementation of IRSA (IAM Roles for Service Accounts) for secure, credential-free AWS service access in our Kubernetes cluster. IRSA eliminates the need for hardcoded AWS credentials by using Kubernetes service account tokens to assume IAM roles.

## Architecture

### Core Components

1. **OIDC Provider**: S3-based OIDC issuer at `https://bf-kops-oidc-store.s3.il-central-1.amazonaws.com`
2. **Per-App IAM Roles**: Each application has a dedicated IAM role with minimal permissions
3. **Kubernetes Service Accounts**: Each app uses a service account with IRSA annotations
4. **AWS SDK v3**: Full compatibility with IRSA credential providers

### Security Model

- **Principle of Least Privilege**: Each app gets only the AWS permissions it needs
- **No Credential Storage**: No AWS keys stored in code, containers, or Kubernetes secrets
- **Time-Limited Access**: Local development uses 1-hour assumed role sessions
- **Service Isolation**: Each app has its own IAM role and Kubernetes service account

## OIDC Configuration

### OIDC Provider Details
- **Issuer URL**: `https://bf-kops-oidc-store.s3.il-central-1.amazonaws.com`
- **Client IDs**: `kubernetes.svc.default`
- **JWT Audience**: `kubernetes.svc.default`
- **AWS ARN**: `arn:aws:iam::363397505860:oidc-provider/bf-kops-oidc-store.s3.il-central-1.amazonaws.com`

### Recent Fixes (July 31, 2025)
1. **JWT Token Audience**: Fixed mismatch from `sts.amazonaws.com` to `kubernetes.svc.default`
2. **OIDC Client ID**: Added `kubernetes.svc.default` to provider client IDs
3. **Cluster Configuration**: Updated serviceAccountIssuer to use S3-based OIDC
4. **Trust Policies**: Corrected audience validation in all IAM roles

## Per-App IAM Structure

### Directory Layout
Each application should have an `aws/iam/` directory:

```
apps/{app-name}/aws/iam/
├── setup-iam.sh              # Creates/updates IAM role and policy
├── permissions-policy.json   # Minimal permissions for the app
├── role-policy.json          # Trust policy (OIDC-based)
└── local-dev-setup.sh        # Assume role for local development
```

### IAM Role Naming Convention
- **Role Name**: `{app-name}-app-role` (e.g., `gamani-app-role`)
- **Policy Name**: `{app-name}-app-policy` (e.g., `gamani-app-policy`)

## Trust Policy Template

Every app role uses this trust policy structure:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::363397505860:oidc-provider/bf-kops-oidc-store.s3.il-central-1.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "bf-kops-oidc-store.s3.il-central-1.amazonaws.com:sub": "system:serviceaccount:apps:{app-name}-service-account",
          "bf-kops-oidc-store.s3.il-central-1.amazonaws.com:aud": "kubernetes.svc.default"
        }
      }
    }
  ]
}
```

## Kubernetes Configuration

### Service Account Template

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {app-name}-service-account
  namespace: apps
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::363397505860:role/{app-name}-app-role
```

### Deployment Configuration

```yaml
spec:
  template:
    spec:
      serviceAccountName: {app-name}-service-account
      containers:
      - name: {app-name}
        env:
        - name: AWS_ROLE_ARN
          value: "arn:aws:iam::363397505860:role/{app-name}-app-role"
        - name: AWS_WEB_IDENTITY_TOKEN_FILE
          value: "/var/run/secrets/kubernetes.io/serviceaccount/token"
        - name: AWS_REGION
          value: "il-central-1"
```

## AWS SDK v3 Integration

### Migration from SDK v2

Our applications have been fully migrated to AWS SDK v3 for IRSA compatibility:

#### Before (SDK v2)
```javascript
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

const result = await dynamodb.get({
  TableName: 'my-table',
  Key: { id: '123' }
}).promise();
```

#### After (SDK v3)
```javascript
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const result = await docClient.send(new GetCommand({
  TableName: 'my-table',
  Key: { id: '123' }
}));
```

### Automatic Credential Detection

AWS SDK v3 automatically detects IRSA credentials when these environment variables are present:
- `AWS_ROLE_ARN`
- `AWS_WEB_IDENTITY_TOKEN_FILE`

No additional credential configuration is required in application code.

## Development Workflow

### Local Development Setup

#### Option 1: Use NPM Scripts (Recommended)
```bash
# Automatically handles credential setup
npm run dev:{app-name}
```

#### Option 2: Manual Setup
```bash
cd apps/{app-name}

# Assume role with minimal permissions (1-hour session)
./aws/iam/local-dev-setup.sh

# Start development server
npm run dev
```

#### Option 3: Development Wrapper
```bash
cd apps/{app-name}

# Combined credential setup and dev server start
./dev-with-creds.sh
```

### Creating IAM Infrastructure for New Apps

#### Automatic Setup (During Deployment)
```bash
# Deploy with automatic IAM setup
./scripts/k8s/deploy-app.sh {app-name} --setup-iam
```

#### Manual Setup
```bash
# Create IAM role and policy
apps/{app-name}/aws/iam/setup-iam.sh

# Validate setup
./scripts/k8s/deploy-app.sh {app-name} --build-only
```

### Updating Permissions

1. Edit `apps/{app-name}/aws/iam/permissions-policy.json`
2. Run `apps/{app-name}/aws/iam/setup-iam.sh` to update the policy
3. Restart application pods to pick up new permissions

## Production Deployment

### Validation Process

Our deployment scripts automatically validate IRSA setup:

```bash
# Validates before deployment
./scripts/k8s/deploy-app.sh {app-name}
```

**Validation Checks:**
- ✅ IAM role existence and configuration
- ✅ Service account setup with correct annotations
- ✅ AWS SDK v3 package compatibility
- ✅ IRSA environment variable configuration
- ✅ Trust policy OIDC provider compatibility

### Deployment Environment Variables

Each deployment automatically includes:
```yaml
env:
- name: AWS_ROLE_ARN
  value: "arn:aws:iam::363397505860:role/{app-name}-app-role"
- name: AWS_WEB_IDENTITY_TOKEN_FILE
  value: "/var/run/secrets/kubernetes.io/serviceaccount/token"
- name: AWS_REGION
  value: "il-central-1"
```

## Example: Gamani App Implementation

### IAM Permissions (`apps/gamani/aws/iam/permissions-policy.json`)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem", 
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": [
        "arn:aws:dynamodb:il-central-1:363397505860:table/gamani-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:il-central-1:363397505860:secret:gamani/*"
      ]
    }
  ]
}
```

### Service Account (`apps/gamani/k8s/service-account.yaml`)
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gamani-service-account
  namespace: apps
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::363397505860:role/gamani-app-role
```

### Application Code Integration
```javascript
// apps/gamani/src/services/aws-services.js
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');
const { SecretsManagerClient } = require('@aws-sdk/client-secrets-manager');

// IRSA credentials automatically detected
const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const secretsClient = new SecretsManagerClient({});

module.exports = { docClient, secretsClient };
```

## Troubleshooting

### Common Issues

#### 1. "Couldn't retrieve verification key from your identity provider"
**Cause**: JWT token audience mismatch
**Solution**: Verify OIDC provider client IDs include `kubernetes.svc.default`

```bash
# Check OIDC provider configuration
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::363397505860:oidc-provider/bf-kops-oidc-store.s3.il-central-1.amazonaws.com \
  --profile bf
```

#### 2. "User is not authorized to perform: sts:AssumeRoleWithWebIdentity"
**Cause**: Trust policy misconfiguration
**Solution**: Verify trust policy audience and subject match

```bash
# Check JWT token claims
kubectl exec -n apps deployment/{app-name} -- sh -c 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); echo $TOKEN | cut -d"." -f2 | base64 -d 2>/dev/null'
```

#### 3. Missing IAM Role
**Cause**: IAM infrastructure not created
**Solution**: Run IAM setup

```bash
# Create missing IAM infrastructure
./scripts/k8s/deploy-app.sh {app-name} --setup-iam
```

#### 4. Credential Expiration (Local Development)
**Cause**: 1-hour session timeout
**Solution**: Re-assume role

```bash
# Renew credentials
npm run dev:{app-name}
# or
cd apps/{app-name} && ./aws/iam/local-dev-setup.sh
```

### Diagnostic Commands

```bash
# Check IAM role exists
aws iam get-role --role-name {app-name}-app-role --profile bf

# Validate IRSA setup
./scripts/k8s/deploy-app.sh {app-name} --build-only

# Check service account annotations
kubectl get serviceaccount {app-name}-service-account -n apps -o yaml

# Verify environment variables in pod
kubectl exec -n apps deployment/{app-name} -- env | grep AWS_

# Test AWS API access from pod
kubectl exec -n apps deployment/{app-name} -- aws sts get-caller-identity
```

## Security Considerations

### Best Practices

1. **Minimal Permissions**: Only grant permissions actually used by the application
2. **Resource-Specific ARNs**: Use specific resource ARNs instead of wildcards when possible
3. **Regular Audits**: Review and update permissions as application requirements change
4. **Separate Environments**: Use different roles for different environments (dev/staging/prod)
5. **Time-Limited Local Access**: Local development sessions expire automatically

### Permission Boundaries

Consider using IAM permission boundaries for additional security:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "il-central-1"
        }
      }
    }
  ]
}
```

## Cost Optimization

IRSA provides several cost benefits:

1. **No NAT Gateway**: No need for expensive NAT Gateway for credential access
2. **No EC2 Instance Profile Permissions**: Master node doesn't need broad AWS permissions
3. **Reduced Secrets Manager Usage**: No stored credentials to rotate
4. **Simplified Operations**: Less infrastructure to manage and secure

## Migration Checklist

When migrating an existing app to IRSA:

- [ ] Upgrade to AWS SDK v3
- [ ] Create `aws/iam/` directory structure
- [ ] Define minimal permissions in `permissions-policy.json`
- [ ] Create trust policy with OIDC configuration
- [ ] Set up IAM role and policy
- [ ] Create Kubernetes service account
- [ ] Update deployment to use service account
- [ ] Add IRSA environment variables
- [ ] Test local development credential setup
- [ ] Verify production deployment
- [ ] Remove any hardcoded credentials
- [ ] Update documentation

## Future Enhancements

Potential improvements to consider:

1. **Cross-Account Access**: Support for accessing resources in other AWS accounts
2. **Permission Boundaries**: Implement organization-wide permission boundaries
3. **Automated Policy Generation**: Generate policies based on actual AWS API usage
4. **Integration Testing**: Automated tests for IRSA configuration
5. **Monitoring**: CloudTrail analysis for role usage and permission optimization