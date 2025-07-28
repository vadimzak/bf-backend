#!/bin/bash

# Docker-based deployment script for sample-app
# Usage: ./docker-deploy.sh [dev|prod]

set -e  # Exit on any error

ENVIRONMENT=${1:-prod}
APP_NAME="sample-app"
COMPOSE_FILE="docker-compose.yml"

echo "🚀 Starting Docker deployment for $APP_NAME in $ENVIRONMENT mode..."

# Set compose file based on environment
if [ "$ENVIRONMENT" = "prod" ]; then
    COMPOSE_FILE="docker-compose.prod.yml"
    ENV_FILE=".env.production"
else
    ENV_FILE=".env"
fi

# Ensure environment file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Environment file $ENV_FILE not found!"
    echo "Please create it from .env.example and configure your settings."
    exit 1
fi

echo "📝 Using environment file: $ENV_FILE"
echo "📝 Using compose file: $COMPOSE_FILE"

# Pull latest images if in production
if [ "$ENVIRONMENT" = "prod" ]; then
    echo "📦 Pulling latest base images..."
    docker-compose -f $COMPOSE_FILE pull nginx
fi

# Build the application
echo "🔨 Building application..."
docker-compose -f $COMPOSE_FILE build --no-cache sample-app

# Stop existing containers
echo "🛑 Stopping existing containers..."
docker-compose -f $COMPOSE_FILE down

# Remove unused images to free space
echo "🧹 Cleaning up unused Docker images..."
docker image prune -f

# Start the services
echo "▶️ Starting services..."
docker-compose -f $COMPOSE_FILE up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Health check
echo "🏥 Running health check..."
if [ "$ENVIRONMENT" = "prod" ]; then
    HEALTH_URL="http://localhost/health"
else
    HEALTH_URL="http://localhost:3001/health"
fi

for i in {1..30}; do
    if curl -f -s $HEALTH_URL > /dev/null; then
        echo "✅ Application is healthy!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Health check failed after 30 attempts"
        echo "📋 Container logs:"
        docker-compose -f $COMPOSE_FILE logs --tail=20
        exit 1
    fi
    echo "⏳ Attempt $i/30 - waiting for application to be ready..."
    sleep 2
done

# Show running containers
echo "📋 Running containers:"
docker-compose -f $COMPOSE_FILE ps

# Show logs
echo "📋 Recent logs:"
docker-compose -f $COMPOSE_FILE logs --tail=10

echo "🎉 Deployment completed successfully!"
echo "🌐 Application is available at:"
if [ "$ENVIRONMENT" = "prod" ]; then
    echo "   - http://localhost (HTTP)"
    echo "   - https://localhost (HTTPS - if SSL configured)"
else
    echo "   - http://localhost:3001"
fi

echo "💡 Useful commands:"
echo "   - View logs: docker-compose -f $COMPOSE_FILE logs -f"
echo "   - Stop services: docker-compose -f $COMPOSE_FILE down"
echo "   - Restart services: docker-compose -f $COMPOSE_FILE restart"
echo "   - View containers: docker-compose -f $COMPOSE_FILE ps"