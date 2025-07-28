# Docker Deployment Guide for Sample App

This guide covers deploying the sample-app using Docker containers on AWS EC2 with cost optimization and production best practices.

## 🚀 Quick Start

### Local Development
```bash
# Clone and setup
git clone <your-repo>
cd sample-app

# Copy environment file
cp .env.example .env

# Start development environment
docker-compose up -d

# View logs
docker-compose logs -f
```

### Production Deployment
```bash
# On your EC2 instance
./deploy/docker-deploy.sh prod
```

## 📋 Architecture Overview

```
Internet → Route53 → EC2 Instance → Nginx → Docker Containers
                                   ├── sample-app (Node.js)
                                   ├── cron-tasks (Scheduled jobs)
                                   └── watchtower (Auto-updates)
```

## 💰 Cost Optimization

### Instance Recommendations
- **Development**: t3a.nano ($3.50/month)
- **Production**: t3a.small spot ($1.50/month)
- **High traffic**: t3a.medium spot ($3.00/month)

### Total Monthly Costs
- **Minimum**: $2/month (spot + Route53)
- **Typical**: $4-8/month
- **Savings**: 60-70% vs on-demand pricing

## 🔧 Setup Instructions

### 1. Server Setup
```bash
# Download and run EC2 setup
curl -O https://your-repo/deploy/setup-ec2-docker.sh
chmod +x setup-ec2-docker.sh
./setup-ec2-docker.sh
```

### 2. Application Deployment
```bash
# Clone repository
cd /var/www
git clone <your-repo> sample-app
cd sample-app

# Configure environment
cp .env.production.example .env.production
# Edit .env.production with your settings

# Deploy
./deploy/docker-deploy.sh prod
```

### 3. SSL Certificate
```bash
sudo certbot --nginx -d sample.vadimzak.com
```

### 4. Monitoring Setup
```bash
./deploy/setup-monitoring.sh
```

## 📊 Monitoring & Health Checks

### Automated Monitoring
- **Health checks**: Every 5 minutes
- **Auto-recovery**: Automatic service restart on failure
- **Resource monitoring**: Memory, disk, CPU usage
- **Log rotation**: Automatic cleanup

### Manual Monitoring
```bash
# Quick status check
~/status.sh

# Full dashboard
~/dashboard.sh

# View logs
docker-compose -f docker-compose.prod.yml logs -f

# Container stats
docker stats
```

## 🔄 Scheduled Tasks

The application includes a dedicated container for scheduled tasks:

- **Health checks**: Every 5 minutes
- **Cleanup**: Daily at 2 AM (removes records > 30 days)
- **Reports**: Weekly on Sundays at 3 AM

### Adding New Tasks
1. Create task in `cron/tasks/`
2. Add to `cron/scheduler.js`
3. Rebuild and deploy

## 🛡️ Security Features

### Application Security
- Helmet.js for security headers
- CORS configuration
- Rate limiting (API: 10 req/s, General: 50 req/s)
- Input validation and sanitization

### Infrastructure Security
- Non-root container user
- Security group restrictions
- SSL/TLS encryption
- Automated security updates

### Access Control
- IAM roles (no hardcoded credentials)
- SSH key authentication
- VPC security groups

## 🔄 Deployment Workflows

### Development Workflow
```bash
# Local development
docker-compose up -d

# Run tests
npm test

# Build and test production image
docker-compose -f docker-compose.prod.yml build
```

### Production Deployment
```bash
# Automated deployment
./deploy/docker-deploy.sh prod

# Manual steps
git pull
docker-compose -f docker-compose.prod.yml build
docker-compose -f docker-compose.prod.yml up -d
```

### Rollback Procedure
```bash
# Quick rollback to previous image
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml up -d

# Rollback to specific commit
git checkout <previous-commit>
./deploy/docker-deploy.sh prod
```

## 📈 Scaling Options

### Vertical Scaling
- Upgrade to larger instance type
- Increase memory limits in docker-compose.prod.yml

### Horizontal Scaling
- Deploy multiple instances
- Use Application Load Balancer
- Implement session storage (Redis)

### Database Scaling
- DynamoDB auto-scaling
- Read replicas for heavy read workloads

## 🚨 Troubleshooting

### Common Issues

**Container won't start**
```bash
# Check logs
docker-compose -f docker-compose.prod.yml logs

# Check container status
docker-compose -f docker-compose.prod.yml ps

# Restart services
docker-compose -f docker-compose.prod.yml restart
```

**Health check failures**
```bash
# Manual health check
curl http://localhost/health

# Check application logs
docker-compose -f docker-compose.prod.yml logs sample-app

# Check nginx logs
docker-compose -f docker-compose.prod.yml logs nginx
```

**High memory usage**
```bash
# Check container memory usage
docker stats

# Clean up unused images
docker system prune -f

# Restart memory-intensive containers
docker-compose -f docker-compose.prod.yml restart sample-app
```

**SSL certificate issues**
```bash
# Renew certificate
sudo certbot renew

# Test SSL configuration
sudo nginx -t

# Restart nginx
sudo systemctl restart nginx
```

### Log Files
- Application logs: `docker-compose logs`
- Nginx logs: `/var/log/nginx/`
- System logs: `/var/log/`
- Monitoring logs: `/var/log/sample-app/`

## 🔧 Configuration Files

### Environment Variables
- `.env` - Development
- `.env.production` - Production
- Environment-specific overrides in docker-compose files

### Key Configuration Files
- `Dockerfile` - Container definition
- `docker-compose.yml` - Development orchestration
- `docker-compose.prod.yml` - Production orchestration
- `nginx/nginx.prod.conf` - Production nginx configuration

## 📞 Support

### Useful Commands
```bash
# View all containers
docker ps -a

# Container logs
docker logs <container-id>

# Execute commands in container
docker exec -it <container-id> /bin/sh

# System monitoring
htop
df -h
free -h

# Network testing
curl -I http://localhost/health
nslookup sample.vadimzak.com
```

### Emergency Procedures
1. **Service down**: Run `~/status.sh` to diagnose
2. **High load**: Check `docker stats` and `htop`
3. **Disk full**: Run `docker system prune -f`
4. **Memory issues**: Restart containers
5. **SSL expiry**: Run `sudo certbot renew`

For additional support, check the logs and monitoring dashboard first, then consult the troubleshooting section above.