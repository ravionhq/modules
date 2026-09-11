################################################################################
# OpenTelemetry collector → Amazon Managed Prometheus (Helm)
#
# A single-replica Deployment running the AWS Distro for OpenTelemetry image
# under the community opentelemetry-collector chart. It scrapes three targets —
# cAdvisor and the kubelet's resource endpoint on every node, through the API
# server proxy, and kube-state-metrics in-cluster — keeps the curated allow-list
# in locals.tf, and remote-writes the survivors to AMP signed with SigV4.
#
# Three things about the shape of this file:
#
#   1. IT IS A HELM RELEASE, NOT THE ADOT EKS ADD-ON. The add-on installs an
#      operator and CRDs, wants cert-manager, and then needs an
#      OpenTelemetryCollector custom resource applied with plan-time cluster
#      connectivity to configure the pipeline at all. A values-driven release is
#      how Karpenter and the External Secrets Operator are installed here.
#
#   2. THE ALLOW-LIST IS THE DESIGN, NOT A TUNING KNOB. AMP bills per sample.
#      Everything outside locals.metrics_*_allowlist is dropped in
#      metric_relabel_configs, which runs before samples enter collector memory,
#      so widening it is the difference between a bill of tens and hundreds of
#      dollars a month. var.metrics_additional_allowlist is the supported way.
#
#   3. ONE REPLICA SCRAPES EVERY NODE. Fine to roughly 100 nodes at a 60s
#      interval. Past that the answer is the chart's target allocator with a
#      StatefulSet, which is deliberately not in this release.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  otel_collector_name = "ravion-otel-collector"

  # Null limits are omitted rather than rendered as null, which Helm would read
  # as "delete this key" — harmless here, but the pod spec is clearer without.
  otel_collector_resource_limits = merge(
    var.otel_collector_resources.cpu_limit == null ? {} : { cpu = var.otel_collector_resources.cpu_limit },
    var.otel_collector_resources.memory_limit == null ? {} : { memory = var.otel_collector_resources.memory_limit },
  )

  otel_collector_resource_requests = merge(
    var.otel_collector_resources.cpu_request == null ? {} : { cpu = var.otel_collector_resources.cpu_request },
    var.otel_collector_resources.memory_request == null ? {} : { memory = var.otel_collector_resources.memory_request },
  )

  otel_collector_resources = merge(
    length(local.otel_collector_resource_requests) > 0 ? { requests = local.otel_collector_resource_requests } : {},
    length(local.otel_collector_resource_limits) > 0 ? { limits = local.otel_collector_resource_limits } : {},
  )

  # One exporter per selected provider. Keys are the collector's component ids;
  # `debug = null` deletes the chart's default exporter.
  otel_metrics_exporters = merge(
    { debug = null },
    local.amp_enabled ? {
      "prometheusremotewrite/amp" = {
        endpoint = local.amp_remote_write_endpoint
        auth = {
          authenticator = "sigv4auth"
        }
        # AMP rejects samples older than an hour; retrying past that only burns
        # the queue, so failures are dropped rather than blocking newer batches.
        retry_on_failure = {
          enabled          = true
          initial_interval = "5s"
          max_interval     = "30s"
          max_elapsed_time = "300s"
        }
        resource_to_telemetry_conversion = {
          enabled = false
        }
      }
    } : {},
    local.metrics_grafana_cloud_enabled ? {
      "prometheusremotewrite/grafana_cloud" = {
        endpoint = local.grafana_cloud_config.metrics_url
        auth = {
          authenticator = "basicauth/grafana_cloud"
        }
        resource_to_telemetry_conversion = {
          enabled = false
        }
      }
    } : {},
    local.prometheus_enabled ? {
      # The in-cluster store, written to exactly the way AMP is - it is a
      # rendering provider, so the same series have to reach it.
      "prometheusremotewrite/in_cluster" = {
        endpoint = local.prometheus_remote_write_endpoint
        tls = {
          insecure = true
        }
        resource_to_telemetry_conversion = {
          enabled = false
        }
      }
    } : {},
    local.metrics_datadog_enabled ? {
      datadog = {
        api = {
          site = local.datadog_config.site
          key  = "$${env:DATADOG_API_KEY}"
        }
      }
    } : {},
    local.metrics_new_relic_enabled ? {
      "otlphttp/new_relic" = {
        endpoint = local.new_relic_otlp_endpoint
        headers = {
          "api-key" = "$${env:NEW_RELIC_LICENSE_KEY}"
        }
      }
    } : {},
    local.metrics_otlp_enabled ? {
      "otlphttp/custom" = merge(
        { endpoint = local.otlp_metrics_config.endpoint },
        local.otlp_metrics_config.headers_secret_arn == null ? {} : {
          headers = { authorization = "$${env:OTLP_METRICS_AUTHORIZATION}" }
        },
      )
    } : {},
  )

  otel_metrics_extensions = merge(
    local.amp_enabled ? {
      sigv4auth = {
        region  = local.amp_region
        service = "aps"
      }
    } : {},
    local.metrics_grafana_cloud_enabled ? {
      "basicauth/grafana_cloud" = {
        client_auth = {
          username = local.grafana_cloud_config.metrics_user
          password = "$${env:GRAFANA_CLOUD_TOKEN}"
        }
      }
    } : {},
  )

  otel_metrics_pipeline_exporters = [for name, _ in local.otel_metrics_exporters : name if name != "debug"]

  otel_collector_extra_envs = [
    for secret in local.otel_metrics_secret_env : {
      name = secret.environment
      valueFrom = {
        secretKeyRef = {
          name = secret.name
          key  = secret.secret_key
        }
      }
    }
  ]

  otel_collector_values = local.otel_metrics_enabled ? templatefile("${path.module}/templates/otel_values.yaml.tpl", {
    name             = local.otel_collector_name
    replica_count    = 1
    image_repository = local.otel_metrics_image_repository
    image_tag        = local.otel_metrics_image_tag
    command_name     = local.otel_metrics_command_name
    service_account  = var.otel_collector_service_account
    resources        = local.otel_collector_resources
    scrape_interval  = "${var.scrape_interval_seconds}s"
    extra_envs       = local.otel_collector_extra_envs

    exporters          = local.otel_metrics_exporters
    extensions         = local.otel_metrics_extensions
    service_extensions = concat(["health_check"], sort(keys(local.otel_metrics_extensions)))
    pipeline_exporters = sort(local.otel_metrics_pipeline_exporters)

    kube_state_metrics_enabled = local.kube_state_metrics_install
    kube_state_metrics_target  = local.kube_state_metrics_target

    cadvisor_keep_regex         = local.metrics_cadvisor_keep_regex
    kube_state_keep_regex       = local.metrics_kube_state_keep_regex
    kubelet_resource_keep_regex = local.metrics_kubelet_resource_keep_regex
  }) : null
}

