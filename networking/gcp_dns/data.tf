data "google_dns_managed_zone" "existing" {
  count = var.zone_creation_enabled ? 0 : 1

  name = var.zone_name
}

data "google_dns_keys" "this" {
  count = local.dnssec_active ? 1 : 0

  managed_zone = google_dns_managed_zone.this[0].id
}
