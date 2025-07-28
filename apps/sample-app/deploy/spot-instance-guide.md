# AWS Spot Instance Deployment Guide

This guide shows how to deploy the sample-app using AWS Spot Instances for maximum cost savings (60-70% cheaper than on-demand).

## Prerequisites

1. AWS CLI configured with appropriate permissions
2. IAM role for EC2 instances with DynamoDB access
3. Security group configured with ports 22, 80, 443
4. Key pair for SSH access
5. Route 53 hosted zone for your domain

## Step 1: Create IAM Role

```bash
# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name sample-app-ec2-role \
  --assume-role-policy-document file://trust-policy.json

# Attach DynamoDB policy
aws iam attach-role-policy \
  --role-name sample-app-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name sample-app-ec2-role

# Add role to instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name sample-app-ec2-role \
  --role-name sample-app-ec2-role
```

## Step 2: Create Security Group

```bash
# Create security group
aws ec2 create-security-group \
  --group-name sample-app-sg \
  --description "Security group for sample-app"

# Add rules (replace sg-xxxxxxxxx with your security group ID)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

## Step 3: Update Launch Template

1. Edit `aws-spot-template.json`
2. Replace placeholders:
   - `sg-xxxxxxxxx` with your security group ID
   - `your-key-pair` with your EC2 key pair name
   - `ami-0c02fb55956c7d316` with latest Amazon Linux 2 AMI in your region

## Step 4: Create Launch Template

```bash
aws ec2 create-launch-template \
  --cli-input-json file://aws-spot-template.json
```

## Step 5: Request Spot Instance

```bash
# Request spot instance with launch template
aws ec2 request-spot-instances \
  --spot-price "0.02" \
  --instance-count 1 \
  --type "one-time" \
  --launch-specification '{
    "LaunchTemplateName": "sample-app-spot-template",
    "LaunchTemplateVersion": "$Latest"
  }'
```

## Step 6: Alternative - Create Spot Fleet

For better availability, use a spot fleet:

```bash
# Create spot fleet configuration
cat > spot-fleet-config.json <<EOF
{
  "SpotFleetRequestConfig": {
    "IamFleetRole": "arn:aws:iam::YOUR-ACCOUNT:role/aws-ec2-spot-fleet-tagging-role",
    "AllocationStrategy": "diversified",
    "TargetCapacity": 1,
    "SpotPrice": "0.02",
    "LaunchTemplateConfigs": [
      {
        "LaunchTemplateSpecification": {
          "LaunchTemplateName": "sample-app-spot-template",
          "Version": "$Latest"
        },
        "Overrides": [
          {
            "InstanceType": "t3a.small",
            "AvailabilityZone": "us-east-1a"
          },
          {
            "InstanceType": "t3a.small",
            "AvailabilityZone": "us-east-1b"
          },
          {
            "InstanceType": "t3.small",
            "AvailabilityZone": "us-east-1a"
          }
        ]
      }
    ],
    "TerminateInstancesWithExpiration": true,
    "Type": "maintain"
  }
}
EOF

# Request spot fleet
aws ec2 request-spot-fleet \
  --spot-fleet-request-config file://spot-fleet-config.json
```

## Step 7: Setup Application

Once the instance is running:

```bash
# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=sample-app-spot" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# SSH to instance
ssh -i your-key.pem ec2-user@$INSTANCE_IP

# On the instance:
cd /var/www
git clone YOUR_REPO_URL sample-app
cd sample-app

# Create production environment file
cp .env.example .env.production
# Edit .env.production with your settings (no AWS credentials needed - using IAM role)

# Deploy
./deploy/docker-deploy.sh prod
```

## Step 8: Configure DNS

```bash
# Update Route 53 record
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "sample.vadimzak.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$INSTANCE_IP'"}]
      }
    }]
  }'
```

## Step 9: Setup SSL

```bash
# On the instance
sudo certbot --nginx -d sample.vadimzak.com --non-interactive --agree-tos --email your-email@example.com
```

## Spot Instance Management

### Monitor Spot Instance
```bash
# Check spot price history
aws ec2 describe-spot-price-history \
  --instance-types t3a.small \
  --product-descriptions "Linux/UNIX" \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)

# Check spot interruption warnings
curl -s http://169.254.169.254/latest/meta-data/spot/instance-action || echo "No interruption warning"
```

### Handle Spot Interruptions

Add this to your monitoring script:

```bash
#!/bin/bash
# Check for spot interruption
if curl -s http://169.254.169.254/latest/meta-data/spot/instance-action; then
  echo "Spot interruption detected - gracefully shutting down"
  cd /var/www/sample-app
  docker-compose -f docker-compose.prod.yml down
  # Optionally trigger a new spot instance request
fi
```

## Cost Comparison

| Instance Type | On-Demand | Spot Price (avg) | Monthly Savings |
|---------------|-----------|------------------|-----------------|
| t3a.small     | $15.33    | $4.60           | $10.73 (70%)    |
| t3.small      | $18.40    | $5.52           | $12.88 (70%)    |
| t3a.nano      | $3.83     | $1.15           | $2.68 (70%)     |

**Total monthly cost with spot instances: ~$2-5/month**

## Best Practices

1. **Use multiple AZs**: Spread across availability zones for better availability
2. **Monitor prices**: Set up CloudWatch alarms for price spikes
3. **Graceful shutdown**: Handle interruption notifications properly
4. **Data backup**: Keep important data in S3 or RDS
5. **Auto-recovery**: Set up scripts to launch new instances automatically

## Troubleshooting

- **Spot request failed**: Check bid price and try different instance types
- **Instance terminated**: Review spot price history and adjust bid
- **Application not starting**: Check user data logs in `/var/log/cloud-init-output.log`
- **DNS not resolving**: Verify Route 53 record and TTL settings