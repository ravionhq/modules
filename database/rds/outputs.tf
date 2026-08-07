################################################################################
# DB Instance Outputs
################################################################################

output "db_instance_id" {
  description = "The ID of the RDS instance."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance."
  value       = aws_db_instance.this.arn
}

output "db_instance_identifier" {
  description = "The identifier of the RDS instance."
  value       = aws_db_instance.this.identifier
}

output "db_instance_resource_id" {
  description = "The resource ID of the RDS instance."
  value       = aws_db_instance.this.resource_id
}

output "db_instance_status" {
  description = "The status of the RDS instance."
  value       = aws_db_instance.this.status
}

output "db_instance_availability_zone" {
  description = "The availability zone of the RDS instance."
  value       = aws_db_instance.this.availability_zone
}

################################################################################
# Connection Outputs
################################################################################

output "endpoint" {
  description = "The connection endpoint of the RDS instance in address:port format."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "The hostname of the RDS instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "The port on which the database accepts connections."
  value       = aws_db_instance.this.port
}

output "hosted_zone_id" {
  description = "The Route53 hosted zone ID of the RDS instance."
  value       = aws_db_instance.this.hosted_zone_id
}

################################################################################
# Database Outputs
################################################################################

output "engine" {
  description = "The database engine used."
  value       = aws_db_instance.this.engine
}

output "engine_version_actual" {
  description = "The actual engine version running on the RDS instance."
  value       = aws_db_instance.this.engine_version_actual
}

output "db_name" {
  description = "The database name."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "The master username for the database."
  value       = aws_db_instance.this.username
}

################################################################################
# Secrets Manager Outputs
################################################################################

output "master_user_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the master user credentials."
  value       = var.master_user_password_management_enabled ? try(aws_db_instance.this.master_user_secret[0].secret_arn, null) : null
}

################################################################################
# Read Replica Outputs
################################################################################

output "read_replica_identifiers" {
  description = "List of identifiers for the read replicas."
  value       = aws_db_instance.read_replica[*].identifier
}

output "read_replica_endpoints" {
  description = "List of endpoints for the read replicas."
  value       = aws_db_instance.read_replica[*].endpoint
}

output "read_replica_arns" {
  description = "List of ARNs for the read replicas."
  value       = aws_db_instance.read_replica[*].arn
}

################################################################################
# Security Group Outputs
################################################################################

output "security_group_id" {
  description = "The ID of the security group."
  value       = local.create_security_group ? module.security_group[0].security_group_id : var.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the security group."
  value       = local.create_security_group ? module.security_group[0].security_group_arn : null
}

################################################################################
# Subnet Group Outputs
################################################################################

output "db_subnet_group_name" {
  description = "The name of the DB subnet group."
  value       = aws_db_subnet_group.this.name
}

output "db_subnet_group_arn" {
  description = "The ARN of the DB subnet group."
  value       = aws_db_subnet_group.this.arn
}

################################################################################
# Parameter Group Outputs
################################################################################

output "db_parameter_group_name" {
  description = "The name of the DB parameter group. Managed groups are named with the rds- prefix."
  value       = local.create_parameter_group ? aws_db_parameter_group.this[0].name : var.parameter_group_name
}

output "db_parameter_group_arn" {
  description = "The ARN of the DB parameter group."
  value       = local.create_parameter_group ? aws_db_parameter_group.this[0].arn : null
}

################################################################################
# Option Group Outputs
################################################################################

output "db_option_group_name" {
  description = "The name of the DB option group."
  value       = local.create_option_group ? aws_db_option_group.this[0].name : var.option_group_name
}

output "db_option_group_arn" {
  description = "The ARN of the DB option group."
  value       = local.create_option_group ? aws_db_option_group.this[0].arn : null
}

################################################################################
# Monitoring Outputs
################################################################################

output "enhanced_monitoring_iam_role_arn" {
  description = "The ARN of the IAM role used for Enhanced Monitoring."
  value       = local.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn
}

output "cloudwatch_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs created by this module."
  value = local.create_cloudwatch_alarms ? {
    cpu_utilization      = aws_cloudwatch_metric_alarm.cpu_utilization[0].arn
    free_storage_space   = aws_cloudwatch_metric_alarm.free_storage_space[0].arn
    database_connections = aws_cloudwatch_metric_alarm.database_connections[0].arn
  } : {}
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

################################################################################
# RDS Proxy Outputs
################################################################################

output "proxy_endpoint" {
  description = "The endpoint of the RDS Proxy. Null when no proxy is created."
  value       = local.create_proxy ? module.proxy[0].endpoint : null
}

output "proxy_arn" {
  description = "The ARN of the RDS Proxy. Null when no proxy is created."
  value       = local.create_proxy ? module.proxy[0].proxy_arn : null
}

output "proxy_security_group_id" {
  description = "The ID of the RDS Proxy security group. Null when no proxy is created."
  value       = local.create_proxy ? module.proxy[0].security_group_id : null
}