resource "helm_release" "otel_collector" {
  count = local.otel_metrics_enabled ? 1 : 0

  name       = local.otel_collector_name
  namespace  = local.metrics_namespace
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.otel_collector_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat([local.otel_collector_values], var.otel_collector_helm_values)

  depends_on = [
    # Service creation must wait for the load balancer admission webhook.
    helm_release.lb_controller,
    # The collector reads AWS credentials on startup through the Pod Identity
    # Agent; without the association it falls back to the node role and every
    # remote write fails with AccessDenied.
    aws_eks_pod_identity_association.otel_collector,
    # Not a hard dependency — a missing target is a failed scrape, not a failed
    # collector — but it keeps the first minutes free of scrape errors.
    helm_release.kube_state_metrics,
    # Remote-writing into a Prometheus that does not exist yet is a retry loop
    # and a page of errors in the first minutes of a cluster's life.
    helm_release.prometheus,
    # A vendor credential that is not materialized yet is a pod that never
    # starts, because the env var references a Secret key.
    helm_release.observability_secrets,
  ]

  lifecycle {
    precondition {
      condition     = !local.metrics_grafana_cloud_enabled || (local.grafana_cloud_config.metrics_url != null && local.grafana_cloud_config.metrics_user != null && local.grafana_cloud_config.token_secret_arn != null)
      error_message = "grafana_cloud is in metrics_providers but its remote-write URL, instance id, or token secret ARN is missing. All three are required: Grafana Cloud authenticates every remote write with basic auth."
    }

    precondition {
      condition     = !local.metrics_datadog_enabled || local.datadog_config.api_key_secret_arn != null
      error_message = "datadog is in metrics_providers but no API key secret ARN was given. The key is read in-cluster from Secrets Manager by External Secrets; without an ARN the collector has nothing to authenticate with."
    }

    precondition {
      condition     = !local.metrics_new_relic_enabled || local.new_relic_config.license_key_secret_arn != null
      error_message = "new_relic is in metrics_providers but no license key secret ARN was given. The key is read in-cluster from Secrets Manager by External Secrets."
    }

    precondition {
      condition     = !local.metrics_otlp_enabled || local.otlp_metrics_config.endpoint != null
      error_message = "otlp is in metrics_providers but no OTLP endpoint was given. There is nowhere to send the metrics."
    }
  }
}
