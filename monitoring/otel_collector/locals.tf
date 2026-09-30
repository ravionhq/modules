################################################################################
# Local Values
################################################################################

locals {
  region = coalesce(var.region, data.aws_region.current.region)

  default_tags = {
    ManagedBy = "terraform"
    Module    = "monitoring/otel_collector"
  }

  tags = merge(local.default_tags, var.tags)

  otlp_grpc_port    = 4317
  otlp_http_port    = 4318
  health_check_port = 13133

  hostname = "${aws_service_discovery_service.this.name}.${aws_service_discovery_private_dns_namespace.this.name}"

  log_group_name         = "/ecs/${var.name}"
  log_stream_prefix      = "collector"
  metrics_log_group_name = "/ecs/${var.name}/metrics"
  otlp_log_group_name    = "/ecs/${var.name}/otlp-logs"

  # Where metrics go: none while metrics are disabled.
  metrics_destination = var.metrics_enabled ? var.metrics_destination : "none"

  # A form leaves an unused field blank rather than null.
  metrics_namespace = try(trimspace(var.metrics_namespace), "") == "" ? null : trimspace(var.metrics_namespace)

  collector_config = templatefile("${path.module}/templates/collector.yaml.tftpl", {
    region                      = local.region
    otlp_grpc_port              = local.otlp_grpc_port
    otlp_http_port              = local.otlp_http_port
    health_check_port           = local.health_check_port
    metrics_destination         = local.metrics_destination
    metrics_log_group_name      = local.metrics_log_group_name
    metrics_namespace           = local.metrics_namespace
    prometheus_remote_write_url = var.prometheus_remote_write_url
    logs_enabled                = var.logs_enabled
    otlp_log_group_name         = local.otlp_log_group_name
  })
}
