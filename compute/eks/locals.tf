locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks"
  }

  tags = merge(local.default_tags, var.tags)

  node_subnet_ids = coalesce(var.node_subnet_ids, var.subnet_ids)

  # Ravion creates a fresh IAM role for every EC2 pipeline run, named
  # rvn-ci-ec2-role-<slug> or rvn-ci-ec2-spot-role-<slug> under the /rvn-ci/
  # path. Those runs are the only callers that should assume the cluster-admin
  # Ravion Runner role, so the trust policy admits just that pattern unless the
  # caller supplies its own list.
  ravion_runner_role_trusted_principal_arns = (
    length(var.ravion_runner_role_trusted_principal_arns) > 0
    ? var.ravion_runner_role_trusted_principal_arns
    : ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/rvn-ci/rvn-ci-*"]
  )

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
