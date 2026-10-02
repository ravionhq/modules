mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.66.0-eksbuild.1" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-cluster-observability" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      version               = "1.36"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
}
mock_provider "helm" {}
mock_provider "ravion" {}

variables {
  cluster_name      = "test-cluster"
  region            = "us-east-2"
  karpenter_enabled = false
  eso_enabled       = false
  logs_providers    = []
}

# Also consumed by test_s3_observability_charts.mjs to render the actual pinned
# charts with these Terraform-derived values, not a hand-maintained fixture.
run "render_contract" {
  command = plan
  variables {
    grafana_enabled = true
  }
  assert {
    condition     = output.prometheus_s3_bucket == "ravion-metrics-test-cluster-123456789012" && output.tempo_s3_bucket == "ravion-traces-test-cluster-123456789012"
    error_message = "Each signal needs a dedicated account-unique bucket."
  }
  assert {
    condition     = output.prometheus_endpoint != trimsuffix(output.prometheus_remote_write_endpoint, "/api/v1/write")
    error_message = "Queries must go to Thanos; writes must go to Prometheus."
  }
  assert {
    condition     = yamldecode(helm_release.prometheus[0].values[0]).server.sidecarContainers.thanos.volumeMounts[0].name == "storage-volume" && contains(yamldecode(helm_release.prometheus[0].values[0]).server.extraFlags, "storage.tsdb.max-block-duration=2h")
    error_message = "Sidecar must share the existing PVC and ship uncompacted blocks."
  }
  assert {
    condition     = yamldecode(local.thanos_objstore_config).config.aws_sdk_auth && !yamldecode(local.thanos_objstore_config).config.insecure
    error_message = "S3 access must use Pod Identity over TLS."
  }
  assert {
    condition     = data.aws_iam_policy_document.thanos_s3["store"].statement[1].actions == toset(["s3:GetObject"]) && !contains(data.aws_iam_policy_document.thanos_s3["sidecar"].statement[1].actions, "s3:DeleteObject") && contains(data.aws_iam_policy_document.thanos_s3["compactor"].statement[1].actions, "s3:DeleteObject")
    error_message = "Store is read-only; only the compactor may delete metrics objects."
  }
  assert {
    condition     = data.aws_iam_policy_document.tempo_s3[0].statement[1].resources == toset(["arn:aws:s3:::ravion-traces-test-cluster-123456789012/*"])
    error_message = "Tempo permissions must be scoped to its bucket."
  }
  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.retention == "168h" && yamldecode(helm_release.tempo[0].values[0]).persistence.enabled && yamldecode(helm_release.tempo[0].values[0]).persistence.storageClassName == "gp3"
    error_message = "Tempo defaults to seven days and a persistent gp3 WAL."
  }
  assert {
    condition     = output.traces_otlp_http_endpoint == "http://ravion-otel-traces.ravion-operator.svc.cluster.local:4318" && output.traces_otlp_grpc_endpoint == "http://ravion-otel-traces.ravion-operator.svc.cluster.local:4317"
    error_message = "Publish the OTLP collector base URLs, not Tempo's query URL."
  }
  assert {
    condition     = yamldecode(helm_release.otel_traces_collector[0].values[0]).config.service.pipelines.traces.exporters == ["otlp_grpc/tempo"] && yamldecode(helm_release.otel_traces_collector[0].values[0]).config.service.pipelines.metrics == null
    error_message = "The trace receiver must forward only traces, without a duplicate metric scraper."
  }
  assert {
    condition     = length(local.grafana_datasources) == 2 && local.grafana_datasources[0].url == output.prometheus_endpoint && local.grafana_datasources[1].uid == "ravion-tempo"
    error_message = "Grafana must provision selected Prometheus/Thanos and Tempo stores."
  }
}

