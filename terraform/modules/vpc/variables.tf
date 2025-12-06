# VPC Module Variables

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster (for subnet tagging)"
  type        = string
}

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
  description = "Use a single NAT gateway for all private subnets (cost savings for non-prod)"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC flow logs"
  type        = number
  default     = 30
}

variable "public_subnet_newbits" {
  description = "Number of additional bits to add to VPC CIDR for public subnets (e.g., 4 creates /20 subnets from /16 VPC)"
  type        = number
  default     = 4
}

variable "private_subnet_newbits" {
  description = "Number of additional bits to add to VPC CIDR for private subnets"
  type        = number
  default     = 4
}

variable "database_subnet_newbits" {
  description = "Number of additional bits to add to VPC CIDR for database subnets"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
