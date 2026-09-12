################################################################################
# Fargate Profile
################################################################################

output "fargate_profile_arn" {
  description = "ARN of the Fargate profile."
  value       = aws_eks_fargate_profile.this.arn
}

output "fargate_profile_id" {
  description = "Composite ID of the Fargate profile ('cluster_name:profile_name')."
  value       = aws_eks_fargate_profile.this.id
}

output "fargate_profile_name" {
  description = "Name of the Fargate profile."
  value       = aws_eks_fargate_profile.this.fargate_profile_name
}

output "fargate_profile_status" {
  description = "Status of the Fargate profile."
  value       = aws_eks_fargate_profile.this.status
}

################################################################################
# IAM
################################################################################

output "pod_execution_role_arn" {
  description = "ARN of the pod execution role used by Fargate."
  value       = local.role_arn
}

output "pod_execution_role_name" {
  description = "Name of the pod execution role (null when a pre-existing role was supplied via var.pod_execution_role_arn)."
  value       = local.create_role ? module.pod_execution_role[0].role_name : null
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the profile is deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the profile is deployed."
  value       = local.region
}
