################################################################################
# Node IAM Role
#
# Created only when var.node_role_arn is null. Includes worker, CNI, and image
# pull permissions. Node administration policies must be explicitly supplied
# through node_role_additional_managed_policy_arns.
################################################################################

module "node_role" {
  count = local.create_node_role ? 1 : 0

  source = "../../../../security/iam"

  name        = "${var.cluster_name}-${var.name}-node"
  description = "EKS managed node group instance role for ${var.cluster_name}/${var.name}"

  trusted_services = ["ec2.amazonaws.com"]

  managed_policy_arns = concat(
    [
      "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
      "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    ],
    var.node_role_additional_managed_policy_arns,
  )

  inline_policy_statements = var.node_role_additional_inline_policy_statements

  tags = local.tags
}
