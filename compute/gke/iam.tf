################################################################################
# Cluster access
#
# GKE authorizes Kubernetes API requests with project IAM roles (and in-cluster
# RBAC on top), so access is granted on the project rather than on the
# cluster.
################################################################################

# Lets Ravion pipelines, including the GKE Add-ons module, manage every
# Kubernetes object, including the RBAC objects and CRDs add-on charts create.
resource "google_project_iam_member" "ravion_runner" {
  count = var.ravion_runner_cluster_admin_enabled ? 1 : 0

  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${local.ravion_runner_service_account_email}"
}

resource "google_project_iam_member" "access" {
  for_each = var.access_members

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
