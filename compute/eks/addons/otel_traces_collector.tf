################################################################################
# OTLP traces -> Tempo. A separate receiver, never the metrics scrape collector.
# Workloads set OTEL_EXPORTER_OTLP_ENDPOINT to one of the published endpoints.
# No injection webhook, automatic workload restart, or implicit sampling.
################################################################################

locals {
  otel_traces_collector_name = "ravion-otel-traces"
  otel_traces_service_host   = "${local.otel_traces_collector_name}.${local.observability_namespace}.svc.cluster.local"
  traces_otlp_grpc_endpoint  = local.tempo_enabled ? "http://${local.otel_traces_service_host}:4317" : null
  traces_otlp_http_endpoint  = local.tempo_enabled ? "http://${local.otel_traces_service_host}:4318" : null
}

resource "helm_release" "otel_traces_collector" {
  count = local.tempo_enabled ? 1 : 0

  name             = local.otel_traces_collector_name
  namespace        = local.observability_namespace
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = var.otel_collector_chart_version
  create_namespace = true
  upgrade_install  = true

  values = concat([yamlencode({
    mode             = "deployment"
    replicaCount     = 1
    fullnameOverride = local.otel_traces_collector_name
    image = {
      repository = var.otel_contrib_image_repository
      tag        = var.otel_contrib_image_tag
    }
    command        = { name = var.otel_contrib_command_name }
    serviceAccount = { create = true, name = local.otel_traces_collector_name }
    service        = { enabled = true, type = "ClusterIP" }
    presets = {
      kubernetesAttributes = { enabled = true }
    }
    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { memory = "512Mi" }
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
    config = {
      receivers = {
        jaeger     = null
        zipkin     = null
        prometheus = null
        otlp = {
          protocols = {
            grpc = { endpoint = "0.0.0.0:4317" }
            http = { endpoint = "0.0.0.0:4318" }
          }
        }
      }
      processors = {
        memory_limiter = { check_interval = "1s", limit_percentage = 75, spike_limit_percentage = 15 }
        batch          = { timeout = "5s", send_batch_size = 512 }
      }
      exporters = {
        debug = null
        "otlp_grpc/tempo" = {
          endpoint      = "${local.tempo_service_host}:4317"
          tls           = { insecure = true }
          sending_queue = { enabled = true, queue_size = 1000 }
          retry_on_failure = {
            enabled          = true
            initial_interval = "5s"
            max_interval     = "30s"
            max_elapsed_time = "300s"
          }
        }
      }
      extensions = { health_check = { endpoint = "0.0.0.0:13133" } }
      service = {
        extensions = ["health_check"]
        pipelines = {
          logs    = null
          metrics = null
          traces = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "k8s_attributes", "batch"]
            exporters  = ["otlp_grpc/tempo"]
          }
        }
      }
    }
  })], var.otel_traces_collector_helm_values)

  depends_on = [helm_release.lb_controller, helm_release.tempo]
}
