################################################################################
# Add-on placement
#
# The controllers this module installs are what the cluster needs to recover,
# so a Spot reclaim must never take them all down at once. Each gets:
#
#   1. REQUIRED: a node that is neither Spot nor preemptible. GKE labels those
#      nodes cloud.google.com/gke-spot and cloud.google.com/gke-preemptible;
#      every other node lacks the labels and matches NotIn.
#   2. PREFERRED: the system node pool (var.system_node_labels). When it is
#      full the scheduler falls back to any other On-demand node instead of
#      leaving the pod Pending.
#   3. A CriticalAddonsOnly toleration, so the add-ons still reach a system
#      pool reserved with that taint.
#
# Values are delivered as their own document ahead of each release's caller
# Helm values, so a caller document can still replace any of it.
################################################################################

locals {
  addon_affinity = {
    nodeAffinity = merge(
      {
        requiredDuringSchedulingIgnoredDuringExecution = {
          nodeSelectorTerms = [{
            matchExpressions = [
              { key = "cloud.google.com/gke-spot", operator = "NotIn", values = ["true"] },
              { key = "cloud.google.com/gke-preemptible", operator = "NotIn", values = ["true"] },
            ]
          }]
        }
      },
      length(var.system_node_labels) == 0 ? {} : {
        preferredDuringSchedulingIgnoredDuringExecution = [{
          weight = 100
          preference = {
            matchExpressions = [
              for key, value in var.system_node_labels : { key = key, operator = "In", values = [value] }
            ]
          }
        }]
      },
    )
  }

  addon_tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists" }]

  addon_pod_placement = {
    affinity    = local.addon_affinity
    tolerations = local.addon_tolerations
  }
}
