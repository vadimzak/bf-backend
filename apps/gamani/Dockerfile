# Multi-stage build for NX monorepo full-stack application
FROM node:18-alpine AS builder

# Install build dependencies
RUN apk add --no-cache python3 make g++

WORKDIR /workspace

# Copy entire workspace
COPY . .

# Install all dependencies
RUN npm ci

# Build the workspace dependencies (but skip gamani)
RUN npx nx run-many --target=build --projects=server-core

# Build gamani specifically using the compiled libs
RUN cd apps/gamani && npx tsc --skipLibCheck

# Build the frontend client
WORKDIR /workspace/apps/gamani/client
# Install client dependencies separately to ensure clean build
RUN npm ci --prefer-offline --no-audit
# Build the client with explicit output
RUN npm run build

# Production stage
FROM node:18-alpine AS production

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodeuser -u 1001

# Set working directory
WORKDIR /app

# Copy the backend app code
COPY --chown=nodeuser:nodejs apps/gamani/src ./src
COPY --chown=nodeuser:nodejs apps/gamani/package.json ./
COPY --chown=nodeuser:nodejs apps/gamani/tsconfig.json ./

# Copy built backend from workspace
COPY --from=builder --chown=nodeuser:nodejs /workspace/apps/gamani/dist ./dist

# Copy dependencies from workspace but exclude @bf-backend symlinks
COPY --from=builder --chown=nodeuser:nodejs /workspace/node_modules ./node_modules
RUN rm -rf ./node_modules/@bf-backend

# Copy built @bf-backend libraries from dist
COPY --from=builder --chown=nodeuser:nodejs /workspace/dist/libs ./node_modules/@bf-backend

# Copy built frontend client
COPY --from=builder --chown=nodeuser:nodejs /workspace/apps/gamani/client/dist ./client/dist

# Create logs directory
RUN mkdir -p logs && chown nodeuser:nodejs logs

# Expose port
EXPOSE 3002

# Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3002/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) }).on('error', () => process.exit(1))"

# Switch to non-root user
USER nodeuser

# Start the application
CMD ["node", "dist/server.js"]