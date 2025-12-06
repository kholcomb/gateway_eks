# LiteLLM EKS Infrastructure
# Root Terraform configuration for deploying LiteLLM on AWS EKS

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "litellm/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "litellm-k8s-deploy"
  }

  # Build database connection URL for secrets module
  database_url = "postgresql://${var.rds_master_username}@${module.rds.db_instance_address}:${module.rds.db_instance_port}/${var.rds_database_name}"
}

# -----------------------------------------------------------------------------
# VPC Module
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  name_prefix        = local.name_prefix
  cluster_name       = var.eks_cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  enable_flow_logs   = var.enable_vpc_flow_logs

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# EKS Module
# -----------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  cluster_name    = var.eks_cluster_name
  cluster_version = var.eks_cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids

  endpoint_private_access    = true
  endpoint_public_access     = var.eks_public_access
  public_access_cidrs        = var.eks_public_access_cidrs
  enabled_cluster_log_types  = var.eks_cluster_log_types
  cluster_log_retention_days = var.eks_log_retention_days

  node_groups = var.eks_node_groups

  enable_ebs_csi_driver    = true
  create_gp3_storage_class = true
  gp3_as_default           = true

  tags = local.common_tags

  depends_on = [module.vpc]
}

# -----------------------------------------------------------------------------
# RDS Module
# -----------------------------------------------------------------------------
module "rds" {
  source = "./modules/rds"

  name_prefix               = local.name_prefix
  vpc_id                    = module.vpc.vpc_id
  db_subnet_group_name      = module.vpc.database_subnet_group_name
  allowed_security_group_id = module.eks.node_security_group_id

  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  database_name         = var.rds_database_name
  master_username       = var.rds_master_username
  multi_az              = var.rds_multi_az

  backup_retention_period      = var.rds_backup_retention_period
  deletion_protection          = var.rds_deletion_protection
  skip_final_snapshot          = var.rds_skip_final_snapshot
  performance_insights_enabled = var.rds_performance_insights_enabled

  create_cloudwatch_alarms = var.create_rds_cloudwatch_alarms

  tags = local.common_tags

  depends_on = [module.vpc, module.eks]
}

# -----------------------------------------------------------------------------
# Secrets Module
# -----------------------------------------------------------------------------
module "secrets" {
  source = "./modules/secrets"

  name_prefix    = local.name_prefix
  secrets_prefix = var.secrets_prefix
  database_url   = local.database_url

  generate_master_key     = true
  generate_salt_key       = true
  generate_redis_password = true

  tags = local.common_tags

  depends_on = [module.rds]
}

# -----------------------------------------------------------------------------
# IAM Module (IRSA Roles)
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  name_prefix       = local.name_prefix
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer       = module.eks.cluster_oidc_issuer_url

  litellm_namespace       = var.litellm_namespace
  litellm_service_account = var.litellm_service_account
  bedrock_model_arns      = var.bedrock_model_arns

  external_secrets_namespace       = var.external_secrets_namespace
  external_secrets_service_account = var.external_secrets_service_account

  secrets_arns = [
    module.secrets.database_url_secret_arn,
    module.secrets.master_key_secret_arn,
    module.secrets.salt_key_secret_arn,
    module.secrets.redis_password_secret_arn,
    module.rds.db_master_user_secret_arn,
  ]

  kms_key_arns = [
    module.secrets.kms_key_arn,
  ]

  enable_cluster_autoscaler           = var.enable_cluster_autoscaler
  enable_aws_load_balancer_controller = var.enable_aws_load_balancer_controller

  tags = local.common_tags

  depends_on = [module.eks, module.secrets]
}

# -----------------------------------------------------------------------------
# Bastion Module (Optional)
# -----------------------------------------------------------------------------
module "bastion" {
  source = "./modules/bastion"

  count = var.create_bastion ? 1 : 0

  name_prefix                = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  subnet_id                  = module.vpc.private_subnet_ids[0]
  eks_cluster_name           = module.eks.cluster_name
  eks_node_security_group_id = module.eks.node_security_group_id
  instance_type              = var.bastion_instance_type
  create_eks_access_entry    = true

  tags = local.common_tags

  depends_on = [module.eks]
}
