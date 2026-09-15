################################################################################
# Fargate Pod Execution Role
#
# Trusted by eks-fargate-pods.amazonaws.com. Distinct from the per-pod task
# role (which IRSA / Pod Identity hands out); this role lets the Fargate
# infrastructure pull container images and write logs on the pod's behalf.
################################################################################

module "pod_execution_role" {
  count = local.create_role ? 1 : 0

  source = "../../../../security/iam"

  name        = local.pod_execution_role_name
  description = "EKS Fargate pod execution role for ${var.cluster_name}/${var.name}"

  trusted_services = ["eks-fargate-pods.amazonaws.com"]

  managed_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy",
  ]

  tags = local.tags
}
