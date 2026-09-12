locals {
  ravion_operator_required_namespaces = sort(distinct(concat(
    var.ravion_operator_namespace_scope,
    var.ravion_operator_deploy_enabled ? local.ravion_operator_deploy_namespaces_effective : [],
  )))
}

# Keep workload namespaces separate from the agent and its release namespace.
# The chart reuses externally managed namespaces and retains those it creates
# when the namespace list shrinks or this release is uninstalled.
resource "helm_release" "ravion_operator_namespaces" {
  count = var.ravion_operator_enabled && var.ravion_operator_namespaces_creation_enabled && length(local.ravion_operator_required_namespaces) > 0 ? 1 : 0

  name            = "ravion-operator-namespaces"
  namespace       = "kube-system"
  chart           = "${path.module}/charts/ravion-operator-namespaces"
  upgrade_install = true

  values = [yamlencode({
    namespaces = local.ravion_operator_required_namespaces
  })]

  # If the agent's own namespace is also in the scope, let its credential
  # release create it first rather than racing two namespace creators.
  depends_on = [helm_release.ravion_operator_credential]
}
