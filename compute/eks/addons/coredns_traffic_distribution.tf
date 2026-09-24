################################################################################
# kube-dns zone-local routing
#
# The compute/eks composite spreads CoreDNS across availability zones through
# the coredns add-on configuration; this is the Service half of the same
# feature. The add-on schema has no Service-level keys and this stack has no
# Kubernetes provider, so a local chart runs a kubectl Job as a Helm hook that
# patches spec.trafficDistribution onto kube-dns. The release's pre-delete hook
# clears the field again, so turning the flag off (which destroys the release)
# restores the stock behavior rather than leaving the patch behind.
################################################################################

resource "helm_release" "coredns_traffic_distribution" {
  count = var.topology_aware_routing_enabled ? 1 : 0

  name            = "coredns-traffic-distribution"
  namespace       = "kube-system"
  chart           = "${path.module}/charts/coredns-traffic-distribution"
  upgrade_install = true

  values = [yamlencode({
    trafficDistribution = "PreferClose"
    image = {
      repository = local.kubectl_image_repository
      tag        = local.kubectl_image_tag
    }
  })]
}

locals {
  # "repo:tag" split for the chart; the digest form is not supported because
  # the chart joins the two with ":".
  kubectl_image_repository = regex("^(.*):([^:/]+)$", var.kubectl_image)[0]
  kubectl_image_tag        = regex("^(.*):([^:/]+)$", var.kubectl_image)[1]
}
