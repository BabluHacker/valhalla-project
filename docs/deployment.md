# Valhalla Deployment Guide

Complete step-by-step guide for deploying the Valhalla platform to AWS.

## Prerequisites

### Required Tools

Install the following tools on your local machine:

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Terraform
brew install terraform

# kubectl
brew install kubectl

# Helm
brew install helm

# Docker Desktop
# Download from https://www.docker.com/products/docker-desktop

# Kustomize
brew install kustomize
```

### AWS Account Setup

1. **Create AWS Account** (if you don't have one)
2. **Create IAM User** with AdministratorAccess
3. **Configure AWS CLI**:

```bash
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: us-east-1
# - Default output format: json
```

4. **Verify AWS access**:

```bash
aws sts get-caller-identity
```

## Deployment Methods

### Option 1: Automated Deployment Script (Recommended)

The easiest way to deploy everything:

```bash
# Deploy to dev environment
./scripts/deploy.sh dev

# Deploy to production
./scripts/deploy.sh prod
```

This script will:
1. ✅ Deploy infrastructure with Terraform
2. ✅ Configure kubectl for EKS
3. ✅ Install AWS Load Balancer Controller
4. ✅ Build and push Docker image
5. ✅ Deploy Kubernetes manifests
6. ✅ Verify deployment

### Option 2: Manual Step-by-Step Deployment

For learning or debugging, follow these manual steps:

#### Step 1: Deploy Infrastructure

```bash
cd terraform/environments/dev

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your preferences
vim terraform.tfvars

# Initialize Terraform
terraform init

# Review changes
terraform plan

# Apply infrastructure
terraform apply
```

**Expected time**: 15-20 minutes

**Resources created**:
- VPC with public/private subnets
- NAT Gateways
- EKS cluster
- EKS node groups (3 nodes)
- ECR repository
- Security groups
- IAM roles

#### Step 2: Configure kubectl

```bash
# Get cluster name from Terraform output
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME

# Verify cluster access
kubectl get nodes
```

You should see 3 nodes in `Ready` status.

#### Step 3: Install Prerequisites in Cluster

**A. Install AWS Load Balancer Controller**

```bash
# Create IAM policy
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# Get VPC ID
VPC_ID=$(terraform output -raw vpc_id)

# Install using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set region=us-east-1 \
  --set vpcId=$VPC_ID

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
```

**B. Install Metrics Server (for HPA)**

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl get deployment metrics-server -n kube-system
```

#### Step 4: Build and Push Docker Image

```bash
# Get ECR repository URL
ECR_REPO=$(terraform output -json ecr_repository_urls | jq -r '.["valhalla-api"]')
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build image
cd ../../../../app
docker build -t valhalla-api:latest .

# Tag and push
docker tag valhalla-api:latest $ECR_REPO:latest
docker tag valhalla-api:latest $ECR_REPO:dev-$(git rev-parse --short HEAD)
docker push $ECR_REPO:latest
docker push $ECR_REPO:dev-$(git rev-parse --short HEAD)

cd ..
```

#### Step 5: Update Kubernetes Manifests

```bash
# Update kustomization with your ECR URL
sed -i '' "s|<AWS_ACCOUNT_ID>|$AWS_ACCOUNT_ID|g" k8s/overlays/dev/kustomization.yaml
```

#### Step 6: Deploy to Kubernetes

```bash
# Preview what will be applied
kubectl kustomize k8s/overlays/dev

# Apply manifests
kubectl apply -k k8s/overlays/dev

# Watch deployment progress
kubectl get pods -n valhalla -w
```

Wait until all pods show `Running` status and `3/3` ready.

#### Step 7: Verify Deployment

```bash
# Check all resources
kubectl get all -n valhalla

# Check pod logs
kubectl logs -n valhalla -l app=valhalla-api --tail=50

# Check ingress
kubectl get ingress -n valhalla

# Get ALB URL (wait 2-3 minutes for provisioning)
ALB_URL=$(kubectl get ingress valhalla-api -n valhalla -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Application URL: http://$ALB_URL"
```

#### Step 8: Test Application

```bash
# Health check
curl http://$ALB_URL/health

# Application status
curl http://$ALB_URL/api/v1/status

# Get data
curl http://$ALB_URL/api/v1/data

# Prometheus metrics
curl http://$ALB_URL/metrics
```

## Local Testing (Without AWS)

To test the application locally before deploying:

```bash
cd app

# Install dependencies
npm install

# Run tests
npm test

# Run locally
npm run dev

# In another terminal
curl http://localhost:3000/health
curl http://localhost:3000/api/v1/status
curl http://localhost:3000/api/v1/data
```

