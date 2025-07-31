# New App Creation Guide

This guide provides step-by-step instructions for creating and deploying a new application in the bf-backend infrastructure.

## Prerequisites

- AWS CLI configured with `bf` profile
- kubectl configured for the k8s.vadimzak.com cluster
- Docker installed and running
- Node.js and npm installed

## Directory Structure

Each app follows this structure:
```
apps/your-app-name/
├── package.json                    # App dependencies and scripts
├── tsconfig.json                   # TypeScript configuration
├── Dockerfile                      # Container build instructions
├── src/
│   └── server.ts                   # Main server file
├── k8s/                            # Kubernetes manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── service-account.yaml
│   ├── ingress.yaml
│   └── kustomization.yaml
└── aws/
    └── iam/                        # IAM configuration
        ├── setup-iam.sh
        ├── permissions-policy.json
        ├── role-policy.json
        └── local-dev-setup.sh
```

## Step 1: Create Basic App Structure

### 1.1 Create App Directory
```bash
mkdir -p apps/your-app-name/src
cd apps/your-app-name
```

### 1.2 Create package.json
```json
{
  "name": "your-app-name",
  "version": "1.0.0",
  "description": "Description of your app",
  "main": "dist/server.js",
  "scripts": {
    "dev": "ts-node src/server.ts",
    "build": "tsc",
    "start": "node dist/server.js"
  },
  "dependencies": {
    "@aws-sdk/client-dynamodb": "^3.857.0",
    "@aws-sdk/lib-dynamodb": "^3.857.0",
    "express": "^4.21.1"
  },
  "devDependencies": {
    "@types/express": "^5.0.0",
    "@types/node": "^22.10.1",
    "ts-node": "^10.9.2",
    "typescript": "^5.7.2"
  }
}
```

### 1.3 Create tsconfig.json
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020"],
    "module": "commonjs",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### 1.4 Create Basic Server (src/server.ts)
```typescript
import express from 'express';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand } from '@aws-sdk/lib-dynamodb';

const app = express();
const PORT = process.env.PORT || 3000;

const dynamoClient = new DynamoDBClient({
  region: process.env.AWS_REGION || 'il-central-1'
});
const docClient = DynamoDBDocumentClient.from(dynamoClient);

const TABLE_NAME = 'your-app-name-items';

app.use(express.static('public'));

// Required health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Example DynamoDB endpoint
app.get('/api/items', async (req, res) => {
  try {
    const command = new ScanCommand({
      TableName: TABLE_NAME
    });
    
    const result = await docClient.send(command);
    res.json({
      items: result.Items || [],
      count: result.Count || 0
    });
  } catch (error) {
    console.error('Error scanning table:', error);
    res.status(500).json({ 
      error: 'Failed to scan table',
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});

// Main page
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Your App Name</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .container { max-width: 600px; }
            button { padding: 10px 20px; margin: 10px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Your App Name</h1>
            <p>Your app description here.</p>
            
            <button onclick="loadItems()">Load Items from DynamoDB</button>
            
            <div id="items" style="display: none;">
                <h3>Items:</h3>
                <div id="itemsList"></div>
            </div>
        </div>
        
        <script>
            async function loadItems() {
                try {
                    const response = await fetch('/api/items');
                    const data = await response.json();
                    
                    const itemsDiv = document.getElementById('items');
                    const itemsList = document.getElementById('itemsList');
                    
                    if (data.error) {
                        itemsList.innerHTML = '<p style="color: red;">Error: ' + data.error + '</p>';
                    } else {
                        itemsList.innerHTML = '<p>Count: ' + data.count + '</p><pre>' + JSON.stringify(data.items, null, 2) + '</pre>';
                    }
                    
                    itemsDiv.style.display = 'block';
                } catch (error) {
                    console.error('Error:', error);
                    alert('Failed to load items');
                }
            }
        </script>
    </body>
    </html>
  `);
});

