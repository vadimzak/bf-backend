# AWS Deployment Plan for NodeJS Prototypes
## Cost-Optimized Architecture for Pre-Seed Startup

### Executive Summary
**Total Monthly Cost: $0 - $5** (staying within AWS Free Tier limits)
**Time to Deploy: 4-6 hours**
**Breakeven Point: ~1000 daily active users**

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        CloudFront                           │
│                    (CDN - Free Tier)                        │
│                         ↓                                   │
│  ┌────────────────────────────────────────────────────┐    │
│  │               Route 53 (DNS)                        │    │
│  │          ($0.50/month per hosted zone)              │    │
│  └────────────────────────────────────────────────────┘    │
│                         ↓                                   │
│  ┌────────────────────────────────────────────────────┐    │
│  │         Application Load Balancer                   │    │
│  │              (Free Tier: 750 hrs)                   │    │
│  └────────────────────────────────────────────────────┘    │
│                         ↓                                   │
│  ┌─────────────────┬─────────────────┬────────────────┐    │
│  │   EC2 t2.micro  │   EC2 t2.micro  │  EC2 t2.micro  │    │
│  │    (App 1)      │    (App 2)      │   (App 3)      │    │
│  │   Free Tier     │   Free Tier     │  Free Tier     │    │
│  └─────────────────┴─────────────────┴────────────────┘    │
│                         ↓                                   │
│  ┌────────────────────────────────────────────────────┐    │
│  │              DynamoDB                               │    │
│  │    (25 GB storage + 25 RCU/WCU free)               │    │
│  └────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │              S3 Bucket                              │    │
│  │    (5 GB storage free for 12 months)               │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Service Selection & Cost Breakdown

### Core Services (Monthly Costs)

| Service | Purpose | Free Tier Limits | Monthly Cost | Why This Service? |
|---------|---------|------------------|--------------|-------------------|
| **EC2 t2.micro** | NodeJS hosting | 750 hrs/month (12 months) | **$0** | Most flexible, can run multiple apps on one instance |
| **DynamoDB** | NoSQL Database | 25 GB + 25 RCU/WCU | **$0** | Serverless, scales to zero, perfect for prototypes |
| **Route 53** | DNS Management | No free tier | **$0.50** | Required for custom domain |
| **CloudFront** | CDN | 1 TB transfer/month | **$0** | Improves performance, reduces EC2 load |
| **S3** | Static assets | 5 GB storage (12 months) | **$0** | Store uploads, logs, backups |
| **ALB** | Load Balancer | 750 hrs/month (12 months) | **$0** | Route to multiple apps on same EC2 |

**Total: $0.50/month** (only Route 53 DNS hosting)

### Additional Services (All Free)

- **CloudWatch**: Basic monitoring (free tier)
- **IAM**: Security management (always free)
- **VPC**: Network isolation (always free)
- **Elastic IPs**: 1 free when attached to running instance

---

## 3. Deployment Architecture

### Option A: Single EC2 Instance (Recommended for Start)
```bash
# EC2 t2.micro instance running:
- Node.js App 1 (port 3001)
- Node.js App 2 (port 3002)
- Node.js App 3 (port 3003)
- Nginx as reverse proxy
- PM2 for process management
```

**Benefits:**
- Maximum free tier utilization
- Simple management
- Easy local development mirror

### Option B: Container-Based (When Ready to Scale)
```bash
# Same EC2 instance running:
- Docker
- Docker Compose
- All apps in containers
```

---

## 4. Implementation Guide

### Phase 1: Initial Setup (2 hours)

1. **Launch EC2 Instance**
```bash
# User data script for EC2
#!/bin/bash
sudo yum update -y
sudo yum install -y nodejs npm nginx git
sudo npm install -g pm2
sudo systemctl start nginx
sudo systemctl enable nginx
```

2. **Configure Security Group**
```
- SSH (22): Your IP only
- HTTP (80): 0.0.0.0/0
- HTTPS (443): 0.0.0.0/0
```

3. **Setup Nginx Configuration**
```nginx
# /etc/nginx/conf.d/apps.conf
server {
    listen 80;
    server_name app1.yourdomain.com;
    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

# Repeat for app2, app3 with different ports/subdomains
```

### Phase 2: Database Setup (30 minutes)

1. **Create DynamoDB Tables**
```javascript
// Free tier friendly settings
{
    TableName: 'prototype_data',
    BillingMode: 'PROVISIONED',
    ProvisionedThroughput: {
        ReadCapacityUnits: 5,  // Well within free tier
        WriteCapacityUnits: 5
    }
}
```

2. **IAM Role for EC2**
```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:Query",
            "dynamodb:Scan"
        ],
        "Resource": "arn:aws:dynamodb:*:*:table/prototype_*"
    }]
}
```

### Phase 3: Domain & SSL Setup (1 hour)

1. **Route 53 Configuration**
```
A Record: yourdomain.com → EC2 Elastic IP
A Record: *.yourdomain.com → EC2 Elastic IP
```

2. **Free SSL with Certbot**
```bash
sudo amazon-linux-extras install epel -y
sudo yum install certbot python-certbot-nginx -y
sudo certbot --nginx -d yourdomain.com -d *.yourdomain.com
```

