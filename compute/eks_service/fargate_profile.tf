################################################################################
# Fargate Profile (optional)
################################################################################

module "fargate_profile" {
  count = var.fargate_profile != null ? 1 : 0

  source = "../eks/modules/eks_fargate_profile"

  cluster_name = var.cluster_name
  name         = try(var.fargate_profile.name, null)
  subnet_ids   = try(var.fargate_profile.subnet_ids, null)
  selectors    = try(var.fargate_profile.selectors, null)

  tags = var.tags
}
