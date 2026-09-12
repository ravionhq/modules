################################################################################
# Fargate Profile
################################################################################

resource "aws_eks_fargate_profile" "this" {
  cluster_name           = var.cluster_name
  fargate_profile_name   = var.name
  pod_execution_role_arn = local.role_arn
  subnet_ids             = var.subnet_ids

  dynamic "selector" {
    for_each = var.selectors
    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-${var.name}"
  })
}
