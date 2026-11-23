################################################################################
# Zone
################################################################################

output "project_id" {
  description = "The Google Cloud project ID that owns the zone."
  value       = var.project_id
}

output "zone_name" {
  description = "Name of the managed zone resource."
  value       = local.zone_name
}

output "zone_id" {
  description = "ID of the managed zone (projects/<project>/managedZones/<name>)."
  value       = var.zone_creation_enabled ? google_dns_managed_zone.this[0].id : data.google_dns_managed_zone.existing[0].id
}

output "dns_name" {
  description = "Domain the zone serves, with a trailing dot."
  value       = local.dns_name
}

output "name_servers" {
  description = "Name servers of the zone. Delegate to these from the registrar or parent zone for a public zone."
  value       = var.zone_creation_enabled ? google_dns_managed_zone.this[0].name_servers : data.google_dns_managed_zone.existing[0].name_servers
}

output "is_private_zone" {
  description = "Whether the zone is private."
  value       = var.zone_creation_enabled ? var.private_zone_enabled : data.google_dns_managed_zone.existing[0].visibility == "private"
}

################################################################################
# Records
################################################################################

output "record_names" {
  description = "Map of record keys (\"<type> <name>\") to fully qualified record names."
  value       = { for key, record in google_dns_record_set.this : key => record.name }
}

################################################################################
# DNSSEC
################################################################################

output "dnssec_ds_records" {
  description = "DS records to publish at the registrar or parent zone once DNSSEC is on (empty otherwise)."
  value       = local.dnssec_active ? [for key in data.google_dns_keys.this[0].key_signing_keys : key.ds_record] : []
}

################################################################################
# Logging
################################################################################

output "server_policy_name" {
  description = "Name of the DNS server policy created for private-zone query logging (null when not created)."
  value       = local.server_policy_creation_enabled ? google_dns_policy.logging[0].name : null
}
