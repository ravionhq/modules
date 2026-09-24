################################################################################
# Lambda Function
################################################################################

output "function_name" {
  description = "The name of the Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "The ARN of the Lambda function."
  value       = aws_lambda_function.this.arn
}

output "function_invoke_arn" {
  description = "The invoke ARN of the Lambda function."
  value       = aws_lambda_function.this.invoke_arn
}

output "function_qualified_arn" {
  description = "The qualified ARN of the Lambda function."
  value       = aws_lambda_function.this.qualified_arn
}

output "function_version" {
  description = "The latest published version of the Lambda function."
  value       = aws_lambda_function.this.version
}

output "function_last_modified" {
  description = "The date this resource was last modified."
  value       = aws_lambda_function.this.last_modified
}

################################################################################
# IAM
################################################################################

output "role_arn" {
  description = "The IAM role ARN used by the Lambda function."
  value       = local.lambda_role_arn
}

################################################################################
# CloudWatch Logs
################################################################################

output "log_group_name" {
  description = "The CloudWatch log group name used by the Lambda function."
  value       = local.log_group_name
}

output "log_group_arn" {
  description = "The CloudWatch log group ARN, or null if not created by this module."
  value       = var.log_group_creation_enabled ? aws_cloudwatch_log_group.this[0].arn : null
}

################################################################################
# Integrations
################################################################################

output "permission_statement_ids" {
  description = "Map of permission item index to statement ID."
  value = {
    for k, v in aws_lambda_permission.this : k => v.statement_id
  }
}

output "event_source_mapping_ids" {
  description = "Map of event source mapping item index to UUID."
  value = {
    for k, v in aws_lambda_event_source_mapping.this : k => v.uuid
  }
}

output "alias_arns" {
  description = "Map of alias names to alias ARNs."
  value = {
    for alias_name, alias in aws_lambda_alias.this : alias_name => alias.arn
  }
}

output "function_url" {
  description = "Lambda function URL, or null when function_url_enabled is false."
  value       = var.function_url_enabled ? aws_lambda_function_url.this[0].function_url : null
}

################################################################################
# Code Bucket
################################################################################

output "code_bucket_id" {
  description = "The name of the auto-created S3 bucket holding the deployment package, or null if not created."
  value       = local.create_code_bucket ? module.code_bucket[0].bucket_id : null
}

output "code_bucket_arn" {
  description = "The ARN of the auto-created S3 bucket holding the deployment package, or null if not created."
  value       = local.create_code_bucket ? module.code_bucket[0].bucket_arn : null
}

output "code_object_key" {
  description = "The S3 key of the initial bootstrap package, or null if not created."
  value       = local.create_code_bucket ? aws_s3_object.bootstrap_package[0].key : null
}

################################################################################
# ECR
################################################################################

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository, or null if disabled."
  value       = var.ecr_repository_creation_enabled ? module.ecr[0].repository_arn : null
}

output "ecr_repository_name" {
  description = "The name of the ECR repository, or null if disabled."
  value       = var.ecr_repository_creation_enabled ? module.ecr[0].repository_name : null
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository, or null if disabled."
  value       = var.ecr_repository_creation_enabled ? module.ecr[0].repository_url : null
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

output "cloudwatch_alarm_arns" {
  description = "Lambda error-rate alarm ARNs keyed by AWS Region."
  value       = { for region, alarm in aws_cloudwatch_metric_alarm.error_rate : region => alarm.arn }
}
