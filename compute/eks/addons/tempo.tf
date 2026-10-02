################################################################################
# Tempo — trace storage (Helm, plus an S3 bucket by default)
#
# The traces counterpart of loki.tf: workload traces land in Tempo running
# inside the cluster. By default every block is stored in an S3 bucket in the
# customer's own account; storage_backend = local keeps them on Tempo's own
# volume instead. The add-ons' OpenTelemetry collector (otel_collector.tf) is
# what sends to it; this file is the store.
#
# The same shape as Loki, for the same reasons:
#
#   1. TEMPO IS NEVER EXPOSED. A ClusterIP Service and nothing else: the
#      collector writes OTLP gRPC to it, and the in-cluster Grafana reads its
#      query API on 3200. The chart's other receivers (Jaeger, OTLP HTTP) stay
#      on, because its Service template reads their ports unguarded and fails
#      to render without them.
#
#   2. MONOLITHIC MODE. Every Tempo component in one StatefulSet replica.
#      The tempo destination's helm_values and tempo_helm_values reach every
#      chart value for larger clusters: replicas, resources, limits, query
#      tuning.
#
#   3. RETENTION IS ENFORCED TWICE. Tempo's backend scheduler is the authority:
#      it deletes blocks once their retention has passed. A created bucket's
#      lifecycle rule expires objects a week later, only to sweep up what a
#      scheduler that stopped running would have orphaned.
#
#   4. NO CREDENTIALS ANYWHERE. The S3 config names a bucket, a region and an
#      endpoint, and Tempo resolves credentials through the Pod Identity Agent,
#      as it does to sign the metrics generator's writes to AMP.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  tempo_release_name = "ravion-tempo"
  tempo_namespace    = local.metrics_namespace

  # The same naming as the Loki bucket: lowercase, globally unique through the
  # account id, and truncated in the cluster segment rather than as a whole.
  # "ravion-tempo-" is a character longer than "ravion-loki-", so the segment
  # is one shorter to stay within S3's 63.
  tempo_generated_bucket_name = "ravion-tempo-${replace(substr(local.loki_cluster_slug, 0, 37), "/-+$/", "")}-${data.aws_caller_identity.current.account_id}"

  tempo_s3_enabled = local.tempo_enabled && local.tempo_config.storage_backend == "s3"
  # A bucket only for S3 storage: local storage needs no AWS access at all. As
  # with Loki, the created bucket follows its use, so switching an existing
  # Tempo to local storage deletes it and the traces in it; the plan shows the
  # deletion for approval first.
  tempo_create_bucket = local.tempo_s3_enabled && local.tempo_config.s3_bucket == null

  # Whether the chart ends up with a persistent volume: the last value set
  # across the module's own, the destination's helm_values and each
  # tempo_helm_values document, in the order Helm merges them. The scratch
  # volume and the reinstall below follow this, not the typed field alone.
  tempo_persistence_layers = concat(
    [local.tempo_config.persistence_enabled],
    [try(tobool(local.tempo_config.helm_values.persistence.enabled), null)],
    [for document in var.tempo_helm_values : try(tobool(yamldecode(document).persistence.enabled), null)],
  )
  tempo_persistence_enabled = reverse([for layer in local.tempo_persistence_layers : layer if layer != null])[0]

  tempo_bucket_name = local.tempo_s3_enabled ? coalesce(local.tempo_config.s3_bucket, local.tempo_generated_bucket_name) : null
  tempo_bucket_arn  = local.tempo_s3_enabled ? "arn:${data.aws_partition.current.partition}:s3:::${local.tempo_bucket_name}" : null

  # The metrics generator writes to the in-cluster Prometheus when there is one,
  # otherwise to Amazon Managed Prometheus, signed with Tempo's own role.
  tempo_generator_enabled = local.tempo_enabled && local.tempo_config.metrics_generator_enabled
  tempo_generator_target  = local.prometheus_enabled ? "prometheus" : (local.amp_enabled ? "amp" : null)
  tempo_generator_to_amp  = local.tempo_generator_enabled && local.tempo_generator_target == "amp"

  # Tempo needs AWS credentials only for S3 and for writing to AMP.
  tempo_role_enabled = local.tempo_s3_enabled || local.tempo_generator_to_amp

  tempo_generator_remote_write = local.tempo_generator_enabled ? [
    merge(
      {
        url            = local.tempo_generator_to_amp ? local.amp_remote_write_endpoint : local.prometheus_remote_write_endpoint
        send_exemplars = true
      },
      { for key, value in { sigv4 = { region = local.amp_region } } : key => value if local.tempo_generator_to_amp },
    ),
  ] : []

  # Blocks in S3, or on Tempo's own volume. For expressions rather than a
  # conditional, because the two shapes differ.
  tempo_trace_storage = merge(
    { wal = { path = "/var/tempo/wal" } },
    {
      for key, value in {
        backend = "s3"
        s3 = {
          bucket   = local.tempo_bucket_name
          region   = data.aws_region.current.region
          endpoint = "s3.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
        }
      } : key => value if local.tempo_s3_enabled
    },
    {
      for key, value in {
        backend = "local"
        local   = { path = "/var/tempo/traces" }
      } : key => value if !local.tempo_s3_enabled
    },
  )

  tempo_bucket_expiration_days = local.tempo_config.retention_days + 7

  tempo_service_host   = "${local.tempo_release_name}.${local.tempo_namespace}.svc.cluster.local"
  tempo_endpoint       = local.tempo_enabled ? "http://${local.tempo_service_host}:3200" : null
  tempo_otlp_grpc_host = "${local.tempo_service_host}:4317"

  tempo_resource_limits = merge(
    var.tempo_resources.cpu_limit == null ? {} : { cpu = var.tempo_resources.cpu_limit },
    var.tempo_resources.memory_limit == null ? {} : { memory = var.tempo_resources.memory_limit },
  )

  tempo_resource_requests = merge(
    var.tempo_resources.cpu_request == null ? {} : { cpu = var.tempo_resources.cpu_request },
    var.tempo_resources.memory_request == null ? {} : { memory = var.tempo_resources.memory_request },
  )

  tempo_resources = merge(
    length(local.tempo_resource_requests) > 0 ? { requests = local.tempo_resource_requests } : {},
    length(local.tempo_resource_limits) > 0 ? { limits = local.tempo_resource_limits } : {},
  )
}

