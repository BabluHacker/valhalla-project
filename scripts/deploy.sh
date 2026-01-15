#!/bin/bash

# Valhalla Deployment Script
# This script deploys infrastructure and application to AWS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="valhalla"

echo -e "${GREEN}=== Valhalla Deployment Script ===${NC}"
echo "Environment: $ENVIRONMENT"
echo "AWS Region: $AWS_REGION"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check prerequisites
echo "Checking prerequisites..."

command -v aws >/dev/null 2>&1 || { print_error "AWS CLI is required but not installed. Aborting."; exit 1; }
command -v terraform >/dev/null 2>&1 || { print_error "Terraform is required but not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed. Aborting."; exit 1; }
command -v docker >/dev/null 2>&1 || { print_error "Docker is required but not installed. Aborting."; exit 1; }

print_status "All prerequisites installed"

# Verify AWS credentials
echo ""
echo "Verifying AWS credentials..."
aws sts get-caller-identity > /dev/null 2>&1 || { print_error "AWS credentials not configured. Run 'aws configure'"; exit 1; }
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_status "AWS Account ID: $AWS_ACCOUNT_ID"

# Step 1: Deploy Infrastructure
echo ""
echo -e "${GREEN}Step 1: Deploying Infrastructure with Terraform${NC}"
cd terraform/environments/$ENVIRONMENT

if [ ! -f "terraform.tfvars" ]; then
    print_warning "terraform.tfvars not found, copying from example..."
    cp terraform.tfvars.example terraform.tfvars
    print_warning "Please update terraform.tfvars with your values and re-run"
    exit 1
fi

echo "Initializing Terraform..."
terraform init

echo "Planning infrastructure..."
terraform plan -out=tfplan

read -p "Apply infrastructure changes? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    print_warning "Deployment cancelled"
    exit 0
fi

echo "Applying infrastructure..."
terraform apply tfplan

# Get outputs
VPC_ID=$(terraform output -raw vpc_id)
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
ECR_REPO_URL=$(terraform output -json ecr_repository_urls | jq -r '.["valhalla-api"]')

print_status "Infrastructure deployed successfully"
print_status "VPC ID: $VPC_ID"
print_status "EKS Cluster: $EKS_CLUSTER_NAME"
print_status "ECR Repository: $ECR_REPO_URL"

cd ../../..

# Step 2: Configure kubectl
echo ""
echo -e "${GREEN}Step 2: Configuring kubectl${NC}"
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
print_status "kubectl configured"

# Verify cluster access
kubectl get nodes
print_status "Cluster access verified"

# Step 3: Install AWS Load Balancer Controller
echo ""
echo -e "${GREEN}Step 3: Installing AWS Load Balancer Controller${NC}"

# Check if already installed
if kubectl get deployment -n kube-system aws-load-balancer-controller >/dev/null 2>&1; then
    print_status "AWS Load Balancer Controller already installed"
else
    echo "Installing AWS Load Balancer Controller..."
    
    # Create IAM policy if doesn't exist
    if ! aws iam get-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy >/dev/null 2>&1; then
        curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json
        aws iam create-policy \
            --policy-name AWSLoadBalancerControllerIAMPolicy \
            --policy-document file://iam_policy.json
        rm iam_policy.json
    fi
    
    # Install using Helm
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName=$EKS_CLUSTER_NAME \
        --set serviceAccount.create=true \
        --set region=$AWS_REGION \
        --set vpcId=$VPC_ID
    
    print_status "AWS Load Balancer Controller installed"
fi

# Step 4: Build and Push Docker Image
echo ""
echo -e "${GREEN}Step 4: Building and Pushing Docker Image${NC}"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
print_status "Logged in to ECR"

# Build image
cd app
docker build -t valhalla-api:latest .
print_status "Docker image built"

# Tag and push
docker tag valhalla-api:latest $ECR_REPO_URL:latest
docker tag valhalla-api:latest $ECR_REPO_URL:$ENVIRONMENT-$(git rev-parse --short HEAD)
docker push $ECR_REPO_URL:latest
docker push $ECR_REPO_URL:$ENVIRONMENT-$(git rev-parse --short HEAD)
print_status "Image pushed to ECR"

cd ..

# Step 5: Update Kustomization with ECR URL
echo ""
echo -e "${GREEN}Step 5: Updating Kubernetes Manifests${NC}"

# Update kustomization.yaml with actual ECR URL
sed -i.bak "s|<AWS_ACCOUNT_ID>|$AWS_ACCOUNT_ID|g" k8s/overlays/$ENVIRONMENT/kustomization.yaml
rm k8s/overlays/$ENVIRONMENT/kustomization.yaml.bak
print_status "Kustomization updated with ECR URL"

# Step 6: Deploy to Kubernetes
echo ""
echo -e "${GREEN}Step 6: Deploying to Kubernetes${NC}"

# Apply manifests
kubectl apply -k k8s/overlays/$ENVIRONMENT
print_status "Kubernetes manifests applied"

# Wait for deployment
echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/valhalla-api -n valhalla

print_status "Deployment ready"

# Step 7: Verify Deployment
echo ""
echo -e "${GREEN}Step 7: Verifying Deployment${NC}"

echo "Pods:"
kubectl get pods -n valhalla

echo ""
echo "Services:"
kubectl get svc -n valhalla

echo ""
echo "Ingress:"
kubectl get ingress -n valhalla

# Get ALB URL
echo ""
echo "Waiting for ALB to be provisioned (this may take a few minutes)..."
sleep 30

ALB_URL=$(kubectl get ingress valhalla-api -n valhalla -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -n "$ALB_URL" ]; then
    print_status "Application Load Balancer: $ALB_URL"
    echo ""
    echo "Testing health endpoint..."
    curl -f http://$ALB_URL/health && print_status "Health check passed" || print_error "Health check failed"
else
    print_warning "ALB URL not available yet. Check 'kubectl get ingress -n valhalla' in a few minutes"
fi

# Step 8: Summary
echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "EKS Cluster: $EKS_CLUSTER_NAME"
echo "Namespace: valhalla"
echo ""
echo "Useful commands:"
echo "  kubectl get pods -n valhalla"
echo "  kubectl logs -n valhalla -l app=valhalla-api --tail=100 -f"
echo "  kubectl get ingress -n valhalla"
echo ""
echo "To access the application:"
echo "  curl http://$ALB_URL/health"
echo "  curl http://$ALB_URL/api/v1/status"
echo ""
