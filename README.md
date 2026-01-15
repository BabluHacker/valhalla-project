# Valhalla Routing Engine - DevOps Platform

Production-ready Valhalla routing engine deployment on AWS EKS with complete DevOps automation.

## Project Overview

This project deploys the [Valhalla routing engine](https://github.com/valhalla/valhalla) - an open-source routing and navigation engine that processes OpenStreetMap data to provide:
- Turn-by-turn routing
- Isochrones (time/distance polygons)
- Map matching
- Optimized route planning
- Multiple travel modes (auto, bicycle, pedestrian)

## Architecture

### Infrastructure (AWS)
- **EKS Cluster**: Managed Kubernetes 1.28
- **VPC**: Multi-AZ across 3 availability zones
- **NAT Gateways**: High availability networking
- **Application Load Balancer**: HTTPS traffic management
- **ECR**: Container registry (not used - using official image)
- **CloudWatch**: Centralized logging and monitoring
- **EBS**: Persistent storage for map tiles (50GB)

### Application
- **Image**: `ghcr.io/gis-ops/docker-valhalla/valhalla:latest`
- **Storage**: 50GB PersistentVolume for map tiles
- **Sample Data**: Utrecht, Netherlands (~50MB)
- **Autoscaling**: 2-10 pods based on CPU/Memory
- **Resources**: 2Gi memory, 2 CPUs per pod

## Quick Start

### Prerequisites

```bash
# Install required tools
brew install terraform kubectl helm kustomize awscli

# Configure AWS credentials
aws configure
```

### Deploy Infrastructure & Application

```bash
# One-command deployment
./scripts/deploy.sh dev
```

This will:
1. Deploy AWS infrastructure with Terraform (~20 minutes)
2. Configure EKS cluster access
3. Install AWS Load Balancer Controller
4. Deploy Valhalla routing engine
5. Verify deployment

### Test Valhalla

```bash
# Get ALB URL
kubectl get ingress -n valhalla

# Test routing
curl http://<ALB_URL>/route \
  --data '{
    "locations": [
      {"lat": 52.0907, "lon": 5.1214},
      {"lat": 52.0938, "lon": 5.1182}
    ],
    "costing": "auto"
  }' \
  -H "Content-Type: application/json"
```

## Project Structure

```
.
├── terraform/              # Infrastructure as Code
│   ├── modules/
│   │   ├── networking/    # VPC, subnets, NAT gateways
│   │   ├── security/      # Security groups
│   │   ├── eks/           # EKS cluster and node groups
│   │   └── ecr/           # Container registry (unused)
│   └── environments/      # Dev/Staging/Prod configs
├── k8s/                   # Kubernetes manifests
│   ├── base/              # Base configuration
│   └── overlays/          # Environment-specific overrides
├── scripts/               # Automation scripts
│   ├── deploy.sh         # Full deployment automation
│   └── test.sh           # Deployment testing
├── docs/                  # Documentation
│   ├── architecture.md    # Architecture overview
│   ├── decisions.md       # Architecture Decision Records
│   ├── deployment.md      # Deployment guide
│   └── valhalla-routing.md # Valhalla-specific docs
└── .github/workflows/     # CI/CD pipelines
```

## Infrastructure Details

### Networking
- **VPC CIDR**: 10.0.0.0/16
- **Public Subnets**: 3 (one per AZ) for ALB, NAT
- **Private Subnets**: 3 (one per AZ) for EKS nodes
- **NAT Gateways**: 1 (dev) or 3 (prod) for HA

### Compute
- **EKS Version**: 1.28
- **Node Instance**: t3.medium (dev), t3.large (prod)
- **Node Count**: 3-6 (dev), 6-15 (prod)
- **Auto-scaling**: Cluster Autoscaler enabled

### Security
- **IAM Roles**: Cluster, node groups, IRSA ready
- **Security Groups**: Least-privilege rules
- **Encryption**: EBS volumes, secrets at rest
- **Network Policies**: Pod-to-pod isolation

## Valhalla Configuration

### Current Setup
- **Map Data**: Utrecht, Netherlands (sample)
- **Replicas**: 2 (dev), 6 (prod)
- **Resources**: 2Gi RAM, 2 CPU per pod
- **Storage**: 50GB PVC (gp3)

### API Endpoints

```bash
# Health check
GET /status

# Routing
POST /route
{
  "locations": [{"lat": 52.09, "lon": 5.12}, {"lat": 52.10, "lon": 5.11}],
  "costing": "auto"
}

# Isochrone
POST /isochrone
{
  "locations": [{"lat": 52.09, "lon": 5.12}],
  "costing": "auto",
  "contours": [{"time": 10}, {"time": 20}]
}

# Map matching
POST /trace_route
{
  "shape": [{"lat": 52.09, "lon": 5.12}, {"lat": 52.10, "lon": 5.11}],
  "costing": "auto"
}
```

## Deployment Environments

| Environment | Replicas | Storage | Instance Type | Auto-Deploy |
|-------------|----------|---------|---------------|-------------|
| **Dev** | 2-10 | 50GB | t3.medium | On push |
| **Staging** | 3-15 | 100GB | t3.large | On merge |
| **Production** | 6-30 | 200GB | t3.large | Manual |

## Cost Estimates

### Dev Environment (~$400/month)
- EKS cluster: $72
- EC2 nodes (3 × t3.medium): $90
- NAT Gateway (1): $35
- ALB: $20
- EBS storage (150GB): $15
- Data transfer: ~$20

### Production (~$1,500/month)
- EKS cluster: $72
- EC2 nodes (6 × t3.large): $360
- NAT Gateways (3): $105
- ALB: $20
- EBS storage (600GB): $60
- Data transfer: ~$100

## Monitoring & Operations

### Logs
```bash
# View Valhalla logs
kubectl logs -n valhalla -l app=valhalla-api -f

# View init container logs (map download)
kubectl logs -n valhalla <pod> -c download-tiles
```

### Scaling
```bash
# Manual scale
kubectl scale deployment valhalla-api -n valhalla --replicas=5

# View HPA status
kubectl get hpa -n valhalla
```

### Updates
```bash
# Update to new Valhalla version
kubectl set image deployment/valhalla-api \
  valhalla=ghcr.io/gis-ops/docker-valhalla/valhalla:v3.2.0 \
  -n valhalla

# Rollback
kubectl rollout undo deployment/valhalla-api -n valhalla
```

## CI/CD Pipeline

### GitHub Actions Workflows
- **CI**: Tests, validation, security scanning
- **CD**: Automated deployment to environments

### Deployment Flow
1. Push code → CI validates
2. Merge to main → Deploy to staging
3. Manual trigger → Deploy to production

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Architecture Decisions (ADRs)](docs/decisions.md)
- [Deployment Guide](docs/deployment.md)
- [Valhalla Routing Guide](docs/valhalla-routing.md)

## Map Data Management

### Using Custom Regions

1. Download OSM data from [Geofabrik](https://download.geofabrik.de/)
2. Build tiles with Valhalla
3. Upload to S3
4. Update init container to download from S3

See [Valhalla Routing Guide](docs/valhalla-routing.md) for details.

## Cleanup

```bash
# Delete Kubernetes resources
kubectl delete -k k8s/overlays/dev

# Destroy infrastructure
cd terraform
terraform destroy -var-file="environments/dev/terraform.tfvars"
```

## Testing

```bash
# Run comprehensive tests
./scripts/test.sh dev
```

## Support

For issues:
1. Check pod logs: `kubectl logs -n valhalla -l app=valhalla-api`
2. Check events: `kubectl get events -n valhalla`
3. Review documentation in `docs/`

## License

This infrastructure code is provided as-is for the DevOps take-home challenge.

Valhalla routing engine: [Valhalla License](https://github.com/valhalla/valhalla/blob/master/LICENSE.md)

---

**Built with**: Terraform, Kubernetes, AWS EKS, Valhalla Routing Engine
