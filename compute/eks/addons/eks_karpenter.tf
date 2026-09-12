################################################################################
# Karpenter AWS-side resources (optional add-on)
#
# Everything Karpenter needs outside the cluster: controller IAM role and Pod
# Identity association, node IAM role + instance profile + EKS access entry,
# SQS interruption queue, and EventBridge interruption rules. The Helm-side
# install lives in karpenter.tf.
################################################################################

module "karpenter" {
  source = "./modules/eks_karpenter"
  count  = var.karpenter_enabled ? 1 : 0

  # Resolved at the root so managed policy ARNs stay known at plan time.
  partition = data.aws_partition.current.partition

  cluster_name = var.cluster_name

  controller_namespace       = var.karpenter_controller_namespace
  controller_service_account = var.karpenter_controller_service_account

  node_role_additional_managed_policy_arns = var.karpenter_node_role_additional_managed_policy_arns

  interruption_queue_name                      = var.karpenter_interruption_queue_name
  interruption_queue_message_retention_seconds = var.karpenter_interruption_queue_message_retention_seconds

  tags = local.tags
}
