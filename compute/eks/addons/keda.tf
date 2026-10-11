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
    [yamlencode({
      crds = { install = true }
      # Keep the scaler available when the Spot application pool is empty or
      # interrupted: On-Demand even with add-on placement off.
      affinity = local.addon_affinity
    })],
    var.addon_placement_enabled ? [yamlencode({ tolerations = local.addon_tolerations })] : [],
    var.keda_helm_values,
  )

  depends_on = [helm_release.lb_controller]
}
