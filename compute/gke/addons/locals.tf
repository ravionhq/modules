################################################################################
# Local Values
################################################################################

locals {
  kubernetes_host = var.use_dns_endpoint ? "https://${data.google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}" : "https://${data.google_container_cluster.this.endpoint}"

  workload_identity_pool = "${var.project_id}.svc.id.goog"

  # Every cluster in a project shares one Workload Identity pool, so the same
  # namespace and service account name is the same IAM principal in each. The
  # controller therefore acts as a Google service account of its own cluster,
  # and every grant names that account, so no two stacks own the same grant.
  # IDs are 6-30 characters and unique per project: a prefix plus a hash of
  # the cluster name and region.
  eso_google_service_account_id = "${trimsuffix(substr(var.cluster_name, 0, 19), "-")}-${substr(sha256("${var.cluster_name}/${var.region}"), 0, 6)}-eso"

  eso_secret_names = toset([
    for secret in var.eso_secret_ids :
    startswith(secret, "projects/") ? secret : "projects/${var.project_id}/secrets/${secret}"
  ])

  eso_allowed_namespaces = sort(distinct(var.eso_allowed_namespaces))
}
