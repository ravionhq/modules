resource "helm_release" "keda" {
  count = var.keda_enabled ? 1 : 0

  name       = "keda"
  namespace  = var.keda_namespace
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_chart_version

  create_namespace = true
  upgrade_install  = true
  wait             = true

  values = concat(
    [yamlencode({ crds = { install = true } })],
    var.addon_placement_enabled ? [yamlencode(local.addon_pod_placement)] : [],
    var.keda_helm_values,
  )
}