run "existing_buckets_and_retention" {
  command = plan
  variables {
    metrics_prometheus = {
      s3_bucket_name    = "existing-dedicated-metrics"
      s3_retention_days = 90
    }
    traces_tempo = {
      s3_bucket_name = "existing-dedicated-traces"
      retention_days = 14
      storage_size   = "20Gi"
    }
  }
  assert {
    condition     = length(module.thanos_bucket) == 0 && length(module.tempo_bucket) == 0 && output.prometheus_s3_bucket == "existing-dedicated-metrics" && output.tempo_s3_bucket == "existing-dedicated-traces"
    error_message = "Existing buckets must be reused without lifecycle or ownership changes."
  }
  assert {
    condition     = yamldecode(helm_release.thanos[0].values[0]).retentionDays == 90 && yamldecode(helm_release.tempo[0].values[0]).tempo.retention == "336h"
    error_message = "Retention must reach both compactors."
  }
}

run "local_only_prometheus" {
  command = plan
  variables {
    traces_providers   = []
    metrics_prometheus = { s3_storage_enabled = false }
  }
  assert {
    condition     = length(helm_release.thanos) == 0 && length(module.thanos_role) == 0 && output.prometheus_s3_bucket == null && length(module.thanos_bucket) == 0
    error_message = "Local-only mode must remove every managed Thanos resource."
  }
  assert {
    condition     = output.prometheus_endpoint == "http://ravion-prometheus-server.ravion-operator.svc.cluster.local:9090" && length(yamldecode(helm_release.prometheus[0].values[0]).server.sidecarContainers) == 0
    error_message = "Without S3, queries must go directly to Prometheus and no sidecar may run."
  }
}

run "existing_prometheus_skips_all_managed_metrics_storage" {
  command = plan
  variables {
    traces_providers   = []
    metrics_prometheus = { endpoint = "https://prometheus.example.com/" }
  }
  assert {
    condition     = length(helm_release.prometheus) == 0 && length(helm_release.thanos) == 0 && length(module.thanos_bucket) == 0 && length(module.thanos_role) == 0
    error_message = "An existing endpoint must skip all managed metrics storage."
  }
  assert {
    condition     = output.prometheus_remote_write_endpoint == "https://prometheus.example.com/api/v1/write"
    error_message = "An endpoint with a trailing slash must not produce a double slash."
  }
}

run "traces_only_grafana" {
  command = plan
  variables {
    metrics_providers = []
    grafana_enabled   = true
  }
  assert {
    condition     = length(local.grafana_datasources) == 1 && local.grafana_datasources[0].uid == "ravion-tempo" && local.grafana_datasources[0].isDefault
    error_message = "Tempo alone must be a valid Grafana datasource selection."
  }
}

run "custom_storage_provisioner" {
  command = plan
  variables {
    ebs_csi_driver_enabled = false
    metrics_prometheus     = { storage_class = "existing-encrypted-class" }
    traces_tempo           = { storage_class = "existing-encrypted-class" }
  }
  assert {
    condition     = yamldecode(helm_release.prometheus[0].values[0]).server.persistentVolume.storageClass == "existing-encrypted-class" && yamldecode(helm_release.tempo[0].values[0]).persistence.storageClassName == "existing-encrypted-class" && yamldecode(helm_release.thanos[0].values[0]).compactor.storageClass == "existing-encrypted-class"
    error_message = "All persistent stores must support a customer-supplied StorageClass."
  }
}

run "invalid_trace_retention" {
  command = plan
  variables {
    traces_tempo = { retention_days = 0 }
  }
  expect_failures = [var.traces_tempo]
}

run "invalid_metrics_retention" {
  command = plan
  variables {
    metrics_prometheus = { s3_retention_days = 0 }
  }
  expect_failures = [var.metrics_prometheus]
}

run "shared_buckets_are_refused" {
  command = plan
  variables {
    metrics_prometheus = { s3_bucket_name = "shared-observability" }
    traces_tempo       = { s3_bucket_name = "shared-observability" }
  }
  expect_failures = [helm_release.thanos, helm_release.tempo]
}

run "empty_bucket_name_is_not_an_existing_bucket" {
  command = plan
  variables {
    traces_tempo = { s3_bucket_name = "" }
  }
  expect_failures = [var.traces_tempo]
}

run "unknown_trace_provider_is_refused" {
  command = plan
  variables {
    traces_providers = ["unknown"]
  }
  expect_failures = [var.traces_providers]
}
