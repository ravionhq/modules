locals {
  # Placeholders reserve capacity where it is needed: the default Karpenter
  # node pool, which Karpenter grows for them, and its On-Demand capacity when
  # it has any, since rollouts surge On-Demand baselines and executor Jobs land
  # there. An explicit node_selector, {} included, replaces this.
  warm_capacity_default_node_selector = var.karpenter_enabled && var.karpenter_default_node_pool_creation_enabled ? merge(
    { "karpenter.sh/nodepool" = "default" },
    contains(var.karpenter_default_node_pool.capacity_types, "on-demand") ? { "karpenter.sh/capacity-type" = "on-demand" } : {},
  ) : {}
  warm_capacity_node_selector = var.ravion_operator_warm_capacity.placement.node_selector != null ? var.ravion_operator_warm_capacity.placement.node_selector : local.warm_capacity_default_node_selector
}

resource "helm_release" "ravion_operator_warm_capacity" {
  count = var.ravion_operator_warm_capacity.enabled ? 1 : 0

  name      = "ravion-warm-capacity"
  namespace = var.ravion_operator_namespace
  chart     = "${path.module}/charts/warm-capacity"
  # Pinned so a Chart.yaml bump shows in the plan (see lb_controller.tf).
  version = yamldecode(file("${path.module}/charts/warm-capacity/Chart.yaml")).version

  upgrade_install = true

  values = [
    yamlencode({
      enabled  = true
      replicas = var.ravion_operator_warm_capacity.replicas
      resources = {
        requests = {
          cpu                 = var.ravion_operator_warm_capacity.requests.cpu
          memory              = var.ravion_operator_warm_capacity.requests.memory
          "ephemeral-storage" = var.ravion_operator_warm_capacity.requests.ephemeral_storage
        }
      }
      nodeSelector = local.warm_capacity_node_selector
      tolerations  = var.ravion_operator_warm_capacity.placement.tolerations
      topologySpread = {
        enabled           = var.ravion_operator_warm_capacity.placement.topology_spread_enabled
        maxSkew           = var.ravion_operator_warm_capacity.placement.topology_spread_max_skew
        topologyKey       = var.ravion_operator_warm_capacity.placement.topology_spread_key
        whenUnsatisfiable = var.ravion_operator_warm_capacity.placement.topology_spread_when_unsatisfiable
      }
    }),
  ]

  depends_on = [helm_release.ravion_operator]

  lifecycle {
    precondition {
      condition     = var.ravion_operator_enabled && var.ravion_operator_execution_jobs_enabled
      error_message = "Warm capacity requires Ravion Operator executor Jobs."
    }
  }
}
