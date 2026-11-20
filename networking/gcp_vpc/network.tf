################################################################################
# VPC network
################################################################################

resource "google_compute_network" "this" {
  name                            = var.name
  description                     = "Managed by Terraform (networking/gcp_vpc)."
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = false

  depends_on = [google_project_service.compute]
}
