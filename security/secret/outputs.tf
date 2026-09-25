################################################################################
# Outputs
#
# Only handles to the stored value are exported. The value itself is never an
# output and never in state.
################################################################################

output "arn" {
  description = "ARN of the SSM parameter or Secrets Manager secret. Use it as valueFrom in ECS task secrets."
  value       = local.use_parameter_store ? aws_ssm_parameter.this[0].arn : aws_secretsmanager_secret.this[0].arn
}

output "name" {
  description = "Name of the SSM parameter or Secrets Manager secret."
  value       = local.use_parameter_store ? aws_ssm_parameter.this[0].name : aws_secretsmanager_secret.this[0].name
}

output "store" {
  description = "Where the value is stored: parameter_store or secrets_manager."
  value       = var.store
}

output "rotation_version" {
  description = "Version of the value currently stored."
  value       = var.rotation_version
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
