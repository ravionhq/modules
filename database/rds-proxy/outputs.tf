################################################################################
# Proxy Outputs
################################################################################

output "proxy_id" {
  description = "The ID of the RDS Proxy."
  value       = aws_db_proxy.this.id
}

output "proxy_arn" {
  description = "The ARN of the RDS Proxy."
  value       = aws_db_proxy.this.arn
}

output "proxy_name" {
  description = "The name of the RDS Proxy."
  value       = aws_db_proxy.this.name
}

################################################################################
# Connection Outputs
################################################################################

output "endpoint" {
  description = "The endpoint that applications use to connect through the proxy."
  value       = aws_db_proxy.this.endpoint
}

output "port" {
  description = "The port on which the proxy accepts connections."
  value       = local.port
}

################################################################################
# Target Group Outputs
################################################################################

output "default_target_group_name" {
  description = "The name of the default proxy target group."
  value       = aws_db_proxy_default_target_group.this.name
}

output "default_target_group_arn" {
  description = "The ARN of the default proxy target group."
  value       = aws_db_proxy_default_target_group.this.arn
}

################################################################################
# IAM Outputs
################################################################################

output "iam_role_arn" {
  description = "The ARN of the IAM role the proxy uses to read Secrets Manager secrets."
  value       = local.iam_role_arn
}

################################################################################
# Security Group Outputs
################################################################################

output "security_group_id" {
  description = "The ID of the security group."
  value       = local.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the security group."
  value       = local.create_security_group ? module.security_group[0].security_group_arn : null
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the resources are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the resources are deployed."
  value       = local.region
}
