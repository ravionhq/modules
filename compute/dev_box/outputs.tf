################################################################################
# Outputs
################################################################################

output "instance_id" {
  description = "ID of the dev box instance."
  value       = aws_instance.this.id
}

output "instance_arn" {
  description = "ARN of the dev box instance."
  value       = aws_instance.this.arn
}

output "region" {
  description = "AWS region of the dev box."
  value       = local.region
}

output "availability_zone" {
  description = "Availability zone of the dev box."
  value       = aws_instance.this.availability_zone
}

output "private_ip" {
  description = "Private IPv4 address of the dev box."
  value       = aws_instance.this.private_ip
}

output "private_dns" {
  description = "Private DNS name of the dev box."
  value       = aws_instance.this.private_dns
}

output "public_ip" {
  description = "Public IPv4 address, or null when none is assigned. It changes when the instance is stopped and started."
  value       = var.public_ip_assignment_enabled ? aws_instance.this.public_ip : null
}

output "ami_id" {
  description = "AMI the dev box was launched from."
  value       = aws_instance.this.ami
}

output "login_user" {
  description = "Default SSH login user for the base image, or null for a custom AMI."
  value       = local.login_user
}

output "security_group_id" {
  description = "ID of the dev box security group."
  value       = aws_security_group.this.id
}

output "iam_role_name" {
  description = "Name of the instance IAM role. Attach more policies to it to grant the box AWS access."
  value       = aws_iam_role.instance.name
}

output "iam_role_arn" {
  description = "ARN of the instance IAM role."
  value       = aws_iam_role.instance.arn
}

output "ssm_start_session_command" {
  description = "AWS CLI command that opens a Session Manager shell on the dev box."
  value       = var.ssm_enabled ? "aws ssm start-session --region ${local.region} --target ${aws_instance.this.id}" : null
}

output "auto_stop_schedule_arn" {
  description = "ARN of the auto stop schedule, or null when auto stop is off."
  value       = var.auto_stop_enabled ? aws_scheduler_schedule.auto_stop[0].arn : null
}
