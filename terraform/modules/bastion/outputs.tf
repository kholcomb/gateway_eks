# Bastion Module Outputs

output "instance_id" {
  description = "ID of the bastion EC2 instance"
  value       = var.create_bastion ? aws_instance.bastion[0].id : null
}

output "instance_private_ip" {
  description = "Private IP address of the bastion instance"
  value       = var.create_bastion ? aws_instance.bastion[0].private_ip : null
}

output "security_group_id" {
  description = "Security group ID of the bastion instance"
  value       = aws_security_group.bastion.id
}

output "iam_role_arn" {
  description = "ARN of the bastion IAM role"
  value       = aws_iam_role.bastion.arn
}

output "iam_role_name" {
  description = "Name of the bastion IAM role"
  value       = aws_iam_role.bastion.name
}

output "ssm_connect_command" {
  description = "Command to connect to the bastion via SSM"
  value       = var.create_bastion ? "aws ssm start-session --target ${aws_instance.bastion[0].id} --region ${data.aws_region.current.name}" : null
}
