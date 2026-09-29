################################################################################
# AWS Cloud Map Service Discovery
#
# Every running task is registered as an A record at otlp.<name>.internal, so
# senders keep one hostname while tasks are replaced.
################################################################################

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "${var.name}.internal"
  description = "Private DNS for OpenTelemetry collector ${var.name}."
  vpc         = var.vpc_id

  tags = local.tags
}

resource "aws_service_discovery_service" "this" {
  name = "otlp"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.this.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  # ECS reports each task's container health check result to Cloud Map, so an
  # unhealthy task drops out of DNS.
  health_check_custom_config {}

  # ECS deregisters tasks asynchronously; without this a destroy can race it.
  force_destroy = true

  tags = local.tags
}
