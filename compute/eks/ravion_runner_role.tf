################################################################################
# Ravion Runner Role
#
# Stable IAM role that Ravion Runner step executions assume to authenticate
# against this cluster's Kubernetes API (e.g. the Helm steps of the
# compute/eks/addons stack). The role holds a permanent EKS access entry with
# cluster-admin, so ephemeral per-run runner roles never need their own access
# entries — they assume this role for `aws eks get-token` and nothing else.
#
# Trust defaults to the cluster's own AWS account, which still requires the
# caller to hold sts:AssumeRole on this role's ARN — Ravion grants that to
# step executions configured to assume it. Tighten the trust further with
# ravion_runner_role_trusted_principal_arns.
################################################################################

data "aws_caller_identity" "current" {}

module "ravion_runner_role" {
  count = var.ravion_runner_role_creation_enabled ? 1 : 0

  source = "../../security/iam"

  name        = "${var.name}-ravion-runner"
  description = "Assumed by Ravion Runner step executions for Kubernetes API access to the ${var.name} EKS cluster"

  trusted_aws_principals = [data.aws_caller_identity.current.account_id]

  assume_role_conditions = length(var.ravion_runner_role_trusted_principal_arns) == 0 ? [] : [{
    test     = "ArnLike"
    variable = "aws:PrincipalArn"
    values   = var.ravion_runner_role_trusted_principal_arns
  }]

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
