################################################################################
# Loki volume migration
#
# Loki runs as a StatefulSet, and a StatefulSet's volume templates cannot be
# changed in place: switching an existing Loki from an emptyDir to a
# PersistentVolumeClaim (the default whenever a StorageClass exists) fails the
# Helm upgrade. This release runs a Job just before the Loki release is
# upgraded. When the layout changes, the Job flushes Loki to S3 and deletes the
# StatefulSet together with its pod; the upgrade then creates both on the new
# volume. Loki is down from the delete until the new pod is ready, about a
# minute. It never orphans the pod: a recreated StatefulSet that adopts a pod
# without its claim cannot add the claim in place and never replaces the pod
# (what chart 0.1.0 did; the Job also replaces pods it left that way).
#
# The Job runs whenever this release changes, and every input of this release is
# part of local.loki_volume_layout, which Loki carries as a pod annotation. So
# whenever the Job deletes the StatefulSet, the Loki release changes too and
# recreates it in the same apply (it depends on this one).
################################################################################

locals {
  # The Job's Role names each pod it may read, so it must cover the most
  # replicas any loki_helm_values document asks for, fixed or autoscaled. The
  # floor matches the chart's default.
  loki_volume_migration_max_replicas = max(3, flatten([
    for doc in var.loki_helm_values : [
      try(tonumber(yamldecode(doc).singleBinary.replicas), 0),
      try(tonumber(yamldecode(doc).singleBinary.autoscaling.maxReplicas), 0),
    ]
  ])...)

  loki_volume_migration_values = {
    statefulSet = {
      name        = local.loki_release_name
      namespace   = local.logs_namespace
      maxReplicas = local.loki_volume_migration_max_replicas
    }
    persistent = local.loki_config.persistence_enabled
    flushUrl   = "http://${local.loki_service_host}:3100/flush"
    image = {
      repository = local.kubectl_image_repository
      tag        = local.kubectl_image_tag
    }
    busyboxImage = {
      repository = local.busybox_image_repository
      tag        = local.busybox_image_tag
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
  # The Job's flush (up to 2m) and pod deletion (up to 4m) run inside this.
  timeout = 600

  values = [yamlencode(local.loki_volume_migration_values)]
}
