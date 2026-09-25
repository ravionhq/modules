resource "helm_release" "ravion_operator_warm_capacity" {
  count = var.ravion_operator_warm_capacity.enabled ? 1 : 0

  name      = "ravion-warm-capacity"
  namespace = var.ravion_operator_namespace
  chart     = "${path.module}/charts/warm-capacity"

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
      nodeSelector = var.ravion_operator_warm_capacity.placement.node_selector
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
