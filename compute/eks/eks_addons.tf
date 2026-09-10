################################################################################
# Post-compute Add-ons (CoreDNS)
#
# Must run after the system node group exists — Deployment-kind add-ons deadlock
# without schedulable compute. Optional add-ons (EBS CSI, Container Insights,
# Karpenter) live in the compute/eks/addons stack.
################################################################################

module "addons" {
  source = "./modules/eks_addons"

  depends_on = [module.system_node_group]

  cluster_name = module.cluster.cluster_name

  coredns_addon_version              = var.coredns_addon_version
  coredns_addon_configuration_values = local.coredns_addon_configuration_values

  tags = local.tags
}
