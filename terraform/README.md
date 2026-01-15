# Valhalla Terraform Infrastructure

This directory contains Terraform infrastructure as code for the Valhalla platform.

## Structure

```
terraform/
├── modules/              # Reusable Terraform modules
│   ├── networking/      # VPC, subnets, NAT, IGW
│   ├── security/        # Security groups
│   ├── eks/             # EKS cluster (Phase 5)
│   └── ecr/             # Container registry (Phase 5)
├── environments/        # Environment-specific configurations
│   ├── dev/
│   ├── staging/
│   └── prod/
├── main.tf              # Root module configuration
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── versions.tf          # Terraform and provider versions
└── backend.tf           # Remote state configuration
```

## Prerequisites

1. **Terraform** >= 1.5.0
2. **AWS CLI** configured with credentials
3. **AWS Account** with appropriate permissions

## Quick Start

### 1. Configure Environment

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan Infrastructure

```bash
terraform plan
```

### 4. Apply Infrastructure

```bash
terraform apply
```

## Modules

### Networking Module

Creates VPC with public and private subnets across multiple AZs.

**Resources:**
- VPC with configurable CIDR
- Public subnets (for ALB, NAT Gateway)
- Private subnets (for EKS worker nodes)
- Internet Gateway
- NAT Gateways (configurable: 1 or 3 for HA)
- Route tables
- VPC Flow Logs

**Usage:**
```hcl
module "networking" {
  source = "./modules/networking"

  environment          = "dev"
  project_name        = "valhalla"
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  single_nat_gateway  = true  # false for production
}
```

### Security Module

Creates security groups for all components.

**Resources:**
- ALB security group (HTTP/HTTPS from internet)
- EKS cluster security group
- EKS nodes security group
- RDS security group (for future use)

**Usage:**
```hcl
module "security" {
  source = "./modules/security"

  environment  = "dev"
  project_name = "valhalla"
  vpc_id       = module.networking.vpc_id
}
```

## Environment Configuration

### Dev Environment
- **VPC CIDR**: 10.0.0.0/16
- **NAT Gateway**: Single (cost optimization)
- **Purpose**: Development and testing

### Staging Environment
- **VPC CIDR**: 10.1.0.0/16
- **NAT Gateway**: 3 (one per AZ)
- **Purpose**: Pre-production testing

### Production Environment
- **VPC CIDR**: 10.2.0.0/16
- **NAT Gateway**: 3 (high availability)
- **Purpose**: Production workloads

## Remote State Setup

To use S3 remote state (recommended for team collaboration):

```bash
# Create S3 bucket
aws s3 mb s3://valhalla-terraform-state-dev --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket valhalla-terraform-state-dev \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket valhalla-terraform-state-dev \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name valhalla-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# Uncomment backend configuration in backend.tf
# Run terraform init -migrate-state
```

## Cost Optimization

### Dev Environment
- Use `single_nat_gateway = true` to save ~$70/month
- Estimated cost: ~$35/month for NAT Gateway

### Production
- Use `single_nat_gateway = false` for high availability
- Estimated cost: ~$105/month for 3 NAT Gateways

## Validation

### Terraform Validate
```bash
terraform validate
```

### Terraform Format
```bash
terraform fmt -recursive
```

### Security Scanning
```bash
# Install tfsec
brew install tfsec

# Run security scan
tfsec .
```

### Cost Estimation
```bash
# Install Infracost
brew install infracost

# Generate cost estimate
infracost breakdown --path .
```

## Outputs

After applying, Terraform will output:
- VPC ID
- Subnet IDs (public and private)
- NAT Gateway IDs and public IPs
- Security group IDs
- Availability zones used

Access outputs:
```bash
terraform output
terraform output -json > outputs.json
```

## Destroy Infrastructure

**Warning**: This will destroy all resources!

```bash
terraform destroy
```

## Troubleshooting

### Issue: State lock error
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Issue: Resource already exists
```bash
# Import existing resource
terraform import aws_vpc.main vpc-xxxxx
```

### Issue: Provider authentication
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Configure AWS CLI
aws configure
```

## Next Steps

After deploying networking infrastructure:
1. Deploy EKS cluster (Phase 5)
2. Deploy ECR repository (Phase 5)
3. Set up Kubernetes manifests (Phase 6)
4. Configure CI/CD pipelines (Phase 7)

## References

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-best-practices.html)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
