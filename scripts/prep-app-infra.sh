#!/bin/bash
# Script to prepare cloud infrastructure for existing apps
# Usage: ./scripts/prep-app-infra.sh <app-name> [options]
# Options:
#   --deploy    Automatically deploy the app after infrastructure setup

set -e

# Parse arguments
APP_NAME=""
DEPLOY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy)
            DEPLOY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <app-name> [options]"
            echo "Prepares cloud infrastructure (DNS, nginx) for existing apps"
            echo ""
            echo "Options:"
            echo "  --deploy    Automatically deploy the app after setup"
            echo ""
            echo "Examples:"
            echo "  $0 my-app           # Setup infrastructure only"
            echo "  $0 my-app --deploy  # Setup infrastructure and deploy"
            exit 0
            ;;
        *)
            if [ -z "$APP_NAME" ]; then
                APP_NAME=$1
            else
                echo "Error: Unknown option $1"
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$APP_NAME" ]; then
    echo "Error: App name is required"
    echo "Usage: $0 <app-name> [options]"
    echo "Run '$0 --help' for more information"
    exit 1
fi

# Configuration
APP_DIR="apps/$APP_NAME"

# Check if app exists
if [ ! -d "$APP_DIR" ]; then
    echo "❌ Error: App '$APP_NAME' does not exist at $APP_DIR"
    echo "Please create the app files first before running infrastructure setup"
    exit 1
fi

# Check if deploy.config exists
if [ ! -f "$APP_DIR/deploy.config" ]; then
    echo "❌ Error: deploy.config not found at $APP_DIR/deploy.config"
    echo "Please create deploy.config with APP_PORT and APP_DOMAIN"
    exit 1
fi

# Read configuration from deploy.config
PORT=$(grep "APP_PORT=" "$APP_DIR/deploy.config" | cut -d= -f2)
DOMAIN=$(grep "APP_DOMAIN=" "$APP_DIR/deploy.config" | cut -d= -f2)

if [ -z "$PORT" ] || [ -z "$DOMAIN" ]; then
    echo "❌ Error: deploy.config must contain APP_PORT and APP_DOMAIN"
    exit 1
fi

echo "🚀 Setting up infrastructure for: $APP_NAME"
echo "📍 Domain: $DOMAIN"
echo "🔌 Port: $PORT"
echo "🔧 Options: $([ "$DEPLOY" = true ] && echo "deploy")"
echo

# Create DNS record
echo "Creating DNS record..."
AWS_PROFILE=bf aws route53 change-resource-record-sets \
  --hosted-zone-id Z2O129XK0SJBV9 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "'$DOMAIN'",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "51.16.33.8"}]
      }
    }]
  }' > /dev/null 2>&1 || echo "⚠️  DNS record may already exist"

# Update nginx configuration
echo "Updating nginx configuration..."
NGINX_CONFIG="/tmp/nginx.conf.new.$$"
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "cat /var/www/sample-app/deploy/nginx.conf" > "$NGINX_CONFIG" 2>/dev/null || {
    echo "❌ Failed to fetch nginx config. Check SSH connectivity."
    exit 1
}

# Check if nginx config already exists for this domain
if grep -q "server_name $DOMAIN;" "$NGINX_CONFIG"; then
    echo "⚠️  Nginx configuration for $DOMAIN already exists. Skipping nginx update."
    rm -f "$NGINX_CONFIG"
else
    # Add new app configuration to nginx
    cat >> "$NGINX_CONFIG" << EOF

# $APP_NAME App Configuration
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    
    ssl_certificate /var/www/ssl/fullchain.pem;
    ssl_certificate_key /var/www/ssl/privkey.pem;
    
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

    # Upload updated nginx config
    scp -i ~/.ssh/sample-app-key.pem "$NGINX_CONFIG" ec2-user@sample.vadimzak.com:/tmp/nginx.conf.new > /dev/null 2>&1
    ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "sudo cp /tmp/nginx.conf.new /var/www/sample-app/deploy/nginx.conf" > /dev/null 2>&1
    rm -f "$NGINX_CONFIG"

    # Restart nginx to apply new configuration
    echo "Restarting nginx..."
    ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "cd /var/www/sample-app && sudo docker-compose -f docker-compose.prod.yml restart nginx" > /dev/null 2>&1 || {
        echo "⚠️  Warning: Failed to restart nginx. You may need to restart it manually."
    }
fi

echo "✅ Infrastructure setup complete!"
echo

# Deploy if requested
if [ "$DEPLOY" = true ]; then
    echo "🚀 Deploying $APP_NAME..."
    ./scripts/deploy-app.sh "$APP_NAME" "Initial deployment of $APP_NAME" || {
        echo "❌ Deployment failed. Check the error messages above."
        exit 1
    }
    echo "✅ Deployment complete!"
    echo
    echo "🌐 Your app is now live at: https://$DOMAIN"
else
    echo "Next steps:"
    echo "1. Deploy your app: ./scripts/deploy-app.sh $APP_NAME"
    echo "   Or from app directory: cd $APP_DIR && ./deploy.sh"
    echo
    echo "🌐 Your app will be available at: https://$DOMAIN"
fi

echo
echo "Note: The wildcard SSL certificate (*.vadimzak.com) already covers this domain!"