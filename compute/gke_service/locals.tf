################################################################################
# Local Values
################################################################################

locals {
  default_labels = {
    managed_by = "terraform"
    module     = "compute-gke_service"
  }

  # GCP label keys and values allow only lowercase letters, digits, "_" and
  # "-", up to 63 characters, so Ravion's tags (ProjectGivenId, ...) are
  # normalized rather than rejected. Same rule as compute/gke.
  labels = {
    for key, value in merge(local.default_labels, var.labels) :
    substr(replace(lower(key), "/[^a-z0-9_-]/", "_"), 0, 63) => substr(replace(lower(value), "/[^a-z0-9_-]/", "_"), 0, 63)
  }

  # Addresses other workloads use to reach this service. The in-cluster host is
  # the ClusterIP Service the rvn-gke-web chart names after the release, in the
  # release namespace, so it is knowable before the first deploy creates it.
  # Worker and cron render no Service and leave kubernetes_service_enabled off.
  service_host = var.kubernetes_service_enabled && var.release_name != null && var.release_namespace != null ? "${var.release_name}.${var.release_namespace}.svc.cluster.local" : null
  service_url  = local.service_host != null ? "http://${local.service_host}:${var.container_port}" : null
}
