################################################################################
# System Node Group (required compute for Deployment-kind add-ons)
################################################################################

module "system_node_group" {
  source = "./modules/eks_node_group"

  depends_on = [module.cluster]

  # Resolved at the root so managed policy ARNs stay known at plan time; the
  # module-level depends_on above defers the submodule's own data sources.
  partition = data.aws_partition.current.partition

  cluster_name = module.cluster.cluster_name
  name         = var.system_node_group.name
  subnet_ids   = local.node_subnet_ids

  capacity_type      = var.system_node_group.capacity_type
  instance_types     = var.system_node_group.instance_types
  ami_type           = var.system_node_group.ami_type
  kubernetes_version = var.system_node_group.kubernetes_version

  min_size     = var.system_node_group.min_size
  desired_size = var.system_node_group.min_size
  max_size     = var.system_node_group.max_size

  max_unavailable              = var.system_node_group.max_unavailable
  max_unavailable_percentage   = var.system_node_group.max_unavailable_percentage
  version_force_update_enabled = var.system_node_group.version_force_update_enabled

  labels = var.system_node_group.labels
  taints = var.system_node_group.taints

  disk_size       = var.system_node_group.disk_size
  disk_type       = var.system_node_group.disk_type
  disk_iops       = var.system_node_group.disk_iops
  disk_throughput = var.system_node_group.disk_throughput
  ebs_kms_key_arn = var.system_node_group.ebs_kms_key_arn

  user_data                            = var.system_node_group.user_data
  security_group_ids                   = var.system_node_group.security_group_ids
  detailed_monitoring_enabled          = var.system_node_group.detailed_monitoring_enabled
  metadata_http_tokens                 = var.system_node_group.metadata_http_tokens
  metadata_http_put_response_hop_limit = var.system_node_group.metadata_http_put_response_hop_limit

  node_role_arn                                 = var.system_node_group.node_role_arn
  node_role_additional_managed_policy_arns      = var.system_node_group.node_role_additional_managed_policy_arns
  node_role_additional_inline_policy_statements = var.system_node_group.node_role_additional_inline_policy_statements

  tags = local.tags
}

################################################################################
# Additional Node Groups
################################################################################

module "node_groups" {
  source   = "./modules/eks_node_group"
  for_each = var.node_groups

  depends_on = [module.cluster]

  partition = data.aws_partition.current.partition

  cluster_name = module.cluster.cluster_name
  name         = each.key
  subnet_ids   = coalesce(each.value.subnet_ids, local.node_subnet_ids)

  capacity_type      = each.value.capacity_type
  instance_types     = each.value.instance_types
  ami_type           = each.value.ami_type
  kubernetes_version = each.value.kubernetes_version

  min_size     = each.value.min_size
  desired_size = each.value.min_size
  max_size     = each.value.max_size

  max_unavailable              = each.value.max_unavailable
  max_unavailable_percentage   = each.value.max_unavailable_percentage
  version_force_update_enabled = each.value.version_force_update_enabled

  labels = each.value.labels
  taints = each.value.taints

  disk_size       = each.value.disk_size
  disk_type       = each.value.disk_type
  disk_iops       = each.value.disk_iops
  disk_throughput = each.value.disk_throughput
  ebs_kms_key_arn = each.value.ebs_kms_key_arn

  user_data                            = each.value.user_data
  security_group_ids                   = each.value.security_group_ids
  detailed_monitoring_enabled          = each.value.detailed_monitoring_enabled
  metadata_http_tokens                 = each.value.metadata_http_tokens
  metadata_http_put_response_hop_limit = each.value.metadata_http_put_response_hop_limit

  node_role_arn                                 = each.value.node_role_arn
  node_role_additional_managed_policy_arns      = each.value.node_role_additional_managed_policy_arns
  node_role_additional_inline_policy_statements = each.value.node_role_additional_inline_policy_statements

  tags = local.tags
}
