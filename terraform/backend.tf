# Backend configuration for Terraform state
# Uncomment and configure after creating S3 bucket and DynamoDB table

# terraform {
#   backend "s3" {
#     bucket         = "valhalla-terraform-state-${var.environment}"
#     key            = "infrastructure/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "valhalla-terraform-locks"
#   }
# }

# Instructions for setting up remote state:
# 1. Create S3 bucket: aws s3 mb s3://valhalla-terraform-state-dev --region us-east-1
# 2. Enable versioning: aws s3api put-bucket-versioning --bucket valhalla-terraform-state-dev --versioning-configuration Status=Enabled
# 3. Enable encryption: aws s3api put-bucket-encryption --bucket valhalla-terraform-state-dev --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
# 4. Create DynamoDB table: aws dynamodb create-table --table-name valhalla-terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region us-east-1
# 5. Uncomment the backend configuration above and run: terraform init -migrate-state