### Phase 4: Deployment Pipeline (1 hour)

**Simple GitHub Actions (Free tier: 2000 minutes/month)**
```yaml
name: Deploy to AWS
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Deploy to EC2
        env:
          PRIVATE_KEY: ${{ secrets.EC2_SSH_KEY }}
          HOST: ${{ secrets.EC2_HOST }}
        run: |
          echo "$PRIVATE_KEY" > private_key.pem
          chmod 600 private_key.pem
          scp -i private_key.pem -r ./app1 ec2-user@$HOST:/home/ec2-user/
          ssh -i private_key.pem ec2-user@$HOST "cd /home/ec2-user/app1 && npm install && pm2 restart app1"
```

---

## 5. Monitoring & Backup Strategy

### Free Monitoring Stack
1. **CloudWatch Basic Metrics** (Free)
   - CPU, Network, Disk usage
   - Basic alarms (10 free)

2. **Uptime Monitoring**
   - UptimeRobot (50 monitors free)
   - StatusCake (10 tests free)

3. **Application Monitoring**
   ```javascript
   // Simple health check endpoint
   app.get('/health', (req, res) => {
     res.json({
       status: 'ok',
       timestamp: new Date(),
       memory: process.memoryUsage(),
       uptime: process.uptime()
     });
   });
   ```

### Backup Strategy (Free)
1. **Database**: DynamoDB Point-in-time recovery (free for 7 days)
2. **Code**: GitHub (unlimited private repos)
3. **Data**: S3 lifecycle policies to Glacier (extremely cheap)

---

## 6. Scaling Triggers & Migration Path

### When to Scale (Monthly Metrics)
| Metric | Current Limit | Action Required | New Monthly Cost |
|--------|---------------|-----------------|------------------|
| Users | < 1,000 | None | $0.50 |
| Requests | < 100k | None | $0.50 |
| Storage | < 25 GB | None | $0.50 |
| **Users** | **> 1,000** | **Add EC2 instance** | **~$10** |
| **Requests** | **> 500k** | **Add CloudFront** | **~$20** |
| **Storage** | **> 25 GB** | **DynamoDB on-demand** | **~$30** |

### Migration Path to Production

1. **Month 1-3**: Single EC2 t2.micro ($0.50/month)
2. **Month 4-6**: Add second EC2 + RDS ($25/month)
3. **Month 7-12**: ECS Fargate + Aurora Serverless ($50-100/month)
4. **Year 2**: Full Kubernetes on EKS ($200+/month)

---

## 7. Security Checklist (All Free)

- [ ] Enable MFA on AWS root account
- [ ] Create IAM users with minimal permissions
- [ ] Enable CloudTrail (free for 90 days)
- [ ] Configure Security Groups (deny by default)
- [ ] Enable VPC Flow Logs to S3
- [ ] Use Secrets Manager free tier (or .env files initially)
- [ ] Enable GuardDuty (30-day free trial)
- [ ] Configure fail2ban on EC2

---

## 8. Common Pitfalls to Avoid

1. **Data Transfer Costs**
   - Use CloudFront to minimize EC2 outbound
   - Keep assets in same region as compute

2. **Hidden Costs**
   - Elastic IP when instance is stopped ($3.60/month)
   - NAT Gateway ($45/month) - use NAT instance instead
   - Unused EBS volumes

3. **Free Tier Gotchas**
   - 750 hours = 1 instance 24/7 OR 2 instances 12/7
   - Free tier expires after 12 months
   - Some services count per-region

---

## 9. Quick Start Commands

```bash
# 1. Launch EC2 (AWS CLI)
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro \
  --key-name your-key \
  --security-group-ids sg-xxxxxx \
  --user-data file://setup.sh

# 2. Create DynamoDB Table
aws dynamodb create-table \
  --table-name prototype_data \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

# 3. Setup Route 53
aws route53 create-hosted-zone --name yourdomain.com

# 4. Deploy App
scp -r ./app1 ec2-user@your-ip:/home/ec2-user/
ssh ec2-user@your-ip "cd app1 && npm install && pm2 start index.js --name app1"
```

---

## 10. Alternative Approaches

### If You Want Even Cheaper ($0/month)

1. **Vercel/Netlify** for frontend (generous free tier)
2. **MongoDB Atlas** free tier (512MB)
3. **Heroku** free tier (if still available in your region)
4. **Railway** ($5 credit/month)

### When to Use These Alternatives
- Pure API/frontend apps without complex backend
- Prototype validation before AWS investment
- Team not comfortable with AWS

---

## Summary

This architecture provides:
- **Professional deployment** for $0.50/month
- **Room for 10,000+ users** before scaling
- **Easy migration path** as you grow
- **No vendor lock-in** (can move to any VPS)
- **Production-ready security** at minimal cost

**Next Steps:**
1. Create AWS account and enable MFA
2. Launch t2.micro instance in us-east-1 (cheapest)
3. Follow the setup guide above
4. Deploy your first app within 2 hours

Remember: Start simple, measure everything, scale only when necessary. Your infrastructure should grow with your revenue, not before it.