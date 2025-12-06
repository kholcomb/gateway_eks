# Production Environment Configuration
# Optimized for high availability, reliability, and observability

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------
aws_region   = "us-east-1"
project_name = "litellm"
environment  = "prod"

# -----------------------------------------------------------------------------
# VPC Configuration (Production)
# -----------------------------------------------------------------------------
vpc_cidr             = "10.0.0.0/16"
az_count             = 3  # Full 3 AZ deployment for HA
single_nat_gateway   = false  # NAT per AZ for resilience
enable_vpc_flow_logs = true   # Enable for security monitoring

# -----------------------------------------------------------------------------
# EKS Configuration (Production)
# -----------------------------------------------------------------------------
eks_cluster_name    = "litellm-eks-prod"
eks_cluster_version = "1.31"
eks_public_access   = true

# IMPORTANT: Restrict to known IP ranges for security
eks_public_access_cidrs = [
  "0.0.0.0/0"  # CHANGE THIS: Replace with your organization's IPs
  # Example: "203.0.113.0/24", "198.51.100.0/24"
]

eks_cluster_log_types  = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
eks_log_retention_days = 90  # Longer retention for compliance

# Production-grade node groups
eks_node_groups = {
  # General workload nodes
  default = {
    instance_types = ["m6i.xlarge", "m5.xlarge"]  # Larger, more powerful
    capacity_type  = "ON_DEMAND"                   # On-demand for reliability
    disk_size      = 200
    desired_size   = 4
    min_size       = 3
    max_size       = 10
    labels = {
      environment = "prod"
      workload    = "general"
    }
    taints = []
  }

  # Optional: Dedicated monitoring nodes
  # Uncomment if you want to separate monitoring workloads
  # monitoring = {
  #   instance_types = ["m6i.2xlarge"]
  #   capacity_type  = "ON_DEMAND"
  #   disk_size      = 300
  #   desired_size   = 2
  #   min_size       = 2
  #   max_size       = 4
  #   labels = {
  #     environment = "prod"
  #     workload    = "monitoring"
  #   }
  #   taints = [
  #     {
  #       key    = "workload"
  #       value  = "monitoring"
  #       effect = "NoSchedule"
  #     }
  #   ]
  # }
}

# -----------------------------------------------------------------------------
# RDS Configuration (Production)
# -----------------------------------------------------------------------------
rds_engine_version               = "16.4"
rds_instance_class               = "db.r6g.xlarge"  # Production-grade instance
rds_allocated_storage            = 100
rds_max_allocated_storage        = 500              # Higher autoscaling limit
rds_database_name                = "litellm"
rds_master_username              = "litellm"
rds_multi_az                     = true             # Multi-AZ for HA
rds_backup_retention_period      = 30               # 30 days for compliance
rds_deletion_protection          = true             # Prevent accidental deletion
rds_skip_final_snapshot          = false            # Create final snapshot
rds_performance_insights_enabled = true             # Enable for troubleshooting
create_rds_cloudwatch_alarms     = true             # Create alarms

# -----------------------------------------------------------------------------
# Secrets Configuration
# -----------------------------------------------------------------------------
secrets_prefix = "litellm-prod"

# -----------------------------------------------------------------------------
# IAM / IRSA Configuration
# -----------------------------------------------------------------------------
litellm_namespace                = "litellm"
litellm_service_account          = "litellm-sa"
external_secrets_namespace       = "external-secrets"
external_secrets_service_account = "external-secrets"

# Production Bedrock models
bedrock_model_arns = [
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0",
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-opus-20240229-v1:0",
  "arn:aws:bedrock:*::foundation-model/meta.llama3-1-70b-instruct-v1:0",
  "arn:aws:bedrock:*::foundation-model/meta.llama3-1-8b-instruct-v1:0",
  "arn:aws:bedrock:*::foundation-model/mistral.mistral-large-2402-v1:0",
]

# -----------------------------------------------------------------------------
# Optional Controllers
# -----------------------------------------------------------------------------
enable_cluster_autoscaler           = true  # Enable for production autoscaling
enable_aws_load_balancer_controller = true  # Enable if using ALB/NLB ingress

# -----------------------------------------------------------------------------
# Bastion Configuration
# -----------------------------------------------------------------------------
# Disable bastion in production - use VPN or AWS Client VPN instead
create_bastion        = false
bastion_instance_type = "t3.medium"

# -----------------------------------------------------------------------------
# Estimated Monthly Cost (us-east-1, as of Dec 2024)
# -----------------------------------------------------------------------------
# - EKS Control Plane: $73
# - 4x m6i.xlarge on-demand nodes: ~$580
# - RDS db.r6g.xlarge Multi-AZ: ~$470
# - NAT Gateways (3): ~$100
# - EBS volumes (800GB total): ~$80
# - Data transfer & CloudWatch: ~$100
# TOTAL: ~$1,403/month (baseline, excludes Bedrock API costs)
#
# Notes:
# - Bedrock costs are usage-based (input/output tokens)
# - Consider Reserved Instances for 40% savings on compute
# - Consider Savings Plans for RDS for 30-40% savings
# - Monitor with AWS Cost Explorer and set budgets
# -----------------------------------------------------------------------------
