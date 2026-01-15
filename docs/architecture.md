# Valhalla Platform - Architecture Documentation

## Overview

Valhalla is a production-ready, highly available web platform built on Amazon Web Services (AWS) using Elastic Kubernetes Service (EKS). The architecture is designed for 24/7 operation, high load capacity, and multiple daily deployments with zero downtime.

## Architecture Diagram

![Valhalla AWS Architecture](diagrams/architecture.png)

## Design Principles

1. **High Availability** - Multi-AZ deployment with automatic failover
2. **Scalability** - Auto-scaling at both infrastructure and application layers
3. **Security** - Defense in depth with network isolation and least-privilege access
4. **Observability** - Comprehensive monitoring, logging, and alerting
5. **Automation** - Infrastructure as Code and CI/CD pipelines
6. **Cost Optimization** - Right-sized resources with auto-scaling

## Infrastructure Components

### 1. Network Architecture

#### VPC Design
- **CIDR Block**: `10.0.0.0/16` (65,536 IP addresses)
- **Region**: `us-east-1` (primary), with multi-region capability
- **Availability Zones**: 3 AZs for high availability

#### Subnet Strategy

**Public Subnets** (NAT + Load Balancers):
- `us-east-1a`: 10.0.1.0/24 (256 IPs)
- `us-east-1b`: 10.0.2.0/24 (256 IPs)
- `us-east-1c`: 10.0.3.0/24 (256 IPs)

**Private Subnets** (EKS Worker Nodes):
- `us-east-1a`: 10.0.11.0/24 (256 IPs)
- `us-east-1b`: 10.0.12.0/24 (256 IPs)
- `us-east-1c`: 10.0.13.0/24 (256 IPs)

**Database Subnets** (Future):
- `us-east-1a`: 10.0.21.0/24
- `us-east-1b`: 10.0.22.0/24
- `us-east-1c`: 10.0.23.0/24

#### Network Components

**Internet Gateway**
- Provides internet connectivity for public subnets
- Single IGW per VPC

**NAT Gateways**
- One per AZ for high availability (3 total)
- Allows private subnet resources to access internet
- Handles outbound traffic from worker nodes

**Route Tables**
- Public route table: Routes 0.0.0.0/0 to IGW
- Private route tables: Routes 0.0.0.0/0 to NAT Gateway in same AZ

### 2. Compute - Amazon EKS

#### EKS Cluster Configuration

**Control Plane**
- Managed by AWS across multiple AZs
- Kubernetes version: 1.28 (with upgrade strategy)
- Private endpoint access enabled
- Public endpoint access enabled (restricted by CIDR)

**Worker Nodes**
- **Node Type**: Managed Node Groups
- **Instance Type**: t3.medium (2 vCPU, 4GB RAM) for dev, t3.large for production
- **Auto Scaling**: 
  - Minimum: 3 nodes (1 per AZ)
  - Desired: 6 nodes (2 per AZ)
  - Maximum: 15 nodes
- **AMI**: Amazon EKS optimized AMI
- **Disk**: 50GB gp3 EBS volumes (encrypted)

**Node Group Strategy**
```
Dev Environment: 3-6 nodes (t3.medium)
Staging: 3-9 nodes (t3.large)
Production: 6-15 nodes (t3.large or c5.xlarge for compute-intensive workloads)
```

### 3. Load Balancing

#### Application Load Balancer (ALB)
- **Type**: Application Load Balancer
- **Scheme**: Internet-facing
- **Subnets**: Across all 3 public subnets
- **Listeners**: 
  - HTTP (80) → Redirect to HTTPS
  - HTTPS (443) → Target groups
- **SSL/TLS**: AWS Certificate Manager (ACM) certificates
- **Health Checks**: `/health` endpoint with 30s interval
- **Sticky Sessions**: Cookie-based for stateful applications

#### Target Groups
- Protocol: HTTP
- Port: Service NodePort or via Ingress Controller
- Health check path: `/health`
- Deregistration delay: 30 seconds

### 4. Container Registry - Amazon ECR

**Repository Configuration**
- Private repositories per application
- Image scanning on push (Trivy integration)
- Image tag immutability enabled
- Lifecycle policies:
  - Keep last 10 tagged images
  - Expire untagged images after 7 days

