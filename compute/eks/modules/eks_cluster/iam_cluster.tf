################################################################################
# Cluster Service Role
################################################################################

module "cluster_role" {
  source = "../../../../security/iam"

  name             = "${var.name}-cluster"
  description      = "EKS cluster service role for ${var.name}"
  trusted_services = ["eks.amazonaws.com"]

  managed_policy_arns = concat(
    ["arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"],
    var.vpc_resource_controller_policy_enabled ? [
      "arn:${local.partition}:iam::aws:policy/AmazonEKSVPCResourceController",
    ] : [],
  )

  tags = local.tags
}
