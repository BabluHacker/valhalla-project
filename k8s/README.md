# Valhalla Kubernetes Manifests

Kubernetes deployment configurations for the Valhalla platform using Kustomize.

## Structure

```
k8s/
├── base/                    # Base Kubernetes manifests
│   ├── namespace.yaml       # Namespace definition
│   ├── serviceaccount.yaml  # Service account for IRSA
│   ├── configmap.yaml       # Application configuration
│   ├── deployment.yaml      # Application deployment
│   ├── service.yaml         # Kubernetes service
│   ├── ingress.yaml         # ALB ingress
│   ├── hpa.yaml             # Horizontal Pod Autoscaler
│   ├── pdb.yaml             # Pod Disruption Budget
│   └── kustomization.yaml   # Base kustomization
└── overlays/                # Environment-specific overlays
    ├── dev/
    ├── staging/
    └── prod/
```

## Prerequisites

1. **EKS Cluster** properly configured with kubectl access
2. **AWS Load Balancer Controller** installed in cluster
3. **Metrics Server** for HPA
4. **Container images** pushed to ECR

## AWS Load Balancer Controller Setup

Required for Ingress to work with ALB:

```bash
# Add the EKS charts repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=valhalla-dev-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## Deployment

### Dev Environment

```bash
# Update image reference in kustomization.yaml with your ECR URL
# Build and view manifests
kubectl kustomize k8s/overlays/dev

# Apply to cluster
kubectl apply -k k8s/overlays/dev

# Verify deployment
kubectl get pods -n valhalla
kubectl get svc -n valhalla
kubectl get ingress -n valhalla
```

### Staging Environment

```bash
kubectl apply -k k8s/overlays/staging
```

### Production Environment

```bash
# Production requires approval - review first
kubectl kustomize k8s/overlays/prod > prod-manifests.yaml
# Review prod-manifests.yaml
kubectl apply -k k8s/overlays/prod
```

## Configuration

### Environment-Specific Settings

| Setting | Dev | Staging | Production |
|---------|-----|---------|------------|
| Replicas | 3 | 3 | 6 |
| CPU Request | 50m | 100m | 200m |
| Memory Request | 128Mi | 128Mi | 256Mi |
| CPU Limit | 200m | 500m | 1000m |
| Memory Limit | 256Mi | 512Mi | 1Gi |
| HPA Min | 3 | 3 | 6 |
| HPA Max | 10 | 20 | 30 |
| Log Level | debug | info | info |
| Hostname | api-dev.valhalla.example.com | api-staging.valhalla.example.com | api.valhalla.com |

### ConfigMap

Update `configmap.yaml` or environment-specific patches:

```yaml
data:
  log_level: "info"
  app_name: "Valhalla API"
  app_version: "1.0.0"
```

### Secrets

For sensitive data, use AWS Secrets Manager with External Secrets Operator or Kubernetes Secrets:

```bash
kubectl create secret generic valhalla-api-secrets \
  -n valhalla \
  --from-literal=database-password=xxxxx
```

## Resource Specifications

### Deployment

- **Strategy**: RollingUpdate (maxSurge: 1, maxUnavailable: 0)
- **Security Context**: Non-root user (1001), read-only filesystem
- **Health Probes**:
  - Liveness: `/health` after 30s startup
  - Readiness: `/ready` after 10s startup
- **Pod Anti-Affinity**: Spread across availability zones

### Service

- **Type**: ClusterIP (internal)
- **Port**: 80 → 3000 (container)

### Ingress

- **Class**: ALB (Application Load Balancer)
- **SSL**: HTTPS redirect enabled
- **Health Check**: `/health` every 30s
- **Target Type**: IP (for Fargate compatibility)

### HPA

- **Metrics**: CPU (70%), Memory (80%)
- **Behavior**:
  - Scale up: Add 2 pods or 100% every 30s
  - Scale down: Remove 1 pod or 50% every 60s (5min stabilization)

### PDB

- **Min Available**: 2 pods during voluntary disruptions

## Monitoring

### View Logs

```bash
# All pods
kubectl logs -n valhalla -l app=valhalla-api --tail=100 -f

# Specific pod
kubectl logs -n valhalla <pod-name> -f
```

### Check Metrics

```bash
# HPA status
kubectl get hpa -n valhalla

# Pod metrics
kubectl top pods -n valhalla

# Node metrics
kubectl top nodes
```

### Describe Resources

```bash
kubectl describe deployment valhalla-api -n valhalla
kubectl describe ingress valhalla-api -n valhalla
```

## Scaling

### Manual Scaling

```bash
# Scale deployment
kubectl scale deployment valhalla-api -n valhalla --replicas=5

# HPA will override manual scaling
```

### Autoscaling

HPA is enabled by default. Monitor with:

```bash
kubectl get hpa -n valhalla -w
```

## Troubleshooting

### Pods Not Starting

```bash
kubectl get pods -n valhalla
kubectl describe pod <pod-name> -n valhalla
kubectl logs <pod-name> -n valhalla
```

### Ingress Not Created

```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify ingress
kubectl describe ingress valhalla-api -n valhalla
```

### Image Pull Errors

```bash
# Verify ECR permissions
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com

# Check service account IRSA
kubectl describe sa valhalla-api -n valhalla
```

### HPA Not Scaling

```bash
# Check metrics server
kubectl get deployment metrics-server -n kube-system

# View HPA events
kubectl describe hpa valhalla-api -n valhalla
```

## Rollback

### Rollback Deployment

```bash
# View rollout history
kubectl rollout history deployment/valhalla-api -n valhalla

# Rollback to previous version
kubectl rollout undo deployment/valhalla-api -n valhalla

# Rollback to specific revision
kubectl rollout undo deployment/valhalla-api -n valhalla --to-revision=2
```

## Cleanup

```bash
# Delete specific environment
kubectl delete -k k8s/overlays/dev

# Delete namespace (removes everything)
kubectl delete namespace valhalla
```

## Next Steps

1. Configure DNS for ingress hostname
2. Set up SSL certificate in ACM
3. Configure monitoring and alerting
4. Set up External Secrets Operator for secrets management
5. Implement network policies for pod-to-pod security

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kustomize](https://kustomize.io/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
