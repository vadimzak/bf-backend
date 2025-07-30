# Multi-stage build for NX monorepo application
FROM node:18-alpine AS builder

# Install build dependencies
RUN apk add --no-cache python3 make g++

WORKDIR /workspace

# Copy entire workspace
COPY . .

# Install all dependencies
RUN npm ci

# Build the workspace (this will build server-core and other dependencies)
RUN npm run build

# Production stage
FROM node:18-alpine AS production

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodeuser -u 1001

# Set working directory
WORKDIR /app

# Copy the app code
COPY --chown=nodeuser:nodejs apps/sample-app/ ./

# Copy dependencies from workspace but exclude @bf-backend symlinks
COPY --from=builder --chown=nodeuser:nodejs /workspace/node_modules ./node_modules
RUN rm -rf ./node_modules/@bf-backend

# Copy built @bf-backend libraries from dist
COPY --from=builder --chown=nodeuser:nodejs /workspace/dist/libs ./node_modules/@bf-backend

# Create logs directory
RUN mkdir -p logs && chown nodeuser:nodejs logs

# Expose port
EXPOSE 3001

# Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js || exit 1

# Switch to non-root user
USER nodeuser

# Start the application
CMD ["node", "server.js"]