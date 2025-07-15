# # ---------- Stage 1: Builder ----------
# FROM node:20-alpine as builder

# WORKDIR /app

# # Copy entire package and lock file (root level)
# COPY package.json package-lock.json ./
# RUN npm install

# # Copy the rest of the source code
# COPY . .

# # Build the admin panel located at src/admin
# RUN npm run build:admin

# # ---------- Stage 2: Production ----------
# FROM node:20-alpine

# WORKDIR /app

# # Copy production dependencies only
# COPY package.json package-lock.json ./
# RUN npm install --omit=dev

# # Copy backend and prebuilt admin from builder
# COPY --from=builder /app ./

# # Expose Medusa server port
# EXPOSE 9000

# # Run DB migrations and start the Medusa backend
# # CMD ["sh", "-c", "npx medusa db:migrate && npm run start"]
# CMD ["npm", "run", "start"]



FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install
COPY . .
EXPOSE 9000
CMD ["npm", "run", "dev"]
