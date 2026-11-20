################################################################################
# Cloud Router and Cloud NAT
################################################################################

resource "google_compute_address" "nat" {
  for_each = local.nat_reserved_addresses

  name         = each.value.name
  description  = "Cloud NAT address. Managed by Terraform (networking/gcp_vpc)."
  region       = each.value.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  depends_on = [google_project_service.compute]
}

resource "google_compute_router" "this" {
  for_each = local.nat_regions

  name    = "${var.name}-router-${each.key}"
  network = google_compute_network.this.id
  region  = each.key
}

resource "google_compute_router_nat" "this" {
  for_each = local.nat_regions

  name   = "${var.name}-nat-${each.key}"
  router = google_compute_router.this[each.key].name
  region = each.key

  nat_ip_allocate_option = length(local.nat_ip_self_links[each.key]) > 0 ? "MANUAL_ONLY" : "AUTO_ONLY"
  nat_ips                = local.nat_ip_self_links[each.key]

  # Only the workload subnetwork is translated, including its GKE secondary
  # ranges. Proxy-only subnetworks reach backends directly.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.this[each.key].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  min_ports_per_vm = var.nat_min_ports_per_vm

  log_config {
    enable = var.nat_logging_enabled
    filter = var.nat_logging_filter
  }
}
