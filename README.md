# 🛍️ Medusa Headless E-Commerce Deployment on AWS ECS with Terraform & GitHub Actions

This project sets up and deploys the Medusa backend to AWS using ECS Fargate, RDS (PostgreSQL). It also includes CI/CD using GitHub Actions, infrastructure provisioning with Terraform, and automatic DB migration.

---

## 📦 Project Structure

```text
.
├── Dockerfile                  # Medusa backend container
├── docker-compose.yml         # (Optional) local setup
├── terraform/                 # Infra provisioning (RDS, VPC, ECS, etc.)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── ...
├── .github/
│   └── workflows/
│       └── deploy.yml         # GitHub Actions pipeline
├── src/
│   └── admin/                 # Medusa Admin (must be built for prod)
├── medusa-config.ts
├── package.json
├── package-lock.json
└── README.md
```

---

## 🛠️ Prerequisites

- AWS CLI configured
- GitHub repository secrets set:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`
- Terraform installed locally (for initial setup)

---

## 🚀 Deployment Steps

### ✅ 1. Provision Infrastructure (One-time)

```bash
cd terraform
terraform init
terraform apply
```

> Outputs like `rds_endpoint`, `ecs_cluster_name`, etc., will be stored for use in GitHub Actions.

---

### ✅ 2. Build Admin Panel for Production

Medusa expects the admin panel to be built before running in production.

```bash
cd src/admin
npm install
npm run build
```

This will create a `dist/` folder that needs to be copied in the Docker image. You can move it or copy in Dockerfile.

---

### ✅ 3. Dockerfile

Update your `Dockerfile`:

```Dockerfile
FROM node:20-alpine
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm install

COPY . .

# Copy built admin panel if not already included
COPY src/admin/dist ./src/admin/dist

# Run DB migrations & create admin user before app starts
CMD npx medusa migrations run && \
    npx medusa user -e admin@medusa-test.com -p supersecret && \
    npm run start
```

---

### ✅ 4. GitHub Actions Workflow (`.github/workflows/deploy.yml`)

```yaml
name: Deploy to ECS

on:
  push:
    branches:
      - main

jobs:
  deploy:
    name: Build and Deploy
    runs-on: ubuntu-latest

    env:
      AWS_REGION: ap-south-1

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      - name: Terraform Apply
        working-directory: terraform
        run: terraform apply -auto-approve

      - name: Get Terraform Outputs
        id: tf
        working-directory: terraform
        run: |
          echo "RDS_HOST=$(terraform output -raw rds_endpoint)" >> $GITHUB_ENV
          echo "ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)" >> $GITHUB_ENV
          echo "ECS_SERVICE=$(terraform output -raw ecs_service_name)" >> $GITHUB_ENV
          echo "TASK_DEF=$(terraform output -raw task_definition_family)" >> $GITHUB_ENV

      - name: Build Docker image
        run: |
          docker build -t medusa-app .

      - name: Login to ECR
        run: |
          aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin <your-ecr-url>

      - name: Push Docker image to ECR
        run: |
          docker tag medusa-app:latest <your-ecr-url>/medusa-app:latest
          docker push <your-ecr-url>/medusa-app:latest

      - name: Update ECS Service
        run: |
          aws ecs update-service \
            --cluster $ECS_CLUSTER \
            --service $ECS_SERVICE \
            --force-new-deployment
```

---

## ✅ Post-Deployment: Testing

### 🧪 Test Medusa Admin Token Auth

```bash
curl -X POST http://<public-ip>:9000/admin/auth/token \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@medusa-test.com", "password": "supersecret"}'
```

Then use the token in headers for protected routes.

---

## ❓ Common Issues

- ❌ **`index.html not found`**: You didn't build the admin panel (`npm run build`) or forgot to copy `dist/`.
- ❌ **Unauthorized on /admin**: No admin user exists. Create with:
  ```bash
  npx medusa user -e admin@medusa-test.com -p supersecret
  ```

---

## 📬 Feedback

PRs and suggestions are welcome!
