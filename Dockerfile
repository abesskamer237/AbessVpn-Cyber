FROM node:22-alpine

WORKDIR /app

# Copy package definition
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production || npm install

# Copy application source code
COPY . .

# Expose port
EXPOSE 3000

# Set environment
ENV NODE_ENV=production
ENV PORT=3000

# Run server
CMD ["npx", "tsx", "server.ts"]
