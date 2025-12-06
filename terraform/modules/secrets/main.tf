# Secrets Manager Module for LiteLLM
# Creates and manages secrets in AWS Secrets Manager

# -----------------------------------------------------------------------------
# Random Value Generators
# -----------------------------------------------------------------------------
resource "random_password" "master_key" {
  count = var.generate_master_key ? 1 : 0

  length  = 64
  special = false
}

resource "random_password" "salt_key" {
  count = var.generate_salt_key ? 1 : 0

  length  = 64
  special = false
}

resource "random_password" "redis_password" {
  count = var.generate_redis_password ? 1 : 0

  length  = 32
  special = false
}

locals {
  master_key     = var.generate_master_key ? "sk-${random_password.master_key[0].result}" : var.master_key
  salt_key       = var.generate_salt_key ? random_password.salt_key[0].result : var.salt_key
  redis_password = var.generate_redis_password ? random_password.redis_password[0].result : var.redis_password
}

# -----------------------------------------------------------------------------
# KMS Key for Secrets Encryption
# -----------------------------------------------------------------------------
resource "aws_kms_key" "secrets" {
  count = var.kms_key_arn == null ? 1 : 0

  description             = "KMS key for ${var.name_prefix} secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-secrets-key"
  })
}

resource "aws_kms_alias" "secrets" {
  count = var.kms_key_arn == null ? 1 : 0

  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets[0].key_id
}

data "aws_caller_identity" "current" {}

locals {
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.secrets[0].arn
}

# -----------------------------------------------------------------------------
# Database URL Secret
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "database_url" {
  name        = "${var.secrets_prefix}/database-url"
  description = "PostgreSQL connection string for LiteLLM"
  kms_key_id  = local.kms_key_arn

  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-database-url"
  })
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = var.database_url
}

# -----------------------------------------------------------------------------
# Master Key Secret
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "master_key" {
  name        = "${var.secrets_prefix}/master-key"
  description = "LiteLLM master API key"
  kms_key_id  = local.kms_key_arn

  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-master-key"
  })
}

resource "aws_secretsmanager_secret_version" "master_key" {
  secret_id     = aws_secretsmanager_secret.master_key.id
  secret_string = local.master_key
}

# -----------------------------------------------------------------------------
# Salt Key Secret
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "salt_key" {
  name        = "${var.secrets_prefix}/salt-key"
  description = "LiteLLM salt key for encryption (immutable after deployment)"
  kms_key_id  = local.kms_key_arn

  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-salt-key"
  })
}

resource "aws_secretsmanager_secret_version" "salt_key" {
  secret_id     = aws_secretsmanager_secret.salt_key.id
  secret_string = local.salt_key

  lifecycle {
    # Salt key should never change after initial creation
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# Redis Password Secret
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "redis_password" {
  name        = "${var.secrets_prefix}/redis-password"
  description = "Redis password for LiteLLM cache"
  kms_key_id  = local.kms_key_arn

  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-redis-password"
  })
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id     = aws_secretsmanager_secret.redis_password.id
  secret_string = local.redis_password
}

# -----------------------------------------------------------------------------
# IAM Policy for Reading Secrets
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "secrets_read" {
  name        = "${var.name_prefix}-secrets-read"
  description = "Policy for reading LiteLLM secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.database_url.arn,
          aws_secretsmanager_secret.master_key.arn,
          aws_secretsmanager_secret.salt_key.arn,
          aws_secretsmanager_secret.redis_password.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = local.kms_key_arn
      }
    ]
  })

  tags = var.tags
}
