# Remote State Backend Configuration
#
# This file provides examples for configuring remote state storage in S3.
# Copy this file to `backend.tf` and customize for your environment.
#
# IMPORTANT:
# - Create the S3 bucket and DynamoDB table BEFORE running terraform init
# - The backend configuration cannot use variables or interpolation
# - Once configured, run: terraform init -migrate-state

# -----------------------------------------------------------------------------
# Example 1: Single Environment (Simple)
# -----------------------------------------------------------------------------
# Use this for a single environment deployment (e.g., only production)

terraform {
    backend "s3" {
        bucket         = "my-terraform-state-bucket"           # CHANGE THIS
        key            = "litellm/terraform.tfstate"
        region         = "us-east-1"                           # CHANGE THIS
        encrypt        = true
#       dynamodb_table = "terraform-state-locks"               # CHANGE THIS
#
#     # Optional: Use KMS for encryption at rest
#     # kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    }
}

# -----------------------------------------------------------------------------
# Example 2: Multiple Environments with Workspaces
# -----------------------------------------------------------------------------
# Use this for managing dev/staging/prod with Terraform workspaces
# Workspaces will store state at: s3://bucket/litellm/env:/workspace-name/terraform.tfstate

# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state-bucket"
#     key            = "litellm/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-locks"
#     workspace_key_prefix = "litellm"
#   }
# }

# Then use workspaces:
#   terraform workspace new dev
#   terraform workspace new staging
#   terraform workspace new prod
#   terraform workspace select dev

# -----------------------------------------------------------------------------
# Example 3: Multiple Environments with Separate State Files
# -----------------------------------------------------------------------------
# Use this for completely separate state files per environment
# You'll need to specify the backend config per environment during init

# Development
# terraform init -backend-config="key=litellm/dev/terraform.tfstate"
#
# Staging
# terraform init -backend-config="key=litellm/staging/terraform.tfstate"
#
# Production
# terraform init -backend-config="key=litellm/prod/terraform.tfstate"

# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state-bucket"
#     # key is specified during terraform init
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-locks"
#   }
# }

# -----------------------------------------------------------------------------
# Creating the Required AWS Resources
# -----------------------------------------------------------------------------
# Before using remote state, create the S3 bucket and DynamoDB table:

# 1. Create S3 bucket for state storage
# aws s3api create-bucket \
#   --bucket my-terraform-state-bucket \
#   --region us-east-1

# 2. Enable versioning on the bucket (recommended)
# aws s3api put-bucket-versioning \
#   --bucket my-terraform-state-bucket \
#   --versioning-configuration Status=Enabled

# 3. Enable encryption on the bucket
# aws s3api put-bucket-encryption \
#   --bucket my-terraform-state-bucket \
#   --server-side-encryption-configuration '{
#     "Rules": [{
#       "ApplyServerSideEncryptionByDefault": {
#         "SSEAlgorithm": "AES256"
#       }
#     }]
#   }'

# 4. Block public access (security best practice)
# aws s3api put-public-access-block \
#   --bucket my-terraform-state-bucket \
#   --public-access-block-configuration \
#     BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 5. Create DynamoDB table for state locking
# aws dynamodb create-table \
#   --table-name terraform-state-locks \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST \
#   --region us-east-1

# 6. (Optional) Add lifecycle policy to S3 bucket for old versions
# Create a file named lifecycle.json:
# {
#   "Rules": [{
#     "Id": "DeleteOldVersions",
#     "Status": "Enabled",
#     "NoncurrentVersionExpiration": {
#       "NoncurrentDays": 90
#     }
#   }]
# }
#
# Then apply it:
# aws s3api put-bucket-lifecycle-configuration \
#   --bucket my-terraform-state-bucket \
#   --lifecycle-configuration file://lifecycle.json

# -----------------------------------------------------------------------------
# Best Practices
# -----------------------------------------------------------------------------
# 1. Use a separate AWS account for state storage (if managing multiple AWS accounts)
# 2. Enable MFA delete on the S3 bucket for additional security
# 3. Use S3 bucket policies to restrict access to specific IAM roles
# 4. Enable CloudTrail logging for the S3 bucket to audit state access
# 5. Regularly review and rotate access keys/roles that have access to state
# 6. Consider using AWS Organizations SCPs to protect the state bucket
# 7. Never commit backend.tf with actual credentials to version control
# 8. Use different state files for different environments (don't share state!)

# -----------------------------------------------------------------------------
# Migration from Local State
# -----------------------------------------------------------------------------
# If you already have local state and want to migrate to remote:

# 1. Create backend.tf from this example
# 2. Run: terraform init -migrate-state
# 3. Confirm the migration when prompted
# 4. Verify state in S3: aws s3 ls s3://my-terraform-state-bucket/litellm/
# 5. Remove local terraform.tfstate and terraform.tfstate.backup files (after verification)
# 6. Add terraform.tfstate* to .gitignore

# -----------------------------------------------------------------------------
# Accessing Remote State from Other Terraform Configurations
# -----------------------------------------------------------------------------
# Other Terraform configurations can read outputs from this state:

# data "terraform_remote_state" "litellm_eks" {
#   backend = "s3"
#   config = {
#     bucket = "my-terraform-state-bucket"
#     key    = "litellm/terraform.tfstate"
#     region = "us-east-1"
#   }
# }
#
# # Use outputs:
# resource "example" "foo" {
#   vpc_id = data.terraform_remote_state.litellm_eks.outputs.vpc_id
# }
