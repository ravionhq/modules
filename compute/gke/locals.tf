################################################################################
# Local Values
################################################################################

locals {
  default_labels = {
    managed_by = "terraform"
    module     = "compute-gke"
  }

  # GCP label keys and values allow only lowercase letters, digits, "_" and
  # "-", up to 63 characters, so Ravion's tags (ProjectGivenId, ...) are
  # normalized rather than rejected.
  labels = {
    for key, value in merge(local.default_labels, var.labels) :
    substr(replace(lower(key), "/[^a-z0-9_-]/", "_"), 0, 63) => substr(replace(lower(value), "/[^a-z0-9_-]/", "_"), 0, 63)
  }

  # Service account IDs are 6-30 characters, so long cluster names are cut.
  node_service_account_id    = "${trimsuffix(substr(var.name, 0, 24), "-")}-nodes"
  node_service_account_email = var.node_service_account_creation_enabled ? google_service_account.nodes[0].email : var.node_service_account_email

  ravion_runner_service_account_email = coalesce(var.ravion_runner_service_account_email, "ravion-runner@${var.project_id}.iam.gserviceaccount.com")

  # The system pool is a node pool like any other, keyed "system" and
  # labelled role=system so the GKE Add-ons module can prefer it.
  system_node_labels = { role = "system" }

  node_pools = merge(
    { for key, pool in var.node_pools : key => pool },
    {
      system = merge(var.system_node_pool, {
        labels = local.system_node_labels
      })
    },
  )
}
