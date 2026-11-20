locals {
  # GCP label keys and values allow only lowercase letters, numbers, hyphens,
  # and underscores, up to 63 characters.
  default_labels = {
    managed-by = "terraform"
    module     = "networking-gcp-network-lb"
  }
  labels = {
    for key, value in merge(local.default_labels, var.labels) :
    substr(replace(lower(key), "/[^a-z0-9_-]/", "-"), 0, 63) => substr(replace(lower(value), "/[^a-z0-9_-]/", "-"), 0, 63)
  }

  scheme = var.internal_load_balancer_enabled ? "INTERNAL" : "EXTERNAL"

  # Google's health checkers probe from these ranges.
  # https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  health_check_source_ranges = (
    var.internal_load_balancer_enabled
    ? ["35.191.0.0/16", "130.211.0.0/22"]
    : ["35.191.0.0/16", "209.85.152.0/22", "209.85.204.0/22"]
  )

  firewall_protocol = var.protocol == "L3_DEFAULT" ? "all" : lower(var.protocol)

  ip_address = var.ip_address_creation_enabled ? google_compute_address.this[0].address : var.ip_address
}
