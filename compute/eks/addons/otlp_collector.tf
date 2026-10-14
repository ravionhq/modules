################################################################################
# OTLP collector — workload traces and metrics (Helm)
#
# A Deployment of its own, apart from the collector that scrapes the cluster
# (otel_collector.tf), so a burst of spans or workload metrics never competes
# with the scrape. It runs while traces are on. Workloads send OTLP to its
# in-cluster Service (otlp_grpc_endpoint, otlp_http_endpoint), and it exports:
#
#   - every trace to each traces destination, and
#   - workload metrics to the metrics destinations while metrics are on,
#     without the scrape allow-list, so every series a workload sends is billed.
#
# THE RECEIVER AUTHENTICATES NO SENDER. Any pod that reaches the Service can
# send spans and metrics under any service name, and they reach the
# destinations as sent: every workload in the cluster is trusted with this
# data. Where that does not hold, restrict who reaches the collector with a
# NetworkPolicy.
#
# Spans and metrics carry the sending pod's Kubernetes attributes (namespace,
# pod, workload) from the chart's kubernetesAttributes preset, which reads pods,
# namespaces and ReplicaSets. The image is always the contrib distribution: it
# has every exporter and the k8s_attributes processor.
################################################################################

locals {
  otlp_collector_name    = "ravion-otel-otlp"
  otlp_collector_enabled = local.traces_on

  otlp_service_host  = "${local.otlp_collector_name}.${local.metrics_namespace}.svc.cluster.local"
  otlp_grpc_endpoint = local.otlp_collector_enabled ? "http://${local.otlp_service_host}:4317" : null
  otlp_http_endpoint = local.otlp_collector_enabled ? "http://${local.otlp_service_host}:4318" : null
  xray_region        = coalesce(try(trimspace(local.trace.xray.region), ""), var.region, data.aws_region.current.region)

  # Workload metrics go where the scraped ones do, while metrics are on.
  otlp_metrics_enabled = local.otlp_collector_enabled && local.otel_metrics_enabled

  # One exporter per traces destination. A vendor that is also a metrics
  # destination shares the metrics exporter's id: one account, one exporter.
  otel_traces_exporters = merge(
    local.xray_enabled ? {
      awsxray = {
        region = local.xray_region
      }
    } : {},
    local.tempo_enabled ? {
      # Plain gRPC inside the cluster, to the same ClusterIP Service Grafana
      # reads. Tempo restarting (a release reinstall, a node replacement) is
      # ridden out by the queue and retries rather than dropping spans.
      "otlp_grpc/tempo" = {
        endpoint = local.tempo_otlp_grpc_host
        tls = {
          insecure = true
        }
        sending_queue = {
          enabled    = true
          queue_size = 1000
        }
        retry_on_failure = {
          enabled          = true
          initial_interval = "5s"
          max_interval     = "30s"
          max_elapsed_time = "300s"
        }
      }
    } : {},
    local.traces_grafana_cloud_enabled ? {
      "otlp_http/grafana_cloud_traces" = {
        endpoint = local.grafana_cloud_config.traces_url
        auth = {
          authenticator = "basicauth/grafana_cloud_traces"
        }
      }
    } : {},
    local.traces_datadog_enabled ? {
      datadog = {
        api = {
          site = local.datadog_config.site
          key  = "$${env:DATADOG_API_KEY}"
        }
      }
    } : {},
    local.traces_new_relic_enabled ? {
      "otlp_http/new_relic" = {
        endpoint = local.new_relic_otlp_endpoint
        headers = {
          "api-key" = "$${env:NEW_RELIC_LICENSE_KEY}"
        }
      }
    } : {},
    local.traces_otlp_enabled ? {
      "otlp_http/custom_traces" = merge(
        { endpoint = local.otlp_traces_config.endpoint },
        local.otlp_traces_config.headers_secret_arn == null ? {} : {
          headers = { authorization = "$${env:OTLP_TRACES_AUTHORIZATION}" }
        },
      )
    } : {},
  )

  # For expressions rather than conditionals, because the shapes differ.
  otlp_collector_exporters = merge(
    { debug = null },
    { for name, exporter in local.otel_metrics_exporters : name => exporter if local.otlp_metrics_enabled && exporter != null },
    local.otel_traces_exporters,
  )

  otlp_collector_extensions = merge(
    { for name, extension in local.otel_metrics_extensions : name => extension if local.otlp_metrics_enabled },
    # Grafana Cloud's traces instance has an id of its own.
    local.traces_grafana_cloud_enabled ? {
      "basicauth/grafana_cloud_traces" = {
        client_auth = {
          username = local.grafana_cloud_config.traces_user
          password = "$${env:GRAFANA_CLOUD_TOKEN}"
        }
      }
    } : {},
  )

  otlp_collector_pipelines = merge(
    {
      logs = null
      traces = {
        receivers  = ["otlp"]
        processors = ["memory_limiter", "batch"]
        exporters  = sort(keys(local.otel_traces_exporters))
      }
    },
    {
      metrics = local.otlp_metrics_enabled ? {
        receivers  = ["otlp"]
        processors = ["memory_limiter", "batch"]
        exporters  = sort(local.otel_metrics_pipeline_exporters)
      } : null
    },
  )

  otlp_collector_role_enabled = local.otlp_collector_enabled && (local.xray_enabled || (local.otlp_metrics_enabled && local.amp_enabled))
}

