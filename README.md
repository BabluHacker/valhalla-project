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
- **EKS Cluster**: Managed Kubernetes 1.29
- **VPC**: Multi-AZ across 3 availability zones
- **NAT Gateways**: High availability networking
- **Network Load Balancer**: Public internet access
- **ECR**: Container registry (created but unused - using official image)
- **CloudWatch**: Centralized logging and monitoring
- **EBS**: Persistent storage for map tiles (50GB gp2)

### Application
- **Image**: `ghcr.io/gis-ops/docker-valhalla/valhalla:latest`
- **Version**: 3.5.1
- **Storage**: 50GB PersistentVolume with gp2 storage class
- **Sample Data**: Monaco (~1MB) - smallest test dataset
- **Autoscaling**: 2-20 pods based on CPU/Memory (HPA)
- **Resources**: 512Mi-2Gi memory, 250m-1 CPU per pod (dev)

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
# Get public LoadBalancer URL
kubectl get svc valhalla-api-lb -n valhalla

# Or use the deployed URL
export VALHALLA_URL="http://k8s-valhalla-valhalla-f7f06e7694-96790d154369cade.elb.us-east-1.amazonaws.com"

# Test routing (Monaco coordinates)
curl $VALHALLA_URL/route \
  --data '{
    "locations": [
      {"lat": 43.7384, "lon": 7.4246},
      {"lat": 43.7311, "lon": 7.4197}
    ],
    "costing": "auto",
    "directions_options": {"units": "kilometers"}
  }' \
  -H "Content-Type: application/json"

# Expected: 2.49km route in ~3.5 minutes
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
- **EKS Version**: 1.29
- **Node Instance**: t3.medium (dev), t3.large (prod)
- **Node Count**: 3 (dev), 6-15 (prod)
- **Auto-scaling**: Cluster Autoscaler enabled
- **Metrics Server**: Installed for HPA

### Security
- **IAM Roles**: Cluster, node groups, IRSA ready
- **Security Groups**: Least-privilege rules
- **Encryption**: EBS volumes, secrets at rest
- **Network Policies**: Pod-to-pod isolation

## Valhalla Configuration

### Current Setup
- **Map Data**: Monaco (~1MB) - smallest real dataset
- **Coverage**: Monaco city (43.73-43.75°N, 7.40-7.44°E)
- **Replicas**: 2-20 (dev with HPA), 6-30 (prod)
- **Resources**: 512Mi-2Gi RAM, 250m-1 CPU per pod (dev)
- **Storage**: 50GB PVC (gp2)

### API Endpoints

```bash
# Health check
GET /status

# Routing (Monaco coordinates)
POST /route
{
  "locations": [{"lat": 43.7384, "lon": 7.4246}, {"lat": 43.7311, "lon": 7.4197}],
  "costing": "auto",
  "directions_options": {"units": "kilometers"}
}

# Isochrone
POST /isochrone
{
  "locations": [{"lat": 43.7384, "lon": 7.4246}],
  "costing": "auto",
  "contours": [{"time": 10}, {"time": 20}]
}

# Map matching
POST /trace_route
{
  "shape": [{"lat": 43.7384, "lon": 7.4246}, {"lat": 43.7311, "lon": 7.4197}],
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

- [Architecture Overview](docs/architecture.md) - AWS infrastructure design
- [Architecture Decisions (ADRs)](docs/decisions.md) - Key technical decisions
- [Deployment Guide](docs/deployment.md) - Step-by-step deployment
- [Getting Started Guide](docs/getting-started.md) - Quick start tutorial
- [Valhalla Routing Guide](docs/valhalla-routing.md) - Routing engine details
- [Monitoring Guide](docs/monitoring.md) - Observability setup

## Map Data Management

### Current Data: Monaco

**Coverage:**
- Region: Monaco (smallest country)
- Size: ~1MB OSM data
- Coordinates: 43.73-43.75°N, 7.40-7.44°E
- Perfect for testing and demos

### Using Custom Regions

1. Download OSM data from [Geofabrik](https://download.geofabrik.de/)
2. Build tiles: `valhalla_build_tiles -c config.json data.osm.pbf`
3. Upload to S3 or include in init container
4. Update `k8s/base/deployment.yaml` init container

**Popular regions:**
- City: Amsterdam (~100MB), Berlin (~200MB)
- Country: Netherlands (~500MB), Germany (~3GB)
- Continent: Europe (~25GB)

See [Valhalla Routing Guide](docs/valhalla-routing.md) for detailed instructions.

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
