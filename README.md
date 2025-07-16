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
EXPOSE 9000
CMD ["npm", "run", "dev"]
```

---

### ✅ 4. GitHub Actions Workflow (`.github/workflows/deploy.yml`)

```yaml
name: Deploy Medusa Store to AWS ECS

on:
  push:
    branches:
      - main

env:
  AWS_REGION: ap-south-1
  AWS_ACCOUNT_ID: 331190361204
  ECR_REPOSITORY: medusa-repo
  ECR_IMAGE_URI: 331190361204.dkr.ecr.ap-south-1.amazonaws.com/medusa-repo:latest
  ECS_CLUSTER: medusa-cluster
  ECS_SERVICE: medusa-service
  TASK_DEFINITION_FAMILY: medusa-task
  CONTAINER_NAME: medusa

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout source
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Log in to Amazon ECR
        run: |
          aws ecr get-login-password --region $AWS_REGION | \
            docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

      - name: Build Docker image
        run: |
          docker build -t $ECR_REPOSITORY .

      - name: Tag and Push image to ECR
        run: |
          docker tag $ECR_REPOSITORY:latest $ECR_IMAGE_URI
          docker push $ECR_IMAGE_URI
          echo "IMAGE_URI=$ECR_IMAGE_URI" >> $GITHUB_ENV

      - name: Update ECS task definition
        id: update-task-def
        run: |
          TASK_DEF=$(aws ecs describe-task-definition \
            --task-definition $TASK_DEFINITION_FAMILY \
            --region $AWS_REGION)

          NEW_TASK_DEF=$(echo "$TASK_DEF" | jq \
            --arg IMAGE_URI "$ECR_IMAGE_URI" \
            --arg CONTAINER_NAME "$CONTAINER_NAME" \
            '.taskDefinition |
            .containerDefinitions |= map(if .name == $CONTAINER_NAME then .image = $IMAGE_URI else . end) |
            del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')

          NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
            --region $AWS_REGION \
            --cli-input-json "$NEW_TASK_DEF" \
            | jq -r '.taskDefinition.taskDefinitionArn')

          echo "task_definition_arn=$NEW_TASK_DEF_ARN" >> $GITHUB_OUTPUT

      - name: Deploy new ECS task
        run: |
          aws ecs update-service \
            --cluster $ECS_CLUSTER \
            --service $ECS_SERVICE \
            --task-definition ${{ steps.update-task-def.outputs.task_definition_arn }} \
            --force-new-deployment \
            --region $AWS_REGION

      - name: Wait for ECS to stabilize
        run: |
          aws ecs wait services-stable \
            --cluster $ECS_CLUSTER \
            --services $ECS_SERVICE \
            --region $AWS_REGION
          echo "ECS service is now stable ✅"

      - name: Run Medusa DB Migrations on ECS
        run: |
          echo "Running DB migrations on ECS..."
          aws ecs run-task \
            --cluster $ECS_CLUSTER \
            --launch-type FARGATE \
            --network-configuration "awsvpcConfiguration={subnets=[subnet-0411fc8f2e2f8523b,subnet-0921b8e9af81137cd],securityGroups=[sg-0e64a4a0da97f441e],assignPublicIp=ENABLED}" \
            --task-definition $TASK_DEFINITION_FAMILY \
            --region $AWS_REGION \
            --overrides "$(jq -n \
              --arg container "$CONTAINER_NAME" \
              --arg cmd1 "npx" \
              --arg cmd2 "medusa" \
              --arg cmd3 "db:migrate" \
              '{containerOverrides:[{name:$container,command:[$cmd1,$cmd2,$cmd3]}]}')"

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
