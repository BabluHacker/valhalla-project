# Getting Started with Valhalla

This guide will help you set up and deploy the Valhalla platform from scratch.

## Prerequisites

### Required Tools

1. **Git** - Version control
2. **Node.js 18+** - For running the application
3. **Docker Desktop** - For containerization
4. **Terraform 1.5+** - For infrastructure provisioning
5. **kubectl** - Kubernetes command-line tool
6. **AWS CLI v2** - AWS command-line interface

### AWS Account Setup

1. Create an AWS account (if you don't have one)
2. Create an IAM user with appropriate permissions
3. Configure AWS CLI:
   ```bash
   aws configure
   ```

### GitHub Setup

1. Fork or clone the repository
2. Set up repository secrets for GitHub Actions

## Step-by-Step Setup

### 1. Clone the Repository

```bash
git clone <your-repo-url>
cd valhalla-project
```

### 2. Test the Application Locally

```bash
cd app
npm install
npm test
npm run dev
```

Visit `http://localhost:3000/health` to verify the app is running.

### 3. Build and Test Docker Image

```bash
cd app
docker build -t valhalla-api:local .
docker run -p 3000:3000 valhalla-api:local
```

### 4. Set Up AWS Infrastructure

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply infrastructure (confirm when prompted)
terraform apply
```

This will create:
- VPC with public/private subnets
- EKS cluster
- ECR repository
- Security groups
- IAM roles

**Note**: This step will incur AWS costs. Review the [cost analysis](cost-analysis.md) first.

### 5. Configure kubectl

```bash
# Update kubeconfig for EKS cluster
aws eks update-kubeconfig \
  --region us-east-1 \
  --name valhalla-dev-cluster

# Verify connection
kubectl get nodes
```

### 6. Deploy to Kubernetes

```bash
# Deploy the application
kubectl apply -k k8s/overlays/dev

# Check deployment status
kubectl get pods -n valhalla
kubectl get services -n valhalla
kubectl get ingress -n valhalla
```

### 7. Set Up CI/CD

1. Add GitHub Secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION`
   - `ECR_REPOSITORY`
   - `EKS_CLUSTER_NAME`

2. Push code to trigger the pipeline:
   ```bash
   git add .
   git commit -m "Initial deployment"
   git push origin main
   ```

### 8. Verify Deployment

```bash
# Check pod status
kubectl get pods -n valhalla

# View logs
kubectl logs -f deployment/valhalla-api -n valhalla

# Get the load balancer URL
kubectl get ingress -n valhalla
```

## Next Steps

- Review [Architecture Documentation](architecture.md)
- Set up [Monitoring](observability.md)
- Configure [Alerting](observability.md#alerting)
- Review [Security Best Practices](security.md)
- Read [Incident Response Playbook](incident-response.md)

## Troubleshooting

### Issue: EKS cluster not accessible

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name valhalla-dev-cluster
```

### Issue: Pods not starting

```bash
# Describe pod for errors
kubectl describe pod <pod-name> -n valhalla

# Check logs
kubectl logs <pod-name> -n valhalla
```

### Issue: Cannot access application

```bash
# Check ingress
kubectl get ingress -n valhalla

# Verify ALB is created
aws elbv2 describe-load-balancers
```

## Clean Up

To avoid ongoing AWS charges:

```bash
# Delete Kubernetes resources
kubectl delete -k k8s/overlays/dev

# Destroy infrastructure
cd terraform/environments/dev
terraform destroy
```

## Support

For issues or questions, please refer to:
- [Documentation](../README.md#documentation)
- [Incident Response](incident-response.md)
- [Runbooks](runbooks/)
