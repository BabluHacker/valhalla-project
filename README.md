# ⚔️ Valhalla - Production-Ready Web API Platform

> A comprehensive DevOps showcase project demonstrating production-grade infrastructure, automation, and operational excellence on AWS.

[![AWS](https://img.shields.io/badge/AWS-EKS-orange.svg)](https://aws.amazon.com/eks/)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-623CE4.svg)](https://www.terraform.io/)
[![GitHub Actions](https://img.shields.io/badge/CI/CD-GitHub_Actions-2088FF.svg)](https://github.com/features/actions)
[![Kubernetes](https://img.shields.io/badge/Platform-Kubernetes-326CE5.svg)](https://kubernetes.io/)

## 📋 Overview

**Valhalla** is a business-critical web platform designed for:
- High load capacity
- Multiple deployments per day
- 24/7 operation with 99.9% uptime SLA

This project demonstrates end-to-end DevOps capabilities including architecture design, infrastructure as code, CI/CD automation, observability, security, and incident response.

## 🏗️ Architecture

Valhalla runs on **Amazon EKS (Elastic Kubernetes Service)** with a multi-AZ deployment for high availability.

**Key Components:**
- **Application**: Node.js Express REST API
- **Infrastructure**: AWS VPC, EKS, ECR, ALB
- **CI/CD**: GitHub Actions for automated build and deployment
- **Monitoring**: CloudWatch Container Insights + Prometheus/Grafana
- **Security**: AWS IAM, Secrets Manager, container scanning

📐 [View detailed architecture documentation](docs/architecture.md)

## 🚀 Quick Start

### Prerequisites

- **Local Tools**: Node.js 18+, Docker, Terraform 1.5+, kubectl, AWS CLI v2
- **AWS Account**: With appropriate IAM permissions
- **GitHub**: Repository with Actions enabled

### Local Development

```bash
# Clone the repository
git clone <repository-url>
cd valhalla-project

# Run the application locally
cd app
npm install
npm run dev

# Run tests
npm test

# Build Docker image
docker build -t valhalla-api .
docker run -p 3000:3000 valhalla-api
```

### Deploy Infrastructure

```bash
# Navigate to Terraform directory
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Plan infrastructure changes
terraform plan

# Apply infrastructure
terraform apply
```

### Deploy Application

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name valhalla-dev-cluster

# Deploy to Kubernetes
kubectl apply -k k8s/overlays/dev

# Check deployment status
kubectl get pods -n valhalla
```

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | System design and AWS service choices |
| [Architecture Decisions](docs/decisions.md) | ADRs for key technical decisions |
| [CI/CD Pipeline](docs/cicd.md) | Build and deployment automation |
| [Deployment Strategy](docs/deployment-strategy.md) | Zero-downtime deployment approach |
| [Observability](docs/observability.md) | Monitoring, logging, and alerting |
| [SLIs/SLOs](docs/slos.md) | Service level objectives and targets |
| [Security](docs/security.md) | Security best practices and compliance |
| [Backup & DR](docs/backup-dr.md) | Disaster recovery procedures |
| [Incident Response](docs/incident-response.md) | Production incident handling |
| [Cost Analysis](docs/cost-analysis.md) | AWS cost breakdown and optimization |
| [Getting Started](docs/getting-started.md) | Detailed setup guide |

## 📁 Project Structure

```
valhalla-project/
├── app/                    # Node.js Web API application
├── terraform/              # Infrastructure as Code
├── k8s/                    # Kubernetes manifests
├── .github/workflows/      # CI/CD pipelines
├── docs/                   # Documentation
└── scripts/                # Helper scripts
```

## 🛠️ Technology Stack

- **Cloud**: AWS (EKS, VPC, ECR, ALB, CloudWatch)
- **Infrastructure as Code**: Terraform
- **Container Orchestration**: Kubernetes
- **CI/CD**: GitHub Actions
- **Application**: Node.js + Express
- **Monitoring**: Prometheus, Grafana, CloudWatch
- **Security**: AWS Secrets Manager, Trivy scanning

## 🎯 Project Deliverables

This project fulfills the following DevOps challenge requirements:

1. ✅ **Architecture & Infrastructure** - Multi-AZ EKS cluster design
2. ✅ **Infrastructure as Code** - Complete Terraform modules
3. ✅ **CI/CD & Deployment** - Automated GitHub Actions pipelines
4. ✅ **Observability & Operations** - Full monitoring stack with SLOs
5. ✅ **Security & Reliability** - IAM, RBAC, secrets management, DR plan
6. ✅ **Incident Simulation** - Detailed response playbook

## 📊 Key Features

- **High Availability**: Multi-AZ deployment with automatic failover
- **Auto-scaling**: Horizontal Pod Autoscaler based on CPU/memory
- **Zero-Downtime Deployment**: Rolling updates with health checks
- **Security**: Container scanning, secrets encryption, network policies
- **Observability**: Real-time metrics, logs, and distributed tracing
- **Disaster Recovery**: Automated backups with documented RTO/RPO

## 🔐 Security

- IAM roles with least-privilege access
- Kubernetes RBAC policies
- Container image scanning (Trivy)
- AWS Secrets Manager for sensitive data
- Network policies for pod-to-pod communication
- Encrypted EBS volumes and S3 buckets

## 📈 Monitoring & Alerting

- **Latency**: p95 < 200ms, p99 < 500ms
- **Error Rate**: < 1% of requests
- **Availability**: 99.9% uptime SLA
- **Alerts**: PagerDuty integration for critical issues

## 🤝 Contributing

This is a showcase project. For improvements or suggestions, please open an issue.

## 📝 License

This project is for educational and demonstration purposes.

---

**Built with ❤️ for DevOps Excellence**
