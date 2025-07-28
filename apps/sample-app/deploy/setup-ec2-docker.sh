#!/bin/bash

# EC2 setup script for Docker-based deployment
# Optimized for t3a.nano instances

set -e

echo "🚀 Setting up EC2 instance for Docker deployment..."

# Update system
sudo yum update -y

# Install Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create symbolic link for easier access
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install git for repository cloning
sudo yum install -y git

# Install nginx for reverse proxy
sudo yum install -y nginx
sudo systemctl enable nginx

# Install certbot for SSL certificates
sudo yum install -y python3 python3-pip
sudo pip3 install certbot certbot-nginx

# Create application directory
sudo mkdir -p /var/www
sudo chown ec2-user:ec2-user /var/www

# Create logs directory
sudo mkdir -p /var/log/sample-app
sudo chown ec2-user:ec2-user /var/log/sample-app

# Configure system limits for better performance
echo "ec2-user soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "ec2-user hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# Optimize for small instance (t3a.nano)
# Configure swap file for memory management
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Configure memory management
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf

# Create systemd service for Docker Compose
sudo tee /etc/systemd/system/sample-app.service > /dev/null <<EOF
[Unit]
Description=Sample App Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/var/www/sample-app
ExecStart=/usr/local/bin/docker-compose -f docker-compose.prod.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker-compose.prod.yml down
TimeoutStartSec=0
User=ec2-user
Group=ec2-user

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl enable sample-app.service

# Configure log rotation for Docker
sudo tee /etc/logrotate.d/docker > /dev/null <<EOF
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=1M
    missingok
    delaycompress
    copytruncate
}
EOF

# Install htop for monitoring
sudo yum install -y htop

# Create monitoring script
tee /home/ec2-user/monitor.sh > /dev/null <<EOF
#!/bin/bash
echo "=== System Status ==="
date
echo ""
echo "=== Memory Usage ==="
free -h
echo ""
echo "=== Disk Usage ==="
df -h
echo ""
echo "=== Docker Containers ==="
docker ps
echo ""
echo "=== Container Stats ==="
docker stats --no-stream
EOF

chmod +x /home/ec2-user/monitor.sh

echo "✅ EC2 setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Logout and login again to use Docker without sudo"
echo "2. Clone your repository to /var/www/"
echo "3. Configure environment variables"
echo "4. Run the deployment script"
echo ""
echo "💡 Useful commands:"
echo "   - Monitor system: ~/monitor.sh"
echo "   - View Docker logs: docker-compose logs -f"
echo "   - Check service status: sudo systemctl status sample-app"
echo "   - Start/stop service: sudo systemctl start/stop sample-app"
echo ""
echo "🔧 For SSL setup, run: sudo certbot --nginx -d your-domain.com"