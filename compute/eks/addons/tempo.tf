################################################################################
# Tempo — private OTLP trace storage on S3, with a persistent local WAL
################################################################################

locals {
  tempo_release_name     = "ravion-tempo"
  tempo_service_account  = "ravion-tempo"
  tempo_generated_bucket = "ravion-traces-${local.s3_observability_cluster_slug}-${data.aws_caller_identity.current.account_id}"
  tempo_bucket_name      = local.tempo_enabled ? coalesce(var.traces_tempo.s3_bucket_name, local.tempo_generated_bucket) : null
  tempo_bucket_arn       = local.tempo_enabled ? "arn:${data.aws_partition.current.partition}:s3:::${local.tempo_bucket_name}" : null
  tempo_create_bucket    = local.tempo_enabled && var.traces_tempo.s3_bucket_name == null
  tempo_service_host     = "${local.tempo_release_name}.${local.observability_namespace}.svc.cluster.local"
  tempo_endpoint         = local.tempo_enabled ? "http://${local.tempo_service_host}:3200" : null
  tempo_storage_class    = var.traces_tempo.storage_class != null ? var.traces_tempo.storage_class : (local.ebs_default_storage_class_enabled ? "gp3" : null)
}

module "tempo_bucket" {
  count  = local.tempo_create_bucket ? 1 : 0
  source = "../../../storage/s3"

  name                  = local.tempo_generated_bucket
  versioning_enabled    = false
  force_destroy_enabled = true
  policy_templates      = ["deny_insecure_transport"]
  # Tempo's compactor owns retention; no lifecycle rule races active blocks.
  lifecycle_rules = [{
    id                                     = "abort-incomplete-uploads"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 1
  }]
  tags = local.tags
}

data "aws_iam_policy_document" "tempo_s3" {
  count = local.tempo_enabled ? 1 : 0

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.tempo_bucket_arn]
  }
  statement {
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:GetObjectTagging", "s3:PutObjectTagging",
    ]
    resources = ["${local.tempo_bucket_arn}/*"]
  }
}

module "tempo_role" {
  count  = local.tempo_enabled ? 1 : 0
  source = "../../../security/iam"

  name                      = "${local.name}-tempo"
  description               = "Tempo trace storage Pod Identity for ${var.cluster_name}"
  custom_assume_role_policy = local.pod_identity_trust_policy
  inline_policies           = { "trace-bucket-access" = data.aws_iam_policy_document.tempo_s3[0].json }
  tags                      = local.tags
}

resource "aws_eks_pod_identity_association" "tempo" {
  count = local.tempo_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.observability_namespace
  service_account = local.tempo_service_account
  role_arn        = module.tempo_role[0].role_arn
  tags            = local.tags
}

resource "helm_release" "tempo" {
  count = local.tempo_enabled ? 1 : 0

  name             = local.tempo_release_name
  namespace        = local.observability_namespace
  repository       = "https://grafana-community.github.io/helm-charts"
  chart            = "tempo"
  version          = var.tempo_chart_version
  create_namespace = true
  upgrade_install  = true

  values = concat([yamlencode({
    fullnameOverride = local.tempo_release_name
    replicas         = 1
    serviceAccount   = { create = true, name = local.tempo_service_account }
    service          = { type = "ClusterIP" }
    persistence = {
      enabled          = true
      size             = var.traces_tempo.storage_size
      storageClassName = local.tempo_storage_class
    }
    # The chart's port helper dereferences jaeger.protocols unconditionally.
    # Keep that empty map for rendering, but omit Jaeger from Tempo's config.
    config = <<-YAML
      memberlist:
        cluster_label: "{{ .Release.Name }}.{{ .Release.Namespace }}"
      multitenancy_enabled: false
      usage_report:
        reporting_enabled: false
      compactor:
        compaction:
          block_retention: {{ .Values.tempo.retention }}
      distributor:
        receivers:
          {{- toYaml (omit .Values.tempo.receivers "jaeger") | nindent 4 }}
      ingester:
        {{- toYaml .Values.tempo.ingester | nindent 2 }}
      server:
        {{- toYaml .Values.tempo.server | nindent 2 }}
      storage:
        {{- toYaml .Values.tempo.storage | nindent 2 }}
      querier:
        {{- toYaml .Values.tempo.querier | nindent 2 }}
      query_frontend:
        {{- toYaml .Values.tempo.queryFrontend | nindent 2 }}
      overrides:
        {{- toYaml .Values.tempo.overrides | nindent 2 }}
    YAML
    tempo = {
      reportingEnabled = false
      # The chart defaults to a 1GiB ballast, which would consume the entire
      # default memory limit before Tempo ingests any spans.
      memBallastSizeMbs = 0
      retention         = "${var.traces_tempo.retention_days * 24}h"
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
      receivers = {
        jaeger = {
          protocols = {
            grpc           = null
            thrift_binary  = null
            thrift_compact = null
            thrift_http    = null
          }
        }
        otlp = {
          protocols = {
            grpc = { endpoint = "0.0.0.0:4317" }
            http = { endpoint = "0.0.0.0:4318" }
          }
        }
      }
      storage = {
        trace = {
          backend = "s3"
          local   = null
          wal     = { path = "/var/tempo/wal" }
          s3 = {
            bucket   = local.tempo_bucket_name
            region   = data.aws_region.current.region
            endpoint = "s3.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
            insecure = false
          }
        }
      }
      metricsGenerator = { enabled = false }
    }
    tempoQuery = { enabled = false }
  })], var.tempo_helm_values)

  lifecycle {
    precondition {
      condition     = local.tempo_bucket_name != local.loki_bucket_name && local.tempo_bucket_name != local.thanos_bucket_name
      error_message = "Metrics, logs and traces must use separate dedicated S3 buckets; their compactors cannot safely share a bucket."
    }
  }

  depends_on = [
    helm_release.lb_controller,
    helm_release.ebs_storage,
    aws_eks_pod_identity_association.tempo,
    module.tempo_bucket,
  ]
}
