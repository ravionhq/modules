################################################################################
# Deployment-kind EKS Add-ons
#
# coredns runs as a Deployment whose pods need schedulable compute. Apply this
# module only after at least one node group or Fargate profile exists —
# otherwise the add-on stays DEGRADED and the apply times out.
#
# Optional add-ons (EBS CSI, CloudWatch Observability, ...) live in the
# compute/eks/addons stack.
################################################################################

resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.coredns_addon_version
  configuration_values        = var.coredns_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}
