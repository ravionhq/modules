################################################################################
# Firewall rules
################################################################################

# GCP has no security group object to attach. Ingress is denied and egress is
# allowed by default, and each workload module creates the rules it needs,
# targeting its instances by network tag or service account. These rules are
# for traffic no module opens.

resource "google_compute_firewall" "internal_ingress" {
  count = var.firewall_internal_ingress_enabled ? 1 : 0

  name          = "${var.name}-allow-internal"
  description   = "Allow ingress from this network's own ranges. Managed by Terraform (networking/gcp_vpc)."
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  priority      = 65000
  source_ranges = local.internal_ranges

  allow {
    protocol = "all"
  }
}

resource "google_compute_firewall" "this" {
  for_each = var.firewall_rules

  name        = "${var.name}-${each.key}"
  description = coalesce(each.value.description, "Managed by Terraform (networking/gcp_vpc).")
  network     = google_compute_network.this.id
  direction   = each.value.direction
  priority    = each.value.priority

  source_ranges           = each.value.direction == "INGRESS" && length(each.value.source_ranges) > 0 ? each.value.source_ranges : null
  destination_ranges      = each.value.direction == "EGRESS" ? each.value.destination_ranges : null
  source_tags             = length(each.value.source_tags) > 0 ? each.value.source_tags : null
  source_service_accounts = length(each.value.source_service_accounts) > 0 ? each.value.source_service_accounts : null
  target_tags             = length(each.value.target_tags) > 0 ? each.value.target_tags : null
  target_service_accounts = length(each.value.target_service_accounts) > 0 ? each.value.target_service_accounts : null

  dynamic "allow" {
    for_each = each.value.action == "allow" ? [1] : []

    content {
      protocol = each.value.protocol
      ports    = length(each.value.ports) > 0 ? each.value.ports : null
    }
  }

  dynamic "deny" {
    for_each = each.value.action == "deny" ? [1] : []

    content {
      protocol = each.value.protocol
      ports    = length(each.value.ports) > 0 ? each.value.ports : null
    }
  }

  dynamic "log_config" {
    for_each = each.value.logging_enabled ? [1] : []

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}
