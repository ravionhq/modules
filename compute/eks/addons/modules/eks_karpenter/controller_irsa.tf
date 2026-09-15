################################################################################
# Karpenter Controller Pod Identity Role
#
# Trusted by pods.eks.amazonaws.com (not the cluster's OIDC provider). The
# eks-pod-identity-agent on the cluster delivers credentials at runtime;
# enable that add-on in the eks_cluster module (default on).
################################################################################

module "controller_role" {
  source = "../../../../../security/iam"

  name        = "${var.cluster_name}-karpenter"
  description = "Karpenter controller Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "node-lifecycle"     = data.aws_iam_policy_document.node_lifecycle.json
    "iam-integration"    = data.aws_iam_policy_document.iam_integration.json
    "eks-integration"    = data.aws_iam_policy_document.eks_integration.json
    "interruption"       = data.aws_iam_policy_document.interruption.json
    "zonal-shift"        = data.aws_iam_policy_document.zonal_shift.json
    "resource-discovery" = data.aws_iam_policy_document.resource_discovery.json
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = var.cluster_name
  namespace       = var.controller_namespace
  service_account = var.controller_service_account
  role_arn        = module.controller_role.role_arn

  tags = local.tags
}
