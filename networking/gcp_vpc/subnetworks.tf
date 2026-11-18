################################################################################
# Subnetworks
################################################################################

# One subnetwork per region. GCP subnetworks are neither public nor private:
# a resource is public only when it has an external IP address. Workloads
# without one reach the internet through Cloud NAT and Google APIs through
# Private Google Access.
resource "google_compute_subnetwork" "this" {
  for_each = local.region_ranges

  name                     = each.value.subnet_name
  description              = "Managed by Terraform (networking/gcp_vpc)."
  network                  = google_compute_network.this.id
  region                   = each.key
  ip_cidr_range            = each.value.primary
  private_ip_google_access = var.private_google_access_enabled

  dynamic "secondary_ip_range" {
    for_each = var.subnetwork_secondary_ranges_enabled ? {
      (local.pods_secondary_range_name)     = each.value.pods
      (local.services_secondary_range_name) = each.value.services
    } : {}

    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }

  dynamic "log_config" {
    for_each = var.flow_logs_enabled ? [1] : []

    content {
      aggregation_interval = var.flow_logs_aggregation_interval
      flow_sampling        = var.flow_logs_sampling
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

################################################################################
# Proxy-only subnetworks
################################################################################

resource "google_compute_subnetwork" "proxy_only" {
  for_each = var.proxy_only_subnetwork_creation_enabled ? local.region_ranges : {}

  name          = "${var.name}-proxy-${each.key}"
  description   = "Proxy-only subnetwork for regional Envoy-based load balancers. Managed by Terraform (networking/gcp_vpc)."
  network       = google_compute_network.this.id
  region        = each.key
  ip_cidr_range = each.value.proxy_only
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}
