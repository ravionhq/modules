################################################################################
# DNS server policy (private-zone query logging)
################################################################################

# Cloud DNS logs private-zone queries per network, through a server policy.
# A network can have only one server policy, so this fails if a visibility
# network already has one; turn query logging on in that policy instead.
resource "google_dns_policy" "logging" {
  count = local.server_policy_creation_enabled ? 1 : 0

  name           = coalesce(var.server_policy_name, substr("${local.created_zone_name}-logging", 0, 63))
  description    = "Query logging for ${local.dns_name_input}. Managed by Terraform (networking/gcp_dns)."
  enable_logging = true

  dynamic "networks" {
    for_each = var.private_visibility_networks

    content {
      network_url = networks.value
    }
  }
}
