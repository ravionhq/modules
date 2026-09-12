################################################################################
# DaemonSet-kind EKS Add-ons
#
# Only DaemonSet-kind add-ons live here (vpc-cni, kube-proxy, and optionally
# eks-pod-identity-agent). They schedule on nodes as they join and do not block
# cluster create when no compute exists yet.
#
# Deployment-kind add-ons (coredns, aws-ebs-csi-driver) live in
# modules/eks_addons and MUST be applied after at least one node group or
# Fargate profile exists — otherwise their pods never schedule and the add-ons
# time out DEGRADED.
################################################################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_addon_version
  configuration_values        = var.vpc_cni_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_addon_version
  configuration_values        = var.kube_proxy_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

################################################################################
# Pod Identity Agent
#
# Required on the data plane for any aws_eks_pod_identity_association to take
# effect. Defaults on because the helpers this module ships (LB Controller)
# use Pod Identity.
################################################################################

resource "aws_eks_addon" "pod_identity_agent" {
  count = var.pod_identity_agent_enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = var.pod_identity_agent_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}
