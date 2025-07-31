# Simple build for test1 app
FROM node:18-alpine

WORKDIR /app

# Copy app files from workspace
COPY apps/test1/package*.json ./
COPY apps/test1/tsconfig.json ./
COPY apps/test1/src ./src

# Install all dependencies for build
RUN npm install
RUN npm run build
# Remove devDependencies after build
RUN npm prune --production

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodeuser -u 1001

# Set ownership
RUN chown -R nodeuser:nodejs /app

EXPOSE 3000

USER nodeuser

CMD ["npm", "start"]