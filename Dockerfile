FROM node:20-alpine AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:20-alpine

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY server.js cluster.js ./
COPY lib ./lib

RUN mkdir -p /app/data && chown -R node:node /app

ENV NODE_ENV=production
ENV PORT=3000
ENV USE_BULK_DATA=true
ENV BULK_DATA_PATH=/app/data
ENV WORKERS=auto

EXPOSE 3000

USER node

CMD ["npm", "run", "start:cluster"]
