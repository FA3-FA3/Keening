FROM node:24-slim
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --omit=optional && npm cache clean --force
COPY --chown=node:node server.js ./
COPY --chown=node:node src ./src
USER node
EXPOSE 8080
CMD ["node", "server.js"]
