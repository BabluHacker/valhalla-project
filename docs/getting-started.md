# Valhalla Platform - Quick Start Guide

This guide helps you get up and running with the Valhalla routing engine on AWS in under 30 minutes.

## What You'll Deploy

- **Valhalla Routing Engine**: Open-source routing with OSM data
- **AWS EKS**: Managed Kubernetes cluster
- **High Availability**: Multi-AZ deployment
- **Auto-scaling**: Based on CPU/memory metrics
- **Production-ready**: Security, monitoring, and best practices

## Prerequisites (5 minutes)

### 1. Install Tools

```bash
# macOS
brew install terraform kubectl helm kustomize awscli

# Verify installations
terraform version  # Should be >= 1.5.0
kubectl version --client
helm version
aws --version
```

### 2. Configure AWS

```bash
# Set up AWS credentials
aws configure

# Verify access
aws sts get-caller-identity
```

You should see your AWS account information.

## Deployment (20 minutes)

### Method 1: Automated (Recommended)

```bash
# Clone or navigate to project
cd valhalla-project

# Run deployment script
./scripts/deploy.sh dev
```

The script will:
1. ✅ Deploy AWS infrastructure (VPC, EKS, Security Groups)
2. ✅ Configure kubectl
3. ✅ Install AWS Load Balancer Controller
4. ✅ Deploy Valhalla with sample map data
5. ✅ Verify everything works

**Total time**: ~20 minutes (EKS cluster creation is slowest part)

### Method 2: Manual Steps

If you prefer step-by-step control:

```bash
# 1. Deploy infrastructure
cd terraform
terraform init
terraform apply -var-file="environments/dev/terraform.tfvars"

# 2. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw eks_cluster_name)

# 3. Install ALB controller
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$(terraform output -raw eks_cluster_name) \
  --set serviceAccount.create=true

# 4. Deploy Valhalla
kubectl apply -k k8s/overlays/dev
kubectl wait --for=condition=available --timeout=300s deployment/valhalla-api -n valhalla

# 5. Get ALB URL
kubectl get ingress -n valhalla
```

## Test Your Deployment (2 minutes)

```bash
# Get the Application Load Balancer URL
ALB_URL=$(kubectl get ingress valhalla-api -n valhalla -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test health endpoint
curl http://$ALB_URL/status

# Get a route (Utrecht, Netherlands coordinates)
curl http://$ALB_URL/route \
  --data '{
    "locations": [
      {"lat": 52.0907, "lon": 5.1214},
      {"lat": 52.0938, "lon": 5.1182}
    ],
    "costing": "auto"
  }' \
  -H "Content-Type: application/json"
```

You should get a JSON response with turn-by-turn directions!

## What Was Deployed

### AWS Infrastructure
- **VPC**: 10.0.0.0/16 across 3 availability zones
- **EKS Cluster**: Kubernetes 1.28 with managed control plane
- **Worker Nodes**: 3 × t3.medium instances
- **Load Balancer**: Application Load Balancer with HTTPS support
- **Storage**: 50GB EBS volume for map data
- **Security**: Security groups, IAM roles, encryption

### Kubernetes Resources
- **Namespace**: `valhalla`
- **Deployment**: 2 Valhalla pods with auto-scaling
- **Service**: ClusterIP exposing port 8002
- **Ingress**: ALB configuration for external access
- **PVC**: 50GB persistent volume for map tiles
- **HPA**: Auto-scaling based on CPU/memory

### Sample Map Data
- **Region**: Utrecht, Netherlands
- **Size**: ~50MB compressed
- **Coverage**: City of Utrecht and surroundings

## Common Tasks

### View Logs

```bash
# All Valhalla pods
kubectl logs -n valhalla -l app=valhalla-api -f

# Specific pod
kubectl logs -n valhalla <pod-name> -c valhalla
```

### Scale Manually

```bash
# Increase replicas
kubectl scale deployment valhalla-api -n valhalla --replicas=5

# Check status
kubectl get pods -n valhalla
```

### Check Auto-scaling

```bash
# View HPA status
kubectl get hpa -n valhalla

# Pod metrics
kubectl top pods -n valhalla
```

### Update Valhalla

```bash
# Update to new version
kubectl set image deployment/valhalla-api \
  valhalla=ghcr.io/gis-ops/docker-valhalla/valhalla:v3.2.0 \
  -n valhalla

# Watch rollout
kubectl rollout status deployment/valhalla-api -n valhalla
```

## Troubleshooting

### Pods Not Running

```bash
# Check pod status
kubectl get pods -n valhalla

# Describe pod
kubectl describe pod <pod-name> -n valhalla

# Check init container (map download)
kubectl logs <pod-name> -n valhalla -c download-tiles
```

### Can't Access Valhalla

```bash
# Check ingress
kubectl get ingress -n valhalla

# Check ALB controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify service endpoints
kubectl get endpoints valhalla-api -n valhalla
```

### Routing Errors

Make sure coordinates are within map coverage (currently Utrecht, Netherlands).

**Utrecht bounds:**
- Latitude: 52.0 - 52.2
- Longitude: 5.0 - 5.2

## Cost Estimate

**Dev environment** (what you just deployed):
- ~$400/month with full-time operation
- ~$150/month if scaled down when not in use

**Main costs:**
- EKS cluster: $72/month (control plane)
- EC2 instances: $90/month (3 nodes)
- NAT Gateway: $35/month
- Load Balancer: $20/month
- Storage & data transfer: ~$40/month

**Cost saving tip**: Scale to 0 replicas when not using:
```bash
kubectl scale deployment valhalla-api -n valhalla --replicas=0
```

## Cleanup

To avoid ongoing charges:

```bash
# Delete Kubernetes resources
kubectl delete -k k8s/overlays/dev

# Destroy infrastructure
cd terraform
terraform destroy -var-file="environments/dev/terraform.tfvars"
```

**Warning**: This deletes everything including map data.

## Next Steps

1. **Custom Map Data**: [Load different regions](valhalla-routing.md#using-custom-regions)
2. **Production Setup**: [Deploy to prod environment](deployment.md#production-deployment)
3. **Monitoring**: Set up Prometheus and Grafana
4. **SSL/DNS**: Configure custom domain with HTTPS
5. **CI/CD**: Set up automated deployments

## Need Help?

- **Detailed Deployment**: See [deployment.md](deployment.md)
- **Valhalla Specifics**: See [valhalla-routing.md](valhalla-routing.md)
- **Architecture**: See [architecture.md](architecture.md)
- **Terraform**: See [terraform/README.md](../terraform/README.md)
- **Kubernetes**: See [k8s/README.md](../k8s/README.md)

## API Examples

Once deployed, try these:

```bash
# Health check
curl http://$ALB_URL/status

# Route (driving)
curl http://$ALB_URL/route --data '{"locations":[{"lat":52.09,"lon":5.12},{"lat":52.10,"lon":5.11}],"costing":"auto"}' -H "Content-Type: application/json"

# Route (cycling)
curl http://$ALB_URL/route --data '{"locations":[{"lat":52.09,"lon":5.12},{"lat":52.10,"lon":5.11}],"costing":"bicycle"}' -H "Content-Type: application/json"

# Isochrone (10min drive time)
curl http://$ALB_URL/isochrone --data '{"locations":[{"lat":52.09,"lon":5.12}],"costing":"auto","contours":[{"time":10}]}' -H "Content-Type: application/json"
```

---

**Congratulations!** 🎉 You now have a production-ready Valhalla routing engine running on AWS!
