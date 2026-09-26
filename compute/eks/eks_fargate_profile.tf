################################################################################
# Fargate Profiles (optional)
################################################################################

module "fargate_profiles" {
  source   = "./modules/eks_fargate_profile"
  for_each = var.fargate_profiles

  depends_on = [module.addons]

  # Resolved at the root so managed policy ARNs stay known at plan time; the
  # module-level depends_on above defers the submodule's own data sources.
  partition = data.aws_partition.current.partition

  cluster_name = module.cluster.cluster_name
  name         = each.key
  subnet_ids   = try(length(each.value.subnet_ids), 0) > 0 ? each.value.subnet_ids : local.node_subnet_ids
  selectors    = each.value.selectors

  pod_execution_role_arn = each.value.pod_execution_role_arn

  tags = local.tags
}
