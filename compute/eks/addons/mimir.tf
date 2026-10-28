################################################################################
# Mimir — horizontally scalable in-cluster metrics on S3
#
# For clusters that outgrow one Prometheus. The classic ingester architecture,
# without Kafka: distributors write every sample to three ingesters, which keep
# recent data on their volumes and ship blocks to S3; the store-gateways serve
# history, and the singleton compactor owns retention. Writers push through the
# gateway; readers query its /prometheus path, the same PromQL as Prometheus.
################################################################################

locals {
  mimir_release_name    = "ravion-mimir"
  mimir_service_account = local.mimir_release_name
  mimir_gateway_url     = "http://${local.mimir_release_name}-gateway.${local.observability_namespace}.svc.cluster.local"

  mimir_endpoint              = local.mimir_enabled ? "${local.mimir_gateway_url}/prometheus" : null
  mimir_remote_write_endpoint = local.mimir_enabled ? "${local.mimir_gateway_url}/api/v1/push" : null

  # Blank form fields are unset, as for Prometheus.
  mimir_config = {
    retention_days = coalesce(var.metrics_mimir.retention_days, 365)
    s3_bucket_name = try(trimspace(var.metrics_mimir.s3_bucket_name), "") == "" ? null : trimspace(var.metrics_mimir.s3_bucket_name)
    storage_class  = try(trimspace(var.metrics_mimir.storage_class), "") != "" ? trimspace(var.metrics_mimir.storage_class) : (local.ebs_default_storage_class_enabled ? "gp3" : null)
    zones          = distinct(coalesce(var.metrics_mimir.zones, []))
  }

  mimir_generated_bucket = "ravion-mimir-${local.s3_observability_cluster_slug}-${data.aws_caller_identity.current.account_id}"
  mimir_bucket_name      = local.mimir_enabled ? coalesce(local.mimir_config.s3_bucket_name, local.mimir_generated_bucket) : null
  mimir_bucket_arn       = local.mimir_enabled ? "arn:${data.aws_partition.current.partition}:s3:::${local.mimir_bucket_name}" : null
  mimir_create_bucket    = local.mimir_enabled && local.mimir_config.s3_bucket_name == null

  # Each zone holds one of the three copies of every sample. Mimir's chart
  # names zones itself; the node selector pins each to an availability zone.
  # Zoned pods ignore the component's affinity, so the store placement rides
  # on each zone instead.
  mimir_zone_aware = length(local.mimir_config.zones) >= 3
  mimir_zones = [
    for index, zone in local.mimir_config.zones : merge(
      {
        name         = "zone-${substr("abcdefghijklmnopqrstuvwxyz", index, 1)}"
        nodeSelector = { "topology.kubernetes.io/zone" = zone }
      },
      { for key, value in { extraAffinity = local.addon_store_placement.affinity } : key => value if var.addon_placement_enabled },
    )
  ]

  # Copies on separate nodes is a hard rule: two on one node lose two at once.
  # A hostname spread alone does not keep it. It counts only nodes that exist,
  # so three replicas on two nodes (2 and 1) are within a skew of one, and
  # ravion-prod ran two ingesters on one node. Anti-affinity refuses the second
  # pod, and Karpenter brings up a node for it. Zones are soft, so a
  # single-zone cluster still runs.
  mimir_replica_spread = [
    { maxSkew = 1, topologyKey = "kubernetes.io/hostname", whenUnsatisfiable = "DoNotSchedule" },
    { maxSkew = 1, topologyKey = "topology.kubernetes.io/zone", whenUnsatisfiable = "ScheduleAnyway" },
  ]
  mimir_replica_anti_affinity = {
    for component, label in { ingester = "ingester", store_gateway = "store-gateway" } : component => {
      podAntiAffinity = {
        requiredDuringSchedulingIgnoredDuringExecution = [{
          topologyKey = "kubernetes.io/hostname"
          labelSelector = {
            matchLabels = {
              "app.kubernetes.io/component" = label
              "app.kubernetes.io/instance"  = local.mimir_release_name
              "app.kubernetes.io/name"      = "mimir"
            }
          }
        }]
      }
    }
  }

  # An ingester keeps every series it has seen in memory until it cuts a block,
  # every two hours. Series from pods that have gone, after a rollout or a
  # scale-down, sit there until then, so churn alone can fill an ingester that
  # holds far fewer live series. Past this many in-memory series it compacts
  # early and drops the inactive ones: half the memory limit at 8KiB a series.
  # The limit counts only when this module sets it: without resilience,
  # mimir_ingester_resources is not applied, so the threshold would follow a
  # limit no pod has. Early compaction is off there, as in Mimir's default.
  mimir_ingester_memory_mib = try(
    tonumber(regex("^([0-9]+)(Mi|Gi)$", var.mimir_ingester_resources.limits.memory)[0]) * { Mi = 1, Gi = 1024 }[regex("^([0-9]+)(Mi|Gi)$", var.mimir_ingester_resources.limits.memory)[1]],
    null,
  )
  mimir_early_head_compaction_series = var.addon_resilience_enabled && local.mimir_ingester_memory_mib != null ? floor(local.mimir_ingester_memory_mib * 1024 / 8 / 2) : 0

  # Go's soft memory limit at 90% of that limit: the runtime collects garbage
  # harder as the heap nears it, instead of being OOMKilled at the limit. The
  # chart sets none for ingesters. Applied with the limit, so only with
  # resilience.
  mimir_ingester_go_env = local.mimir_ingester_memory_mib == null ? [] : [{ name = "GOMEMLIMIT", value = "${floor(local.mimir_ingester_memory_mib * 0.9)}MiB" }]

  mimir_values = {
    fullnameOverride = local.mimir_release_name
    serviceAccount   = { create = true, name = local.mimir_service_account }

    # The module's own bucket replaces MinIO. Kafka is the chart's default ingest
    # path; the classic path writes straight to the ingesters, one fewer
    # stateful system to run. These are the chart's classic-architecture.yaml.
    minio = { enabled = false }
    kafka = { enabled = false }

    # Nothing here configures rules or alerts.
    ruler        = { enabled = false }
    alertmanager = { enabled = false }

    rollout_operator = { enabled = local.mimir_zone_aware }

    ingester = merge(
      { replicas = var.mimir_ingester_replicas, persistentVolume = { size = "50Gi", storageClass = local.mimir_config.storage_class } },
      { for key, value in { zoneAwareReplication = { enabled = true, topologyKey = "kubernetes.io/hostname", zones = local.mimir_zones } } : key => value if local.mimir_zone_aware },
      { for key, value in { zoneAwareReplication = { enabled = false }, topologySpreadConstraints = local.mimir_replica_spread, affinity = local.mimir_replica_anti_affinity.ingester } : key => value if !local.mimir_zone_aware },
    )
    store_gateway = merge(
      { replicas = 3, persistentVolume = { size = "20Gi", storageClass = local.mimir_config.storage_class } },
      { for key, value in { zoneAwareReplication = { enabled = true, topologyKey = "kubernetes.io/hostname", zones = local.mimir_zones } } : key => value if local.mimir_zone_aware },
      { for key, value in { zoneAwareReplication = { enabled = false }, topologySpreadConstraints = local.mimir_replica_spread, affinity = local.mimir_replica_anti_affinity.store_gateway } : key => value if !local.mimir_zone_aware },
    )
    compactor = {
      persistentVolume = { size = "50Gi", storageClass = local.mimir_config.storage_class }
    }

    mimir = {
      structuredConfig = {
        # One cluster is one tenant: no writer or reader needs X-Scope-OrgID.
        multitenancy_enabled = false

        # No keys: the SDK chain resolves the Pod Identity association below.
        common = {
          storage = {
            backend = "s3"
            s3 = {
              endpoint = "s3.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
              region   = data.aws_region.current.region
            }
          }
        }
        blocks_storage = {
          storage_prefix = "blocks"
          s3             = { bucket_name = local.mimir_bucket_name }
          tsdb           = { early_head_compaction_min_in_memory_series = local.mimir_early_head_compaction_series }
        }
        ruler_storage        = { storage_prefix = "ruler", s3 = { bucket_name = local.mimir_bucket_name } }
        alertmanager_storage = { storage_prefix = "alertmanager", s3 = { bucket_name = local.mimir_bucket_name } }

        ingest_storage = {
          enabled = false
          kafka   = { address = null, topic = null, auto_create_topic_default_partitions = null }
        }
        distributor = { remote_timeout = null }
        ingester = merge(
          {
            push_grpc_method_enabled = null
            ring                     = { replication_factor = 3 }
          },
          # Refuses new series past the limit rather than OOMKilling every copy.
          { for key, value in { instance_limits = { max_series = var.mimir_ingester_max_series } } : key => value if var.mimir_ingester_max_series > 0 },
        )

        # Mimir's defaults reject data: 150,000 series and 10,000 samples a
        # second per tenant, which one busy cluster passes. Nothing written is
        # turned away; size the ingesters instead.
        limits = {
          max_global_series_per_user   = 0
          max_global_series_per_metric = 0
          ingestion_rate               = 10000000
          ingestion_burst_size         = 100000000
          max_label_names_per_series   = 128
          max_label_name_length        = 1024
          max_label_value_length       = 16384
          max_metadata_length          = 4096
          # Collectors retry a failed write for up to ten minutes.
          out_of_order_time_window = "15m"
          # The compactor owns retention; no bucket rule competes with it.
          compactor_blocks_retention_period = "${local.mimir_config.retention_days * 24}h"
        }
      }
    }
  }
}

