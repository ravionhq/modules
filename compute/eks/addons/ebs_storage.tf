################################################################################
# EBS storage defaults
#
# Two cluster-wide defaults for EBS-backed volumes, installed as one local
# chart once the EBS CSI driver is in place:
#
#   - A `gp3` StorageClass, encrypted, allowing volume expansion, and marked as
#     the cluster default. EKS stopped creating a default class in 1.30, so
#     without it a chart that names no class leaves its volumes Pending.
#
#   - Online growth of StatefulSet volumes. Kubernetes rejects any change to a
#     StatefulSet's volumeClaimTemplates, so raising a chart's volume size
#     fails the deploy. A MutatingAdmissionPolicy lets an update through when
#     the only template change is a larger storage request, recording the
#     requested sizes on the StatefulSet, and a resizer grows each existing
#     PersistentVolumeClaim to match. The EBS CSI driver expands the volume and
#     its filesystem while the pod keeps running: no restart, no data copied.
#     MutatingAdmissionPolicy is GA from Kubernetes 1.36, so older clusters get
#     the StorageClass only.
################################################################################

locals {
  # Mocked or unexpected version strings read as 0 and turn the feature off
  # rather than failing the plan.
  cluster_kubernetes_minor_version = try(tonumber(regex("^1\\.([0-9]+)", data.aws_eks_cluster.this.version)[0]), 0)

  ebs_default_storage_class_enabled    = var.ebs_csi_driver_enabled && var.ebs_default_storage_class_enabled
  statefulset_volume_expansion_enabled = var.ebs_csi_driver_enabled && var.statefulset_volume_expansion_enabled && local.cluster_kubernetes_minor_version >= 36

  busybox_image_repository = regex("^(.*):([^:/]+)$", var.busybox_image)[0]
  busybox_image_tag        = regex("^(.*):([^:/]+)$", var.busybox_image)[1]
}

resource "helm_release" "ebs_storage" {
  count = local.ebs_default_storage_class_enabled || local.statefulset_volume_expansion_enabled ? 1 : 0

  name            = "ebs-storage"
  namespace       = "kube-system"
  chart           = "${path.module}/charts/ebs-storage"
  upgrade_install = true

  values = [yamlencode({
    storageClass = {
      enabled = local.ebs_default_storage_class_enabled
    }
    volumeExpansion = {
      enabled = local.statefulset_volume_expansion_enabled
    }
    image = {
      repository = local.kubectl_image_repository
      tag        = local.kubectl_image_tag
    }
    busyboxImage = {
      repository = local.busybox_image_repository
      tag        = local.busybox_image_tag
    }
  })]

  depends_on = [aws_eks_addon.ebs_csi]
}

check "statefulset_volume_expansion_supported" {
  assert {
    condition     = !(var.ebs_csi_driver_enabled && var.statefulset_volume_expansion_enabled) || local.statefulset_volume_expansion_enabled
    error_message = "statefulset_volume_expansion_enabled needs Kubernetes 1.36 or newer (MutatingAdmissionPolicy); cluster ${var.cluster_name} runs ${data.aws_eks_cluster.this.version}, so StatefulSet volume growth is not installed. Upgrade the cluster to enable it."
  }
}
