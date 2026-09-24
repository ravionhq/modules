################################################################################
# kube-state-metrics (Helm)
#
# The source of every kube_* series the collector keeps: replica counts, pod
# phase, container restart and termination reasons, HPA state, node conditions.
# cAdvisor knows what a container is *using*; only kube-state-metrics knows what
# the API server was *asked* for, which is the half that answers "is this
# deployment healthy".
#
# Tiny, no CRDs, and a registry.k8s.io image. There is deliberately no
# node-exporter: the node headline numbers come from the kubelet's
# /metrics/resource endpoint instead (see otel_collector.tf), and node capacity
# from kube_node_status_capacity here.
#
# fullnameOverride pins the Service name so the collector's scrape target is a
# constant rather than a function of the chart's fullname template.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  kube_state_metrics_name = "ravion-kube-state-metrics"

  # In-cluster DNS, so the collector never leaves the cluster to scrape it.
  kube_state_metrics_target = "${local.kube_state_metrics_name}.${local.metrics_namespace}.svc.cluster.local:8080"

  kube_state_metrics_install = local.kube_state_metrics_wanted && var.kube_state_metrics_enabled
}

resource "helm_release" "kube_state_metrics" {
  count = local.kube_state_metrics_install ? 1 : 0

  name       = local.kube_state_metrics_name
  namespace  = local.metrics_namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  version    = var.kube_state_metrics_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        fullnameOverride = local.kube_state_metrics_name

        # A single replica: the exporter is a stateless projection of the API
        # server, and a second one would double every kube_* sample without
        # adding a fact.
        replicas = 1

        # Nothing scrapes kube-state-metrics' own process metrics — the
        # allow-list would drop them anyway.
        selfMonitor = {
          enabled = false
        }
      }),
    ],
    var.kube_state_metrics_helm_values,
  )

  # Service creation must wait for the load balancer admission webhook.
  depends_on = [helm_release.lb_controller]
}