### Test with Docker locally

```bash
# Build image
docker build -t valhalla-api:local .

# Run container
docker run -p 3000:3000 -e NODE_ENV=production valhalla-api:local

# Test
curl http://localhost:3000/health
```

## Monitoring Deployment

### Watch Pods

```bash
kubectl get pods -n valhalla -w
```

### View Logs

```bash
# All pods
kubectl logs -n valhalla -l app=valhalla-api -f --tail=100

# Specific pod
kubectl logs -n valhalla valhalla-api-xxxxx -f
```

### Check HPA

```bash
# Watch autoscaler
kubectl get hpa -n valhalla -w

# Pod metrics
kubectl top pods -n valhalla
```

### Check Ingress

```bash
kubectl describe ingress valhalla-api -n valhalla
```

## Troubleshooting

### Pods Not Starting

```bash
# Describe pod to see events
kubectl describe pod <pod-name> -n valhalla

# Check if image exists in ECR
aws ecr describe-images --repository-name valhalla-dev-valhalla-api --region us-east-1
```

### Image Pull Errors

```bash
# Verify ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Check node IAM permissions
kubectl describe node | grep ProviderID
```

### ALB Not Created

```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify ingress annotations
kubectl get ingress valhalla-api -n valhalla -o yaml
```

### Health Checks Failing

```bash
# Check pod readiness
kubectl get pods -n valhalla

# View application logs
kubectl logs -n valhalla -l app=valhalla-api --tail=100

# Test health endpoint directly from pod
kubectl exec -n valhalla <pod-name> -- curl localhost:3000/health
```

## Scaling

### Manual Scaling

```bash
# Scale deployment
kubectl scale deployment valhalla-api -n valhalla --replicas=5

# Verify
kubectl get pods -n valhalla
```

### Update Configuration

```bash
# Edit ConfigMap
kubectl edit configmap valhalla-api-config -n valhalla

# Restart deployment to pick up changes
kubectl rollout restart deployment valhalla-api -n valhalla
```

## Updates and Rollbacks

### Deploy New Version

```bash
# Build and push new image
docker build -t valhalla-api:v1.1.0 app/
docker tag valhalla-api:v1.1.0 $ECR_REPO:v1.1.0
docker push $ECR_REPO:v1.1.0

# Update kustomization
cd k8s/overlays/dev
kustomize edit set image valhalla-api=$ECR_REPO:v1.1.0

# Apply
kubectl apply -k .

# Watch rollout
kubectl rollout status deployment/valhalla-api -n valhalla
```

### Rollback

```bash
# View history
kubectl rollout history deployment/valhalla-api -n valhalla

# Rollback to previous version
kubectl rollout undo deployment/valhalla-api -n valhalla

# Rollback to specific revision
kubectl rollout undo deployment/valhalla-api -n valhalla --to-revision=2
```

## Cleanup

### Delete Kubernetes Resources

```bash
kubectl delete -k k8s/overlays/dev
```

### Destroy Infrastructure

```bash
cd terraform/environments/dev
terraform destroy
```

**Warning**: This will delete all AWS resources including the EKS cluster, VPC, and ECR images.

## Cost Optimization

### Dev Environment

- Use single NAT Gateway: ~$35/month (configured by default)
- Use spot instances for node groups (recommended for dev)
- Scale down when not in use:

```bash
# Scale to 0 replicas
kubectl scale deployment valhalla-api -n valhalla --replicas=0

# Scale back up
kubectl scale deployment valhalla-api -n valhalla --replicas=3
```

### Estimated Costs

**Dev Environment** (minimal):
- EKS cluster: $72/month
- EC2 nodes (3 × t3.medium): ~$90/month
- NAT Gateway (1): ~$35/month
- ALB: ~$20/month
- **Total**: ~$217/month

**Production** (HA):
- EKS cluster: $72/month
- EC2 nodes (6 × t3.large): ~$360/month
- NAT Gateways (3): ~$105/month
- ALB: ~$20/month
- **Total**: ~$557/month

## Next Steps

1. ✅ Set up custom domain and SSL certificate in ACM
2. ✅ Configure Route 53 for DNS
3. ✅ Set up monitoring and alerting
4. ✅ Configure backup and disaster recovery
5. ✅ Implement CI/CD with GitHub Actions

## Support

For issues or questions:
1. Check application logs: `kubectl logs -n valhalla -l app=valhalla-api`
2. Review Kubernetes events: `kubectl get events -n valhalla`
3. Verify AWS resources in console
4. Check this documentation's troubleshooting section
