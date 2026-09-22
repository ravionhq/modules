################################################################################
# Managed Node Group
#
# Preserve the live autoscaler-owned desired size, clamping only when it falls
# outside the requested bounds. Ignoring desired_size would send an invalid
# scaling_config when min_size rises above it or max_size drops below it.
################################################################################

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = var.name
  node_role_arn   = local.node_role_arn

  subnet_ids     = var.subnet_ids
  capacity_type  = var.capacity_type
  instance_types = var.instance_types
  ami_type       = var.ami_type
  version        = var.kubernetes_version

  # disk_size is only valid when no launch template is supplied.
  disk_size = local.create_launch_template ? null : var.disk_size

  scaling_config {
    min_size     = var.min_size
    desired_size = min(var.max_size, max(var.min_size, local.current_desired_size))
    max_size     = var.max_size
  }

  update_config {
    max_unavailable            = var.max_unavailable
    max_unavailable_percentage = var.max_unavailable == null ? var.max_unavailable_percentage : null
  }

  force_update_version = var.version_force_update_enabled

  dynamic "launch_template" {
    for_each = local.create_launch_template ? [1] : []
    content {
      id      = aws_launch_template.this[0].id
      version = aws_launch_template.this[0].latest_version
    }
  }

  labels = var.labels

  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.tags, {
    Name                                        = "${var.cluster_name}-${var.name}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle {
    precondition {
      condition     = var.min_size <= var.max_size
      error_message = "min_size must not exceed max_size."
    }
  }
}
