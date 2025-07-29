#!/bin/bash
# Renew wildcard certificate for *.vadimzak.com
# This script should be run periodically (e.g., via cron) to renew the certificate

set -e

echo "🔐 Renewing wildcard certificate for *.vadimzak.com"
echo "=================================================="

# Renew certificate using Route53 DNS validation
ssh -i ~/.ssh/sample-app-key.pem ec2-user@sample.vadimzak.com << 'EOF'
# Renew certificate
sudo /usr/local/bin/certbot renew --dns-route53 --non-interactive

# Copy renewed certificate files to /var/www/ssl
if [ -f "/etc/letsencrypt/live/wildcard-vadimzak/fullchain.pem" ]; then
  echo "Copying renewed certificates..."
  sudo cp /etc/letsencrypt/live/wildcard-vadimzak/fullchain.pem /var/www/ssl/
  sudo cp /etc/letsencrypt/live/wildcard-vadimzak/privkey.pem /var/www/ssl/
  sudo chmod 644 /var/www/ssl/fullchain.pem
  sudo chmod 600 /var/www/ssl/privkey.pem
  
  # Restart nginx to use new certificate
  cd /var/www/sample-app && sudo docker-compose -f docker-compose.prod.yml restart nginx
  echo "✅ Certificate renewed and nginx restarted!"
else
  echo "⚠️  Certificate renewal may have failed"
fi
EOF

echo "✅ Certificate renewal process complete!"