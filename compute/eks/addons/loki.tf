################################################################################
# Loki — log storage (S3 bucket + Helm)
#
# Container logs land in Loki running inside the cluster, with every chunk and
# index file stored in an S3 bucket in the customer's own account. Grafana Alloy
# is the collector (alloy.tf); this file is the store.
#
# Four things about the shape of this file:
#
#   1. LOKI IS NEVER EXPOSED. No ingress, no load balancer, no gateway — a
#      ClusterIP Service on 3100 and nothing else. Ravion reads it through the
#      Ravion Operator's tunnel, which is why the log data never leaves the
#      customer's account except as the answer to a query they can audit.
#
#   2. SINGLE-BINARY MODE. Every Loki target in one StatefulSet replica, with
#      the memcached caches and the nginx gateway off. A simple-scalable
#      deployment is three workloads plus two memcached tiers before it stores a
#      byte, and this pipeline's job is to be unremarkable on a cluster running
#      twenty services. loki_helm_values is the escape hatch for larger ones.
#
#   3. RETENTION IS ENFORCED TWICE, DELIBERATELY. Loki's compactor is the
#      authority: it rewrites the index and deletes chunks whose retention has
#      passed. The bucket's lifecycle rule expires objects a week LATER, so it
#      never races the compactor into deleting an index still being read — it
#      only sweeps up what a compactor that stopped running would have orphaned.
#
#   4. NO CREDENTIALS ANYWHERE. The chart's S3 config carries a region and a
#      bucket name and no keys, so Loki resolves credentials through the AWS SDK
#      default chain, which the Pod Identity Agent populates.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  loki_release_name = "ravion-loki"

  # S3 bucket names are lowercase, 3-63 characters, and globally unique. The
  # cluster segment is truncated rather than the whole name, so the account id
  # that makes it unique always survives; a trailing hyphen left by the
  # truncation would be an invalid name, hence the trim.
  loki_cluster_slug = replace(
    substr(replace(lower(var.cluster_name), "/[^a-z0-9-]/", "-"), 0, 38),
    "/-+$/",
    "",
  )

  loki_generated_bucket_name = "ravion-loki-${local.loki_cluster_slug}-${data.aws_caller_identity.current.account_id}"

  loki_create_bucket = local.loki_enabled && local.loki_config.s3_bucket == null

  loki_bucket_name = local.loki_enabled ? coalesce(local.loki_config.s3_bucket, local.loki_generated_bucket_name) : null

  # Constructed rather than read from the module output, so the bring-your-own
  # case needs no data source and no round trip.
  loki_bucket_arn = local.loki_enabled ? "arn:${data.aws_partition.current.partition}:s3:::${local.loki_bucket_name}" : null

  # Loki takes durations, not days. Kept a whole number of days so it lines up
  # with the 24h index period.
  loki_retention_period = "${local.loki_config.retention_days * 24}h"

  # The bucket sweeps up a week after the compactor should have. See (3) above.
  loki_bucket_expiration_days = local.loki_config.retention_days + 7

  loki_service_host = "${local.loki_release_name}.${local.logs_namespace}.svc.cluster.local"
  loki_endpoint     = local.loki_enabled ? "http://${local.loki_service_host}:3100" : null
  loki_push_url     = local.loki_enabled ? "${local.loki_endpoint}/loki/api/v1/push" : null

  loki_resource_limits = merge(
    var.loki_resources.cpu_limit == null ? {} : { cpu = var.loki_resources.cpu_limit },
    var.loki_resources.memory_limit == null ? {} : { memory = var.loki_resources.memory_limit },
  )

  loki_resource_requests = merge(
    var.loki_resources.cpu_request == null ? {} : { cpu = var.loki_resources.cpu_request },
    var.loki_resources.memory_request == null ? {} : { memory = var.loki_resources.memory_request },
  )

  loki_resources = merge(
    length(local.loki_resource_requests) > 0 ? { requests = local.loki_resource_requests } : {},
    length(local.loki_resource_limits) > 0 ? { limits = local.loki_resource_limits } : {},
  )
}

################################################################################
# Log bucket
################################################################################

module "loki_bucket" {
  count = local.loki_create_bucket ? 1 : 0

  source = "../../../storage/s3"

  name = local.loki_generated_bucket_name

  # Logs are a stream, not a document store: a second copy of every chunk is
  # storage cost with nothing to recover, and the compactor's deletes would
  # leave noncurrent versions behind that no retention rule here removes.
  versioning_enabled = false

  # Loki writes continuously, so a destroy with objects present is the normal
  # case rather than an accident. Retention makes the bucket self-limiting;
  # refusing to destroy it would leave orphans on every cluster teardown.
  force_destroy_enabled = true

  lifecycle_rules = [
    {
      id      = "ravion-loki-retention"
      enabled = true

      expiration = {
        days = local.loki_bucket_expiration_days
      }

      # A failed multipart upload is invisible and billable.
      abort_incomplete_multipart_upload_days = 7
    },
  ]

  tags = local.tags
}

################################################################################
# Loki write identity
################################################################################

