################################################################################
# Ravion Runner Role
#
# Stable cluster-admin identity, retaining the existing Runner role and EKS
# access-entry addresses. Only the account integration role may assume it,
# from approved control-plane egress, including when propagating SourceIdentity.
# Legacy ephemeral runner credentials cannot assume this role directly.
################################################################################

data "aws_caller_identity" "current" {}

module "ravion_runner_role" {
  count = var.ravion_runner_role_creation_enabled ? 1 : 0

  source = "../../security/iam"

  name        = "${var.name}-ravion-runner"
  description = "Assumed by the Ravion integration role for admin Kubernetes API access to the ${var.name} EKS cluster"

  # Keep this EKS-specific; other users of security/iam retain their own trust.
  custom_assume_role_policy = local.ravion_access_assume_role_policy

  # `aws eks get-token` needs no IAM permissions; DescribeCluster covers
  # tooling that fetches the endpoint and CA under the assumed role.
  inline_policy_statements = [{
    sid       = "DescribeThisCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [module.cluster.cluster_arn]
  }]

  tags = local.tags
}

resource "aws_eks_access_entry" "ravion_runner" {
  count = var.ravion_runner_role_creation_enabled ? 1 : 0

  cluster_name  = module.cluster.cluster_name
  principal_arn = module.ravion_runner_role[0].role_arn
  type          = "STANDARD"

  tags = local.tags
}

resource "aws_eks_access_policy_association" "ravion_runner_admin" {
  count = var.ravion_runner_role_creation_enabled ? 1 : 0

  cluster_name  = module.cluster.cluster_name
  principal_arn = aws_eks_access_entry.ravion_runner[0].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
