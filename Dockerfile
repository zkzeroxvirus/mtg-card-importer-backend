FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js cluster.js ./
COPY lib ./lib

ENV NODE_ENV=production
ENV PORT=3000
ENV USE_BULK_DATA=true
ENV BULK_DATA_PATH=/app/data
ENV WORKERS=auto

EXPOSE 3000

CMD ["npm", "run", "start:cluster"]
