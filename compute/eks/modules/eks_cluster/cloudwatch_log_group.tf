################################################################################
# Control Plane Log Group
#
# EKS expects this exact log group name when control-plane logging is enabled.
# Pre-creating it lets us own retention and tags rather than letting EKS create
# it implicitly.
################################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  count = local.enable_logging ? 1 : 0

  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.cluster_log_retention_in_days

  tags = local.tags
}
