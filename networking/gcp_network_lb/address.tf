################################################################################
# Static IP address
################################################################################

resource "google_compute_address" "this" {
  count = var.ip_address_creation_enabled ? 1 : 0

  name         = "${var.name}-ip"
  description  = "Network Load Balancer address. Managed by Terraform (networking/gcp_network_lb)."
  region       = var.region
  address_type = local.scheme
  subnetwork   = var.internal_load_balancer_enabled ? var.subnetwork : null
  network_tier = var.internal_load_balancer_enabled ? null : var.network_tier
}
