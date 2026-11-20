################################################################################
# Private Service Access
################################################################################

# An internal range peered to Google's service producer network. Cloud SQL,
# AlloyDB, Memorystore, and Filestore allocate their private IP addresses
# from it.
resource "google_compute_global_address" "private_service_access" {
  count = var.private_service_access_enabled ? 1 : 0

  name          = "${var.name}-psa"
  description   = "Private Service Access range. Managed by Terraform (networking/gcp_vpc)."
  network       = google_compute_network.this.id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", local.private_service_access_cidr)[0]
  prefix_length = tonumber(split("/", local.private_service_access_cidr)[1])
}

resource "google_service_networking_connection" "private_service_access" {
  count = var.private_service_access_enabled ? 1 : 0

  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access[0].name]
  deletion_policy         = var.private_service_access_deletion_policy

  depends_on = [google_project_service.servicenetworking]
}
