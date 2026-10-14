################################################################################
# Thanos — durable Prometheus history on S3
#
# The existing Prometheus PVC remains the write-ahead/recent-data store. A
# sidecar ships uncompacted two-hour blocks; Query reads both the sidecar and
# Store Gateway. Only the singleton Compactor deletes blocks for retention.
# No age-based bucket expiration: compacted objects' ages are not sample ages.
################################################################################

locals {
  thanos_enabled             = local.prometheus_install && local.prometheus_config.s3_storage_enabled
  thanos_release_name        = "ravion-thanos"
  prometheus_service_account = "ravion-prometheus"
  thanos_query_endpoint      = "http://${local.thanos_release_name}-query.${local.observability_namespace}.svc.cluster.local:9090"
  thanos_generated_bucket    = "ravion-metrics-${local.s3_observability_cluster_slug}-${data.aws_caller_identity.current.account_id}"
  thanos_bucket_name         = local.thanos_enabled ? coalesce(local.prometheus_config.s3_bucket_name, local.thanos_generated_bucket) : null
  thanos_bucket_arn          = local.thanos_enabled ? "arn:${data.aws_partition.current.partition}:s3:::${local.thanos_bucket_name}" : null
  thanos_create_bucket       = local.thanos_enabled && local.prometheus_config.s3_bucket_name == null

  # aws_sdk_auth is required for the SDK's EKS Pod Identity credential chain.
  thanos_objstore_config = yamlencode({
    type = "S3"
    config = {
      bucket       = local.thanos_bucket_name
      region       = data.aws_region.current.region
      endpoint     = "s3.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
      aws_sdk_auth = true
      insecure     = false
    }
  })

  thanos_identities = local.thanos_enabled ? {
    sidecar = {
      service_account = local.prometheus_service_account
      object_actions  = ["s3:GetObject", "s3:PutObject"]
    }
    store = {
      service_account = "${local.thanos_release_name}-store"
      object_actions  = ["s3:GetObject"]
    }
    compactor = {
      service_account = "${local.thanos_release_name}-compactor"
      object_actions  = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    }
  } : {}

  thanos_sidecar = {
    image = var.thanos_image
    args = [
      "sidecar",
      "--prometheus.url=http://127.0.0.1:9090",
      "--tsdb.path=/data",
      "--grpc-address=0.0.0.0:10901",
      "--http-address=0.0.0.0:10902",
      "--objstore.config=${local.thanos_objstore_config}",
    ]
    ports = [
      { name = "thanos-grpc", containerPort = 10901 },
      { name = "thanos-http", containerPort = 10902 },
    ]
    volumeMounts = [{ name = "storage-volume", mountPath = "/data" }]
    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { memory = "512Mi" }
    }
    securityContext = {
      allowPrivilegeEscalation = false
      readOnlyRootFilesystem   = true
      capabilities             = { drop = ["ALL"] }
    }
    readinessProbe = { httpGet = { path = "/-/ready", port = "thanos-http" } }
    livenessProbe  = { httpGet = { path = "/-/healthy", port = "thanos-http" } }
  }
}

module "thanos_bucket" {
  count  = local.thanos_create_bucket ? 1 : 0
  source = "../../../storage/s3"

  name                  = local.thanos_generated_bucket
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

data "aws_iam_policy_document" "thanos_s3" {
  for_each = local.thanos_identities

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.thanos_bucket_arn]
  }
  statement {
    actions   = each.value.object_actions
    resources = ["${local.thanos_bucket_arn}/*"]
  }
}

module "thanos_role" {
  for_each = local.thanos_identities
  source   = "../../../security/iam"

  name                      = "${local.name}-thanos-${each.key}"
  description               = "Thanos ${each.key} Pod Identity for ${var.cluster_name}"
  custom_assume_role_policy = local.pod_identity_trust_policy
  inline_policies           = { "metrics-bucket-access" = data.aws_iam_policy_document.thanos_s3[each.key].json }
  tags                      = local.tags
}

resource "aws_eks_pod_identity_association" "thanos" {
  for_each = local.thanos_identities

  cluster_name    = var.cluster_name
  namespace       = local.observability_namespace
  service_account = each.value.service_account
  role_arn        = module.thanos_role[each.key].role_arn
  tags            = local.tags
}

resource "helm_release" "thanos" {
  count = local.thanos_enabled ? 1 : 0

  name      = local.thanos_release_name
  namespace = local.observability_namespace
  chart     = "${path.module}/charts/thanos"
  # Pinned so a Chart.yaml bump shows in the plan (see lb_controller.tf).
  version          = yamldecode(file("${path.module}/charts/thanos/Chart.yaml")).version
  create_namespace = true
  upgrade_install  = true

  values = concat([yamlencode({
    image             = var.thanos_image
    objstoreConfig    = local.thanos_objstore_config
    prometheusRelease = local.prometheus_release_name
    retentionDays     = local.prometheus_config.s3_retention_days
    compactor = {
      storageClass = local.prometheus_config.storage_class
    }
  })], local.addon_placement_values, var.thanos_helm_values)

  lifecycle {
    precondition {
      condition     = local.thanos_bucket_name != local.loki_bucket_name && local.thanos_bucket_name != local.tempo_bucket_name
      error_message = "Metrics, logs and traces must use separate dedicated S3 buckets; their compactors cannot safely share a bucket."
    }
  }

  depends_on = [
    helm_release.lb_controller,
    helm_release.ebs_storage,
    helm_release.prometheus,
    aws_eks_pod_identity_association.thanos,
    module.thanos_bucket,
  ]
}
