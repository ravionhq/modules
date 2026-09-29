################################################################################
# Kubernetes Metrics Server (Helm)
#
# Serves metrics.k8s.io to kubectl top and resource-based HPAs. This is not a
# telemetry destination and must remain independent of metrics_providers.
# Only one APIService may own v1beta1.metrics.k8s.io in a cluster, so installing
# alongside an existing Metrics Server must be explicitly disabled.
################################################################################

resource "helm_release" "metrics_server" {
  count = var.metrics_server_enabled ? 1 : 0

  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  # Do not adopt another release named metrics-server: this singleton APIService
  # may already be managed by a different installer. Let Helm fail instead.
  values = var.metrics_server_helm_values

  # When both are installed, wait for the load balancer controller's admission
  # webhook before creating the Metrics Server Service.
  depends_on = [helm_release.lb_controller]
}
