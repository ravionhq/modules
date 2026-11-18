################################################################################
# Data Sources
################################################################################

# A regional internal Gateway forwards requests from the region's proxy-only
# subnet, so the workload's ingress allow-list has to admit that range, and the
# Gateway cannot be programmed without one.
data "google_compute_subnetworks" "proxy_only" {
  count = var.load_balancer_scheme == "internal" ? 1 : 0

  project = var.project_id
  region  = var.region
  filter  = "purpose = \"REGIONAL_MANAGED_PROXY\""
}
