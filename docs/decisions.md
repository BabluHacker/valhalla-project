# Architecture Decision Records (ADRs)

This document captures key architectural decisions made for the Valhalla platform, including context, decision, and consequences.

---

## ADR-001: Amazon EKS for Container Orchestration

**Date**: 2026-01-15  
**Status**: Accepted

### Context
We need a container orchestration platform that is:
- Production-ready and enterprise-grade
- Highly available and scalable
- Managed to reduce operational overhead
- Compatible with Kubernetes ecosystem tools

### Decision
Use Amazon EKS (Elastic Kubernetes Service) as the container orchestration platform.

### Alternatives Considered
1. **Self-managed Kubernetes on EC2**
   - Pros: Full control, cost savings
   - Cons: High operational overhead, requires deep Kubernetes expertise
   
2. **Amazon ECS (Elastic Container Service)**
   - Pros: Simpler than Kubernetes, AWS-native
   - Cons: Vendor lock-in, smaller ecosystem, not industry standard
   
3. **AWS Fargate**
   - Pros: Serverless, no node management
   - Cons: Higher cost, less control, cold start latency

### Consequences

**Positive:**
- Managed control plane reduces operational burden
- Automatic updates and patches for control plane
- Native integration with AWS services (IAM, CloudWatch, etc.)
- Strong community support and ecosystem
- Industry-standard Kubernetes API

**Negative:**
- Cost: $72/month for control plane + EC2 costs
- Some AWS-specific configurations required
- Learning curve for Kubernetes if team is new to it

**Mitigations:**
- Use managed node groups to reduce operational complexity
- Implement cluster autoscaler for cost optimization
- Invest in team training and documentation

---

## ADR-002: Multi-AZ Deployment for High Availability

**Date**: 2026-01-15  
**Status**: Accepted

### Context
The platform requires 99.9% availability SLA (43 minutes downtime/month). Single AZ deployment poses risk of total outage during AZ failure.

### Decision
Deploy across 3 Availability Zones (us-east-1a, us-east-1b, us-east-1c) with resources distributed evenly.

### Rationale
- AWS AZ failure probability: ~0.1% per year
- Multi-AZ reduces single point of failure
- ALB automatically routes traffic to healthy AZs
- EKS worker nodes spread across AZs

### Consequences

**Positive:**
- Survives complete AZ failure with 67% capacity
- Meets 99.9% availability SLA
- Zero-downtime deployments possible
- Better latency distribution

**Negative:**
- Higher costs: 3x NAT Gateways (~$105/month vs $35/month)
- More complex network configuration
- Cross-AZ data transfer charges (minimal for most workloads)

**Trade-offs Accepted:**
- Paying ~$70/month extra for NAT Gateways is acceptable for HA
- Cross-AZ traffic cost is negligible compared to downtime cost

---

## ADR-003: Separate VPCs Per Environment

**Date**: 2026-01-15  
**Status**: Accepted

### Context
We need to isolate dev, staging, and production environments for security and compliance while managing costs.

### Decision
Create separate VPCs for each environment (dev, staging, production).

### Alternatives Considered
1. **Single VPC with namespace isolation**
   - Pros: Lower cost, simpler networking
   - Cons: Shared fate, security risk, compliance issues
   
2. **Separate AWS accounts per environment**
   - Pros: Maximum isolation, separate billing
   - Cons: Higher complexity, duplicate resources

### Consequences

**Positive:**
- Strong network isolation between environments
- Independent security groups and network policies
- Can tear down dev/staging without affecting production
- Easier to comply with security standards
- No risk of accidental production access from dev

**Negative:**
- Higher costs: 3x VPCs, 3x NAT Gateways per environment
- More Terraform code to maintain
- CIDR block management complexity

**Future Consideration:**
- Move production to separate AWS account when team scales
- Keep dev/staging in shared account for cost efficiency

---

## ADR-004: Terraform for Infrastructure as Code

**Date**: 2026-01-15  
**Status**: Accepted

### Context
Need IaC tool for provisioning and managing AWS infrastructure with version control, repeatability, and team collaboration.

