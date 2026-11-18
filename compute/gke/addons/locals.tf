################################################################################
# Local Values
################################################################################

locals {
  kubernetes_host = var.use_dns_endpoint ? "https://${data.google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}" : "https://${data.google_container_cluster.this.endpoint}"

  workload_identity_pool = "${var.project_id}.svc.id.goog"

  # Workload Identity Federation for GKE lets IAM name a Kubernetes service
  # account directly, so no Google service account or impersonation binding
  # is needed.
  eso_principal = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${local.workload_identity_pool}/subject/ns/${var.eso_namespace}/sa/${var.eso_service_account}"

  eso_secret_names = toset([
    for secret in var.eso_secret_ids :
    startswith(secret, "projects/") ? secret : "projects/${var.project_id}/secrets/${secret}"
  ])

  eso_allowed_namespaces = sort(distinct(var.eso_allowed_namespaces))
}
