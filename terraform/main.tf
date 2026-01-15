provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "networking" {
  source = "./modules/networking"

  environment            = var.environment
  project_name          = var.project_name
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  enable_nat_gateway    = var.enable_nat_gateway
  single_nat_gateway    = var.single_nat_gateway
  enable_dns_hostnames  = var.enable_dns_hostnames
  enable_dns_support    = var.enable_dns_support
  tags                  = var.tags
}

module "security" {
  source = "./modules/security"

  environment  = var.environment
  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  tags         = var.tags
}

module "eks" {
  source = "./modules/eks"

  environment                = var.environment
  project_name              = var.project_name
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  cluster_security_group_id = module.security.eks_cluster_security_group_id
  nodes_security_group_id   = module.security.eks_nodes_security_group_id
  tags                      = var.tags
}

module "ecr" {
  source = "./modules/ecr"

  environment  = var.environment
  project_name = var.project_name
  tags         = var.tags
}
