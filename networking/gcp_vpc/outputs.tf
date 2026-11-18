################################################################################
# Project & Region
################################################################################

output "project_id" {
  description = "The Google Cloud project ID where the network is deployed."
  value       = var.project_id
}

output "region" {
  description = "The primary region."
  value       = var.region
}

output "regions" {
  description = "Every region with a subnetwork, primary region first."
  value       = local.regions
}

################################################################################
# Network
################################################################################

output "network_id" {
  description = "The ID of the VPC network (projects/<project>/global/networks/<name>)."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "The self link of the VPC network."
  value       = google_compute_network.this.self_link
}

output "network_cidr" {
  description = "The IPv4 range every range in this network is carved from."
  value       = var.network_cidr
}

################################################################################
# Primary-region subnetwork
################################################################################

output "subnetwork_id" {
  description = "The ID of the primary region's subnetwork."
  value       = google_compute_subnetwork.this[var.region].id
}

output "subnetwork_name" {
  description = "The name of the primary region's subnetwork."
  value       = google_compute_subnetwork.this[var.region].name
}

output "subnetwork_self_link" {
  description = "The self link of the primary region's subnetwork."
  value       = google_compute_subnetwork.this[var.region].self_link
}

output "subnetwork_cidr" {
  description = "The primary IPv4 range of the primary region's subnetwork."
  value       = google_compute_subnetwork.this[var.region].ip_cidr_range
}

################################################################################
# Subnetworks per region
################################################################################

output "subnetwork_ids" {
  description = "Map of region to subnetwork ID."
  value       = { for region, subnet in google_compute_subnetwork.this : region => subnet.id }
}

output "subnetwork_names" {
  description = "Map of region to subnetwork name."
  value       = { for region, subnet in google_compute_subnetwork.this : region => subnet.name }
}

output "subnetwork_self_links" {
  description = "Map of region to subnetwork self link."
  value       = { for region, subnet in google_compute_subnetwork.this : region => subnet.self_link }
}

output "subnetwork_cidrs" {
  description = "Map of region to the subnetwork's primary IPv4 range."
  value       = { for region, subnet in google_compute_subnetwork.this : region => subnet.ip_cidr_range }
}

################################################################################
# GKE secondary ranges
################################################################################

output "pods_secondary_range_name" {
  description = "Name of the GKE pods secondary range on every subnetwork (null when secondary ranges are disabled)."
  value       = var.subnetwork_secondary_ranges_enabled ? local.pods_secondary_range_name : null
}

output "services_secondary_range_name" {
  description = "Name of the GKE services secondary range on every subnetwork (null when secondary ranges are disabled)."
  value       = var.subnetwork_secondary_ranges_enabled ? local.services_secondary_range_name : null
}

output "pods_secondary_range_cidrs" {
  description = "Map of region to the GKE pods secondary range (empty when secondary ranges are disabled)."
  value       = var.subnetwork_secondary_ranges_enabled ? { for region in local.regions : region => local.region_ranges[region].pods } : {}
}

output "services_secondary_range_cidrs" {
  description = "Map of region to the GKE services secondary range (empty when secondary ranges are disabled)."
  value       = var.subnetwork_secondary_ranges_enabled ? { for region in local.regions : region => local.region_ranges[region].services } : {}
}

################################################################################
# Proxy-only subnetworks
################################################################################

output "proxy_only_subnetwork_ids" {
  description = "Map of region to proxy-only subnetwork ID (empty when not created)."
  value       = { for region, subnet in google_compute_subnetwork.proxy_only : region => subnet.id }
}

output "proxy_only_subnetwork_cidrs" {
  description = "Map of region to proxy-only subnetwork range (empty when not created). Backends must allow ingress from these ranges."
  value       = { for region, subnet in google_compute_subnetwork.proxy_only : region => subnet.ip_cidr_range }
}

################################################################################
# Cloud NAT
################################################################################

output "nat_router_names" {
  description = "Map of region to Cloud Router name (empty when Cloud NAT is disabled)."
  value       = { for region, router in google_compute_router.this : region => router.name }
}

output "nat_names" {
  description = "Map of region to Cloud NAT gateway name (empty when Cloud NAT is disabled)."
  value       = { for region, nat in google_compute_router_nat.this : region => nat.name }
}

output "nat_ip_addresses" {
  description = "Map of region to the static external IP addresses created by this module for Cloud NAT. Regions that use supplied addresses or automatic allocation are not listed."
  value = {
    for region in local.nat_regions : region => [
      for key, address in local.nat_reserved_addresses : google_compute_address.nat[key].address if address.region == region
    ] if !contains(keys(var.nat_ip_self_links), region) && var.nat_static_ip_count > 0
  }
}

output "nat_ip_self_links" {
  description = "Map of region to the self links of the addresses Cloud NAT uses. Empty for regions with automatic allocation."
  value       = { for region, links in local.nat_ip_self_links : region => links if length(links) > 0 }
}

################################################################################
# Private Service Access
################################################################################

output "private_service_access_range_name" {
  description = "Name of the Private Service Access allocated range. Pass it as allocated_ip_range to Cloud SQL, AlloyDB, or Memorystore (null when disabled)."
  value       = var.private_service_access_enabled ? google_compute_global_address.private_service_access[0].name : null
}

output "private_service_access_cidr" {
  description = "The Private Service Access range (null when disabled)."
  value       = var.private_service_access_enabled ? local.private_service_access_cidr : null
}

output "private_service_access_connection_id" {
  description = "ID of the service networking connection. Depend on it so database instances are created after the connection (null when disabled)."
  value       = var.private_service_access_enabled ? google_service_networking_connection.private_service_access[0].id : null
}

################################################################################
# Firewall & Peering
################################################################################

output "firewall_rule_names" {
  description = "Map of firewall_rules keys to the created firewall rule names."
  value       = { for key, rule in google_compute_firewall.this : key => rule.name }
}

output "network_peering_states" {
  description = "Map of network_peerings keys to their state. A peering stays INACTIVE until the peer network creates the matching peering."
  value       = { for key, peering in google_compute_network_peering.this : key => peering.state }
}
