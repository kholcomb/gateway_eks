# LiteLLM EKS Infrastructure Variables

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "litellm"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

# -----------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (cost savings for non-prod)"
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# EKS Configuration
# -----------------------------------------------------------------------------
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "litellm-eks"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "eks_public_access" {
  description = "Enable public access to the EKS API endpoint"
  type        = bool
  default     = false
}

variable "eks_public_access_cidrs" {
  description = "CIDR blocks that can access the public EKS endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  sensitive   = true # May contain specific IPs for security
}

variable "eks_cluster_log_types" {
  description = "List of control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "eks_log_retention_days" {
  description = "Number of days to retain cluster logs"
  type        = number
  default     = 30
}

variable "eks_node_groups" {
  description = "Map of EKS managed node group configurations"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    disk_size      = number
    desired_size   = number
    min_size       = number
    max_size       = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = {
    default = {
      instance_types = ["t3a.medium", "t3.medium", "t2.medium"]
      capacity_type  = "SPOT"
      disk_size      = 50
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      labels         = {}
      taints         = []
    }
  }
}

# -----------------------------------------------------------------------------
# RDS Configuration
# -----------------------------------------------------------------------------
variable "rds_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum storage for autoscaling in GB"
  type        = number
  default     = 100
}

variable "rds_database_name" {
  description = "Name of the default database"
  type        = string
  default     = "litellm"
}

variable "rds_master_username" {
  description = "Master username for the database"
  type        = string
  default     = "litellm"
  sensitive   = true
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "rds_backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = false
}

variable "rds_performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "create_rds_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for RDS"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Secrets Configuration
# -----------------------------------------------------------------------------
variable "secrets_prefix" {
  description = "Prefix for secrets in Secrets Manager"
  type        = string
  default     = "litellm"
}

# -----------------------------------------------------------------------------
# IAM / IRSA Configuration
# -----------------------------------------------------------------------------
variable "litellm_namespace" {
  description = "Kubernetes namespace for LiteLLM"
  type        = string
  default     = "litellm"
}

variable "litellm_service_account" {
  description = "Kubernetes service account name for LiteLLM"
  type        = string
  default     = "litellm-sa"
}

variable "external_secrets_namespace" {
  description = "Kubernetes namespace for External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "Kubernetes service account name for External Secrets"
  type        = string
  default     = "external-secrets"
}

variable "bedrock_model_arns" {
  description = "List of Bedrock model ARNs to allow access to"
  type        = list(string)
  default = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-opus-20240229-v1:0",
    "arn:aws:bedrock:*::foundation-model/meta.llama3-1-70b-instruct-v1:0",
    "arn:aws:bedrock:*::foundation-model/meta.llama3-1-8b-instruct-v1:0",
    "arn:aws:bedrock:*::foundation-model/mistral.mistral-large-2402-v1:0"
  ]
}

# -----------------------------------------------------------------------------
# Optional Controllers
# -----------------------------------------------------------------------------
variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler IAM role"
  type        = bool
  default     = false
}

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller IAM role"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Bastion Configuration (for testing without public exposure)
# -----------------------------------------------------------------------------
variable "create_bastion" {
  description = "Create a bastion EC2 for testing OpenWebUI via port-forward (no public exposure)"
  type        = bool
  default     = false
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
  default     = "t3.medium"
}

# -----------------------------------------------------------------------------
# ECR Configuration
# -----------------------------------------------------------------------------
variable "create_ecr_repositories" {
  description = "Create ECR repositories for container images"
  type        = bool
  default     = true
}

variable "ecr_infrastructure_repository" {
  description = "Infrastructure repository configuration (for litellm, openwebui, etc.)"
  type = object({
    name                    = string
    tag_mutability          = string
    lifecycle_tag_count     = number
    lifecycle_untagged_days = number
  })
  default = {
    name                    = "infrastructure"
    tag_mutability          = "IMMUTABLE"
    lifecycle_tag_count     = 20 # Keep more versions for infrastructure
    lifecycle_untagged_days = 7
  }
}

variable "ecr_deployments_repository" {
  description = "Deployments repository configuration (for mcp-servers, custom apps, etc.)"
  type = object({
    name                    = string
    tag_mutability          = string
    lifecycle_tag_count     = number
    lifecycle_untagged_days = number
  })
  default = {
    name                    = "deployments"
    tag_mutability          = "MUTABLE"
    lifecycle_tag_count     = 10
    lifecycle_untagged_days = 3 # More aggressive cleanup
  }
}

variable "ecr_scan_on_push" {
  description = "Enable image scanning on push to ECR"
  type        = bool
  default     = true
}

variable "ecr_enable_encryption" {
  description = "Enable KMS encryption for ECR repositories"
  type        = bool
  default     = true
}
