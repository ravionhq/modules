locals {
  ################################################################################
  # Labels
  ################################################################################

  # GCP label keys and values allow only lowercase letters, numbers, hyphens,
  # and underscores, up to 63 characters.
  default_labels = {
    managed-by = "terraform"
    module     = "networking-gcp-vpc"
  }
  labels = {
    for key, value in merge(local.default_labels, var.labels) :
    substr(replace(lower(key), "/[^a-z0-9_-]/", "-"), 0, 63) => substr(replace(lower(value), "/[^a-z0-9_-]/", "-"), 0, 63)
  }

  ################################################################################
  # Address plan
  ################################################################################

  # network_cidr is split into 8 equal blocks. Block N belongs to the Nth
  # region (primary first, then additional_regions in order); block 7 holds the
  # Private Service Access range. Within a region block, the first half is the
  # GKE pods range and the second half holds the subnetwork, GKE services, and
  # proxy-only ranges. With a /12 network_cidr:
  #   region block /15 -> pods /16, subnetwork /20, services /20, proxy-only /23
  #   Private Service Access /16
  regions = concat([var.region], var.additional_regions)

  region_ranges = {
    for index, region in local.regions : region => {
      index       = index
      primary     = cidrsubnet(cidrsubnet(cidrsubnet(var.network_cidr, 3, index), 1, 1), 4, 0)
      services    = cidrsubnet(cidrsubnet(cidrsubnet(var.network_cidr, 3, index), 1, 1), 4, 1)
      proxy_only  = cidrsubnet(cidrsubnet(cidrsubnet(var.network_cidr, 3, index), 1, 1), 7, 16)
      pods        = cidrsubnet(cidrsubnet(var.network_cidr, 3, index), 1, 0)
      is_primary  = index == 0
      subnet_name = "${var.name}-${region}"
    }
  }

  private_service_access_cidr = cidrsubnet(cidrsubnet(var.network_cidr, 3, 7), 1, 0)

  pods_secondary_range_name     = "pods"
  services_secondary_range_name = "services"

  # Every range in this network, used by the optional allow-internal rule.
  internal_ranges = concat(
    [for region in local.regions : local.region_ranges[region].primary],
    var.subnetwork_secondary_ranges_enabled ? flatten([for region in local.regions : [local.region_ranges[region].pods, local.region_ranges[region].services]]) : [],
    var.proxy_only_subnetwork_creation_enabled ? [for region in local.regions : local.region_ranges[region].proxy_only] : [],
  )

  ################################################################################
  # Cloud NAT
  ################################################################################

  nat_regions = var.nat_enabled ? toset(local.regions) : toset([])

  # Addresses the module reserves itself: nat_static_ip_count per region,
  # except regions that supply their own addresses.
  nat_reserved_addresses = {
    for item in flatten([
      for region in local.nat_regions : [
        for index in range(var.nat_static_ip_count) : {
          key    = "${region}-${index}"
          region = region
          name   = "${var.name}-nat-${region}-${index}"
        }
      ] if !contains(keys(var.nat_ip_self_links), region)
    ]) : item.key => item
  }

  nat_ip_self_links = {
    for region in local.nat_regions : region => (
      contains(keys(var.nat_ip_self_links), region)
      ? var.nat_ip_self_links[region]
      : [for key, address in local.nat_reserved_addresses : google_compute_address.nat[key].self_link if address.region == region]
    )
  }
}
