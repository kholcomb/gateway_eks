# ECR Module Variables

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "repositories" {
  description = "Map of repository configurations to create"
  type = map(object({
    name                    = string
    tag_mutability          = string
    lifecycle_tag_count     = number
    lifecycle_untagged_days = number
  }))
  default = {}
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable KMS encryption for ECR repositories"
  type        = bool
  default     = true
}

variable "kms_deletion_window_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Lifecycle Policy Variables
# -----------------------------------------------------------------------------
variable "lifecycle_tag_prefixes" {
  description = "List of tag prefixes for lifecycle policy"
  type        = list(string)
  default     = ["v", "prod", "staging", "dev"]
}

# -----------------------------------------------------------------------------
# Cross-Account Access Variables
# -----------------------------------------------------------------------------
variable "enable_cross_account_access" {
  description = "Enable cross-account access to ECR repositories"
  type        = bool
  default     = false
}

variable "allowed_principal_arns" {
  description = "List of AWS principal ARNs allowed to pull images"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Replication Variables
# -----------------------------------------------------------------------------
variable "enable_replication" {
  description = "Enable ECR replication to other regions"
  type        = bool
  default     = false
}

variable "replication_destinations" {
  description = "List of replication destinations"
  type = list(object({
    region      = string
    registry_id = string
  }))
  default = []
}

variable "replication_filter" {
  description = "Repository prefix filter for replication"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudWatch Variables
# -----------------------------------------------------------------------------
variable "create_scan_findings_log_group" {
  description = "Create CloudWatch log group for scan findings"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
