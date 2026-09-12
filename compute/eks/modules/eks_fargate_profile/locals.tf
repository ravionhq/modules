locals {
  region    = data.aws_region.current.region
  partition = var.partition != null ? var.partition : data.aws_partition.current.partition
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks/modules/eks_fargate_profile"
  }

  tags = merge(local.default_tags, var.tags)

  provided_role_arn            = var.pod_execution_role_arn == null ? "" : trimspace(var.pod_execution_role_arn)
  create_role                  = local.provided_role_arn == ""
  pod_execution_role_name_base = "${var.cluster_name}-${var.name}-fargate"
  pod_execution_role_name = length(local.pod_execution_role_name_base) <= 64 ? local.pod_execution_role_name_base : format(
    "%s-%s",
    substr(local.pod_execution_role_name_base, 0, 55),
    substr(sha1(local.pod_execution_role_name_base), 0, 8),
  )
  role_arn = local.create_role ? module.pod_execution_role[0].role_arn : local.provided_role_arn
}
