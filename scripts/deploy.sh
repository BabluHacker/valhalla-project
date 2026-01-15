#!/bin/bash

# Valhalla Deployment Script
# This script deploys infrastructure and Valhalla routing engine to AWS

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
command -v helm >/dev/null 2>&1 || { print_error "Helm is required but not installed. Aborting."; exit 1; }

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

# Check if tfvars exists
if [ ! -f "terraform/environments/$ENVIRONMENT/terraform.tfvars" ]; then
    print_warning "terraform.tfvars not found, copying from example..."
    cp terraform/environments/$ENVIRONMENT/terraform.tfvars.example terraform/environments/$ENVIRONMENT/terraform.tfvars
    print_warning "Please update terraform/environments/$ENVIRONMENT/terraform.tfvars with your values and re-run"
    exit 1
fi

cd terraform

echo "Initializing Terraform..."
terraform init

echo "Planning infrastructure..."
terraform plan -var-file="environments/$ENVIRONMENT/terraform.tfvars" -out=tfplan

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

print_status "Infrastructure deployed successfully"
print_status "VPC ID: $VPC_ID"
print_status "EKS Cluster: $EKS_CLUSTER_NAME"

cd ..

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
    
    # Install using Helm
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName=$EKS_CLUSTER_NAME \
        --set serviceAccount.create=true \
        --set region=$AWS_REGION \
        --set vpcId=$VPC_ID
    
    # Wait for deployment
    echo "Waiting for ALB controller to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/aws-load-balancer-controller -n kube-system
    
    print_status "AWS Load Balancer Controller installed"
fi

# Step 4: Install Metrics Server
echo ""
echo -e "${GREEN}Step 4: Installing Metrics Server${NC}"

if kubectl get deployment -n kube-system metrics-server >/dev/null 2>&1; then
    print_status "Metrics Server already installed"
else
    echo "Installing Metrics Server..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Wait for deployment
    echo "Waiting for Metrics Server to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/metrics-server -n kube-system
    
    print_status "Metrics Server installed"
fi

# Step 5: Deploy Valhalla Routing Engine
echo ""
echo -e "${GREEN}Step 5: Deploying Valhalla Routing Engine${NC}"
print_status "Using official ghcr.io/gis-ops/docker-valhalla/valhalla:latest"

# Apply manifests
kubectl apply -k k8s/overlays/$ENVIRONMENT
print_status "Kubernetes manifests applied"

# Wait for deployment
echo "Waiting for Valhalla pods to be ready (this may take 2-3 minutes)..."
echo "Init container will download map data on first deployment..."
kubectl wait --for=condition=available --timeout=300s deployment/valhalla-api -n valhalla || {
    print_warning "Deployment did not become ready within 5 minutes"
    echo "Checking pod status..."
    kubectl get pods -n valhalla
    kubectl describe pod -n valhalla -l app=valhalla-api
}

print_status "Valhalla deployment ready"

# Step 6: Verify Deployment
echo ""
echo -e "${GREEN}Step 6: Verifying Deployment${NC}"

echo "Pods:"
kubectl get pods -n valhalla

echo ""
echo "Services:"
kubectl get svc -n valhalla

echo ""
echo "Ingress:"
kubectl get ingress -n valhalla

echo ""
echo "PersistentVolumeClaim:"
kubectl get pvc -n valhalla

# Get ALB URL
echo ""
echo "Waiting for ALB to be provisioned (this may take 2-3 minutes)..."
sleep 60

ALB_URL=$(kubectl get ingress valhalla-api -n valhalla -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$ALB_URL" ]; then
    print_status "Application Load Balancer: $ALB_URL"
    echo ""
    echo "Testing status endpoint..."
    
    # Try status check with retry
    for i in {1..5}; do
        if curl -f -s http://$ALB_URL/status > /dev/null 2>&1; then
            print_status "Status check passed"
            break
        else
            if [ $i -lt 5 ]; then
                echo "Attempt $i failed, retrying in 30 seconds..."
                sleep 30
            else
                print_warning "Status check failed after 5 attempts"
                echo "ALB may still be warming up. Try manually: curl http://$ALB_URL/status"
            fi
        fi
    done
else
    print_warning "ALB URL not available yet. Check 'kubectl get ingress -n valhalla' in a few minutes"
fi

# Step 7: Summary
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

if [ -n "$ALB_URL" ]; then
    echo "To access Valhalla routing engine:"
    echo "  Health: curl http://$ALB_URL/status"
    echo ""
    echo "  Route: curl http://$ALB_URL/route \\"
    echo "    --data '{\"locations\":[{\"lat\":52.09,\"lon\":5.12},{\"lat\":52.10,\"lon\":5.11}],\"costing\":\"auto\"}' \\"
    echo "    -H 'Content-Type: application/json'"
    echo ""
    echo "  Isochrone: curl http://$ALB_URL/isochrone \\"
    echo "    --data '{\"locations\":[{\"lat\":52.09,\"lon\":5.12}],\"costing\":\"auto\",\"contours\":[{\"time\":10}]}' \\"
    echo "    -H 'Content-Type: application/json'"
else
    echo "Run 'kubectl get ingress -n valhalla' to get the ALB URL once it's ready"
fi

echo ""
print_status "Deployment completed successfully!"
