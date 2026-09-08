################################################################################
# In-cluster Prometheus — the metrics store that is not AWS's
#
# `prometheus` in metrics_providers installs Prometheus in the cluster with its
# remote-write receiver on, and the metrics collector writes to it exactly the
# way it writes to AMP. It is a rendering provider: Ravion queries it through
# the EKS service proxy over SSM, like in-cluster Loki, so it has no ingress
# and no route out of the cluster.
#
# Three things about the shape of this file:
#
#   1. IT DOES NOT SCRAPE. Every scrape in this module belongs to the one
#      collector (otel_collector.tf), which keeps the curated allow-list and the
#      label contract in one place; this Prometheus is a write-only sink with a
#      query API. That is why every scrape job, the node exporter, and the
#      chart's own kube-state-metrics are off.
#
#   2. IT NEEDS A STORAGE CLASS. Retention only means something with a volume
#      behind it, so the server's PersistentVolumeClaim is on — which on a
#      Ravion cluster means ebs_csi_driver_enabled. An unschedulable PVC is a
#      loud failure rather than a quiet one, which is the right trade for a
#      store whose whole job is to still have yesterday's data.
#
#   3. metrics_prometheus.endpoint SKIPS THE INSTALL. A cluster that already
#      runs Prometheus points at it instead, and the module only remote-writes
#      and publishes the endpoint.
#
# CHART VALUES — VERIFY ON UPGRADE. prometheus-community/prometheus is pinned by
# prometheus_chart_version. The keys used below (server.extraFlags,
# server.retention, server.persistentVolume, server.service.servicePort, and the
# alertmanager / pushgateway / exporter subchart toggles) are the ones that
# chart has carried for several majors, but a chart bump is a values review.
################################################################################

resource "helm_release" "prometheus" {
  count = local.prometheus_install ? 1 : 0

  name       = local.prometheus_release_name
  namespace  = local.observability_namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = var.prometheus_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        # Pins the Service name the collector and read-only API proxy use.
        fullnameOverride = local.prometheus_release_name

        server = {
          # The receiver is off by default, and without it every remote write
          # from the collector is a 404.
          extraFlags = [
            "web.enable-lifecycle",
            "web.enable-remote-write-receiver",
          ]

          retention = "${local.prometheus_config.retention_days}d"

          persistentVolume = {
            enabled = true
            size    = local.prometheus_config.storage_size
          }

          service = {
            servicePort = 9090
          }

          # No ingress: external reads use the EKS service proxy over SSM.
          ingress = {
            enabled = false
          }
        }

        # A write-only sink. Every scrape belongs to the collector, which owns
        # the allow-list and the label contract.
        serverFiles = {
          "prometheus.yml" = {
            scrape_configs = []
          }
        }

        # Alerting, the pushgateway, and a second copy of the exporters this
        # module already runs — none of which a remote-write sink needs.
        alertmanager               = { enabled = false }
        "prometheus-pushgateway"   = { enabled = false }
        "prometheus-node-exporter" = { enabled = false }
        "kube-state-metrics"       = { enabled = false }
      }),
    ],
    var.prometheus_helm_values,
  )
}
