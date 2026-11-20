################################################################################
# Firewall rules
################################################################################

# Passthrough load balancers deliver packets with the original source IP, so
# the backends' firewall must allow both Google's health checkers and the
# clients themselves.

resource "google_compute_firewall" "health_checks" {
  count = var.firewall_creation_enabled ? 1 : 0

  name                    = "${var.name}-allow-hc"
  description             = "Allow load balancer health checks. Managed by Terraform (networking/gcp_network_lb)."
  network                 = var.network
  direction               = "INGRESS"
  source_ranges           = local.health_check_source_ranges
  target_tags             = length(var.target_tags) > 0 ? var.target_tags : null
  target_service_accounts = length(var.target_service_accounts) > 0 ? var.target_service_accounts : null

  allow {
    protocol = "tcp"
    ports    = [tostring(var.health_check.port)]
  }
}

resource "google_compute_firewall" "clients" {
  count = var.firewall_creation_enabled && length(var.ingress_source_ranges) > 0 ? 1 : 0

  name                    = "${var.name}-allow-clients"
  description             = "Allow clients through the load balancer. Managed by Terraform (networking/gcp_network_lb)."
  network                 = var.network
  direction               = "INGRESS"
  source_ranges           = var.ingress_source_ranges
  target_tags             = length(var.target_tags) > 0 ? var.target_tags : null
  target_service_accounts = length(var.target_service_accounts) > 0 ? var.target_service_accounts : null

  allow {
    protocol = local.firewall_protocol
    ports    = local.firewall_protocol != "all" && length(var.ports) > 0 ? var.ports : null
  }
}
