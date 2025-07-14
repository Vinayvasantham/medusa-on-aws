FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install
COPY . .
EXPOSE 9000
RUN npx medusa migrations run
CMD ["npm", "run", "dev"]
