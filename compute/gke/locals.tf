################################################################################
# Local Values
################################################################################

locals {
  default_labels = {
    managed_by = "terraform"
    module     = "compute-gke"
  }

  # GCP label keys and values allow only lowercase letters, digits, "_" and
  # "-", up to 63 characters, and keys must start with a letter, so Ravion's
  # tags (ProjectGivenId, ...) are normalized rather than rejected. Keys that
  # normalize to the same label (Owner and owner) are grouped first so they
  # cannot fail the map with a duplicate key; the last in key order wins.
  label_values_by_key = {
    for key, value in merge(local.default_labels, var.labels) :
    substr(join("", [can(regex("^[a-z]", lower(key))) ? "" : "x_", replace(lower(key), "/[^a-z0-9_-]/", "_")]), 0, 63) => substr(replace(lower(value), "/[^a-z0-9_-]/", "_"), 0, 63)...
  }
  labels = { for key, values in local.label_values_by_key : key => values[length(values) - 1] }

  # Service account IDs are 6-30 characters and unique per project. A hash of
  # the full name and region keeps clusters that share a long prefix, or the
  # same name in two regions, from colliding after the cut.
  node_service_account_id    = "${trimsuffix(substr(var.name, 0, 17), "-")}-${substr(sha256("${var.name}/${var.region}"), 0, 6)}-nodes"
  node_service_account_email = var.node_service_account_creation_enabled ? google_service_account.nodes[0].email : var.node_service_account_email

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