################################################################################
# AWS access: X-Ray for traces, AMP remote write for workload metrics
################################################################################

data "aws_iam_policy_document" "otlp_collector" {
  count = local.otlp_collector_role_enabled ? 1 : 0

  # X-Ray has no resource-level permissions for these actions.
  dynamic "statement" {
    for_each = local.xray_enabled ? [1] : []
    content {
      sid       = "WriteTraces"
      effect    = "Allow"
      actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = local.otlp_metrics_enabled && local.amp_enabled ? [1] : []
    content {
      sid       = "WriteWorkloadMetrics"
      effect    = "Allow"
      actions   = ["aps:RemoteWrite"]
      resources = [local.amp_workspace_arn]
    }
  }
}

module "otlp_collector_role" {
  count = local.otlp_collector_role_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${local.name}-otel-otlp"
  description = "OTLP collector Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "otlp-collector" = data.aws_iam_policy_document.otlp_collector[0].json
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "otlp_collector" {
  count = local.otlp_collector_role_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.metrics_namespace
  service_account = local.otlp_collector_name
  role_arn        = module.otlp_collector_role[0].role_arn

  tags = local.tags
}

################################################################################
# Collector
################################################################################

resource "helm_release" "otlp_collector" {
  count = local.otlp_collector_enabled ? 1 : 0

  name       = local.otlp_collector_name
  namespace  = local.metrics_namespace
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.otel_collector_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        mode             = "deployment"
        replicaCount     = 1
        fullnameOverride = local.otlp_collector_name

        image = {
          repository = var.otel_contrib_image_repository
          tag        = var.otel_contrib_image_tag
        }
        command = {
          name = var.otel_contrib_command_name
        }

        # Must match the Pod Identity association above.
        serviceAccount = {
          create = true
          name   = local.otlp_collector_name
        }

        # The ClusterIP Service carries the two OTLP ports and nothing else.
        service = {
          enabled = true
          type    = "ClusterIP"
        }
        ports = {
          otlp             = { enabled = true }
          "otlp-http"      = { enabled = true }
          "jaeger-compact" = { enabled = false }
          "jaeger-thrift"  = { enabled = false }
          "jaeger-grpc"    = { enabled = false }
          zipkin           = { enabled = false }
          metrics          = { enabled = false }
        }

        presets = {
          kubernetesAttributes = { enabled = true }
        }

        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { memory = "1Gi" }
        }

        extraEnvs = [
          for secret in local.otlp_collector_secret_env : {
            name = secret.environment
            valueFrom = {
              secretKeyRef = {
                name = secret.name
                key  = secret.secret_key
              }
            }
          }
        ]

        config = {
          receivers = {
            jaeger     = null
            zipkin     = null
            prometheus = null
          }
          exporters  = local.otlp_collector_exporters
          extensions = local.otlp_collector_extensions
          service = {
            extensions = concat(["health_check"], sort(keys(local.otlp_collector_extensions)))
            pipelines  = local.otlp_collector_pipelines
          }
        }
      }),
    ],
    local.addon_placement_values,
    var.otlp_collector_helm_values,
  )

  depends_on = [
    helm_release.lb_controller,
    aws_eks_pod_identity_association.otlp_collector,
    # A vendor credential that is not materialized yet is a pod that never
    # starts, because the env var references a Secret key.
    helm_release.observability_secrets,
    helm_release.tempo,
  ]

  lifecycle {
    precondition {
      condition     = !local.traces_grafana_cloud_enabled || (local.grafana_cloud_config.traces_url != null && local.grafana_cloud_config.traces_user != null && local.grafana_cloud_config.token_secret_arn != null)
      error_message = "grafana_cloud is a trace destination but its OTLP endpoint, instance id, or token secret ARN is missing. All three are required: Grafana Cloud authenticates every export with basic auth."
    }

    precondition {
      condition     = !local.traces_datadog_enabled || local.datadog_config.api_key_secret_arn != null
      error_message = "datadog is a trace destination but no API key secret ARN was given. The key is read in-cluster from Secrets Manager by External Secrets."
    }

    precondition {
      condition     = !local.traces_new_relic_enabled || local.new_relic_config.license_key_secret_arn != null
      error_message = "new_relic is a trace destination but no license key secret ARN was given. The key is read in-cluster from Secrets Manager by External Secrets."
    }

    precondition {
      condition     = !local.traces_otlp_enabled || local.otlp_traces_config.endpoint != null
      error_message = "otlp is a trace destination but no OTLP endpoint was given. There is nowhere to send the traces."
    }
  }
}
