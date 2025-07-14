FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install
COPY . .
EXPOSE 9000
# CMD ["sh", "-c", "npx medusa migrations run && npm run dev"]
CMD ["npm", "run", "start"]
