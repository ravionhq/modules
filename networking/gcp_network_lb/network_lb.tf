################################################################################
# Health check
################################################################################

resource "google_compute_region_health_check" "this" {
  name                = "${var.name}-hc"
  region              = var.region
  check_interval_sec  = var.health_check.interval_seconds
  timeout_sec         = var.health_check.timeout_seconds
  healthy_threshold   = var.health_check.healthy_threshold
  unhealthy_threshold = var.health_check.unhealthy_threshold

  dynamic "tcp_health_check" {
    for_each = var.health_check.protocol == "TCP" ? [1] : []

    content {
      port = var.health_check.port
    }
  }

  dynamic "http_health_check" {
    for_each = var.health_check.protocol == "HTTP" ? [1] : []

    content {
      port         = var.health_check.port
      request_path = var.health_check.request_path
    }
  }

  dynamic "https_health_check" {
    for_each = var.health_check.protocol == "HTTPS" ? [1] : []

    content {
      port         = var.health_check.port
      request_path = var.health_check.request_path
    }
  }
}

################################################################################
# Backend service
################################################################################

resource "google_compute_region_backend_service" "this" {
  name                            = "${var.name}-backend"
  description                     = "Managed by Terraform (networking/gcp_network_lb)."
  region                          = var.region
  load_balancing_scheme           = local.scheme
  protocol                        = var.protocol == "L3_DEFAULT" ? "UNSPECIFIED" : var.protocol
  network                         = var.internal_load_balancer_enabled ? var.network : null
  health_checks                   = [google_compute_region_health_check.this.id]
  session_affinity                = var.session_affinity
  connection_draining_timeout_sec = var.connection_draining_timeout_seconds

  dynamic "backend" {
    for_each = var.backends

    content {
      group          = backend.value.group
      balancing_mode = "CONNECTION"
      failover       = var.internal_load_balancer_enabled ? backend.value.failover : null
    }
  }

  log_config {
    enable      = var.logging_enabled
    sample_rate = var.logging_enabled ? var.logging_sample_rate : null
  }

  lifecycle {
    precondition {
      condition     = var.internal_load_balancer_enabled || alltrue([for backend in var.backends : !backend.failover])
      error_message = "Failover backends are only supported on internal load balancers."
    }
  }
}

################################################################################
# Forwarding rule
################################################################################

resource "google_compute_forwarding_rule" "this" {
  name                  = "${var.name}-fr"
  description           = "Managed by Terraform (networking/gcp_network_lb)."
  region                = var.region
  load_balancing_scheme = local.scheme
  backend_service       = google_compute_region_backend_service.this.id
  ip_protocol           = var.protocol
  ip_address            = local.ip_address
  ports                 = length(var.ports) > 0 ? var.ports : null
  all_ports             = length(var.ports) == 0 ? true : null
  network_tier          = var.internal_load_balancer_enabled ? null : var.network_tier

  network             = var.internal_load_balancer_enabled ? var.network : null
  subnetwork          = var.internal_load_balancer_enabled ? var.subnetwork : null
  allow_global_access = var.internal_load_balancer_enabled ? var.global_access_enabled : null

  lifecycle {
    precondition {
      condition     = !var.internal_load_balancer_enabled || var.subnetwork != null
      error_message = "subnetwork is required for an internal load balancer."
    }
  }
}
