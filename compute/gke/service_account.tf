################################################################################
# Node service account
#
# Nodes run as a dedicated account instead of the Compute Engine default
# account, which has roles/editor on the project. Workloads get their own
# Google identities through Workload Identity, never the node's.
################################################################################

resource "google_service_account" "nodes" {
  count = var.node_service_account_creation_enabled ? 1 : 0

  project      = var.project_id
  account_id   = local.node_service_account_id
  display_name = "GKE nodes for ${var.name}"
}

# roles/container.defaultNodeServiceAccount covers what nodes need to run:
# writing logs and metrics and reading GKE's own images. Artifact Registry
# read lets nodes pull the project's private images.
resource "google_project_iam_member" "nodes" {
  for_each = var.node_service_account_creation_enabled ? toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes[0].email}"
}
