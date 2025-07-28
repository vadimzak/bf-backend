# AWS Deployment Guide for Sample NodeJS App

This guide will walk you through deploying the sample app to AWS at sample.vadimzak.com.

## Prerequisites

- AWS Account with Route 53 hosted zone for vadimzak.com
- AWS CLI configured with appropriate credentials
- Domain sample.vadimzak.com already in Route 53

## Step 1: Create DynamoDB Table

Run the DynamoDB creation script:

```bash
cd deploy
chmod +x create-dynamodb-table.sh
./create-dynamodb-table.sh
```

This creates a table named `sample-app-items` with on-demand billing.

## Step 2: Launch EC2 Instance

1. Go to AWS Console > EC2 > Launch Instance
2. Choose:
   - **AMI**: Amazon Linux 2
   - **Instance Type**: t2.micro (free tier)
   - **Key Pair**: Select or create one
   - **Security Group**: Create new with rules:
     - SSH (22) from your IP
     - HTTP (80) from anywhere
     - HTTPS (443) from anywhere

3. Launch the instance

## Step 3: Configure Route 53

1. Go to Route 53 > Hosted zones > vadimzak.com
2. Create an A record:
   - **Name**: sample
   - **Type**: A
   - **Value**: Your EC2 instance's public IP

## Step 4: Connect to EC2 and Setup

```bash
# Connect to your instance
ssh -i your-key.pem ec2-user@YOUR_EC2_IP

# Download and run setup script
curl -O https://raw.githubusercontent.com/yourusername/sample-app/main/deploy/setup-ec2.sh
chmod +x setup-ec2.sh
./setup-ec2.sh
```

## Step 5: Deploy the Application

```bash
# Clone your repository (or upload files)
cd /var/www
git clone https://github.com/yourusername/sample-app.git
cd sample-app

# Set up environment variables
cp .env.example .env
nano .env  # Add your AWS credentials

# Run deployment script
chmod +x deploy/deploy-app.sh
./deploy/deploy-app.sh
```

## Step 6: Configure SSL Certificate

```bash
sudo certbot --nginx -d sample.vadimzak.com
```

Follow the prompts to get a free Let's Encrypt SSL certificate.

## Step 7: IAM Role (Recommended)

Instead of using AWS credentials in .env, create an IAM role:

1. Go to IAM > Roles > Create Role
2. Choose EC2 as the trusted entity
3. Attach policy: `AmazonDynamoDBFullAccess` (or create custom policy)
4. Name: `sample-app-role`
5. Attach to your EC2 instance

Then remove AWS credentials from .env file.

## Verification

1. Check application: `pm2 status`
2. View logs: `pm2 logs sample-app`
3. Test endpoints:
   - https://sample.vadimzak.com
   - https://sample.vadimzak.com/health
   - https://sample.vadimzak.com/api

## Troubleshooting

- **502 Bad Gateway**: Check if app is running (`pm2 status`)
- **Connection refused**: Check security group rules
- **DynamoDB errors**: Verify IAM permissions
- **SSL issues**: Ensure domain points to EC2 IP

## Maintenance

- Update app: `git pull && npm ci && pm2 restart sample-app`
- View logs: `pm2 logs`
- Monitor: `pm2 monit`
- Nginx logs: `/var/log/nginx/`

## Cost Summary

- EC2 t2.micro: Free tier (12 months) then ~$8.35/month
- DynamoDB: Free tier (25GB forever)
- Route 53: $0.50/month
- Total: $0.50/month (first year), then ~$8.85/month