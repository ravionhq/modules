locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks"
  }

  tags = merge(local.default_tags, var.tags)

  node_subnet_ids = coalesce(var.node_subnet_ids, var.subnet_ids)

  # CoreDNS answers every in-cluster lookup, so a replica in each zone is what
  # lets the kube-dns Service (patched by compute/eks/addons) keep DNS traffic
  # zone-local. ScheduleAnyway rather than DoNotSchedule: a two-node cluster
  # or a Spot interruption must never leave DNS pending. An explicit
  # configuration document wins untouched.
  coredns_zone_spread_configuration_values = jsonencode({
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "topology.kubernetes.io/zone"
      whenUnsatisfiable = "ScheduleAnyway"
      labelSelector = {
        matchLabels = { "k8s-app" = "kube-dns" }
      }
    }]
  })

  coredns_addon_configuration_values = (
    var.coredns_addon_configuration_values != null
    ? var.coredns_addon_configuration_values
    : (var.topology_aware_routing_enabled ? local.coredns_zone_spread_configuration_values : null)
  )
}
