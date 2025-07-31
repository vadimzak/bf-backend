# Gamani Development Guide

## Quick Start

### For Local Development with Minimal Permissions

Use the development script that automatically sets up AWS credentials:

```bash
cd apps/gamani
./dev-with-creds.sh
```

This script will:
1. Assume the `gamani-app-role` with minimal DynamoDB permissions
2. Set up all required environment variables
3. Start the development server on http://localhost:3002

**Note**: Credentials expire every hour. Re-run the script when they expire.

### Manual Setup (Alternative)

If you prefer to set up credentials manually:

```bash
# Set up minimal permissions
eval "$(./aws/iam/local-dev-setup.sh eval)"

# Start development server
npm run dev
```

## Security Model

### Local Development
- Uses **minimal permissions** via IAM role assumption
- Only has access to `gamani-items` DynamoDB table
- Cannot access S3, EC2, or other AWS services
- Credentials expire after 1 hour for security

### Production
- Uses Kubernetes service account with IAM role mapping
- Same minimal permissions as local development
- No hardcoded credentials in deployment

## IAM Role Management

### One-time Setup
```bash
# Create the IAM role and policy (run once)
./aws/iam/setup-iam.sh
```

### Updating Permissions
Edit `aws/iam/permissions-policy.json` and run:
```bash
./aws/iam/setup-iam.sh  # Updates existing policy
```

## Development URLs
- **Local**: http://localhost:3002
- **Production**: https://gamani.vadimzak.com

## Environment Variables
See `.env.example` for all required environment variables.

## Troubleshooting

### "Missing credentials" Error
Run the development script: `./dev-with-creds.sh`

### "Access Denied" Error
The minimal permissions only allow access to:
- DynamoDB table: `gamani-items`
- Secrets Manager: `gamani/*` (if needed)

This is intentional for security.

### Credentials Expired
Re-run `./dev-with-creds.sh` to get fresh 1-hour credentials.