################################################################################
# Data Sources
################################################################################

# Endpoints and CA of the existing cluster the add-ons are installed onto.
data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

# Access token of the identity running Terraform, used by the Helm provider.
data "google_client_config" "current" {}
