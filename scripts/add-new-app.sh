#!/bin/bash
# Streamlined script to add a new app to the monorepo
# Usage: ./scripts/add-new-app.sh <app-name>

set -e

APP_NAME=$1

if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <app-name>"
    echo "Example: $0 my-new-app"
    exit 1
fi

# Configuration
DOMAIN="$APP_NAME.vadimzak.com"
APP_DIR="apps/$APP_NAME"

# Find next available port
USED_PORTS=$(grep -h "APP_PORT=" apps/*/deploy.config 2>/dev/null | cut -d= -f2 | sort -n)
LAST_PORT=$(echo "$USED_PORTS" | tail -1)
PORT=$((LAST_PORT + 1))
if [ $PORT -lt 3001 ]; then PORT=3001; fi

echo "🚀 Setting up new app: $APP_NAME"
echo "📍 Domain: $DOMAIN"
echo "🔌 Port: $PORT"
echo

# Create app directory structure
echo "Creating app structure..."
mkdir -p "$APP_DIR"/{public,deploy}

# Create package.json
cat > "$APP_DIR/package.json" << EOF
{
  "name": "$APP_NAME",
  "version": "1.0.0",
  "description": "$APP_NAME NodeJS app for $DOMAIN",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": ["nodejs", "express"],
  "author": "",
  "license": "ISC",
  "dependencies": {
    "express": "^4.18.2",
    "dotenv": "^16.0.3",
    "cors": "^2.8.5",
    "helmet": "^7.0.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.22"
  }
}
EOF

# Create minimal server.js
cat > "$APP_DIR/server.js" << EOF
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || $PORT;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static('public'));

// Home route
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    service: '$APP_NAME',
    timestamp: new Date().toISOString()
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start server
app.listen(PORT, () => {
  console.log(\`$APP_NAME app listening on port \${PORT}\`);
  console.log(\`Environment: \${process.env.NODE_ENV || 'development'}\`);
});
EOF

# Create minimal HTML page
cat > "$APP_DIR/public/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APP_NAME</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <header>
            <h1>APP_NAME Application</h1>
            <p class="subtitle">A minimal demo page</p>
        </header>
        
        <main>
            <div class="card">
                <h2>Welcome to APP_NAME</h2>
                <p>This app is deployed on AWS infrastructure.</p>
                <button id="statusBtn" class="btn">Check Status</button>
                <div id="status" class="status"></div>
            </div>
        </main>
        
        <footer>
            <p>&copy; 2025 APP_NAME | <a href="/health">Health Check</a></p>
        </footer>
    </div>
    
    <script src="app.js"></script>
</body>
</html>
EOF

# Replace APP_NAME in HTML
sed -i '' "s/APP_NAME/$APP_NAME/g" "$APP_DIR/public/index.html"

# Create CSS
cat > "$APP_DIR/public/styles.css" << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    line-height: 1.6;
    color: #333;
    background-color: #f4f4f4;
}

.container {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
}

header {
    background-color: #2c3e50;
    color: white;
    text-align: center;
    padding: 2rem;
}

header h1 {
    font-size: 2.5rem;
    margin-bottom: 0.5rem;
}

.subtitle {
    font-size: 1.2rem;
    opacity: 0.9;
}

main {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 2rem;
}

.card {
    background: white;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    padding: 2rem;
    max-width: 600px;
    width: 100%;
}

.card h2 {
    color: #2c3e50;
    margin-bottom: 1rem;
}

.btn {
    background-color: #3498db;
    color: white;
    border: none;
    padding: 0.75rem 1.5rem;
    font-size: 1rem;
    border-radius: 4px;
    cursor: pointer;
    margin-top: 1rem;
    transition: background-color 0.3s;
}

.btn:hover {
    background-color: #2980b9;
}

.status {
    margin-top: 1rem;
    padding: 1rem;
    border-radius: 4px;
    display: none;
}

.status.success {
    background-color: #d4edda;
    color: #155724;
    border: 1px solid #c3e6cb;
    display: block;
}

.status.error {
    background-color: #f8d7da;
    color: #721c24;
    border: 1px solid #f5c6cb;
    display: block;
}

footer {
    background-color: #34495e;
    color: white;
    text-align: center;
    padding: 1rem;
}

footer a {
    color: #3498db;
    text-decoration: none;
}

footer a:hover {
    text-decoration: underline;
}
EOF

# Create JavaScript
cat > "$APP_DIR/public/app.js" << 'EOF'
document.getElementById('statusBtn').addEventListener('click', async () => {
    const statusDiv = document.getElementById('status');
    const btn = document.getElementById('statusBtn');
    
    btn.disabled = true;
    btn.textContent = 'Checking...';
    
    try {
        const response = await fetch('/health');
        const data = await response.json();
        
        statusDiv.className = 'status success';
        statusDiv.innerHTML = `
            <strong>✅ Service is healthy!</strong><br>
            Service: ${data.service}<br>
            Status: ${data.status}<br>
            Time: ${new Date(data.timestamp).toLocaleString()}
        `;
    } catch (error) {
        statusDiv.className = 'status error';
        statusDiv.innerHTML = `
            <strong>❌ Error checking status</strong><br>
            ${error.message}
        `;
    } finally {
        btn.disabled = false;
        btn.textContent = 'Check Status';
    }
});
EOF

# Create environment files
cat > "$APP_DIR/.env.example" << EOF
# $APP_NAME Application Environment Variables

# Server Configuration
PORT=$PORT
NODE_ENV=development

# Domain Configuration (for deployment)
DOMAIN=$DOMAIN
EOF

cat > "$APP_DIR/.env.production" << EOF
# Production Environment Variables for $APP_NAME
NODE_ENV=production
PORT=$PORT
DOMAIN=$DOMAIN
EOF

# Create Dockerfile
cat > "$APP_DIR/Dockerfile" << 'EOF'
FROM node:18-alpine

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies
RUN npm install --only=production

# Copy app source
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001
RUN chown -R nextjs:nodejs /app

# Switch to non-root user
USER nextjs

# Expose port
EXPOSE APP_PORT

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:APP_PORT/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1); })"

# Start the application
CMD ["node", "server.js"]
EOF

# Replace APP_PORT in Dockerfile
sed -i '' "s/APP_PORT/$PORT/g" "$APP_DIR/Dockerfile"

# Create docker-compose.prod.yml
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
    env_file:
      - .env.production
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:$PORT/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1); })"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  app-network:
    external: true
    name: sample-app_app-network
EOF

# Create deployment configuration
cat > "$APP_DIR/deploy.config" << EOF
# Deployment configuration for $APP_NAME
APP_PORT=$PORT
APP_DOMAIN=$DOMAIN
EOF

# Create simplified deployment wrapper
cat > "$APP_DIR/deploy.sh" << EOF
#!/bin/bash
# Deploy $APP_NAME
# This is a convenience wrapper for the main deployment script

# Change to project root
cd "\$(dirname "\$0")/../.."

# Run the deployment
./scripts/deploy-app.sh $APP_NAME "\$@"
EOF

chmod +x "$APP_DIR/deploy.sh"

# Create DNS record
echo "Creating DNS record..."
aws route53 change-resource-record-sets \
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
echo "Updating nginx configuration for multi-app routing..."
NGINX_CONFIG="/tmp/nginx.conf.new"
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "cat /var/www/sample-app/deploy/nginx.conf" > "$NGINX_CONFIG"

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

# Upload updated nginx config
scp -i ~/.ssh/sample-app-key.pem "$NGINX_CONFIG" ec2-user@sample.vadimzak.com:/tmp/nginx.conf.new
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com "sudo cp /tmp/nginx.conf.new /var/www/sample-app/deploy/nginx.conf"
rm -f "$NGINX_CONFIG"

echo "✅ App setup complete!"
echo
echo "Next steps:"
echo "1. Deploy your app: cd $APP_DIR && ./deploy.sh"
echo "2. After deployment, the app will be automatically connected to the shared network"
echo "3. Restart nginx to load the new configuration:"
echo "   ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com 'cd /var/www/sample-app && sudo docker-compose -f docker-compose.prod.yml restart nginx'"
echo
echo "🌐 Your app will be available at: https://$DOMAIN"
echo
echo "Note: The wildcard SSL certificate (*.vadimzak.com) already covers this domain!"