################################################################################
# Trace bucket
################################################################################

module "tempo_bucket" {
  count = local.tempo_create_bucket ? 1 : 0

  source = "../../../storage/s3"

  name = local.tempo_generated_bucket_name

  # Traces are a stream: a second copy of every block is cost with nothing to
  # recover, and retention deletes would leave noncurrent versions behind.
  versioning_enabled = false

  # Tempo writes continuously, so a destroy with objects present is the normal
  # case. Retention keeps the bucket bounded.
  force_destroy_enabled = true

  # Tempo only ever talks HTTPS to S3; anything else is refused.
  policy_templates = ["deny_insecure_transport"]

  lifecycle_rules = [
    {
      id      = "ravion-tempo-retention"
      enabled = true

      expiration = {
        days = local.tempo_bucket_expiration_days
      }

      abort_incomplete_multipart_upload_days = 7
    },
  ]

  tags = local.tags
}

################################################################################
# Tempo write identity
################################################################################

data "aws_iam_policy_document" "tempo" {
  count = local.tempo_role_enabled ? 1 : 0

  dynamic "statement" {
    for_each = local.tempo_s3_enabled ? [1] : []
    content {
      sid    = "ListTraceBucket"
      effect = "Allow"
      actions = [
        "s3:ListBucket",
        "s3:GetBucketLocation",
      ]
      resources = [local.tempo_bucket_arn]
    }
  }

  # Delete is how the backend scheduler enforces retention and how compaction
  # removes the blocks it merged. The tagging actions are in Tempo's documented
  # minimal policy for S3.
  dynamic "statement" {
    for_each = local.tempo_s3_enabled ? [1] : []
    content {
      sid    = "ReadWriteTraceObjects"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectTagging",
        "s3:PutObjectTagging",
      ]
      resources = ["${local.tempo_bucket_arn}/*"]
    }
  }

  dynamic "statement" {
    for_each = local.tempo_generator_to_amp ? [1] : []
    content {
      sid       = "WriteGeneratedMetrics"
      effect    = "Allow"
      actions   = ["aps:RemoteWrite"]
      resources = [local.amp_workspace_arn]
    }
  }
}

