################################################################################
# Ravion Runner Role
#
# Stable cluster-admin identity for customer-side Terraform provisioning and
# legacy Helm runners. Preserve its existing trust: ephemeral runner credentials
# and customer NAT cannot satisfy runtime integration-role/egress restrictions.
# Runtime SSM clients use the separate ravion_access_admin role instead.
################################################################################

data "aws_caller_identity" "current" {}

locals {
  ravion_runner_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [merge({
      Sid    = "TrustAWSPrincipals"
      Effect = "Allow"
      Action = ["sts:AssumeRole", "sts:SetSourceIdentity"]
      Principal = {
        AWS = length(var.ravion_runner_role_trusted_principal_arns) > 0 ? distinct([for arn in var.ravion_runner_role_trusted_principal_arns : "arn:${data.aws_partition.current.partition}:iam::${split(":", arn)[4]}:root"]) : ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
      }
      }, length(var.ravion_runner_role_trusted_principal_arns) == 0 ? {} : {
      Condition = { ArnLike = { "aws:PrincipalArn" = var.ravion_runner_role_trusted_principal_arns } }
    })]
  })
}

module "ravion_runner_role" {
  count = var.ravion_runner_role_creation_enabled ? 1 : 0

  source = "../../security/iam"

  name        = "${var.name}-ravion-runner"
  description = "Assumed by Ravion Runner step executions for Kubernetes API access to the ${var.name} EKS cluster"

  # Keep this EKS-specific; other users of security/iam retain their own trust.
  custom_assume_role_policy = local.ravion_runner_assume_role_policy

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
