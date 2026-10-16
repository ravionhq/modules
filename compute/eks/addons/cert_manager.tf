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
      # Certificates must keep renewing when the Spot application pool is
      # empty or interrupted: On-Demand even with add-on placement off.
      affinity        = local.addon_affinity
      webhook         = { affinity = local.addon_affinity }
      cainjector      = { affinity = local.addon_affinity }
      startupapicheck = { affinity = local.addon_affinity }
    })],
    var.addon_placement_enabled ? [yamlencode({
      tolerations     = local.addon_tolerations
      webhook         = { tolerations = local.addon_tolerations }
      cainjector      = { tolerations = local.addon_tolerations }
      startupapicheck = { tolerations = local.addon_tolerations }
    })] : [],
    local.cert_manager_resilience_values,
    var.cert_manager_helm_values,
  )

  depends_on = [helm_release.lb_controller]
}
