# Valhalla Routing Engine - Deployment Guide

Complete step-by-step guide for deploying Valhalla routing engine to AWS.

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
1. ✅ Deploy infrastructure with Terraform (~15-20 minutes)
2. ✅ Configure kubectl for EKS
3. ✅ Install AWS Load Balancer Controller
4. ✅ Deploy Valhalla routing engine with sample data
5. ✅ Verify deployment

### Option 2: Manual Step-by-Step Deployment

For learning or debugging, follow these manual steps:

#### Step 1: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review what will be created
terraform plan -var-file="environments/dev/terraform.tfvars"

# Apply infrastructure (takes ~15-20 minutes)
terraform apply -var-file="environments/dev/terraform.tfvars"
```

**Expected time**: 15-20 minutes (EKS cluster creation is slow)

**Resources created**:
- VPC with public/private subnets across 3 AZs
- NAT Gateway (1 for dev, 3 for prod)
- Internet Gateway
- EKS cluster (Kubernetes 1.28)
- EKS managed node groups (3 t3.medium nodes)
- Security groups
- IAM roles and policies
- ECR repository (unused - using official image)
- CloudWatch log groups

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

#### Step 3: Install AWS Load Balancer Controller

```bash
# Add Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get VPC ID and cluster name
VPC_ID=$(cd terraform && terraform output -raw vpc_id)
CLUSTER_NAME=$(cd terraform && terraform output -raw eks_cluster_name)

# Install controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set region=us-east-1 \
  --set vpcId=$VPC_ID

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

#### Step 4: Install Metrics Server (for HPA)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl get deployment metrics-server -n kube-system
```

#### Step 5: Deploy Valhalla Routing Engine

```bash
# Preview manifests
kubectl kustomize k8s/overlays/dev

# Apply manifests (creates namespace, PVC, deployment, service, ingress, HPA)
kubectl apply -k k8s/overlays/dev

# Watch deployment progress
kubectl get pods -n valhalla -w
```

**What happens:**
1. Namespace created
2. 50GB PersistentVolume provisioned (EBS gp3)
3. Init container downloads Utrecht map data (~50MB)
4. Valhalla pods start (2 replicas for dev)
5. Service exposes port 8002
6. Ingress creates Application Load Balancer (~2-3 minutes)

Wait until all pods show `Running` status and `2/2` ready.

#### Step 6: Verify Deployment

```bash
# Check all resources
kubectl get all -n valhalla

# Check PVC
kubectl get pvc -n valhalla

# Check pod logs
kubectl logs -n valhalla -l app=valhalla-api --tail=50

# Check init container logs (map download)
POD=$(kubectl get pods -n valhalla -l app=valhalla-api -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n valhalla $POD -c download-tiles

# Check ingress
kubectl describe ingress valhalla-api -n valhalla

# Get ALB URL (wait 2-3 minutes for provisioning)
ALB_URL=$(kubectl get ingress valhalla-api -n valhalla -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Valhalla URL: http://$ALB_URL"
```

#### Step 7: Test Valhalla Routing Engine

```bash
# Health check
curl http://$ALB_URL/status

# Get a route (Utrecht coordinates)
curl http://$ALB_URL/route \
  --data '{
    "locations": [
      {"lat": 52.0907, "lon": 5.1214},
      {"lat": 52.0938, "lon": 5.1182}
    ],
    "costing": "auto",
    "directions_options": {"units": "kilometers"}
  }' \
  -H "Content-Type: application/json"

# Get isochrone (10 and 20 minute drive times)
curl http://$ALB_URL/isochrone \
  --data '{
    "locations": [{"lat": 52.0907, "lon": 5.1214}],
    "costing": "auto",
    "contours": [{"time": 10}, {"time": 20}]
  }' \
  -H "Content-Type: application/json"
```

## Monitoring Deployment

### Watch Pods

```bash
# Watch pods come up
kubectl get pods -n valhalla -w

# Describe a pod
kubectl describe pod <pod-name> -n valhalla
```

### View Logs

```bash
# All Valhalla pods
kubectl logs -n valhalla -l app=valhalla-api -f --tail=100

# Specific pod - Valhalla container
kubectl logs -n valhalla <pod-name> -c valhalla -f

# Init container (map download)
kubectl logs -n valhalla <pod-name> -c download-tiles
```

### Check HPA

```bash
# Watch autoscaler
kubectl get hpa -n valhalla -w

# Pod metrics
kubectl top pods -n valhalla

# Node metrics
kubectl top nodes
```

### Check Ingress and ALB

```bash
# Ingress details
kubectl describe ingress valhalla-api -n valhalla

# Get ALB URL
kubectl get ingress valhalla-api -n valhalla -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Check ALB in AWS Console
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'valhalla')]"
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n valhalla

# Describe pod to see events
kubectl describe pod <pod-name> -n valhalla

# Check init container logs
kubectl logs <pod-name> -n valhalla -c download-tiles

# Check Valhalla container logs
kubectl logs <pod-name> -n valhalla -c valhalla
```

**Common issues:**
- PVC not binding: Check storage class `kubectl get sc`
- Image pull errors: Verify internet connectivity from nodes
- Map download fails: Check init container logs

### PVC Issues

```bash
# Check PVC status
kubectl get pvc -n valhalla

# Describe PVC
kubectl describe pvc valhalla-data -n valhalla

# Check PersistentVolume
kubectl get pv

# Check storage class
kubectl get sc
```

### ALB Not Created

```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100

# Verify ingress annotations
kubectl get ingress valhalla-api -n valhalla -o yaml