app.listen(PORT, () => {
  console.log(`${process.env.npm_package_name || 'App'} server running on port ${PORT}`);
});
```

## Step 2: Create Dockerfile

Create a Dockerfile that works with the NX monorepo structure:

```dockerfile
# Build for your-app-name
FROM node:18-alpine

WORKDIR /app

# Copy app files from workspace
COPY apps/your-app-name/package*.json ./
COPY apps/your-app-name/tsconfig.json ./
COPY apps/your-app-name/src ./src

# Install all dependencies for build
RUN npm install
RUN npm run build
# Remove devDependencies after build
RUN npm prune --production

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodeuser -u 1001

# Set ownership
RUN chown -R nodeuser:nodejs /app

EXPOSE 3000

USER nodeuser

CMD ["npm", "start"]
```

## Step 3: Create Kubernetes Manifests

### 3.1 Create k8s Directory
```bash
mkdir -p k8s
```

### 3.2 Create Service Account (k8s/service-account.yaml)
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: your-app-name-service-account
  namespace: apps
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::363397505860:role/your-app-name-app-role
```

### 3.3 Create Deployment (k8s/deployment.yaml)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-app-name
  namespace: apps
  labels:
    app: your-app-name
spec:
  replicas: 1
  selector:
    matchLabels:
      app: your-app-name
  template:
    metadata:
      labels:
        app: your-app-name
    spec:
      serviceAccountName: your-app-name-service-account
      containers:
      - name: app
        image: 363397505860.dkr.ecr.il-central-1.amazonaws.com/your-app-name:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: NODE_ENV
          value: production
        - name: PORT
          value: "3000"
        - name: AWS_REGION
          value: "il-central-1"
        - name: AWS_ROLE_ARN
          value: "arn:aws:iam::363397505860:role/your-app-name-app-role"
        - name: AWS_WEB_IDENTITY_TOKEN_FILE
          value: "/var/run/secrets/kubernetes.io/serviceaccount/token"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
```

### 3.4 Create Service (k8s/service.yaml)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: your-app-name
  namespace: apps
  labels:
    app: your-app-name
spec:
  selector:
    app: your-app-name
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
    name: http
  type: ClusterIP
```

### 3.5 Create Ingress (k8s/ingress.yaml)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: your-app-name
  namespace: apps
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - your-app-name.vadimzak.com
    secretName: your-app-name-tls
  rules:
  - host: your-app-name.vadimzak.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: your-app-name
            port:
              number: 80
```

### 3.6 Create Kustomization (k8s/kustomization.yaml)
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: apps

resources:
  - deployment.yaml
  - service.yaml
  - service-account.yaml
  - ingress.yaml

commonLabels:
  app: your-app-name
  environment: production
```

## Step 4: Create IAM Configuration

### 4.1 Create IAM Directory
```bash
mkdir -p aws/iam
```

### 4.2 Create Permissions Policy (aws/iam/permissions-policy.json)
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
        "arn:aws:dynamodb:il-central-1:363397505860:table/your-app-name-items"
      ]
    }
  ]
}
```

### 4.3 Create Role Policy (aws/iam/role-policy.json)
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
          "bf-kops-oidc-store.s3.il-central-1.amazonaws.com:sub": "system:serviceaccount:apps:your-app-name-service-account",
          "bf-kops-oidc-store.s3.il-central-1.amazonaws.com:aud": "kubernetes.svc.default"
        }
      }
    }
  ]
}
```

### 4.4 Create IAM Setup Script (aws/iam/setup-iam.sh)
```bash
#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE_NAME="your-app-name-app-role"
POLICY_NAME="your-app-name-app-policy"
AWS_PROFILE="bf"

echo "Setting up IAM role and policy for your-app-name app..."

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
```

### 4.5 Create Local Dev Setup (aws/iam/local-dev-setup.sh)
```bash
#!/bin/bash

set -euo pipefail

ROLE_NAME="your-app-name-app-role"
ROLE_ARN="arn:aws:iam::363397505860:role/$ROLE_NAME"
SESSION_NAME="your-app-name-local-dev-$(date +%s)"
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
```