### Decision
Use Terraform as the primary Infrastructure as Code tool.

### Alternatives Considered
1. **AWS CloudFormation**
   - Pros: Native AWS, no state management needed
   - Cons: AWS-only, verbose YAML, slower development
   
2. **AWS CDK (Cloud Development Kit)**
   - Pros: Use programming languages, type safety
   - Cons: Generates CloudFormation, AWS-only, steeper learning curve
   
3. **Pulumi**
   - Pros: Use programming languages, multi-cloud
   - Cons: Smaller community, enterprise features require paid tier

### Consequences

**Positive:**
- Multi-cloud capability (future-proof)
- Large community and module ecosystem
- Declarative syntax easy to understand
- State management with remote backends (S3)
- Strong plan/apply workflow for safety

**Negative:**
- State file management required
- State locking needed (DynamoDB)
- Learning curve for HCL syntax
- Some AWS resources lag behind CloudFormation

**Best Practices:**
- Use remote state in S3 with versioning
- Implement state locking with DynamoDB
- Modular structure for reusability
- Separate state files per environment

---

## ADR-005: GitHub Actions for CI/CD

**Date**: 2026-01-15  
**Status**: Accepted

### Context
Need CI/CD platform for automated testing, building, and deployment with GitHub integration.

### Decision
Use GitHub Actions as the CI/CD platform.

### Alternatives Considered
1. **Jenkins**
   - Pros: Mature, flexible, extensive plugins
   - Cons: Self-hosted maintenance, complex setup, aging UI
   
2. **GitLab CI**
   - Pros: Integrated GitLab ecosystem, powerful
   - Cons: Requires GitLab, migration needed from GitHub
   
3. **CircleCI**
   - Pros: Fast, good UX, cloud-hosted
   - Cons: Cost for private repos, limited free tier
   
4. **AWS CodePipeline**
   - Pros: Native AWS integration
   - Cons: Limited features, AWS-specific, poor UX

### Consequences

**Positive:**
- Native GitHub integration
- Free for public repos, generous free tier for private
- YAML-based configuration (familiar)
- Secrets management built-in
- Large marketplace of actions
- Easy OIDC integration with AWS (no long-term credentials)

**Negative:**
- GitHub dependency (vendor lock-in)
- Limited to 6 hours per job
- Some advanced features require self-hosted runners

**Implementation Details:**
- Use OIDC for AWS authentication (no access keys)
- Separate workflows for CI and CD
- Environment-specific deployment workflows
- Manual approval gates for production

---

## ADR-006: Application Load Balancer (ALB) vs Network Load Balancer (NLB)

**Date**: 2026-01-15  
**Status**: Accepted

### Context
Need to expose Kubernetes services to the internet. Choose between ALB (Layer 7) and NLB (Layer 4).

### Decision
Use Application Load Balancer (ALB) with AWS Load Balancer Controller.

### Rationale
- HTTP/HTTPS workload (REST API)
- Need path-based routing
- Want SSL/TLS termination at load balancer
- Benefit from WAF integration

### Consequences

**Positive:**
- Layer 7 routing (path, host, headers)
- SSL/TLS termination (certificates managed by ACM)
- AWS WAF integration for security
- Better for HTTP/HTTPS workloads
- Health checks at application level

**Negative:**
- Slightly higher latency than NLB (~1-2ms)
- More expensive than NLB (~$20/month vs ~$15/month)
- Not suitable for non-HTTP protocols

**When to Use NLB Instead:**
- TCP/UDP protocols
- Ultra-low latency required (<1ms)
- Static IP addresses needed
- High throughput (millions of requests/sec)

---

## ADR-007: Managed Node Groups vs Self-Managed Nodes

**Date**: 2026-01-15  
**Status**: Accepted

### Context
EKS supports both managed node groups and self-managed nodes. Need to decide which to use.

### Decision
Use EKS Managed Node Groups for all worker nodes.

### Rationale
- AWS handles AMI updates and patching
- Simplified node lifecycle management
- Automatic integration with cluster
- One-click security updates

### Consequences

