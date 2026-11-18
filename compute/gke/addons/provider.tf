provider "google" {
  project = var.project_id
  region  = var.region
}

# Authenticates against the existing cluster with the access token of the
# identity running Terraform (on a Ravion runner, its attached service account,
# which the compute/gke stack grants roles/container.admin). Nothing is stored
# in state and no gcloud plugin is needed.
#
# By default the DNS-based control plane endpoint is used: it is reachable from
# anywhere with IAM authorization and serves a publicly trusted certificate, so
# the runner needs no network path into the VPC. With use_dns_endpoint = false
# the IP endpoint and its cluster CA are used instead, and the runner must reach
# it (from inside the VPC, or through an authorized network).
provider "helm" {
  kubernetes = {
    host                   = local.kubernetes_host
    cluster_ca_certificate = var.use_dns_endpoint ? null : base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
  }
}
