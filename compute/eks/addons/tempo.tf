################################################################################
# Tempo — trace storage (S3 bucket + Helm)
#
# The traces counterpart of loki.tf: workload traces land in Tempo running
# inside the cluster, with every block stored in an S3 bucket in the customer's
# own account. The add-ons' OpenTelemetry collector (otel_collector.tf) is what
# sends to it; this file is the store.
#
# The same shape as Loki, for the same reasons:
#
#   1. TEMPO IS NEVER EXPOSED. A ClusterIP Service and nothing else: the
#      collector writes OTLP to it, and the in-cluster Grafana reads its query
#      API on 3200. Every receiver but OTLP gRPC is off.
#
#   2. MONOLITHIC MODE. Every Tempo component in one StatefulSet replica.
#      tempo_helm_values is the escape hatch for larger clusters.
#
#   3. RETENTION IS ENFORCED TWICE. Tempo's backend scheduler is the authority:
#      it deletes blocks once their retention has passed. The bucket's
#      lifecycle rule expires objects a week later, only to sweep up what a
#      scheduler that stopped running would have orphaned.
#
#   4. NO CREDENTIALS ANYWHERE. The S3 config names a bucket, a region and an
#      endpoint, and Tempo resolves credentials through the Pod Identity Agent.
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
  tempo_generated_bucket_name = "ravion-tempo-${local.loki_cluster_slug}-${data.aws_caller_identity.current.account_id}"

  tempo_create_bucket = local.tempo_enabled && local.tempo_config.s3_bucket == null

  tempo_bucket_name = local.tempo_enabled ? coalesce(local.tempo_config.s3_bucket, local.tempo_generated_bucket_name) : null
  tempo_bucket_arn  = local.tempo_enabled ? "arn:${data.aws_partition.current.partition}:s3:::${local.tempo_bucket_name}" : null

  # The bucket sweeps up a week after the backend scheduler should have.
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

data "aws_iam_policy_document" "tempo_s3" {
  count = local.tempo_enabled ? 1 : 0

  statement {
    sid    = "ListTraceBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [local.tempo_bucket_arn]
  }

  # Delete is how the backend scheduler enforces retention and how compaction
  # removes the blocks it merged. The tagging actions are in Tempo's documented
  # minimal policy for S3.
  statement {
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

module "tempo_role" {
  count = local.tempo_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${local.name}-tempo"
  description = "Tempo trace storage Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "trace-bucket-access" = data.aws_iam_policy_document.tempo_s3[0].json
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "tempo" {
  count = local.tempo_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.tempo_namespace
  service_account = var.tempo_service_account
  role_arn        = module.tempo_role[0].role_arn

  tags = local.tags
}

################################################################################
# Tempo
################################################################################

resource "helm_release" "tempo" {
  count = local.tempo_enabled ? 1 : 0

  name      = local.tempo_release_name
  namespace = local.tempo_namespace
  # The grafana/helm-charts copy is deprecated; the chart moved to
  # grafana-community in January 2026, as Grafana's did.
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        # Pins the Service name the collector and Grafana are pointed at.
        fullnameOverride = local.tempo_release_name
        replicas         = 1

        tempo = {
          reportingEnabled = false
          resources        = local.tempo_resources

          # Rendered into the backend scheduler's block retention.
          retention = "${local.tempo_config.retention_days * 24}h"

          storage = {
            trace = {
              backend = "s3"
              s3 = {
                bucket   = local.tempo_bucket_name
                region   = data.aws_region.current.region
                endpoint = "s3.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
              }
              wal = {
                path = "/var/tempo/wal"
              }
            }
          }

          # OTLP gRPC from the collector only. The chart's default Jaeger
          # receivers would each open a port on the Service.
          receivers = {
            jaeger = null
            otlp = {
              protocols = {
                grpc = {
                  endpoint = "0.0.0.0:4317"
                }
              }
            }
          }

          # The chart mounts /var/tempo only with persistence on. An emptyDir
          # with a size limit keeps the WAL and the live store writable and
          # bounded without one; blocks are in S3 as soon as they are cut.
          extraVolumeMounts = [
            {
              name      = "tempo-data"
              mountPath = "/var/tempo"
            },
          ]
        }

        extraVolumes = [
          {
            name     = "tempo-data"
            emptyDir = { sizeLimit = local.tempo_config.local_storage_size }
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
    var.tempo_helm_values,
  )

  # Tempo reads AWS credentials on startup through the Pod Identity Agent, and
  # writes to a bucket that must already exist.
  depends_on = [
    aws_eks_pod_identity_association.tempo,
    module.tempo_bucket,
  ]
}
