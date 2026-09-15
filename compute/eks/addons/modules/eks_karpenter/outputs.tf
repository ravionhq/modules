################################################################################
# Controller
################################################################################

output "controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role (Pod Identity)."
  value       = module.controller_role.role_arn
}

output "controller_role_name" {
  description = "Name of the Karpenter controller IAM role."
  value       = module.controller_role.role_name
}

################################################################################
# Node Role
################################################################################

output "node_role_arn" {
  description = "ARN of the IAM role attached to Karpenter-launched nodes."
  value       = module.node_role.role_arn
}

output "node_role_name" {
  description = "Name of the IAM role attached to Karpenter-launched nodes. Reference this in your EC2NodeClass spec."
  value       = module.node_role.role_name
}

output "node_instance_profile_name" {
  description = "Instance profile name to set on Karpenter EC2NodeClass.spec.instanceProfile."
  value       = module.node_role.instance_profile_name
}

output "node_instance_profile_arn" {
  description = "Instance profile ARN for Karpenter-launched nodes."
  value       = module.node_role.instance_profile_arn
}

################################################################################
# Interruption Queue
################################################################################

output "interruption_queue_name" {
  description = "Name of the SQS interruption queue. Pass this to Karpenter Helm chart `settings.interruptionQueue`."
  value       = aws_sqs_queue.interruption.name
}

output "interruption_queue_arn" {
  description = "ARN of the SQS interruption queue."
  value       = aws_sqs_queue.interruption.arn
}

output "interruption_queue_url" {
  description = "URL of the SQS interruption queue."
  value       = aws_sqs_queue.interruption.url
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where Karpenter resources are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where Karpenter resources are deployed."
  value       = local.region
}
