################################################################################
# Gateway address
#
# The web chart renders a GKE Gateway for the workload and pins it to this
# reserved address (spec.addresses, type NamedAddress), so the address, and
# the URL built from it, are known when the stack applies, before any deploy,
# and survive the Gateway being recreated. A null load_balancer_scheme is a
# cluster-only service: no address and no Gateway.
#
#   external: a global external Application Load Balancer
#             (gatewayClassName gke-l7-global-external-managed), global IP.
#   internal: a regional internal Application Load Balancer
#             (gatewayClassName gke-l7-rilb), an internal IP in the cluster's
#             subnetwork. Needs a proxy-only subnet in the region.
################################################################################

locals {
  load_balancer_enabled = var.load_balancer_scheme != null

  # Address names must start with a letter; release names may start with a digit.
  gateway_address_name = "gw-${var.name}"

  gateway_address = (
    var.load_balancer_scheme == "external" ? one(google_compute_global_address.gateway[*].address) :
    var.load_balancer_scheme == "internal" ? one(google_compute_address.gateway[*].address) : null
  )

  gateway_https_enabled = var.gateway_certificate_map_name != null || length(var.gateway_pre_shared_certificate_names) > 0

  # The URL prefers the first concrete hostname: an HTTPRoute scoped to
  # hostnames does not match a request to the bare Gateway address.
  load_balancer_hostnames = [for hostname in var.hostnames : hostname if !strcontains(hostname, "*")]
  load_balancer_host      = local.load_balancer_enabled ? (length(local.load_balancer_hostnames) > 0 ? local.load_balancer_hostnames[0] : local.gateway_address) : null
  load_balancer_url       = local.load_balancer_host != null ? "${local.gateway_https_enabled ? "https" : "http"}://${local.load_balancer_host}" : null

  # Every Application Load Balancer health-checks from Google's health check
  # ranges, and a global external one also forwards requests from them. A
  # regional internal one forwards from the region's proxy-only subnet. The
  # chart's ingress allow-list admits these so the load balancer still reaches
  # the pods.
  # https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  google_health_check_cidr_blocks = ["130.211.0.0/22", "35.191.0.0/16"]
  # Networks compare by their project/name path: self links may differ in API
  # version.
  gateway_network = try(regex("projects/[^/]+/global/networks/[^/]+$", data.google_compute_subnetwork.gateway[0].network), null)
  proxy_only_cidr_blocks = [
    for subnet in try(data.google_compute_subnetworks.proxy_only[0].subnetworks, []) : subnet.ip_cidr_range
    if try(regex("projects/[^/]+/global/networks/[^/]+$", subnet.network_self_link), null) == local.gateway_network
  ]
  load_balancer_source_cidr_blocks = local.load_balancer_enabled ? sort(distinct(concat(
    local.google_health_check_cidr_blocks,
    local.proxy_only_cidr_blocks,
  ))) : []
}

resource "google_compute_global_address" "gateway" {
  count = var.load_balancer_scheme == "external" ? 1 : 0

  project     = var.project_id
  name        = local.gateway_address_name
  description = "Gateway address for ${var.name}"
  labels      = local.labels
}

resource "google_compute_address" "gateway" {
  count = var.load_balancer_scheme == "internal" ? 1 : 0

  project      = var.project_id
  region       = var.region
  name         = local.gateway_address_name
  description  = "Gateway address for ${var.name}"
  address_type = "INTERNAL"
  subnetwork   = var.subnetwork
  purpose      = "SHARED_LOADBALANCER_VIP"
  labels       = local.labels

  lifecycle {
    precondition {
      condition     = var.subnetwork != null
      error_message = "An internal load balancer needs subnetwork: its address is reserved in the cluster's subnetwork."
    }
    precondition {
      condition     = length(local.proxy_only_cidr_blocks) > 0
      error_message = "An internal load balancer needs a proxy-only subnet (purpose REGIONAL_MANAGED_PROXY) in ${var.region} in the VPC network of ${coalesce(var.subnetwork, "the subnetwork")}. Create one in the cluster's VPC network first."
    }
  }
}