data "aws_iam_policy_document" "loki_s3" {
  count = local.loki_enabled ? 1 : 0

  statement {
    sid    = "ListLogBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [local.loki_bucket_arn]
  }

  # Delete is required, not optional: it is how the compactor enforces
  # retention. Without it chunks accumulate until the bucket lifecycle rule
  # catches them a week late.
  statement {
    sid    = "ReadWriteLogObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.loki_bucket_arn}/*"]
  }
}

module "loki_role" {
  count = local.loki_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-loki"
  description = "Loki log storage Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "log-bucket-access" = data.aws_iam_policy_document.loki_s3[0].json
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "loki" {
  count = local.loki_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.logs_namespace
  service_account = var.loki_service_account
  role_arn        = module.loki_role[0].role_arn

  tags = local.tags
}

################################################################################
# Loki
################################################################################

resource "helm_release" "loki" {
  count = local.loki_enabled ? 1 : 0

  name       = local.loki_release_name
  namespace  = local.logs_namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        deploymentMode = "SingleBinary"

        # Pins the Service name the collector and Ravion Operator are pointed at, so it
        # is a constant rather than a function of the release name.
        fullnameOverride = local.loki_release_name

        loki = {
          # One tenant per cluster. Without auth_enabled every request is
          # attributed to the "fake" tenant and no X-Scope-OrgID header is
          # needed anywhere — including in Ravion Operator's proxied queries.
          auth_enabled = false

          commonConfig = {
            replication_factor = 1
          }

          server = {
            http_listen_port = 3100
          }

          # A schema is the one thing the chart refuses to guess, because
          # changing it later means a new `from` date rather than an edit.
          # tsdb + v13 is the current Loki 3.x pairing and the only one that
          # supports structured metadata, which is where `level` lives.
          schemaConfig = {
            configs = [
              {
                from         = "2024-04-01"
                store        = "tsdb"
                object_store = "s3"
                schema       = "v13"
                index = {
                  prefix = "index_"
                  period = "24h"
                }
              },
            ]
          }

          storage = {
            type = "s3"
            bucketNames = {
              chunks = local.loki_bucket_name
              ruler  = local.loki_bucket_name
            }
            s3 = {
              region           = data.aws_region.current.region
              s3ForcePathStyle = false
            }
          }

          limits_config = {
            retention_period = local.loki_retention_period

            # Structured metadata is what keeps `level` out of the index while
            # still being filterable, so the whole label design depends on it.
            allow_structured_metadata = true

            # Powers the log-volume histogram the dashboard draws above a
            # result set.
            volume_enabled = true

            # A node with a badly skewed clock can otherwise poison a stream's
            # ordering for everything behind it.
            reject_old_samples         = true
            reject_old_samples_max_age = "168h"
          }

          compactor = {
            working_directory = "/var/loki/compactor"

            # The authority on retention. Off by default in Loki, which is the
            # single most common reason a Loki bucket grows forever.
            retention_enabled    = true
            delete_request_store = "s3"
            compaction_interval  = "10m"

            # A grace window between marking a chunk deletable and deleting it,
            # so a query in flight does not lose its objects underneath it.
            retention_delete_delay = "2h"
          }

          analytics = {
            reporting_enabled = false
          }
        }

        # Must match the Pod Identity association above, or Loki falls back to
        # the node role and every write fails with AccessDenied.
        serviceAccount = {
          create = true
          name   = var.loki_service_account
        }

        # The chart mounts /var/loki only when persistence is on, and the
        # container runs with a read-only root filesystem — so with persistence
        # off and nothing else done, Loki cannot write its WAL, its compactor
        # working directory, or its index cache, and crash-loops. An emptyDir
        # with the same size limit fills that gap: ephemeral, bounded, and
        # evicted rather than filling the node if Loki ever runs away.
        singleBinary = {
          replicas  = 1
          resources = local.loki_resources

          persistence = {
            enabled = local.loki_config.persistence_enabled
            size    = local.loki_config.persistence_size
          }

          # Empty when the PVC above already covers /var/loki.
          extraVolumes = local.loki_config.persistence_enabled ? [] : [
            {
              name     = "loki-data"
              emptyDir = { sizeLimit = local.loki_config.persistence_size }
            },
          ]

          extraVolumeMounts = local.loki_config.persistence_enabled ? [] : [
            {
              name      = "loki-data"
              mountPath = "/var/loki"
            },
          ]
        }

        # Every other topology off. The chart validates these against
        # deploymentMode, so a non-zero replica count here is a render error
        # rather than a surprise second copy of Loki.
        backend = { replicas = 0 }
        read    = { replicas = 0 }
        write   = { replicas = 0 }

        # memcached tiers, an nginx gateway, a canary DaemonSet and a bundled
        # MinIO — none of which a single-binary Loki backed by S3 needs.
        chunksCache  = { enabled = false }
        resultsCache = { enabled = false }
        gateway      = { enabled = false }
        lokiCanary   = { enabled = false }
        test         = { enabled = false }
        minio        = { enabled = false }
      }),
    ],
    var.loki_helm_values,
  )

  # Loki reads AWS credentials on startup through the Pod Identity Agent, and
  # writes to a bucket that must already exist.
  depends_on = [
    helm_release.lb_controller,
    aws_eks_pod_identity_association.loki,
    module.loki_bucket,
  ]
}
