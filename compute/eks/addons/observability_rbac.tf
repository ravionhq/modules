# The read role's EKS View policy does not grant services/proxy. Restrict the
# extra GET permission to selected observability services. A separate inventory
# ClusterRole covers nodes/metrics omitted by View; no pod exec, secrets, write
# verbs, or general-purpose proxy grant is added.
resource "helm_release" "observability_access" {
  count = 1

  name             = "ravion-observability-access"
  namespace        = local.observability_namespace
  create_namespace = true
  chart            = "${path.module}/charts/observability-access"
  values = [yamlencode({
    clusterInventoryEnabled = true
    namespaces              = distinct(concat(local.loki_enabled ? [local.logs_namespace] : [], local.prometheus_install ? [local.observability_namespace] : []))
    services = concat(
      local.loki_enabled ? [{ namespace = local.logs_namespace, name = local.loki_release_name, port = "3100" }] : [],
      local.prometheus_install ? [{ namespace = local.observability_namespace, name = "${local.prometheus_release_name}-server", port = "9090" }] : [],
    )
  })]
  depends_on = [helm_release.loki, helm_release.prometheus]
}
