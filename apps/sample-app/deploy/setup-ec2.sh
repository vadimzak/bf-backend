#!/bin/bash

# EC2 Setup Script for Sample NodeJS App
# This script sets up a fresh Amazon Linux 2 EC2 instance

echo "Starting EC2 setup for Sample NodeJS App..."

# Update system
sudo yum update -y

# Install Node.js 18.x
curl -sL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# Install Git
sudo yum install -y git

# Install Nginx
sudo amazon-linux-extras install nginx1 -y

# Install PM2 globally
sudo npm install -g pm2

# Create app directory
sudo mkdir -p /var/www/sample-app
sudo chown ec2-user:ec2-user /var/www/sample-app

# Install Certbot for SSL
sudo yum install -y certbot python3-certbot-nginx

# Start and enable Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Configure firewall
sudo yum install -y firewalld
sudo systemctl start firewalld
sudo systemctl enable firewalld
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Create PM2 startup script
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u ec2-user --hp /home/ec2-user

echo "EC2 setup complete!"
echo "Next steps:"
echo "1. Clone your application to /var/www/sample-app"
echo "2. Configure Nginx (see nginx-config.conf)"
echo "3. Set up environment variables"
echo "4. Start the application with PM2"