# Bastion Module Variables

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the bastion instance (should be a private subnet)"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS nodes (for network access)"
  type        = string
}

variable "create_bastion" {
  description = "Whether to create the bastion instance"
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 20
}

variable "create_eks_access_entry" {
  description = "Create EKS access entry for the bastion role (for API auth mode)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
