# AWS SDK v3 Migration Guide

## Overview

This document outlines the complete migration from AWS SDK v2 to v3, implemented on July 31, 2025, to support IRSA (IAM Roles for Service Accounts) in Kubernetes.

## Migration Summary

### Packages Updated
```json
// Before (AWS SDK v2)
{
  "dependencies": {
    "aws-sdk": "^2.1400.0"
  }
}

// After (AWS SDK v3)
{
  "dependencies": {
    "@aws-sdk/client-dynamodb": "^3.857.0",
    "@aws-sdk/lib-dynamodb": "^3.857.0",
    "@aws-sdk/client-secrets-manager": "^3.857.0"
  }
}
```

### Code Changes

#### 1. Imports
```typescript
// Before (v2)
import AWS from 'aws-sdk';

// After (v3)
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, PutCommand, GetCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
```

#### 2. Client Configuration
```typescript
// Before (v2)
AWS.config.update({
  region: process.env.AWS_REGION || 'il-central-1'
});
const dynamodb = new AWS.DynamoDB.DocumentClient();
const secretsManager = new AWS.SecretsManager();

// After (v3)
const awsRegion = process.env.AWS_REGION || 'il-central-1';
const dynamoClient = new DynamoDBClient({ region: awsRegion });
const secretsManagerClient = new SecretsManagerClient({ region: awsRegion });

const dynamodb = DynamoDBDocumentClient.from(dynamoClient, {
  marshallOptions: {
    convertEmptyValues: false,
    removeUndefinedValues: true,
    convertClassInstanceToMap: false,
  },
  unmarshallOptions: {
    wrapNumbers: false,
  },
});
```

#### 3. Command Pattern
```typescript
// Before (v2)
const result = await dynamodb.scan({
  TableName: 'my-table',
  FilterExpression: 'userId = :userId',
  ExpressionAttributeValues: { ':userId': userId }
}).promise();

// After (v3)
const command = new ScanCommand({
  TableName: 'my-table',
  FilterExpression: 'userId = :userId',
  ExpressionAttributeValues: { ':userId': userId }
});
const result = await dynamodb.send(command);
```

## IRSA Integration

### Automatic Credential Detection
AWS SDK v3 automatically detects IRSA credentials when these environment variables are present:

```yaml
env:
- name: AWS_ROLE_ARN
  value: "arn:aws:iam::363397505860:role/gamani-app-role"
- name: AWS_WEB_IDENTITY_TOKEN_FILE
  value: "/var/run/secrets/kubernetes.io/serviceaccount/token"
```

### No Explicit Credential Configuration Needed
```typescript
// v3 automatically uses IRSA credentials - no config needed!
const dynamoClient = new DynamoDBClient({ region: awsRegion });
```

## Benefits of v3 + IRSA

1. **Security**: No hardcoded credentials in code or config
2. **Automatic Rotation**: Kubernetes handles token refresh
3. **Least Privilege**: Each app has minimal required permissions
4. **Tree Shaking**: Smaller bundle sizes with modular v3 packages
5. **Type Safety**: Better TypeScript support in v3
6. **Performance**: Faster initialization and lower memory usage

## References
- [AWS SDK v3 Documentation](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)