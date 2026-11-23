################################################################################
# Managed zone
################################################################################

resource "google_dns_managed_zone" "this" {
  count = var.zone_creation_enabled ? 1 : 0

  name          = local.created_zone_name
  dns_name      = local.dns_name_input
  description   = var.description
  visibility    = var.private_zone_enabled ? "private" : "public"
  force_destroy = var.record_force_destroy_enabled

  dynamic "private_visibility_config" {
    for_each = var.private_zone_enabled ? [1] : []

    content {
      dynamic "networks" {
        for_each = var.private_visibility_networks

        content {
          network_url = networks.value
        }
      }
    }
  }

  dynamic "dnssec_config" {
    for_each = local.create_public_zone ? [1] : []

    content {
      state         = var.dnssec_enabled ? "on" : "off"
      non_existence = var.dnssec_enabled ? var.dnssec_non_existence : null
    }
  }

  # Cloud Logging for public zones. Private zones log through a DNS server
  # policy on the networks instead (server_policy.tf).
  dynamic "cloud_logging_config" {
    for_each = local.create_public_zone ? [1] : []

    content {
      enable_logging = var.query_logging_enabled
    }
  }

  lifecycle {
    precondition {
      condition     = var.dns_name != null
      error_message = "dns_name is required when zone_creation_enabled is true."
    }
    precondition {
      condition     = !var.private_zone_enabled || length(var.private_visibility_networks) > 0
      error_message = "A private zone needs at least one network in private_visibility_networks."
    }
  }
}
