#!/bin/bash

# Simple script to make an existing app deployable
# Just sets up DNS subdomain and copies deployment files

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
PORT=$(grep -o "30[0-9][0-9]" "$APP_DIR"/{package.json,server.js,.env*} 2>/dev/null | head -1)
PORT=${PORT:-$((3000 + $(find apps/ -maxdepth 1 -type d | wc -l)))}

echo "Setting up $APP_NAME on $DOMAIN:$PORT"

# Create deployment files
mkdir -p "$APP_DIR/deploy"

# Copy and customize deployment script
cp apps/sample-2/deploy/one-click-deploy.sh "$APP_DIR/deploy/"
sed -i '' "s/sample-2/$APP_NAME/g; s/sample-2\.vadimzak\.com/$DOMAIN/g; s/3002/$PORT/g" "$APP_DIR/deploy/one-click-deploy.sh"

# Copy docker-compose and nginx configs  
cp apps/sample-2/docker-compose.prod.yml "$APP_DIR/"
cp apps/sample-2/deploy/nginx.prod.conf "$APP_DIR/deploy/"
sed -i '' "s/sample-2/$APP_NAME/g; s/3002/$PORT/g" "$APP_DIR/docker-compose.prod.yml"
sed -i '' "s/sample-2\.vadimzak\.com/$DOMAIN/g; s/sample-2/$APP_NAME/g; s/3002/$PORT/g" "$APP_DIR/deploy/nginx.prod.conf"

# Create .env.production if missing
[[ ! -f "$APP_DIR/.env.production" ]] && echo -e "NODE_ENV=production\nPORT=$PORT\nDOMAIN=$DOMAIN" > "$APP_DIR/.env.production"

# Set up DNS subdomain
EC2_IP=$(ssh -i ~/.ssh/sample-app-key.pem -o ConnectTimeout=5 ec2-user@sample.vadimzak.com "curl -s http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null)
if [[ -n "$EC2_IP" ]]; then
    echo "Creating DNS: $DOMAIN -> $EC2_IP"
    aws route53 change-resource-record-sets --profile bf --hosted-zone-id Z2O129XK0SJBV9 --change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$DOMAIN\",\"Type\":\"A\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$EC2_IP\"}]}}]}" >/dev/null
    echo "✅ Ready to deploy: cd $APP_DIR && ./deploy/one-click-deploy.sh"
else
    echo "⚠️  Could not get EC2 IP. Set up DNS manually: $DOMAIN -> your-ec2-ip"
fi