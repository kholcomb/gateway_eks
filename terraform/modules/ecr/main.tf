# ECR Module for Container Registry
# Creates private ECR repositories with security scanning, lifecycle policies, and encryption

# -----------------------------------------------------------------------------
# KMS Key for ECR Encryption
# -----------------------------------------------------------------------------
resource "aws_kms_key" "ecr" {
  count = var.enable_encryption ? 1 : 0

  description             = "${var.name_prefix}-ecr-encryption-key"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-ecr-key"
    }
  )
}

resource "aws_kms_alias" "ecr" {
  count = var.enable_encryption ? 1 : 0

  name          = "alias/${var.name_prefix}-ecr"
  target_key_id = aws_kms_key.ecr[0].key_id
}

# -----------------------------------------------------------------------------
# ECR Repositories
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = each.value.name
  image_tag_mutability = each.value.tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.enable_encryption ? "KMS" : "AES256"
    kms_key         = var.enable_encryption ? aws_kms_key.ecr[0].arn : null
  }

  tags = merge(
    var.tags,
    {
      Name       = each.value.name
      Repository = each.key
      Type       = each.key # infrastructure or deployments
    }
  )
}

# -----------------------------------------------------------------------------
# Lifecycle Policies
# -----------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${each.value.lifecycle_untagged_days} days of untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = each.value.lifecycle_untagged_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last ${each.value.lifecycle_tag_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = var.lifecycle_tag_prefixes
          countType     = "imageCountMoreThan"
          countNumber   = each.value.lifecycle_tag_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Repository Policies (Cross-Account Access)
# -----------------------------------------------------------------------------
resource "aws_ecr_repository_policy" "this" {
  for_each = var.enable_cross_account_access ? var.repositories : {}

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_principal_arns
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Replication Configuration (Optional)
# -----------------------------------------------------------------------------
resource "aws_ecr_replication_configuration" "this" {
  count = var.enable_replication ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.replication_destinations
        content {
          region      = destination.value.region
          registry_id = destination.value.registry_id
        }
      }

      repository_filter {
        filter      = var.replication_filter
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for ECR (Optional)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecr_scan_findings" {
  count = var.create_scan_findings_log_group ? 1 : 0

  name              = "/aws/ecr/${var.name_prefix}/scan-findings"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
