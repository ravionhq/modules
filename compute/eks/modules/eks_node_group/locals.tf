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
    Module    = "compute/eks/modules/eks_node_group"
  }

  tags = merge(local.default_tags, var.tags)

  create_node_role = var.node_role_arn == null
  node_role_arn    = local.create_node_role ? module.node_role[0].role_arn : var.node_role_arn

  create_launch_template = (
    var.user_data != null
    || var.disk_size != null
    || var.disk_type != null
    || var.disk_iops != null
    || var.disk_throughput != null
    || var.ebs_kms_key_arn != null
    || length(var.security_group_ids) > 0
    || var.detailed_monitoring_enabled
    || var.metadata_http_tokens != "required"
    || var.metadata_http_put_response_hop_limit != 2
  )
}
