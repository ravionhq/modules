################################################################################
# Karpenter Node Role
#
# IAM role that Karpenter assigns to every node it launches. The associated
# instance profile is referenced by Karpenter's EC2NodeClass spec
# (`instanceProfile` field) — its name is exposed via the
# `node_instance_profile_name` output.
#
# AmazonEC2ContainerRegistryPullOnly is the right ECR policy for nodes (matches
# the upstream Karpenter CFN). Node administration policies must be explicitly
# supplied through node_role_additional_managed_policy_arns.
################################################################################

module "node_role" {
  source = "../../../../../security/iam"

  name        = "${var.cluster_name}-karpenter-node"
  description = "Karpenter-launched node IAM role for ${var.cluster_name}"

  trusted_services = ["ec2.amazonaws.com"]

  managed_policy_arns = concat(
    [
      "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
      "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    ],
    var.node_role_additional_managed_policy_arns,
  )

  instance_profile_creation_enabled = true
  instance_profile_name             = "${var.cluster_name}-karpenter-node"

  tags = local.tags
}