### 5. Storage

#### Persistent Storage
- **EBS CSI Driver**: For persistent volumes
- **Storage Classes**:
  - `gp3`: General purpose SSD (default)
  - `io2`: High IOPS for databases
- **EFS**: For shared file systems (if needed)

#### State Storage
- **Terraform State**: S3 bucket with versioning and encryption
- **State Locking**: DynamoDB table

### 6. Secrets Management

**AWS Secrets Manager**
- Database credentials
- API keys
- Third-party service tokens

**Kubernetes Secrets**
- Service account tokens
- TLS certificates
- ConfigMaps for non-sensitive configuration

**External Secrets Operator**
- Syncs secrets from AWS Secrets Manager to Kubernetes
- Automatic rotation support

## Environment Separation Strategy

### Multi-Environment Architecture

We deploy three separate environments with isolated resources:

| Component | Dev | Staging | Production |
|-----------|-----|---------|------------|
| VPC | Separate VPC | Separate VPC | Separate VPC |
| EKS Cluster | valhalla-dev | valhalla-staging | valhalla-prod |
| Node Count | 3-6 | 3-9 | 6-15 |
| Instance Type | t3.medium | t3.large | t3.large/c5.xlarge |
| Namespaces | default, monitoring | default, monitoring | default, monitoring, ingress |
| Domain | dev.valhalla.io | staging.valhalla.io | valhalla.io |

### Resource Isolation

**Network Level**
- Each environment has its own VPC
- No VPC peering between environments
- Separate security groups per environment

**AWS Account Strategy** (Future)
- Dev/Staging: Shared AWS account
- Production: Dedicated AWS account
- Centralized billing and monitoring

### Deployment Strategy Per Environment

**Dev Environment**
- Auto-deploy on every commit to `develop` branch
- Relaxed resource limits
- Debug logging enabled
- Cost-optimized instance types

**Staging Environment**
- Deploy on merge to `main` branch
- Production-like configuration
- Performance testing enabled
- Integration testing

**Production Environment**
- Manual approval required
- Canary deployments
- Strict resource limits
- Minimal logging (info level only)
- Blue/green deployment capability

## High Availability Strategy

### Multi-AZ Deployment

**Worker Nodes**
- Distributed across 3 availability zones
- Pod disruption budgets to maintain availability during updates
- Node affinity rules to spread pods across AZs

**Application Layer**
- Minimum 3 replicas per deployment
- Anti-affinity rules to avoid single AZ placement
- Horizontal Pod Autoscaler (HPA) based on CPU/memory

**Data Layer** (Future)
- Amazon RDS with Multi-AZ deployment
- Automated backups with point-in-time recovery
- Read replicas for read-heavy workloads

### Failure Scenarios

| Scenario | Impact | Recovery |
|----------|--------|----------|
| Single Pod Failure | None | Kubernetes restarts pod automatically |
| Node Failure | Temporary reduction | ASG launches new node, pods rescheduled |
| AZ Failure | 33% capacity loss | ALB routes to healthy AZs |
| Region Failure | Full outage | Manual failover to DR region (future) |

### SLA Targets

- **Availability**: 99.9% uptime (43 minutes downtime/month)
- **Latency**: p95 < 200ms, p99 < 500ms
- **Error Rate**: < 1% of requests
- **RTO**: 30 minutes (regional failure)
- **RPO**: 15 minutes (data loss tolerance)

## Scaling Strategy

### Horizontal Scaling

**Cluster Autoscaler**
- Automatically adds/removes nodes based on pending pods
- Scale-up time: ~3-5 minutes
- Scale-down time: 10 minutes after nodes become underutilized

**Horizontal Pod Autoscaler (HPA)**
```yaml
Metrics: CPU (70% threshold), Memory (80% threshold)
Min Replicas: 3
Max Replicas: 20
Scale-up: Add 2 pods if sustained high usage (30s)
Scale-down: Remove 1 pod every 5 minutes if underutilized
```

**Application Load Balancer**
- Automatically scales based on traffic
- Cross-zone load balancing enabled

### Vertical Scaling

**Pod Resources**
- Requests: CPU 100m, Memory 128Mi
- Limits: CPU 500m, Memory 512Mi
- Vertical Pod Autoscaler (VPA) for optimization recommendations

