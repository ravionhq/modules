################################################################################
# AWS Cloud Map Service Discovery
################################################################################

resource "aws_service_discovery_service" "this" {
  count = local.enable_service_discovery ? 1 : 0

  name = var.name

  dns_config {
    namespace_id   = var.service_discovery.namespace_id
    routing_policy = var.service_discovery.routing_policy

    dns_records {
      ttl  = var.service_discovery.dns_ttl
      type = var.service_discovery.dns_record_type
    }
  }

  dynamic "health_check_custom_config" {
    for_each = var.service_discovery.health_check_custom_config != null ? [var.service_discovery.health_check_custom_config] : []
    content {
      failure_threshold = health_check_custom_config.value.failure_threshold
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  # The service name becomes one DNS label under the namespace, so the wider
  # 255-character ECS name limit does not apply here.
  lifecycle {
    precondition {
      condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?$", var.name))
      error_message = "service_discovery requires name to be a single DNS label of at most 63 letters, numbers, hyphens, or underscores."
    }
  }
}