# Check AWS events
aws elbv2 describe-target-health --target-group-arn <arn>
```

### Routing Requests Failing

```bash
# Check if pods are ready
kubectl get pods -n valhalla

# Test from within cluster
kubectl run -it --rm debug --image=alpine --restart=Never -- sh
apk add curl
curl http://valhalla-api.valhalla.svc.cluster.local/status

# Check service endpoints
kubectl get endpoints valhalla-api -n valhalla
```

**Common issues:**
- Coordinates outside map coverage (currently only Utrecht)
- Invalid JSON in request
- Pod not ready (check readiness probe)

## Scaling

### Manual Scaling

```bash
# Scale deployment
kubectl scale deployment valhalla-api -n valhalla --replicas=5

# Verify
kubectl get pods -n valhalla
```

### Auto-scaling (HPA)

HPA is configured to scale based on:
- CPU usage > 70%
- Memory usage > 80%

```bash
# View HPA status
kubectl get hpa -n valhalla

# Describe HPA
kubectl describe hpa valhalla-api -n valhalla
```

### Update Configuration

Map data is stored in PVC and persists across deployments. To change map region:

1. Delete existing PVC: `kubectl delete pvc valhalla-data -n valhalla`
2. Update init container in `k8s/base/deployment.yaml` to download new region
3. Redeploy: `kubectl apply -k k8s/overlays/dev`

## Updates and Rollbacks

### Update Valhalla Version

```bash
# Update to specific version
kubectl set image deployment/valhalla-api \
  valhalla=ghcr.io/gis-ops/docker-valhalla/valhalla:v3.2.0 \
  -n valhalla

# Watch rollout
kubectl rollout status deployment/valhalla-api -n valhalla
```

### Rollback Deployment

```bash
# View history
kubectl rollout history deployment/valhalla-api -n valhalla

# Rollback to previous version
kubectl rollout undo deployment/valhalla-api -n valhalla

# Rollback to specific revision
kubectl rollout undo deployment/valhalla-api -n valhalla --to-revision=2
```

### Update Resources

```bash
# Edit deployment
kubectl edit deployment valhalla-api -n valhalla

# Or update via kustomize
vim k8s/overlays/dev/deployment-patch.yaml
kubectl apply -k k8s/overlays/dev
```

## Cleanup

### Delete Kubernetes Resources

```bash
# Delete all Valhalla resources
kubectl delete -k k8s/overlays/dev

# Or delete namespace (removes everything)
kubectl delete namespace valhalla
```

### Destroy Infrastructure

```bash
cd terraform

# Preview destruction
terraform plan -destroy -var-file="environments/dev/terraform.tfvars"

# Destroy all AWS resources
terraform destroy -var-file="environments/dev/terraform.tfvars"
```

**Warning**: This will permanently delete:
- EKS cluster and all workloads
- VPC and networking
- Load balancers
- EBS volumes (map data will be lost)
- CloudWatch logs

## Cost Optimization

### Dev Environment

To reduce costs:

```bash
# Scale down when not in use
kubectl scale deployment valhalla-api -n valhalla --replicas=0

# Scale back up
kubectl scale deployment valhalla-api -n valhalla --replicas=2

# Or delete entirely and redeploy when needed
kubectl delete -k k8s/overlays/dev
```

### Estimated Costs

**Dev Environment** (~$400/month):
- EKS cluster control plane: $72/month
- EC2 nodes (3 × t3.medium): ~$90/month
- NAT Gateway (1): ~$35/month
- ALB: ~$20/month
- EBS storage (50GB + node volumes): ~$20/month
- Data transfer: ~$20/month

**Production** (~$1,500/month):
- EKS cluster: $72/month
- EC2 nodes (6 × t3.large): ~$360/month
- NAT Gateways (3 for HA): ~$105/month
- ALB: ~$20/month
- EBS storage (200GB): ~$40/month
- Data transfer: ~$100/month

**Cost Reduction Tips:**
- Use Spot instances for dev (save 70%)
- Single NAT Gateway for dev (save $70/month)
- Smaller map regions (save storage costs)
- Auto-shutdown dev environment nights/weekends

## Production Deployment

For production:

1. Use separate VPC: `terraform.tfvars` with `environment = "prod"`
2. Set `single_nat_gateway = false` for HA
3. Increase node count: `node_group_min_size = 6`
4. Use larger instances: `t3.large` or `c5.xlarge`
5. Set up DNS with Route 53
6. Configure SSL certificate in ACM
7. Enable WAF for security
8. Set up monitoring and alerting
9. Configure backup for PVC
10. Implement disaster recovery plan

## Next Steps

After successful deployment:

1. **Custom Map Data**: See [Valhalla Routing Guide](valhalla-routing.md)
2. **Monitoring**: Set up Prometheus/Grafana
3. **CI/CD**: Configure GitHub Actions workflows
4. **DNS**: Point custom domain to ALB
5. **SSL**: Configure HTTPS with ACM certificate
6. **Security**: Implement network policies
7. **Backup**: Snapshot PVC with map data

## Support

For issues:
1. Check pod logs: `kubectl logs -n valhalla -l app=valhalla-api`
2. Check events: `kubectl get events -n valhalla --sort-by='.lastTimestamp'`
3. Verify AWS resources in console
4. Review [Valhalla documentation](https://valhalla.readthedocs.io/)
5. Check [troubleshooting guide](valhalla-routing.md#troubleshooting)

## References

- [Valhalla Documentation](https://valhalla.readthedocs.io/)
- [Docker Valhalla](https://github.com/gis-ops/docker-valhalla)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
