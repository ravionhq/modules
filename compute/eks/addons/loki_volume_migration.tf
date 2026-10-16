################################################################################
# Loki volume migration
#
# Loki runs as a StatefulSet, and a StatefulSet's volume templates cannot be
# changed in place: switching an existing Loki from an emptyDir to a
# PersistentVolumeClaim (the default whenever a StorageClass exists) fails the
# Helm upgrade. This release runs a kubectl Job that deletes the StatefulSet
# with --cascade=orphan, leaving its pod running, just before the Loki release
# is upgraded; the upgrade then creates the StatefulSet with the new volume
# layout, adopts the pod and replaces it.
#
# The Job runs whenever this release changes, and every input of this release is
# part of local.loki_volume_layout, which Loki carries as a pod annotation. So
# whenever the Job deletes the StatefulSet, the Loki release changes too and
# recreates it in the same apply (it depends on this one).
################################################################################

locals {
  loki_volume_migration_values = {
    statefulSet = {
      name      = local.loki_release_name
      namespace = local.logs_namespace
    }
    persistent = local.loki_config.persistence_enabled
    image = {
      repository = local.kubectl_image_repository
      tag        = local.kubectl_image_tag
    }
  }

  loki_volume_migration_chart_version = yamldecode(file("${path.module}/charts/statefulset-volume-migration/Chart.yaml")).version

  loki_volume_layout = "${local.loki_config.persistence_enabled ? "persistent" : "ephemeral"}-${substr(sha256(jsonencode({
    values  = local.loki_volume_migration_values
    version = local.loki_volume_migration_chart_version
  })), 0, 12)}"
}

resource "helm_release" "loki_volume_migration" {
  count = local.loki_enabled ? 1 : 0

  name      = "${local.loki_release_name}-volume-migration"
  namespace = local.logs_namespace
  chart     = "${path.module}/charts/statefulset-volume-migration"
  # Pinned so a Chart.yaml bump shows in the plan (see lb_controller.tf).
  version          = yamldecode(file("${path.module}/charts/statefulset-volume-migration/Chart.yaml")).version
  create_namespace = true
  upgrade_install  = true

  values = [yamlencode(local.loki_volume_migration_values)]
}
