# Secrets Module Variables

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "secrets_prefix" {
  description = "Prefix for secrets in Secrets Manager (e.g., 'litellm')"
  type        = string
  default     = "litellm"
}

variable "database_url" {
  description = "PostgreSQL connection string"
  type        = string
  sensitive   = true
}

variable "master_key" {
  description = "LiteLLM master API key (generated if not specified)"
  type        = string
  default     = null
  sensitive   = true
}

variable "generate_master_key" {
  description = "Generate a master key automatically"
  type        = bool
  default     = true
}

variable "salt_key" {
  description = "LiteLLM salt key (generated if not specified)"
  type        = string
  default     = null
  sensitive   = true
}

variable "generate_salt_key" {
  description = "Generate a salt key automatically"
  type        = bool
  default     = true
}

variable "redis_password" {
  description = "Redis password (generated if not specified)"
  type        = string
  default     = null
  sensitive   = true
}

variable "generate_redis_password" {
  description = "Generate a Redis password automatically"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of existing KMS key for encryption (creates new key if not specified)"
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Number of days before a secret is permanently deleted"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
