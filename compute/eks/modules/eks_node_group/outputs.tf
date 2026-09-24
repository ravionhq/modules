################################################################################
# Node Group
################################################################################

output "node_group_arn" {
  description = "ARN of the managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_group_id" {
  description = "Composite ID of the managed node group ('cluster_name:node_group_name')."
  value       = aws_eks_node_group.this.id
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_status" {
  description = "Status of the managed node group (ACTIVE, CREATING, etc.)."
  value       = aws_eks_node_group.this.status
}

output "node_group_resources" {
  description = "Underlying resources (autoscaling groups, remote access SG) created by EKS for this node group."
  value       = aws_eks_node_group.this.resources
}

################################################################################
# IAM
################################################################################

output "node_role_arn" {
  description = "ARN of the IAM role used by the nodes."
  value       = local.node_role_arn
}

output "node_role_name" {
  description = "Name of the IAM role used by the nodes (null when a pre-existing role was supplied via var.node_role_arn)."
  value       = local.create_node_role ? module.node_role[0].role_name : null
}

################################################################################
# Launch Template
################################################################################

output "launch_template_id" {
  description = "ID of the launch template used by the node group (null when EKS-default)."
  value       = local.create_launch_template ? aws_launch_template.this[0].id : null
}

output "launch_template_arn" {
  description = "ARN of the launch template used by the node group (null when EKS-default)."
  value       = local.create_launch_template ? aws_launch_template.this[0].arn : null
}

output "launch_template_latest_version" {
  description = "Latest version number of the launch template (null when EKS-default)."
  value       = local.create_launch_template ? aws_launch_template.this[0].latest_version : null
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the node group is deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the node group is deployed."
  value       = local.region
}
