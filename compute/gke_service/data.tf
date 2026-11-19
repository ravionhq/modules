################################################################################
# Data Sources
################################################################################

# A regional internal Gateway forwards requests from the region's proxy-only
# subnet, so the workload's ingress allow-list has to admit that range, and the
# Gateway cannot be programmed without one.
# Only the proxy-only subnet of the network the Gateway address lives in counts
# (see gateway_address.tf): another VPC's subnet in the same region neither
# lets the Gateway be programmed nor forwards its requests.
data "google_compute_subnetwork" "gateway" {
  count = var.load_balancer_scheme == "internal" && var.subnetwork != null ? 1 : 0

  project = var.project_id
  region  = var.region
  name    = basename(var.subnetwork)
}

data "google_compute_subnetworks" "proxy_only" {
  count = var.load_balancer_scheme == "internal" ? 1 : 0

  project = var.project_id
  region  = var.region
  filter  = "purpose = \"REGIONAL_MANAGED_PROXY\""
}
