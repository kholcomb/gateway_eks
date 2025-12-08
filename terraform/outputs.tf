# LiteLLM EKS Infrastructure Outputs

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

# -----------------------------------------------------------------------------
# EKS Outputs
# -----------------------------------------------------------------------------
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_oidc_issuer" {
  description = "OIDC issuer URL for the cluster"
  value       = module.eks.cluster_oidc_issuer
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = module.eks.oidc_provider_arn
}

output "eks_cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "eks_node_security_group_id" {
  description = "Security group ID of the EKS node groups"
  value       = module.eks.node_security_group_id
}

# -----------------------------------------------------------------------------
# RDS Outputs
# -----------------------------------------------------------------------------
output "rds_endpoint" {
  description = "Connection endpoint of the RDS instance"
  value       = module.rds.db_instance_endpoint
}

output "rds_address" {
  description = "Address of the RDS instance"
  value       = module.rds.db_instance_address
}

output "rds_port" {
  description = "Port of the RDS instance"
  value       = module.rds.db_instance_port
}

output "rds_database_name" {
  description = "Name of the default database"
  value       = module.rds.db_instance_name
}

output "rds_master_user_secret_arn" {
  description = "ARN of the AWS-managed secret containing the RDS master password"
  value       = module.rds.db_master_user_secret_arn
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Secrets Outputs
# -----------------------------------------------------------------------------
output "secrets_database_url_arn" {
  description = "ARN of the database URL secret"
  value       = module.secrets.database_url_secret_arn
  sensitive   = true
}

output "secrets_master_key_arn" {
  description = "ARN of the master key secret"
  value       = module.secrets.master_key_secret_arn
  sensitive   = true
}

output "secrets_salt_key_arn" {
  description = "ARN of the salt key secret"
  value       = module.secrets.salt_key_secret_arn
  sensitive   = true
}

output "secrets_redis_password_arn" {
  description = "ARN of the Redis password secret"
  value       = module.secrets.redis_password_secret_arn
  sensitive   = true
}

output "secrets_kms_key_arn" {
  description = "ARN of the KMS key used for secrets encryption"
  value       = module.secrets.kms_key_arn
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------
output "litellm_bedrock_role_arn" {
  description = "ARN of the LiteLLM Bedrock IAM role for IRSA"
  value       = module.iam.litellm_bedrock_role_arn
}

output "external_secrets_role_arn" {
  description = "ARN of the External Secrets Operator IAM role for IRSA"
  value       = module.iam.external_secrets_role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IAM role (if enabled)"
  value       = module.iam.cluster_autoscaler_role_arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM role (if enabled)"
  value       = module.iam.aws_load_balancer_controller_role_arn
}

output "ecr_push_pull_policy_arn" {
  description = "ARN of the ECR push/pull policy (attach to CI/CD IAM roles/users)"
  value       = module.iam.ecr_push_pull_policy_arn
}

# -----------------------------------------------------------------------------
# Kubectl Configuration
# -----------------------------------------------------------------------------
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# -----------------------------------------------------------------------------
# Deploy Script Environment Variables
# -----------------------------------------------------------------------------
output "deploy_script_env_vars" {
  description = "Environment variables to set for the deploy.sh script"
  value       = <<-EOT
    # Set these environment variables before running deploy.sh:
    export AWS_REGION="${var.aws_region}"
    export AWS_ACCOUNT_ID="${data.aws_caller_identity.current.account_id}"
    export EKS_CLUSTER_NAME="${module.eks.cluster_name}"
  EOT
}

# -----------------------------------------------------------------------------
# Bastion Outputs
# -----------------------------------------------------------------------------
output "bastion_instance_id" {
  description = "ID of the bastion EC2 instance"
  value       = var.create_bastion ? module.bastion[0].instance_id : null
}

output "bastion_ssm_connect_command" {
  description = "Command to connect to the bastion via SSM Session Manager"
  value       = var.create_bastion ? module.bastion[0].ssm_connect_command : null
}

# -----------------------------------------------------------------------------
# Additional Helper Outputs
# -----------------------------------------------------------------------------
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# ECR Outputs
# -----------------------------------------------------------------------------
output "ecr_repository_urls" {
  description = "Map of ECR repository URLs"
  value       = var.create_ecr_repositories ? module.ecr[0].repository_urls : {}
}

output "ecr_repository_arns" {
  description = "Map of ECR repository ARNs"
  value       = var.create_ecr_repositories ? module.ecr[0].repository_arns : {}
}

output "ecr_kms_key_arn" {
  description = "ARN of the KMS key used for ECR encryption"
  value       = var.create_ecr_repositories ? module.ecr[0].kms_key_arn : null
}

output "ecr_login_command" {
  description = "Command to authenticate Docker to ECR"
  value       = var.create_ecr_repositories ? module.ecr[0].ecr_login_command : null
}
