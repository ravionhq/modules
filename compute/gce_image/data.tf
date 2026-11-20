data "google_compute_zones" "available" {
  region = var.region
  status = "UP"
}

# Looked up so a missing network or subnetwork fails the apply, not a build.
data "google_compute_network" "this" {
  count = var.subnetwork == null ? 1 : 0

  name    = var.network
  project = local.network_project_id
}

data "google_compute_subnetwork" "this" {
  count = var.subnetwork == null ? 0 : 1

  name    = var.subnetwork
  region  = var.region
  project = local.network_project_id
}
