################################################################################
# Required APIs
#
# Left enabled on destroy: other clusters and tools in the project may rely on
# the Kubernetes Engine API.
################################################################################

resource "google_project_service" "container" {
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}
