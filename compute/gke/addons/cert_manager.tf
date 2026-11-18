resource "helm_release" "cert_manager" {
  count = var.cert_manager_enabled ? 1 : 0

  name       = "cert-manager"
  namespace  = var.cert_manager_namespace
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version

  create_namespace = true
  upgrade_install  = true
  wait             = true

  values = concat(
    [yamlencode({
      # Keep the CRDs on uninstall: deleting them would delete every
      # Certificate and Issuer in the cluster, and the Secrets they own.
      crds = { enabled = true, keep = true }
    })],
    var.addon_placement_enabled ? [yamlencode(merge(local.addon_pod_placement, {
      webhook         = local.addon_pod_placement
      cainjector      = local.addon_pod_placement
      startupapicheck = local.addon_pod_placement
    }))] : [],
    var.cert_manager_helm_values,
  )
}
