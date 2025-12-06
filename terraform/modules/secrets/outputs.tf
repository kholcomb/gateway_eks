# Secrets Module Outputs

output "database_url_secret_arn" {
  description = "ARN of the database URL secret"
  value       = aws_secretsmanager_secret.database_url.arn
}

output "database_url_secret_name" {
  description = "Name of the database URL secret"
  value       = aws_secretsmanager_secret.database_url.name
}

output "master_key_secret_arn" {
  description = "ARN of the master key secret"
  value       = aws_secretsmanager_secret.master_key.arn
}

output "master_key_secret_name" {
  description = "Name of the master key secret"
  value       = aws_secretsmanager_secret.master_key.name
}

output "salt_key_secret_arn" {
  description = "ARN of the salt key secret"
  value       = aws_secretsmanager_secret.salt_key.arn
}

output "salt_key_secret_name" {
  description = "Name of the salt key secret"
  value       = aws_secretsmanager_secret.salt_key.name
}

output "redis_password_secret_arn" {
  description = "ARN of the Redis password secret"
  value       = aws_secretsmanager_secret.redis_password.arn
}

output "redis_password_secret_name" {
  description = "Name of the Redis password secret"
  value       = aws_secretsmanager_secret.redis_password.name
}

output "secrets_read_policy_arn" {
  description = "ARN of the IAM policy for reading secrets"
  value       = aws_iam_policy.secrets_read.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = local.kms_key_arn
}

output "master_key" {
  description = "Generated master key value (sensitive)"
  value       = local.master_key
  sensitive   = true
}

output "redis_password" {
  description = "Generated Redis password value (sensitive)"
  value       = local.redis_password
  sensitive   = true
}
