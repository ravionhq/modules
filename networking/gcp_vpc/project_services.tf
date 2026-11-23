################################################################################
# Project services
################################################################################

# The APIs this network needs. disable_on_destroy is false because other
# modules and workloads in the project use the same APIs.
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  count = var.private_service_access_enabled ? 1 : 0

  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}
