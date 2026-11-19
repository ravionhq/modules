################################################################################
# KEDA (Helm)
#
# While the metrics collector runs, KEDA's operator also serves its own
# Prometheus metrics (keda_scaler_metrics_value, keda_scaler_active, scaler and
# ScaledObject errors), which the collector scrapes into every metrics
# destination. Without them a scaling decision cannot be traced to the trigger
# that drove it, and a failing scaler is invisible.
#
# The operator leader-elects and only the leader runs the scale loops, so the
# collector has to reach every replica, not whichever one the chart's ClusterIP
# Service picks. A headless Service, shipped through the chart's own
# extraObjects, gives one DNS record per ready operator pod; the collector
# discovers them by DNS and needs no Kubernetes API access to do it. A caller
# document that sets extraObjects replaces this list and drops the Service.
################################################################################

locals {
  keda_metrics_enabled      = var.keda_enabled && local.otel_metrics_enabled
  keda_metrics_port         = 8080
  keda_metrics_service_name = "keda-operator-prometheus"
  keda_metrics_service_fqdn = "${local.keda_metrics_service_name}.${var.keda_namespace}.svc.cluster.local"

  keda_metrics_values = local.keda_metrics_enabled ? [yamlencode({
    prometheus = {
      operator = {
        enabled = true
        port    = local.keda_metrics_port
      }
    }
    extraObjects = [{
      apiVersion = "v1"
      kind       = "Service"
      metadata = {
        name      = local.keda_metrics_service_name
        namespace = var.keda_namespace
        labels = {
          "app.kubernetes.io/name"     = local.keda_metrics_service_name
          "app.kubernetes.io/instance" = "keda"
        }
      }
      spec = {
        clusterIP = "None"
        # The labels addon_resilience.tf spreads the operator's pods by.
        selector = {
          "app.kubernetes.io/name"     = "keda-operator"
          "app.kubernetes.io/instance" = "keda"
        }
        ports = [{
          name       = "metrics"
          port       = local.keda_metrics_port
          targetPort = local.keda_metrics_port
        }]
      }
    }]
  })] : []
}

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
    local.keda_metrics_values,
    local.keda_resilience_values,
    var.keda_helm_values,
  )

  depends_on = [helm_release.lb_controller]
}
