# IAM Module Variables

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "oidc_issuer" {
  description = "OIDC issuer URL (without https://)"
  type        = string
}

# LiteLLM Bedrock Configuration
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

# External Secrets Configuration
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

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARNs to allow access to"
  type        = list(string)
}

variable "kms_key_arns" {
  description = "List of KMS key ARNs for decrypting secrets"
  type        = list(string)
}

# Optional Controllers
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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
