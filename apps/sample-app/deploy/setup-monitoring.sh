#!/bin/bash

# Setup monitoring and auto-recovery for sample-app

set -e

echo "🔧 Setting up monitoring and auto-recovery..."

# Create monitoring log directory
sudo mkdir -p /var/log/sample-app
sudo chown ec2-user:ec2-user /var/log/sample-app

# Copy monitoring script to system location
sudo cp /var/www/sample-app/deploy/monitoring.sh /usr/local/bin/sample-app-monitor
sudo chmod +x /usr/local/bin/sample-app-monitor

# Setup cron job for monitoring (every 5 minutes)
echo "Setting up cron job for health monitoring..."
(crontab -l 2>/dev/null || echo "") | grep -v "sample-app-monitor" | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/sample-app-monitor >> /var/log/sample-app/cron.log 2>&1") | crontab -

# Setup logrotate for monitoring logs
sudo tee /etc/logrotate.d/sample-app > /dev/null <<EOF
/var/log/sample-app/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su ec2-user ec2-user
}
EOF

# Create CloudWatch log group (if AWS CLI is available)
if command -v aws >/dev/null 2>&1; then
    echo "Creating CloudWatch log group..."
    aws logs create-log-group --log-group-name "/aws/ec2/sample-app" 2>/dev/null || echo "Log group might already exist"
    aws logs create-log-stream --log-group-name "/aws/ec2/sample-app" --log-stream-name "monitoring" 2>/dev/null || echo "Log stream might already exist"
fi

# Create system monitoring dashboard script
tee /home/ec2-user/dashboard.sh > /dev/null <<'EOF'
#!/bin/bash

clear
echo "================== Sample App Dashboard =================="
echo "Last updated: $(date)"
echo ""

echo "=== Container Status ==="
cd /var/www/sample-app
docker-compose -f docker-compose.prod.yml ps
echo ""

echo "=== Resource Usage ==="
echo "Memory:"
free -h | head -2
echo ""
echo "Disk:"
df -h / | tail -1
echo ""
echo "CPU Load:"
uptime
echo ""

echo "=== Recent Health Checks ==="
tail -10 /var/log/sample-app/monitoring.log 2>/dev/null || echo "No monitoring logs yet"
echo ""

echo "=== Container Logs (last 5 lines) ==="
docker-compose -f docker-compose.prod.yml logs --tail=5
echo ""

echo "=== Nginx Status ==="
curl -s http://localhost/nginx-health || echo "Nginx health check failed"
echo ""

echo "=== App Health ==="
curl -s http://localhost/health | jq . 2>/dev/null || curl -s http://localhost/health || echo "App health check failed"
echo ""

echo "================== End Dashboard =================="
EOF

chmod +x /home/ec2-user/dashboard.sh

# Create simple status check script
tee /home/ec2-user/status.sh > /dev/null <<'EOF'
#!/bin/bash

echo "🔍 Quick Status Check"
echo "Date: $(date)"
echo ""

# Check if containers are running
echo "📦 Containers:"
cd /var/www/sample-app
if docker-compose -f docker-compose.prod.yml ps --quiet | grep -q .; then
    echo "✅ Containers are running"
    docker-compose -f docker-compose.prod.yml ps --format "table {{.Name}}\t{{.Status}}"
else
    echo "❌ No containers running"
fi
echo ""

# Quick health check
echo "🏥 Health Check:"
if curl -f -s http://localhost/health > /dev/null 2>&1; then
    echo "✅ Application is healthy"
else
    echo "❌ Application health check failed"
fi

# Check nginx
if curl -f -s http://localhost/nginx-health > /dev/null 2>&1; then
    echo "✅ Nginx is healthy"
else
    echo "❌ Nginx health check failed"
fi
echo ""

# Resource usage
echo "📊 Resources:"
echo "Memory: $(free | awk 'NR==2{printf "%.0f%%", $3*100/$2}')"
echo "Disk: $(df / | awk 'NR==2 {print $5}')"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
EOF

chmod +x /home/ec2-user/status.sh

# Create alerting configuration template
tee /var/www/sample-app/alerting.conf.example > /dev/null <<EOF
# Alerting configuration for sample-app monitoring
# Copy this to alerting.conf and configure your notification methods

# Slack webhook URL (optional)
SLACK_WEBHOOK_URL=""

# Email settings (optional)
ALERT_EMAIL=""
SMTP_SERVER=""
SMTP_PORT=""
SMTP_USERNAME=""
SMTP_PASSWORD=""

# AWS SNS topic ARN (optional)
SNS_TOPIC_ARN=""

# Enable/disable alert types
ENABLE_HEALTH_ALERTS=true
ENABLE_RESOURCE_ALERTS=true
ENABLE_CONTAINER_ALERTS=true
EOF

echo "✅ Monitoring setup completed!"
echo ""
echo "📋 Summary:"
echo "  - Health monitoring runs every 5 minutes"
echo "  - Logs are stored in /var/log/sample-app/"
echo "  - Auto-recovery will restart services if health checks fail"
echo "  - Log rotation configured for 7 days"
echo ""
echo "💡 Useful commands:"
echo "  - Check status: ~/status.sh"
echo "  - View dashboard: ~/dashboard.sh"
echo "  - View monitoring logs: tail -f /var/log/sample-app/monitoring.log"
echo "  - View cron jobs: crontab -l"
echo "  - Manual health check: /usr/local/bin/sample-app-monitor"
echo ""
echo "🔧 To configure alerting:"
echo "  - Copy alerting.conf.example to alerting.conf"
echo "  - Configure your notification preferences"
echo "  - Restart the monitoring service"