module "tempo_role" {
  count = local.tempo_role_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${local.name}-tempo"
  description = "Tempo Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "tempo" = data.aws_iam_policy_document.tempo[0].json
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "tempo" {
  count = local.tempo_role_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.tempo_namespace
  service_account = var.tempo_service_account
  role_arn        = module.tempo_role[0].role_arn

  tags = local.tags
}

################################################################################
# Tempo
################################################################################

# Turning persistence on or off adds or removes the StatefulSet's volume claim
# template, which Kubernetes refuses to change in place, so the release is
# reinstalled instead. Tempo is down for that apply. With S3 storage only the
# write-ahead log is lost; with local storage, every block. A larger volume is
# a different case: statefulset_volume_expansion_enabled grows it in place.
resource "terraform_data" "tempo_volume_kind" {
  count = local.tempo_enabled ? 1 : 0

  input = local.tempo_persistence_enabled
}

resource "helm_release" "tempo" {
  count = local.tempo_enabled ? 1 : 0

  name      = local.tempo_release_name
  namespace = local.tempo_namespace
  # The grafana/helm-charts copy is deprecated; the chart moved to
  # grafana-community in January 2026, as Grafana's did.
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "tempo"
  version    = local.tempo_config.chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        # Pins the Service name the collector and Grafana are pointed at.
        fullnameOverride = local.tempo_release_name
        replicas         = 1

        tempo = merge(
          {
            reportingEnabled = false
            resources        = local.tempo_resources

            # Rendered into the backend scheduler's block retention.
            retention = "${local.tempo_config.retention_days * 24}h"

            storage = {
              trace = local.tempo_trace_storage
            }

            # The chart mounts /var/tempo only with persistence on. An emptyDir
            # with a size limit keeps the WAL and the live store writable and
            # bounded without one.
            extraVolumeMounts = local.tempo_persistence_enabled ? [] : [
              {
                name      = "tempo-data"
                mountPath = "/var/tempo"
              },
            ]
          },
          {
            for key, value in {
              metricsGenerator = {
                enabled = true
                storage = {
                  path         = "/var/tempo/generator"
                  remote_write = local.tempo_generator_remote_write
                }
              }
              overrides = {
                defaults = {
                  metrics_generator = {
                    processors = ["service-graphs", "span-metrics"]
                  }
                }
              }
            } : key => value if local.tempo_generator_enabled
          },
        )

        persistence = merge(
          {
            enabled = local.tempo_config.persistence_enabled
            size    = local.tempo_config.persistence_size
          },
          local.tempo_config.storage_class == null ? {} : { storageClassName = local.tempo_config.storage_class },
        )

        extraVolumes = local.tempo_persistence_enabled ? [] : [
          {
            name     = "tempo-data"
            emptyDir = { sizeLimit = local.tempo_config.persistence_size }
          },
        ]

        # Must match the Pod Identity association above, or Tempo falls back
        # to the node role and every write fails with AccessDenied.
        serviceAccount = {
          create = true
          name   = var.tempo_service_account
        }
      }),
    ],
    length(keys(local.tempo_config.helm_values)) > 0 ? [yamlencode(local.tempo_config.helm_values)] : [],
    var.tempo_helm_values,
  )

  # Tempo reads AWS credentials on startup through the Pod Identity Agent, and
  # writes to a bucket that must already exist.
  depends_on = [
    helm_release.lb_controller,
    helm_release.ebs_storage,
    aws_eks_pod_identity_association.tempo,
    module.tempo_bucket,
  ]

  lifecycle {
    replace_triggered_by = [terraform_data.tempo_volume_kind[count.index]]

    precondition {
      condition     = !local.tempo_generator_enabled || local.tempo_generator_target != null
      error_message = "Tempo's metrics generator writes service graphs and span metrics to Prometheus, but metrics_providers has neither prometheus nor amp. Select one, or turn the tempo destination's metrics_generator_enabled off."
    }
  }
}
