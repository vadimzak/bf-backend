#!/bin/bash

# Deployment script for sample NodeJS app
# Run this on the EC2 instance after initial setup

APP_DIR="/var/www/sample-app"
REPO_URL="https://github.com/yourusername/sample-app.git"  # Update with your repo

echo "Deploying Sample App to $APP_DIR"

# Clone or pull latest code
if [ -d "$APP_DIR/.git" ]; then
    echo "Updating existing repository..."
    cd $APP_DIR
    git pull origin main
else
    echo "Cloning repository..."
    cd /var/www
    git clone $REPO_URL sample-app
    cd $APP_DIR
fi

# Install dependencies
echo "Installing dependencies..."
npm ci --production

# Copy environment variables
if [ ! -f ".env" ]; then
    echo "Creating .env file..."
    cp .env.example .env
    echo "Please update .env with your AWS credentials and settings"
fi

# Stop existing PM2 process if running
pm2 stop sample-app 2>/dev/null || true
pm2 delete sample-app 2>/dev/null || true

# Start application with PM2
echo "Starting application with PM2..."
pm2 start ecosystem.config.js

# Save PM2 process list
pm2 save

# Copy Nginx configuration
echo "Configuring Nginx..."
sudo cp deploy/nginx.conf /etc/nginx/conf.d/sample-app.conf
sudo nginx -t && sudo systemctl reload nginx

echo "Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Update .env file with your AWS credentials"
echo "2. Set up SSL certificate: sudo certbot --nginx -d sample.vadimzak.com"
echo "3. Update Route 53 to point to this EC2 instance"
echo ""
echo "Check application status: pm2 status"
echo "View logs: pm2 logs sample-app"