**Positive:**
- Reduced operational overhead
- Automatic AMI updates
- Simplified node replacement
- Better integration with AWS Auto Scaling
- Terraform support via `aws_eks_node_group`

**Negative:**
- Less customization than self-managed
- Can't use custom AMIs easily
- Slightly higher cost (minimal)

**Best Practices:**
- Use launch templates for custom user data if needed
- Enable automatic updates for node groups
- Set proper maintenance windows

---

## ADR-008: Prometheus + Grafana vs CloudWatch Only

**Date**: 2026-01-15  
**Status**: Accepted

### Context
Need comprehensive monitoring solution. CloudWatch is native to AWS, but Prometheus/Grafana is industry standard for Kubernetes.

### Decision
Use hybrid approach: CloudWatch Container Insights + Prometheus + Grafana.

### Rationale
- **CloudWatch**: Infrastructure and AWS service metrics
- **Prometheus**: Kubernetes and application metrics
- **Grafana**: Unified visualization

### Consequences

**Positive:**
- Best of both worlds
- CloudWatch for AWS-specific metrics
- Prometheus for custom application metrics
- Grafana for beautiful dashboards
- Standard `/metrics` endpoint for applications

**Negative:**
- More complexity than single solution
- Need to maintain Prometheus/Grafana in cluster
- Higher cost (CloudWatch + storage for Prometheus)
- Duplicate some metrics

**Implementation:**
- CloudWatch Container Insights for cluster/node metrics
- Prometheus for pod/application metrics
- Grafana for dashboards (connects to both)
- AlertManager for Prometheus alerts
- CloudWatch Alarms for critical infrastructure

---

## ADR-009: Public vs Private EKS Endpoint

**Date**: 2026-01-15  
**Status**: Accepted

### Context
EKS API server can be private-only, public-only, or both. Need to balance security and accessibility.

### Decision
Enable both public and private endpoints with CIDR restrictions on public access.

### Rationale
- Developers need access from outside VPC
- CI/CD needs access to deploy
- Internal services should use private endpoint

### Consequences

**Positive:**
- Flexible access from CI/CD and developer machines
- Internal traffic uses private endpoint (faster, free)
- Can restrict public access by IP CIDR
- Can disable public later if needed

**Negative:**
- Public endpoint is potential attack surface
- Need to manage allowlist of CIDRs

**Security Mitigations:**
- Require kubectl authentication (no anonymous access)
- Restrict public endpoint to known CIDRs
- Monitor API server logs for suspicious activity
- Use AWS IAM for authentication
- Implement Kubernetes RBAC

---

## ADR-010: Horizontal vs Vertical Pod Autoscaling

**Date**: 2026-01-15  
**Status**: Accepted

### Context
Applications need to scale based on load. Choose between adding more pods (HPA) or increasing pod resources (VPA).

### Decision
Primarily use Horizontal Pod Autoscaler (HPA) with defined resource requests/limits. Use VPA for recommendations only.

### Rationale
- Web APIs benefit more from horizontal scaling
- Better utilization across nodes
- Easier to implement and understand
- More resilient (pods fail independently)

### Consequences

**Positive:**
- Better fault tolerance (multiple pods)
- Works well with rolling updates
- Distributes load across nodes and AZs
- Proven pattern for stateless applications

**Negative:**
- Requires application to be stateless
- Higher overhead (multiple pods)
- Pod startup time affects scale-up speed

**Configuration:**
```yaml
Min Replicas: 3
Max Replicas: 20
Target CPU: 70%
Target Memory: 80%
```

**When to Use VPA:**
- Initial sizing recommendations
- Applications that can't scale horizontally
- Stateful applications with single instance

---

## Summary

These architectural decisions form the foundation of the Valhalla platform. They prioritize:
1. **High Availability** over cost optimization
2. **Managed Services** over self-managed for operational simplicity
3. **Security** through isolation and least-privilege access
4. **Industry Standards** (Kubernetes, Terraform, GitHub Actions)
5. **Observability** with comprehensive monitoring

All decisions are documented, versioned, and open to revision as requirements evolve.
