################################################################################
# Cluster access
#
# GKE authorizes Kubernetes API requests with project IAM roles (and in-cluster
# RBAC on top), so access is granted on the project rather than on the
# cluster. A project grant has one owner: if two stacks managed the same
# member and role, destroying either would revoke it for both. That is why the
# Ravion runner's roles/container.admin is left to Ravion's GCP setup
# (runner_sa_roles), which owns the runner's other project roles, and why
# access_members should not repeat a grant another stack manages.
################################################################################

resource "google_project_iam_member" "access" {
  for_each = var.access_members

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