### 4.6 Make Scripts Executable
```bash
chmod +x aws/iam/setup-iam.sh
chmod +x aws/iam/local-dev-setup.sh
```

## Step 5: Create DynamoDB Table (Optional)

If your app needs a DynamoDB table:

```bash
aws dynamodb create-table \
    --table-name your-app-name-items \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region il-central-1 \
    --profile bf
```

Add some test data:
```bash
aws dynamodb put-item \
    --table-name your-app-name-items \
    --item '{"id": {"S": "1"}, "name": {"S": "Test Item 1"}, "description": {"S": "First test item"}}' \
    --region il-central-1 \
    --profile bf
```

## Step 6: Deploy the Application

### 6.1 Setup IAM (First Time Only)
```bash
# From your app directory
./aws/iam/setup-iam.sh
```

### 6.2 Build and Deploy
```bash
# From project root
./scripts/k8s/deploy-app.sh your-app-name
```

Or use the configure-apps script for automated setup:
```bash
# Configure all apps (builds images, generates manifests)
./scripts/k8s/configure-apps.sh

# Apply manifests
kubectl apply -k apps/your-app-name/k8s/
```

### 6.3 Verify Deployment
```bash
# Check pod status
kubectl get pods -n apps | grep your-app-name

# Check logs
kubectl logs -n apps deployment/your-app-name

# Test health endpoint
curl https://your-app-name.vadimzak.com/health
```

## Step 7: Local Development

### 7.1 Install Dependencies
```bash
npm install
```

### 7.2 Setup Local Credentials
```bash
# Assume IAM role for local development
./aws/iam/local-dev-setup.sh

# Or use eval to set environment
eval $(./aws/iam/local-dev-setup.sh eval)
```

### 7.3 Run Locally
```bash
npm run dev
```

## Step 8: DNS Configuration

The DNS for `your-app-name.vadimzak.com` should automatically be configured if you're using the secondary IP setup. If not, you may need to update DNS records to point to:

- **With Secondary IP**: `51.84.16.238` (for HTTPS on port 443)
- **Without Secondary IP**: Use the master node IP with port 30443

## Troubleshooting

### Common Issues

1. **Pod not starting**: Check deployment logs and ensure Docker image builds correctly
2. **Credentials error**: Verify IAM role setup and IRSA configuration
3. **Health check failing**: Ensure `/health` endpoint returns 200 status
4. **DNS not resolving**: Check if DNS records are properly configured
5. **SSL certificate issues**: Wait for cert-manager to provision certificates (can take a few minutes)

### Debug Commands

```bash
# Check pod details
kubectl describe pod -n apps <pod-name>

# Check pod logs
kubectl logs -n apps deployment/your-app-name

# Check service account
kubectl get serviceaccount your-app-name-service-account -n apps -o yaml

# Check ingress
kubectl get ingress -n apps your-app-name

# Test internal connectivity
kubectl exec -n apps deployment/your-app-name -- curl localhost:3000/health
```

## Security Best Practices

1. **Minimal IAM Permissions**: Only grant permissions your app actually needs
2. **No Hardcoded Credentials**: Always use IRSA for AWS access
3. **Health Checks**: Always implement `/health` endpoint for liveness/readiness probes
4. **Resource Limits**: Set appropriate CPU and memory limits
5. **Non-root User**: Run containers as non-root user (already configured in Dockerfile)
6. **HTTPS Only**: All apps should use HTTPS with valid certificates

## Next Steps

After deploying your app:

1. **Monitor**: Check logs and metrics in monitoring dashboards
2. **Scale**: Adjust replicas in deployment.yaml if needed
3. **Optimize**: Review resource usage and adjust limits/requests
4. **Backup**: Consider backup strategies for DynamoDB tables
5. **Documentation**: Update this guide with any app-specific requirements

Your app should now be accessible at `https://your-app-name.vadimzak.com`!