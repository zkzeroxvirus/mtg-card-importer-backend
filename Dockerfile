FROM node:18-alpine

# Install dependencies for better performance
RUN apk add --no-cache tini

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --production

# Copy application code
COPY . .

# Create data directory for bulk data
RUN mkdir -p /app/data

# Use tini for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s \
  CMD node -e "require('http').get('http://localhost:3000/', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start server
CMD ["node", "server.js"]
