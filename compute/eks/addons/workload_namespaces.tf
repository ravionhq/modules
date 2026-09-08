# Keep the legacy resource address, chart path and release name for state continuity.
# The chart reuses externally managed namespaces and retains those it creates
# when the namespace list shrinks or this release is uninstalled.
resource "helm_release" "ravion_operator_namespaces" {
  count = length(local.ravion_access_namespaces) > 0 ? 1 : 0

  name            = "ravion-operator-namespaces"
  namespace       = "kube-system"
  chart           = "${path.module}/charts/ravion-operator-namespaces"
  upgrade_install = true

  values = [yamlencode({
    namespaces              = var.workload_namespaces_creation_enabled ? local.ravion_access_namespaces : []
    helmInventoryNamespaces = local.ravion_access_namespaces
  })]
}
locals {
  ravion_access_namespaces = sort(distinct(concat(var.workload_namespaces, var.observed_namespaces)))
}
