# IAM Module Outputs

output "litellm_bedrock_role_arn" {
  description = "ARN of the LiteLLM Bedrock IAM role"
  value       = aws_iam_role.litellm_bedrock.arn
}

output "litellm_bedrock_role_name" {
  description = "Name of the LiteLLM Bedrock IAM role"
  value       = aws_iam_role.litellm_bedrock.name
}

output "external_secrets_role_arn" {
  description = "ARN of the External Secrets Operator IAM role"
  value       = aws_iam_role.external_secrets.arn
}

output "external_secrets_role_name" {
  description = "Name of the External Secrets Operator IAM role"
  value       = aws_iam_role.external_secrets.name
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IAM role"
  value       = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler[0].arn : null
}

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM role"
  value       = var.enable_aws_load_balancer_controller ? aws_iam_role.aws_load_balancer_controller[0].arn : null
}

output "ecr_push_pull_policy_arn" {
  description = "ARN of the ECR push/pull IAM policy (for attaching to CI/CD roles)"
  value       = length(var.ecr_repository_arns) > 0 ? aws_iam_policy.ecr_push_pull[0].arn : null
}

output "ecr_push_pull_policy_name" {
  description = "Name of the ECR push/pull IAM policy"
  value       = length(var.ecr_repository_arns) > 0 ? aws_iam_policy.ecr_push_pull[0].name : null
}
