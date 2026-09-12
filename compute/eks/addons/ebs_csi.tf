################################################################################
# EBS CSI Driver (optional add-on)
#
# Native EKS add-on installed via the AWS API. Wired with a Pod Identity
# association rather than IRSA. AmazonEBSCSIDriverPolicy is the AWS-managed
# policy maintained for this component.
################################################################################

module "ebs_csi_role" {
  count = var.ebs_csi_driver_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-ebs-csi"
  description = "EBS CSI driver Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
  ]

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count = var.ebs_csi_driver_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = module.ebs_csi_role[0].role_arn

  tags = local.tags
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.ebs_csi_driver_enabled ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_addon_version
  configuration_values        = var.ebs_csi_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags

  depends_on = [aws_eks_pod_identity_association.ebs_csi]
}
