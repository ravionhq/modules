################################################################################
# Add-on placement
#
# The controllers and stores this module installs (load balancer controller,
# External Secrets, KEDA, kube-state-metrics, the collectors, Loki,
# Prometheus, Thanos, Tempo, Grafana and Ravion Operator) are what the cluster
# needs to recover from anything, so a single Spot reclaim must never take them
# all down at once. Each gets the same rules:
#
#   1. REQUIRED: On-Demand capacity. A managed node group reports its capacity
#      type in eks.amazonaws.com/capacityType, a Karpenter node in
#      karpenter.sh/capacity-type; the two terms are ORed.
#   2. PREFERRED: the system node group (var.system_node_labels). When it is
#      full the scheduler falls back to On-Demand Karpenter capacity instead
#      of leaving the pod Pending, so a small default group never blocks an
#      install.
#   3. A CriticalAddonsOnly toleration, so the add-ons still reach a system
#      group reserved with that taint.
#
# Values are delivered as their own document ahead of each release's caller
# Helm values, so a caller document can still replace any of it.
################################################################################

locals {
  addon_on_demand_terms = [
    { matchExpressions = [{ key = "eks.amazonaws.com/capacityType", operator = "In", values = ["ON_DEMAND"] }] },
    { matchExpressions = [{ key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] }] },
  ]

  addon_affinity = {
    nodeAffinity = merge(
      {
        requiredDuringSchedulingIgnoredDuringExecution = {
          nodeSelectorTerms = local.addon_on_demand_terms
        }
      },
      {
        for key, value in {
          preferredDuringSchedulingIgnoredDuringExecution = [{
            weight = 100
            preference = {
              matchExpressions = [
                for key, value in var.system_node_labels : { key = key, operator = "In", values = [value] }
              ]
            }
          }]
        } : key => value if length(var.system_node_labels) > 0
      },
    )
  }

  addon_tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists" }]

  # Pod-level placement for a chart that takes affinity and tolerations at the
  # path the release nests it under. Callers gate it on addon_placement_enabled.
  addon_pod_placement = {
    affinity    = local.addon_affinity
    tolerations = local.addon_tolerations
  }

  # The same placement as a single top-level values document, for charts that
  # read affinity and tolerations at the root.
  addon_placement_values = var.addon_placement_enabled ? [yamlencode(local.addon_pod_placement)] : []
}
