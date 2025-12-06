# Development Environment Configuration
# Optimized for cost savings - single NAT, smaller instances, no Multi-AZ

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------
aws_region   = "us-east-1"
project_name = "litellm"
environment  = "dev"

# -----------------------------------------------------------------------------
# VPC Configuration (Cost Optimized)
# -----------------------------------------------------------------------------
vpc_cidr             = "10.0.0.0/16"
az_count             = 2  # Only 2 AZs for dev
single_nat_gateway   = true  # Single NAT gateway to save costs (~$32/month savings)
enable_vpc_flow_logs = false # Disable flow logs in dev to save costs

# -----------------------------------------------------------------------------
# EKS Configuration (Cost Optimized)
# -----------------------------------------------------------------------------
eks_cluster_name    = "litellm-eks-dev"
eks_cluster_version = "1.31"
eks_public_access   = true

# Restrict API access to specific IPs for security (replace with your IPs)
# eks_public_access_cidrs = ["your.ip.address/32"]

eks_cluster_log_types  = ["api", "audit"]  # Only essential logs
eks_log_retention_days = 7                  # Shorter retention for dev

# Smaller node group for dev
eks_node_groups = {
  default = {
    instance_types = ["t3.large"]  # Burstable instances
    capacity_type  = "SPOT"        # Use spot instances for 70% cost savings
    disk_size      = 50            # Smaller disk
    desired_size   = 2
    min_size       = 1
    max_size       = 3
    labels         = {
      environment = "dev"
    }
    taints = []
  }
}

# -----------------------------------------------------------------------------
# RDS Configuration (Cost Optimized)
# -----------------------------------------------------------------------------
rds_engine_version               = "16.4"
rds_instance_class               = "db.t3.small"  # Smaller instance
rds_allocated_storage            = 20
rds_max_allocated_storage        = 50             # Lower max storage
rds_database_name                = "litellm"
rds_master_username              = "litellm"
rds_multi_az                     = false          # Single AZ for dev
rds_backup_retention_period      = 3              # Shorter retention
rds_deletion_protection          = false          # Allow easy cleanup
rds_skip_final_snapshot          = true           # Skip final snapshot
rds_performance_insights_enabled = false          # Disable to save costs
create_rds_cloudwatch_alarms     = false          # No alarms needed in dev

# -----------------------------------------------------------------------------
# Secrets Configuration
# -----------------------------------------------------------------------------
secrets_prefix = "litellm-dev"

# -----------------------------------------------------------------------------
# IAM / IRSA Configuration
# -----------------------------------------------------------------------------
litellm_namespace                = "litellm"
litellm_service_account          = "litellm-sa"
external_secrets_namespace       = "external-secrets"
external_secrets_service_account = "external-secrets"

# Limited Bedrock models for dev
bedrock_model_arns = [
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",  # Cheapest model for testing
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
]

# -----------------------------------------------------------------------------
# Optional Controllers
# -----------------------------------------------------------------------------
enable_cluster_autoscaler           = false
enable_aws_load_balancer_controller = false

# -----------------------------------------------------------------------------
# Bastion Configuration
# -----------------------------------------------------------------------------
# Enable bastion for testing without public exposure
create_bastion        = true
bastion_instance_type = "t3.small"  # Smaller instance for dev

# -----------------------------------------------------------------------------
# Estimated Monthly Cost (us-east-1, as of Dec 2024)
# -----------------------------------------------------------------------------
# - EKS Control Plane: $73
# - 2x t3.large spot nodes (~70% discount): ~$36
# - RDS db.t3.small single-AZ: ~$30
# - NAT Gateway (1): ~$33
# - Bastion t3.small: ~$15
# - EBS volumes, data transfer: ~$20
# TOTAL: ~$207/month
# -----------------------------------------------------------------------------
