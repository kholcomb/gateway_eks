# ECR Module Outputs

output "repository_urls" {
  description = "Map of repository names to their URLs"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository names to their ARNs"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.arn
  }
}

output "repository_registry_ids" {
  description = "Map of repository names to their registry IDs"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.registry_id
  }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for ECR encryption"
  value       = var.enable_encryption ? aws_kms_key.ecr[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key used for ECR encryption"
  value       = var.enable_encryption ? aws_kms_key.ecr[0].id : null
}

output "ecr_login_command" {
  description = "Command to authenticate Docker to ECR"
  value       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

# Data sources for outputs
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