**Node Types**
- Start with t3.medium for cost efficiency
- Upgrade to compute-optimized (c5.xlarge) for CPU-intensive workloads
- Upgrade to memory-optimized (r5.large) for memory-intensive workloads

## Security Architecture

### Network Security

**Security Groups**
- ALB SG: Allow 80/443 from internet (0.0.0.0/0)
- Worker Node SG: Allow traffic from ALB, allow inter-node communication
- Control Plane SG: Managed by AWS, restricted access

**Network Policies**
- Pod-to-pod communication restrictions
- Namespace isolation
- Deny all by default, allow explicitly

### Access Control

**AWS IAM**
- Role-based access control (RBAC)
- Service accounts with OIDC provider
- Pod IAM roles via IRSA (IAM Roles for Service Accounts)
- Least privilege principle

**Kubernetes RBAC**
- Namespace-scoped roles
- ClusterRoles for cluster-wide resources
- Service accounts per application

### Data Security

**Encryption at Rest**
- EBS volumes encrypted with KMS
- S3 buckets encrypted (SSE-S3 or KMS)
- Secrets Manager uses KMS encryption

**Encryption in Transit**
- TLS 1.2+ for all external communication
- mTLS between services (service mesh future)
- Certificate management via AWS ACM

## Monitoring & Observability

### Metrics
- **CloudWatch Container Insights**: Cluster and node metrics
- **Prometheus**: Application metrics scraping
- **Grafana**: Dashboard visualization

### Logging
- **CloudWatch Logs**: Centralized log aggregation
- **FluentBit**: Log forwarding from pods
- **Log retention**: 30 days for dev, 90 days for production

### Tracing
- **AWS X-Ray**: Distributed tracing
- **OpenTelemetry** (future): Vendor-neutral tracing

### Alerting
- **CloudWatch Alarms**: Infrastructure alerts
- **AlertManager**: Application alerts
- **Integration**: SNS → PagerDuty for critical alerts

## Cost Optimization

### Estimated Monthly Costs (Dev Environment)

| Resource | Quantity | Unit Cost | Monthly Cost |
|----------|----------|-----------|--------------|
| EKS Cluster | 1 | $72 | $72 |
| EC2 (t3.medium) | 3-6 nodes | ~$30/node | $180 |
| NAT Gateway | 3 | ~$35/each | $105 |
| ALB | 1 | ~$20 | $20 |
| EBS Volumes | 300GB | $0.10/GB | $30 |
| Data Transfer | 100GB | $0.09/GB | $9 |
| **Total** | | | **~$416/month** |

**Production** (estimated): ~$1,200-2,000/month depending on scale

### Cost Reduction Strategies
- Use Spot Instances for non-critical workloads (40-60% savings)
- Implement cluster autoscaler to reduce idle capacity
- Use S3 Intelligent-Tiering for old logs
- Reserved Instances for predictable workloads (up to 72% savings)

## Disaster Recovery

### Backup Strategy
- **Velero**: Kubernetes resource backups (daily)
- **EBS Snapshots**: Automated snapshots of persistent volumes
- **S3 Versioning**: Terraform state and configuration backups

### Recovery Procedures
- Infrastructure recreation via Terraform (~30 minutes)
- Application deployment via CI/CD (~10 minutes)
- Data restoration from backups (~15 minutes)

### Business Continuity
- **RTO**: 30 minutes (Recovery Time Objective)
- **RPO**: 15 minutes (Recovery Point Objective)
- Regular DR drills (quarterly)

## Future Enhancements

1. **Multi-Region Deployment** - Active-passive for disaster recovery
2. **Service Mesh** - Istio or AWS App Mesh for advanced traffic management
3. **GitOps** - ArgoCD for declarative deployment
4. **Chaos Engineering** - Chaos Monkey for resilience testing
5. **FinOps** - Advanced cost allocation and optimization
6. **Database Layer** - Amazon RDS or Aurora for persistent data

## Conclusion

This architecture provides a solid foundation for running Valhalla as a production-grade platform with high availability, scalability, and security. The design follows AWS Well-Architected Framework principles and industry best practices for Kubernetes deployments.
