################################################################################
# In-cluster Prometheus — the metrics store that is not AWS's
#
# `prometheus` in metrics_providers installs Prometheus in the cluster with its
# remote-write receiver on, and the metrics collector writes to it exactly the
# way it writes to AMP. Thanos ships its blocks to S3 by default (thanos.tf).
# Ravion reads recent and historical metrics from Thanos Query through Operator;
# with S3 off it queries Prometheus directly. Neither has a public endpoint.
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
        # Pins the Prometheus ingestion Service; Thanos has a separate query URL.
        fullnameOverride = local.prometheus_release_name

        server = merge({
          # The receiver is off by default, and without it every remote write
          # from the collector is a 404.
          # The query limits keep one query (KEDA, Grafana and Thanos all fan
          # out to this server) from exhausting its memory.
          extraFlags = concat([
            "web.enable-lifecycle",
            "web.enable-remote-write-receiver",
            "query.max-samples=30000000",
            "query.timeout=2m",
            ], local.thanos_enabled ? [
            "storage.tsdb.min-block-duration=2h",
            "storage.tsdb.max-block-duration=2h",
          ] : [])

          # Keep the existing Deployment/PVC addresses on upgrade. Disabling
          # local compaction above lets Thanos compact uploaded blocks safely.
          sidecarContainers = local.thanos_enabled ? { thanos = local.thanos_sidecar } : {}
          # A replica's own name, expanded by Prometheus from POD_NAME, is what
          # lets Thanos tell two copies of a series apart and merge them.
          global = {
            external_labels = merge(
              { cluster = var.cluster_name },
              local.prometheus_ha ? { prometheus_replica = "$${POD_NAME}" } : {},
            )
          }

          retention = "${local.prometheus_config.retention_days}d"
          # A full volume crashes Prometheus. Delete the oldest blocks first,
          # well before the volume fills.
          retentionSize = local.prometheus_retention_size

          persistentVolume = {
            enabled      = true
            size         = local.prometheus_config.storage_size
            storageClass = local.prometheus_config.storage_class
          }

          service = {
            servicePort = 9090
          }

          # No ingress, ever: the only route in is Ravion Operator's proxy.
          ingress = {
            enabled = false
          }
          }, { for key, value in {
            # Each replica gets its own volume and every sample (see
            # prometheus_remote_write_endpoints), so either can be lost while
            # the other serves. Parallel starts both at once after an outage.
            # Their blocks are in S3, so removing the StatefulSet (with the
            # provider, or back to one replica) deletes the volumes too,
            # instead of leaving them billed. Scaling down keeps them.
            statefulSet  = { enabled = true, podManagementPolicy = "Parallel", pvcDeleteOnStsDelete = true, pvcDeleteOnStsScale = false }
            replicaCount = local.prometheus_replicas
            env = [{
              name      = "POD_NAME"
              valueFrom = { fieldRef = { fieldPath = "metadata.name" } }
            }]
            podDisruptionBudget = { enabled = true, maxUnavailable = 1 }
            # Never two replicas on one node; across zones when the cluster has
            # them, so a zone outage leaves one.
            podAntiAffinity            = "hard"
            podAntiAffinityTopologyKey = "kubernetes.io/hostname"
            topologySpreadConstraints = [{
              maxSkew           = 1
              topologyKey       = "topology.kubernetes.io/zone"
              whenUnsatisfiable = "ScheduleAnyway"
              labelSelector = { matchLabels = {
                "app.kubernetes.io/name"      = "prometheus"
                "app.kubernetes.io/instance"  = local.prometheus_release_name
                "app.kubernetes.io/component" = "server"
              } }
            }]
        } : key => value if local.prometheus_ha })

        serviceAccounts = {
          server = { create = true, name = local.prometheus_service_account }
        }
        rbac = { create = false }

        # A write-only sink. Every scrape belongs to the collector, which owns
        # the allow-list and the label contract.
        serverFiles = {
          "prometheus.yml" = {
            scrape_configs = []
          }
        }
        # Chart 28+ ships its default scrape jobs in the scrapeConfigs map, on by
        # default; null deletes it so the empty scrape_configs above is the whole list.
        scrapeConfigs = null

        # Alerting, the pushgateway, and a second copy of the exporters this
        # module already runs — none of which a remote-write sink needs.
        alertmanager               = { enabled = false }
        "prometheus-pushgateway"   = { enabled = false }
        "prometheus-node-exporter" = { enabled = false }
        "kube-state-metrics"       = { enabled = false }
      }),
    ],
    var.addon_placement_enabled ? [yamlencode({ server = local.addon_store_placement })] : [],
    local.prometheus_resilience_values,
    var.prometheus_helm_values,
  )

  # Service creation must wait for the load balancer admission webhook.
  depends_on = [
    helm_release.lb_controller,
    helm_release.ebs_storage,
    aws_eks_pod_identity_association.thanos,
    module.thanos_bucket,
  ]
}