module "mimir_bucket" {
  count  = local.mimir_create_bucket ? 1 : 0
  source = "../../../storage/s3"

  name                  = local.mimir_generated_bucket
  versioning_enabled    = false
  force_destroy_enabled = true
  policy_templates      = ["deny_insecure_transport"]
  lifecycle_rules = [{
    id                                     = "abort-incomplete-uploads"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 7
  }]
  tags = local.tags
}

data "aws_iam_policy_document" "mimir_s3" {
  count = local.mimir_enabled ? 1 : 0

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.mimir_bucket_arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.mimir_bucket_arn}/*"]
  }
}

module "mimir_role" {
  count  = local.mimir_enabled ? 1 : 0
  source = "../../../security/iam"

  name                      = "${local.name}-mimir"
  description               = "Mimir Pod Identity for ${var.cluster_name}"
  custom_assume_role_policy = local.pod_identity_trust_policy
  inline_policies           = { "metrics-bucket-access" = data.aws_iam_policy_document.mimir_s3[0].json }
  tags                      = local.tags
}

resource "aws_eks_pod_identity_association" "mimir" {
  count = local.mimir_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.observability_namespace
  service_account = local.mimir_service_account
  role_arn        = module.mimir_role[0].role_arn
  tags            = local.tags
}

resource "helm_release" "mimir" {
  count = local.mimir_enabled ? 1 : 0

  name             = local.mimir_release_name
  namespace        = local.observability_namespace
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "mimir-distributed"
  version          = var.mimir_chart_version
  create_namespace = true
  upgrade_install  = true
  # Three ingesters start one after another, each replaying its WAL.
  timeout = 1200

  values = concat(
    [yamlencode(local.mimir_values)],
    var.addon_placement_enabled ? [yamlencode({
      for component in local.mimir_stateless_components : component => local.addon_pod_placement
    })] : [],
    # Ingesters, store-gateways and the compactor hold volumes and run with
    # the other stores.
    var.addon_placement_enabled ? [yamlencode({
      for component in local.mimir_stateful_components : component => local.addon_store_placement
    })] : [],
    local.mimir_resilience_values,
    var.mimir_helm_values,
  )

  lifecycle {
    precondition {
      condition     = !contains(compact([local.thanos_bucket_name, local.loki_bucket_name, local.tempo_bucket_name]), local.mimir_bucket_name)
      error_message = "Mimir needs its own S3 bucket, separate from the Thanos, Loki and Tempo buckets; their compactors cannot safely share one."
    }
  }

  depends_on = [
    helm_release.lb_controller,
    helm_release.ebs_storage,
    aws_eks_pod_identity_association.mimir,
    module.mimir_bucket,
  ]
}
