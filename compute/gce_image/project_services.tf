################################################################################
# Project services
################################################################################

# disable_on_destroy is false because other modules and workloads in the
# project use the same APIs.
resource "google_project_service" "this" {
  for_each = var.enable_project_services ? toset(["compute.googleapis.com", "iam.googleapis.com", "storage.googleapis.com"]) : toset([])

  service            = each.value
  disable_on_destroy = false
}
