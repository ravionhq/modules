################################################################################
# Workload Identity
#
# The workload's Google identity, the GKE analogue of an EKS Pod Identity role:
# a Google service account owned by this stack, which the release's Kubernetes
# service account impersonates through Workload Identity Federation for GKE.
# The chart annotates the Kubernetes service account with
# iam.gke.io/gcp-service-account = the email output, and the GKE metadata
# server hands the pods short-lived credentials for it. No key is created.
#
# Roles are not granted to the Kubernetes service account's own principal:
# every cluster in a project shares one Workload Identity pool, so the same
# namespace and service account name is the same principal in every cluster.
# Two stacks (another cluster, or another environment reusing the namespace
# and release name) would own the same project IAM member, and destroying one
# would revoke the other's access. Every grant here names this stack's own
# Google service account instead, the way compute/gke/addons does for ESO.
################################################################################

locals {
  workload_identity_enabled              = length(var.workload_identity_project_roles) > 0
  workload_identity_pool                 = coalesce(var.workload_identity_pool, "${var.project_id}.svc.id.goog")
  workload_identity_service_account_name = coalesce(var.workload_identity_service_account_name, var.release_name, var.name)

  # IDs are 6-30 characters, start with a letter and are unique per project: a
  # prefix of the workload name plus a hash of where the Kubernetes service
  # account lives. Two stacks only get the same ID when they target the same
  # service account in the same cluster, which is already the same release.
  workload_identity_google_service_account_prefix = can(regex("^[a-z]", var.name)) ? var.name : "w${var.name}"
  workload_identity_google_service_account_id = format(
    "%s-%s",
    trimsuffix(substr(local.workload_identity_google_service_account_prefix, 0, 23), "-"),
    substr(sha256(join("/", [
      coalesce(var.cluster_name, "-"),
      var.region,
      coalesce(var.release_namespace, "-"),
      local.workload_identity_service_account_name,
    ])), 0, 6),
  )
}

resource "google_service_account" "workload_identity" {
  count = local.workload_identity_enabled ? 1 : 0

  project      = var.project_id
  account_id   = local.workload_identity_google_service_account_id
  display_name = "GKE workload ${var.name}"
  description  = "Workload Identity for ${coalesce(var.release_namespace, "-")}/${local.workload_identity_service_account_name} on GKE cluster ${coalesce(var.cluster_name, "-")}."
}

resource "google_service_account_iam_member" "workload_identity" {
  count = local.workload_identity_enabled ? 1 : 0

  service_account_id = google_service_account.workload_identity[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_identity_pool}[${var.release_namespace}/${local.workload_identity_service_account_name}]"
}

resource "google_project_iam_member" "workload_identity" {
  for_each = local.workload_identity_enabled ? toset(var.workload_identity_project_roles) : toset([])

  project = var.project_id
  role    = each.value
  member  = google_service_account.workload_identity[0].member
}
