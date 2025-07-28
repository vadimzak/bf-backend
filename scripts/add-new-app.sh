#!/bin/bash

# Simple script to make an existing app deployable
# Sets up DNS subdomain, deployment files, and handles multi-app nginx routing

set -e

APP_NAME="$1"
DOMAIN="${2:-$APP_NAME.vadimzak.com}"

if [[ -z "$APP_NAME" || ! -d "apps/$APP_NAME" ]]; then
    echo "Usage: $0 <app-name> [domain]"
    echo "Example: $0 blog [blog.vadimzak.com]"
    exit 1
fi

APP_DIR="apps/$APP_NAME"

# Detect port from app
PORT=$(grep -o "30[0-9][0-9]" "$APP_DIR"/{package.json,server.js,.env*} 2>/dev/null | head -1 | grep -o "30[0-9][0-9]")
PORT=${PORT:-$((3000 + $(find apps/ -maxdepth 1 -type d | wc -l)))}

echo "Setting up $APP_NAME on $DOMAIN:$PORT"

# Create deployment files
mkdir -p "$APP_DIR/deploy"

# Copy and customize deployment script
cp apps/sample-2/deploy/one-click-deploy.sh "$APP_DIR/deploy/"
sed -i '' "s/sample-2/$APP_NAME/g; s/sample-2\.vadimzak\.com/$DOMAIN/g; s/3002/$PORT/g" "$APP_DIR/deploy/one-click-deploy.sh"

# Copy docker-compose WITHOUT nginx (shared nginx handles routing)
cat > "$APP_DIR/docker-compose.prod.yml" << EOF
version: '3.8'

services:
  $APP_NAME:
    image: $APP_NAME:latest
    restart: unless-stopped
    ports:
      - "$PORT:$PORT"
    environment:
      - NODE_ENV=production
      - PORT=$PORT
    env_file:
      - .env.production
    networks:
      - app-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

networks:
  app-network:
    external: true
    name: sample-app_app-network
EOF

# Create .env.production if missing
[[ ! -f "$APP_DIR/.env.production" ]] && echo -e "NODE_ENV=production\nPORT=$PORT\nDOMAIN=$DOMAIN" > "$APP_DIR/.env.production"

# Set up DNS subdomain
EC2_IP=$(ssh -i ~/.ssh/sample-app-key.pem -o ConnectTimeout=5 ec2-user@sample.vadimzak.com "curl -s http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null)
if [[ -n "$EC2_IP" ]]; then
    echo "Creating DNS: $DOMAIN -> $EC2_IP"
    aws route53 change-resource-record-sets --profile bf --hosted-zone-id Z2O129XK0SJBV9 --change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$DOMAIN\",\"Type\":\"A\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$EC2_IP\"}]}}]}" >/dev/null
else
    echo "⚠️  Could not get EC2 IP. Set up DNS manually: $DOMAIN -> your-ec2-ip"
fi

# Update SSL certificate to include new domain
echo "Adding $DOMAIN to SSL certificate..."
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "cd /var/www/sample-app && sudo docker-compose -f docker-compose.prod.yml stop nginx" 2>/dev/null || true

# Get current domains from certificate
CURRENT_DOMAINS=$(ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "sudo openssl x509 -in /var/www/ssl/fullchain.pem -text -noout | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/.*DNS://g' | sed 's/, DNS:/ -d /g'" 2>/dev/null)

# Add new domain to certificate
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "sudo /usr/local/bin/certbot certonly --standalone -d $CURRENT_DOMAINS -d $DOMAIN --expand --agree-tos --email vadim@vadimzak.com --non-interactive" 2>/dev/null || echo "⚠️  SSL expansion failed - you may need to add $DOMAIN manually"

# Copy new certificate
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "sudo cp /etc/letsencrypt/live/sample.vadimzak.com/fullchain.pem /var/www/ssl/ && sudo cp /etc/letsencrypt/live/sample.vadimzak.com/privkey.pem /var/www/ssl/" 2>/dev/null || true

# Update nginx configuration to handle multiple domains
echo "Updating nginx configuration for multi-app routing..."
NGINX_CONFIG=$(ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "cat /var/www/sample-app/deploy/nginx.conf")

# Add new domain configuration if not already present
if ! echo "$NGINX_CONFIG" | grep -q "server_name $DOMAIN"; then
    cat > /tmp/new-domain-config << EOF

# $APP_NAME App Configuration
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    
    ssl_certificate /etc/ssl/fullchain.pem;
    ssl_certificate_key /etc/ssl/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    location / {
        proxy_pass http://$APP_NAME-$APP_NAME-1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Append new configuration to existing nginx config
    scp -i ~/.ssh/sample-app-key.pem /tmp/new-domain-config ec2-user@sample.vadimzak.com:/tmp/
    ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "cat /tmp/new-domain-config >> /var/www/sample-app/deploy/nginx.conf"
    rm /tmp/new-domain-config
fi

# Start nginx
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "cd /var/www/sample-app && sudo docker-compose -f docker-compose.prod.yml start nginx" 2>/dev/null || true

echo "✅ Infrastructure setup complete!"
echo ""
echo "Next steps:"
echo "1. Deploy your app: cd $APP_DIR && ./deploy/one-click-deploy.sh"
echo "2. After deployment, connect to shared network:"
echo "   ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com 'sudo docker network connect sample-app_app-network $APP_NAME-$APP_NAME-1'"
echo "3. Restart nginx to reload config:"
echo "   ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com 'cd /var/www/sample-app && sudo docker-compose -f docker-compose.prod.yml restart nginx'"
echo ""
echo "🌐 Your app will be available at: https://$DOMAIN"