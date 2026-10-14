################################################################################
# Metrics Server — EKS community add-on
#
# It serves metrics.k8s.io for HPAs and kubectl top, independently of the
# observability collectors in compute/eks/addons. Like CoreDNS, its pods need
# schedulable compute before the EKS API installs the add-on. The EKS-managed
# distribution uses port 10251 for its server, avoiding the Fargate 10250
# conflict. Its kubelet scrape traffic still uses port 10250.
################################################################################

resource "aws_eks_addon" "metrics_server" {
  count = var.metrics_server_enabled ? 1 : 0

  cluster_name         = var.cluster_name
  addon_name           = "metrics-server"
  addon_version        = var.metrics_server_addon_version
  configuration_values = var.metrics_server_addon_configuration_values

  # Refuse to silently adopt Kubernetes resources installed by a separate
  # Helm release. Remove that release before enabling the EKS add-on.
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}
