locals {
  # GCP label keys and values allow only lowercase letters, numbers, hyphens,
  # and underscores, up to 63 characters.
  default_labels = {
    managed-by = "terraform"
    module     = "networking-gcp-dns"
  }
  labels = {
    for key, value in merge(local.default_labels, var.labels) :
    substr(replace(lower(key), "/[^a-z0-9_-]/", "-"), 0, 63) => substr(replace(lower(value), "/[^a-z0-9_-]/", "-"), 0, 63)
  }

  dns_name_input = var.dns_name == null ? null : (endswith(var.dns_name, ".") ? lower(var.dns_name) : "${lower(var.dns_name)}.")

  generated_zone_name = local.dns_name_input == null ? null : substr(trim(replace(trimsuffix(local.dns_name_input, "."), "/[^a-z0-9-]/", "-"), "-"), 0, 63)
  created_zone_name   = coalesce(var.zone_name, local.generated_zone_name, "unset")

  create_public_zone  = var.zone_creation_enabled && !var.private_zone_enabled
  create_private_zone = var.zone_creation_enabled && var.private_zone_enabled

  zone_name = var.zone_creation_enabled ? google_dns_managed_zone.this[0].name : data.google_dns_managed_zone.existing[0].name
  dns_name  = var.zone_creation_enabled ? google_dns_managed_zone.this[0].dns_name : data.google_dns_managed_zone.existing[0].dns_name

  # Normalize names: "@" is the zone apex, a name ending in a dot is fully
  # qualified, a name ending in the zone's domain gets the dot added, and any
  # other name is relative to the zone (app -> app.example.com.).
  zone_domain = trimsuffix(local.dns_name, ".")
  records = {
    for record in var.records : "${record.type} ${record.name}" => merge(record, {
      fqdn = (
        record.name == "@" ? local.dns_name :
        endswith(record.name, ".") ? lower(record.name) :
        lower(record.name) == local.zone_domain || endswith(lower(record.name), ".${local.zone_domain}") ? "${lower(record.name)}." :
        "${lower(record.name)}.${local.dns_name}"
      )
    })
  }

  dnssec_active = local.create_public_zone && var.dnssec_enabled

  server_policy_creation_enabled = local.create_private_zone && var.query_logging_enabled
}
